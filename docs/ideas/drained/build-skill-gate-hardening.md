# Build Skill Gate Hardening — Step 4a

> Brainstormed 2026-05-19. Status: implemented.

## Problem

Step 4a of `system/procedures/build.md` uses a heuristic gate:

> "If NO skills results were returned (or all below 0.3) AND the task involves a specific technology..."

This silently bypasses skill acquisition whenever ruflo returns *any* non-empty result — even if those results are topically unrelated to the task's tech context (e.g., documentation pattern results for a Rust integration test task). This caused t-1466 to proceed without `/brana:rust-skills`, missing 179 Rust idiom rules.

Root structural gap: ruflo does not index skills in its knowledge/pattern namespaces. Step 4's `namespace: "skills"` check almost never fires. Step 4a compensates, but its gate condition is too permissive.

## Proposed Solution

Replace the heuristic with a deterministic 3-signal detection chain + tech-aware result validation.

### Detection Chain (Step 4a)

```
Signal 1: Task description + explicit tags → tech keywords
         ("Rust", "[rust]", "async", "Cargo", "CLI", ".rs", etc.)

Signal 2: Project manifest files (static, always reliable)
         Cargo.toml present → Rust
         pyproject.toml / uv.lock → Python
         package.json + tsconfig.json → TypeScript

Signal 3: File paths in task description/context
         Extract extensions from mentioned paths → tech inference
         ("add test to brana-memory/src/lib.rs" → Rust unambiguous)

Bonus:   Parent task tag/keyword inheritance (one hop only — not siblings)
```

Signals are checked in order; first match wins. If zero signals fire → skip detection entirely (no tech inferred, 4a does not trigger).

### Skill Matching (No New Fields Needed)

When tech is detected:
1. Scan installed skills: find any SKILL.md whose `keywords` list overlaps with detected tech terms
2. The `keywords` field already exists and is populated across all tech-domain skills (audit: 2026-05-19 shows 100% coverage for code skills)
3. `caveman` and other style/utility skills (no `task_strategies` with code work) are excluded by design

### Tech-Aware Ruflo Result Validation

After matching a skill by keywords:
- Check if any ruflo result key overlaps with that skill's `keywords` list
- If NO overlap → matched skill was not represented in LOAD → trigger 4a
- If overlap → skill knowledge present in LOAD → skip 4a (gate passes)

This replaces the binary "empty/non-empty" check with a **tech-relevance filter**.

### Mandatory Ask + Warn-on-Skip

When 4a triggers:
```
AskUserQuestion:
  question: "Detected {tech} context. No {skill} knowledge loaded. Search marketplace or load skill?"
  header: "Skill Gap"
  options:
    - "Load {skill} now (Recommended)"
    - "Search marketplace for alternatives"
    - "Skip"
```

If user skips:
- Append to task context: `skill-gap-warning: {skill} available but not loaded (skipped {date})`
- Auditable via `brana backlog search "skill-gap-warning"`
- "LOAD never blocks" invariant preserved

## Design Decisions

| Decision | Rationale |
|----------|-----------|
| `keywords` field (not `tech_context`) | Already exists, no new frontmatter needed |
| Project manifests over sibling task tags | Manifests are static and file-system-verifiable; sibling tags are human-authored and ambiguous |
| Warn-on-skip (not block) | Preserves "LOAD never blocks" invariant while creating audit trail |
| Confidence threshold unchanged (0.3) | Threshold serves LOAD breadth; the gate uses type-relevance, not confidence |
| Interim framing | This patch explicitly sunsets when Skill Registry (t-608) ships |

## Interim Status

This is an **explicitly scoped stopgap** while the Skill Registry MCP server (t-608) is not yet built.

When t-608 ships:
- Step 4 becomes: `skill_suggest(tech_context)` → results present = offer to load
- Step 4a becomes: `skill_suggest(tech_context)` → no results = offer acquisition
- This procedure's detection chain and keyword-matching logic is removed entirely
- Add `SUNSET: when Skill Registry (t-608) ships, remove steps 4 and 4a` comment in build.md

## Risks

| Risk | Mitigation |
|------|-----------|
| Tech detection false positives (doc task in Rust project) | Mandatory ask, not mandatory load — Skip is always valid |
| Gate adds friction | Only fires when ruflo results don't contain tech-matching keys; covered builds pass unchanged |
| `keywords` drift in SKILL.md | Add validate.sh lint: assert `keywords` present for all skills with `task_strategies` |
| t-608 never ships; patch becomes permanent | `SUNSET` comment in build.md; t-608 link in backlog context |

## Engineering Disciplines

- **DDD:** No ADR needed — procedure edit, not architecture decision. t-608's ADR already covers the long-term direction.
- **TDD:** Gate logic is prose. Validation: run 5 consecutive Rust builds, confirm all offered rust-skills. Document as AC in task.
- **SDD:** Update `docs/architecture/build.md` or add field note to CLAUDE.md. Same commit as build.md edit.
- **Docs strategy:** Refactor type → tech doc update only

## Next Steps

1. **S / t-?**: Edit `build.md` step 4a — replace heuristic with 3-signal detection chain + tech-aware result validation
2. **S / t-?**: Add `validate.sh` lint rule — assert `keywords` presence for all SKILL.md with `task_strategies` containing code-work strategies
3. **S / t-?**: Add field note to `thebrana/.claude/CLAUDE.md` — document `keywords`-as-tech-gate pattern
4. **Link to t-608** — tag the step 4a edit task with `context: sunset when t-608 ships`
5. **Later (M, t-608)**: Skill Registry MCP — when built, step 4/4a rewrites to `skill_suggest()`; heuristic detection removed

## Concrete Example (t-1466)

| Signal | Value |
|--------|-------|
| Task description | "TDD spec for brana memory write" — no explicit Rust keyword |
| Project manifest | `system/cli/rust/Cargo.toml` present → **Rust detected** |
| File paths in context | `brana-memory/src/` → `.rs` → **Rust confirmed** |
| Matched skill | `brana:rust-skills` (keywords: [rust, best-practices, code-quality, optimization]) |
| Ruflo result keys | Documentation patterns — no key contains `rust` → **gap detected** |
| Gate action | AskUserQuestion: "Detected Rust context. rust-skills not loaded. Load now?" |
| t-1466 actual outcome | Silent bypass ✗ |
| Hardened outcome | Mandatory ask ✓ |
