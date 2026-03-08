# ADR-004: Session Handoff as Self-Learning Loop

**Date:** 2026-02-23
**Status:** accepted

## Context

The brana system has three disconnected session lifecycle concerns:

1. **Session pickup** — `/session-handoff` reads previous session's note and reconciles cross-session changes
2. **Knowledge extraction** — `/debrief` + `/retrospective` extract learnings, but only if the user remembers to call them
3. **Doc sync** — `/back-propagate` updates specs when implementation changes, but only if manually invoked

The gap: no automation connects "I'm done building" to "extract what I learned" to "check if docs need updating." The user must remember to call 3 separate commands in the right order. Most sessions end without any of them.

Additionally, the `session-end.sh` hook stores raw event counts but doesn't check for doc drift or write handoff notes. The `session-start.sh` hook recalls patterns but doesn't surface flags from the previous session.

## Decision

### 1. Unified `/session-handoff` with auto-detect mode

The skill auto-detects pickup vs close mode based on git state and conversation context:
- **Close mode** (recent commits exist): debrief → doc drift heuristic → handoff note → store + backup
- **Pickup mode** (no recent commits): read previous note → reconcile → check flags → report

Close mode reuses the existing `debrief-analyst` agent (Opus) for knowledge extraction — no new debrief implementation. Doc drift is a heuristic grep for system file changes, not a full `/back-propagate` analysis. Suggestions are surfaced; execution is left to the user.

### 2. Enhanced session-end hook (automatic fallback)

If `/session-handoff` wasn't called, the session-end hook auto-generates a minimal handoff entry from git log. Also writes a `.needs-backprop` flag file if system files were modified.

### 3. Enhanced session-start hook (flag surfacing)

Checks for `.needs-backprop` flag from previous session and injects a suggestion into additionalContext.

### 4. Delegation routing trigger

Add "Session ending / user says done/bye" → suggest `/session-handoff` to the routing table.

## Alternatives considered

### Separate `/session-close` skill
Pro: clean separation, no bi-modal command. Con: adds yet another command to remember (anti-pattern per work-preferences rule: "embed as steps in existing commands"). The auto-detect approach means one command serves both purposes seamlessly.

### Inline lightweight debrief
Pro: faster, less token cost. Con: creates a third debrief implementation alongside `/debrief` skill and `debrief-analyst` agent. Divergence risk is high. Reusing the existing agent is cheaper to maintain.

### Separate changelog file
Pro: formal project history. Con: duplicates handoff note + git log + claude-flow memory. Enriching the existing handoff note with a Learnings section achieves the same goal without a new artifact.

## Consequences

- Every session that produces commits will automatically extract learnings (via close mode or hook fallback)
- Doc drift is flagged within the session and surfaced at next session start
- No new debrief implementation — reuses debrief-analyst agent
- Backlog #72 (session-close workflow) resolved, #68 (handoff as changelog) absorbed into enriched handoff format, #41 (changelog-based doc updates) stays separate for `/maintain-specs`
- Context budget: skill description grows by ~50 bytes (within budget)
