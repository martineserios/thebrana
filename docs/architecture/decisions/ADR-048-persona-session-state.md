# ADR-048: Persona modifier persisted in session state, not CLAUDE.local.md

**Status:** Accepted  
**Date:** 2026-06-03  
**Deciders:** Martin Rios  
**Context:** docs/ideas/prompt-patterns-brana-enrichment.md, t-1823 (agy_delegate fix backlog)

---

## Problem

`/brana:persona` needs to inject a session-level expert role context ("You are the CTO of X")
that shapes Claude's responses for the duration of the session. Where should this context live?

## Options Considered

### Option A: Write to CLAUDE.local.md

CLAUDE.local.md is gitignored, loaded last, and wins on conflict — appears ideal for
machine-local session overrides.

**Rejected because:**
- Session bleed: CLAUDE.local.md persists across sessions. If the user ends a session
  without explicitly running `/brana:persona reset`, the persona carries silently into
  the next session.
- No close-hook awareness: `/brana:close` reads session state to offer cleanup — it has
  no mechanism to detect arbitrary content in CLAUDE.local.md.
- First-time failure: the pattern has no precedent in brana; shipping it with a known
  silent failure mode is high risk.
- Debugging difficulty: a "stuck" persona in CLAUDE.local.md has no visible signal in
  the session state or backlog — it would appear as surprising Claude behavior with no
  obvious cause.

### Option B: Persist in brana session state JSON (chosen)

The brana session state (`mcp__brana__session_write` / `mcp__brana__session_read`)
already tracks the active session's context. Add a `persona` field.

**Accepted because:**
- Session lifecycle: session state is written on start and cleared/archived on close.
  `/brana:close` already reads session state — it can detect an active persona and offer
  to reset before ending the session.
- No silent bleed: when a session ends via close, the persona goes with it.
- Explicit override: if the persona should persist (rare), the user can explicitly
  write it to CLAUDE.local.md manually — this is a deliberate action, not a default.
- Consistent with existing state management: session state already tracks `branch`,
  `accomplished`, `focus` — persona is the same kind of session-scoped metadata.

## Decision

`/brana:persona` writes to and reads from the brana session state JSON via MCP:

```
# Set persona
mcp__brana__session_write(payload: {...existing_state, persona: "CTO of a fintech startup"})

# Clear persona
mcp__brana__session_write(payload: {...existing_state, persona: null})

# Read active persona (for injection into prompts)
mcp__brana__session_read(field: "persona")
```

**Injection mechanism:** At skill invocation time, `/brana:persona` reads the persona
field and prepends it to the conversation as a system-context statement:
`"For this session, respond as: {persona}. Maintain this perspective throughout."`

**Close hook integration:** `/brana:close` checks `session.persona` — if non-null,
offers: "Active persona: '{persona}'. Reset before closing? [Yes / Keep for next session]"
If yes: clears the field. If no: leaves it set (user's explicit choice).

## Consequences

- `/brana:close` needs a persona-awareness check added to its procedure.
- The persona is not active across sessions by default — this is intentional.
- Users who want a persistent persona (e.g., always act as CTO) should add it to
  CLAUDE.local.md manually — this ADR does not block that use case, it just makes it explicit.
- Future session-scoped modifiers (mode, depth, etc.) should follow the same pattern.
