# Self-Improvement

Automatic learning. Runs every session without invocation.

- **On correction**: capture the pattern in auto memory immediately. What went wrong, the fix, what prevents recurrence.
- **On session start**: read and apply MEMORY.md patterns. Follow learned conventions without being told again.
- **On session end**: write learnings to auto memory — decisions, patterns, mistakes. A few lines, no skill needed.
- **On failure**: stop. Reassess from scratch, don't patch forward.
- **On repeated patterns**: same workaround recurring across sessions → propose a rule, hook, or convention change.

## Where to store what

| Classification | Destination | Test |
|---------------|-------------|------|
| Directive ("always/never/must") | `rules/*.md` | Prescribes behavior |
| Convention (stack, architecture) | `CLAUDE.md` | Project identity |
| Automation (event-triggered) | `hooks/` | Should fire on tool use |
| Recipe (multi-step workflow) | `skills/` | Reusable command |
| Log entry (something happened) | `/brana:log` | Event record |
| Derivable (command/file output) | Nowhere | Run the command instead |
| **True memory** | **MEMORY.md** | External API details, pointers not in code |

**MEMORY.md is the last resort.** Reference, don't cache. Cached facts drift silently.

```
Example — on correction:

  User: "don't mock the database in integration tests"
  → feedback_no-db-mocks.md in rules/ (directive)

Example — where does this go?

  "Always use uv, never python"   → rules/  (directive)
  "Project uses Next.js 15"       → CLAUDE.md (convention)
  "On PR creation, run linter"    → hooks/   (automation)
  "Stripe webhook URL is /api/x"  → MEMORY.md (external pointer)
```
