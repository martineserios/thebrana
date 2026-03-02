# 00 - User Practices: What Works When Using the Brana System

Field notes from building and using the brana system. This document is the user's feedback loop — patterns discovered through real usage that feed back into system evolution. It grows over time as the user tells the system what to record here.

---

## Why This Document Exists

The spec repo designs the system. The implementation repo builds it. But neither captures what the user actually learns by living with it. That knowledge — "this workflow feels wrong," "this shortcut saves time," "this failure mode keeps happening" — is the signal that drives system evolution.

Without a place to land, these observations stay in the user's head or get scattered across session memories. With this document, the cycle closes:

```
build system → use system → discover practice → record here → improve system → repeat
```

This is a living document. It starts sparse and grows dense. Every entry is something the user experienced firsthand.

---

## How to Use This Document

**As a user:** When you notice a pattern — good or bad — tell the system to record it here. Say something like "add to user practices: always run validate before deploy, I keep forgetting." The entry gets added to the right category with a date.

**As the system:** When updating this doc, add entries under the appropriate category with a date tag. Don't editorialize — capture the user's observation as-is. If a practice contradicts an earlier one, keep both and note the contradiction. The user resolves it.

**As an evolution signal:** When multiple entries cluster around the same pain point, that's a signal for system improvement. A practice the user has to remember manually should eventually become automated (a hook, a validation check, a default).

---

## Session Workflow

Practices around starting, running, and ending Claude Code sessions.

- **2026-02-10:** Use `/session-handoff` when switching sessions. It reads the handoff note from the previous session, checks for cross-session changes (git log), reconciles conflicts, and reports where to continue. Without it, the new session starts blind and may redo or contradict work from the previous one.

---

## Memory and Learning

Practices around what gets stored, how to query it, and when storage causes more harm than good.

*(No entries yet.)*

---

## Skills and Commands

Practices around invoking skills, when to use which, and gotchas.

- **2026-02-10:** Refresh dimension docs periodically. Dimension docs (research and analysis) are the foundation everything else builds on. When external tools update (new Claude Code features, claude-flow releases, ecosystem changes), the relevant dimension docs go stale silently. Set a habit: before starting a new implementation phase, re-read the dimension docs that inform it and check if claims still hold. This isn't automated yet — it's a manual practice until staleness detection (doc 25) is built.
- **2026-02-10:** Use `/refresh-knowledge` to systematically research updates across dimension docs. It launches parallel scouts that web-search for changes to the tools, creators, and concepts each doc covers. Run with `all` (default), `high`/`medium`/`low` for priority tiers, or a specific doc number (e.g., `/refresh-knowledge 11`). The skill reports findings — it doesn't modify docs. You decide what to act on, then propagate upward.

---

## Tool Preferences

Opinionated tool choices that apply across all managed projects. Enforced via `~/.claude/rules/universal-quality.md`.

- **2026-02-12:** Python projects always use **uv** (package/env manager) and **ruff** (linter/formatter). No pip, poetry, conda, venv, black, flake8, isort. One tool per job: `uv` for environments and dependencies, `ruff` for code quality, `pytest` for testing. Run via `uv run pytest`, `ruff check --fix`, `ruff format`. Configured in `pyproject.toml` — no separate config files.

---

## Hooks and Automation

Practices around hooks firing, debugging hook failures, and when automation helps vs hurts.

*(No entries yet.)*

---

## Deploy and Validate

Practices around the deploy/validate cycle, common mistakes, recovery patterns.

*(No entries yet.)*

---

## Cross-Project Work

Practices around working across multiple projects, context switching, and cross-pollination.

- **2026-02-12:** Each directory is a workstation. `cd enter` = architect mode (design specs). `cd thebrana` = operator mode (build and deploy). `cd brana-knowledge` = vault (export and backup). The global brain (`~/.claude/`) follows you everywhere — you don't configure anything when switching. The local CLAUDE.md tells the brain what role to play.
- **2026-02-12:** Don't cross-edit. Don't edit specs from thebrana (`cd thebrana` then modify `../enter/` files), and don't edit system code from enter (`cd enter` then modify `../thebrana/` files). Each workstation has the context for its own files. Cross-editing loses that context and leads to mistakes that the local CLAUDE.md would have prevented.

---

## System Evolution

Practices around changing the brana system itself — when to modify, how to test changes, what goes wrong.

- **2026-02-10:** Remember to trigger upward propagation when modifying docs. The system (Claude) sometimes forgets. The rule: changes to a dimension doc → recheck reflection docs (08, 14). Changes to a reflection doc → recheck roadmap docs (17, 18, 19, 24). If the system doesn't do this automatically, remind it: "you updated a dimension doc, check propagation." This is a manual guardrail until it can be automated as a validation check or hook.
- **2026-02-12:** Two directions of propagation, two commands. **Forward** (`/maintain-specs`): spec change cascades to dependent specs (dimension → reflection → roadmap). **Backward** (`/back-propagate`): implementation change propagates back to specs (rule/hook/skill → dimension → reflection → roadmap). Without `/back-propagate`, implementation decisions silently diverge from specs. Example: adding ruff+uv as a rule without updating [docs 22](dimensions/22-testing.md) and 27 means `/project-align` wouldn't know about the standard.

---

## Anti-Patterns Discovered

Things the user tried that didn't work. Equally valuable as good practices — prevents repeating mistakes.

*(No entries yet.)*

---

## Graduation Log

Practices that were automated or built into the system. When a manual practice becomes a hook, validation check, or default, move it here with a link to what replaced it.

| Practice | Graduated To | Date |
|---|---|---|
| *(none yet)* | | |

---

## Cross-References

- [15-self-development-workflow.md](./15-self-development-workflow.md) — genome vs connectome; user practices are connectome input
- [16-knowledge-health.md](dimensions/16-knowledge-health.md) — quarantine applies here too; unverified practices stay provisional
- [24-roadmap-corrections.md](./24-roadmap-corrections.md) — errata pattern; user practices catch the same class of errors at usage level instead of spec level
- [25-self-documentation.md](./25-self-documentation.md) — documentation locality; this doc is the ONE place for user-discovered practices
