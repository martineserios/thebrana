#!/usr/bin/env bash
# test-digest-multi-task-beats.sh — digest consumers read `pulled_task_ids` (t-3275, ADR-090 §4).
#
# ADR-090 §4 sends N concurrent build-CLOSEs from one parallel beat into the SAME cockpit
# digest queue. The risk it names is conflation: N branches from one beat read as N unrelated
# review items. So both digest consumers group a beat's close-outs into ONE entry that lists
# every task id.
#
# Batching applies only to a beat that pulled >= 2 ids. A beat with 0 or 1 pulled ids has
# nothing to conflate, so it changes nothing about the render — that is the AC-2 regression
# property asserted below (P2 for pipeline-digest, S3 for the scheduler digest), and it is
# what keeps the pre-t-3275 output byte-identical wherever no multi-task beat exists.
#
# Beat records are the loops-library schema shape (docs/architecture/features/loops-library.md
# §Beat record schema), appended by `autonomous-runner.sh --run-beat` to the runner's existing
# run-state dir. A record with NO `pulled_task_ids` key predates the field and must never be
# conflated with one recording `[]` (P5/P6).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PIPE_SH="$REPO_ROOT/system/scripts/pipeline-digest.sh"
SCHED_SH="$REPO_ROOT/system/scheduler/brana-scheduler-digest.sh"
RUNNER_SH="$REPO_ROOT/system/scripts/autonomous-runner.sh"

PASS=0; FAIL=0; TOTAL=0
check() {
    local desc="$1" ok="$2"
    TOTAL=$((TOTAL+1))
    if [ "$ok" = "0" ]; then PASS=$((PASS+1)); echo "  PASS: $desc"
    else FAIL=$((FAIL+1)); echo "  FAIL: $desc"; fi
}

echo "=== digest multi-task beats (t-3275, ADR-090 §4) ==="

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# ── Fixture repo: three branches that one beat would have pulled, plus one branch no beat
#    ever touched (the "renders exactly as today" control). ────────────────────────────────
FIX="$TMP/repo"
mkdir -p "$FIX"
GA=(-c user.email=t@t -c user.name=t -c commit.gpgsign=false)
git -C "$FIX" init -q -b main
git -C "$FIX" "${GA[@]}" commit -q --allow-empty -m init
git -C "$FIX" branch dev
for b in runner/auto/t-9001 runner/auto/t-9002 runner/auto/t-9003 topic/feat-solo; do
    git -C "$FIX" checkout -q -b "$b" dev
    echo "$b" > "$FIX/$(printf '%s' "$b" | tr / _).txt"
    git -C "$FIX" add -A
    git -C "$FIX" "${GA[@]}" commit -q -m "work on $b"
done
git -C "$FIX" checkout -q dev

BEATS="$TMP/beats.jsonl"
OUT="$TMP/digest-out"

beat_rec() {  # beat_rec <n> <instance> <state> <ids...>   (no ids -> pulled_task_ids: [])
    local n="$1" inst="$2" state="$3"; shift 3
    local ids
    if [ "$#" -eq 0 ]; then ids='[]'
    else ids="$(printf '%s\n' "$@" | jq -R . | jq -sc .)"; fi
    jq -cn --argjson b "$n" --arg i "$inst" --arg s "$state" --argjson ids "$ids" \
        '{loop:"autonomous-runner",instance:$i,beat:$b,timestamp:"2026-09-04T10:00:00Z",
          state:$s,what_happened:"beat",pulled_task_ids:$ids,
          progress:{kind:"unbounded",remaining:null,total:null},escalations:[],next_wake:null}'
}

render() {  # render [beats-file] -> digest on stdout
    # Two fields move on their own between runs and are not the property under test: the
    # beat's own UTC stamp, and git's relative `last activity` (which ticks from "0 seconds
    # ago" to "1 second ago" mid-suite). Everything else is compared byte for byte.
    local bf="${1:-}"
    rm -rf "$OUT"
    BRANA_BEATS_FILE="$bf" BRANA_DIGEST_DIR="$OUT" bash "$PIPE_SH" "$FIX" 2>/dev/null \
        | sed -E -e 's/^# Pipeline digest — .*/# Pipeline digest — <TS>/' \
                 -e 's/last activity: [^·]*$/last activity: <REL>/'
}

# ── P1/P2 — AC2: a single-task beat renders exactly as before. ─────────────────────────────
R_NONE="$(render "$TMP/absent.jsonl")"
[ -n "$R_NONE" ]; check "P1: digest renders with no beats file" $?

beat_rec 1 wave-1 active t-9001 > "$BEATS"
R_ONE="$(render "$BEATS")"
[ "$R_NONE" = "$R_ONE" ]
check "P2: single-task beat renders byte-identical to the no-beat render (AC2)" $?

# ── P3 — AC1/AC3: three ids in one beat render as ONE batched entry naming all three. ──────
beat_rec 4 wave-1 active t-9001 t-9002 t-9003 > "$BEATS"
R_THREE="$(render "$BEATS")"

BATCH_LINES="$(printf '%s\n' "$R_THREE" | grep -c '^- \*\*beat ')"
[ "$BATCH_LINES" = "1" ]
check "P3a: exactly one batched beat entry (AC3)" $?

BATCH="$(printf '%s\n' "$R_THREE" | grep '^- \*\*beat ' || true)"
printf '%s' "$BATCH" | grep -q 't-9001' && \
printf '%s' "$BATCH" | grep -q 't-9002' && \
printf '%s' "$BATCH" | grep -q 't-9003'
check "P3b: the batched entry lists every task id (AC1)" $?

printf '%s' "$BATCH" | grep -q 'beat 4'
check "P3c: the batched entry names the beat" $?

for br in runner/auto/t-9001 runner/auto/t-9002 runner/auto/t-9003; do
    [ "$(printf '%s\n' "$R_THREE" | grep -c "\`$br\`")" = "1" ]
    check "P3d: $br appears exactly once (not duplicated by grouping)" $?
    printf '%s\n' "$R_THREE" | grep -q "^  - \`$br\`"
    check "P3e: $br is nested under the batched entry" $?
done

# the branch no beat touched keeps its pre-change top-level row, byte for byte
SOLO_BEFORE="$(printf '%s\n' "$R_NONE"  | grep '^- `topic/feat-solo`' || true)"
SOLO_AFTER="$(printf '%s\n'  "$R_THREE" | grep '^- `topic/feat-solo`' || true)"
[ -n "$SOLO_BEFORE" ] && [ "$SOLO_BEFORE" = "$SOLO_AFTER" ]
check "P3f: a branch outside any beat renders exactly as today" $?

printf '%s\n' "$R_THREE" | grep -q '^## Unmerged branches (4)$'
check "P3g: the unmerged-branch headline count is unchanged by grouping" $?

# ── P4 — a multi-task beat and a single-task beat in the same file. ────────────────────────
{ beat_rec 4 wave-1 active t-9001 t-9002 t-9003; beat_rec 5 wave-1 active t-9004; } > "$BEATS"
R_MIX="$(render "$BEATS")"
[ "$(printf '%s\n' "$R_MIX" | grep -c '^- \*\*beat ')" = "1" ]
check "P4: only the multi-task beat is batched; the single-task beat adds nothing" $?

# ── P5/P6 — `[]` and a missing key are different answers; neither batches. ─────────────────
beat_rec 6 wave-1 empty > "$BEATS"
R_EMPTY="$(render "$BEATS")"
[ "$R_EMPTY" = "$R_NONE" ]
check "P5: a zero-pull beat (pulled_task_ids: []) changes nothing" $?

jq -cn '{loop:"epic-drain",instance:"wave-1",beat:2,timestamp:"2026-08-14T18:02:11Z",
         state:"active",what_happened:"pulled t-9001, t-9002 and t-9003"}' > "$BEATS"
R_LEGACY="$(render "$BEATS")"
[ "$R_LEGACY" = "$R_NONE" ]
check "P6: a pre-field record (no pulled_task_ids key) is never read as ids from prose" $?

# ── P7 — a malformed line must not take the beat down. ─────────────────────────────────────
{ echo 'not json at all'; beat_rec 4 wave-1 active t-9001 t-9002 t-9003; } > "$BEATS"
R_JUNK="$(render "$BEATS")"
[ "$(printf '%s\n' "$R_JUNK" | grep -c '^- \*\*beat ')" = "1" ]
check "P7: a malformed beats line is skipped, the good record still batches" $?

# ══════════════════════ scheduler digest ═══════════════════════════════════════════════════
# Hermetic: a temp HOME so the real ~/.claude and ~/.hub-secrets are never touched, plus
# stub curl (captures the Telegram payload) and stub ssh (laptop unreachable).
SH="$TMP/schedhome"; SBIN="$TMP/schedbin"
mkdir -p "$SH/.claude/scheduler" "$SBIN"
cat > "$SH/.hub-secrets" <<'EOF'
TELEGRAM_BOT_TOKEN=fake-token
OWNER_CHAT_ID=12345
LAPTOP_HOST=nowhere.invalid
EOF
echo '{"jobs":{"feed":{"enabled":true},"digest":{"enabled":true}}}' > "$SH/.claude/scheduler/scheduler.json"
echo '{"feed":{"status":"SUCCESS"},"digest":{"status":"SUCCESS"}}' > "$SH/.claude/scheduler/last-status.json"
cat > "$SBIN/curl" <<EOF
#!/usr/bin/env bash
for a in "\$@"; do case "\$a" in text=*) printf '%s' "\${a#text=}" > "$TMP/telegram.txt" ;; esac; done
exit 0
EOF
printf '#!/usr/bin/env bash\nexit 255\n' > "$SBIN/ssh"
chmod +x "$SBIN/curl" "$SBIN/ssh"

TODAY="$(date '+%Y-%m-%d')"
sched_beat() {  # like beat_rec but stamped today, so the daily digest picks it up
    local n="$1" inst="$2"; shift 2
    local ids; ids="$(printf '%s\n' "$@" | jq -R . | jq -sc .)"
    jq -cn --argjson b "$n" --arg i "$inst" --arg ts "${TODAY}T10:00:00Z" --argjson ids "$ids" \
        '{loop:"autonomous-runner",instance:$i,beat:$b,timestamp:$ts,state:"active",
          what_happened:"beat",pulled_task_ids:$ids,
          progress:{kind:"unbounded",remaining:null,total:null},escalations:[],next_wake:null}'
}
send() {  # send [beats-file] -> Telegram payload on stdout
    rm -f "$TMP/telegram.txt"
    env HOME="$SH" PATH="$SBIN:$PATH" BRANA_BEATS_FILE="${1:-}" \
        bash "$SCHED_SH" >/dev/null 2>&1
    cat "$TMP/telegram.txt" 2>/dev/null
}

S_NONE="$(send "$TMP/absent.jsonl")"
printf '%s' "$S_NONE" | grep -q 'Scheduler Digest'
check "S1: scheduler digest still sends with no beats file" $?

sched_beat 4 wave-1 t-9001 t-9002 t-9003 > "$BEATS"
S_THREE="$(send "$BEATS")"
[ "$(printf '%s\n' "$S_THREE" | grep -c 'beat 4')" = "1" ]
check "S2a: a three-id beat is one entry in the scheduler digest (AC3)" $?
S_LINE="$(printf '%s\n' "$S_THREE" | grep 'beat 4' || true)"
printf '%s' "$S_LINE" | grep -q 't-9001' && \
printf '%s' "$S_LINE" | grep -q 't-9002' && \
printf '%s' "$S_LINE" | grep -q 't-9003'
check "S2b: that single entry lists every task id (AC1)" $?

sched_beat 5 wave-1 t-9004 > "$BEATS"
S_ONE="$(send "$BEATS")"
[ "$S_ONE" = "$S_NONE" ]
check "S3: a single-task beat renders exactly as before (AC2)" $?

beat_rec 6 wave-1 active t-8001 t-8002 > "$BEATS"   # timestamp 2026-09-04, not today's date
S_OLD="$(send "$BEATS")"
if [ "$TODAY" = "2026-09-04" ]; then
    printf '%s' "$S_OLD" | grep -q 't-8001'; check "S4: today's beat is reported" $?
else
    [ "$S_OLD" = "$S_NONE" ]; check "S4: a beat from another day is not in today's digest" $?
fi

# ══════════════════════ producer: --run-beat emits the record ══════════════════════════════
# The consumers above are useless without a producer. One end-to-end check that the runner
# appends a schema-shaped record naming every id it pulled, into the file the digests read.
STUBD="$TMP/stub"; mkdir -p "$STUBD"
cat > "$STUBD/claude" <<'EOF'
#!/usr/bin/env bash
prompt="$(cat)"
printf '%s' "$prompt" | grep -q "PLANNING step" && { echo "AUTODOABLE: ok"; exit 0; }
printf 'the\n' > target.txt
echo "DONE"
EOF
cat > "$STUBD/brana" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "backlog" ] && [ "${2:-}" = "wave" ] && [ "${3:-}" = "pull" ]; then
  arr="$(printf '%s\n' ${STUB_PULL_IDS:-} | grep -v '^$' | jq -R . | jq -sc .)"
  jq -cn --arg w "${4:-wave-1}" --argjson ids "$arr" \
     '{ok:true,id:$w,n:($ids|length),pulled_task_ids:$ids,stopped:"reached_n"}'
  exit 0
fi
exit 0
EOF
chmod +x "$STUBD/claude" "$STUBD/brana"

RREPO="$TMP/runrepo"; mkdir -p "$RREPO"
git -C "$RREPO" init -q -b main
printf 'teh\n' > "$RREPO/target.txt"
git -C "$RREPO" add -A; git -C "$RREPO" "${GA[@]}" commit -q -m init
printf '[{"id":"t-8001","subject":"a","status":"in_progress","execution":"autonomous","priority":"P3","blocked_by":[]},{"id":"t-8002","subject":"b","status":"in_progress","execution":"autonomous","priority":"P3","blocked_by":[]}]' > "$TMP/fix.json"

RBEATS="$TMP/runner-beats.jsonl"
( cd "$RREPO" && env RUNNER_SANDBOX=0 CLAUDE_BIN="$STUBD/claude" BRANA_BIN="$STUBD/brana" \
    RUNNER_TASKS_JSON="$TMP/fix.json" RUNNER_PLAN=0 RUNNER_LEDGER="$TMP/rl.jsonl" \
    RUNNER_BASE_BRANCH=main RUNNER_WORKTREE_DIR="$TMP/wt" RUNNER_LOCK_FILE="$TMP/rlock" \
    RUNNER_KILL_SWITCH="$TMP/nostop" RUNNER_FANOUT=2 RUNNER_BEATS_FILE="$RBEATS" \
    STUB_PULL_IDS="t-8001 t-8002" \
    bash "$RUNNER_SH" --run-beat --wave wave-1 >"$TMP/runner.out" 2>&1 )

[ -s "$RBEATS" ]; check "R1: --run-beat appends a beat record" $?
jq -e '.pulled_task_ids == ["t-8001","t-8002"]' "$RBEATS" >/dev/null 2>&1
check "R2: the record carries pulled_task_ids in pull order (schema shape)" $?
jq -e 'has("loop") and has("instance") and has("beat") and has("timestamp") and has("state")' \
    "$RBEATS" >/dev/null 2>&1
check "R3: the record carries the loops-library beat fields" $?

echo ""; echo "$PASS/$TOTAL passed"
[ "$FAIL" -eq 0 ] || exit 1
