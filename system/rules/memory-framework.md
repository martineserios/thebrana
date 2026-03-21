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
