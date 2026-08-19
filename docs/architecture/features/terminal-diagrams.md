# Feature: Terminal diagrams — proactive inline visual explanations

**Date:** 2026-08-19
**Status:** specifying
**Task:** t-2991

## Problem

Claude's terminal answers are prose-only by default. For architecture, flow, hierarchy, or
comparison questions, a small inline diagram (rendered as plain monospace text — Unicode
box-drawing, ASCII) often clarifies faster than prose, and the user has explicitly said they
find this useful. Two things bound the scope and must not be duplicated:

- `artifact-diagramming` is Claude's native platform skill for Mermaid diagrams **published as
  Artifacts** (a separate page, external to the terminal transcript) — not something this repo
  implements or governs, but real and present in the assistant's own skill list. That path
  stays untouched.
- `system/skills/backlog/phases/display-themes.md` already proves the mechanism works in this
  repo: box-drawing tree connectors and progress bars rendered as plain instructions in a
  skill file, no external renderer, no code — "themes are rendering instructions, not code
  logic" (`docs/architecture/features/tasks-theme-system.md`).

What's missing is a **general-purpose** version of that mechanism (any diagram shape, not just
backlog trees/bars) that fires **proactively** — without the user having to ask for a diagram
or invoke a skill by name.

## Decision Record (frozen 2026-08-19)
> Do not modify after acceptance.

**Context:** A skill only engages when invoked or routed to by name — it cannot itself decide,
mid-answer, that a diagram would help. A rule is injected into every session and shapes default
behavior without being called. "Proactive" requires the rule mechanism; the question was whether
to pair it with a skill for the diagramming reference material.

**Decision:** Split mechanism, confirmed by user (2026-08-19):
- The trigger heuristic (when to reach for a diagram) lives as a new `## Terminal diagrams`
  section **inside the existing always-loaded rule** `system/rules/work-preferences.md`, not a
  new standalone rule file — see Consequences below for why.
- A **skill** (`system/skills/terminal-diagrams/SKILL.md`) carries the full diagramming
  reference: general principles + primitives for rendering *any* diagram shape in fixed-width
  terminal text, not a closed enumerated list of styles. User's own framing: "every kind of
  diagram in general, written terminal inline."

**Consequences (revised 2026-08-19 — pre-edit challenger RECONSIDER, both findings fixed):**
The spec originally planned a standalone `system/rules/terminal-diagrams.md` and cited
`system/rules/README.md`'s prose ("cap: 28 KB", "Check 5a") for headroom. Pre-edit challenger
review caught that this prose is stale: the live enforcement (`system/scripts/context-budget.sh`,
t-2505; `validate.sh` "Check 5" delegates to it, not "5a") splits the budget into two
independently-gated pools, and the real AUTHORED pool (CLAUDE.md + always-load rules) cap is
**22528 bytes**, measured **22524/22528 used — 4 bytes of headroom** at review time (not the
~4.2KB the stale prose implied). A new standalone rule file — even a terse one — would have
blown the real cap immediately.

Fix applied: folded the heuristic into `work-preferences.md` as a new subsection, and tightened
that file's existing prose (Parallelism/Subagent strategy/Plan before building/Autonomous
execution/Automation through usage — meaning preserved, wording tightened) to net the file
*smaller* than before despite the addition (1446B → 1267B). Result: **183 bytes headroom**,
confirmed via `bash system/scripts/context-budget.sh --report`. `system/rules/README.md`'s
stale cap/check-number prose is a separate, small doc-fix follow-up — not corrected by this task.

Second challenger finding, also fixed: the spec's differentiation argument originally stated
"artifact-diagramming... exists" as repo-verified fact. It does not exist anywhere in this
codebase (grepped: zero hits in `system/skills/*`, `docs/`, `.claude/`) — it is Claude's native
platform Artifact-authoring skill, not a repo-governed mechanism. The Boundaries table below is
therefore a one-way fence (this rule won't reach for Artifacts) with no repo-side guarantee
against the platform's own native tendency to reach for an Artifact on the same trigger — a
residual, unmitigated overlap risk, noted rather than solved (out of scope to fix a platform
behavior from a repo rule).

## Constraints

- Terminal-only. No Mermaid, no Artifact call — diagrams are plain text in the response body.
- Rule stays terse (pointer, not reference material) to protect the always-load budget.
- Reuse existing conventions where they exist (display-themes.md's box-drawing tree/bar
  vocabulary) rather than inventing a parallel one.
- Must not fire on every answer — noise defeats the point. Heuristic favors structural
  content (3+ related components/steps/branches) over simple/linear answers.

## Scope (v1)

- Rule: proactive trigger heuristic + pointer to the skill.
- Skill: general diagramming reference — box/arrow flow, tree/hierarchy, comparison grids,
  boxed component/architecture diagrams — taught as composable primitives (boxes, connectors,
  arrows, alignment rules) so any shape can be drawn, not a fixed template per diagram "type."
  Explicitly covers the four styles the user called out as recommended v1 coverage (flow/
  pipeline, tree/hierarchy, comparison table, architecture/component) as worked examples of
  the general primitives — not an exhaustive or closed list.
- Explicitly out of scope: Mermaid/Artifact rendering (existing `artifact-diagramming` skill
  owns that), interactive/ANSI-color diagrams, diagram generation via external tooling.

## Assumptions

- **Trigger heuristic specifics** (when exactly to draw unprompted): not separately confirmed
  with the user beyond "proactively... when useful to understand and visualize." Chose a
  structural-content threshold (3+ related nodes/steps/branches, or an explicit before/after or
  multi-option comparison) — because "useful" without a threshold either never fires or fires on
  every answer, and a concrete floor is falsifiable/adjustable later — **needs confirmation via
  usage, not blocking further on it now.**
- **Rule scope declaration**: `always-load: true`, not `paths:`-scoped — because the behavior
  should apply to any conversation, not just sessions touching particular file paths, and
  scoping it to a path pattern would silently exclude the majority of cases where a diagram
  would help (most usefully, non-code explanatory answers).

## Design

**`system/rules/work-preferences.md` §Terminal diagrams** (new subsection, existing
`always-load: true` file):
- Two sentences stating the proactive trigger heuristic and pointing to the skill.
- Claude reads the skill content directly (Read tool) when it decides a diagram is warranted;
  no formal Skill-tool invocation required, since the rule already grants standing permission
  to draw the diagram inline.

**`system/skills/terminal-diagrams/SKILL.md`** (single file, no phases/ subdir — matches other
Small single-step skills like `sitrep`):
- Frontmatter: `name`, `description`, `keywords`, `group`, `allowed-tools` (Read only — this
  skill is read-as-reference, not invoked as a multi-step procedure).
- Body: composable primitives (box-drawing character set, arrows, connectors, alignment rules —
  extending display-themes.md's vocabulary), then 4 worked examples (flow/pipeline, tree/
  hierarchy, comparison table, architecture/component), then general composition guidance for
  shapes outside those 4.

## Boundaries

| Always | Ask First | Never |
|--------|-----------|-------|
| Render inline as plain monospace text in the response | Nothing — this is answer-formatting, not a system change | Call the Artifact tool for this purpose; use Mermaid syntax outside an Artifact context |

## Documentation Plan

- [x] **Tech doc** — this file (`docs/architecture/features/terminal-diagrams.md`).
- [x] **No separate user guide** — the rule/skill pair IS the user-facing behavior; a guide
  would just restate the rule.
- [x] **Existing docs to update** — `docs/reference/skills.md` regenerated via
  `brana reference generate` (entry present, includes the Read-as-reference note in the
  skill's own description). `system/rules/README.md`'s stale budget-cap prose ("28 KB",
  "Check 5a") is a separate, small follow-up — not fixed by this task, flagged in the
  Decision Record above.

## Challenger findings

**Pre-edit challenger (2026-08-19), verdict RECONSIDER — both critical findings fixed, see
Decision Record §Consequences:**
1. Budget cap cited was stale vs. the live `context-budget.sh` enforcement (4B real headroom,
   not ~4.2KB) — fixed by folding into `work-preferences.md` instead of a new rule file.
2. `artifact-diagramming` was stated as a verified-existing repo mechanism; it's actually
   Claude's native platform skill, not repo-governed — Problem section reworded, residual
   overlap risk (platform's own native Artifact tendency vs. this rule's trigger) noted as
   unmitigated and out of scope.

Warnings (accepted, not blocking): docs/reference/skills.md registry entry added to
Documentation Plan above; trigger-heuristic interaction with context-budget.md's orange/red
zone guidance stays an open question for the Assumptions section, resolved via usage.
