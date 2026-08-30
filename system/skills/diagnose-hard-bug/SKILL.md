---
name: diagnose-hard-bug
description: "Hard-bug diagnosis: tight loop, ranked hypotheses."
keywords: [debug, diagnose, bug, regression, hypothesis, hard-bug]
task_strategies: [bug-fix]
group: core
allowed-tools: [Read, Bash, Skill]
disable-model-invocation: true
status: experimental
vendored_from: mattpocock/skills@v1.2.3
---

# Diagnose Hard Bug (adapter)

ADR-084 vendor+wrap pilot (t-2834). Thin adapter, not a copy — the actual discipline lives in the vendored organ, read fresh every invocation (no state to lose across compaction — steps 1-2 below are the whole procedure):

1. **Read the vendored skill**: `Skill(skill: "diagnosing-bugs")` — `.claude/skills/diagnosing-bugs/SKILL.md`, verbatim upstream, pinned `v1.2.3`, tracked in `skills-lock.json`. Follow its six phases as written.
2. **While following it, remap:**
   - "Issue tracker" / "issue" / "ticket" → this project's `tasks.json` / `t-NNN` task. Never prompt for `/setup-matt-pocock-skills` — not installed, not needed.
   - `CONTEXT.md` (upstream expects a repo-root glossary file that doesn't exist here) → use this project's own memory instead: the 2-3 most relevant `docs/architecture/*.md` files + the task's own context, inline, rather than looking for a file.
   - Cross-skill references → [redirect-check.md](redirect-check.md), the committed list; re-verify it against the vendored `SKILL.md` on every upstream bump (ADR-084 §1 pump).
3. **Early exit** (inherited from the vendored skill's own Phase 1): if no tight, red-capable feedback loop can be built, stop and say so explicitly rather than hypothesising — this is a valid, complete exit, not a failure to route around.
4. **Record on completion or early exit**: append one line to `~/.claude/run-state/pocock-diagnosing-bugs.jsonl` via a single shell redirect — `printf '%s\n' '{"task_id":...}' >> ~/.claude/run-state/pocock-diagnosing-bugs.jsonl` — never read-then-rewrite-the-file; this is a cross-session shared log and a single `>>` of one line (well under `PIPE_BUF`) is the only append form safe against two concurrent `/brana:fix` sessions racing on it. Fields: `{"task_id", "phase_reached", "tight_loop_command", "hypotheses_ranked", "outcome", "date"}` — the invocation evidence ADR-084 §7's kill/expand evaluation reads.
