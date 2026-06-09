#!/usr/bin/env bash
# confirm.sh — destructive-operation confirmation helper.
#
# Source AFTER lib/common.sh. Provides confirm_destructive(), which:
#   - Prints a clearly visible warning header + the description provided.
#   - Requires the user to type literal "yes" (no shortcut accepted).
#   - Honours FORCE=yes (for non-interactive runs of 99-uninstall.sh) by
#     skipping the prompt with a warning log.
#
# Rationale: keep destructive prompts in one place so behaviour is uniform
# across 01-create-lvm-volume.sh and 99-uninstall.sh, and so the literal-"yes"
# requirement is hard to bypass accidentally.

if [[ "${__HOMELAB_LLM_CONFIRM_SH_SOURCED:-0}" -eq 1 ]]; then
    return 0
fi
__HOMELAB_LLM_CONFIRM_SH_SOURCED=1

# Sanity: lib/common.sh must already be sourced (we use __C_* + log_*).
if [[ "${__HOMELAB_LLM_COMMON_SH_SOURCED:-0}" -ne 1 ]]; then
    printf 'confirm.sh: source lib/common.sh first.\n' >&2
    exit 1
fi

# confirm_destructive <description>
# Prints a banner + description, prompts for literal "yes". Returns 0 if
# confirmed, 1 otherwise. Skips with FORCE=yes.
confirm_destructive() {
    local description="${1:-Destructive operation}"

    if [[ "${FORCE:-no}" == "yes" ]]; then
        log_warn "FORCE=yes — skipping interactive confirmation for: ${description}"
        return 0
    fi

    printf '\n%s%s!!! DESTRUCTIVE OPERATION !!!%s\n' "${__C_BOLD}" "${__C_RED}" "${__C_RESET}"
    printf '%s%s\n' "${__C_RED}" "${description}"
    printf 'This action may DELETE DATA permanently.%s\n\n' "${__C_RESET}"

    local reply
    printf "Type %s'yes'%s (literal, lowercase) to proceed: " "${__C_BOLD}" "${__C_RESET}"
    read -r reply || reply=""

    if [[ "${reply}" == "yes" ]]; then
        log_info "Confirmation accepted."
        return 0
    fi

    log_warn "Confirmation declined (got '${reply}'); aborting."
    return 1
}
