# Brana Enhancements from addyosmani/agent-skills Analysis

> Researched 2026-04-13 from https://github.com/addyosmani/agent-skills (Addy Osmani, Google Chrome DevRel).
> Status: ideas for adoption — none implemented yet.

## Context

`addyosmani/agent-skills` is an independent production framework (not a fork of `vercel-labs/agent-skills`) encoding Google engineering practices. It has 20 skills across 6 development phases. Key architectural differences from brana:

| Dimension | addyosmani/agent-skills | brana |
|---|---|---|
| Enforcement | Skill prose (rationalization + verification sections) | Hooks (stop gates), rules, frontmatter |
| Memory | None (stateless) | ruflo MCP, MEMORY.md, patterns |
| Skill format | Plain markdown, portable across 6+ agents | Frontmatter-rich, CC-specific, ruflo-routed |
| Entry points | 7 slash commands in `.claude/commands/` | 35+ skills + commands in `system/` |
| Cross-session learning | None | Knowledge pipeline, session insights |

**Key validation:** Osmani independently arrived at the same "procedure body in separate file" pattern as brana's ADR-034 stub pattern. Architecture confirmed.

---

## Enhancement 1: Anti-Rationalization Sections in Skills

### What Osmani does
Every skill includes a `## Rationalizations` section listing common excuses agents give to skip steps, paired with explicit rebuttal text. Examples:
- "The tests are obvious" → "Tests document behavior for future contributors — obvious now, opaque later"
- "We can add docs later" → "Later never comes. Docs written at implementation time are 10x more accurate"
- "This is too small for a spec" → "Scope creep starts with 'too small'. One sentence spec beats none"

### Why it matters for brana
Brana enforces behavior via hooks (stop gates) and rules. But hook coverage is limited to detectable events. Anti-rationalizations address the **compliance gap**: when an agent has the capacity to skip a step and no hook fires. It's behavioral enforcement embedded in skill prose — free to implement, zero overhead.

### Proposal
Add `## Anti-Rationalizations` section to these high-stakes brana skills:
- `/brana:build` — "The spec is obvious", "TDD slows me down", "I'll doc it in the commit"
- `/brana:ship` — "The tests cover enough", "It works locally"
- `/brana:close` — "Nothing notable happened this session"
- `/brana:reconcile` — "The drift is minor"

### Effort / Value
- Effort: **S** (prose additions to existing procedures)
- Value: **HIGH** — closes behavioral compliance gaps hooks can't reach
- Task: create via `brana backlog add`

---

## Enhancement 2: Verification Checklist Section Standard

### What Osmani does
Every skill ends with a concrete checklist. "Seems right" is called out explicitly as insufficient. Example from spec skill:
- [ ] Human has reviewed and approved the spec
- [ ] Success criteria are testable (not vague)
- [ ] Spec is saved to repository (not just in chat)
- [ ] Implementation approach has been validated

### Why it matters for brana
Brana procedures have narrative exit criteria embedded in prose. They're easy to overlook. A structured checklist at the end of every skill is:
1. Scannable — agent can check items without re-reading the full procedure
2. Auditable — user can see exactly what the agent claims to have done
3. Gate-compatible — could be wired to a hook in the future

### Proposal
Standardize a `## Verification` checklist section at the end of all skill procedures in `system/procedures/`. Format:

```markdown
## Verification

Before closing this skill, confirm:
- [ ] {exit criterion 1}
- [ ] {exit criterion 2}
- [ ] {exit criterion 3}
```

Start with the highest-stakes skills: `build.md`, `ship.md`, `close.md`, `reconcile.md`.

### Effort / Value
- Effort: **S** (structured additions to existing procedures)
- Value: **HIGH** — standardizes exit criteria across all skills
- Task: create via `brana backlog add`

---

## Enhancement 3: `context-engineering` Skill

### What Osmani does
A dedicated skill for "Strategic information delivery to maximize output quality." Covers:
- What context to include before acting (relevant files, prior decisions, constraints)
- How to scope context to the task (avoid context bloat)
- When to prune (what to exclude)
- How to structure context for maximum model comprehension

### Why it matters for brana
Brana discusses context engineering in MEMORY.md field notes and the 4-levers framework (Rules + MCP + Skills + SDD). But there is **no skill that teaches the agent how to engineer its own context** before starting work. The agent relies on whatever the user provides plus the LOAD step in build/research.

A `context-engineering` skill would:
1. Run early in complex tasks to surface the right files, decisions, constraints
2. Make the LOAD step in `/brana:build` and `/brana:research` more principled
3. Reduce context rot by setting scope at the start

### Proposal
Create `system/skills/context-engineering/SKILL.md` + `system/procedures/context-engineering.md` with:
- When to invoke (before any M+ effort task)
- Protocol: identify task scope → surface key files → load relevant decisions → prune irrelevant → set budget
- Integration: referenced by `/brana:build` LOAD step

### Effort / Value
- Effort: **M** (new skill + procedure)
- Value: **HIGH** — closes a genuine gap in brana's build workflow
- Task: create via `brana backlog add`

---

## Enhancement 4: `deprecation-and-migration` Skill

### What Osmani does
A skill covering:
- Safe deprecation paths (warn before remove)
- Migration strategies (parallel run, feature flags, gradual rollout)
- Backwards compatibility analysis (Hyrum's Law cited explicitly)
- Communication patterns (changelogs, migration guides)

### Why it matters for brana
Brana has no migration skill. This is a gap that surfaces repeatedly:
- Rust CLI migration (Python → Rust across multiple modules)
- Knowledge pipeline evolution (tiers, formats changing)
- Skill tiering migration (full skills → stubs per ADR-034)
- Future: MCP tool API changes, schema migrations

### Proposal
Create `system/skills/deprecation-and-migration/SKILL.md` + `system/procedures/deprecation-and-migration.md` with:
- Deprecation checklist: timeline, warning period, migration guide
- Migration protocol: parallel run → validate → cut over → remove old
- Backwards compat analysis: who depends on this? (grep callers before removing)
- Brana-specific: integrates with `/brana:reconcile` for drift detection post-migration

### Effort / Value
- Effort: **M** (new skill + procedure)
- Value: **MEDIUM** — directly useful for ongoing Rust migration work
- Task: create via `brana backlog add`

---

## Other Patterns Worth Monitoring

### Specialist Persona Invocation
Osmani's system has 3 named agent personas (`code-reviewer`, `test-engineer`, `security-auditor`) invoked explicitly from within skill execution. Brana has `system/agents/` but lacks **named persona invocation from skills**. Low priority — brana's agents fire via delegation logic, not skill calls. Watch for community convergence.

### Boundaries Pattern (Always / Ask First / Never)
Spec template includes per-feature scope tiers. More granular than brana's global rules. Could be useful in SDD specs for high-stakes client work. Low priority until we have a concrete use case.

### Multi-Platform Portability
Osmani's plain-markdown format works across Cursor, Gemini CLI, Windsurf. Brana's frontmatter (`group`, `status`, `allowed-tools`) is CC-specific. This is a deliberate tradeoff: brana gets ruflo semantic routing, Osmani gets portability. Not a gap — a feature. Worth documenting in architecture docs as intentional.

---

## Source

- Repo: https://github.com/addyosmani/agent-skills
- Research task: t-1208
- Related brana docs: `docs/dimensions/11-ecosystem-skills-plugins.md`, `docs/architecture/skills.md`
