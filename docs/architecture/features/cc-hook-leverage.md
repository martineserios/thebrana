---
depends_on:
  - docs/architecture/features/test-lint-feedback-hook.md
informs:
  - docs/architecture/features/skill-utilization-tracking.md
---
# Feature: CC Hook Leverage — Expanded Event Coverage

**Date:** 2026-03-15
**Task:** t-507, t-513, t-515, t-199, t-512
**Status:** shipped
**Branch:** multiple (feat/t-507, feat/t-513, feat/t-515, feat/t-199)

## Goal

Expand brana's use of CC hook events from 5 to 8+, adding native TaskCompleted, SubagentStart, and per-skill model routing. Research (t-506) revealed CC has 21 hook events — brana was using 5. This phase addressed the highest-value gaps.

## Design Decisions

- **Two task managers, two hooks** — CC Tasks (step registry) and brana backlog are separate systems. `step-completed.sh` handles CC Task completions, `task-completed.sh` handles brana backlog completions. They don't overlap.
- **Challenger reduced scope from 11 to 4** — of 11 proposed tasks, challenger cut 4 (HTTP daemon, UserPromptSubmit, PermissionRequest, WorktreeCreate), deferred 2 (contextModifier, step auto-advance), and a spike cancelled 1 (PreCompact/PostCompact). Net: 3 shipped + 1 from prior work.
- **Model routing via frontmatter, not code** — per-skill `model:` field is a one-line frontmatter change, not a code feature. CC handles the contextModifier automatically.
- **SubagentStart injection uses brana CLI** — hook calls `brana backlog query --status in_progress` to find the active task, then injects up to 4 context signals: active task metadata, current git branch, active plan title, and last 3 decisions. Agents receive it transparently.
- **PreCompact/PostCompact spiked and cancelled** — spike showed all critical state (build_step, task metadata, git state) is already persisted to disk. Compaction only loses conversation context, which sitrep recovers.
- **Guard-explore added (2026-03-25)** — PreToolUse hook on Read|Grep|Glob. Logs reads-without-search on implementation files. Runs only in `strict` hook profile. See [hooks architecture](../../architecture/hooks.md#guard-explore-read-pattern-observability).
- **Hook profiles added (2026-03-25)** — `BRANA_HOOK_PROFILE` env var tiers hook execution: minimal (none), standard (default, SDD gate + worktree gate), strict (adds guard-explore). Each tier maps to a CC effort level (strict→low, standard→high, minimal→max) via `get_profile_effort()`, exported as `BRANA_EFFORT_LEVEL` at session start. See [hooks architecture](../../architecture/hooks.md#hook-profiles).

## Code Flow

1. **Entry:** CC fires hook event (TaskCompleted, SubagentStart, PostToolUse on Bash)
2. **Core:** Shell script receives JSON via stdin, extracts event data, calls brana CLI for task metadata
3. **Output:** JSON on stdout with `additionalContext` injected into Claude's next turn

### Key Files

| File | Role |
|------|------|
| `system/hooks/task-completed.sh` | PostToolUse Bash hook — detects `brana backlog set <id> status completed`, triggers rollup + GitHub close + decision log |
| `system/hooks/step-completed.sh` | TaskCompleted hook — logs CC Task step completion to session file, injects step name as context |
| `system/hooks/subagent-context.sh` | SubagentStart hook — injects active task metadata into every spawned subagent |
| `system/hooks/hooks.json` | Plugin hook registry — SubagentStart + TaskCompleted registered here |
| `bootstrap.sh` | Identity layer — PostToolUse hooks + TaskCompleted registered in settings.json |
| `system/scripts/cc-changelog-check.sh` | Scheduled script — checks npm for CC version changes, writes report |
| `system/hooks/session-start.sh` | Surfaces CC changelog report on session start |
| `system/skills/*/SKILL.md` | 34 skills with `model:` frontmatter (19 haiku, 14 sonnet) |

## API Surface

### Hook Events Used

| Event | Hook | Registered In |
|-------|------|---------------|
| PreToolUse (Write\|Edit) | pre-tool-use.sh, tdd-gate.sh, feedback-gate.sh, memory-write-gate.sh | plugin hooks.json |
| PreToolUse (Bash) | worktree-gate.sh, branch-name-warn.sh | plugin hooks.json |
| PostToolUse (Write\|Edit\|Bash) | post-tool-use.sh | plugin hooks.json ⚠ |
| PostToolUse (Write\|Edit) | post-sale.sh, post-tasks-validate.sh | plugin hooks.json ⚠ |
| PostToolUse (ExitPlanMode) | post-plan-challenge.sh | plugin hooks.json ⚠ |
| PostToolUse (Bash) | post-pr-review.sh, task-completed.sh | plugin hooks.json ⚠ |
| PostToolUseFailure | post-tool-use-failure.sh | plugin hooks.json ⚠ |
| **TaskCompleted** | step-completed.sh | plugin hooks.json |
| **SubagentStart** | subagent-context.sh | plugin hooks.json |
| SessionStart | session-start.sh | plugin hooks.json |
| SessionEnd | session-end.sh → session-end-metrics.sh + session-end-persist.sh + session-end-drift.sh | plugin hooks.json |

⚠ = Registered in plugin hooks.json but dispatch from plugin unconfirmed in CC v2.1.x (CC #24529). See Known Limitations.

### Skill Model Routing

| Model | Skills |
|-------|--------|
| haiku | acquire-skills, cargo-machete, client-retire, do, export-pdf, log, meta-templates, onboard, plugin, rust-skills, scheduler, sitrep, verify-docs |
| sonnet | align, backlog, brainstorm, build, claudemd, close, docs, fix, reconcile, research, retrospective, review, ship |
| inherit | challenge, gsheets, mcp-builder, memory |

## Testing

Hook scripts now have automated test coverage in `system/hooks/tests/`. The test suite covers 36 hooks as of 2026-06-04.

Run all hook tests:
```bash
for t in system/hooks/tests/test-*.sh; do bash "$t"; done
```

Run a specific hook test:
```bash
bash system/hooks/tests/test-task-completed.sh
bash system/hooks/tests/test-branch-name-warn.sh
```

Manual verification for task-completed.sh:
```bash
# Complete a task and check for rollup + GitHub close
brana backlog set t-XXX status completed
# Check /tmp/brana-task-sync.log for GitHub close
# Check /tmp/brana-decisions.log for decision log entry
```

## Known Limitations

- **PostToolUse plugin dispatch (CC #24529, unresolved as of 2026-05-31)** — PostToolUse/PostToolUseFailure hooks are registered in `plugin hooks.json` (migrated from bootstrap settings.json during E2026-05-31-2). However, `validate.sh` warns CC v2.1.x may not dispatch these events from plugin hooks. If post-tool-use hooks stop firing, re-add them to settings.json via bootstrap.sh until CC #24529 is confirmed resolved. TaskCompleted and SubagentStart are NOT PostToolUse and work reliably from plugin hooks.json.
- **`args:[]` hook schema removed (E2026-05-31-2)** — All hook entries must use `"command": "bash script.sh"` (string), not `"args": ["bash", "script.sh"]` (array). The array form causes a silent load failure; `validate.sh` Check 51 now catches this at validation time.
- **task-completed.sh uses grep matching** — detects `brana backlog set <id> status completed` via regex on Bash command. Fragile if CLI syntax changes. Native CC TaskCompleted fires for CC Tasks only, not brana backlog tasks.
- **SubagentStart injection only works when a task is in_progress** — if no active task, hook returns silently. Agents spawned outside of task context don't receive injection.
- **Model override is static** — set in frontmatter, not dynamic. Can't downgrade mid-skill based on task complexity. contextModifier (t-509, deferred) would enable dynamic routing.
- **CC changelog check depends on npm** — if npm is unavailable or the package name changes, the script fails silently.
