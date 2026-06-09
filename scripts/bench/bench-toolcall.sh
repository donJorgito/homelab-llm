#!/usr/bin/env bash
# bench-toolcall.sh — classify tool-use behaviour per model.
#
# For each MODEL passed as argument, POST a /api/chat request that defines
# write_file + read_file as tools and asks the model to "Write hello.py and
# read it back". Categorise the response:
#
#   PASS — .message.tool_calls[] non-empty (native structured tool-use).
#   PARTIAL — .message.content contains JSON-shaped tool calls
#             (works with aider --edit-format whole, fails with OpenCode).
#   FAIL  — neither (no usable tool intent).
#
# Output is a small table.
set -euo pipefail
IFS=$'\n\t'

# bench/* lives one level deeper than scripts/, so go up two levels.
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=../lib/common.sh
source "${REPO_ROOT}/scripts/lib/common.sh"

if [[ -f "${REPO_ROOT}/.env" ]]; then
    # shellcheck disable=SC1091
    source "${REPO_ROOT}/.env"
fi

# Defaults.
OLLAMA_PORT="${OLLAMA_PORT:-11434}"
OLLAMA_BASE_URL="${OLLAMA_BASE_URL:-http://${OLLAMA_HOST:-127.0.0.1}:${OLLAMA_PORT}}"

usage() {
    cat <<EOF
Usage: $(basename "$0") MODEL [MODEL ...] [--help]

Probe each MODEL for native tool-use against the Ollama /api/chat endpoint.

Verdicts:
  PASS     — model returned structured .message.tool_calls[]
  PARTIAL  — model returned JSON tool-call shape inside .message.content
             (compatible with aider whole/diff format; not with OpenCode)
  FAIL     — neither

Options:
  -h, --help  Show this help.

Env vars used:
  OLLAMA_BASE_URL  (default http://\${OLLAMA_HOST:-127.0.0.1}:\${OLLAMA_PORT})

Example:
  $(basename "$0") qwen2.5-coder:7b qwen2.5-coder:3b granite3.3:8b
EOF
}

MODELS=()
for arg in "$@"; do
    case "${arg}" in
        -h|--help) usage; exit 0 ;;
        --*)
            log_error "Unknown option: ${arg}"
            usage
            exit 2
            ;;
        *) MODELS+=("${arg}") ;;
    esac
done

if [[ ${#MODELS[@]} -eq 0 ]]; then
    log_error "No models provided."
    usage
    exit 2
fi

require_cmd curl jq

# Tool definitions sent to the model.
TOOLS_JSON='[
  {
    "type": "function",
    "function": {
      "name": "write_file",
      "description": "Write content to a file.",
      "parameters": {
        "type": "object",
        "properties": {
          "path":    {"type": "string", "description": "File path"},
          "content": {"type": "string", "description": "File content"}
        },
        "required": ["path", "content"]
      }
    }
  },
  {
    "type": "function",
    "function": {
      "name": "read_file",
      "description": "Read a file and return its content.",
      "parameters": {
        "type": "object",
        "properties": { "path": {"type": "string"} },
        "required": ["path"]
      }
    }
  }
]'

USER_PROMPT="Write a file hello.py containing print('hello world'), then read it back."

probe_model() {
    local model="$1"
    local body resp tool_calls_count content
    body="$(jq -n \
        --arg model "${model}" \
        --arg user "${USER_PROMPT}" \
        --argjson tools "${TOOLS_JSON}" '{
            model: $model,
            messages: [ { role: "user", content: $user } ],
            tools: $tools,
            stream: false
        }')"

    if ! resp="$(curl -fsS -X POST "${OLLAMA_BASE_URL}/api/chat" \
        -H 'Content-Type: application/json' \
        -d "${body}" 2>/dev/null)"; then
        printf 'ERROR\t-\tcurl failed (model unreachable or not pulled?)'
        return 0
    fi

    tool_calls_count="$(printf '%s' "${resp}" | jq '(.message.tool_calls // []) | length')"
    content="$(printf '%s' "${resp}" | jq -r '.message.content // ""')"

    if [[ "${tool_calls_count}" -gt 0 ]]; then
        printf 'PASS\t%s\tnative .message.tool_calls[]' "${tool_calls_count}"
        return 0
    fi

    # Heuristic: response contains JSON object(s) with both "name" and "arguments"
    # keys, even though they sit inside .message.content.
    if printf '%s' "${content}" | grep -Eq '"name"[[:space:]]*:[[:space:]]*"(write_file|read_file)"' \
       && printf '%s' "${content}" | grep -Eq '"arguments"[[:space:]]*:'; then
        printf 'PARTIAL\t0\tJSON tool calls embedded in .message.content'
        return 0
    fi

    printf 'FAIL\t0\tno tool intent detected'
}

log_step "tool-use probe"
log_info "Endpoint: ${OLLAMA_BASE_URL}/api/chat"

# Header.
printf '\n%-30s %-9s %-9s %s\n' "Model" "Verdict" "ToolCalls" "Notes"
printf '%s\n' "----------------------------------------------------------------------------"

for model in "${MODELS[@]}"; do
    line="$(probe_model "${model}")"
    verdict="$(printf '%s' "${line}" | awk -F'\t' '{print $1}')"
    tcc="$(printf '%s' "${line}"     | awk -F'\t' '{print $2}')"
    note="$(printf '%s' "${line}"    | awk -F'\t' '{print $3}')"
    case "${verdict}" in
        PASS)    color="${__C_GREEN}" ;;
        PARTIAL) color="${__C_YELLOW}" ;;
        FAIL)    color="${__C_RED}" ;;
        *)       color="${__C_RED}" ;;
    esac
    printf '%-30s %s%-9s%s %-9s %s\n' "${model}" "${color}" "${verdict}" "${__C_RESET}" "${tcc}" "${note}"
done

log_step "Legend"
cat <<EOF
  PASS     usable from any structured-tool client (OpenCode, aider --tool-use, etc.)
  PARTIAL  works only with text-parsing clients such as aider --edit-format whole
  FAIL     not usable for tool-driven workflows in current Ollama shim
EOF
