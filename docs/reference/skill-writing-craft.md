# Skill Writing Craft

Companion to [`skill-validation-checklist.md`](skill-validation-checklist.md). The checklist is a
compliance gate — pass/fail items a finished skill should satisfy. This doc is the craft
rationale behind two of those items: **why** bounded context loading (checklist item 3) and
explicit control flow (checklist item 4) work, not just that they're required. Read this when
authoring or editing a skill, not when auditing one — the checklist stays the audit tool.

Derived from Matt Pocock's [`writing-for-agents`](https://github.com/mattpocock/skills/blob/main/skills/productivity/writing-for-agents/SKILL.md)
and [`SKILL-MECHANICS.md`](https://github.com/mattpocock/skills/blob/main/skills/productivity/writing-for-agents/SKILL-MECHANICS.md)
(Pocock, 2025), via [t-2830](../research/2026-08-13-matt-pocock-skill-system.md) research
comparing brana's skill system against his. The levers below generalize to any document an
agent consumes — a `SKILL.md`, a phase file, `CLAUDE.md` — but this doc frames them against
brana's own `SKILL.md` + `phases/*.md` split.

---

## Context pointers

A **context pointer** is a reference held in the agent's context that names some out-of-context
material and encodes the condition for reaching it. In brana's skills, the PHASES registry table
(e.g. `system/skills/build/SKILL.md`'s `| Step | File | Load when |` table) is a set of context
pointers — each row names a phase file and the condition ("After LOAD completes") that should
trigger reading it.

The pointer's **wording**, not its target, decides when the agent reaches the material — and how
reliably. A phase file that's essential but reached through a vaguely-worded "load when" condition
is a variance bug: the fix is sharpening the wording, not restructuring the file. Only inline the
material if sharpening the pointer genuinely fails.

A pointer does two jobs: state what the material is, and list the branches that should trigger
reaching it. Every word of an always-loaded pointer (a `SKILL.md` frontmatter `description`, a
PHASES table row) costs on every turn it's in context, so:

- **Front-load the leading word** — put the triggering condition first, not buried after
  explanation.
- **One trigger per branch** — synonyms restating one condition are the same branch written
  twice; collapse them.
- **Cut identity the body already carries** — don't restate what the phase file's own heading
  already says.

## Information hierarchy

Brana's own skill/phase-file split is this hierarchy made structural, ranked by how immediately
the agent needs the material:

1. **In-file step** — what `SKILL.md`'s numbered flow does, in order.
2. **In-file reference** — consulted on demand, still in the same file (a table, a rule list).
   A flat peer-set on one rung is a legitimate arrangement, not a smell.
3. **Disclosed reference** — pushed to a separate `phases/*.md` file, reached only when its
   PHASES-table condition fires. This is brana's phase-file mechanism exactly: each phase file
   is disclosed reference, loaded only at the step boundary that needs it.

Push too little down and the top (`SKILL.md`) bloats past what a reader can hold; push too much
down and steps the agent actually needs on every run go missing from view. **Progressive
disclosure** is the move down this ladder — the test is branching: inline what every invocation
needs, disclose what only some invocations reach. A skill whose `SKILL.md` inlines steps that
only the `refactor` strategy needs is failing this test for every `feature`-strategy invocation.

**Sprawl** is the failure mode: a file too long even when every line is live and unique.
Attention thins across the excess. The cure is the same ladder — split by branch (strategy
variants → their own phase file, as `strategies.md` already does) or by sequence (LOAD →
CLASSIFY → SPECIFY → ... as separate phase files, as `build`'s own registry already does).

## Completion criteria

Every step should end on a condition that tells the agent the work is done, judged on two axes:

- **Clarity** — can the agent tell done from not-done? A vague bound ("understanding reached")
  invites ending a step before it's genuinely finished. brana's `## ☑ Checkpoint` blocks
  (writing a `{"step":"NAME","completed":...}` line to `~/.claude/run-state/{task_id}.jsonl`) are
  a clarity mechanism — the checkpoint doesn't exist until the step's actual completion action
  ran, so there's no ambiguous middle state to prematurely call "done."
- **Demand** — how much the criterion requires. "Every AC line converted to the canonical field"
  forces more legwork than "ACs looked at." Demand isn't step-bound — it applies to flat
  reference too: a checklist item worded "every rule applied" carries the same exhaustiveness
  bar as a step worded "every step done."

The strongest criteria are both checkable and exhaustive — this is the rationale behind
checklist item 4's "early-exit conditions are stated" and "resume behavior... is defined."

## Leading words

A leading word is a compact concept already living in the model's pretraining, reused as a
single token rather than restated as a sentence each time — it recruits priors the model already
holds instead of paying definition tokens for a coined term. Brana already does this in places:
"blast radius," "gate," "spec-first," "no-op." The lever is deliberate reuse — checking whether a
recurring three-clause description ("fast, deterministic, low-overhead") could collapse into one
term instead, and then using that term consistently across `SKILL.md`, phase files, and rules
docs so the same word triggers the same behavior everywhere it appears.

**Negation is the failure mode beside this lever**: prohibitions ("don't skip TDD") drag the
forbidden behavior into context and make it more available, not less. State the positive target
("write the test first") so the banned behavior is never spoken; reserve prohibition for hard
guardrails that can't be phrased positively, and pair even those with the positive target.

## Pruning and the no-op test

- **Single source of truth** — one authoritative place per meaning. `branch-prefix.md` and
  `epic-ancestor-walk.md` exist precisely because this was violated once (t-2494): two files
  each restated the same mapping, drifted, and mislabeled branches. Duplication isn't just
  extra tokens — it inflates a meaning's apparent importance past its real rank and creates a
  second place that can go stale.
- **The environment is a source of truth too.** `--help` output, `tasks.json` schema,
  `package.json` scripts — a phase file that restates these is a cache, and a cache only earns
  its keep when the lookup itself is expensive. Leave one-command lookups to the environment,
  where they can't go stale in the doc.
- **The no-op test**, applied sentence by sentence: does this instruction change behavior versus
  what the model already does by default? If not, it's load with no effect and should be
  deleted outright — not trimmed to a shorter no-op. The test is model-relative, not
  reader-relative: settle a disagreement by running the document, not by debate. A weak leading
  word ("be thorough" when the agent is already thorough-ish) fails the same test; the fix is a
  stronger word, not a different technique.

Without a pruning discipline, the default fate is **sediment** — stale layers accumulating
because adding feels safe and removing feels risky, until auditing a skill means coring down
through history to find what's still live. This is the same failure class checklist item 8
("single-responsibility") and item 12 ("can be audited") are gating against — sediment is what
makes a skill un-auditable, not merely long.

---

## Worked example — `system/skills/close/SKILL.md`

Run as a doc-only worked example against this doc's levers (no skill body changed as part of
this task). `close` was picked as a known-sprawling skill — a session-ending skill whose job
(extract learnings, write handoff, detect doc drift, store patterns) already spans several
independent concerns.

Findings, run against each lever:

- **Information hierarchy** — `close`'s own PHASES table already disclosures its steps into
  separate phase files (`phases/extract.md`, `phases/handoff.md`, etc.), so the top-level ladder
  placement is sound. The `SKILL.md` body itself, though, carries several paragraphs of
  in-file reference (what auto-memory is, why it differs from session state) that a reader
  needs only once, not on every invocation — a disclosure candidate, not currently disclosed.
- **Context pointers** — the PHASES table's "Load when" column is mostly single-branch and
  well-worded ("Session ending" / "After learnings extracted"), consistent with the "one
  trigger per branch" rule. No variance-bug pointers found.
- **Leading words** — `close` already reuses "handoff" and "session state" as consistent
  tokens across its phase files rather than re-describing each concept per file — this lever
  is already in active use here, not a gap.
- **Pruning / no-op test** — the skill's Rules section (numbered list of behavioral rules)
  restates some defaults the model already follows without the reminder (e.g. "write clear
  commit messages" reads as a no-op given the global git-discipline.md rule is already loaded
  every session) — a candidate for deletion under the no-op test, not rewording.
- **Sprawl verdict** — `close` is not sprawling at the phase-file level (the disclosure
  structure is doing its job); the sprawl, where it exists, is concentrated in `SKILL.md`'s own
  body carrying reference material that belongs one rung further down the hierarchy.

No skill body was rewritten to act on these findings — that's follow-up work if judged worth a
task of its own, not part of this doc-only task's scope.

---

## Origin

Both source files (`SKILL.md`, `SKILL-MECHANICS.md`) fetched in full from
[mattpocock/skills](https://github.com/mattpocock/skills) (2026-08-17) rather than reconstructed
from the t-2830 research summary, so the levers above are transcribed against the primary
source, not a paraphrase of a paraphrase.
