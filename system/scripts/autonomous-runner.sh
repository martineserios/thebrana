#!/usr/bin/env bash
# autonomous-runner.sh — native /loop-over-backlog autonomous runner (t-2140).
#
# Staged rollout (docs/architecture/features/autonomous-runner.md):
#   --observe   STAGE 1: select eligible tasks, plan each, emit a would-run/would-park/
#               excluded ledger. ZERO mutations. (proves judgment before write access)
#   --run-one   STAGE 2: run the FIRST eligible would-run task on an isolated branch,
#               verify, commit, STOP. Never merges, never marks the task completed.
#               On ANY failure: revert working tree, return to base branch, delete branch.
#   --run-batch STAGE 3: loop run-one over eligible tasks (a snapshot, each on its own
#               branch) until the batch cap or bounds trip. Bounded: RUNNER_MAX_TASKS cap,
#               consecutive-failure KILL at RUNNER_MAX_FAILS (ADR-050), and a kill-switch
#               file (RUNNER_KILL_SWITCH). Reports ALLDONE when nothing is eligible.
#               PR-per-task; never merges, never marks tasks completed.
#   --run-beat  STAGE 4 (ADR-090 §1/§2, t-3271): ONE beat of a draining WAVE at fan-out
#               width N — pull up to N tasks via `brana backlog wave pull -n N` (N real
#               sequential atomic pulls, each with its own lease), then dispatch N
#               `claude -p` processes IN PARALLEL, one per pulled id, each in its own
#               ephemeral worktree. Same ADR-060 isolation contract as --run-one, invoked
#               N times instead of once — no new isolation primitive (ADR-090 §2). Needs
#               --wave <id> (or RUNNER_WAVE). Never merges, never marks tasks completed.
#
# Native only — no ruflo. Modelled on system/scripts/feed-summarize.sh.
#
# Env (shared):
#   RUNNER_TASKS_JSON  task-source override (file path; for tests). Default: live backlog.
#                      When set, brana mutations (remind/set) are skipped (hermetic tests).
#   RUNNER_MAX_TASKS   batch cap for --observe (default 5)
#   RUNNER_PLAN        1=claude judges would-run vs would-park (default 1); 0=skip
#   RUNNER_LEDGER      ledger path (default ~/.claude/scheduler/runner-ledger-<date>.jsonl)
#   CLAUDE_BIN         claude binary (default ~/.local/bin/claude)
# Env (--run-one adds):
#   RUNNER_VALIDATE_CMD  OPT-IN execution check, OFF by default (t-3256). When set it runs the
#                        worktree's command on the HOST — safe only for a trusted command or a
#                        sandboxed runner (ADR-062). The always-on gate is verify_diff (trusted
#                        inspection: git diff --check + deny-paths + secret-scan), which executes
#                        no worktree code; tests/build run at PR review (never auto-merged).
#   RUNNER_DENY_PATHS    pipe-separated globs the diff may not touch (default: none)
#   RUNNER_SECRET_SCAN   1=park a diff that introduces an obvious secret (default 1)
#   RUNNER_BRANCH_PREFIX per-task branch namespace (default runner/auto)
#   RUNNER_PUSH          1=open a PR via gh after commit (default 0 = local branch only)
#   RUNNER_BASE_BRANCH   integration branch to cut from (ADR-060). Default resolution:
#                        env → .claude/CLAUDE.md "integration=<b>" → "dev" → current HEAD (warn).
#                        The agent NEVER targets production directly; PRs open against this branch.
#   RUNNER_WORKTREE_DIR  parent dir for ephemeral per-task worktrees (default /tmp/brana-runner)
# Env (--run-batch adds):
#   RUNNER_MAX_FAILS     consecutive-failure kill threshold (default 3, ADR-050 cap)
#   RUNNER_KILL_SWITCH   abort if this file exists (default ~/.claude/scheduler/runner.stop)
#   RUNNER_LOCK_FILE     flock path serializing batch runs (default ~/.claude/scheduler/locks/autonomous-runner.lock)
# Env (--run-beat adds; also honours KILL_SWITCH + LOCK_FILE above):
#   RUNNER_WAVE          wave id to pull from (or --wave <id>). No default — a beat with no
#                        wave is a caller error, never a fall-through to another mode.
#   RUNNER_FANOUT        ADR-090 §1's `N`: fan-out width for the beat (default 1 = today's
#                        single dispatch). The real width is min(wip_limit - live, N) —
#                        the wave's wip_limit still bounds it, per pull.
#   RUNNER_CLAIMANT      lease claimant for the beat's pulls (default runner:beat-<pid>)
#   RUNNER_TASKS_FILE    tasks.json to pull against (passed to `wave pull --file`); default
#                        is the CLI's own auto-detection
#   BRANA_BIN            brana binary used for the wave pull / task read (default: brana)
#   RUNNER_BEATS_FILE    beat-record log the digests read (default ~/.claude/scheduler/beats.jsonl,
#                        t-3275). Append-only, loops-library schema, one line per beat.
#   RUNNER_WT_LOCK       flock serializing git worktree ADMIN mutations across the fan-out
#                        (default <RUNNER_WORKTREE_DIR>/.worktree-admin.lock)
#
# Eligibility: status==pending ∧ execution==autonomous ∧ priority!=P0 ∧ blocked_by empty.
set -u

MODE="observe"
WAVE_ID="${RUNNER_WAVE:-}"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --observe)   MODE="observe" ;;
    --run-one)   MODE="run-one" ;;
    --run-batch) MODE="run-batch" ;;
    --run-beat)  MODE="run-beat" ;;
    --wave)      shift; WAVE_ID="${1:-}" ;;
    --wave=*)    WAVE_ID="${1#--wave=}" ;;
  esac
  shift 2>/dev/null || break
done

MAX_TASKS="${RUNNER_MAX_TASKS:-5}"
PLAN="${RUNNER_PLAN:-1}"
CLAUDE_BIN="${CLAUDE_BIN:-$HOME/.local/bin/claude}"
LEDGER="${RUNNER_LEDGER:-$HOME/.claude/scheduler/runner-ledger-$(date -u +%Y%m%d).jsonl}"
VALIDATE_CMD="${RUNNER_VALIDATE_CMD:-}"   # OPT-IN execution check, off by default (t-3256, ADR-062 C2); inspection gate always runs
BRANCH_PREFIX="${RUNNER_BRANCH_PREFIX:-runner/auto}"
PUSH="${RUNNER_PUSH:-0}"
MAX_FAILS="${RUNNER_MAX_FAILS:-3}"
KILL_SWITCH="${RUNNER_KILL_SWITCH:-$HOME/.claude/scheduler/runner.stop}"
RUN_LOCK="${RUNNER_LOCK_FILE:-$HOME/.claude/scheduler/locks/autonomous-runner.lock}"
# Beat records (t-3275, ADR-090 §4). APPEND-only, one line per beat, in the runner's existing
# run-state dir alongside LEDGER/KILL_SWITCH/RUN_LOCK — and the same dir the scheduler digest
# already reads. Deliberately NOT $LEDGER: that file is truncated at every invocation (`: >`
# below), so it can only ever describe the newest run, while the digests must attribute every
# beat whose branches are still waiting at the merge valve.
BEATS_FILE="${RUNNER_BEATS_FILE:-$HOME/.claude/scheduler/beats.jsonl}"
FANOUT="${RUNNER_FANOUT:-1}"              # ADR-090 §1 `N` — operator-set fan-out cap
BRANA_BIN="${BRANA_BIN:-brana}"
CLAIMANT="${RUNNER_CLAIMANT:-runner:beat-$$}"
FIXTURE_MODE=0; [ -n "${RUNNER_TASKS_JSON:-}" ] && FIXTURE_MODE=1
TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

mkdir -p "$(dirname "$LEDGER")"
: > "$LEDGER"

if [ -n "${RUNNER_TASKS_JSON:-}" ]; then
  TASKS_JSON="$(cat "$RUNNER_TASKS_JSON" 2>/dev/null || echo '[]')"
else
  TASKS_JSON="$(brana backlog query --status pending --output json 2>/dev/null || echo '[]')"
fi

# SANDBOX-CLAUDE-BLOCK — t-3257: test-autonomous-runner-real-claude-compat.sh extracts
# exactly this span and sources it, so the opt-in real-claude compat check always exercises
# the shipped sandbox_claude() rather than a reimplementation (same convention as
# EPIC-WALK-BLOCK / BRANCH-PREFIX-BLOCK). Do not remove or rename these markers; keep the
# fences inside them. The extracting test re-sets RUNNER_SCRIPT_DIR after sourcing (it would
# otherwise resolve to the temp extraction file's directory, not this script's).
resolve_claude() { local cb="$CLAUDE_BIN"; [ -x "$cb" ] || cb="$(command -v claude 2>/dev/null || true)"; echo "$cb"; }

RUNNER_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# stage_runner_home <dst> : build a writable per-run HOME holding ONLY the claude
# subscription auth state, with third-party MCP tokens + history + project data stripped.
# WHY writable (not an --ro-bind of the cred file): `claude` rewrites ~/.claude.json on
# startup, so a read-only bind makes it bail "Not logged in · Please run /login" (ADR-062
# addendum, spike-validated 2026-06-21). Exposing a writable copy of the live OAuth token to
# the executor is safe ONLY because egress is allowlisted (token unexfiltratable) — never
# stage real creds without the egress proxy active.
stage_runner_home() {
  local dst="$1"
  mkdir -p "$dst/.claude"; chmod 700 "$dst" "$dst/.claude"
  if [ -f "$HOME/.claude/.credentials.json" ]; then
    # keep ONLY the claude subscription oauth; drop mcpOAuth.* (linear/supabase/… tokens)
    jq '{claudeAiOauth}' "$HOME/.claude/.credentials.json" 2>/dev/null > "$dst/.claude/.credentials.json" \
      || cp "$HOME/.claude/.credentials.json" "$dst/.claude/.credentials.json"
    chmod 600 "$dst/.claude/.credentials.json"
  fi
  if [ -f "$HOME/.claude.json" ]; then
    # keep account identity; strip MCP servers (so none load → egress stays to the API host)
    # + mcpOAuth tokens + history/projects bulk.
    jq 'del(.mcpServers, .mcpOAuth, .history, .projects, .tipsHistory, .cachedChangelog)' \
      "$HOME/.claude.json" 2>/dev/null > "$dst/.claude.json" \
      || cp "$HOME/.claude.json" "$dst/.claude.json"
    chmod 600 "$dst/.claude.json"
  fi
}

# sandbox_claude <workdir> -- <claude args...> : run `claude -p` inside a bubblewrap
# capability jail (ADR-062 + egress addendum). The prompt is read from STDIN and forwarded
# into the jail. Containment (spike-validated, single-level userns — works under Ubuntu
# 24.04+ apparmor_restrict_unprivileged_userns):
#   - minimal --ro-bind list (NOT /) → ~/.config/brana/*.env, ~/.ssh, ~/.aws are ABSENT
#   - env -i → inherited env secrets (LINEAR_API_KEY, …) cleared
#   - writable per-run HOME copy (claude state only, MCP/secrets stripped), rm -rf'd after
#   - <workdir> bound to /workspace = the ONLY host-backed writable path
#   - rlimits via inner ulimit (bwrap 0.11.1 has no --rlimit-* flags)
#   - EGRESS: --unshare-net (jail = loopback only) + a bind-mounted unix socket to a host
#     CONNECT allowlist proxy (api.anthropic.com only); in-jail socat + HTTPS_PROXY route
#     traffic through it. nft/slirp + srt are infeasible unprivileged on this host, so this
#     unix-socket bridge is the boundary. The proxy resolves host-side → jail needs no DNS.
# Graceful fallback to UNSANDBOXED (loud warning) when bwrap is missing or RUNNER_SANDBOX=0
# (e.g. CI without user namespaces, or orchestration tests that stub `claude`).
SANDBOX="${RUNNER_SANDBOX:-1}"
EGRESS="${RUNNER_EGRESS:-1}"
EGRESS_ALLOW="${RUNNER_EGRESS_ALLOW:-api.anthropic.com}"
EGRESS_PORT="${RUNNER_EGRESS_PORT:-18080}"
# Trusted, inspection-only per-task gate (ADR-062 C2, t-3256). Runs on the host but executes
# NO worktree code — only trusted `git` reads over the diff against the base ref. This is the
# root-cause close for the host-RCE class: the gate can never run executor-written code.
# Answers "is this a sane, safe diff worth a human's review?", not "is it correct" (tests and
# build run at PR review — the runner never auto-merges). Returns 0 = pass, 1 = park/fail.
#   1. non-empty diff (a real change exists)
#   2. git diff --check — no conflict markers or whitespace errors
#   3. deny-paths (opt-in, RUNNER_DENY_PATHS = pipe-separated globs) — refuse sensitive paths
#   4. secret-scan on ADDED lines — obvious keys/tokens are parked for a human, not committed
#      (guards the cross-project secret-leak blast radius; disable with RUNNER_SECRET_SCAN=0)
verify_diff() {
  local wd="$1" base="$2"
  # Hardened, read-only git: neutralise every git config surface that runs a command
  # (fsmonitor, hooks, file-protocol, quoting). The gitlink-tamper guard in run_task is the
  # primary defence; these flags are defence-in-depth so verify_diff cannot execute code even
  # if reached another way. Never mutates the index (no add/checkout) — pure inspection.
  local -a G=(git -C "$wd" -c core.fsmonitor= -c core.hooksPath=/dev/null
              -c protocol.file.allow=never -c core.quotePath=false)
  if [ -z "$("${G[@]}" status --porcelain 2>/dev/null)" ]; then
    echo "[autonomous-runner] verify: empty diff" >&2; return 1
  fi
  # Size guard: bound the work so one giant diff can't hang/balloon the batch loop.
  local addln; addln=$("${G[@]}" diff --numstat "$base" 2>/dev/null | awk '{s+=$1} END{print s+0}')
  if [ "${addln:-0}" -gt "${RUNNER_MAX_DIFF_LINES:-20000}" ]; then
    echo "[autonomous-runner] verify: diff too large ($addln added lines > ${RUNNER_MAX_DIFF_LINES:-20000}) — parking for human review" >&2; return 1
  fi
  if ! "${G[@]}" diff --check "$base" >/dev/null 2>&1; then
    echo "[autonomous-runner] verify: git diff --check failed (conflict markers or whitespace errors)" >&2; return 1
  fi
  # Changed paths = tracked (vs base) + untracked new files — the runner commits both (git add -A).
  local changed; changed="$({ "${G[@]}" diff --name-only "$base" 2>/dev/null; "${G[@]}" ls-files --others --exclude-standard 2>/dev/null; } | sort -u)"
  local deny="${RUNNER_DENY_PATHS:-}"
  if [ -n "$deny" ]; then
    local p pat; local -a _pats
    IFS='|' read -ra _pats <<< "$deny"
    while IFS= read -r p; do
      [ -z "$p" ] && continue
      for pat in "${_pats[@]}"; do
        # shellcheck disable=SC2254
        case "$p" in $pat) echo "[autonomous-runner] verify: change touches denied path '$p' (RUNNER_DENY_PATHS='$deny')" >&2; return 1 ;; esac
      done
    done <<< "$changed"
  fi
  if [ "${RUNNER_SECRET_SCAN:-1}" = "1" ]; then
    # Scan added lines: tracked diff additions + full content of untracked new files.
    local added; added="$("${G[@]}" diff "$base" 2>/dev/null | grep '^+' | grep -v '^+++')"
    local f
    while IFS= read -r f; do
      [ -z "$f" ] && continue
      added+=$'\n'"$(cat "$wd/$f" 2>/dev/null)"
    done <<< "$("${G[@]}" ls-files --others --exclude-standard 2>/dev/null)"
    if printf '%s' "$added" | grep -qE 'AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY-----' \
       || printf '%s' "$added" | grep -qiE '(api[_-]?key|secret|token|passwd|password)["'"'"' ]*[:=][ "'"'"']*[A-Za-z0-9/+_-]{20,}'; then
      echo "[autonomous-runner] verify: possible secret in the diff — discarding, task stays pending (set RUNNER_SECRET_SCAN=0 to disable)" >&2; return 1
    fi
  fi
  return 0
}

sandbox_claude() {
  local wd="$1"; shift
  local cb; cb="$(resolve_claude)"
  if [ "$SANDBOX" = "0" ] || ! command -v bwrap >/dev/null 2>&1; then
    [ "$SANDBOX" != "0" ] && echo "[autonomous-runner] WARN: bwrap unavailable — executor running UNSANDBOXED (ADR-062)" >&2
    ( cd "$wd" && timeout "${RUNNER_DISPATCH_TIMEOUT:-600}" "$cb" "$@" )
    return $?
  fi
  local cbr; cbr="$(readlink -f "$cb")"
  local rhome rsock="" proxy_pid=""
  rhome="$(mktemp -d "${TMPDIR:-/tmp}/runner-home-XXXXXX")"
  stage_runner_home "$rhome"
  local -a B=(--unshare-ipc --unshare-pid
    --ro-bind /usr /usr --ro-bind /bin /bin --ro-bind /lib /lib)
  [ -e /lib64 ] && B+=(--ro-bind /lib64 /lib64)
  B+=(--ro-bind /etc /etc --ro-bind "$cbr" /opt/claude --bind "$rhome" /home/sb)
  [ -e "$HOME/.cargo" ]    && B+=(--ro-bind "$HOME/.cargo" /home/sb/.cargo)
  [ -e "$HOME/.gitconfig" ] && B+=(--ro-bind "$HOME/.gitconfig" /home/sb/.gitconfig)
  B+=(--bind "$wd" /workspace --tmpfs /tmp --proc /proc --dev /dev --chdir /workspace)

  local egress_proxy="$RUNNER_SCRIPT_DIR/runner-egress-proxy.py"
  local inner='ulimit -u 200 2>/dev/null; ulimit -f 1024000 2>/dev/null; exec /opt/claude "$@"'
  if [ "$EGRESS" = "1" ] && command -v python3 >/dev/null 2>&1 \
       && command -v socat >/dev/null 2>&1 && [ -f "$egress_proxy" ]; then
    rsock="$(mktemp -u "${TMPDIR:-/tmp}/runner-egress-XXXXXX.sock")"
    # Redirect BOTH stdout and stderr away from the caller's fds: this proxy is a background
    # daemon, and if it inherited stdout it would hold a command-substitution pipe open
    # (DOUT="$(… | sandbox_claude …)") and hang the dispatch until killed.
    python3 "$egress_proxy" "$rsock" "$EGRESS_ALLOW" >/dev/null 2>>"${RUNNER_EGRESS_LOG:-/dev/null}" </dev/null &
    proxy_pid=$!
    local i=0; while [ ! -S "$rsock" ] && [ "$i" -lt 50 ]; do sleep 0.1; i=$((i+1)); done
    B+=(--unshare-net --bind "$rsock" /egress.sock)
    # In-jail bridge: a localhost proxy endpoint → the bind-mounted unix socket. We must NOT
    # `exec` claude here: under --unshare-pid bwrap is the ns init and waits on ALL children,
    # so the backgrounded socat (a daemon) would keep it alive and hang the dispatch's command
    # substitution. Run claude, then reap socat (pkill children + kill listener + wait) so the
    # ns empties and bwrap exits. Written to a bound FILE (not `bash -c`) — the inline-string
    # form proved fragile under the runner's command-substitution; the file form is robust.
    cat > "$rhome/.sbx-inner.sh" <<EOF
socat -T 3 TCP4-LISTEN:$EGRESS_PORT,bind=127.0.0.1,fork,reuseaddr UNIX-CONNECT:/egress.sock </dev/null >/dev/null 2>&1 &
__sp=\$!
sleep 0.4
export HTTPS_PROXY=http://127.0.0.1:$EGRESS_PORT HTTP_PROXY=http://127.0.0.1:$EGRESS_PORT NO_PROXY=
ulimit -u 200 2>/dev/null; ulimit -f 1024000 2>/dev/null
/opt/claude "\$@"; __rc=\$?
pkill -P "\$__sp" 2>/dev/null; kill "\$__sp" 2>/dev/null; wait 2>/dev/null
exit "\$__rc"
EOF
    inner=""   # empty → dispatch via the bound /home/sb/.sbx-inner.sh file
  elif [ "$EGRESS" = "1" ]; then
    echo "[autonomous-runner] WARN: egress deps missing (python3/socat/proxy) — executor network UNRESTRICTED (ADR-062)" >&2
  fi

  if [ -n "$inner" ]; then
    timeout "${RUNNER_DISPATCH_TIMEOUT:-600}" bwrap "${B[@]}" \
      env -i HOME=/home/sb PATH=/usr/sbin:/usr/bin:/bin TERM="${TERM:-dumb}" \
      bash -c "$inner" _ "$@"
  else
    timeout "${RUNNER_DISPATCH_TIMEOUT:-600}" bwrap "${B[@]}" \
      env -i HOME=/home/sb PATH=/usr/sbin:/usr/bin:/bin TERM="${TERM:-dumb}" \
      bash /home/sb/.sbx-inner.sh "$@"
  fi
  local rc=$?
  [ -n "$proxy_pid" ] && kill "$proxy_pid" 2>/dev/null
  [ -n "$rsock" ] && rm -f "$rsock" 2>/dev/null
  rm -rf "$rhome" 2>/dev/null
  return $rc
}
# /SANDBOX-CLAUDE-BLOCK

emit() { # id subject decision reason
  jq -cn --arg id "$1" --arg s "$2" --arg d "$3" --arg r "$4" --arg ts "$TS" \
    '{id:$id,subject:$s,decision:$d,reason:$r,ts:$ts}' >> "$LEDGER"
}

# emit_beat <instance> <state> <what_happened> [id...] — one loops-library beat record
# (docs/architecture/features/loops-library.md §Beat record schema). `pulled_task_ids` is
# always an array in pull order; a beat that pulled nothing records `[]`, which is a different
# answer from a record that predates the field and consumers must not conflate them — so the
# key is written on every record, never omitted.
emit_beat() {
  local inst="$1" state="$2" what="$3"; shift 3
  local ids prev
  if [ "$#" -eq 0 ]; then ids='[]'; else ids="$(printf '%s\n' "$@" | jq -R . | jq -sc .)"; fi
  mkdir -p "$(dirname "$BEATS_FILE")" 2>/dev/null || true
  # `beat` is 1-based and monotonic per running instance — continue this instance's sequence.
  # Line-at-a-time fromjson so a corrupt line can never break numbering for the next beat.
  prev="$(jq -rR --arg i "$inst" 'fromjson? // empty | select(.instance == $i) | .beat // empty' \
            "$BEATS_FILE" 2>/dev/null | sort -n | tail -1)"
  jq -cn --arg loop autonomous-runner --arg i "$inst" --argjson b "$(( ${prev:-0} + 1 ))" \
         --arg ts "$TS" --arg st "$state" --arg w "$what" --argjson ids "$ids" \
    '{loop:$loop,instance:$i,beat:$b,timestamp:$ts,state:$st,what_happened:$w,
      pulled_task_ids:$ids,progress:{kind:"unbounded",remaining:null,total:null},
      escalations:[],next_wake:null}' >> "$BEATS_FILE"
}

plan_task() { # id subject -> "would-run <reason>" | "would-park <reason>"
  local id="$1" subj="$2"
  if [ "$PLAN" != "1" ]; then echo "would-run eligible"; return; fi
  local cb; cb="$(resolve_claude)"
  if [ -z "$cb" ]; then echo "would-run eligible (no claude; plan skipped)"; return; fi
  local prompt verdict
  prompt="You are the PLANNING step of an autonomous task runner in OBSERVE mode — make NO changes, only assess. Task ${id}: \"${subj}\". Can an agent complete this with NO human input, or does it need a human decision first (ambiguous scope, irreversible/risky action, a choice only the owner can make)? Reply with exactly one line: AUTODOABLE: <why> or NEEDSHUMAN: <what decision is needed>."
  verdict="$(printf '%s' "$prompt" | timeout 60 "$cb" -p --model haiku --allowedTools "Read,Grep,Glob" --output-format text 2>/dev/null)"
  case "$verdict" in
    NEEDSHUMAN:*) echo "would-park ${verdict#NEEDSHUMAN: }" ;;
    AUTODOABLE:*) echo "would-run ${verdict#AUTODOABLE: }" ;;
    *)            echo "would-run eligible (plan inconclusive)" ;;
  esac
}

# ════════════════════════════════ STAGE 1: OBSERVE ════════════════════════════
if [ "$MODE" = "observe" ]; then
  ELIG=0; RUN=0; PARK=0; EXCL=0; TAKEN=0
  while IFS= read -r t; do
    [ -z "$t" ] && continue
    id="$(echo "$t" | jq -r '.id // "?"')"; subj="$(echo "$t" | jq -r '.subject // ""')"
    status="$(echo "$t" | jq -r '.status // ""')"; execm="$(echo "$t" | jq -r '.execution // ""')"
    prio="$(echo "$t" | jq -r '.priority // ""')"; nblock="$(echo "$t" | jq -r '(.blocked_by // []) | length')"
    if [ "$status" != "pending" ];   then emit "$id" "$subj" excluded "not-pending ($status)"; EXCL=$((EXCL+1)); continue; fi
    if [ "$execm" != "autonomous" ]; then emit "$id" "$subj" excluded "not-autonomous (execution=$execm)"; EXCL=$((EXCL+1)); continue; fi
    if [ "$prio" = "P0" ];           then emit "$id" "$subj" excluded "p0 (never auto)"; EXCL=$((EXCL+1)); continue; fi
    if [ "$nblock" -gt 0 ];          then emit "$id" "$subj" excluded "blocked ($nblock blocker(s))"; EXCL=$((EXCL+1)); continue; fi
    ELIG=$((ELIG+1))
    if [ "$TAKEN" -ge "$MAX_TASKS" ]; then emit "$id" "$subj" excluded "cap (RUNNER_MAX_TASKS=$MAX_TASKS)"; EXCL=$((EXCL+1)); continue; fi
    read -r decision reason < <(plan_task "$id" "$subj")
    emit "$id" "$subj" "$decision" "$reason"; TAKEN=$((TAKEN+1))
    if [ "$decision" = "would-park" ]; then PARK=$((PARK+1)); else RUN=$((RUN+1)); fi
  done < <(echo "$TASKS_JSON" | jq -c '.[]' 2>/dev/null)
  echo "[autonomous-runner] mode=observe (OBSERVE — no changes made)"
  echo "[autonomous-runner] eligible=$ELIG  would-run=$RUN  would-park=$PARK  excluded=$EXCL  (cap=$MAX_TASKS)"
  echo "[autonomous-runner] ledger: $LEDGER"
  exit 0
fi

# ═══════════════════════ STAGE 2/3: per-task executor (run_task) ═══════════════
# Auto-generated files churn as a side effect of brana reads/writes (e.g. brana regenerates
# docs/spec-graph.json on any backlog query). They are never hand-edited, so their uncommitted
# churn is always safe to discard — do so before the clean check and before committing.
GENERATED="${RUNNER_GENERATED_FILES:-docs/spec-graph.json}"
drop_generated() { local gf; for gf in $GENERATED; do git checkout -- "$gf" 2>/dev/null || true; done; }

# resolve_base_branch — the per-project integration branch (ADR-060 Layer-2 policy).
# Precedence: RUNNER_BASE_BRANCH env → repo .claude/CLAUDE.md "integration=<b>" declaration → "dev".
# The concrete ref is resolved later (origin/<b> → local <b> → current HEAD with a loud warning),
# so the runner NEVER silently targets production.
resolve_base_branch() {
  if [ -n "${RUNNER_BASE_BRANCH:-}" ]; then echo "$RUNNER_BASE_BRANCH"; return; fi
  local decl
  decl="$(grep -oiE 'integration=[A-Za-z0-9._/-]+' .claude/CLAUDE.md 2>/dev/null | head -1 | cut -d= -f2)"
  if [ -n "$decl" ]; then echo "$decl"; return; fi
  echo "dev"
}

# cleanup_worktree <path> <branch> — remove an ephemeral worktree and its branch. The live
# working tree and the base branch are NEVER touched (that is the isolation boundary, ADR-060).
# t-3271 (ADR-090 §2): under --run-beat, N run_task children share ONE repo, and the git
# worktree ADMIN state (.git/worktrees entries, prune, branch refs) is the one thing they
# genuinely contend on — a `worktree prune` from one child can strip a sibling's
# half-registered entry. Serialize only those mutations; the builds themselves stay fully
# parallel, which is the whole point of the fan-out. At fan-out 1 this is an uncontended
# flock, so --run-one/--run-batch behaviour is unchanged.
WT_LOCK="${RUNNER_WT_LOCK:-${RUNNER_WORKTREE_DIR:-/tmp/brana-runner}/.worktree-admin.lock}"
git_wt() {
  mkdir -p "$(dirname "$WT_LOCK")" 2>/dev/null || true
  if command -v flock >/dev/null 2>&1; then ( flock 8; "$@" ) 8>"$WT_LOCK"; else "$@"; fi
}

cleanup_worktree() { git_wt _cleanup_worktree_locked "$1" "$2"; }
_cleanup_worktree_locked() {
  git worktree remove --force "$1" 2>/dev/null || rm -rf "$1" 2>/dev/null || true
  git worktree prune 2>/dev/null || true
  [ -n "$2" ] && git branch -D "$2" -q 2>/dev/null || true
}

park() { # id subj reason — record a needs-human question and leave the task pending
  emit "$1" "$2" would-park "$3"
  if [ "$FIXTURE_MODE" = "0" ] && command -v brana >/dev/null 2>&1; then
    # High priority + actionable: parked questions must surface above the medium-priority noise.
    brana remind write --text "Runner parked $1: $3" --action "brana backlog get $1" \
      --priority high --tags "runner-question,needs-human" --task-id "$1" --dedup-key "runner-$1" >/dev/null 2>&1 || true
    brana backlog set "$1" context "PARKED $(date -u +%F): $3" --append >/dev/null 2>&1 || true
  fi
  echo "[autonomous-runner] run-task: PARKED $1 — $3"
}

# run_task <task-json> — isolate in an EPHEMERAL WORKTREE off the integration branch, dispatch,
# verify, commit one task. STOPS (no merge, no completed-mark). The live working tree and the base
# branch are never touched. Returns: 0=ran, 2=parked (needs human), 1=failed (worktree removed).
run_task() {
  local TASK="$1" ID SUBJ DESC CTX DECISION REASON BASE_BRANCH BASE_REF FALLBACK WT BRANCH CB DPROMPT DOUT REASON_H gf
  ID="$(echo "$TASK" | jq -r '.id')"; SUBJ="$(echo "$TASK" | jq -r '.subject // ""')"
  DESC="$(echo "$TASK" | jq -r '.description // ""')"; CTX="$(echo "$TASK" | jq -r '.context // ""')"

  # Plan gate: only run a would-run; park a would-park (clean outcome, not a failure).
  read -r DECISION REASON < <(plan_task "$ID" "$SUBJ")
  if [ "$DECISION" = "would-park" ]; then park "$ID" "$SUBJ" "$REASON"; return 2; fi

  # Resolve the integration branch (ADR-060) and a concrete base ref. Prefer origin/<b>, then
  # local <b>; else fall back to current HEAD with a LOUD warning (never silently hit production).
  BASE_BRANCH="$(resolve_base_branch)"
  git fetch origin "$BASE_BRANCH" --quiet 2>/dev/null || true
  if git rev-parse --verify -q "refs/remotes/origin/$BASE_BRANCH" >/dev/null 2>&1; then
    BASE_REF="origin/$BASE_BRANCH"
  elif git rev-parse --verify -q "refs/heads/$BASE_BRANCH" >/dev/null 2>&1; then
    BASE_REF="$BASE_BRANCH"
  else
    FALLBACK="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)"
    echo "[autonomous-runner] WARN: integration branch '$BASE_BRANCH' not found — falling back to '$FALLBACK'. Set RUNNER_BASE_BRANCH or declare 'integration=<branch>' in .claude/CLAUDE.md." >&2
    BASE_REF="$FALLBACK"; BASE_BRANCH="$FALLBACK"
  fi

  BRANCH="${BRANCH_PREFIX}/${ID}"
  WT="${RUNNER_WORKTREE_DIR:-/tmp/brana-runner}/${ID}"
  # Stale-state hygiene: drop any leftover worktree/branch from a prior crashed run.
  cleanup_worktree "$WT" "$BRANCH"

  # Isolated worktree off the base ref — its own .git/index, parallel-safe, base untouched.
  if ! git_wt git worktree add -q "$WT" -b "$BRANCH" "$BASE_REF" 2>/dev/null; then
    emit "$ID" "$SUBJ" failed "could not create worktree off $BASE_REF"
    echo "[autonomous-runner] run-task: ABORT $ID — worktree add failed (base $BASE_REF)"; return 1
  fi
  # Pin the trusted gitlink NOW, before the executor ever touches the worktree (t-3256,
  # challenger finding). $WT/.git is a plain writable file inside the jail's rw bind — a
  # prompt-injected executor could redirect it at a fake git dir whose config (core.fsmonitor,
  # textconv, …) runs code on the HOST during any later `git -C "$WT"` call. We compare against
  # this snapshot after dispatch and refuse a tampered gitlink rather than run git through it.
  TRUSTED_GITLINK="$(cat "$WT/.git" 2>/dev/null)"

  CB="$(resolve_claude)"
  if [ -z "$CB" ]; then cleanup_worktree "$WT" "$BRANCH"; emit "$ID" "$SUBJ" failed "no claude binary"; return 1; fi
  DPROMPT="You are an autonomous worker completing ONE backlog task in a git repo. Follow the repo's conventions and make MINIMAL, focused changes for exactly this task — nothing else.

Task ${ID}: ${SUBJ}
${DESC:+Description: $DESC}
${CTX:+Context: $CTX}

If you can complete it, do the edits, then end with one line: DONE: <one-line summary>.
If it needs a human decision first (ambiguous, risky, owner's choice), make NO changes and end with: NEEDSHUMAN: <what decision is needed>."
  # Dispatch inside a bwrap capability jail (ADR-062): the worktree is the only writable
  # host path, inherited secrets are cleared (env -i), and ~/.config/brana et al. are absent.
  # The git worktree isolates tracked files; the jail isolates the OS process.
  DOUT="$(printf '%s' "$DPROMPT" | sandbox_claude "$WT" -p --allowedTools "Read,Write,Edit,Bash" --output-format text 2>/dev/null)"

  # Verify gate (all checks scoped to the worktree). NEEDSHUMAN → park; empty diff / validate fail → failed.
  if printf '%s' "$DOUT" | grep -q "NEEDSHUMAN:"; then
    REASON_H="$(printf '%s' "$DOUT" | sed -n 's/.*NEEDSHUMAN: *//p' | head -1)"
    cleanup_worktree "$WT" "$BRANCH"; park "$ID" "$SUBJ" "${REASON_H:-needs human decision}"; return 2
  fi
  # Gitlink-tamper guard (t-3256): a rewritten $WT/.git means an injection tried to point our
  # host-side git at attacker-controlled config — refuse before ANY `git -C "$WT"` runs below.
  if [ "$(cat "$WT/.git" 2>/dev/null)" != "$TRUSTED_GITLINK" ]; then
    cleanup_worktree "$WT" "$BRANCH"; emit "$ID" "$SUBJ" failed "worktree .git gitlink tampered — refusing (injection, t-3256)"
    echo "[autonomous-runner] run-task: FAILED $ID (gitlink tampered) — worktree removed, base '$BASE_BRANCH' pristine"; return 1
  fi
  if [ -z "$(git -C "$WT" status --porcelain 2>/dev/null)" ]; then
    cleanup_worktree "$WT" "$BRANCH"; emit "$ID" "$SUBJ" failed "no changes produced"
    echo "[autonomous-runner] run-task: FAILED $ID (no changes) — worktree removed, base '$BASE_BRANCH' pristine"; return 1
  fi
  # Trusted inspection gate (ADR-062 C2, t-3256). NEVER execute the worktree's own code as
  # the gate: it is executor-writable, so a prompt-injected task could plant a malicious
  # verify script and get host RCE (the git-hooks twin was already closed via --no-verify).
  # verify_diff reads the diff with trusted git only — no worktree code runs. It answers
  # "is this a sane, safe diff worth a human's review?"; correctness (tests/build) is the
  # human/CI job at PR review, since --run-batch never auto-merges.
  if ! verify_diff "$WT" "$BASE_REF"; then
    cleanup_worktree "$WT" "$BRANCH"; emit "$ID" "$SUBJ" failed "diff inspection failed"
    echo "[autonomous-runner] run-task: FAILED $ID (inspection) — worktree removed, base '$BASE_BRANCH' pristine"; return 1
  fi
  # Optional execution check (RUNNER_VALIDATE_CMD) — OFF by default. When set it runs the
  # worktree's command ON THE HOST, which is only safe for a trusted command or under an OS
  # sandbox (ADR-062, t-2173). Kept as an escape hatch, never the default.
  if [ -n "$VALIDATE_CMD" ]; then
    echo "[autonomous-runner] WARN: RUNNER_VALIDATE_CMD set — executing worktree code on the host ('$VALIDATE_CMD'). Safe only for a trusted command or a sandboxed runner (ADR-062)." >&2
    if ! ( cd "$WT" && eval "$VALIDATE_CMD" ) >/dev/null 2>&1; then
      cleanup_worktree "$WT" "$BRANCH"; emit "$ID" "$SUBJ" failed "verification failed ($VALIDATE_CMD)"
      echo "[autonomous-runner] run-task: FAILED $ID (validate) — worktree removed, base '$BASE_BRANCH' pristine"; return 1
    fi
  fi

  # Commit on the task branch (inside the worktree) — hooks run. Never merge, never mark completed.
  for gf in $GENERATED; do git -C "$WT" checkout -- "$gf" 2>/dev/null || true; done  # drop brana side-effect churn
  git -C "$WT" add -A
  # --no-verify (ADR-062 C2): never run the worktree's own .git/hooks on the host — a
  # prompt-injected agent could otherwise plant a malicious pre-commit and get host RCE.
  if ! git -C "$WT" commit -q --no-verify -m "feat(auto): ${SUBJ} (${ID})"; then
    cleanup_worktree "$WT" "$BRANCH"; emit "$ID" "$SUBJ" failed "commit rejected (hooks?)"; return 1
  fi
  # Report the gate that actually ran: inspection always; execution only when opted in (t-3256).
  GATE_DESC="inspected"; [ -n "$VALIDATE_CMD" ] && GATE_DESC="inspected + '$VALIDATE_CMD'"
  emit "$ID" "$SUBJ" ran "committed on $BRANCH ($GATE_DESC), awaiting human review"

  if [ "$PUSH" = "1" ] && command -v gh >/dev/null 2>&1; then
    git -C "$WT" push -u origin "$BRANCH" -q 2>/dev/null && \
      gh pr create --title "auto: ${SUBJ} (${ID})" --body "Autonomous runner. Task ${ID}. Gate: ${GATE_DESC} (inspection only — tests/build are the reviewer's job). Human review + merge required." --base "$BASE_BRANCH" >/dev/null 2>&1 \
      && echo "[autonomous-runner] run-task: PR opened for $ID (base $BASE_BRANCH)" \
      || echo "[autonomous-runner] run-task: committed but PR push failed — branch $BRANCH is local"
  fi
  if [ "$FIXTURE_MODE" = "0" ] && command -v brana >/dev/null 2>&1; then
    brana backlog set "$ID" context "RUNNER: committed on $BRANCH $(date -u +%F) off $BASE_BRANCH, awaiting human review+merge" --append >/dev/null 2>&1 || true
  fi
  # Remove the worktree; the branch is left (with its commit) for human review. Base never touched.
  cleanup_worktree "$WT" ""   # keep the branch, drop only the worktree
  echo "[autonomous-runner] run-task: DONE $ID — committed on '$BRANCH' (base '$BASE_BRANCH'), worktree removed, NOT merged. Human review required."
  return 0
}

# ════════════════════════════════ STAGE 2: RUN-ONE ════════════════════════════
if [ "$MODE" = "run-one" ]; then
  # Pick the first eligible task (jq preserves array order).
  TASK="$(echo "$TASKS_JSON" | jq -c '[.[] | select(.status=="pending" and .execution=="autonomous" and (.priority//"")!="P0" and ((.blocked_by//[])|length==0))] | .[0] // empty' 2>/dev/null)"
  if [ -z "$TASK" ]; then echo "[autonomous-runner] run-one: no eligible task — nothing to do"; exit 0; fi
  run_task "$TASK"; rc=$?
  [ "$rc" = "1" ] && exit 1 || exit 0   # ran/parked = clean (0); only true failure is non-zero
fi

# ═════════════ STAGE 4: RUN-BEAT — headless N-process fan-out (ADR-090) ═══════
# One beat of ONE draining wave at fan-out width N (ADR-090 §1/§2, t-3271).
#
# Pull: `brana backlog wave pull <wave> -n N` = N REAL sequential atomic pulls, each in its
# own lock_tasks critical section taking its own lease (t-3271's pull_wave_tasks_n) — not a
# simulation and not one batched claim. That matters here specifically: we fan out worktrees
# against these ids, so every id must already be leased, or a concurrent pump could hand the
# same task to a second executor.
#
# Dispatch: one `claude -p` per pulled id, each through the SAME run_task the single-task
# path uses — its own ephemeral worktree off the integration branch, its own bwrap jail, its
# own branch, its own inspection gate. ADR-090 §2 is explicit that this adds no new isolation
# primitive: the ADR-060 contract is invoked N times instead of once. The known gap it
# inherits N times over is the jail mounting no ~/.claude/projects (t-2516) — unchanged here.
#
# Never merges and never marks a task completed: the beat leaves N branches for the human
# merge valve (ADR-090 §4's batched digest), exactly as --run-one leaves one.
if [ "$MODE" = "run-beat" ]; then
  if [ -z "$WAVE_ID" ]; then
    echo "[autonomous-runner] run-beat: no wave — pass --wave <id> or set RUNNER_WAVE" >&2
    exit 1
  fi
  case "$FANOUT" in ''|*[!0-9]*)
    echo "[autonomous-runner] run-beat: RUNNER_FANOUT must be a positive integer (got '$FANOUT')" >&2
    exit 1 ;;
  esac
  if [ "$FANOUT" -lt 1 ]; then
    echo "[autonomous-runner] run-beat: RUNNER_FANOUT must be >= 1 (got $FANOUT)" >&2; exit 1
  fi
  # Kill-switch BEFORE the pull, not after: a beat that pulled and then aborted would leave
  # N tasks in_progress under live leases with no executor behind them.
  if [ -f "$KILL_SWITCH" ]; then
    echo "[autonomous-runner] run-beat: kill-switch present ($KILL_SWITCH) — aborting before any work"
    exit 0
  fi
  # Same non-blocking flock --run-batch uses: two overlapping beats on one repo would double
  # the real fan-out width the operator asked for.
  mkdir -p "$(dirname "$RUN_LOCK")" 2>/dev/null || true
  exec 9>"$RUN_LOCK" 2>/dev/null || true
  if command -v flock >/dev/null 2>&1 && ! flock -n 9; then
    echo "[autonomous-runner] run-beat: another run holds the lock ($RUN_LOCK) — exiting"; exit 0
  fi

  PULL_ARGS=(backlog wave pull "$WAVE_ID" -n "$FANOUT" --claimant "$CLAIMANT")
  [ -n "${RUNNER_TASKS_FILE:-}" ] && PULL_ARGS+=(--file "$RUNNER_TASKS_FILE")
  # Keep the CLI's stderr: a beat that fails PARTWAY through has already claimed tasks, and
  # `pull_wave_tasks_n` names them in its error precisely so they are not silently orphaned
  # in_progress under a live lease. Swallowing it would turn a reclaimable failure into an
  # invisible one — so surface the CLI's own message rather than asserting nothing happened.
  PULL_ERR="$(mktemp "${TMPDIR:-/tmp}/brana-beat-pullerr-XXXXXX")"
  if ! PULL_OUT="$("$BRANA_BIN" "${PULL_ARGS[@]}" 2>"$PULL_ERR")"; then
    echo "[autonomous-runner] run-beat: wave pull failed for $WAVE_ID — no executor dispatched." >&2
    echo "[autonomous-runner] run-beat: any task the CLI names below was CLAIMED before the failure and needs acking or reclaiming:" >&2
    sed 's/^/  /' "$PULL_ERR" >&2
    rm -f "$PULL_ERR"
    exit 1
  fi
  rm -f "$PULL_ERR"
  # n=1 keeps the single-pull output shape ({"pulled": id|null}); n>1 reports the array plus
  # a `stopped` reason. Accept both so RUNNER_FANOUT=1 needs no special case.
  BEAT_IDS="$(printf '%s' "$PULL_OUT" | jq -r '(.pulled_task_ids // [.pulled]) | map(select(. != null)) | .[]' 2>/dev/null)"
  BEAT_STOP="$(printf '%s' "$PULL_OUT" | jq -r '.stopped // (if .at_limit then "at_limit" elif .none_eligible then "none_eligible" else "reached_n" end)' 2>/dev/null)"
  if [ -z "$BEAT_IDS" ]; then
    emit_beat "$WAVE_ID" empty "wave $WAVE_ID claimed nothing (stopped=${BEAT_STOP:-unknown})"
    echo "[autonomous-runner] run-beat: ALLDONE — wave $WAVE_ID claimed nothing (stopped=${BEAT_STOP:-unknown})"
    echo "[autonomous-runner] ledger: $LEDGER"
    exit 0
  fi

  # Resolve a pulled id to its task object. The pull just flipped these to in_progress, so
  # the top-of-script pending query never contains them — read each one directly.
  beat_task_json() {
    if [ -n "${RUNNER_TASKS_JSON:-}" ]; then
      printf '%s' "$TASKS_JSON" | jq -c --arg id "$1" '.[] | select(.id==$id)' 2>/dev/null | head -1
    else
      "$BRANA_BIN" backlog get "$1" 2>/dev/null | jq -c '.' 2>/dev/null
    fi
  }

  BEATDIR="$(mktemp -d "${TMPDIR:-/tmp}/brana-runner-beat-XXXXXX")"
  BEAT_PIDS=(); BEAT_DIDS=()
  for BID in $BEAT_IDS; do
    BTASK="$(beat_task_json "$BID")"
    if [ -z "$BTASK" ]; then
      # Claimed but unreadable: say so loudly — the task is in_progress under a live lease
      # with no executor, which is the reclaimer's problem, not a silent skip.
      emit "$BID" "" failed "pulled but not readable — in_progress under a live lease, needs acking or reclaiming"
      echo "[autonomous-runner] run-beat: WARN $BID pulled but not readable — left claimed, needs reclaiming" >&2
      continue
    fi
    # Per-child output is buffered to a file and replayed in pull order, so N interleaved
    # run_task logs stay readable.
    run_task "$BTASK" >"$BEATDIR/$BID.log" 2>&1 &
    BEAT_PIDS+=("$!"); BEAT_DIDS+=("$BID")
  done

  RAN=0; PARKED=0; FAILED=0
  if [ "${#BEAT_PIDS[@]}" -gt 0 ]; then
    for i in "${!BEAT_PIDS[@]}"; do
      wait "${BEAT_PIDS[$i]}"; rc=$?
      cat "$BEATDIR/${BEAT_DIDS[$i]}.log" 2>/dev/null
      case "$rc" in
        0) RAN=$((RAN+1)) ;;
        2) PARKED=$((PARKED+1)) ;;
        *) FAILED=$((FAILED+1)) ;;
      esac
    done
  fi
  rm -rf "$BEATDIR"
  # The beat record is what lets both digests present these N close-outs as ONE review item
  # instead of N unrelated ones (ADR-090 §4). Every id the beat CLAIMED goes in, including any
  # that failed to dispatch — they are in_progress under this beat's lease either way, so the
  # digest must still show them as this beat's.
  emit_beat "$WAVE_ID" active \
    "fan-out $FANOUT: dispatched ${#BEAT_PIDS[@]}, ran $RAN, parked $PARKED, failed $FAILED (stopped=${BEAT_STOP:-unknown})" \
    $BEAT_IDS
  echo "[autonomous-runner] run-beat: wave=$WAVE_ID fanout=$FANOUT dispatched=${#BEAT_PIDS[@]} ran=$RAN parked=$PARKED failed=$FAILED (pull stopped=${BEAT_STOP:-unknown})"
  echo "[autonomous-runner] run-beat: NOT merged — each task sits on its own branch awaiting human review."
  echo "[autonomous-runner] ledger: $LEDGER"
  exit 0
fi

# ════════════════════════════════ STAGE 3: RUN-BATCH ══════════════════════════
# Loop run_task over a snapshot of eligible tasks (run_task leaves each pending, so we
# iterate the snapshot rather than re-pick first — avoids re-running the same task forever).
if [ -f "$KILL_SWITCH" ]; then
  echo "[autonomous-runner] run-batch: kill-switch present ($KILL_SWITCH) — aborting before any work"; exit 0
fi
# Concurrency lock (t-2144): a non-blocking flock serializes batch runs — a second overlapping
# --run-batch exits cleanly rather than double-running a task (run_task leaves tasks pending, so
# two batches over the same snapshot would otherwise both pick it). Released on process exit.
mkdir -p "$(dirname "$RUN_LOCK")" 2>/dev/null || true
exec 9>"$RUN_LOCK" 2>/dev/null || true
if command -v flock >/dev/null 2>&1 && ! flock -n 9; then
  echo "[autonomous-runner] run-batch: another batch holds the lock ($RUN_LOCK) — exiting"; exit 0
fi
ATTEMPTED=0; RAN=0; PARKED=0; FAILED=0; CONSEC=0
while IFS= read -r TASK; do
  [ -z "$TASK" ] && continue
  [ "$ATTEMPTED" -ge "$MAX_TASKS" ] && break
  if [ -f "$KILL_SWITCH" ]; then echo "[autonomous-runner] run-batch: kill-switch tripped mid-batch — stopping"; break; fi
  run_task "$TASK"; rc=$?
  ATTEMPTED=$((ATTEMPTED+1))
  case "$rc" in
    0) RAN=$((RAN+1));    CONSEC=0 ;;
    2) PARKED=$((PARKED+1)); CONSEC=0 ;;
    *) FAILED=$((FAILED+1)); CONSEC=$((CONSEC+1)) ;;
  esac
  if [ "$CONSEC" -ge "$MAX_FAILS" ]; then
    echo "[autonomous-runner] run-batch: KILL — $CONSEC consecutive failures (ADR-050 cap=$MAX_FAILS)"; break
  fi
done < <(echo "$TASKS_JSON" | jq -c '[.[] | select(.status=="pending" and .execution=="autonomous" and (.priority//"")!="P0" and ((.blocked_by//[])|length==0))] | .[]' 2>/dev/null)

if [ "$ATTEMPTED" = "0" ]; then echo "[autonomous-runner] run-batch: ALLDONE — no eligible tasks"; fi
echo "[autonomous-runner] run-batch: attempted=$ATTEMPTED ran=$RAN parked=$PARKED failed=$FAILED (cap=$MAX_TASKS, kill-at=$MAX_FAILS)"
echo "[autonomous-runner] ledger: $LEDGER"
exit 0
