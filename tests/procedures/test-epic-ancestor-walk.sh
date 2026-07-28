#!/usr/bin/env bash
# Regression test: resolve_epic_ancestor() must not fail OPEN (t-2487).
#
# The walk used to do `json=$(brana backlog get "$id")` then pipe to jq. The
# command substitution exits 0 even when the payload is unparseable, so jq died,
# type_val/cur went empty, the loop fell out and the function printed "" —
# byte-identical to the legitimate "no epic ancestor found" answer. Callers
# (close Step 9c, backlog start branch naming) then routed on a WRONG epic slug,
# which is the t-2263 clobber class: `brana session write` keys handoffs by epic
# and REPLACES rather than merges.
#
# This test asserts the three outcomes stay distinguishable:
#   - found      → slug on stdout, exit 0
#   - not found  → empty stdout, exit 0   (a real negative)
#   - lookup failed → exit non-zero        (NOT an empty string at exit 0)
#
# The function under test is extracted from system/skills/_shared/epic-ancestor-walk.md
# so this test exercises the shipped source, not a copy (t-1978 rot class).
#
# Run: bash tests/procedures/test-epic-ancestor-walk.sh

set -uo pipefail

PASS=0
FAIL=0
TOTAL=0

assert_eq() {
    local desc="$1" expected="$2" actual="$3"
    TOTAL=$((TOTAL + 1))
    if [ "$expected" = "$actual" ]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc — expected [$expected], got [$actual]"
        FAIL=$((FAIL + 1))
    fi
}

assert_nonzero() {
    local desc="$1" code="$2"
    TOTAL=$((TOTAL + 1))
    if [ "$code" -ne 0 ]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc — expected non-zero exit, got 0"
        FAIL=$((FAIL + 1))
    fi
}

echo "=== test-epic-ancestor-walk.sh ==="
echo ""

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WALK_MD="$REPO_ROOT/system/skills/_shared/epic-ancestor-walk.md"

if [ ! -f "$WALK_MD" ]; then
    echo "ERROR: $WALK_MD not found"
    exit 1
fi

# ── Extract the function from the procedure doc ───────────────────────────────
TMPDIR_T="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_T"' EXIT

# FIRST ```bash block only — the doc also carries a caller-example block further
# down, which would execute (and trip `set -u`) if it were sourced too.
awk '/^```bash$/{if(!seen){inb=1; seen=1; next}} /^```$/{inb=0} inb' "$WALK_MD" > "$TMPDIR_T/walk.sh"

if ! grep -q 'resolve_epic_ancestor()' "$TMPDIR_T/walk.sh"; then
    echo "ERROR: could not extract resolve_epic_ancestor() from $WALK_MD"
    exit 1
fi

# ── Fake `brana` on PATH ──────────────────────────────────────────────────────
# Fixture graph:
#   t-child  -> parent t-epic   (type task)
#   t-epic   -> type epic, subject "close", parent null
#   t-orphan -> type task, parent null            (no epic ancestor)
#   t-prose  -> type epic, subject "Backlog UI — rich views", parent null (non-slug)
#   t-corrupt-> full-JSON output carries a RAW control char (the live t-2487 bug);
#              --field reads stay clean
#   t-boom   -> every lookup exits 1 (task vanished / binary error)
mkdir -p "$TMPDIR_T/bin"
cat > "$TMPDIR_T/bin/brana" <<'FAKE'
#!/usr/bin/env bash
# usage: brana backlog get <id> [--field <f>]
id="$3"
field=""
if [ "${4:-}" = "--field" ]; then field="$5"; fi

emit_field() {
    case "$1:$2" in
        t-child:type)      echo '"task"' ;;
        t-child:parent)    echo '"t-epic"' ;;
        t-child:subject)   echo '"a child task"' ;;
        t-epic:type)       echo '"epic"' ;;
        t-epic:parent)     echo 'null' ;;
        t-epic:subject)    echo '"close"' ;;
        t-orphan:type)     echo '"task"' ;;
        t-orphan:parent)   echo 'null' ;;
        t-orphan:subject)  echo '"an orphan"' ;;
        t-prose:type)      echo '"epic"' ;;
        t-prose:parent)    echo 'null' ;;
        t-prose:subject)   echo '"Backlog UI — rich views"' ;;
        t-corrupt:type)    echo '"epic"' ;;
        t-corrupt:parent)  echo 'null' ;;
        t-corrupt:subject) echo '"close"' ;;
        *)                 echo 'null' ;;
    esac
}

# t-boom: total lookup failure, non-zero exit, nothing on stdout
if [ "$id" = "t-boom" ]; then
    echo "task $id not found" >&2
    exit 1
fi

if [ -n "$field" ]; then
    emit_field "$id" "$field"
    exit 0
fi

# Full-object form. For t-corrupt this emits a RAW control char inside a string
# and still exits 0 — precisely the live failure mode t-2487 recorded.
if [ "$id" = "t-corrupt" ]; then
    printf '{"id":"t-corrupt","type":"epic","subject":"close","context":"line1\x01line2","parent":null}\n'
    exit 0
fi
printf '{"id":"%s","type":%s,"subject":%s,"parent":%s}\n' \
    "$id" "$(emit_field "$id" type)" "$(emit_field "$id" subject)" "$(emit_field "$id" parent)"
exit 0
FAKE
chmod +x "$TMPDIR_T/bin/brana"

export PATH="$TMPDIR_T/bin:$PATH"
# shellcheck disable=SC1090
source "$TMPDIR_T/walk.sh"

# ── Sanity: the fixture really is unparseable in the old full-object form ─────
echo "Fixture sanity"
if brana backlog get t-corrupt | jq -e . >/dev/null 2>&1; then
    echo "  FAIL: t-corrupt fixture parses as valid JSON — it must not"
    FAIL=$((FAIL + 1))
else
    echo "  PASS: t-corrupt full-object output is unparseable by jq (reproduces t-2487)"
    PASS=$((PASS + 1))
fi
TOTAL=$((TOTAL + 1))
echo ""

# ── Case 1: found ────────────────────────────────────────────────────────────
echo "Case 1: epic ancestor found"
out=$(resolve_epic_ancestor t-child); code=$?
assert_eq "returns the epic slug" "close" "$out"
assert_eq "exits 0" "0" "$code"
echo ""

# ── Case 2: real negative ────────────────────────────────────────────────────
echo "Case 2: no epic ancestor (real negative)"
out=$(resolve_epic_ancestor t-orphan); code=$?
assert_eq "returns empty" "" "$out"
assert_eq "exits 0 — a negative is not a failure" "0" "$code"
echo ""

# ── Case 3: non-slug epic subject keeps the t-2263 guard ─────────────────────
echo "Case 3: epic subject is prose, not a slug"
out=$(resolve_epic_ancestor t-prose); code=$?
assert_eq "rejects the prose subject" "" "$out"
echo ""

# ── Case 4: THE REGRESSION — unparseable payload must not look like a negative ─
echo "Case 4: corrupt payload (t-2487 fail-open)"
out=$(resolve_epic_ancestor t-corrupt); code=$?
assert_eq "resolves the slug anyway via jq-free --field reads" "close" "$out"
assert_eq "exits 0" "0" "$code"
echo ""

# ── Case 5: hard lookup failure must be distinguishable from 'no epic' ───────
echo "Case 5: lookup fails outright"
out=$(resolve_epic_ancestor t-boom); code=$?
assert_nonzero "signals failure via exit status, not an empty string" "$code"
echo ""

# ── Summary ──────────────────────────────────────────────────────────────────
echo "─────────────────────────────────"
echo "Total: $TOTAL  Pass: $PASS  Fail: $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
