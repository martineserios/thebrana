# Feature Spec — Autonomous Task Runner

**Task:** t-2140 · **Status:** Stages 1-3 built + worktree isolation (t-2146, ADR-060) · Stage 4 = t-2142 · **Date:** 2026-06-20
**Basis:** ADR-059 (substrate selection) · [substrate-leverage-audit](../../research/substrate-leverage-audit.md) · ADR-050 (autonomy caps) · [ADR-060](../decisions/ADR-060-branch-strategy-autonomous-agents.md) (branch strategy: agents cut from `dev` in ephemeral worktrees, PR to `dev`, human promotes `dev`→`main`)

## Problem

brana needs an autonomous tier — "keep working through the backlog until done / overnight." The substrate audit settled the *how*: **native `/loop + claude -p` over the backlog**, not ruflo (autopilot/`--claude`/MCP are redundant or hollow under subscription). This spec defines a *safe, staged* runner that integrates with existing brana machinery instead of reinventing it.

## Principles

1. **Native only.** Zero ruflo execution. (`backlog execute` is ruflo-FIRST and would silently under-execute on the subscription — so the runner is a thin native loop, not a wrapper around it.)
2. **Autonomy earns write access — it isn't granted.** Roll out in trust-earning stages; give write access last.
3. **Defer, don't guess or halt.** When a task needs a human-only decision, park a question and continue with other tasks.
4. **Reuse the system.** Lean on existing hooks, gates, and CLI; add only the thin delta.

## Decisions (locked)

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Eligibility | `execution: autonomous` **+ not P0** + unblocked + lint-clean | Default-deny, whitelist-in. Reach expands later via learning (t-2142). |
| Output | branch + PR per task; **human merges** | ADR-050 (merges human-gated); isolated, revertable, reviewable units. |
| Shared state | **native only** — backlog + ledger files | Minimal dependencies; no ruflo coupling. |
| Verification | `validate.sh` **+ AC check** (build-evaluator vs task `AC:` lines) | Catches "ran but did the wrong thing", not just structural breakage. |
| Failure policy | consecutive-failure **kill at 3** (ADR-050 cap), per-task timeout, batch cap, cost ceiling | Bounded blast radius. |

## Staged rollout (the safety backbone)

```
Stage 0  DESIGN (this spec)
Stage 1  OBSERVE-ONLY   ← picks eligible tasks, PLANS per task, reports would-run /
                          would-park / excluded. ZERO mutations. You watch its judgment.   ← THIS BUILD
Stage 2  SINGLE-TASK    ← runs ONE eligible task → PR → stops. Human reviews.   ← BUILT
Stage 3  BOUNDED BATCH  ← many tasks/run, all bounds + kill-switch, PR-per-task. ← BUILT
Stage 4  LEARNED        ← graduates task shapes to auto-eligible from track record. (t-2142)
```

Each stage is gated by the prior earning trust. Stage 1 proves *judgment* (right task pick, right done-vs-park call) **before** the runner can touch a file.

## Reuse map (free, already in brana)

| Need | Reuse |
|------|-------|
| Loop template | `system/scripts/feed-summarize.sh` pattern (cap, `timeout claude -p`, per-item skip) |
| Eligibility gate | `brana backlog lint` + `execution: autonomous` marker |
| Quality gate | `validate.sh` (non-zero = task failed) — Stage 2+ |
| Question queue | `brana remind write --tags "runner-question,needs-human" --task-id t-NNN` — Stage 2+ |
| Commit safety | existing hooks (attribution, secrets, budget, doc-gate, branch-guard) — automatic |
| Scheduling | `brana ops` job — Stage 3+ |
| Governance | ADR-050 caps |

## Stage 1 — Observe-only (this build)

`system/scripts/autonomous-runner.sh --observe`

**Does:** load pending tasks → filter to eligible (`execution:autonomous` ∧ `priority≠P0` ∧ unblocked) → cap to `RUNNER_MAX_TASKS` → per task, emit a planned **decision** (`would-run` / `would-park` / `excluded:<reason>`) to a JSONL **ledger** → print a summary.

**Must NOT (observe invariant):** no `brana backlog set`, no `git` writes, no `brana remind write`, no edits to the repo or tasks.json. Read + ledger-write only.

**Interfaces / env (for testability + ops):**
- `RUNNER_TASKS_JSON` — task source override (test fixture); default `brana backlog query --status pending --output json`
- `RUNNER_MAX_TASKS` — batch cap (default 5)
- `RUNNER_LEDGER` — ledger output path (default under `~/.claude/scheduler/`)
- `RUNNER_PLAN` (0/1) — whether to call `claude -p` for per-task planning (default 1); `CLAUDE_BIN` overridable for tests
- exit 0 always on a clean observe pass (it's read-only)

**Eligibility (exact):** `status == "pending"` ∧ `execution == "autonomous"` ∧ `priority != "P0"` ∧ (`blocked_by` empty/null). Everything else → `excluded:<reason>`.

## Testing

`system/scripts/tests/test-autonomous-runner.sh` (TDD — written first):
- eligible task → `would-run`
- P0-autonomous → `excluded:p0`
- blocked-autonomous → `excluded:blocked`
- non-autonomous → `excluded:not-autonomous`
- `RUNNER_MAX_TASKS` cap respected
- **observe invariant:** task source unchanged, no reminder file written, no git mutation

Runs with `RUNNER_PLAN=0` (no `claude` call) for a hermetic, fast test.

## Stage 2 — Single-task supervised (this build)

`system/scripts/autonomous-runner.sh --run-one`

**Does:** select the **first** eligible `would-run` task (cap 1) → isolate on a per-task branch → dispatch `claude -p` (scoped `Read,Write,Edit,Bash`, build-discipline prompt) to do the work → **verify** → commit on the branch → **stop**. Never merges (ADR-050: human-gated). Never marks the task `completed` (human gates that too — runner leaves it for review).

**Verification gate (all must hold to commit):**
1. dispatch did not return `NEEDSHUMAN:` (else park + abort, no commit),
2. the working tree actually changed (empty diff = nothing done → abort),
3. `RUNNER_VALIDATE_CMD` (default `./validate.sh`) passes,
4. (best-effort) AC check if the task has `AC:` lines.

**Worktree isolation (t-2146, ADR-060):** `run_task` no longer touches the live working tree. It
resolves the integration branch (`RUNNER_BASE_BRANCH` → `.claude/CLAUDE.md` `integration=` → `dev` →
current HEAD with a loud warning), then cuts an **ephemeral worktree** off that base
(`git worktree add … origin/<base>`), does all dispatch/verify/commit *inside* it, opens the PR with
`--base <integration>`, and removes the worktree on every exit. This contains blast radius (live tree +
base never modified), enables parallel agents (separate `.git/index`), and **resolves the detached-HEAD
bug by construction** — the base is explicit, never derived from `git branch --show-current`.

**Failure invariant (the critical safety property):** on *any* failure — `NEEDSHUMAN`, empty diff, validate fail, dispatch error — the runner **removes the ephemeral worktree and its branch.** No partial commits; the live tree and base branch are never touched.

**Output:** a commit on `RUNNER_BRANCH_PREFIX/<id>` (default `runner/auto/<id>`). With `RUNNER_PUSH=1` it also opens a PR via `gh`. Default is local-branch-only (no remote needed).

**Env (adds to Stage 1):** `RUNNER_VALIDATE_CMD` · `RUNNER_PUSH` (0/1) · `RUNNER_BRANCH_PREFIX`. brana mutations (remind/set) are skipped when `RUNNER_TASKS_JSON` is set (fixture/test mode) — keeps tests hermetic.

**Tests** (`test-autonomous-runner-stage2.sh`, hermetic temp git repo, stub claude + stub validate):
- would-run task → change made, validate passes → commit exists on task branch, base branch has no new commit, task not `completed`
- stub returns `NEEDSHUMAN` → no commit, base branch pristine, branch deleted
- stub makes no change → no commit, clean abort
- validate fails → working tree reverted, no commit, back on base branch
- would-park task → not executed at all

## Stage 3 — Bounded batch (this build)

`system/scripts/autonomous-runner.sh --run-batch`

**Does:** snapshot the eligible set (same predicate as Stage 1/2), then loop the Stage 2
executor (`run_task`) over it — each task on its own `runner/auto/<id>` branch, verified
and committed, base left pristine. Iterates the *snapshot* (not "re-pick first") because
`run_task` leaves tasks `pending` (human gates completion) — re-picking would re-run the
same task forever.

**Bounds (all enforced):**
- **Batch cap** — `RUNNER_MAX_TASKS` (default 5) attempts per run.
- **Consecutive-failure kill** — stop after `RUNNER_MAX_FAILS` (default 3) failures in a row (ADR-050 cap). Parks and successes reset the counter; only real failures (empty diff, validate fail, dispatch/commit error) count.
- **Kill-switch** — abort before any work, or between tasks mid-batch, if `RUNNER_KILL_SWITCH` (default `~/.claude/scheduler/runner.stop`) exists. External `touch` halts a running batch cleanly.
- **Per-task timeout** — inherited from `run_task` (600s dispatch).

**Outcomes per task** (`run_task` return → ledger decision): `ran` / `would-park` / `failed`.
Failures emit a `failed` ledger row (Stage 2 only echoed) so the batch can count toward the
kill threshold and the run is auditable. `ALLDONE` is reported when nothing is eligible.

**Question queue (needs-human):** parks write a **high-priority, actionable** reminder
(`--priority high --action "brana backlog get <id>" --tags runner-question,needs-human`) so
they surface above the medium-priority noise, plus a `PARKED` note on the task context.

**`brana ops` host:** a disabled, `--observe` scheduler job (`autonomous-runner` in
`system/scheduler/scheduler.template.json`). Default-deny — the operator sets `enabled=true`
and switches `--observe`→`--run-batch` to grant autonomy; bounds + kill-switch apply.

**Tests** (`test-autonomous-runner-stage3.sh`, hermetic temp repo + stub claude): batch runs
N tasks on N branches (base pristine); `RUNNER_MAX_TASKS` cap respected; 3-consecutive-fail
kill stops the batch (4th never attempted); kill-switch file aborts; `ALLDONE` on empty
backlog; mid-batch `NEEDSHUMAN` parks without counting as a failure.

## Capability isolation (the OS boundary) — t-2173, ADR-062

A git worktree isolates *tracked files in a checkout*, not the *OS process*. The executor
(`claude -p --allowedTools "Read,Write,Edit,Bash"`) has **unscoped Bash**, so any side
effect that never lands as a tracked file — network egress, `$HOME` writes, reads of
`~/.config/brana/*.env`, `rm`, `git push` — is invisible to every gate (`git status`,
`validate.sh`, `git add -A`, human review). With backlog task text flowing into the prompt,
that is the **Lethal Trifecta** (private data + untrusted input + external comms). Containment
must live at the **capability layer**, not the git layer. Filtering (denylist/allowlist) is
bypassable and is kept only as a tripwire — see [ADR-062](../decisions/ADR-062-runner-executor-sandbox.md).

**Mechanism — bubblewrap jail** (`sandbox_claude()` in `autonomous-runner.sh`), wrapping the
dispatch (spike-validated 2026-06-21):

- **Minimal `--ro-bind` list (never `/`)** → `~/.config/brana/*.env`, `~/.ssh`, `~/.aws`,
  other users' files are *absent* from the jail.
- **`env -i`** → inherited env secrets (`LINEAR_API_KEY`, …) cleared.
- **Writable tmpfs HOME** with claude's creds ro-bound inside → auth works; the worktree is
  the only writable host path.
- **rlimits via inner `ulimit`** (bwrap 0.11.1 has no `--rlimit-*` flags) → fork-bomb / disk-fill contained.
- **`git commit --no-verify`** → the worktree's own `.git/hooks` never execute on the host.

**Controls.** `RUNNER_SANDBOX=1` (default on). Set `RUNNER_SANDBOX=0` only for stub-driven
orchestration tests or environments without user namespaces — the runner then warns loudly
and runs unsandboxed. `RUNNER_DISPATCH_TIMEOUT` (default 600) bounds the jailed run.

**The boundary is machine-checked.** `validate.sh` Check 61 runs the escape battery
(`test-autonomous-runner-sandbox.sh`): a prompt-injected stub attempts secret-read, env-leak,
and host writes; the test fails LOUDLY if any succeeds. This is the load-bearing mitigation
for the top risk — an operator loosening the jail under compatibility friction is caught on
the next validate, not six months later.

**Known gap (tracked).** **Network egress is not yet restricted** — the spike used the shared
host net namespace, so the executor can still reach arbitrary hosts. The egress allowlist
(`--unshare-net` + slirp4netns/proxy to `api.anthropic.com:443`, or an nftables filter) is the
remaining Layer-1 item. **Until it lands, do not run `--run-batch` unattended on untrusted
tasks** — keep the scheduler job default-deny (`brana orbit` in `observe`). The OBSERVE
planner (line ~80, tools `Read,Grep,Glob` only — no Bash/network leg) is lower risk and its
sandboxing is deferred with the egress work.

## Follow-ups

- t-2142 (learned eligibility) — Stage 4.
- Wire the leverage doctrine into `delegation-routing.md` (done — ADR-059 rewrite).
- **t-2173 remaining:** egress allowlist (the open Layer-1 item), validate-from-base-ref copy
  (ADR-062 C2 — the second half, prevents host exec via a written `validate.sh`), sandbox the
  OBSERVE planner, and the compatibility soak (real rust/shell/python tasks).
