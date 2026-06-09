#!/usr/bin/env bash
# common.sh — shared helpers for homelab-llm scripts.
#
# Source this file from every script:
#
#   REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
#   # shellcheck source=lib/common.sh
#   source "${REPO_ROOT}/scripts/lib/common.sh"
#
# Conventions:
#   - All callers run with `set -euo pipefail` and `IFS=$'\n\t'`.
#   - Logging functions degrade gracefully when stdout is not a TTY.
#   - Destructive helpers honour the env vars DRY_RUN and SKIP_CONFIRM.

# Guard: prevent double sourcing.
if [[ "${__HOMELAB_LLM_COMMON_SH_SOURCED:-0}" -eq 1 ]]; then
    return 0
fi
__HOMELAB_LLM_COMMON_SH_SOURCED=1

# -----------------------------------------------------------------------------
# Color setup (degrades to no-op when not a TTY).
# -----------------------------------------------------------------------------

if [[ -t 1 ]] && command -v tput >/dev/null 2>&1 && [[ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]]; then
    __C_RESET="$(tput sgr0)"
    __C_RED="$(tput setaf 1)"
    __C_GREEN="$(tput setaf 2)"
    __C_YELLOW="$(tput setaf 3)"
    __C_BLUE="$(tput setaf 4)"
    __C_BOLD="$(tput bold)"
else
    __C_RESET=""
    __C_RED=""
    __C_GREEN=""
    __C_YELLOW=""
    __C_BLUE=""
    __C_BOLD=""
fi

# -----------------------------------------------------------------------------
# Logging.
# -----------------------------------------------------------------------------

log_info() {
    printf '%s[INFO]%s %s\n' "${__C_GREEN}" "${__C_RESET}" "$*"
}

log_warn() {
    printf '%s[WARN]%s %s\n' "${__C_YELLOW}" "${__C_RESET}" "$*" >&2
}

log_error() {
    printf '%s[ERROR]%s %s\n' "${__C_RED}" "${__C_RESET}" "$*" >&2
}

log_step() {
    printf '\n%s%s=== %s ===%s\n' "${__C_BOLD}" "${__C_BLUE}" "$*" "${__C_RESET}"
}

# -----------------------------------------------------------------------------
# Validation helpers.
# -----------------------------------------------------------------------------

# require_cmd <cmd> [<cmd> ...]
# Verifies each command exists in PATH; exits 1 with a clear message otherwise.
require_cmd() {
    local missing=()
    local cmd
    for cmd in "$@"; do
        if ! command -v "${cmd}" >/dev/null 2>&1; then
            missing+=("${cmd}")
        fi
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Required command(s) not found: ${missing[*]}"
        log_error "Install them and retry."
        exit 1
    fi
}

# require_var <varname> [<varname> ...]
# Verifies each env var is set and non-empty; exits 1 otherwise.
require_var() {
    local name
    local missing=()
    for name in "$@"; do
        # Indirect expansion with default-empty check.
        if [[ -z "${!name:-}" ]]; then
            missing+=("${name}")
        fi
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Required environment variable(s) unset or empty: ${missing[*]}"
        log_error "Set them in .env (copy from .env.example) or export them in the shell."
        exit 1
    fi
}

# -----------------------------------------------------------------------------
# Dry-run + confirmation helpers.
# -----------------------------------------------------------------------------

# is_dry_run — returns 0 (true) if DRY_RUN=yes, 1 otherwise.
is_dry_run() {
    [[ "${DRY_RUN:-no}" == "yes" ]]
}

# dry_run_exec <cmd> [args...]
# If DRY_RUN=yes, log the command without running it. Otherwise execute it.
# Quotes preserved via "$@".
dry_run_exec() {
    if is_dry_run; then
        printf '%s[DRY]%s %s\n' "${__C_YELLOW}" "${__C_RESET}" "$*"
        return 0
    fi
    "$@"
}

# confirm <message>
# Returns 0 on yes, 1 on no/empty. Auto-answers yes when SKIP_CONFIRM=yes.
# Default answer is "no".
confirm() {
    local message="${1:-Proceed?}"
    if [[ "${SKIP_CONFIRM:-no}" == "yes" ]]; then
        log_info "${message} [auto-yes via --yes/SKIP_CONFIRM]"
        return 0
    fi
    local reply
    printf '%s%s%s [y/N]: ' "${__C_BOLD}" "${message}" "${__C_RESET}"
    read -r reply || reply=""
    case "${reply}" in
        y|Y|yes|YES) return 0 ;;
        *)           return 1 ;;
    esac
}
