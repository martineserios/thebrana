# DDD + SDD Lifecycle Artifacts

> Brainstormed 2026-06-16. Two adversarial challenge passes. Status: design-ready idea.

## Problem

`docs/domain/` has only MODEL-001 after months of work — no mechanism to grow it organically.
The system already has a feature spec convention at `docs/architecture/features/{slug}.md`
(61 files, defined in `build/phases/specify.md:69`), but:

1. No quality bar on behavioral content — `## Behavior` and `## Edge Cases` sections don't exist in the current template
2. The spec file requirement isn't enforced — gate passes on any `docs/` commit
3. No extraction pipeline from spec docs to domain model docs

**The gap is enforcement, quality bar, and extraction — not a missing artifact type.**

## Proposed Solution

Three targeted patches on the existing structure.

```
docs/architecture/features/{slug}.md  →  nightly cron extraction  →  docs/domain/MODEL-NNN-*.md  →  index at session start
        (Phase 1: enforce quality)              (Phase 2: extract)              (Phase 3: surface)
```

## Design Decisions

### No new spec location

The existing convention is `docs/architecture/features/{slug}.md`. No `docs/specs/` directory —
that would introduce a third competing convention alongside `docs/architecture/features/` and
`docs/architecture/decisions/`.

### ADR vs feature spec

| | Feature spec | ADR |
|---|---|---|
| Answers | "What does it do? Edge cases?" | "Which approach? Why?" |
| Trigger | M+ tasks (spec file required) | Only when ≥2 approaches were weighed |
| Lifetime | Permanent feature doc | Permanent system history |
| Location | `docs/architecture/features/{slug}.md` | `docs/architecture/decisions/ADR-NNN-*.md` |

### Phase 1 — Template update + spec file gate

**Template change (Option C — bridges old and new):**
- New specs: add `## Behavior` (≥3 sentences) + `## Edge Cases` (≥2 items) between `## Problem` and `## Decision Record`
- Existing 61 specs: satisfy the gate via `## Scope` + `## Constraints` (already present in all specs written to the current template) — no forced backfill

**Gate:**
- Advisory PreToolUse warn on M+ branch if no `docs/architecture/features/` file exists
- Gate checks **file existence** (not whether SPECIFY ran — that's the same thing in practice)
- **Hardening criteria:** after 5 M+ tasks → if >80% have a spec file: harden to blocking; if <50%: trim template. Deadline: 6 weeks from first task.

**AC lines:**
- AC: lines in task `context` remain valid for now
- SPECIFY step optionally generates AC lines from the feature spec's `## Acceptance criteria` section
- Both sources are valid; feature spec is authoritative when both exist

### Phase 2 — Domain extraction via nightly cron

**Trigger: nightly cron (ADR-052 Track 2), not `/brana:close`.**

`--finish` fires rarely in a solo workflow with long-lived branches. Extraction at close time
adds cognitive load at the worst moment. Nightly cron already processes session diffs.

**Process:**
1. Cron scans `docs/architecture/features/*.md` for specs not yet in `.extraction-processed.json`
   (or where content hash changed since last extraction)
2. Quality gate: skip if no `## Behavior` section AND no `## Scope` section (catches truly empty specs)
3. Extraction prompt scoped to `## Problem`, `## Behavior`/`## Scope`, `## Edge Cases`/`## Constraints` only —
   NOT `## Implementation`, `## Key Files`, `## Code Flow` (avoids extracting implementation artifacts)
4. Draft candidates saved to `docs/domain/.extraction-staging.json`
5. Processed log updated in `docs/domain/.extraction-processed.json`: `{path, content_hash, extracted_at}`

**Session-start surfacing:**
- If staging file has pending entries: *"N domain entity candidates pending (oldest: X days) — review? [y/skip]"*
- "y" → opens staging for review and guided promotion to `docs/domain/MODEL-NNN-*.md`
- "skip" → no action, candidates remain

**Queue hygiene:**
- 30-day expiry: candidates older than 30 days auto-removed on next cron run
- 50-candidate cap: extraction pauses when staging hits 50 (prevents silent accumulation)
- Re-extraction: if spec content hash changes, it re-enters the extraction queue

**One-time backfill (after Phase 1 ships):**
- Run a single extraction pass on all 61 existing specs using `## Problem` + `## Scope` as source
- Review draft manually before any promotion (existing specs are implementation guides;
  extraction will yield noisier candidates than future Behavior-section specs)
- Deferred until after Phase 1 pilot so existing specs may gain Behavior sections first

### Phase 3 — Domain index

`docs/domain/index.md` auto-generated from all `MODEL-*.md` files.
Surfaced in `/brana:sitrep` and session startup hook.

## What Was Ruled Out (and Why)

| Option | Rejected because |
|---|---|
| `docs/specs/t-NNN-slug.md` (new directory) | Third competing convention; `docs/architecture/features/` already exists |
| Extraction at `/brana:close --finish` | Fires rarely; wrong moment for cognitive triage |
| Advisory gate without hardening criteria | All prior advisory gates stayed advisory permanently |
| Task-scoped spec docs (archive after merge) | Phase 2 needs a stable permanent corpus |
| `.specify-done` marker enforcement | File existence is the real failure mode; solo workflow doesn't need extra mechanism |
| Extraction from Implementation/Key Files sections | Yields implementation vocabulary, not domain concepts |

## Risks

- **Thin specs pass the gate** → mitigated at extraction time (quality gate skips Scope-only specs for Phase 2)
- **Backfill extraction is noisy** → manual review required; existing specs are implementation guides
- **Advisory gate stays advisory** → binary hardening criteria with 6-week deadline
- **Cron extraction is expensive** → scoped extraction prompt + quality gate keeps per-spec cost low; sidecar deduplication prevents re-extraction

## Next Steps

**Phase 1 — Template + gate (start here)**
1. Update `system/skills/build/phases/specify.md` template: add `## Behavior` + `## Edge Cases` sections
2. Update gate logic: "spec file required" for M+ tasks; existing specs satisfy via Scope + Constraints
3. Advisory PreToolUse warn on M+ branch without `docs/architecture/features/` file
4. Pilot: 5 M+ tasks → measure compliance rate → apply hardening criteria at 6-week mark

**Phase 2 — Nightly extraction (after Phase 1 pilot)**
5. Extend nightly cron: scan `docs/architecture/features/`, extract from Problem + Behavior/Scope sections only
6. Sidecar files: `.extraction-staging.json` (candidates) + `.extraction-processed.json` (watermark)
7. Session-start hook: surface count line if staging non-empty
8. Queue hygiene: 30-day expiry, 50-candidate cap
9. One-time backfill pass after pilot (deferred)

**Phase 3 — Index**
10. `docs/domain/index.md` auto-generation from `MODEL-*.md`
11. Surface in `/brana:sitrep` + session start hook
