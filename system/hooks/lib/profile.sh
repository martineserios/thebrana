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

# Returns the recommended CC effort level for the current profile tier.
# Agents override via frontmatter `effort:` field; users via `/effort`.
#
# Mapping:
#   strict  → low    (cost-conscious, routine enforcement)
#   standard → high  (balanced thinking)
#   minimal  → max   (full power, no constraints)
#
# Override: set BRANA_EFFORT_LEVEL to bypass profile mapping.
get_profile_effort() {
    if [ -n "${BRANA_EFFORT_LEVEL:-}" ]; then
        echo "$BRANA_EFFORT_LEVEL"
        return
    fi

    local current="${BRANA_HOOK_PROFILE:-standard}"
    case "$current" in
        strict)   echo "low" ;;
        standard) echo "high" ;;
        minimal)  echo "max" ;;
        *)        echo "high" ;;
    esac
}
