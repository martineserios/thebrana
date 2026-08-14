---
title: Loop-First Operation of thebrana
status: draft
created: 2026-08-13
informs: [docs/ideas/loops-library.md]
---
# Loop-First Operation of thebrana

> Brainstormed 2026-08-13. Status: draft — shaped, probed, externally validated.
>
> **Descendants of this approach** (this doc is the philosophy; these carry it forward):
> [loops-library.md](loops-library.md) — the catalog born from this approach: entry schema,
> queue types, the five-verb pull interface, leases. · ADR-079 + the backlog-drain epic
> (t-2811, delivered 2026-08-13) — the substrate the loops pump against: waves, `ac approve`
> valve, atomic `wave pull`, `docs/guide/workflows/drain-loop.md` (first committed loop,
> proven live over 8 beats). · t-2828 — plan-time wave graphs + epic-level runner.

## Shape summary

**Problem:** loop-native architecture decided 2026-06-11, prerequisites all
completed, but no loop ever ran; harness grew to 40 skills; human remained the
dispatcher; 5 branches sit unmerged.
**Solution:** loops as thin schedulers driving *existing* skills over durable
queues (branches, inbox, backlog, docs), with a graduated autonomy ladder
(L0 Reporter → L1 Preparer → L2 trivially-safe Merger → L3) promoted by
evidence (5 clean runs), never assumed. Redesign follows observed loop
failures, not upfront design.
**Success:** unmerged queue ≤2 sustained · inbox drained weekly unprompted ·
≥1 loop promoted L1→L2 by rule · user stops manually triggering maintenance
skills.

**Loop roster, wave 1:**
1. `babysit-dev` — L1 Preparer, 30–60m: rebase+test inactive clean branches,
   mark ready; human merges. Guards: skip <24h-active, skip dirty worktrees.
2. `drain-inbox` — L1: process queued inbox items; outputs land on branches
   behind the same review gate (shared cap).
3. `cleanup` — closer loop, daily: delete merged branches/worktrees.
Graduation target: t-1994 foreman, once wave-1 promotion evidence exists.

**Design rules (probe-derived):** dedicated lean loop sessions (~100× cheaper
than piggybacking; cache-read ≈ context size) · 30m+ cadence on subscription ·
cheap no-op preflight opens every beat · producers open ≤ review rate; every
producer paired with a closer · termination = durable state change only.

### Second-order effects
- babysit-dev → merge throughput rises → untended branches rot faster relative
  to a faster dev → **the loop roster becomes the de-facto prioritization
  mechanism**; staleness becomes a kill/keep signal (t-2173-class).
- drain-inbox → visible queue empties → output shifts to the less-visible
  branch-review queue → without the shared cap it relocates pileup, not
  resolves it.

### Engineering disciplines
- **DDD:** ADR "Graduated loop autonomy" (ladder, promotion rules, guards) —
  extends ADR-050/ADR-059.
- **TDD:** guard logic as testable bash (active-branch, dirty-worktree,
  safe-class classifier) before any unattended run.
- **SDD:** update loop-native research doc + `docs/guide/workflows/branching.md`.
- **Docs:** tech doc `docs/architecture/features/loop-first-operation.md` +
  user-guide loop-roster entry + `docs/README.md` index.

## Seed

Adopt Boris Cherny's loop-engineering stance for thebrana: make `/loop` the key
command, and prefer **creating loops over writing new harness components**
(skills/hooks). Scope chosen: full redesign through the loop lens, weeks+
investment. Success = user's role shifts to writing loops; autonomous backlog
throughput; validated learning. Constraint: subscription budget only.

## Source

Boris Cherny (creator of Claude Code), Acquired Unplugged, 2026-06-02:

> "I don't prompt Claude anymore. I have loops that are running. They're the
> ones that are prompting Claude and kind of figuring out what to do. My job is
> to write loops."

Loop-engineering frame (karanbansal.in/blog/loop-engineering):
- Hierarchy: code → prompting agents → **writing loops that prompt agents**
- Loop = **trigger + committed prompt file + termination check the agent can't game**
- "The repo is the memory; the agent forgets"
- Verification/termination is "the whole game" — honor-system tags are the weak
  end; stop-hooks that run real commands and fresh-context verifier agents are
  the strong end.

## Prior art in thebrana (not starting from zero)

- Loop-native redesign is the **active architecture direction since 2026-06-11**
  (challenger-approved): backlog = work source, `/loop` = foreman, `Workflow` = crew.
- ADR-059 picked native `/loop + claude -p` as the autonomous tier (validated
  probe: 4 iterations, correct pick, self-halt, $0.18).
- **Key evidence (2026-08-13):** all four prerequisites of the foreman DAG are
  completed (t-1991 rehearsal, t-1992 step-state ADR, t-1993 pending-questions
  ADR, t-1981 backlog lint, t-1982 autonomous validation) — but **t-1994, the
  foreman loop itself, is still pending** after ~2 months. The runway got built;
  no loop ever ran on it.
- Meanwhile the harness kept growing: 40 skills (some 23–37K tokens), hooks,
  step registries, guided-execution protocols.

## Discussion outcomes

**Round 1 — order inversion accepted.** Challenge: "weeks-long redesign is more
preparation work — the same failure mode that left t-1994 pending for 2 months
while its prerequisites all completed." User accepted: **loop first, redesign
after.** Real loop failures drive what gets redesigned, not upfront design.

**Round 1b — entry shape.** Chosen: **B then A** — 1-2 narrow single-purpose
loops with trivially verifiable termination (e.g. doc-drift: `validate.sh` exits
0; worktree/branch cleanup; backlog lint) to learn failure modes cheaply, then
start the t-1994 foreman with that evidence.

**Round 2 — devil's advocate resolved by research.** Counter-position ("loops
only fit code with objective oracles; brana's judgment work can't have
ungameable termination") was **refuted by evidence of Cherny's actual loops**:
`/loop 5m /babysit` (shepherd PRs), `/loop 30m /slack-feedback`,
`/loop /post-merge-sweeper`, `/loop 1h /pr-pruner`, plus fleets of triage agents
over GitHub/Slack/Twitter. Three corrections to the meme:

1. **Every Cherny loop invokes a slash command he wrote.** Loops are thin
   schedulers driving skills — the harness stayed; the human-as-dispatcher went
   away. He still grows CLAUDE.md/skills when Claude repeats mistakes.
2. **Termination ≠ ungameable tests.** His trick is durable external state as
   the queue (PRs, Slack) + a human gate downstream (he merges). Empty queue →
   beat no-ops. Judgment work IS loopable when output lands behind a review gate.
3. **Brana translation:** not "loops instead of skills" — *every skill that
   operates on queue-like durable state gets a loop wrapper*; the user's role
   moves from invoking skills to reviewing outputs. Brana's queues already
   exist: backlog, dev-branch PRs, `inbox/`, doc drift, memory hygiene, feed.

**Cost caveat (own memory, CC #54086):** looping a slash command re-fires full
cost each beat. Cherny runs 5-min cadences on Anthropic's budget; on
subscription, every loop needs a cheap "queue empty?" preflight that no-ops fast.

## Validation research (2026-08-13, pre-save)

- **Babysit loops are proven and public**: Cherny's thread (x.com/bcherny/status/2038454341884154269 — "/loop and /schedule… up to a week"); implementations: tilomitra `/babysit-pr` gist, pstack `babysit` port, solberg.is/babysit-pr writeup. Their converged design independently validates our probe-derived guards: **triage step (judgment per finding, never blind-fix)** · **rebase only on real conflicts, no gratuitous force-push** · **adaptive cadence (back off when queue quiet)**. Ours swaps GitHub PRs for dev-branch worktrees; skeleton transfers.
- **Dedicated lean loop sessions = persistent tmux on the workstation/server** (standard pattern, documented). Caveat: on 5-hour-window exhaustion the session pauses awaiting "continue" (CC #35744) — wave-1 loops fail safe (queue waits), acceptable.

## Risks

Pre-mortem (2026-08-13), both mitigations designed in from day one:

- **A — Quota starvation:** loops silently eat the subscription 5-hour window;
  interactive work throttles; loops get disabled and never re-enabled.
  *Mitigation:* cheap no-op preflight per beat; off-peak/slow cadences;
  per-loop beat budget.
- **B — Review pileup:** loops open branches/PRs/docs faster than the human
  gate reviews them; trust erodes; regression to manual. *Mitigation:* cap
  concurrent open outputs per loop; pair every producer loop with a closer loop
  (pr-pruner pattern — loops that CLOSE work count as much as loops that open it).

## Pipeline framing (2026-08-13 — the system vocabulary)

User insight during review: "it's a flow — you can play with processes, steps,
pipeline ideas." Loops don't stand alone; they compose. Brana becomes **a
pipeline of durable stores with pumps between them**, described by four
primitives:

| Primitive | Definition | Instances |
|---|---|---|
| **Queue** | durable state holding work | `inbox/`, branches, backlog, waves, `ready/*` |
| **Pump** | a loop moving work one stage forward | drain-inbox, babysit-dev, cleanup, (later) foreman |
| **Valve** | a human gate between stages | AC approval (`ac_state`), you merging |
| **Gauge** | a readout on a queue or on the pumps | L0 digest, `brana ops status` line, watchdog |

```
inbox/ ──▶ backlog tasks ──▶ branches ──▶ ready/* ──▶ merged ──▶ (cleanup)
  PUMP:       VALVE:            PUMP:        VALVE:      PUMP:
  drain-inbox ac approve        babysit-dev  YOU MERGE   cleanup
  (opt-in)    (t-2811!)         prep only
```

**Key consequences:**

- **t-2811 (backlog-drain) and this plan are two halves of one pipeline.**
  t-2811/ADR-079 built the front half (waves = named queue segments,
  `ac_state` = the proposed→approved valve). This plan builds the back half
  (prepare → review → merge → clean). The foreman is the middle pump both
  point at; highest risk, so it ships last.
- **Backpressure replaces coordination.** ready-cap full (5) → upstream pumps
  no-op automatically; drain-inbox outputs count against the same cap. Loops
  never talk to each other — they coordinate through queue levels (kanban).
  Today's 5-unmerged-branches state is precisely a pipeline with no
  backpressure.
- **Autonomy levels are routing decisions, not smarter agents.** L2 = opening
  a bypass valve on a `ready-trivial/*` pipe only; the human valve stays on
  everything else.
- **Every stage needs an explicit "no" path (dead-letter queue).** Rejected
  ready-branches flow to `rejected/*` with their own tiny closer pump —
  answers the challenger's "rejected branch is invisible to all guards"
  finding; also the root cause of 160-day stale tasks.
- **The watchdog is a gauge on the pumps themselves** — one meta-gauge covers
  every current and future loop automatically.
- Cherny's "my job is to write loops" = **the human's job becomes pipeline
  design** (stages, valve placement, pipe widths); agents do the pumping.

The ADR (t-2821 in the proposed plan) should adopt queue/pump/valve/gauge/
backpressure as the design vocabulary for every future loop.

## Framings ledger — same system, different lenses (food for the future)

Each framing made something visible the others missed. Keep all of them; pick
the lens that fits the question at hand.

| Framing | What it reveals | What it hides |
|---|---|---|
| **Cherny/scheduler** ("loops drive skills; human stops being the trigger") | the role shift; loops ≠ replacement for harness | safety gates, cost model |
| **Restaurant/prep-cook** (loops as staff earning trust) | the autonomy ladder; promotion-by-evidence; "nobody starts with the credit card" | composition between loops |
| **Pipeline/plumbing** (queues, pumps, valves, gauges, backpressure) | composition, t-2811 as the other half, dead-letter paths, caps as backpressure | per-loop internals, guard details |
| **Factory/kanban** (backlog = work source, foreman/crew) | the original 2026-06-11 architecture; where the foreman fits; why it goes last | why the foreman stalled (human factors) |
| **Challenger lenses** (convergent/systems/critical) | secrets in inbox, RCE gate, lifecycle darkness, TOCTOU, quota accumulation | the value/opportunity side |
| **Pre-mortem** (imagine it failed) | quota starvation & review pileup as the two death modes | slow-burn failure (framings above caught those) |

Method note worth keeping: **deliberately re-describing the system in a new
vocabulary is a cheap generator of design insight** — the pipeline reframe
alone produced backpressure, dead-letter queues, and autonomy-as-routing in
minutes, none of which the first three framings surfaced.

## Proposed backlog plan — MATERIALIZED (reconcile snapshot 2026-08-14)

> **Stale-marker fix:** this section was drafted as "pending user approval — not yet
> written". It has since been written: epic **t-2820 loop-first** exists with children
> (t-2823 merge-radar L0 **shipped**, t-2825, t-2826 loops-library), in parallel with the
> **t-2811 backlog-drain epic (delivered 2026-08-13)** — waves, `ac approve`, `wip_limit`,
> atomic `wave pull`, and the committed drain-loop runbook, built via the first live
> supervised `/loop` (8 beats). Follow-ons: t-2827 (approve-denial hardening), **t-2828
> (plan-time wave graphs + epic runner) — which owns reconciling the two epics' scopes**
> plus the design corpus accumulated 2026-08-14: seven operating laws, studio/cockpit
> two-rooms model, six-color identity language, lease gap. Corpus lives in t-2828's
> context, [loops-library.md](loops-library.md), and the design one-pager
> [wave-pipeline-design.html](wave-pipeline-design.html). Original proposal kept below
> for provenance:

Epic `t-2820 loop-first` → phase `ph-14 Loop-First Operation — wave 1`:

- **ms-52 M1 Foundations:** t-2821 ADR graduated-loop-autonomy (design,S) ·
  t-2822 guard library, tests-first (S, blocked_by 2821) · t-2823 watchdog
  systemd-timer (S, blocked_by 2821) · t-2824 worktree-gate `git -C` regex
  fix (XS)
- **ms-53 M2 babysit-dev:** t-2825 L0 Reporter + digest channel (S,
  blocked_by 2822; AC includes 7-day first-beat tripwire) · t-2826 supervised
  L1 on the 5 real branches → `ready/*` refs, `--force-with-lease` (S,
  blocked_by 2825) · t-2827 unattended L1 (P2, blocked_by 2826 AND t-2173)
- **ms-54 M3 Safe expansion:** t-2828 inbox opt-in marker scheme,
  default-deny (S) · t-2829 drain-inbox (S, blocked_by 2828) · t-2830 cleanup
  loop, fresh-fetch + rejected-branch disposition (XS, blocked_by 2822) ·
  t-2831 docs (S, blocked_by 2825)

Deliberately excluded: the foreman (t-2811's capstone; t-1994 = graduation
target, to be re-scoped under t-2811).

## Challenger review (2026-08-13, 3-worker quorum — convergent / systems / critical)

**Verdict: 3× RECONSIDER — thesis and ladder sound; wave-1 not ready as specified.**
All findings mechanically fixable. HIGH = raised by ≥2 workers.

**HIGH / CRITICAL (must close before wave-1 goes live):**

1. **drain-inbox targets dangerous content** (2 workers). `inbox/` holds a live SSH
   private key, an active CNV regulatory appeal, family negotiation docs,
   client-confidential deliverables — not "audio, docs". A loop would put key
   material in transcripts and legal content into permanent git history.
   → **Default-deny:** loop touches only items with an explicit
   "safe-for-autonomous" opt-in marker; hard-exclude secret-bearing paths from
   loop context; everything else queues for human triage.
2. **Unattended test execution = host RCE; prerequisite open** (2 workers).
   Running `validate.sh`/tests in an unattended worktree repeats the mechanism
   the t-2140 stage-3 challenge already rated RECONSIDER; its named
   prerequisite **t-2173 (bwrap sandbox) is still in_progress**.
   → First *unattended* babysit-dev run `blocked_by: t-2173`; supervised runs OK.
3. **Loop lifecycle darkness** (2 workers). `/loop` is session-scoped, hard
   7-day expiry, no catch-up — and every repo health signal fires only at
   interactive SessionStart, which this plan makes rarer. Roster can go dark
   for days unnoticed. → External watchdog: `brana ops` systemd-timer reads
   each loop's last-beat timestamp from durable state, alerts at >2× cadence;
   in-loop re-arm before the 7-day cap (re-arm actor must be external to the
   loop it guards — gate-armed-by-the-party-it-constrains).
4. **24h-activity guard is inadequate for a destructive op** (3 workers).
   Point-in-time check = TOCTOU race with a resuming human; >24h quiet is an
   *expected* state under this very system (5h window pauses); in-place rebase
   rewrites a human-owned branch. → Advisory lock marker before rebase;
   cross-check tasks.json status as second signal; land prepared rebases on a
   `ready/<branch>` ref (never rewrite the human's ref); `--force-with-lease`
   only.
5. **"Mark ready" + pileup cap exist in prose, not in guards** (3 workers).
   No named mechanism/channel for readiness; cap=5 not wired into any guard.
   → L0 digest ships day-1 as mandatory companion (channel: SessionStart
   notice / `brana ops status`); babysit guard: count ready branches ≥5 → no-op.
6. **Quota model is flat but sessions accumulate** (2 workers). "~8K lean
   session" decays: cache-read ≈ accumulated context, and a session left open
   for days regrows fat purely from turn count. → Named session-recreation/
   compaction cadence (e.g. restart loop session daily); redo projection as
   cumulative; scope "unprompted" success metrics to active hours or move
   gap-surviving loops to Routines/desktop tier.

**Single-worker (fix cheaply during build):**
- `worktree-gate.sh` commit regex misses `git -C <path> commit` — extend regex
  before any cross-worktree loop commits (systems).
- `.claude/loop.md` rules ("never auto-commit/auto-delete") contradict wave-1
  loops → ADR states roster loops are separate committed prompts
  (`/brana:babysit-dev` etc.); `loop.md` stays the bare-`/loop` L0 fallback,
  unchanged (systems).
- New ADR must reconcile ADR-050's clauses (durable:true, kill-sweep owner,
  machine-verifiable prompt content) by name, not cite-and-move-on (critical).
- Exclude loop-issued skill invocations from `brana skills usage` counters
  (systems). · cleanup must diff against freshly-fetched `origin/dev`
  (critical). · Define disposition for ready-but-rejected branches (systems).
- Dated tripwire: first babysit-dev beat fires by a set date regardless of
  ADR-amendment completeness — same evidence-gated teeth as L1→L2 (critical).

**Wave-1 as amended:** Loop #1 = **L0 Reporter digest** (read-only, no RCE
surface, immediate value) + *supervised* L1 babysit runs; unattended L1 gated
on t-2173; drain-inbox gated on opt-in marker scheme; watchdog ships with the
first loop, not after.

## Probe results (2026-08-13, real repo)

**Day-1 beat simulation — what each candidate loop finds right now:**

| Candidate loop | Preflight | Day-1 result |
|---|---|---|
| doc-drift | `./validate.sh` | **no-op** (PASS, exit 0) — ideal no-op behavior |
| inbox-drain | `ls inbox/` | **fires** — 6 dirs + 3 files queued (audio, docs) |
| cleanup | merged-branch scan | **fires** — 4 stale merged branches |
| backlog-stale | `brana backlog stale` | **fires** — tasks stale 160+ days |
| backlog-lint | `brana backlog lint` | needs harness tweak — lint is per-task, no global mode |

**Pileup (risk B) is not hypothetical — it's the current state:** 5 unmerged
feature branches sitting in worktrees today, with zero loops running. The system
already opens work faster than it merges.

**Quota simulation (risk A) — cost per beat ≈ context size (cache-read is 97%
of tokens, see pattern_cache-read-is-the-cost-not-the-work):**

- Fat 120K interactive session, 5m cadence → ~14.4M tok/day. Ruinous.
- Dedicated lean ~8K loop session, 30–60m cadence → ~0.1–0.2M tok/day. ~100×
  cheaper. **Design rule: loops get their own lean sessions, never piggyback
  the interactive session; 30m+ cadence on subscription.**

**Pileup simulation (risk B):** cap=5 bounds the queue but halts the producer
20/30 days when open-rate (3/day) exceeds review-rate (1/day). **The binding
constraint is review rate, not the cap.** Cherny's answer is `/babysit` — a loop
that accelerates the human gate rather than producing more. Producers must open
at ≤ the real review rate (~1/day here).

**Implication for loop #1:** the first loop should attack the existing pileup —
a `babysit-dev` loop shepherding the 5 unmerged branches to merge — because it
is simultaneously (a) a narrow loop with durable-state termination (branch
merged = gone from queue), and (b) the standing mitigation for risk B.

**Round 3 — feasibility probe of babysit-dev (the 5 real branches):** full
autonomy fails day one: t-2812 was committed **3 minutes ago** (active session —
loop would race it, the t-2216 harm), t-2622 has a **dirty worktree** (2
uncommitted files a loop can't judge), t-2173 is **838 commits behind / 7 weeks
old** ("still wanted?" is human judgment). Killer detail: `git merge-tree`
reports **0 conflicts for all five** — the mechanical oracle is a weak gate;
real gates are tests/validate.sh post-rebase + human intent.

**Decision — graduated autonomy ladder (user: "gain levels of autonomy little
by little; this is the first step"):**

- **L0 Reporter** — merge-readiness digest per beat.
- **L1 Preparer** (start here) — rebase+test inactive clean branches, mark
  ready; human merges. Guards: skip branches with commits <24h old, skip dirty
  worktrees.
- **L2 Merger of the trivially-safe** — auto-merge only docs-only/tiny diff +
  green + task-completed + inactive >48h; escalate the rest. **Promotion by
  rule: after 5 consecutive prepared-then-approved-unchanged merges.**
- **L3 Full** — not now; would require its own promotion evidence.

The ladder + promotion-by-evidence generalizes to every loop in the roster
(cf. pattern_gate-destructive-capability-on-proof-not-assertion, t-1992's
"5 clean completions" sunset trigger).

## Changelog

- 2026-08-13: L0 Reporter shipped (t-2823) — system/scripts/pipeline-digest.sh + system/loops/pipeline-digest.md; challenger PROCEED WITH CHANGES, findings fixed in-branch; graduated-autonomy ADR tracked as t-2824.
