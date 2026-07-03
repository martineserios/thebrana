#!/usr/bin/env bash
# Tests for close-snapshot.sh --git-range (t-2242).
#
# Bug (two live reproductions, proyecto_anita 2026-07-02): the close gate's
# COMMIT_COUNT is TOPOLOGICAL (git log --oneline | wc -l — counts commits
# brought in by --no-ff merges) but close-snapshot.sh anchored the range with
# HEAD~N, which walks FIRST-PARENT only. Any merge commit inside the window
# makes the queued range too wide — it swallows another session's commits.
#
# Fix under test: an explicit --git-range A..B is used verbatim; the legacy
# HEAD~N derivation remains as fallback when --git-range is absent.
#
# Run: bash tests/procedures/test-close-snapshot-range.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SNAPSHOT_SH="$SCRIPT_DIR/../../system/scripts/close-snapshot.sh"

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
        echo "  FAIL: $desc (expected '$expected', got '$actual')"
        FAIL=$((FAIL + 1))
    fi
}

# ── Fixture: temp repo with a --no-ff merge inside the session window ─────────
# History (first-parent chain on main: P ← M ← C3):
#   P  (prior close boundary)
#   f1 (feature branch commit)
#   M  (merge --no-ff of f1 into main)
#   C3 (post-merge chore)
# Session = P..HEAD → topological count 3 (f1, M, C3) but first-parent depth 2.
# HEAD~3 therefore lands BEFORE P — the mis-anchor this test pins.
TMP_REPO=$(mktemp -d)
MOCK_BIN=$(mktemp -d)
trap 'rm -rf "$TMP_REPO" "$MOCK_BIN"' EXIT

git -C "$TMP_REPO" init -q -b main
git -C "$TMP_REPO" config user.email t@t && git -C "$TMP_REPO" config user.name t
echo base > "$TMP_REPO/a.txt" && git -C "$TMP_REPO" add . && git -C "$TMP_REPO" commit -qm "root"
echo p > "$TMP_REPO/a.txt" && git -C "$TMP_REPO" commit -qam "P prior close boundary"
P_SHA=$(git -C "$TMP_REPO" rev-parse --short HEAD)
git -C "$TMP_REPO" switch -qc feature
echo f1 > "$TMP_REPO/f.txt" && git -C "$TMP_REPO" add . && git -C "$TMP_REPO" commit -qm "f1 feature work"
git -C "$TMP_REPO" switch -q main
git -C "$TMP_REPO" merge -q --no-ff feature -m "M merge feature"
echo c3 > "$TMP_REPO/c.txt" && git -C "$TMP_REPO" add . && git -C "$TMP_REPO" commit -qm "C3 chore"
HEAD_SHA=$(git -C "$TMP_REPO" rev-parse --short HEAD)

TOPO_COUNT=$(git -C "$TMP_REPO" log --oneline "${P_SHA}..HEAD" | wc -l | tr -d ' ')
assert_eq "fixture: topological count is 3 (merge inflates it past first-parent depth 2)" "3" "$TOPO_COUNT"

# Mock brana: capture close-queue append args, one per line.
CAPTURE="$MOCK_BIN/captured-args"
cat > "$MOCK_BIN/brana" << MOCK
#!/usr/bin/env bash
printf '%s\n' "\$@" > "$CAPTURE"
exit 0
MOCK
chmod +x "$MOCK_BIN/brana"

run_snapshot() {
    rm -f "$CAPTURE"
    BRANA="$MOCK_BIN/brana" HOME="$TMP_REPO" bash "$SNAPSHOT_SH" \
        --git-root "$TMP_REPO" --branch main --project test-proj \
        --commit-count "$TOPO_COUNT" "$@" >/dev/null 2>&1
}

queued_range() {
    # captured args are newline-separated: value follows the --git-range flag
    awk 'prev == "--git-range" { print; exit } { prev = $0 }' "$CAPTURE" 2>/dev/null
}

# ── 1. Explicit --git-range is used verbatim ─────────────────────────────────
run_snapshot --git-range "${P_SHA}..${HEAD_SHA}"
assert_eq "explicit --git-range queued verbatim" "${P_SHA}..${HEAD_SHA}" "$(queued_range)"

# ── 2. Fallback (no --git-range) still queues — legacy HEAD~N behavior ───────
run_snapshot
FALLBACK_RANGE=$(queued_range)
TOTAL=$((TOTAL + 1))
if [ -n "$FALLBACK_RANGE" ]; then
    echo "  PASS: fallback without --git-range still queues (got $FALLBACK_RANGE)"
    PASS=$((PASS + 1))
else
    echo "  FAIL: fallback without --git-range queued nothing"
    FAIL=$((FAIL + 1))
fi
# Document the known mis-anchor: with a merge in the window, HEAD~3 != P.
HEAD3=$(git -C "$TMP_REPO" rev-parse --short "HEAD~3" 2>/dev/null || echo "")
TOTAL=$((TOTAL + 1))
if [ "$FALLBACK_RANGE" = "${HEAD3}..${HEAD_SHA}" ] && [ "$HEAD3" != "$P_SHA" ]; then
    echo "  PASS: fallback mis-anchors across the merge (HEAD~N=$HEAD3 != P=$P_SHA) — why --git-range exists"
    PASS=$((PASS + 1))
else
    echo "  FAIL: fallback anchor expectation changed (range=$FALLBACK_RANGE, HEAD~3=$HEAD3, P=$P_SHA) — update test if fallback was fixed"
    FAIL=$((FAIL + 1))
fi

# ── 3. Invalid --git-range degrades silently (exit 0, nothing queued) ────────
rm -f "$CAPTURE"
BRANA="$MOCK_BIN/brana" HOME="$TMP_REPO" bash "$SNAPSHOT_SH" \
    --git-root "$TMP_REPO" --branch main --project test-proj \
    --commit-count "$TOPO_COUNT" --git-range "deadbeef..cafebabe" >/dev/null 2>&1
RC=$?
assert_eq "invalid --git-range exits 0 (close never blocks)" "0" "$RC"
TOTAL=$((TOTAL + 1))
if [ ! -f "$CAPTURE" ]; then
    echo "  PASS: invalid --git-range queues nothing"
    PASS=$((PASS + 1))
else
    echo "  FAIL: invalid --git-range still queued: $(cat "$CAPTURE" | tr '\n' ' ')"
    FAIL=$((FAIL + 1))
fi

echo
echo "close-snapshot-range: $PASS/$TOTAL passed"
[ "$FAIL" -eq 0 ]
