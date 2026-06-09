#!/usr/bin/env bash
# bench-perf.sh — measure tok/s, TTFT and total time for a model on Ollama.
#
# Sends 3 short coding prompts via /api/generate (non-streaming JSON), preceded
# by a 1-token warmup so the model is loaded into VRAM before we measure.
#
# Output is a small table per prompt + a final summary average.
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
DEFAULT_MODEL="${DEFAULT_MODEL:-qwen2.5-coder:7b}"
NUM_PREDICT="${NUM_PREDICT:-200}"

usage() {
    cat <<EOF
Usage: $(basename "$0") [MODEL] [--help]

Benchmark generation throughput (tok/s), time-to-first-token, and total time
for MODEL against the Ollama server at OLLAMA_BASE_URL.

Arguments:
  MODEL  Optional. Defaults to \${DEFAULT_MODEL} (currently ${DEFAULT_MODEL}).

Options:
  -h, --help  Show this help.

Env vars used:
  OLLAMA_BASE_URL  (default http://\${OLLAMA_HOST:-127.0.0.1}:\${OLLAMA_PORT})
  DEFAULT_MODEL    (default qwen2.5-coder:7b)
  NUM_PREDICT      (default 200) — tokens to generate per prompt
EOF
}

MODEL=""
for arg in "$@"; do
    case "${arg}" in
        -h|--help) usage; exit 0 ;;
        --*)
            log_error "Unknown option: ${arg}"
            usage
            exit 2
            ;;
        *)
            if [[ -z "${MODEL}" ]]; then
                MODEL="${arg}"
            else
                log_error "Too many positional arguments."
                usage
                exit 2
            fi
            ;;
    esac
done
MODEL="${MODEL:-${DEFAULT_MODEL}}"

require_cmd curl jq awk

# Three short coding prompts. Same shape used in the manual bench so results
# are comparable across runs.
PROMPTS=(
    "Write a Python function that returns the Fibonacci sequence up to n."
    "Refactor this snippet to use a list comprehension: result = []\\nfor x in xs:\\n    if x > 0:\\n        result.append(x*x)"
    "Explain in one paragraph the difference between a Python generator and an iterator."
)

api_generate() {
    # api_generate <prompt> <num_predict>
    local prompt="$1"
    local n="$2"
    local body
    body="$(jq -n --arg model "${MODEL}" --arg prompt "${prompt}" --argjson n "${n}" '{
        model: $model,
        prompt: $prompt,
        stream: false,
        options: { num_predict: $n }
    }')"
    curl -fsS -X POST "${OLLAMA_BASE_URL}/api/generate" \
        -H 'Content-Type: application/json' \
        -d "${body}"
}

log_step "Verify Ollama API"
HTTP_CODE="$(curl -fsS -o /dev/null -w '%{http_code}' "${OLLAMA_BASE_URL}/api/tags" || echo "000")"
if [[ "${HTTP_CODE}" != "200" ]]; then
    log_error "Ollama API returned HTTP ${HTTP_CODE} at ${OLLAMA_BASE_URL}/api/tags"
    exit 1
fi
log_info "Model under test: ${MODEL}"
log_info "num_predict per prompt: ${NUM_PREDICT}"

log_step "Warmup (1 token)"
api_generate "Hello" 1 >/dev/null
log_info "Warmup complete."

# Print table header.
printf '\n%-7s %-10s %-10s %-10s %-10s %s\n' "Prompt" "Eval(tok)" "TTFT(s)" "Gen(s)" "Total(s)" "tok/s"
printf '%s\n' "------------------------------------------------------------------------"

# Aggregates.
SUM_TOKS=0
SUM_TIME_NS=0
SUM_TPS_INT=0  # tok/s * 100, integer math.
COUNT=0

for i in "${!PROMPTS[@]}"; do
    idx=$((i + 1))
    prompt="${PROMPTS[$i]}"
    resp="$(api_generate "${prompt}" "${NUM_PREDICT}")"

    # Ollama /api/generate non-streaming response includes:
    #   eval_count, eval_duration (ns), prompt_eval_duration (ns), total_duration (ns).
    eval_count="$(printf '%s' "${resp}" | jq -r '.eval_count // 0')"
    eval_dur_ns="$(printf '%s' "${resp}" | jq -r '.eval_duration // 0')"
    prompt_dur_ns="$(printf '%s' "${resp}" | jq -r '.prompt_eval_duration // 0')"
    total_dur_ns="$(printf '%s' "${resp}" | jq -r '.total_duration // 0')"

    # Compute seconds + tok/s using awk (bash has no float arith).
    ttft_s="$(awk -v ns="${prompt_dur_ns}" 'BEGIN {printf "%.2f", ns/1e9}')"
    gen_s="$(awk  -v ns="${eval_dur_ns}"   'BEGIN {printf "%.2f", ns/1e9}')"
    total_s="$(awk -v ns="${total_dur_ns}" 'BEGIN {printf "%.2f", ns/1e9}')"
    tps="$(awk -v c="${eval_count}" -v ns="${eval_dur_ns}" 'BEGIN {
        if (ns <= 0) print "0.00"; else printf "%.2f", c/(ns/1e9)
    }')"

    printf '%-7s %-10s %-10s %-10s %-10s %s\n' "#${idx}" "${eval_count}" "${ttft_s}" "${gen_s}" "${total_s}" "${tps}"

    SUM_TOKS=$((SUM_TOKS + eval_count))
    SUM_TIME_NS=$((SUM_TIME_NS + total_dur_ns))
    # tok/s * 100 to keep awk-formatted value as an integer for averaging.
    tps_int="$(awk -v t="${tps}" 'BEGIN {printf "%d", t*100}')"
    SUM_TPS_INT=$((SUM_TPS_INT + tps_int))
    COUNT=$((COUNT + 1))
done

log_step "Summary"
if [[ "${COUNT}" -gt 0 ]]; then
    avg_tps="$(awk -v s="${SUM_TPS_INT}" -v n="${COUNT}" 'BEGIN {printf "%.2f", (s/n)/100}')"
    total_s_all="$(awk -v ns="${SUM_TIME_NS}" 'BEGIN {printf "%.2f", ns/1e9}')"
    log_info "Model:       ${MODEL}"
    log_info "Prompts:     ${COUNT}"
    log_info "Total tok:   ${SUM_TOKS}"
    log_info "Total time:  ${total_s_all} s"
    log_info "Avg tok/s:   ${avg_tps}"
fi
