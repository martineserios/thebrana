---
name: diagnose-hard-bug
description: "Hard-bug diagnosis: tight loop, ranked hypotheses."
keywords: [debug, diagnose, bug, regression, hypothesis, hard-bug]
task_strategies: [bug-fix]
group: core
allowed-tools: [Read, Bash, Skill]
status: experimental
vendored_from: mattpocock/skills@v1.2.3
---

# Diagnose Hard Bug (adapter)

ADR-084 vendor+wrap pilot (t-2834). Thin adapter, not a copy — the actual discipline lives in the vendored organ, read fresh every invocation (no state to lose across compaction — steps 1-2 below are the whole procedure):

Model-invocable on purpose: callers reach this adapter through the Skill tool, which `disable-model-invocation` blocks (ADR-076 verified finding #3) — the flag made the band unreachable until t-3489.

0. **Resolve, then record** (ADR-097 P0, t-3489): run `"$HOME/.claude/scripts/organ-resolve.sh" diagnosing-bugs` (the deployed copy; in this repo's own checkout `system/scripts/` holds the source). **Any non-zero exit** — 1 (organ not vendored here) or 127 (script absent, as in a client repo) — means: say so and return to the caller's inline procedure; never improvise the organ from memory. Then `"$HOME/.claude/scripts/organ-record.sh" diagnosing-bugs <t-NNN> <caller>` (entry record for ADR-084 §7's invocation proxy; advisory, its exit status never aborts this skill).
1. **Read the vendored skill**: `Skill(skill: "diagnosing-bugs")` — `.claude/skills/diagnosing-bugs/SKILL.md`, verbatim upstream, pinned `v1.2.3`, tracked in `skills-lock.json`. Follow its six phases as written.
2. **While following it, remap:**
   - "Issue tracker" / "issue" / "ticket" → this project's `tasks.json` / `t-NNN` task. Never prompt for `/setup-matt-pocock-skills` — not installed, not needed.
   - `CONTEXT.md` (upstream expects a repo-root glossary file that doesn't exist here) → use this project's own memory instead: the 2-3 most relevant `docs/architecture/*.md` files + the task's own context, inline, rather than looking for a file.
   - Cross-skill references → [redirect-check.md](redirect-check.md), the committed list; re-verify it against the vendored `SKILL.md` on every upstream bump (ADR-084 §1 pump).
3. **Early exit** (inherited from the vendored skill's own Phase 1): if no tight, red-capable feedback loop can be built, stop and say so explicitly rather than hypothesising — this is a valid, complete exit, not a failure to route around.
4. **Record on completion or early exit**: `"$HOME/.claude/scripts/organ-record.sh" diagnosing-bugs <t-NNN> <caller> complete` (or `early-exit`) — same shape as the entry record, so the ADR-084 §7 reader counts `event=entry` lines and never sees two shapes in one log. Advisory: its exit status never aborts this skill.