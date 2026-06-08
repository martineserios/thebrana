#!/usr/bin/env bash
# Unit test for Check 50: removed schema fields must not appear in producer surfaces.
#
# Tests:
#   T1 — no violation in producer surface → no warning
#   T2 — removed field found in producer surface → warning emitted
#   T3 — field found only in comment lines → no warning
#   T4 — schema-removals.json missing → check skips gracefully (no warning)

set -uo pipefail

PASS=0
FAIL=0
TOTAL=0

assert_empty() {
    local desc="$1" result="$2"
    TOTAL=$((TOTAL + 1))
    if [ -z "$result" ]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc — expected no violations, got: $result"
        FAIL=$((FAIL + 1))
    fi
}

assert_contains() {
    local desc="$1" result="$2" needle="$3"
    TOTAL=$((TOTAL + 1))
    if echo "$result" | grep -qF "$needle"; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc — expected '$needle' in output, got: $result"
        FAIL=$((FAIL + 1))
    fi
}

# Extract Check 50 logic — inline reproduction of the validate.sh implementation.
# Given a schema-removals JSON string and a scratch dir containing producer files,
# returns violation lines for each active removed field found outside comment lines.
check50_violations() {
    local schema_json="$1"   # JSON content of schema-removals.json (or empty string if absent)
    local search_dir="$2"    # directory to grep inside (simulates producer surfaces)

    # Missing registry → skip entirely
    [ -z "$schema_json" ] && return 0

    # For each active entry: field, pattern, whole_word flag, include_globs array (as JSON)
    echo "$schema_json" \
    | jq -r '.removed_fields[] | select(.status == "active") |
              [.field, .grep_pattern,
               (.grep_whole_word // false | tostring),
               (.grep_include_globs | tojson)] | @tsv' 2>/dev/null \
    | while IFS=$'\t' read -r field pattern whole_word globs_json; do
        [ -z "$field" ] && continue
        # -w (whole word) if grep_whole_word is true — avoids \b backslash escaping via @tsv
        word_flag=""
        [ "$whole_word" = "true" ] && word_flag="-w"
        # Build --include flags as a bash array (avoids nullglob expansion of unquoted globs)
        declare -a c50_include=()
        while IFS= read -r glob; do
            c50_include+=("--include=$glob")
        done < <(echo "$globs_json" | jq -r '.[]' 2>/dev/null)
        # grep for pattern; filter out Rust comment lines (line content starts with //)
        # shellcheck disable=SC2086 — $word_flag is intentionally unquoted (may be empty)
        hits=$(grep -rn $word_flag "$pattern" "$search_dir" "${c50_include[@]}" 2>/dev/null \
               | grep -v '^[^:]*:[0-9]*:[[:space:]]*//' \
               || true)
        if [ -n "$hits" ]; then
            echo "$hits" | while IFS= read -r line; do
                echo "$field: $line"
            done
        fi
    done
}

# ── T1: no violation — clean producer surface ────────────────────────────────
echo "=== T1: clean producer surface → no warning ==="

TMPDIR_T1=$(mktemp -d)
cat > "$TMPDIR_T1/backlog_add.rs" <<'RS'
pub struct BacklogAdd {
    pub subject: String,
    pub work_type: String,
}
RS

SCHEMA_JSON=$(cat <<'SCHEMAEOF'
{
  "removed_fields": [
    {
      "field": "stream",
      "grep_pattern": "stream",
      "grep_whole_word": true,
      "grep_include_globs": ["*_add.rs", "*_stats.rs"],
      "search_dir": "system/cli/rust/crates/",
      "status": "active",
      "removed_in": "t-1540"
    }
  ]
}
SCHEMAEOF
)

result=$(check50_violations "$SCHEMA_JSON" "$TMPDIR_T1")
assert_empty "T1: clean surface → no violations" "$result"
rm -rf "$TMPDIR_T1"

# ── T2: violation — removed field found in producer surface ─────────────────
echo "=== T2: removed field found in producer surface → warning ==="

TMPDIR_T2=$(mktemp -d)
cat > "$TMPDIR_T2/backlog_add.rs" <<'RS'
pub struct BacklogAdd {
    pub subject: String,
    pub stream: String,   // BUG: stream was removed
}
RS

result=$(check50_violations "$SCHEMA_JSON" "$TMPDIR_T2")
assert_contains "T2: live 'stream' field triggers violation" "$result" "stream"
rm -rf "$TMPDIR_T2"

# ── T3: field in comment-only line → no warning ──────────────────────────────
echo "=== T3: field in comments only → no warning ==="

TMPDIR_T3=$(mktemp -d)
cat > "$TMPDIR_T3/backlog_add.rs" <<'RS'
// "stream" was removed in t-1540 — do not re-add
pub struct BacklogAdd {
    pub subject: String,
    pub work_type: String,
}
RS

result=$(check50_violations "$SCHEMA_JSON" "$TMPDIR_T3")
assert_empty "T3: comment-only lines → no violations" "$result"
rm -rf "$TMPDIR_T3"

# ── T4: schema-removals.json absent → skips gracefully ───────────────────────
echo "=== T4: missing schema-removals.json → no warnings ==="

result=$(check50_violations "" "/tmp")
assert_empty "T4: absent registry → no output" "$result"

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo "=== Check 50 test summary: $PASS/$TOTAL passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
