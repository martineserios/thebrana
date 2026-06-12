#!/usr/bin/env bash
# Tests: system/cron/close-extraction.sh — nightly extraction worker (t-1974, ADR-052 §6-7).
# Fake agy via $AGY_BIN; real brana close-queue + remind stores under isolated $HOME.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CRON="$SCRIPT_DIR/../../cron/close-extraction.sh"
PASS=0; FAIL=0; TOTAL=0
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

REAL_BRANA="$SCRIPT_DIR/../../cli/rust/target/release/brana"
[ -x "$REAL_BRANA" ] || REAL_BRANA="$(command -v brana)"

check() {
    local desc="$1" expected="$2" actual="$3"
    TOTAL=$((TOTAL + 1))
    if [ "$expected" = "$actual" ]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        echo "FAIL: $desc"
        echo "  expected: $expected"
        echo "  actual:   $actual"
    fi
}

# Fake agy that prints the contents of $FAKE_AGY_OUTPUT (or nothing).
make_fake_agy() {
    local path="$1"
    cat > "$path" <<'EOF'
#!/usr/bin/env bash
[ -n "${FAKE_AGY_OUTPUT:-}" ] && cat "$FAKE_AGY_OUTPUT"
exit "${FAKE_AGY_EXIT:-0}"
EOF
    chmod +x "$path"
}

# Seed one queue entry with a real snapshot file. Prints entry id.
seed_entry() {
    local home="$1" branch="$2" range="$3"
    mkdir -p "$home/.claude/sessions"
    local snap="$home/.claude/sessions/snap-seed-$branch.diff"
    printf 'diff --git a/x b/x\n+++ b/x\n+content %s\n' "$branch" > "$snap"
    HOME="$home" "$REAL_BRANA" close-queue append --project testproj --branch "$branch" \
        --git-root /tmp --git-range "$range" --snapshot-path "$snap" --commit-count 2 \
        | python3 -c "import json,sys; print(json.load(sys.stdin)['id'])"
}

run_cron() {
    local home="$1"; shift
    HOME="$home" BRANA="$REAL_BRANA" AGY_BIN="$FAKE_AGY" "$@" bash "$CRON"
}

FAKE_AGY="$TMPDIR/agy"
make_fake_agy "$FAKE_AGY"

GOOD_OUTPUT="$TMPDIR/good.json"
cat > "$GOOD_OUTPUT" <<'EOF'
{"learnings": [
  {"type": "pattern", "size": "LARGE", "title": "Sidecar locks beat inode locks", "body": "Atomic rename replaces the inode.", "confidence": 0.9},
  {"type": "errata", "size": "SMALL", "title": "validate flag renamed", "body": "--check is now --verify.", "confidence": 0.8}
]}
EOF

if [ ! -f "$CRON" ]; then echo "FAIL: $CRON does not exist"; exit 1; fi

# ── 1. happy path: valid agy output → reminders + processed + summary ──
H1="$TMPDIR/h1"; mkdir -p "$H1"
ID1=$(seed_entry "$H1" feat-a a..b)
FAKE_AGY_OUTPUT="$GOOD_OUTPUT" run_cron "$H1" env FAKE_AGY_OUTPUT="$GOOD_OUTPUT" >/dev/null 2>&1
check "happy path exits 0" "0" "$?"
check "entry marked processed" "1" "$(HOME="$H1" "$REAL_BRANA" close-queue list | grep -c '"processed": true')"
RJSON=$(HOME="$H1" "$REAL_BRANA" remind list)
check "two reminders written" "2" "$(echo "$RJSON" | grep -c '"id"')"
check "LARGE learning → high priority" "1" "$(echo "$RJSON" | python3 -c "
import json,sys
rs=json.load(sys.stdin)
print(sum(1 for r in rs if r['priority']=='high' and 'Sidecar' in r['text']))")"
SUMMARY=$(ls "$H1/.claude/sessions/"daily-summary-*.md 2>/dev/null | head -1)
check "daily summary written" "yes" "$([ -n "$SUMMARY" ] && echo yes || echo no)"
check "summary contains learning title" "1" "$(grep -c 'Sidecar locks' "$SUMMARY" 2>/dev/null)"

# second entry same day → summary APPENDS (ADR-052 M9)
ID2=$(seed_entry "$H1" feat-b c..d)
FAKE_AGY_OUTPUT="$GOOD_OUTPUT" run_cron "$H1" env FAKE_AGY_OUTPUT="$GOOD_OUTPUT" >/dev/null 2>&1
check "summary appends on second run" "2" "$(grep -c 'Sidecar locks' "$SUMMARY" 2>/dev/null)"

# ── 2. empty agy output → mark-failed, no reminder, exit nonzero ──────
H2="$TMPDIR/h2"; mkdir -p "$H2"
seed_entry "$H2" feat-a a..b >/dev/null
EMPTY="$TMPDIR/empty.json"; : > "$EMPTY"
FAKE_AGY_OUTPUT="$EMPTY" run_cron "$H2" env FAKE_AGY_OUTPUT="$EMPTY" >/dev/null 2>&1
rc=$?
check "empty output exits nonzero" "1" "$([ "$rc" -ne 0 ] && echo 1 || echo 0)"
Q2=$(HOME="$H2" "$REAL_BRANA" close-queue list)
check "empty output marks failed" "1" "$(echo "$Q2" | grep -c '"failed": true')"
check "empty output not processed" "0" "$(echo "$Q2" | grep -c '"processed": true')"
check "empty output writes no reminders" "0" "$(HOME="$H2" "$REAL_BRANA" remind list | grep -c '"id"')"

# ── 3. malformed JSON → mark-failed ────────────────────────────────────
H3="$TMPDIR/h3"; mkdir -p "$H3"
seed_entry "$H3" feat-a a..b >/dev/null
BAD="$TMPDIR/bad.json"; echo '{oops' > "$BAD"
FAKE_AGY_OUTPUT="$BAD" run_cron "$H3" env FAKE_AGY_OUTPUT="$BAD" >/dev/null 2>&1
check "malformed marks failed, retry_count 1" "1" "$(HOME="$H3" "$REAL_BRANA" close-queue list | grep -c '"retry_count": 1')"

# ── 4. third failure → processing-failure reminder ─────────────────────
for _ in 1 2; do
    FAKE_AGY_OUTPUT="$BAD" run_cron "$H3" env FAKE_AGY_OUTPUT="$BAD" >/dev/null 2>&1
done
check "retry_count reaches 3" "1" "$(HOME="$H3" "$REAL_BRANA" close-queue list | grep -c '"retry_count": 3')"
check "failure reminder written after 3 strikes" "1" "$(HOME="$H3" "$REAL_BRANA" remind list | grep -ci 'extraction failed')"
# 4th run: entry exhausted (retry_count>=3) → skipped, count stays 3
FAKE_AGY_OUTPUT="$BAD" run_cron "$H3" env FAKE_AGY_OUTPUT="$BAD" >/dev/null 2>&1
check "exhausted entry skipped on later runs" "1" "$(HOME="$H3" "$REAL_BRANA" close-queue list | grep -c '"retry_count": 3')"

# ── 5. agy binary missing → exit nonzero, nothing marked processed ─────
H5="$TMPDIR/h5"; mkdir -p "$H5"
seed_entry "$H5" feat-a a..b >/dev/null
HOME="$H5" BRANA="$REAL_BRANA" AGY_BIN="$TMPDIR/no-such-agy" bash "$CRON" >/dev/null 2>&1
rc=$?
check "missing agy exits nonzero" "1" "$([ "$rc" -ne 0 ] && echo 1 || echo 0)"
check "missing agy processes nothing" "0" "$(HOME="$H5" "$REAL_BRANA" close-queue list | grep -c '"processed": true')"

# ── 6. stale unprocessed entry (>3d) → stale-queue reminder ────────────
H6="$TMPDIR/h6"; mkdir -p "$H6"
seed_entry "$H6" feat-old a..b >/dev/null
python3 - "$H6/.claude/close-queue.json" <<'EOF'
import json, sys, datetime
p = sys.argv[1]
d = json.load(open(p))
old = (datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(days=4)).isoformat()
for e in d["entries"]:
    e["timestamp"] = old
json.dump(d, open(p, "w"))
EOF
# agy succeeds for it — but stale reminder should still have fired for the backlog age
FAKE_AGY_OUTPUT="$GOOD_OUTPUT" run_cron "$H6" env FAKE_AGY_OUTPUT="$GOOD_OUTPUT" >/dev/null 2>&1
check "stale-queue reminder written" "1" "$(HOME="$H6" "$REAL_BRANA" remind list | python3 -c "
import json,sys
rs=json.load(sys.stdin)
print(sum(1 for r in rs if r.get('dedup_key')=='stale-close-queue'))")"

# ── 7. snapshot cleanup: processed >14d → snapshot file deleted ────────
H7="$TMPDIR/h7"; mkdir -p "$H7"
seed_entry "$H7" feat-done a..b >/dev/null
FAKE_AGY_OUTPUT="$GOOD_OUTPUT" run_cron "$H7" env FAKE_AGY_OUTPUT="$GOOD_OUTPUT" >/dev/null 2>&1
SNAP7="$H7/.claude/sessions/snap-seed-feat-done.diff"
check "snapshot kept right after processing" "yes" "$([ -f "$SNAP7" ] && echo yes || echo no)"
python3 - "$H7/.claude/close-queue.json" <<'EOF'
import json, sys, datetime
p = sys.argv[1]
d = json.load(open(p))
old = (datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(days=20)).isoformat()
for e in d["entries"]:
    e["processed_at"] = old
json.dump(d, open(p, "w"))
EOF
run_cron "$H7" env FAKE_AGY_OUTPUT="$GOOD_OUTPUT" >/dev/null 2>&1
check "snapshot deleted 14d after processing" "no" "$([ -f "$SNAP7" ] && echo yes || echo no)"

# ── 8. truncated snapshot → processed normally, never failed ──────────
H8="$TMPDIR/h8"; mkdir -p "$H8/.claude/sessions"
SNAP8="$H8/.claude/sessions/snap-trunc.diff"
printf 'diff --git a/y b/y\n+++ b/y\n+partial' > "$SNAP8"
HOME="$H8" "$REAL_BRANA" close-queue append --project testproj --branch feat-t \
    --git-root /tmp --git-range t1..t2 --snapshot-path "$SNAP8" --commit-count 1 \
    --snapshot-truncated >/dev/null
FAKE_AGY_OUTPUT="$GOOD_OUTPUT" run_cron "$H8" env FAKE_AGY_OUTPUT="$GOOD_OUTPUT" >/dev/null 2>&1
Q8=$(HOME="$H8" "$REAL_BRANA" close-queue list)
check "truncated snapshot processed" "1" "$(echo "$Q8" | grep -c '"processed": true')"
check "truncated snapshot not failed" "0" "$(echo "$Q8" | grep -c '"failed": true')"

# ── 9. agy failure reason carries the real exit code, not $? of the ! test (t-2004) ──
H9="$TMPDIR/h9"; mkdir -p "$H9"
seed_entry "$H9" feat-exit a..b >/dev/null
run_cron "$H9" env FAKE_AGY_EXIT=7 >/dev/null 2>&1
Q9=$(HOME="$H9" "$REAL_BRANA" close-queue list)
check "agy failure reason carries real exit code" "1" "$(echo "$Q9" | grep -c 'exit 7')"
check "agy failure reason never reports exit 0" "0" "$(echo "$Q9" | grep -c 'exit 0')"

# ── 10. structural: cron never touches the store file directly ─────────
check "cron never references close-queue.json path" "0" "$(grep -v '^\s*#' "$CRON" | grep -c 'close-queue\.json')"

echo ""
echo "test-close-extraction: $PASS/$TOTAL passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
