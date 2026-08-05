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

for fn in remedy_62_apply remedy_62_undo remedy_63_apply remedy_63_undo remedy_64_apply remedy_64_undo \
          remedy_42_apply remedy_42_undo remedy_29_apply remedy_29_undo; do
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

# ── Check 42 (debrief-analyst model field) — separate fixture, own repo ────────
# Two independent sub-cases, both driven by the same underlying check condition
# (grep -m1 '^model:' | awk '{print $2}' != "sonnet"): the field absent entirely,
# and the field present but wrong. apply() must fix both.
echo ""
echo "=== Check 42 remedy: debrief-analyst.md model field ==="

FIXTURE42_REPO=$(mktemp -d)
DEBRIEF_FIXTURE="$FIXTURE42_REPO/system/agents/debrief-analyst.md"
mkdir -p "$FIXTURE42_REPO/system/agents"

write_debrief_fixture() {
    # $1: body to substitute for the model line ("" = field absent entirely)
    if [ -z "$1" ]; then
        cat > "$DEBRIEF_FIXTURE" <<'EOF'
---
name: debrief-analyst
description: "test fixture"
effort: high
---
body
EOF
    else
        cat > "$DEBRIEF_FIXTURE" <<EOF
---
name: debrief-analyst
description: "test fixture"
$1
effort: high
---
body
EOF
    fi
}

( cd "$FIXTURE42_REPO" && git init -q )

echo "--- sub-case: model field absent ---"
write_debrief_fixture ""
( cd "$FIXTURE42_REPO" && git add -A && git -c user.email=test@test -c user.name=test commit -q -m "fixture: model absent" )
( SCRIPT_DIR="$FIXTURE42_REPO"; remedy_42_apply ) >/dev/null 2>&1
MODEL_AFTER_ABSENT=$(grep -m1 '^model:' "$DEBRIEF_FIXTURE" | awk '{print $2}' | tr -d '"')
assert_true "remedy_42_apply: absent-field sub-case sets model: sonnet" \
    "$([ "$MODEL_AFTER_ABSENT" = "sonnet" ] && echo true || echo false)"

( SCRIPT_DIR="$FIXTURE42_REPO"; remedy_42_apply ) >/dev/null 2>&1
IDEMPOTENT_RC=$?
MODEL_AFTER_ABSENT_2=$(grep -m1 '^model:' "$DEBRIEF_FIXTURE" | awk '{print $2}' | tr -d '"')
assert_true "remedy_42_apply: idempotent after fixing absent-field case" \
    "$([ "$IDEMPOTENT_RC" -eq 0 ] && [ "$MODEL_AFTER_ABSENT_2" = "sonnet" ] && echo true || echo false)"

( SCRIPT_DIR="$FIXTURE42_REPO"; remedy_42_undo ) >/dev/null 2>&1
UNDO_DIFF=$(cd "$FIXTURE42_REPO" && git diff --stat)
assert_true "remedy_42_undo: exact restoration after absent-field case" \
    "$([ -z "$UNDO_DIFF" ] && echo true || echo false)"
[ -n "$UNDO_DIFF" ] && echo "    residual diff: $UNDO_DIFF"

echo "--- sub-case: model field present but wrong (opus) ---"
write_debrief_fixture "model: opus"
( cd "$FIXTURE42_REPO" && git add -A && git -c user.email=test@test -c user.name=test commit -q -m "fixture: model wrong" )
( SCRIPT_DIR="$FIXTURE42_REPO"; remedy_42_apply ) >/dev/null 2>&1
MODEL_AFTER_WRONG=$(grep -m1 '^model:' "$DEBRIEF_FIXTURE" | awk '{print $2}' | tr -d '"')
assert_true "remedy_42_apply: wrong-value sub-case corrects model: opus -> sonnet" \
    "$([ "$MODEL_AFTER_WRONG" = "sonnet" ] && echo true || echo false)"

( SCRIPT_DIR="$FIXTURE42_REPO"; remedy_42_apply ) >/dev/null 2>&1
IDEMPOTENT_RC=$?
MODEL_AFTER_WRONG_2=$(grep -m1 '^model:' "$DEBRIEF_FIXTURE" | awk '{print $2}' | tr -d '"')
assert_true "remedy_42_apply: idempotent after fixing wrong-value case" \
    "$([ "$IDEMPOTENT_RC" -eq 0 ] && [ "$MODEL_AFTER_WRONG_2" = "sonnet" ] && echo true || echo false)"

( SCRIPT_DIR="$FIXTURE42_REPO"; remedy_42_undo ) >/dev/null 2>&1
UNDO_DIFF=$(cd "$FIXTURE42_REPO" && git diff --stat)
assert_true "remedy_42_undo: exact restoration after wrong-value case (back to opus)" \
    "$([ -z "$UNDO_DIFF" ] && echo true || echo false)"
[ -n "$UNDO_DIFF" ] && echo "    residual diff: $UNDO_DIFF"

rm -rf "$FIXTURE42_REPO"

# ── Check 29 (brana reference generate) — copied minimal skills/hooks/agents tree ──
# find_project_root() resolves via `git rev-parse --show-toplevel` against the
# CALLER's CWD (same hazard class as the migrate scripts) — a fresh git-inited
# fixture repo with its own minimal skill tree naturally reproduces the FAIL state
# (docs/reference/ doesn't exist yet), no special corruption needed.
echo ""
echo "=== Check 29 remedy: brana reference generate ==="

FIXTURE29_REPO=$(mktemp -d)
mkdir -p "$FIXTURE29_REPO/system/skills/example-skill" \
         "$FIXTURE29_REPO/system/hooks" \
         "$FIXTURE29_REPO/system/agents" \
         "$FIXTURE29_REPO/system/rules" \
         "$FIXTURE29_REPO/system/commands"
cat > "$FIXTURE29_REPO/system/skills/example-skill/SKILL.md" <<'EOF'
---
name: example-skill
description: "fixture skill for check 29 remedy test"
---
# Example Skill
Body.
EOF
( cd "$FIXTURE29_REPO" && git init -q && git add -A && git -c user.email=test@test -c user.name=test commit -q -m init )

if ! command -v brana >/dev/null 2>&1; then
    echo "  SKIP: brana CLI not found in PATH — cannot exercise check 29's remedy"
else
    PRE_CHECK_RC=0
    ( cd "$FIXTURE29_REPO" && brana reference generate --check ) >/dev/null 2>&1 || PRE_CHECK_RC=$?
    assert_true "fixture reproduces the FAIL state (reference docs not yet generated)" \
        "$([ "$PRE_CHECK_RC" -ne 0 ] && echo true || echo false)"

    ( SCRIPT_DIR="$FIXTURE29_REPO"; remedy_29_apply ) >/dev/null 2>&1
    POST_CHECK_RC=0
    ( cd "$FIXTURE29_REPO" && brana reference generate --check ) >/dev/null 2>&1 || POST_CHECK_RC=$?
    assert_true "remedy_29_apply: reference docs now up to date (--check passes)" \
        "$([ "$POST_CHECK_RC" -eq 0 ] && echo true || echo false)"
    assert_true "remedy_29_apply: docs/reference/skills.md was actually written" \
        "$([ -f "$FIXTURE29_REPO/docs/reference/skills.md" ] && echo true || echo false)"

    ( cd "$FIXTURE29_REPO" && git add -A && git -c user.email=test@test -c user.name=test commit -q -m "generated reference docs" )
    ( SCRIPT_DIR="$FIXTURE29_REPO"; remedy_29_apply ) >/dev/null 2>&1
    IDEMPOTENT_RC=$?
    IDEMPOTENT_DIFF=$(cd "$FIXTURE29_REPO" && git diff --stat)
    assert_true "remedy_29_apply: idempotent (second call is a safe no-op, no diff)" \
        "$([ "$IDEMPOTENT_RC" -eq 0 ] && [ -z "$IDEMPOTENT_DIFF" ] && echo true || echo false)"

    ( SCRIPT_DIR="$FIXTURE29_REPO"; remedy_29_undo ) >/dev/null 2>&1
    UNDO_STATUS=$(cd "$FIXTURE29_REPO" && git status --porcelain docs/reference/)
    assert_true "remedy_29_undo: docs/reference/ reverted to last commit" \
        "$([ -z "$UNDO_STATUS" ] && echo true || echo false)"
fi

rm -rf "$FIXTURE29_REPO"

echo ""
echo "=== Summary ==="
echo "Total: $TOTAL | Passed: $PASS | Failed: $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
