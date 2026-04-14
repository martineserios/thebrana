---
paths: ["system/hooks/**", "system/rules/**"]
---

# Rules Over Hooks for Behavioral Gates

Prefer a rule file over a hook for "always do X before Y" behavioral constraints.

**Why:** Hooks add per-event overhead and pollute context on every tool call. Rules load once and apply without side effects. Hooks are for automated actions that must fire without LLM involvement — not for directing behavior.
**How to apply:** When tempted to write a PreToolUse/PostToolUse hook to enforce a process step, ask: "could a rule communicate this just as effectively?" If yes, write the rule.
