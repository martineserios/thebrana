# /brana:content — Seed-to-Post Guided Workflow

> Brainstormed 2026-03-30. Status: idea.

## Problem

The content pipeline stops at seed generation (`/brana:harvest` → `ideas.md`). From `[seed]` to published post, there's no structure — just a blank page and manual bookkeeping across multiple files.

## Proposed solution

A stateless `/brana:content` skill with two subcommands:

- **`/brana:content draft [seed-keyword]`** — pick a seed, generate a structured draft skeleton with guiding prompts and expanded angles, save to `linkedin/content/drafts/YYYY-MM-DD-slug.md`
- **`/brana:content publish [draft-file]`** — bookkeeping: update `ideas.md` status, append to `published.md`, show pillar distribution

### Draft subcommand flow

1. **PICK** — Show active `[seed]` entries from `ideas.md`. Display hook, angle, pillar, systems patterns. Show pillar distribution (informational, no nudge). AskUserQuestion for selection. Update `ideas.md`: `[seed]` → `[picked]`.
2. **SKELETON** — Read seed's angle, pillar, components, systems patterns. Apply pillar-specific structural pattern (Zoom, Reversal, Before/After, Cross-Domain, Subtraction). Generate draft file with:
   - Hook suggestion (from seed angle)
   - Guiding prompts per section ("What's the core tension?", "What surprised you?")
   - Expanded bullet points from seed angle (2-3)
   - Systems pattern tie-in suggestion
   - Closer prompt ("One sentence takeaway")
   - Metadata footer (pillar, seed reference, structural pattern used)

### Publish subcommand flow

1. **DETECT** — Find draft files in `linkedin/content/drafts/`. If multiple, AskUserQuestion. If argument provided, use that file.
2. **BOOKKEEP** — Update `ideas.md`: `[picked]` → `[published]`. Append to `linkedin/content/published.md`. Show updated pillar distribution.

## Design decisions

| Decision | Resolution | Rationale |
|----------|-----------|-----------|
| Voice/tone review | Deferred to Phase B | Phase A builds authentic voice through practice; reviewing against theory calcifies prematurely |
| Pillar balance nudging | Show, don't nudge (Phase A) | 3 posts/week × 4 pillars = impossible exact balance; enthusiasm > distribution early |
| State management | Stateless | Draft file is implicit state; each invocation is fresh; avoids unnecessary complexity |
| Skeleton depth | Prompts + seed expansion | Guiding questions + expanded angles + systems tie-in. Not a full draft, not empty scaffolding |
| Subcommands | `draft` + `publish` | Natural breakpoint at "you write." No session to resume |
| Phase gate | Hybrid — build minimal now | Full automation waits for Phase B (after 12 posts). This assists without replacing judgment |

## Phase B additions (after 12 posts)

- Voice/tone review step (between draft and publish)
- Pillar balance nudging in seed picker
- Carousel/visual format support
- Auto-language detection (EN/ES)

## Risks

| Risk | Mitigation |
|------|-----------|
| Skeleton becomes a crutch | Prompts are questions, not answers — forces thinking |
| Bookkeeping step skipped | Skill reminds at end of `draft`; `publish` is fast enough to not skip |
| Pillar data shown but ignored | Fine for Phase A — awareness without pressure |

## Implementation

**Skill location:** `~/enter_thebrana/linkedin/.agents/skills/content/SKILL.md` (linkedin repo, not thebrana)
**Invocation:** `/content draft` and `/content publish` (from linkedin project context)
**Phase:** t-732 in thebrana backlog
**Status:** t-736 completed (SKILL.md + symlink). Remaining: t-737 through t-743.
