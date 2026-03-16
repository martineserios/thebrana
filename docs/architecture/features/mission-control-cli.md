# Feature: Mission Control CLI

**Date:** 2026-03-16
**Status:** building
**Task:** t-525

## Problem

Managing 5+ projects across terminal screens requires constant manual switching. No unified way to spawn agents on tasks, monitor their progress, or ensure all work flows through the backlog.

## Decision Record (frozen 2026-03-16)

> Do not modify after acceptance.

**Context:** User manages multiple projects via separate terminal screens. Work should flow through brana's task framework but launching agents on tasks is manual (create worktree, run claude, update task status — 3 separate steps).

**Decision:** Enrich brana Rust CLI with orchestration commands (`run`, `agents`, `agents kill`). CLI-first, no daemon, no MCP wrapper. tmux for spawning (user always works in tmux). PID tracking with live liveness checks (agents.json is cache, not truth).

**Consequences:** Each command is independently useful and thin — if CC ships native orchestration, individual commands can be deprecated without losing the rest. Requires tmux for `--spawn` mode.

## Constraints

- No external framework adoption (Composio, delegate)
- CLI via Bash is the CC integration layer (no MCP)
- tmux required for `--spawn` (errors gracefully if not in tmux)
- agents.json is cache — live PID checks are authoritative
- Read-only agents pattern preserved (main context owns writes)
- Challenger-approved: print-first, spawn-later, tmux-optional

## Scope (v1)

### Phase 0.5 — `brana run <task-id>` (shipped)
- Creates git worktree + branch from task metadata
- Sets task: status=in_progress, started=today, branch
- Prints the claude command to run
- Pure logic in tasks.rs with 13 unit tests

### Phase 1 — `brana run <task-id> --spawn`
- Spawns claude in a new tmux window
- Writes agent metadata to `~/.claude/agents.json`
- Requires being inside a tmux session

### Phase 2 — `brana agents`
- Lists active agents from agents.json
- Live-checks PIDs via `/proc/{pid}` (Linux)
- Updates agents.json as side effect (removes dead agents)
- Formatted table output

### Phase 2.5 — `brana agents kill <agent-id>`
- Sends SIGINT to tmux pane (C-c)
- Waits 5s, SIGKILL fallback
- Post-kill cleanup: reset task status, optionally remove worktree

## Research

- Investigation: `docs/research/multi-agent-orchestration-investigation.md`
- Idea: `docs/ideas/mission-control.md`
- 13 sources researched (5 orchestrators, 4 workflow patterns, 3 CC native, 1 security)
- Challenger review: 2 critical findings accepted (decouple tmux, split phases)
- Key patterns: delegate's 6-layer security, Composio's event reactions, Tomcal's minimalism

## Design

### Key Files

| File | Purpose |
|------|---------|
| `system/cli/rust/src/tasks.rs` | Pure logic: branch_for_task, worktree_path_for_task, validate_task_runnable, agents.json I/O |
| `system/cli/rust/src/cli.rs` | CLI wiring: cmd_run, cmd_agents, cmd_agents_kill |
| `system/cli/rust/Cargo.toml` | Dependencies (may need sysinfo for PID checks) |
| `~/.claude/agents.json` | Agent state cache (PID, task, tmux target, timestamps) |

### agents.json Schema

```json
[
  {
    "id": "agent-001",
    "task_id": "t-063",
    "pid": 12345,
    "tmux_target": "brana:t-063",
    "worktree": "../thebrana-docs/t-063",
    "branch": "docs/t-063-first-principles-building-methodology-do",
    "started": "2026-03-16T13:00:00Z",
    "status": "active"
  }
]
```

### tmux Spawning Pattern

```
tmux new-window -t brana -n "t-{id}" "cd {worktree} && claude"
```

If not in tmux: error with message "tmux required for --spawn. Run without --spawn to get the command."

### Agent Liveness

Check `/proc/{pid}/status` exists. If not, agent is dead — remove from agents.json, optionally reset task.

## Challenger findings

- CRITICAL: tmux coupling → decoupled to optional `--spawn` flag (Phase 0.5 works without tmux)
- CRITICAL: Phase 1 scope → split into 0.5 (print) → 1 (spawn) → 1.5 (tmux visual)
- WARNING: agents.json drift → live PID checks are authoritative, agents.json is cache
- WARNING: CC Agent Teams may obsolete → commands are thin, deprecable
- WARNING: Process kill fragility → post-kill cleanup mandatory
