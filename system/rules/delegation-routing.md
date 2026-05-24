---
always-load: true
produced_by: docs/architecture/decisions/ADR-040-compute-hierarchy-claude-ruflo-gemini.md
---
# Delegation Routing

Two layers: **compute routing** (who runs the work) and **skill routing** (which skill to invoke).

---

## Layer 1 — Compute Routing (Claude / Ruflo / Gemini)

Every task asks: **who runs this?** Walk the tree top-to-bottom; first match wins.

```
1. Is this brana-system work?
   (git, hooks, tasks.json, system/ files, architecture decisions, ruflo stores)
     YES → Claude only. Never delegate. Full stop.

2. Is it atomic, system-isolated, and context-enrichable?
   (can run without in-session Claude state, produces a file or structured output)
     NO  → Claude only. (Needs session state or is multi-step.)

3. Is it convention-sensitive?
   Known types: boilerplate generation, test scaffolding, ADR drafts,
   naming/structure decisions, any output applied to the repo that must
   match codebase conventions to be correct.
   DEFAULT: when in doubt → treat as convention-sensitive.
   A false positive (task aborts when ruflo is down) is acceptable.
   A false negative (unenriched Gemini writes convention-violating output) is not.

     YES — Is ruflo available?
       NO  → ABORT. Error: "ruflo required for convention-sensitive task —
              use Claude directly." Do NOT fall back to unenriched Gemini.
       YES → Gemini (agy_delegate) with ENRICH step mandatory.
              ruflo memory_search(smart:true) → /tmp/context.md → agy prompt.
              Output → /tmp/result.md. Claude reads and applies via Write/Edit.

4. Is it a sub-agent needing cost tracking or ownership?
   (work that must be queryable per-project, claimed, or coordinated across sessions)
     YES → ruflo agent_spawn. Claims ownership. Queryable ledger.

5. Is it parallel, bulk, or token-heavy for Claude?
   (summarization, competitive research, formatting, brana-agnostic batch work)
     YES → Gemini (agy_delegate). ENRICH step optional.
            ruflo down → proceed with warning (not abort).
            Output → /tmp/result.md. Claude applies.

6. Everything else → Claude inline.
```

### Hard constraints (ADR-040)

- Gemini never writes to ruflo directly
- Gemini never writes to repo paths directly
- Ruflo never calls agy directly — Claude is the only dispatcher
- Gemini output → `/tmp/` only, always
- Hive-mind quorum workers → Claude only

---

## Layer 2 — Skill Routing (which skill to invoke)

Invoke skills directly — don't suggest them. If user declines, don't repeat.
Never invoke a skill AND delegate to an agent for the same trigger.

| Trigger | Action |
|---------|--------|
| Work starting (feat/fix/refactor) | check `tasks.json`, then **run skill routing** (see `skill-routing.md`) |
| Planning new work | `/brana:backlog add` |
| Session ending (done/bye/closing) | `/brana:close` |
| Big decision forming | `/brana:challenge` |
| New/unfamiliar codebase | `/brana:onboard` |
| Research on a new topic | `/brana:research [topic]` |
| Business health check | `/brana:review check` |
| Weekly/monthly review | `/brana:review` / `/brana:review monthly` |
| Spec changes need impl sync | `/brana:reconcile` |
| Uncommitted spec changes | `/brana:repo-cleanup` |
| Gemini delegation needed | `/brana:gemini` (Phase 3 — not yet shipped) |

```
Example — user says "let's add webhook support"

  1. Check tasks.json → no existing task → propose one
  2. Trigger: "work starting" → run skill routing (see skill-routing.md):
     Ask which skills to load → user confirms → invoke chosen skill(s)
  3. During PLAN step: challenger agent auto-fires (plan forming)
  4. User says "I'm done for today" → invoke /brana:close

  WRONG: silently invoke /brana:build without asking first
  WRONG: suggest "/brana:build" instead of invoking after confirmation
  WRONG: fire challenger AND suggest /brana:challenge
  WRONG: delegate convention-sensitive task to Gemini when ruflo is unavailable
```
