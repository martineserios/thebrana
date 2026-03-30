# Memory Framework

## Where things go

| Classification | Destination | Test |
|---------------|-------------|------|
| Directive ("always/never/must") | `rules/*.md` | Prescribes behavior |
| Convention (stack, architecture) | `CLAUDE.md` | Project identity |
| Automation (event-triggered) | `hooks/` | Should fire on tool use |
| Recipe (multi-step workflow) | `skills/` | Reusable command |
| Log entry (something happened) | `/brana:log` | Event record |
| Derivable (command/file output) | Nowhere | Run the command instead |
| Historical (no future value) | Nowhere | Delete |
| Cross-project | `~/.claude/rules/` | Not repo-specific |
| **True memory** | **MEMORY.md** | External API details, pointers not in code |

**MEMORY.md is the last resort.** Reference, don't cache — store pointers, not content. Cached facts drift silently.

Periodic maintenance happens in `/brana:close` Step 10: classify each MEMORY.md entry through this gate, move or delete accordingly.

```
Example — where does this go?

  "Always use uv, never python directly" → rules/  (directive)
  "Project uses Next.js 15 + Prisma"    → CLAUDE.md (convention)
  "On PR creation, run linter"          → hooks/   (automation)
  "How to deploy to Railway"            → skills/  (recipe)
  "Met client on 2026-03-15"            → /brana:log (event)
  "git log shows 4 commits today"       → Nowhere  (derivable)
  "Stripe API key is sk_live_..."       → Nowhere  (secret — env var)
  "Stripe webhook URL is /api/hook"     → MEMORY.md (external pointer)
```
