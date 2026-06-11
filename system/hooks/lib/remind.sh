#!/usr/bin/env bash
# Reminder write primitive for hooks (t-1965, ADR-051 §2).
#
# Thin marshalling wrapper around `brana remind write` — the Rust CLI owns
# ALL store mutation (locking, dedup, validation, atomic write). This file
# must never contain jq or any JSON manipulation.
#
# Usage (from any hook):
#   source "$SCRIPT_DIR/lib/remind.sh"
#   write_reminder --text "edited hooks 3x — run validate" \
#       [--action "./validate.sh"] [--priority low|medium|high] \
#       [--dedup-key hooks-validate] [--project thebrana] [--tags "a,b"]
#
# Degradation contract: if the brana binary is missing, warn to stderr and
# return 0 — hooks never block on the reminder system.

write_reminder() {
    local brana_bin="${BRANA:-}"

    # Resolve the binary if the caller didn't provide $BRANA.
    if [ -z "$brana_bin" ] || [ ! -x "$brana_bin" ]; then
        if [ -n "${SCRIPT_DIR:-}" ] && [ -f "${SCRIPT_DIR}/lib/resolve-brana.sh" ]; then
            # shellcheck source=resolve-brana.sh
            source "${SCRIPT_DIR}/lib/resolve-brana.sh"
            brana_bin="${BRANA:-}"
        else
            brana_bin="$(command -v brana 2>/dev/null)" || true
        fi
    fi

    if [ -z "$brana_bin" ] || [ ! -x "$brana_bin" ]; then
        echo "remind.sh: brana binary not found — reminder dropped: $*" >&2
        return 0
    fi

    # Pure pass-through: arg validation (required --text, enum values) is
    # owned by the CLI. Surface CLI failures as non-zero so caller bugs are
    # visible in hook logs, but callers may suppress with `|| true`.
    "$brana_bin" remind write "$@" >/dev/null
}
