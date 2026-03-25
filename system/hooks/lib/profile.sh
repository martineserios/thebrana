#!/usr/bin/env bash
# Hook Profile Library — tiered hook execution
#
# Usage: source this in any hook script, then call hook_should_run.
#
#   source "${SCRIPT_DIR}/lib/profile.sh"
#   hook_should_run "standard" || { pass_through; exit 0; }
#
# Tiers (ordered by strictness):
#   minimal  — only essential gates (write safety, spec-before-code)
#   standard — default, all production hooks (backward compatible)
#   strict   — adds observability hooks (guard-explore, future auditing)
#
# Set via: BRANA_HOOK_PROFILE=minimal|standard|strict
# Default: standard (no behavior change from pre-profile state)

hook_should_run() {
    local required_tier="$1"
    local current="${BRANA_HOOK_PROFILE:-standard}"

    case "$current" in
        strict)   return 0 ;;  # strict runs everything
        standard) [ "$required_tier" != "strict" ] && return 0 ;;
        minimal)  [ "$required_tier" = "minimal" ] && return 0 ;;
    esac
    return 1
}
