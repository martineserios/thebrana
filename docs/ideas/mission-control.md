# Brana Mission Control

> Brainstormed 2026-03-16. Challenged 2026-03-16 (simplicity). Status: idea.
> Related: t-525, investigation doc.

## Problem

Managing 5+ projects across terminal screens requires constant manual switching. No unified way to spawn agents on tasks, monitor progress, or ensure all work flows through the backlog. Current workflow: one terminal per project, manual `git worktree` + `claude` invocations, no visibility across agents.

## Proposed solution

Enrich the brana Rust CLI with orchestration commands. Genuinely incremental: print-first, spawn-later, monitor-only-if-needed.

## Architecture (post-challenge)

```
brana CLI (Rust, existing binary — extend)
│
├── Phase 0.5: brana run <task-id>
│   ├── Reads task from backlog
│   ├── Creates git worktree + branch
│   ├── Sets task: status=in_progress, started=today, branch
│   └── PRINTS the claude command to run (user copies it)
│
├── Phase 1: brana run <task-id> --spawn
│   ├── Everything from 0.5 PLUS:
│   ├── Spawns claude as background process (std::process::Command)
│   ├── Tracks PID in agents.json
│   └── Liveness: check /proc/{pid} (Linux)
│
├── Phase 1.5: brana run <task-id> --spawn --tmux
│   ├── Everything from Phase 1 PLUS:
│   ├── Opens tmux window (optional, only if in tmux)
│   └── tmux_interface crate for pane management
│
├── Phase 2: brana agents [--wide]
│   ├── Live-checks PIDs first (authoritative)
│   ├── Updates agents.json as side effect (cache, not source of truth)
│   └── Formatted table (comfy-table crate)
│
├── Phase 2.5: brana agents kill <agent-id>
│   ├── SIGINT → wait 5s → SIGKILL fallback
│   ├── Post-kill cleanup: reset task, clean worktree if no changes
│   └── Update agents.json
│
├── Phase 3: brana queue [--max N] [--auto]
│   ├── Calls brana backlog next (top N by priority)
│   ├── Shows candidates with complexity score + model routing
│   └── --auto: spawns agents on all N
│
└── Future (evaluate later):
    ├── brana cost — token/cost tracking (needs stable CC cost API)
    ├── brana monitor — Ratatui TUI (only if CLI snapshots insufficient)
    └── brana serve — Axum web (only if TUI insufficient)
```

## Key Design Decisions

### Print before you automate (challenger finding)
Phase 0.5 just creates the worktree and prints the command. User copies it into whatever terminal they want. This gives 80% of the value with 20% of the complexity. `--spawn` earns its way in by demonstrated need.

### PIDs first, tmux optional (challenger finding)
Orchestration decoupled from display. `brana run --spawn` tracks processes via PID. `--tmux` is an optional visual layer on top. Works everywhere: bare terminal, tmux, SSH, screen.

### Live state is truth (challenger finding)
`brana agents` always checks `/proc/{pid}` for liveness. agents.json is a write-ahead cache, not source of truth. No reconciliation needed — live checks happen on every read.

### CLI via Bash is the CC integration layer
No MCP wrapper. CLAUDE.md directives + skills already route CC to brana CLI. New subcommands get called the same way existing ones do.

### Shell-first exploration welcome
If any phase feels uncertain, prototype as shell function first. Promote to Rust only when validated. Matches the "CC absorbs orchestration quarterly" thesis.

## CC Deep Integration

CLAUDE.md rules + skills route CC to brana CLI via Bash tool. New commands integrate identically to existing ones — no new integration pattern needed.

Future: Agent Teams sync bridge (only when Agent Teams stabilizes and if brana's tasks.json can't be the shared task list natively).

## State: ~/.claude/agents.json

```json
[
  {
    "id": "agent-001",
    "task_id": "t-525",
    "pid": 12345,
    "tmux_target": null,
    "worktree": "../thebrana-research-t-525",
    "model": "opus",
    "started": "2026-03-16T13:00:00Z",
    "status": "active"
  }
]
```

Note: `tmux_target` only populated when `--tmux` is used. Cost fields deferred until stable CC cost API exists.

## Phases Summary

| Phase | Command | Effort | Value |
|-------|---------|--------|-------|
| 0.5 | `brana run` (print command) | S | Automated setup: worktree + branch + task status |
| 1 | `brana run --spawn` | M | Background process with PID tracking |
| 1.5 | `brana run --spawn --tmux` | S | Visual multiplexing (optional) |
| 2 | `brana agents` | S | See what's running (live PID checks) |
| 2.5 | `brana agents kill` | S | Graceful stop + cleanup |
| 3 | `brana queue` | M | Auto-suggest + batch-spawn |

### Future (evaluate separately)

| Item | Trigger to evaluate |
|------|-------------------|
| `brana cost` | CC exposes stable cost API |
| `brana monitor` (Ratatui) | CLI snapshots prove insufficient after 2+ weeks of use |
| `brana serve` (Axum web) | Need remote/persistent monitoring |
| Agent Teams sync | Agent Teams ships stable + proven benefit over subagents |

## Risks and mitigations

| Risk | Mitigation |
|------|-----------|
| CC ships native orchestration | Each command is thin, standalone. Deprecate gracefully |
| PID tracking misses process exit | Live-check /proc/{pid} on every `brana agents` call |
| SIGTERM ignored by CC | SIGINT first (C-c if tmux, kill -2 otherwise), 5s wait, SIGKILL fallback. Post-kill cleanup mandatory |
| Cost data unavailable | Defer brana cost until CC has stable API. Don't parse undocumented JSONL |
| Phase 1 scope creep | Print-first approach forces genuine incrementalism |

## Challenge Log

**2026-03-16 — Simplicity challenger (Opus)**
- CRITICAL: tmux coupling → decoupled to optional `--tmux` flag
- CRITICAL: Phase 1 scope → split into 0.5 (print) → 1 (spawn) → 1.5 (tmux)
- WARNING: agents.json drift → inverted to live-check-first
- WARNING: CC Agent Teams obsolescence → accepted as risk, shell-first prototype welcome
- WARNING: JSONL cost parsing → deferred until stable API
- WARNING: Process kill fragility → post-kill cleanup made mandatory
- OBSERVATION: TUI/web won't ship → moved to "evaluate separately"
- OBSERVATION: Queue assumes clean deps → don't over-promise

Verdict: **PROCEED WITH CHANGES.** Core instinct validated, phasing improved.

## Next steps

1. Implement Phase 0.5: `brana run` (worktree + print command + set task in_progress)
2. Use it for 1 week across projects
3. Decide if `--spawn` is needed based on actual friction
