# Feature: Reconcile propagation — scan dim "Could Adopt" sections into the backlog

**Date:** 2026-09-07
**Status:** built
**Task:** t-1706

## Problem

Dimension docs (`brana-knowledge/dimensions/*.md`) are a pull system: enrichment sessions
write `Could Adopt` / `What X Could Adopt` sections listing ideas worth pursuing, but nothing
reads them back out unless someone happens to reopen the doc and manually notices a line. The
result is candidate ideas that sit permanently unactioned — dim enrichment is write-only.
`/brana:reconcile --scope propagation` already cascades errata and validates the spec graph on
a pull basis (PROP-1, PROP-2); it has no push-capable step that surfaces untracked ideas from
dimension docs into the backlog.

## Decision Record (frozen 2026-09-07)
**Context:** Layer 1 of the link-signal enrichment pipeline (t-3306–t-3314, ADR-093) built the
analogous push mechanism for URL/link signals — score post-sync, queue as pending backlog
candidates, cap + expire via wave mechanics. Layer 2 (the link-signal scan→propose pump itself)
stays deferred per ADR-093. t-1706's own context flags it as "the same scan→propose pump" that
should serve dim docs and links, folding into Layer 2 once Layer 2 is planned. Layer 2 has not
been planned as a task yet (verified 2026-09-07 — no backlog match), so there is nothing to fold
into today.
**Decision:** Build the dim-doc scan step now, scoped only to dimension docs, using the existing
`reconcile` procedural-markdown pattern (no new script, no new queue infrastructure). Keep the
extraction and diff logic simple enough that a future Layer-2 pump could reuse the same shape
(scan → extract → diff-against-backlog → human-approve → add) without this step needing to be
rewritten — but do not build the generalized pump itself; that is Layer 2's job when it is
planned.
**Consequences:** This step adds no new persistent state (no queue, no wave). Every run is a
fresh scan; nothing is cached or deduped across runs except by re-checking the live backlog at
run time. If Layer 2 later centralizes queueing (wip_limit, expiry, dead-letter per ADR-093),
this step's extraction logic is the part that gets lifted into it — the human-approval gate
stays local to reconcile either way.

## Constraints

- No new backlog task type, wave, or persistent queue — out of scope (that's Layer 2).
- Never auto-create backlog tasks without human approval (reconcile's existing rule: "Never
  auto-create new capabilities" / "Ask for clarification whenever you need it" extends here —
  ideas are surfaced, not silently added).
- Must not re-surface ideas that already have a matching backlog task (avoid duplicate-task
  spam on every reconcile run).
- Follows the existing `knowledge.md` KNOW-1 procedural shape: no new script file, no new test
  file — this is a markdown-interpreted step consistent with propagation's other steps (PROP-1,
  PROP-2) and knowledge's DECAY steps (KNOW-1/2/3), none of which have scripted/unit-tested
  internals.

## Scope (v1)

- New step `PROP-3` in `phases/propagation.md`, under `--scope propagation`.
- Scans `brana-knowledge/dimensions/*.md` for headings matching `Could Adopt` or `What * Could
  Adopt` (case-insensitive), extracts the list items under each matching heading as candidate
  ideas.
- For each candidate, diffs against `brana backlog query --status pending` +
  `--status in_progress` (`--status` takes one value, not a comma list — run both and merge) by:
  subject keyword overlap (2+ significant words in common) OR tag overlap (1+ shared tag,
  inferred from the dim doc's slug/topic).
- Untracked candidates (no match) are presented via `AskUserQuestion` (multiSelect) for the user
  to approve → `backlog_add`.
- PROP-REPORT gains a line: dim ideas scanned / already tracked / newly added.

## Research

- `knowledge.md` KNOW-1 (stale dimensions) is the direct structural precedent: glob → per-file
  signal extraction → threshold/match logic → `AskUserQuestion` multiSelect → apply.
- ADR-093 (link-signal enrichment) documents the sibling Layer-2 decision record this step
  deliberately does not duplicate: queue-vs-valve, post-sync scoring, wip_limit + dead-letter —
  all out of scope here because this step has no queue.
- t-1706's task context (written 2026-05-27, updated 2026-09-06) is the origin spec; this doc
  formalizes it per the project's M+ effort feature-spec gate.

## Assumptions

- `Could Adopt` sections are Markdown headings (`##`/`###`) followed by a bullet list — if a dim
  doc uses prose instead of bullets under such a heading, the step extracts the paragraph text
  as a single candidate rather than skipping it. **Assumption: prose-form candidates are rarer
  and still worth surfacing — needs confirmation if dim doc authors object to noisy prose
  candidates in the approval prompt.**
- "Subject keyword overlap (2+ significant words)" reuses the same fuzzy-match bar as
  `build/phases/load.md` Step 0a cross-reference — no new threshold invented.

## Behavior

- Running `/brana:reconcile --scope propagation` (or its turn in `--scope all`) now includes a
  PROP-3 step between PROP-2 and PROP-REPORT.
- If dim docs contain no `Could Adopt` sections, or every candidate already matches an existing
  backlog task, PROP-3 reports "0 untracked ideas found" and adds nothing — no interactive
  prompt fires.
- If untracked candidates exist, the user sees a multiSelect prompt listing each candidate (dim
  doc + heading + candidate text), selects which to add, and those become new backlog tasks
  (`kind: feature` default, tagged with the source dim slug).
- PROP-REPORT's summary table gains a row for PROP-3's counts.

## Edge Cases

- A dim doc with multiple `Could Adopt` headings (e.g. one per numbered section, like dim 49's
  §6.3 style): each heading's list is extracted separately, but candidates are still diffed and
  presented as one flat list (no need to preserve per-heading grouping across the whole run).
- A candidate whose text is only a doc cross-reference (e.g. "see dim 44") with no actionable
  verb: still surfaced — the human approval gate is the filter, not the extraction step.

## Design

- **File touched:** `system/skills/reconcile/phases/propagation.md` — add PROP-3 section,
  following the KNOW-1 structural pattern (numbered steps, explicit `[INTERACTIVE]` marker,
  match logic spelled out in prose + one inline bash glob).
- **File touched:** `system/skills/reconcile/SKILL.md` — Step Registry list for `propagation`
  gains `PROP-3` between `PROP-SCAN`/`PROP-APPLY` and `PROP-REPORT`; the domain table's
  "What it checks" cell for Propagation gains "+ dim Could Adopt scan".
- No new files, no new scripts, no new backlog fields.

## Boundaries

| Always | Ask First | Never |
|--------|-----------|-------|
| Scans dim docs read-only; never edits a dim doc | Adding a candidate to the backlog (via the multiSelect approval) | Auto-adds a backlog task without the approval prompt |
| Diffs against the live backlog at run time (no cache) | — | Builds a persistent queue, wave, or dedup store (Layer-2 scope) |

## Testing Strategy

- **Unit:** none — procedural markdown step, no scripted logic to unit test (matches sibling
  steps PROP-1/PROP-2/KNOW-1/2/3, none of which carry unit tests).
- **Integration:** manual dry run against `brana-knowledge/dimensions/` during CLOSE
  verification — confirm at least one known `Could Adopt` section (e.g. dim 49 §6.3, cited in
  t-1706's original context) is correctly extracted and correctly diffed as already-tracked or
  untracked.
- **E2E:** none.
- **Mock policy:** n/a.

## Documentation Plan

- [x] **Tech doc** — this file (`docs/architecture/features/reconcile-dim-could-adopt-scan.md`).
- [x] **User guide** — `system/skills/reconcile/SKILL.md` itself is the user-facing doc for this
  command; its domain table and step registry are updated in the same change (no separate
  `docs/guide/` page — reconcile has none for other scopes either).
- [ ] **Existing docs to update** — none beyond SKILL.md/propagation.md themselves.

## Challenger findings

Run 2026-09-07 (effort M mandates the gate regardless of the earlier build-plan skip estimate).
Verdict: **PROCEED WITH CHANGES** — 1 finding, max severity 3.

- **Security (severity 3):** PROP-3 step 6 originally built a `brana backlog add --subject "..."`
  shell command by interpolating dim-doc-sourced candidate text directly into a double-quoted
  argument — an injection surface for candidate text containing `"`, a backtick, or `$(...)`.
  Deviated from the step's own cited precedent (KNOW-1/2/3 use MCP tools, not shell CLI calls).
  **Fixed:** replaced with a structured `mcp__brana__backlog_add(...)` call.
- **Sibling (not fixed here):** `system/skills/backlog/phases/done-and-add.md:78` has the same
  raw-CLI-interpolation pattern for a user-supplied epic slug — lower risk (direct user input,
  not doc-scraped text) but same pattern class. Filed as t-3320, out of scope for this task.
- AC coverage, spec/diff alignment, and the `--status` single-value fix: all confirmed correct,
  no other findings.
