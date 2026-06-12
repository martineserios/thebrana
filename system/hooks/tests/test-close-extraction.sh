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
# FAKE_AGY_STDIN_DUMP copies stdin to a file (diagnostic; stdin is NOT the diff
# carrier — agy drops large stdin payloads and goes agentic, see t-2055).
make_fake_agy() {
    local path="$1"
    cat > "$path" <<'EOF'
#!/usr/bin/env bash
[ -n "${FAKE_AGY_STDIN_DUMP:-}" ] && cat > "$FAKE_AGY_STDIN_DUMP"
# $1=-p $2=prompt — dispatch on prompt content so the propagation pass
# (ADR-056) gets its own fixture without depending on call order.
case "${2:-}" in
    *knowledge-propagation*)
        [ -n "${FAKE_AGY_PROP_OUTPUT:-}" ] && cat "$FAKE_AGY_PROP_OUTPUT"
        exit "${FAKE_AGY_PROP_EXIT:-${FAKE_AGY_EXIT:-0}}"
        ;;
    *)
        [ -n "${FAKE_AGY_OUTPUT:-}" ] && cat "$FAKE_AGY_OUTPUT"
        exit "${FAKE_AGY_EXIT:-0}"
        ;;
esac
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
check "two extraction reminders written" "2" "$(echo "$RJSON" | python3 -c "
import json,sys
rs=json.load(sys.stdin)
print(sum(1 for r in rs if 'extraction' in r.get('tags',[])))")"
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

# ── 7. snapshot cleanup: processed >30d → snapshot file deleted ────────
H7="$TMPDIR/h7"; mkdir -p "$H7"
seed_entry "$H7" feat-done a..b >/dev/null
FAKE_AGY_OUTPUT="$GOOD_OUTPUT" run_cron "$H7" env FAKE_AGY_OUTPUT="$GOOD_OUTPUT" >/dev/null 2>&1
SNAP7="$H7/.claude/sessions/snap-seed-feat-done.diff"
check "snapshot kept right after processing" "yes" "$([ -f "$SNAP7" ] && echo yes || echo no)"
python3 - "$H7/.claude/close-queue.json" <<'EOF'
import json, sys, datetime
p = sys.argv[1]
d = json.load(open(p))
old = (datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(days=35)).isoformat()
for e in d["entries"]:
    e["processed_at"] = old
json.dump(d, open(p, "w"))
EOF
run_cron "$H7" env FAKE_AGY_OUTPUT="$GOOD_OUTPUT" >/dev/null 2>&1
check "snapshot deleted 30d after processing" "no" "$([ -f "$SNAP7" ] && echo yes || echo no)"

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

# ── 10. large snapshot (>128KB argv limit) → processed, not failed (t-2055) ──
# A diff bigger than MAX_ARG_STRLEN poisons the entry if inlined whole into argv:
# exec fails E2BIG before agy even runs. The cron must truncate to MAX_DIFF_BYTES.
H10="$TMPDIR/h10"; mkdir -p "$H10/.claude/sessions"
SNAP10="$H10/.claude/sessions/snap-big.diff"
{ printf 'diff --git a/big b/big\n+++ b/big\n+'; head -c 200000 /dev/zero | tr '\0' 'x'; echo; } > "$SNAP10"
HOME="$H10" "$REAL_BRANA" close-queue append --project testproj --branch feat-big \
    --git-root /tmp --git-range b1..b2 --snapshot-path "$SNAP10" --commit-count 1 >/dev/null
FAKE_AGY_OUTPUT="$GOOD_OUTPUT" run_cron "$H10" env FAKE_AGY_OUTPUT="$GOOD_OUTPUT" >/dev/null 2>&1
Q10=$(HOME="$H10" "$REAL_BRANA" close-queue list)
check "large snapshot processed (argv limit avoided)" "1" "$(echo "$Q10" | grep -c '"processed": true')"
check "large snapshot not failed" "0" "$(echo "$Q10" | grep -c '"failed": true')"

# ── 11. L3 propagation pass (ADR-056): propagate:true → gaps audited ──
GAPS_OUTPUT="$TMPDIR/gaps.json"
cat > "$GAPS_OUTPUT" <<'EOF'
{"gaps": [
  {"category": "a", "title": "test-strategy pointer never written", "evidence": "Doc Plan unchecked", "proposed_fix": "write docs/test-strategy.md"},
  {"category": "d", "title": "memory says pending go", "evidence": "MEMORY.md stale", "proposed_fix": "update memory"}
]}
EOF

H11="$TMPDIR/h11"; mkdir -p "$H11/.claude/sessions"
SNAP11="$H11/.claude/sessions/snap-prop.diff"
printf 'diff --git a/docs/spec.md b/docs/spec.md\n+++ b/docs/spec.md\n+- [ ] pending item\n' > "$SNAP11"
HOME="$H11" "$REAL_BRANA" close-queue append --project testproj --branch feat-prop \
    --git-root /tmp --git-range p1..p2 --snapshot-path "$SNAP11" --commit-count 1 \
    --propagate >/dev/null
FAKE_AGY_OUTPUT="$GOOD_OUTPUT" FAKE_AGY_PROP_OUTPUT="$GAPS_OUTPUT" \
    run_cron "$H11" env FAKE_AGY_OUTPUT="$GOOD_OUTPUT" FAKE_AGY_PROP_OUTPUT="$GAPS_OUTPUT" >/dev/null 2>&1
check "propagate entry run exits 0" "0" "$?"
Q11=$(HOME="$H11" "$REAL_BRANA" close-queue list)
check "propagate entry processed" "1" "$(echo "$Q11" | grep -c '"processed": true')"
R11=$(HOME="$H11" "$REAL_BRANA" remind list)
check "two propagation gap reminders written" "2" "$(echo "$R11" | python3 -c "
import json,sys
rs=json.load(sys.stdin)
print(sum(1 for r in rs if r.get('dedup_key','').startswith('prop:')))")"
check "gap reminder tagged propagation" "1" "$(echo "$R11" | python3 -c "
import json,sys
rs=json.load(sys.stdin)
print(sum(1 for r in rs if 'propagation' in (r.get('tags') or []) and 'test-strategy' in r['text']))")"

# ── 12. propagate:false → no propagation pass, no prop reminders ──────
H12="$TMPDIR/h12"; mkdir -p "$H12"
seed_entry "$H12" feat-noprop n1..n2 >/dev/null
FAKE_AGY_OUTPUT="$GOOD_OUTPUT" FAKE_AGY_PROP_OUTPUT="$GAPS_OUTPUT" \
    run_cron "$H12" env FAKE_AGY_OUTPUT="$GOOD_OUTPUT" FAKE_AGY_PROP_OUTPUT="$GAPS_OUTPUT" >/dev/null 2>&1
R12=$(HOME="$H12" "$REAL_BRANA" remind list)
check "no propagation reminders for propagate:false" "0" "$(echo "$R12" | python3 -c "
import json,sys
rs=json.load(sys.stdin)
print(sum(1 for r in rs if r.get('dedup_key','').startswith('prop:')))")"

# ── 13. invalid gaps output → entry mark-failed, never partial ────────
H13="$TMPDIR/h13"; mkdir -p "$H13/.claude/sessions"
SNAP13="$H13/.claude/sessions/snap-badprop.diff"
printf 'diff --git a/z b/z\n+++ b/z\n+x\n' > "$SNAP13"
HOME="$H13" "$REAL_BRANA" close-queue append --project testproj --branch feat-badprop \
    --git-root /tmp --git-range bp1..bp2 --snapshot-path "$SNAP13" --commit-count 1 \
    --propagate >/dev/null
BAD_GAPS="$TMPDIR/badgaps.json"; echo "not json at all" > "$BAD_GAPS"
FAKE_AGY_OUTPUT="$GOOD_OUTPUT" FAKE_AGY_PROP_OUTPUT="$BAD_GAPS" \
    run_cron "$H13" env FAKE_AGY_OUTPUT="$GOOD_OUTPUT" FAKE_AGY_PROP_OUTPUT="$BAD_GAPS" >/dev/null 2>&1
Q13=$(HOME="$H13" "$REAL_BRANA" close-queue list)
check "invalid gaps output → not processed" "0" "$(echo "$Q13" | grep -c '"processed": true')"
check "invalid gaps output → marked failed" "1" "$(echo "$Q13" | grep -c '"failed": true')"

# ── 14. structural: cron never touches the store file directly ─────────
check "cron never references close-queue.json path" "0" "$(grep -v '^\s*#' "$CRON" | grep -c 'close-queue\.json')"

# ── 15. dedup key embeds learning type (t-1979 #2) ─────────────────────
# Cron-side key must discriminate by type so a pattern and an errata with
# the same title don't collide.
check "dedup key embeds learning type" "1" "$(echo "$RJSON" | python3 -c "
import json,sys
rs=json.load(sys.stdin)
print(sum(1 for r in rs if (r.get('dedup_key') or '').startswith('extract:testproj:pattern:')))")"

# ── 16. categorized failure reasons (t-1979 #4) ────────────────────────
H12="$TMPDIR/h12"; mkdir -p "$H12"
seed_entry "$H12" feat-schema a..b >/dev/null
FAKE_AGY_OUTPUT="$BAD" run_cron "$H12" env FAKE_AGY_OUTPUT="$BAD" >/dev/null 2>&1
check "contract failure categorized schema-invalid" "1" "$(HOME="$H12" "$REAL_BRANA" close-queue list | python3 -c "
import json,sys
print(sum(1 for e in json.load(sys.stdin) if (e.get('error') or '').startswith('schema-invalid')))")"

H12T="$TMPDIR/h12t"; mkdir -p "$H12T"
seed_entry "$H12T" feat-tmo a..b >/dev/null
run_cron "$H12T" env FAKE_AGY_EXIT=124 >/dev/null 2>&1
check "exit 124 categorized timeout" "1" "$(HOME="$H12T" "$REAL_BRANA" close-queue list | python3 -c "
import json,sys
print(sum(1 for e in json.load(sys.stdin) if (e.get('error') or '').startswith('timeout')))")"

H12R="$TMPDIR/h12r"; mkdir -p "$H12R"
seed_entry "$H12R" feat-rate a..b >/dev/null
RATE_OUT="$TMPDIR/rate.txt"; echo 'Error: 429 RESOURCE_EXHAUSTED rate limit exceeded' > "$RATE_OUT"
FAKE_AGY_OUTPUT="$RATE_OUT" run_cron "$H12R" env FAKE_AGY_OUTPUT="$RATE_OUT" FAKE_AGY_EXIT=1 >/dev/null 2>&1
check "429 output categorized rate-limit" "1" "$(HOME="$H12R" "$REAL_BRANA" close-queue list | python3 -c "
import json,sys
print(sum(1 for e in json.load(sys.stdin) if (e.get('error') or '').startswith('rate-limit')))")"

H12E="$TMPDIR/h12e"; mkdir -p "$H12E"
seed_entry "$H12E" feat-err a..b >/dev/null
run_cron "$H12E" env FAKE_AGY_EXIT=7 >/dev/null 2>&1
check "plain nonzero exit categorized agy-error" "1" "$(HOME="$H12E" "$REAL_BRANA" close-queue list | python3 -c "
import json,sys
print(sum(1 for e in json.load(sys.stdin) if (e.get('error') or '').startswith('agy-error')))")"

# ── 17. confidence filter + cap 3 (t-1979 #7) ──────────────────────────
H13="$TMPDIR/h13"; mkdir -p "$H13"
seed_entry "$H13" feat-many a..b >/dev/null
MANY="$TMPDIR/many.json"
cat > "$MANY" <<'EOF'
{"learnings": [
  {"type": "pattern", "size": "LARGE", "title": "keeper one", "body": "b1", "confidence": 0.9},
  {"type": "pattern", "size": "SMALL", "title": "low conf dropme", "body": "b2", "confidence": 0.3},
  {"type": "errata", "size": "SMALL", "title": "keeper two", "body": "b3", "confidence": 0.8},
  {"type": "field-note", "size": "SMALL", "title": "keeper three", "body": "b4", "confidence": 0.7},
  {"type": "pattern", "size": "SMALL", "title": "overflow four", "body": "b5", "confidence": 0.6}
]}
EOF
FAKE_AGY_OUTPUT="$MANY" run_cron "$H13" env FAKE_AGY_OUTPUT="$MANY" >/dev/null 2>&1
R13=$(HOME="$H13" "$REAL_BRANA" remind list)
check "confidence<0.5 learning filtered" "0" "$(echo "$R13" | grep -c 'dropme')"
check "learnings capped at 3 per entry" "3" "$(echo "$R13" | python3 -c "
import json,sys
rs=json.load(sys.stdin)
print(sum(1 for r in rs if 'extraction' in r.get('tags',[])))")"

# ── 18. weekly unrouted-learnings reminder (t-1979 #8) ─────────────────
check "weekly unrouted-learnings reminder written" "1" "$(HOME="$H13" "$REAL_BRANA" remind list | python3 -c "
import json,sys
rs=json.load(sys.stdin)
print(sum(1 for r in rs if (r.get('dedup_key') or '').startswith('weekly-learnings-review:')))")"

# ── 19. defensive snapshot sweep — age-based, status-blind (t-1979 #5) ──
H15="$TMPDIR/h15"; mkdir -p "$H15/.claude/sessions"
ORPHAN="$H15/.claude/sessions/snap-orphan.diff"
FRESH="$H15/.claude/sessions/snap-fresh.diff"
printf 'old' > "$ORPHAN"; touch -d '35 days ago' "$ORPHAN"
printf 'new' > "$FRESH"
seed_entry "$H15" feat-sweep a..b >/dev/null
FAKE_AGY_OUTPUT="$GOOD_OUTPUT" run_cron "$H15" env FAKE_AGY_OUTPUT="$GOOD_OUTPUT" >/dev/null 2>&1
check "orphan snapshot >30d swept" "no" "$([ -f "$ORPHAN" ] && echo yes || echo no)"
check "fresh snapshot kept by sweep" "yes" "$([ -f "$FRESH" ] && echo yes || echo no)"

# failed (never-processed) snapshot also swept once old
H15F="$TMPDIR/h15f"; mkdir -p "$H15F"
seed_entry "$H15F" feat-failsweep a..b >/dev/null
run_cron "$H15F" env FAKE_AGY_EXIT=1 >/dev/null 2>&1
SNAP15="$H15F/.claude/sessions/snap-seed-feat-failsweep.diff"
touch -d '35 days ago' "$SNAP15"
run_cron "$H15F" env FAKE_AGY_EXIT=1 >/dev/null 2>&1
check "failed-entry snapshot swept at >30d" "no" "$([ -f "$SNAP15" ] && echo yes || echo no)"

# ── 20. daily-summary 30d prune (t-1979 #9) ────────────────────────────
OLD_SUMMARY="$H15/.claude/sessions/daily-summary-2026-01-01.md"
printf 'old summary' > "$OLD_SUMMARY"; touch -d '35 days ago' "$OLD_SUMMARY"
FAKE_AGY_OUTPUT="$GOOD_OUTPUT" run_cron "$H15" env FAKE_AGY_OUTPUT="$GOOD_OUTPUT" >/dev/null 2>&1
check "daily summary >30d pruned" "no" "$([ -f "$OLD_SUMMARY" ] && echo yes || echo no)"
check "today's summary kept" "yes" "$(ls "$H15/.claude/sessions/"daily-summary-$(date +%Y-%m-%d).md >/dev/null 2>&1 && echo yes || echo no)"

# ── 21. cron preamble exports HOME (t-1979 #6) ─────────────────────────
check "cron exports HOME explicitly" "1" "$(grep -c '^export HOME' "$CRON")"

# ── 22. extraction prompt is a versioned file (t-1979 #7) ──────────────
PROMPT_FILE="$SCRIPT_DIR/../../cron/prompts/close-extraction.txt"
check "versioned prompt file exists" "yes" "$([ -f "$PROMPT_FILE" ] && echo yes || echo no)"
check "cron reads the versioned prompt file" "1" "$(grep -v '^\s*#' "$CRON" | grep -c 'prompts/close-extraction.txt')"

echo ""
echo "test-close-extraction: $PASS/$TOTAL passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
