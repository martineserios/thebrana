---
status: accepted
---

# ADR-084: Upstream Skill Band — Vendored Pocock Cognitive Skills Over Brana Orchestration Shells

**Status:** Accepted — pilot-only (2026-08-17); challenge findings applied 2026-08-23 (see Challenge record)
**Date:** 2026-08-17
**Deciders:** Martín Rios
**Tags:** skills, mattpocock-mining, the-brana, adr, upstream-band
**Tasks:** t-2837 (this ADR) · t-2830 (source research) · t-2834 (pilot beat: diagnosing-bugs) · t-2835, t-2836 (gated on pilot) · t-2833, t-2831, t-2832 (already shipped, unaffected)
**Relates:** [t-2830 research](../research/2026-08-13-matt-pocock-skill-system.md) (comparison table, §4 proposals, §7 integration modes) ·
[the-brana.md §Scale](../the-brana.md) (the layer test / spectrum / skeleton match this ADR applies — absorbed from `drained/wave-pipeline.md`, t-3028) · [ADR-085](ADR-085-skills-as-stations-no-atom-schema.md) (adapter-as-station reading, D3/D6 — lands after this ADR) ·
[ADR-078](ADR-078-stale-task-park-via-tag.md) (`parked` tag mechanism used to gate t-2835/t-2836) ·
[ADR-012](ADR-012-acquire-skills.md) (existing vendoring precedent: `.agents/skills/` + `skills-lock.json`, reused here rather than reinvented) ·
[docs/reference/skill-writing-craft.md](../../reference/skill-writing-craft.md) (t-2833's shipped ADAPT-mode doc, ratified as final for `writing-for-agents` below) ·
[gentle-ai-adoption-ladder.md §Rung 3](../../ideas/drained/gentle-ai-adoption-ladder.md) (killed `mode: execute-only` precedent — the adversarial-pass discipline this ADR follows)

---

## Context

t-2830 (2026-08-13) read all 35 skills in [mattpocock/skills](https://github.com/mattpocock/skills)
(MIT, `v1.2.3` at time of writing, 220K★, `pushed_at: 2026-08-17` — actively maintained) and
mapped every one to a brana counterpart. Six candidate tasks (t-2831–t-2836) were queued
`wave:drain-3`, all built under a **port** reading: rewrite the Pocock idea as native brana
skill content. A same-day studio dialogue reframed the model as **depend, don't fork**
(t-2830 §7, added 2026-08-14): for skills that are self-contained artifacts (not vocabulary
or process ideas), install the upstream skill **pinned**, wrapped by a thin brana adapter,
rather than copy its content into a brana-maintained fork that silently drifts.

This reframing arrived mid-wave. t-2833 shipped 2026-08-17 as a doc-only ADAPT-mode
companion (not vendored) before this ADR landed; its own challenger review (iteration 1:
RECONSIDER sev4) flagged the premise conflict and resolved it with an explicit
reconciliation section stating the doc **coexists with, not substitutes for**, a future
vendored dependency. t-2834, t-2835, t-2836 were parked (ADR-078 tag mechanism) rather than
built under stale AC, each carrying an unresolved note asking this ADR to settle scope.
Two internal inconsistencies surfaced during drafting (see §3) that this ADR resolves
rather than restates.

Per `m-plus-discipline-enforcement.md`, this M-effort design task is the settling ADR the
epic's blocked children need before code starts.

## Decision

### 1. The layer test — this is a new band, not a new skill format

Per the layer test owned by [the-brana.md §Scale](../the-brana.md) ("a proposed band is real iff you can name its queue,
pump, valve, gauge, and memory contract — admission stays graded, a band exists once
something has actually cycled in it with records emitted"), the upstream band is specified
as follows and admitted **pilot-only** (§5) pending its first real beat:

| Primitive | Instrument |
|---|---|
| **Queue** | The unreviewed delta between the pinned ref and upstream's latest tag — one entry per vendored skill in `skills-lock.json` (extended, §2). |
| **Pump** | A sync check (folded into `/brana:reconcile`, new `--scope pocock-sync`) that diffs pinned vs. latest tag per vendored skill and stages a report. Never applies anything. |
| **Valve** | A human review at a cockpit sitting: per-skill bump/hold decision, never a blanket "update everything." Mirrors the existing ac-approve batch pattern (ADR-079) — explicit confirmation, no rubber-stamp. |
| **Gauge** | A digest line: "N Pocock-vendored skills, M versions behind" (cockpit digest or `brana doctor`). |
| **Memory** | This ADR (read-on-entry) + each adapter's own header (source repo, pinned tag, last-sync-check date) — write-on-exit is the sync report landing in the adapter's context. |

The band is **not** materialized by this ADR alone — per the layer test's own admission
rule, it materializes only once the pilot beat (§5) actually cycles. The table above is this
ADR's *instance* of the test; the test itself, and the station reading of "adapter" (a thin
user-invoked wrapper over a model-invoked organ), are owned by the-brana.md §Scale and
ADR-085 D3/D6 respectively — not restated here.

### 2. Vendoring mechanism — reuse `.agents/skills/` + `skills-lock.json`, not native plugin install

Two mechanisms exist in the repo already; neither needs inventing:

- **Native Claude Code plugin install** (`claude plugin install mattpocock-skills`) —
  Pocock's own README calls this "a managed, read-only bundle that **updates
  automatically**." That property is disqualifying: it removes the human valve this ADR's
  queue/pump/valve model requires. **Rejected** for this band.
- **File-copy vendoring** (`.agents/skills/<name>/`, symlinked at `.claude/skills/<name>`,
  tracked in `skills-lock.json` with `source`, `sourceType`, `skillPath`, `computedHash`) —
  already proven for 15 acquired thinking-skills (ADR-012). **Adopted, with two schema
  extensions** (challenge finding #2, 2026-08-23):
  - `pinnedRef` (the upstream git tag, e.g. `"v1.2.3"`) — `computedHash` alone tells a
    machine whether content changed; it doesn't tell a human how far behind the pin is, which
    the gauge (§1) needs to report.
  - **`computedHash` covers the whole vendored directory**, not `SKILL.md` alone: hash of
    every file under `.agents/skills/<name>/` (sorted path + content), with the hashed paths
    recorded in a `files[]` list. Today's lock hashes one file per skill, so companion files
    (`diagnosing-bugs` ships `agents/` and `scripts/hitl-loop.template.sh`) would drift
    invisibly — the §1 gauge would be blind to exactly the files most likely to break the
    adapter. The 15 existing single-file entries stay valid (their directory *is* one file);
    `files[]` is required only for multi-file skills.

Each vendored organ lands at `.agents/skills/<pocock-name>/` verbatim (SKILL.md +
sub-files: `agents/`, `scripts/`, or companion `.md` references, whatever the upstream skill
ships), symlinked into `.claude/skills/`, exactly like the existing acquired-skills tree.
The brana-side **adapter** is a separate ~10-line `system/skills/<brana-name>/SKILL.md` that
does the input/output remap (§3) and nothing else — it is not a copy of upstream content.

### 3. Name-remap contract — the adapter's actual job

Per the task's own framing, the adapter is "the piece that breaks silently on upstream
updates." Its contract:

- **Vocabulary map** (from Pocock's `CONTEXT.md`, read during t-2830):
  - `Issue tracker` → brana's `tasks.json` (adapter always answers "local files," never
    prompts Pocock's own `/setup-matt-pocock-skills`, which is not installed).
  - `Issue` / `ticket` → brana `task` (`t-NNN`).
  - `Triage role` → brana `status` + `tags` (vocabulary differs; no 1:1 mapping needed
    since brana's own `/brana:backlog triage` already owns this job — no upstream triage
    skill is vendored).
- **Cross-skill references.** Upstream skills reference each other by slash-name inside
  their own prose (`diagnosing-bugs` recommends handoff to
  `/improve-codebase-architecture` at Phase 6; `code-review` tells the reader to run
  `/setup-matt-pocock-skills` if `docs/agents/issue-tracker.md` is missing). **Every such
  reference the adapter's brief must intercept and redirect** — either to a brana
  equivalent (`/improve-codebase-architecture` → recommend filing an architecture-refactor
  task, not installing an unvendored Pocock skill) or to a no-op with an explanation
  (`/setup-matt-pocock-skills` → adapter always pre-supplies the issue-tracker answer, so
  this path never fires). This redirect table lives **in the adapter**, not upstream — it
  is exactly the part that silently breaks on a `git pull`-style bump if not re-checked at
  every valve turn (§1 pump/valve). **Artifact (challenge finding #4):** the adapter
  commits the table as a checkable list — every upstream slash-reference (`/name`) found in
  the vendored skill's text, mapped to its brana redirect or explicit no-op. The §1 pump
  re-greps upstream's slash-refs on every bump and diffs them against this list; an unmapped
  ref is a reported drift, not a silent break. t-2834 ships the first list.
- **`CONTEXT.md` assumption.** Upstream skills read a repo-root `CONTEXT.md` glossary file
  brana does not maintain. The adapter substitutes brana's own memory system
  (`docs/architecture/`, `~/.claude/projects/.../memory/`) — pass the relevant glossary
  terms inline in the sub-agent brief rather than pointing at a file that doesn't exist.

### 4. Per-skill swap table — every skill from the t-2830 comparison

Verdict legend: **VENDOR+WRAP** (pin + `.agents/skills/`, adapter does the remap) ·
**KEEP-BRANA** (brana's own implementation stays as-is or absorbs the idea natively, no
upstream dependency) · **SKIP** (not portable, or explicitly rejected with reasoning
already on record).

#### Engineering tier

| Pocock skill | Verdict | Notes |
|---|---|---|
| `ask-matt` | KEEP-BRANA (idea-adapted) | Shipped t-2831 — ordered spine doc; architecture, not artifact, so nothing to vendor. |
| `grill-with-docs` | KEEP-BRANA | brainstorm is the superset; not portable as a standalone artifact tied to our tasks.json. |
| `grilling` (primitive) | SKIP for this band | Listed in t-2830 §7's DEPEND table, but nothing vendored in this band calls it (its only callers, `grill-with-docs`/`grill-me`, are KEEP-BRANA). No consumer, no queue — the layer test fails for this one specifically. Revisit only if a future thin-organ needs a structured interview primitive distinct from brainstorm's. |
| `implement` | KEEP-BRANA | `/brana:build` is a strict superset. |
| `tdd` | KEEP-BRANA, unclaimed DEPEND candidate | §7's DEPEND table lists it but no backlog task exists; brana's TDD discipline is diffused across `sdd-tdd.md` + build's TDD loop and works. Not this wave. |
| `code-review` | **VENDOR+WRAP** — pilot-gated (t-2835) | **Resolves conflict #1** (§5): t-2830 §7 filed this under ADAPT ("two-axis review in our reviewer agents"), but the 2026-08-14 studio dialogue (recorded in t-2837's own context) explicitly reshaped t-2835 from port to vendor+wrap. The studio note is later and more specific; §7's table entry was an oversight, corrected here. Upstream's two-axis parallel-subagent design is a self-contained process (87 lines, its own Fowler smell baseline) — an artifact to vendor, not an idea to reimplement. |
| `triage` | KEEP-BRANA | Job covered; vocabulary (5-role state machine vs. brana's `status`) intentionally differs — no remap value. |
| `improve-codebase-architecture` | SKIP for this wave | t-2830 §4 P8 rejected pending a stated architecture-health pain point; stands. |
| `setup-matt-pocock-skills` | N/A | Meta-setup for Pocock's own plugin set; irrelevant once we vendor individual skills via file-copy rather than plugin-install. |
| `to-spec` | KEEP-BRANA | `/brana:build` SPECIFY is the superset. |
| `to-tickets` | KEEP-BRANA (partial gap noted) | Blocking-edge mechanics exist (`blocked_by`); the named "expand–contract" pattern for wide refactors has no brana equivalent and no task was filed for it — logged here as a future backlog candidate, not adopted now. |
| `wayfinder` | KEEP-BRANA | Structural cousin to waves (frontier, claim-before-work), but drains *decisions* where waves drain *execution* — deliberately not conflated (t-2830 §2). |
| `diagnosing-bugs` | **VENDOR+WRAP** — **the pilot** (t-2834) | See §5. |
| `research` | KEEP-BRANA | `/brana:research` is a strict superset (registry, scout budget, agy cross-check). |
| `resolving-merge-conflicts` | SKIP | **Resolves conflict #2** (§5): §7's DEPEND table lists it, but §4 P9 explicitly rejected it the same document ("log as idea, not worth a wave slot until conflict pain is actually observed") and no task exists. §4's explicit, reasoned reject stands; §7's table over-listed it — corrected here. |
| `prototype` | KEEP-BRANA, unclaimed DEPEND candidate | Real partial gap (brana's `strategy: spike` field exists with no discipline around it), listed in §7's DEPEND table but never promoted to a P-numbered proposal or a task. Logged as a future small-effort candidate, not this wave. |
| `wizard` | **VENDOR+WRAP** — gated on pilot (t-2836) | **Resolves the flagged ambiguity t-2836 asked this ADR to settle**: §7's DEPEND table names `wizard`; the 2026-08-14 studio note (t-2837's own reshape list) doesn't mention t-2836 at all. Read as an omission, not a deliberate exclusion — the studio note's silence on t-2836 contradicts nothing it does say, whereas §7's DEPEND table is explicit. **Confirmed in scope.** Self-contained artifact (`template.sh` library + stage-authoring convention) with near-zero brana-specific coupling — the DEPEND organ pattern fits cleanly. |
| `codebase-design` | SKIP for this wave | t-2830 §4 P8 rejected — needs its own ADR (new shared vocabulary) if revisited. |

#### Productivity tier

| Pocock skill | Verdict | Notes |
|---|---|---|
| `grill-me` | KEEP-BRANA | Same reasoning as `grill-with-docs`. |
| `handoff` | KEEP-BRANA | `/brana:close --continue` is a strict superset (also does pattern extraction, doc-drift detection). |
| `teach` | SKIP | t-2830 §4 P10 — personal-workspace feature, not a skill-system gap. |
| `to-questionnaire` | SKIP | t-2830 §4 P10. |
| `wait-what` | SKIP | t-2830 §4 P10 — different job than `/brana:sitrep`. |
| `writing-for-agents` | KEEP-BRANA (idea-adapted), ratified | **Resolves conflict #3** (§5): shipped t-2833 as a doc-only companion (`docs/reference/skill-writing-craft.md`), not vendored, per its own already-negotiated reconciliation section. This ADR **ratifies that as the final answer for this decision round** — the doc's own text already states a future DEPEND-mode vendoring is a live option, not decided now; nothing in this ADR forecloses revisiting it once the upstream band exists as a proven pattern (post-pilot). |

#### In-progress and misc tiers

No change from t-2830's original recommendations: `claude-handoff`, `loop-me`,
`writing-beats`/`writing-fragments`/`writing-shape` — SKIP (personal-writing tooling, no
skill-system gap). `setup-ts-deep-modules` — N/A (not portable, brana is Rust/shell).
`git-guardrails-claude-code` — KEEP-BRANA, brana already exceeds it. `migrate-to-shoehorn`,
`scaffold-exercises`, `setup-pre-commit` — N/A, course/tech-specific.

### 5. Reconciling the two inconsistencies + the flagged ambiguity

Three same-day artifacts (t-2830 §7's DEPEND/ADAPT/SKIP tables, the studio dialogue
recorded in t-2837's context, and each task's own AC) disagreed with each other in three
places. This ADR is the settling authority per its own AC. **One tie-break rule, applied to
all three** (challenge finding #1 — the draft mixed recency for conflict 1 with specificity
for conflict 2, and §7 is dated *later* than §4, so "later wins" would have flipped conflict
2; the rule below is document-order-independent):

> **R1.** An explicit, *reasoned* rejection is never reversed by a later table that merely
> re-lists the item without new reasoning.
> **R2.** A note that *names the specific task* overrides a generic table entry that does not.
>
> Neither clause asks which artifact is dated later.

The resolutions, each with the clause that decides it:

1. **`code-review` (t-2835): ADAPT → VENDOR+WRAP.** *R2:* the studio dialogue names
   t-2835 explicitly; §7's ADAPT entry is a generic table row. (Recency is irrelevant.)
2. **`resolving-merge-conflicts`: DEPEND (table) → SKIP.** *R1:* §4 P9 is a reasoned
   rejection; §7's DEPEND row re-lists it with no new reasoning. No task was ever filed —
   the reject was never reversed, just inconsistently re-listed. (That §7 is dated later
   changes nothing under R1.)
3. **`wizard` (t-2836): ambiguous → confirmed VENDOR+WRAP, in scope.** *Neither clause
   fires against the table:* the studio note neither rejects `wizard` (no R1 trigger) nor
   names t-2836 (no R2 trigger) — it is silent, and its own hedge language reads that
   silence as omission. The only explicit statement (§7's DEPEND row) stands.

### 6. Decision — **pilot-only**, not a standing band yet

Per the graded-admission rule (the-brana.md §Scale) and the loop-first discipline (t-1994: "redesign
follows observed loop failures, not upfront design" — never a big-bang rewrite), this ADR
approves:

- The mechanism (§1–§3) and the per-skill swap table (§4) as **final for this decision
  round**.
- **One pilot beat**: t-2834 vendors `diagnosing-bugs`, wrapped thin in `/brana:fix`'s
  REPRODUCE→DIAGNOSE step, run on a real bug, records emitted (per t-2837's own admission
  bar).
- t-2835 and t-2836 stay **parked** (ADR-078 tag), `blocked_by` re-pointed from `t-2837`
  (now resolved) to **`t-2834`** — they proceed only after the pilot's kill/expand
  evaluation (§7), not automatically.

**Not decided here:** whether the band expands past the pilot, or whether the queue/pump/
valve/gauge instruments (§1) get built as standing infrastructure vs. run manually per
bump. That is exactly what the pilot is for.

### 7. Kill / expand criteria for the pilot (t-2834)

Evaluate after the pilot beat completes (real bug, real invocation, records emitted) or
after 30 days elapsed, whichever comes first:

**Expand** (t-2835, t-2836 unpark; §1's instruments get built as standing infrastructure;
band is materialized) if, at evaluation:
- The adapter survived the pilot without needing a mid-flight rewrite of its remap table
  (§3) — proof the name-remap contract is stable, not fragile.
- At least one real bug-fix invocation shows the tight-loop/ranked-hypothesis discipline
  changed outcome or process quality (not just "it ran").
- Upstream stayed on `v1.2.3` or bumped cleanly (diff reviewable, no breaking rename) —
  proof the pin+valve mechanism is maintainable, not a maintenance sink.

**Kill** (revert t-2834 to its original pre-§7 "port" AC — rewrite content natively into
`/brana:fix` instead — and do not pursue t-2835/t-2836 as vendored) if:
- The adapter needs rework on the first upstream touch (mirrors the falsified
  `mode: execute-only` precedent, gentle-ai-adoption-ladder Rung 3, t-2591:
  `churn_share` above threshold on the wrapper itself is the same failure signature).
- Zero organic invocations in the 30-day window (pattern_looptrap-autonomy-findings: built,
  unused).
- The native-plugin-vs-file-copy tradeoff (§2) turns out cheaper to maintain the other way
  — i.e., file-copy vendoring proves more maintenance burden than the port-and-own
  alternative it was chosen over.

**Pilot-only, evidence held open** if neither threshold is clearly crossed at 30 days —
extend the observation window once, do not default to expand.

**Pre-registered proxies** (challenge finding #3 — the t-2591 precedent computed its
threshold three ways *before* looking; these are fixed now, before t-2834 starts):
- `adapter_churn` — commits touching the adapter (`system/skills/<brana-name>/SKILL.md` +
  its redirect list) *after its first working version*, from `git log --follow` on those
  paths at evaluation time. **Kill signal: ≥2 such commits** without an upstream bump
  driving them (the wrapper is being rewritten to keep working — `churn_share`'s analog).
- `invocations` — count of records emitted by the adapter in the window (grep on the
  records path the adapter writes). **Kill signal: 0.** Expand's "changed outcome" test
  is judged on those same records, not on recollection.
- `upstream_delta` — `git log v1.2.3..<latest-tag> -- skills/engineering/diagnosing-bugs/`
  in the upstream repo at evaluation. Reviewable diff = expand-eligible; rename or
  restructure = maintainability signal for kill.

## Consequences

- **Positive:** the six-task wave-3 batch is unblocked with an explicit, reconciled
  per-skill decision instead of three disagreeing same-day notes; t-2834 can start
  immediately under corrected AC.
- **Positive:** reuses the existing `.agents/skills/` + `skills-lock.json` vendoring
  mechanism (ADR-012) rather than inventing a second one — one vendoring pattern in the
  repo, not two.
- **Positive:** explicitly rejects native plugin auto-update for this band, closing a real
  gap the pin+valve requirement would otherwise silently violate.
- **Negative (accepted):** three skills (`grilling`, `tdd`, `prototype`) are logged as
  DEPEND-listed-but-unclaimed — real gaps the research doc named but no task ever
  operationalized. Left as future candidates, not fabricated into this wave's scope.
- **Negative (accepted):** the band is not materialized yet — no queue/pump/valve/gauge
  instruments exist until the pilot proves the pattern. A second ADR (or an amendment to
  this one) is needed if the pilot expands, to actually spec the `reconcile --scope
  pocock-sync` pump and the digest gauge line as buildable work.
- **Scope boundary:** this ADR covers the vendoring mechanism, the per-skill verdicts, and
  the pilot's kill/expand criteria only. It does not implement `/brana:fix`'s adapter
  (t-2834's own build), nor the `pocock-sync` pump (deferred to post-expand).

## Non-Actions

- Does not vendor `grilling`, `tdd`, `prototype`, or `resolving-merge-conflicts` this wave.
- Does not build the queue/pump/valve/gauge instruments (§1) — those are pilot-gated.
- Does not install Pocock's plugin via `claude plugin install` — explicitly rejected (§2).
- Does not reopen `writing-for-agents`'s ADAPT-vs-DEPEND question — ratified as ADAPT-mode
  final for this round (§4).

## References

- [t-2830 research doc](../research/2026-08-13-matt-pocock-skill-system.md) §1 (comparison
  table), §4 (scored proposals), §7 (integration modes)
- [the-brana.md §Scale](../the-brana.md) (layer test, spectrum, skeleton match — absorbed
  from `drained/wave-pipeline.md`, t-3028) · [ADR-085](ADR-085-skills-as-stations-no-atom-schema.md)
  (adapter-as-station, D3/D6)
- [ADR-012](ADR-012-acquire-skills.md) (vendoring precedent reused, §2)
- [ADR-078](ADR-078-stale-task-park-via-tag.md) (`parked` tag mechanism, §6)
- [gentle-ai-adoption-ladder.md §Rung 3](../../ideas/drained/gentle-ai-adoption-ladder.md) /
  t-2591 (kill-threshold precedent reused in §7)
- Upstream: [github.com/mattpocock/skills](https://github.com/mattpocock/skills) `v1.2.3`,
  MIT license (confirmed via `gh api`, no clearance blocker — same finding as t-2833)

## Challenge record

- 2026-08-18: `/brana:challenge` — the merged 3-agent synthesis never landed; the interim
  direct-analysis report is the report of record. Findings: (1) CRITICAL §5 tie-break
  inconsistent; (2) CRITICAL §2 lock hashes one file per skill; (3) WARN §7 kill/expand
  uninstrumented; (4) WARN §3 name-remap re-check has no artifact; (5) OBS wizard resolution
  lowest-risk. Operator HOLD placed 2026-08-18 pending idea consolidation.
- 2026-08-23: hold lifted (consolidation landed as the-brana.md). Findings 1–4 applied in
  place (§5 rule R1/R2; §2 dir-level `computedHash` + `files[]`; §7 pre-registered proxies;
  §3 redirect-check artifact); 5 accepted. t-2834 AC widened to match §2/§3/§7. §1/§3/refs
  repointed from `drained/wave-pipeline.md` to the-brana.md §Scale and ADR-085 (t-3028
  absorb). ADR-085 declares a landing dependency on this ADR; this lands first.
