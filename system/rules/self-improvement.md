# Self-Improvement

Automatic learning. Runs every session without invocation.

- **On correction**: capture the pattern in auto memory immediately. What went wrong, the fix, what prevents recurrence.
- **On session start**: read and apply MEMORY.md patterns. Follow learned conventions without being told again.
- **On session end**: write learnings to auto memory — decisions, patterns, mistakes. A few lines, no skill needed.
- **On failure**: stop. Reassess from scratch, don't patch forward.
- **On repeated patterns**: same workaround recurring across sessions → propose a rule, hook, or convention change.

## Where to store what

Use `/brana:retrospective` to classify and route. The taxonomy:

| Type | Destination | Gate |
|------|------------|------|
| Rule ("always/never") | `system/rules/` draft → human places | human |
| Decision (why X over Y) | ADR stub → human commits | human |
| Reference (where something lives) | `~/.claude/memory/portfolio.md` | auto |
| Pattern (reusable solution) | `~/.claude/memory/patterns.md` (cap 50) | auto |
| Knowledge (domain fact, model) | `~/.claude/memory/knowledge-staging.md` (cap 30) | auto |
| Session (resume-only state) | native memory dir — skip retrospective | auto |

**Never create `feedback_*.md` files.** All learnings route through the taxonomy.
**MEMORY.md is an index, not a store.**
