#!/usr/bin/env bash
# Tests: post-tasks-validate.sh jq fallback schema check (t-2742)
# Verifies the jq-only fallback path (used when the Rust CLI binary is
# unavailable) flags invalid work_type/kind, accepts epic/initiative types,
# and no longer requires the retired `stream` field.

set -uo pipefail

PASS=0; FAIL=0; TOTAL=0
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

assert_contains() {
    local desc="$1" haystack="$2" needle="$3"
    TOTAL=$((TOTAL + 1))
    if [[ "$haystack" == *"$needle"* ]]; then
        echo "  PASS: $desc"; PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc"
        echo "    expected to contain: $needle"
        echo "    got:                 $haystack"
        FAIL=$((FAIL + 1))
    fi
}

assert_empty() {
    local desc="$1" got="$2"
    TOTAL=$((TOTAL + 1))
    if [ -z "$got" ]; then
        echo "  PASS: $desc"; PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc"
        echo "    expected empty, got: $got"
        FAIL=$((FAIL + 1))
    fi
}

# Mirrors the SCHEMA_ERRORS jq expression in post-tasks-validate.sh's fallback
# branch — same convention as test-validate-hooks-json-command-schema.sh
# (extract the expression, test it directly against fixtures).
SCHEMA_JQ='
  [ if .version == null then "missing version" else empty end,
    if .project == null then "missing project" else empty end,
    if (.tasks | type) != "array" then "tasks must be array" else empty end,
    (.tasks[] |
      [ if .id == null then "task missing id" else empty end,
        if .subject == null then "task \(.id // "?") missing subject" else empty end,
        if .status == null then "task \(.id // "?") missing status" else empty end,
        if (.status | IN("pending","in_progress","completed","cancelled") | not)
          then "task \(.id // "?"): invalid status \(.status)" else empty end,
        if .type == null then "task \(.id // "?") missing type" else empty end,
        if (.type | IN("phase","milestone","task","subtask","epic","initiative") | not)
          then "task \(.id // "?"): invalid type \(.type)" else empty end,
        if .work_type != null and (.work_type | IN("implement","research","design","infra","chore","review") | not)
          then "task \(.id // "?"): invalid work_type \(.work_type)" else empty end,
        if .kind != null and (.kind | IN("feature","fix","refactor","research","docs","design","ops") | not)
          then "task \(.id // "?"): invalid kind \(.kind)" else empty end,
        if .tags != null and (.tags | type) != "array"
          then "task \(.id // "?"): tags must be array" else empty end,
        if .tags != null and (.tags | type) == "array" and ([.tags[] | type != "string"] | any)
          then "task \(.id // "?"): tags items must be strings" else empty end,
        if .context != null and (.context | type) != "string"
          then "task \(.id // "?"): context must be string" else empty end
      ] | .[]
    )
  ] | if length > 0 then join("; ") else empty end
'

echo "post-tasks-validate.sh jq fallback tests"
echo "========================================="
echo ""

echo "--- Invalid work_type flagged ---"
BAD_WT="$TMPDIR/bad-work-type.json"
cat > "$BAD_WT" <<'JSON'
{"version":"1","project":"test","tasks":[
  {"id":"t-1","subject":"x","status":"pending","type":"task","work_type":"bogus"}
]}
JSON
OUT=$(jq -r "$SCHEMA_JQ" "$BAD_WT")
assert_contains "flags invalid work_type" "$OUT" "invalid work_type bogus"

echo ""
echo "--- Invalid kind flagged ---"
BAD_KIND="$TMPDIR/bad-kind.json"
cat > "$BAD_KIND" <<'JSON'
{"version":"1","project":"test","tasks":[
  {"id":"t-1","subject":"x","status":"pending","type":"task","kind":"bogus"}
]}
JSON
OUT=$(jq -r "$SCHEMA_JQ" "$BAD_KIND")
assert_contains "flags invalid kind" "$OUT" "invalid kind bogus"

echo ""
echo "--- epic/initiative types accepted ---"
EPIC="$TMPDIR/epic-initiative.json"
cat > "$EPIC" <<'JSON'
{"version":"1","project":"test","tasks":[
  {"id":"t-1","subject":"Epic node","status":"pending","type":"epic"},
  {"id":"t-2","subject":"Stray initiative","status":"pending","type":"initiative"}
]}
JSON
OUT=$(jq -r "$SCHEMA_JQ" "$EPIC")
assert_empty "epic/initiative types pass" "$OUT"

echo ""
echo "--- retired stream field is not required ---"
NO_STREAM="$TMPDIR/no-stream.json"
cat > "$NO_STREAM" <<'JSON'
{"version":"1","project":"test","tasks":[
  {"id":"t-1","subject":"x","status":"pending","type":"task"}
]}
JSON
OUT=$(jq -r "$SCHEMA_JQ" "$NO_STREAM")
assert_empty "task without stream field passes" "$OUT"

echo ""
echo "--- valid work_type/kind pass ---"
GOOD="$TMPDIR/good.json"
cat > "$GOOD" <<'JSON'
{"version":"1","project":"test","tasks":[
  {"id":"t-1","subject":"x","status":"pending","type":"task","work_type":"implement","kind":"fix"}
]}
JSON
OUT=$(jq -r "$SCHEMA_JQ" "$GOOD")
assert_empty "valid work_type/kind pass" "$OUT"

echo ""
echo "Results: $PASS passed, $FAIL failed, $TOTAL total"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
