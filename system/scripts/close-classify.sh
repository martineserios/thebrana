#!/usr/bin/env bash
# Close-mode weight classification (single source of truth — t-1978, ADR-052 §5;
# orientation flags t-1980, ADR-053).
#
# Called by /brana:close gate (phases/gate-and-evidence.md Step 1) AND by
# tests/procedures/test-close-weight-adaptive.sh. Do not replicate this logic
# anywhere — replicate-the-logic copies rot silently (found at t-1973: the
# test's copy predated NANO).
#
# Usage:
#   close-classify.sh --commit-count N [--arguments "..."] [--mode-override <orientation>] < changed-files.txt
#   (changed files newline-separated on stdin; `git diff --name-only` output)
#
# Prints one of: NANO | LIGHT | LIGHT-INLINE | INSTANT | FULL
#
# Matrix (ADR-052 §5 Track 1 + ADR-053 §1 orientations):
#   orientation (--continue/--finish/--patterns/--abort, via --arguments or
#     --mode-override) wins over EVERYTHING — including --light/--full/--nano:
#       continue → INSTANT   finish → INSTANT
#       patterns → LIGHT-INLINE (extract now, NEVER queues — ADR-053 §3,
#         the documented exception to ADR-052 §5; gate Step 1b queues
#         INSTANT/LIGHT/FULL only, so LIGHT-INLINE is structurally excluded)
#       abort    → NANO
#   --light/--full/--nano escape hatches next, in that order
#   auto-heavy (≥2 commits, code/behavioral files) → INSTANT (queue + handoff;
#     extraction deferred to nightly cron). FULL only via explicit --full.
#   1 commit, ≤5 non-code files → NANO (never queues)
#   else → LIGHT

set -uo pipefail

orientation_weight() {
    case "$1" in
        continue|finish) echo "INSTANT" ;;
        patterns)        echo "LIGHT-INLINE" ;;
        abort)           echo "NANO" ;;
        *) echo "close-classify: unknown orientation '$1' (valid: continue finish patterns abort)" >&2; exit 2 ;;
    esac
}

COMMIT_COUNT=0
ARGUMENTS=""
MODE_OVERRIDE=""
while [ $# -gt 0 ]; do
    case "$1" in
        --commit-count)  COMMIT_COUNT="$2"; shift 2 ;;
        --arguments)     ARGUMENTS="$2"; shift 2 ;;
        --mode-override) MODE_OVERRIDE="$2"; shift 2 ;;
        *) echo "close-classify: unknown argument $1" >&2; exit 2 ;;
    esac
done

# Orientation flags win over everything (ADR-053 §1). Explicit --mode-override
# first (programmatic callers), then orientation flags inside --arguments —
# same string-contains convention as the weight escape hatches below.
if [ -n "$MODE_OVERRIDE" ]; then
    orientation_weight "$MODE_OVERRIDE"
    exit 0
fi
for ORIENT in continue finish patterns abort; do
    if [[ "$ARGUMENTS" == *"--$ORIENT"* ]]; then
        orientation_weight "$ORIENT"
        exit 0
    fi
done

CHANGED_FILES=$(cat)
FILE_COUNT=$(echo "$CHANGED_FILES" | grep -c . || echo 0)
# Behavioral JSON: system/ or .claude/ JSON files, excluding tasks.json (state file)
BEHAVIORAL_JSON=$(echo "$CHANGED_FILES" | grep -E '^(system|\.claude)/.*\.json$' \
                 | grep -v '^\.claude/tasks\.json$' || true)

# Escape hatches take priority
if [[ "$ARGUMENTS" == *"--light"* ]]; then CLOSE_MODE="LIGHT"
elif [[ "$ARGUMENTS" == *"--full"* ]]; then CLOSE_MODE="FULL"
elif [[ "$ARGUMENTS" == *"--nano"* ]]; then CLOSE_MODE="NANO"
# INSTANT (was auto-FULL pre-Track-1): ≥2 commits in this session
elif [[ "${COMMIT_COUNT:-0}" -ge 2 ]]; then CLOSE_MODE="INSTANT"
# INSTANT: any code or behavioral config file changed
elif echo "$CHANGED_FILES" | grep -qE '\.(rs|ts|tsx|js|jsx|py|sh|toml|yaml|yml)$'; then CLOSE_MODE="INSTANT"
elif [[ -n "$BEHAVIORAL_JSON" ]]; then CLOSE_MODE="INSTANT"
# NANO: exactly 1 commit, ≤5 files, no code/config files, only .md / tasks.json / state files
elif [[ "${COMMIT_COUNT:-0}" -eq 1 ]] && [[ "${FILE_COUNT:-0}" -le 5 ]]; then CLOSE_MODE="NANO"
# LIGHT: only .md, tasks.json, state/*.json, or inbox/ changed
else CLOSE_MODE="LIGHT"
fi

echo "$CLOSE_MODE"
