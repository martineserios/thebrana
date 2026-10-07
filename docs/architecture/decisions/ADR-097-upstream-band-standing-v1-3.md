---
status: accepted
extends: docs/architecture/decisions/ADR-084-upstream-skill-band-vendored-pocock-skills.md
respects: docs/architecture/decisions/ADR-061-goal-integration-three-primitive.md
informs: docs/architecture/decisions/ADR-085-skills-as-stations-no-atom-schema.md
---

# ADR-097: The upstream skill band is standing — default pin v1.3.1, admit `tdd`, take `pr` as a template, hold `retro`

**Status:** Accepted with changes (2026-10-07 by Martín Rios, on instruction "run /brana:challenge then accept") — one 3-worker pre-mortem + deep verification (RECONSIDER, narrow: 3 CRITICAL, 9 WARNING held, 1 refuted); every finding applied before acceptance, see Challenge record. Nothing under `system/` moves until the tasks in §Plan start.
**Date:** 2026-10-07
**Deciders:** Martín Rios
**Tags:** skills, upstream-band, mattpocock-mining, adr-084, adr-061, tdd, merge-valve
**Tasks:** t-3263 (evidence) · t-2981 (organ 4, approved) · P0–P4, P7 filed on acceptance; P5, P6, P8–P10 parked in [ideas/pocock-v13-adoption.md](../../ideas/pocock-v13-adoption.md) · twins t-3010 (TDD reference consolidation), t-3018 (refactor-split spike)
**Extends:** [ADR-084](ADR-084-upstream-skill-band-vendored-pocock-skills.md) — §7a: "that remains a separate follow-up ADR/amendment." This is it. **Amends §1's Valve row** (D1) and **supersedes §3's CONTEXT.md sentence** (D7).
**Respects:** [ADR-061](ADR-061-goal-integration-three-primitive.md) §4 inv. 2–3 · [ADR-060](ADR-060-branch-strategy-autonomous-agents.md) (executors never merge) · [ADR-092](ADR-092-graduated-loop-autonomy-ladder.md) (no pre-designed L2 classifier)
**Informs:** [ADR-085](ADR-085-skills-as-stations-no-atom-schema.md) D4/D6 — `tdd` is the one extraction build's granularity floor admits.
**Evidence:** [research/2026-10-07-pocock-recheck.md](../../research/2026-10-07-pocock-recheck.md) §2, §3, §6 · [research/2026-08-22-pocock-alignment-decision-matrix.md](../../research/2026-08-22-pocock-alignment-decision-matrix.md) §0 · ADR-084 §7a

---

## Context

ADR-084 (2026-08-17) admitted a band of upstream skills vendored verbatim, pinned, and wrapped
by thin brana adapters, as **pilot-only**. The pilot (`diagnosing-bugs` → `diagnose-hard-bug`,
t-2834) read EXPAND on 2026-08-30; two more organs followed (`code-review` →
`two-axis-review`, `wizard` → `provisioning-wizard`). All three are pinned `v1.2.3`. §7a
deferred whether the band is *standing*.

Upstream shipped v1.3.0/v1.3.1 on 2026-10-04. The quarterly recheck (t-3263) found three
graduated skills (`implement-spec`, `pr`, `retro`), a `CONTEXT.md` → `GLOSSARY.md` rename, and
`SCOPE.md` + `.out-of-scope/` records that close new-skill contributions and name the prose
"Other" tracker backend (brana's `docs/agents/issue-tracker.md`) as the sanctioned path. Placed
on brana's rings, everything is Beat or Knowledge; nothing is Epic-ring; no KEEP verdict in the
2026-08-22 matrix flips.

The challenge run before acceptance found what the recheck had not:

- **The band's call path has been structurally unreachable since it shipped.**
  `disable-model-invocation: true` "blocks only the Skill tool" (ADR-076 verified finding #3,
  recorded in `docs/architecture/skills.md`). Both live adapters carry that flag, and
  `/brana:fix` calls `diagnose-hard-bug` through the Skill tool. This is why the only recorded
  invocation was an inline run. No `~/.claude/run-state/pocock-*.jsonl` exists on this machine
  today; `two-axis-review` and `provisioning-wizard` have no caller anywhere in `system/`.
- **Organs are repo-local.** They live under `.agents/skills/` symlinked into `.claude/skills/`;
  `bootstrap.sh` syncs only `system/`. Adapters travel with the plugin, organs do not. A
  client-repo build calling an organ calls a missing skill.
- **Tag v1.3.1 predates PR #1209** (2026-10-07, `diagnosing-bugs` only). The "prove the
  mutation landed" step is on `main`, not in any tag.
- `build-loop.md` has **no refactor step**; its post-green steps are verify, probe boundaries,
  commit. The red commit (3d1) is what triggers `red-verification.sh` registration.

## Decision

### D1 — The band is standing, with one default pin and a per-organ hold

Standing means the mechanism is no longer on trial, not that every organ is. Terms:

- **One default pin for the band** (`v1.3.1` after P1). **Amends ADR-084 §1's Valve row**
  ("per-skill bump/hold decision, never a blanket update"): the default is band-wide, and each
  organ may carry a **dated hold** (`held_at: <tag>`, `hold_until: <date>`, reason) recorded in
  its `skills-lock.json` entry when its adapter would need rework at the new tag. A hold that
  expires without a bump reverts that organ to port-and-own. The per-skill decision survives;
  it is the exception, not the default.
- **Pre-registered proxies, readable before they are read.** "Rework on first touch" means: a
  change to the adapter's remap table or to the step headings its `redirect-check.md` names,
  excluding `vendored_from:` and pin-text updates, which every bump makes by definition.
  Invocation counts come from call-site records: every adapter appends to
  `~/.claude/run-state/pocock-<organ>.jsonl` on entry (two do today; P0 adds the rest), and
  callers invoke the adapter, never the organ directly. Until those records exist the
  invocation proxy is **unreadable, not zero**, and is not read.
- **Kill criteria** (ADR-084 §7, per organ, read at each bump): `adapter_churn` ≥ 2 between
  bumps; zero recorded invocations across a full bump window *once records exist*; rework on
  first touch as defined above. One organ failing is reverted alone. Two in one window re-open
  this ADR.
- **`code-review` and `wizard` get an invocation window**: no recorded call by the next
  quarterly recheck (t-3477, ~2027-01-07) reverts that organ to port-and-own.
- **Instruments stay unbuilt** until the third bump (ADR-084 "Negative (accepted)").

### D2 — Default pin moves to v1.3.1; diagnosing-bugs notes the post-tag step

`diagnosing-bugs`, `code-review`, `wizard`: `v1.2.3` → `v1.3.1` via
[features/upstream-band-pin-bump.md](../features/upstream-band-pin-bump.md). The bump updates
`vendored_from:` and pin text in each adapter (hard-coded today), regenerates
`computedHash`/`files[]` by script, re-verifies each `redirect-check.md`, and **creates** the
heading-presence and pin-equality tests the specs previously described as existing. PR #1209's
mutation-proof step is **not** in v1.3.1; the adapter notes the correspondence to
`red-verification.sh` and the next tag carries it.

### D3 — Admit `tdd` (organ 4); take `pr` as a template, not an organ

**`tdd`** — as t-2981 approved, corrected by the challenge
([features/tdd-organ-build-loop.md](../features/tdd-organ-build-loop.md)):

- The adapter is **model-invocable** (no `disable-model-invocation`), because its callers reach
  it through the Skill tool. The same correction is P0 for the two existing adapters.
- The organ covers **write the failing test → smallest green** only, in two calls per subtask.
  The red commit (3d1), the test gate (3d2), verify, probe boundaries and commit stay
  **caller-owned** in `build-loop.md`, so `red-verification.sh` registration and the `/goal`
  span (ADR-061 §4 inv. 2–3) are untouched. There is no refactor step in brana's loop today;
  whether one is added, and where, is t-3018's spike, which this ADR does not pre-decide.
- **Inline fallback.** Callers probe that the organ resolves; if it does not (client repos,
  broken symlink), today's inline prose runs. The inline text is not deleted.
- Delegated subtasks keep `delegation-tdd-checklist.md`; the spec names that path.

**`pr`** — the three-section body (summary visual · before/after evidence · Merge Danger as
door + blast radius) is adopted as a **template and a hook, not a vendored skill**
([features/pr-body-organ.md](../features/pr-body-organ.md)): a template file under
`system/skills/ship/`, `--body-file` in ship Part A, the same template in the runner's
`gh pr create` (autonomous-runner.sh:439, whose executor has no Skill tool), and a
`PreToolUse` hook on `gh pr create` that checks the three headings. Reason: a model-invoked
verbatim organ would outrank an 80-byte adapter and skip the never-invent-evidence guard, and
the two real PR paths are scripted blocks a skill cannot run inside. Upstream's `pr` SKILL.md
is kept as a pinned reference copy for the template's provenance (credited to Dex Horthy's
`show-me` upstream), not symlinked into `.claude/skills/`.

**Merge Danger informs the human.** The door and blast-radius call is written by the agent
that wrote the diff; it can only *tighten* a decision (missing, unknown or one-way goes to the
human). It is not a classifier for any autonomy rung: ADR-092 requires a machine-verifiable
L2 safe-class check derived by whichever loop first proposes promotion, and this ADR does not
pre-design it.

### D4 — Two `implement-spec` invariants enter the Beat contract as prose; the skill does not

brana's runner is the "deterministic loop" he ranks above `implement-spec`. The skill is
KEEP-BRANA. Two invariants are adopted:

1. **Explore once, point after.** Exploration output is written once, outside the repo, and
   every later implementer receives a pointer (ADR-086 §7, now stated for the runner's
   exploration step too).
2. **Conflict-readiness before the merge command.** At `build/phases/close.md` step 10, before
   presenting `git merge --no-ff`, the close runs a **read-only** merge-readiness probe against
   the current `dev` tip (the digest script already has one) and reports conflicts. It does
   not merge `dev` into the branch (that would widen close Step 1b's window, the t-2242
   over-reach) and it never runs in the runner, whose verb guard denies `git merge` under
   ADR-060; the beat names merge order there. Home: close.md step 10; epic-drain §Merge gets
   one sentence pointing at it. Filed as P4.

### D5 — `retro` is held, not rejected

The seven-category environment lens is a real gap: nothing in brana reads session logs or
treats the environment (hooks, rules, CLAUDE.md weight, tool cost) as the subject of a
retrospective. Not vendored this round: its home is undecided (a step in `/brana:close`
EXTRACT, a quarterly run like `verify-docs`, or neither) and its author's rule must travel
with it: human applies, sampled sessions, never a loop ("automating this means the agent will
get itself into a loop where it continually finds false positives"). The decision task (P5,
parked until an observed failure motivates it) must say where the human sits.

### D6 — `chief-of-staff` and `loop-me` are watched

Both are `in-progress/` upstream and re-derive in one session what brana persists in epic
nodes, waves and memory. Re-evaluate at t-3477 if either graduates. Two terms are worth citing
now without adopting anything: **push right** (defer the checkpoint as far as it will go) and
**brief** (a checkpoint presents a decision-ready summary, never the raw output) — brana's
valve and digest.

### D7 — GLOSSARY remap supersedes ADR-084 §3's CONTEXT.md sentence

Wherever an upstream skill reads `GLOSSARY.md` / `GLOSSARY-MAP.md`, the adapter maps to the
`docs/domain/` **directory**: `glossary.md` when it exists (t-3013 owns that), else
`MODEL-001-brana-core.md`'s Ubiquitous Language table, with ADR-084 §3's "2–3 most relevant
`docs/architecture/*.md` + the task's own context" fallback kept. One shared remap note in
`system/skills/_shared/`, referenced by every adapter, so the glossary decision costs zero
adapter commits.

### D8 — Sweep additions: one practice enters the plan, three are parked

The deeper sweep (research §6) found four adoptable practices. Only one has an observed
failure behind it (Pocock's own `SCOPE.md` bar, applied to ourselves):

1. **Rules → hooks audit, one-shot** (S1, P7): each always-load rule line is tested with
   "could a `PreToolUse` hook exit 2 with this message?". The pass is **proposal-only** with
   per-line human approval; every converted line ships with a **must-fire test**
   (`pattern_detector-needs-a-must-fire-test`) before the rule line is deleted; the gauge is
   the count of converted-and-tested rules, headroom from `system/scripts/context-budget.sh`
   second. It **scopes, and cites, `system/rules/rules-over-hooks-for-gates.md`**: that rule
   stays the default for process steps; this pass applies only to lines that name a concrete
   tool pattern (a command, a path, a flag) a hook can match deterministically. No recurring
   scope until P5 decides retro's home. The observed failure: the CI headroom floor broke on
   2026-09-07 and 2026-10-05 and was fixed by hand trims (t-3470).
2. **Triage repro gate** (S2, P8) — **parked**: no observed failure yet.
3. **QA-plan brief at wave ship** (S3, P9) — **parked**: no observed failure yet.
4. **File-size gate** (S4, P10) — **parked**: undefined for files already over the limit
   (`validate.sh` is ~134 KB) and no observed failure.

Habits S5–S8 are folded into existing tasks' context (t-3012, t-2984, t-2981, decompose
phase). The routing rule the operator asked for (smartest model for the interview and
challenge, cheaper models for build, runner and read-and-extract fan-out) lands in
`delegation-routing.md` **after** P7 frees bytes; until then it lives in the pattern store.

### D9 — Organ availability outside thebrana is a fallback, not a deployment

Organs stay repo-local. Client repos run the inline fallback (D3). Shipping organs through the
plugin would make a third-party artifact auto-deploy to every project, which is exactly the
"managed, read-only bundle that updates automatically" ADR-084 §2 rejected. Re-open only if a
client repo needs an organ, and then by vendoring into that repo with its own lock entry.

## Plan (filed on acceptance)

| # | Task | Kind | Effort | Blocked by |
|---|---|---|---|---|
| P0 | Fix the band's call path: remove `disable-model-invocation` from `diagnose-hard-bug` and `two-axis-review`, add call-site records to all adapters, add one resolution test per organ; re-read ADR-084 §7a's invocation proxy against real records | fix | S | — |
| P1 | Pin bump v1.2.3 → v1.3.1 per `upstream-band-pin-bump.md`; adapters' `vendored_from:` updated; heading-presence + pin-equality tests created | chore | S | P0 |
| P2 | t-2981 as corrected: `tdd` organ, callers keep 3d1/3d2, inline fallback, delegation checklist path named | feature | M | P1 |
| P3 | PR-body template + `--body-file` in ship Part A + runner body + `gh pr create` headings hook; docs updated in the same task | feature | S | — |
| P4 | Read-only merge-readiness probe at close.md step 10; one sentence in epic-drain §Merge; "explore once, point after" stated for the runner's exploration step | fix | XS | — |
| P7 | One-shot rules → hooks audit, proposal-only, must-fire test per conversion, scoped by `rules-over-hooks-for-gates.md` | refactor | S | — |

Parked in the idea doc with their trigger: P5 (retro home), P6 (GLOSSARY wording in t-3013;
ADR-084 §3 is superseded by D7 here), P8, P9, P10.

## Consequences

**Positive.** The band's call path works for the first time (P0), with records that make
ADR-084's proxies readable. One default pin with a dated hold keeps the gauge a single number
without removing the per-skill valve. The two disciplines that most directly carry his
implementation quality land where they can actually fire: `tdd` as an organ with a fallback,
`pr` as a template and hook on every real PR path including the runner. The merge valve gets a
conflict report before the human merges.

**Negative (accepted).** Five `redirect-check.md` re-verifications per bump stay hand labour
until the third bump. The inline TDD prose and the organ coexist, so two texts must stay
consistent (the resolution test catches a missing organ, not drift between the two; t-3010
owns the consolidation). Holding `retro` leaves the environment-lens gap open for at least one
more quarter.

**Risk retained.** A bump that renames a step heading the adapter depends on is caught by the
heading-presence test, not by a semantic check; the diff reviewer still reads every line.

## Non-Actions

| Not doing | Why |
|---|---|
| Vendor `implement-spec` | brana's runner is the thing he ranks above it; no Epic-ring state in his version |
| Vendor `pr` as a skill | would outrank its adapter and cannot run inside the two scripted PR paths (D3) |
| Vendor `retro` now | home and human position undecided (D5) |
| Use Merge Danger as an L2 predicate | author-asserted prose; ADR-092 requires a machine-verifiable classifier designed by the promoting loop |
| Sync `dev` into the branch at close, or in the runner | widens close's window (t-2242); runner verb guard denies merge (ADR-060) |
| Ship organs through the plugin | re-creates the auto-updating bundle ADR-084 §2 rejected (D9) |
| Build the ADR-084 §1 instruments | two bumps are not a trend; third bump re-opens |
| Create `docs/domain/glossary.md` here | t-3013 decides its shape; D7 resolves to the directory |
| Contribute fixes upstream | closed by his `new-skills.md`; vendoring is the only relationship |
| Recurring rules → hooks scope | inverts `rules-over-hooks-for-gates.md` as a default; one-shot only until P5 |

## References

- [ideas/pocock-v13-adoption.md](../../ideas/pocock-v13-adoption.md) — shaped idea, ring-fit table, plan and parked items
- [research/2026-10-07-pocock-recheck.md](../../research/2026-10-07-pocock-recheck.md) — §2 findings, §3 follow-ups, §3a diagrams, §6 deeper sweep
- [ADR-084](ADR-084-upstream-skill-band-vendored-pocock-skills.md) §1 (amended), §2, §3 (superseded in part), §7, §7a
- [ADR-061](ADR-061-goal-integration-three-primitive.md) §4 inv. 2–3 · [ADR-060](ADR-060-branch-strategy-autonomous-agents.md) · [ADR-076](ADR-076-build-receipts-as-executed-evidence.md) verified finding #3 · [ADR-092](ADR-092-graduated-loop-autonomy-ladder.md)
- `system/rules/rules-over-hooks-for-gates.md` — scoped, not reversed, by D8
- `system/skills/diagnose-hard-bug/SKILL.md`, `system/skills/two-axis-review/SKILL.md`, `system/skills/provisioning-wizard/SKILL.md` — the live adapters
- upstream: `mattpocock/skills` `SCOPE.md`, `.out-of-scope/`, tags v1.3.0/v1.3.1, PR #1209

## Challenge record

**2026-10-07, pre-mortem, three native challengers (convergent · systems · critical, Sonnet)
+ deep verification (7 findings × 2 skeptics; 6 held, 1 refuted). Gemini grounding
unavailable. Verdict: RECONSIDER, narrow. Applied before acceptance:**

| # | Finding | Severity | Verified by | Applied as |
|---|---|---|---|---|
| 1 | `disable-model-invocation` blocks the Skill tool; adapters unreachable; organs not deployed | CRITICAL | tool (docs/architecture/skills.md, bootstrap.sh) | P0; D3 fallback; D9 |
| 2 | No refactor step exists; one call swallows 3d1/3d2 | CRITICAL | tool (build-loop.md) | D3 split; refactor to t-3018 |
| 3 | Standing declared on zero recorded invocations | CRITICAL | tool (run-state, system/ grep) | D1 proxies readable-first; windows |
| 4 | `pr` organ cannot cover ship / runner paths; would outrank adapter | WARNING | VERIFIED 2/2 | D3: template + hook |
| 5 | Merge Danger as L2 predicate vs ADR-092; author-asserted | WARNING | tool (ADR-092 line 67) | paragraph removed; Non-Action |
| 6 | D4 wrong home, no-ff not ff, runner denies merge | WARNING | tool (close.md:127-133, runner-verb-guard.sh) | D4 probe-only |
| 7 | v1.3.1 predates #1209; #1209 is diagnosing-bugs | WARNING | tool (gh, tag contents) | D2; tdd spec corrected |
| 8 | One pin removes ADR-084 §1 hold; no redirect test exists; tags hard-coded | WARNING | VERIFIED 2/2 | D1 hold; D2 tests created |
| 9 | D8 is retro by another name; gauge rewards deletion; inverts rules-over-hooks | WARNING | VERIFIED 2/2 | D8 one-shot, must-fire, scoped |
| 10 | Kill proxies unreadable; "rework" undefined | WARNING | VERIFIED 2/2 | D1 definitions; P0 records |
| 11 | D7 points at the wrong file | WARNING | REFUTED 0/2 | D7 wording only (directory) |
| 12 | Plan not an honest cut; t-3010/t-3018 uncited; delegation checklist omitted | WARNING | VERIFIED 2/2 | Plan cut; twins cited; spec names the path |
| 13 | P10 undefined for over-limit files; P7 inverts standing rule uncited | WARNING | VERIFIED 2/2 | P10 parked; D8 cites and scopes |

One finding the panel did not raise but the fact-check did: the pilot's own evidence in
ADR-084 §7a was consistent with the adapter never being callable; P0 re-reads it.
