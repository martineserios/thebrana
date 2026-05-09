# Memory and Knowledge

Brana learns from every session and applies those learnings in future work. The memory system has two layers: **auto memory** (project-level files in `~/.claude/projects/*/memory/`) and **ruflo** (cross-client neural search when the MCP server is running).

## Quick start

```
/brana:memory "JWT refresh patterns"    -- recall patterns before starting work
/brana:memory pollinate                 -- pull patterns from other clients
/brana:memory review                    -- monthly knowledge health audit
```

## Recall — before you start work

Run recall at the start of any session where you're working on a familiar problem type. Patterns from past sessions surface here, tiered by confidence:

```
## Proven patterns (confidence >= 0.7)
- Hook cd + brana CLI requires subshell CWD wrapping — confidence: 0.85, recalls: 6

## Quarantined patterns (confidence 0.2–0.7)
- [treat with caution — unproven across sessions]
```

If ruflo is unavailable, brana falls back to scanning `~/.claude/projects/*/memory/MEMORY.md` files for keyword matches. The system works at reduced capability but still recalls.

## Saving memories

Memories are saved automatically when you correct brana's behavior or when a session closes via `/brana:close`. You can also save explicitly:

```
/brana:retrospective    -- save a specific learning or pattern right now
```

### What to save

| Type | When to save | Examples |
|------|-------------|---------|
| **feedback** | When you correct brana, or confirm a non-obvious approach worked | "Don't mock the DB in these tests", "single bundled PR was right" |
| **project** | When you learn why something is the way it is | "Auth rewrite driven by legal compliance, not tech debt" |
| **user** | When you learn something about your own role or preferences | Role, stack expertise, collaboration style |
| **reference** | When you learn where something lives in external systems | "Pipeline bugs tracked in Linear project INGEST" |

### What NOT to save

- Code patterns or architecture (read the code instead)
- Git history or who changed what (`git log` is authoritative)
- Ephemeral task details or in-progress work (use task context field)
- Anything already in CLAUDE.md

### Memory file structure

Each memory is a separate file with frontmatter:

```markdown
---
name: Hook CWD wrapping
description: Hooks that cd must wrap brana CLI in subshells
type: feedback
---

Always wrap brana CLI calls in subshells with `cd "$GIT_ROOT"` when the hook does a cd first.
**Why:** brana uses CWD to find the project; a hook's cd changes the process CWD globally.
**How to apply:** any hook script that changes directory before calling brana.
```

`MEMORY.md` is an index file — one line per memory, ~150 chars max. Never write memory content directly into MEMORY.md; always create a topic file and add a pointer.

## Pollinate — cross-client patterns

Pollinate pulls patterns from other clients that are relevant to your current work:

```
/brana:memory pollinate "WhatsApp template submission"
```

Only patterns marked `transferable: true` or with confidence > 0.7 are shown. Cross-pollinated patterns need validation in the current project context before trusting — what worked in client A may need adaptation for client B.

## Review — monthly knowledge audit

Run monthly to keep the knowledge base healthy:

```
/brana:memory review
```

This surfaces:
- **Promotion candidates** — quarantined patterns with 3+ recalls (ready to promote to proven)
- **Staleness candidates** — patterns stored 60+ days ago, never recalled
- **Confidence distribution** — proven vs quarantined vs suspect ratio

If the distribution is healthy (proven > 50%, quarantine < 30%), review reports "No action needed" with the numbers. No busy work.

## Audit — contradiction detection

Detect factual contradictions between docs:

```
/brana:memory review --audit              -- audit all 5 reflection docs + CLAUDE.md files
/brana:memory review --audit docs/14.md  -- audit a specific doc and everything it links to
```

This complements `/brana:reconcile` (which checks spec vs implementation) — audit works at the knowledge layer (doc vs doc).

## Key rules

- **Recall before starting on familiar problems.** Ten seconds of recall prevents rediscovering what already failed.
- **Don't save what you can derive.** File paths, conventions, and architecture are in the code. Save the non-obvious: constraints, surprises, validated judgment calls, corrections.
- **Confidence matters.** `confidence:quarantine` means unproven — treat as a hypothesis to validate, not a rule to follow blindly.
- **Memory can go stale.** Before acting on a recalled memory that names a specific file or function, verify it still exists. The memory was true when written; the code may have changed.
- **Save corrections AND confirmations.** If you only save corrections, you drift away from approaches the user already validated. If brana makes an unusual choice and the user accepts it without pushback, that's a confirmation worth saving.
