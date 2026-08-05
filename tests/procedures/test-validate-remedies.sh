#!/usr/bin/env bash
# Regression test: remedy apply/undo/idempotency round-trips (t-2630, ADR-077).
#
# Each remedy is tested against an ISOLATED fixture git repo, never the real
# repo's own .claude/tasks.json — the fixture repo carries its own copy of the
# migrate scripts under system/scripts/migrate/ (matching the real repo's layout)
# so remedy_<id>_apply's relative script path resolves correctly when $SCRIPT_DIR
# is overridden to point at the fixture for the duration of one call.
#
# Run: bash tests/procedures/test-validate-remedies.sh

set -uo pipefail

PASS=0
FAIL=0
TOTAL=0

assert_true() {
    local desc="$1" cond="$2"
    TOTAL=$((TOTAL + 1))
    if [ "$cond" = "true" ]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc"
        FAIL=$((FAIL + 1))
    fi
}

REPO_ROOT=$(git rev-parse --show-toplevel)
REMEDIES_SH="$REPO_ROOT/system/scripts/validate-remedies.sh"

if [ ! -f "$REMEDIES_SH" ]; then
    echo "ERROR: $REMEDIES_SH does not exist yet"
    exit 1
fi
# shellcheck source=/dev/null
source "$REMEDIES_SH"

for fn in remedy_62_apply remedy_62_undo remedy_63_apply remedy_63_undo remedy_64_apply remedy_64_undo; do
    if ! declare -f "$fn" >/dev/null; then
        echo "ERROR: $fn() not defined by $REMEDIES_SH"
        exit 1
    fi
done

# ── Fixture repo setup ──────────────────────────────────────────────────────
FIXTURE_REPO=$(mktemp -d)
trap 'rm -rf "$FIXTURE_REPO"' EXIT

( cd "$FIXTURE_REPO" \
  && git init -q \
  && mkdir -p .claude system/scripts/migrate \
  && cp "$REPO_ROOT/system/scripts/migrate/normalize-tags.py" system/scripts/migrate/ \
  && cp "$REPO_ROOT/system/scripts/migrate/collapse-level-epic-v3.py" system/scripts/migrate/ \
  && cp "$REPO_ROOT/system/scripts/migrate/drop-stream-field-v3.py" system/scripts/migrate/
) || { echo "ERROR: fixture repo setup failed"; exit 1; }

FIXTURE_TASKS_JSON="$FIXTURE_REPO/.claude/tasks.json"

write_fixture_tasks_json() {
    cat > "$FIXTURE_TASKS_JSON" <<'EOF'
{
  "tasks": [
    {"id": "t-1", "subject": "bad tags", "tags": "a,b,c"},
    {"id": "t-2", "subject": "bad level/epic", "level": 1, "epic": "old-slug"},
    {"id": "t-3", "subject": "bad stream", "stream": "dev"},
    {"id": "t-4", "subject": "clean task", "tags": ["x"]}
  ]
}
EOF
}

commit_fixture() {
    ( cd "$FIXTURE_REPO" && git add -A && git -c user.email=test@test -c user.name=test commit -q -m "$1" )
}

echo "=== Setup: commit fixture tasks.json with all three violations ==="
write_fixture_tasks_json
commit_fixture "fixture: bad tags, level/epic, stream"

# ── Check 62 (tags) ─────────────────────────────────────────────────────────
echo ""
echo "=== Check 62 remedy: tags normalization ==="

( SCRIPT_DIR="$FIXTURE_REPO"; remedy_62_apply ) >/dev/null 2>&1
TAGS_TYPE=$(jq -r '.tasks[] | select(.id=="t-1") | (.tags | type)' "$FIXTURE_TASKS_JSON")
assert_true "remedy_62_apply: t-1's tags is now an array" "$([ "$TAGS_TYPE" = "array" ] && echo true || echo false)"

# Idempotency: apply again, still an array, no error
( SCRIPT_DIR="$FIXTURE_REPO"; remedy_62_apply ) >/dev/null 2>&1
IDEMPOTENT_RC=$?
TAGS_TYPE_2=$(jq -r '.tasks[] | select(.id=="t-1") | (.tags | type)' "$FIXTURE_TASKS_JSON")
assert_true "remedy_62_apply: idempotent (second call is a safe no-op)" \
    "$([ "$IDEMPOTENT_RC" -eq 0 ] && [ "$TAGS_TYPE_2" = "array" ] && echo true || echo false)"

( SCRIPT_DIR="$FIXTURE_REPO"; remedy_62_undo ) >/dev/null 2>&1
UNDO_DIFF=$(cd "$FIXTURE_REPO" && git diff --stat)
assert_true "remedy_62_undo: exact restoration (git diff --quiet)" \
    "$([ -z "$UNDO_DIFF" ] && echo true || echo false)"
[ -n "$UNDO_DIFF" ] && echo "    residual diff: $UNDO_DIFF"

# ── Check 63 (level/epic) ────────────────────────────────────────────────────
echo ""
echo "=== Check 63 remedy: retired level/epic key removal ==="

( SCRIPT_DIR="$FIXTURE_REPO"; remedy_63_apply ) >/dev/null 2>&1
HAS_LEVEL_EPIC=$(jq -r '[.tasks[] | select(has("level") or has("epic"))] | length' "$FIXTURE_TASKS_JSON")
assert_true "remedy_63_apply: no task carries level/epic keys" "$([ "$HAS_LEVEL_EPIC" = "0" ] && echo true || echo false)"

( SCRIPT_DIR="$FIXTURE_REPO"; remedy_63_apply ) >/dev/null 2>&1
IDEMPOTENT_RC=$?
HAS_LEVEL_EPIC_2=$(jq -r '[.tasks[] | select(has("level") or has("epic"))] | length' "$FIXTURE_TASKS_JSON")
assert_true "remedy_63_apply: idempotent (second call is a safe no-op)" \
    "$([ "$IDEMPOTENT_RC" -eq 0 ] && [ "$HAS_LEVEL_EPIC_2" = "0" ] && echo true || echo false)"

( SCRIPT_DIR="$FIXTURE_REPO"; remedy_63_undo ) >/dev/null 2>&1
UNDO_DIFF=$(cd "$FIXTURE_REPO" && git diff --stat)
assert_true "remedy_63_undo: exact restoration (git diff --quiet)" \
    "$([ -z "$UNDO_DIFF" ] && echo true || echo false)"
[ -n "$UNDO_DIFF" ] && echo "    residual diff: $UNDO_DIFF"

# ── Check 64 (stream) ────────────────────────────────────────────────────────
echo ""
echo "=== Check 64 remedy: retired stream key removal ==="

( SCRIPT_DIR="$FIXTURE_REPO"; remedy_64_apply ) >/dev/null 2>&1
HAS_STREAM=$(jq -r '[.tasks[] | select(has("stream"))] | length' "$FIXTURE_TASKS_JSON")
assert_true "remedy_64_apply: no task carries a stream key" "$([ "$HAS_STREAM" = "0" ] && echo true || echo false)"

( SCRIPT_DIR="$FIXTURE_REPO"; remedy_64_apply ) >/dev/null 2>&1
IDEMPOTENT_RC=$?
HAS_STREAM_2=$(jq -r '[.tasks[] | select(has("stream"))] | length' "$FIXTURE_TASKS_JSON")
assert_true "remedy_64_apply: idempotent (second call is a safe no-op)" \
    "$([ "$IDEMPOTENT_RC" -eq 0 ] && [ "$HAS_STREAM_2" = "0" ] && echo true || echo false)"

( SCRIPT_DIR="$FIXTURE_REPO"; remedy_64_undo ) >/dev/null 2>&1
UNDO_DIFF=$(cd "$FIXTURE_REPO" && git diff --stat)
assert_true "remedy_64_undo: exact restoration (git diff --quiet)" \
    "$([ -z "$UNDO_DIFF" ] && echo true || echo false)"
[ -n "$UNDO_DIFF" ] && echo "    residual diff: $UNDO_DIFF"

echo ""
echo "=== Summary ==="
echo "Total: $TOTAL | Passed: $PASS | Failed: $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
