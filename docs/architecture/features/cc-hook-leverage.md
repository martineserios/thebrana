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
- **SubagentStart injection uses brana CLI** — hook calls `brana backlog query --status in_progress` to find the active task, then injects metadata as additionalContext. Agents receive it transparently.
- **PreCompact/PostCompact spiked and cancelled** — spike showed all critical state (build_step, task metadata, git state) is already persisted to disk. Compaction only loses conversation context, which sitrep recovers.

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
| `system/skills/*/SKILL.md` | 4 skills with `model:` frontmatter (sitrep, log, export-pdf → haiku; retrospective → sonnet) |

## API Surface

### Hook Events Used

| Event | Hook | Registered In |
|-------|------|---------------|
| PreToolUse (Write\|Edit) | pre-tool-use.sh | plugin hooks.json |
| PreToolUse (Bash) | worktree-gate.sh | plugin hooks.json |
| PostToolUse (Write\|Edit\|Bash) | post-tool-use.sh | bootstrap settings.json |
| PostToolUse (Write\|Edit) | post-sale.sh, post-tasks-validate.sh, task-sync.sh | bootstrap settings.json |
| PostToolUse (ExitPlanMode) | post-plan-challenge.sh | bootstrap settings.json |
| PostToolUse (Bash) | post-pr-review.sh, task-completed.sh | bootstrap settings.json |
| PostToolUseFailure | post-tool-use-failure.sh | bootstrap settings.json |
| **TaskCompleted** | step-completed.sh | plugin hooks.json + bootstrap |
| **SubagentStart** | subagent-context.sh | plugin hooks.json |
| SessionStart | session-start.sh | plugin hooks.json |
| SessionEnd | session-end.sh | plugin hooks.json |

### Skill Model Routing

| Model | Skills |
|-------|--------|
| haiku | sitrep, log, export-pdf |
| sonnet | retrospective |
| inherit | all others (28 skills) |

## Testing

No automated tests — shell hooks are verified by observing behavior during normal usage. The task-completed.sh hook was tested live when completing t-199.

```bash
# Manual verification: complete a task and check for rollup + GitHub close
brana backlog set t-XXX status completed
# Check /tmp/brana-task-sync.log for GitHub close
# Check /tmp/brana-decisions.log for decision log entry
```

## Known Limitations

- **PostToolUse plugin dispatch bug (CC #24529)** — PostToolUse hooks must be installed via bootstrap.sh → settings.json, not plugin hooks.json. TaskCompleted and SubagentStart are NOT PostToolUse, so they work in plugin hooks.json.
- **task-completed.sh uses grep matching** — detects `brana backlog set <id> status completed` via regex on Bash command. Fragile if CLI syntax changes. Native CC TaskCompleted fires for CC Tasks only, not brana backlog tasks.
- **SubagentStart injection only works when a task is in_progress** — if no active task, hook returns silently. Agents spawned outside of task context don't receive injection.
- **Model override is static** — set in frontmatter, not dynamic. Can't downgrade mid-skill based on task complexity. contextModifier (t-509, deferred) would enable dynamic routing.
- **CC changelog check depends on npm** — if npm is unavailable or the package name changes, the script fails silently.
