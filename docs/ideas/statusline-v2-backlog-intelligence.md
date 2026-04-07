# Statusline v2 — Backlog-Aware Intelligence

> Brainstormed 2026-04-07. Challenged 2026-04-07. **Implemented 2026-04-07** (all 4 milestones shipped).

## Problem

Current statusline shows project/branch/CTX% but doesn't surface *where you are in the build loop*. Orientation requires running `/brana:sitrep`. The statusline should provide enough context to resume work at a glance.

Note: the statusline already shows active task (truncated subject), phase progress, and bug count. The gap is build step, session score, and performance.

## Challenge findings (2026-04-07)

Opus pre-mortem found 3 critical issues with the original plan:

1. **Phase 1 duplicated existing functionality** — active task segment already exists (lines 84-87). Only build_step and session score are genuinely new.
2. **100ms baseline, 73ms jq on 1MB tasks.json** — adding cache reads on top makes it worse. Must replace jq, not add to it.
3. **Cache population via PostToolUse hooks is fragile** — depends on CC bug workaround (#24529). Self-populating cache is more robust.

Additional warnings: terminal width overflow (~130+ chars), no job detection signal source for Phase 3, ruflo latency risk for Phase 4, `find | wc` latency bomb on claude-flow tasks dir.

Verdict: PROCEED WITH CHANGES. Phases 1-2 collapsed into a single revised Phase 1.

## Proposed solution (revised)

### Phase 1 — Performance + new signals (hours)

Replace the expensive parts and add genuinely new signals:

1. **Replace jq with brana-query** — Rust binary already exists (2ms vs 73ms). Used by session-start.sh. Switch all tasks.json parsing to it.
2. **Add build_step bracket** — `[SPECIFY]` or `[BUILD]` — if active task has build_step field, show it. The one genuinely new orientation signal.
3. **Add session score** — `S: 17✓ 0✗` — tasks completed vs corrections. Read from session state counter file.
4. **Self-populating cache** — statusline writes its computed task values to `~/.claude/statusline-cache.json` with mtime. Next call reads cache if fresh (<30s), skips all computation. Under 5ms for cached reads. No dependency on PostToolUse hooks.
5. **Width detection** — `tput cols` + progressive segment dropping. If total exceeds width, drop in priority order: scheduler health → phase progress → session score → lines +/-.
6. **Replace `find | wc` with `ls | wc`** for claude-flow task count.

Target: under 50ms total (down from 100ms+).

### Phase 2 — Slow-cache signals (days)

Add a scheduled job (5min interval) that writes slow-changing signals to the cache:
- Ruflo health (entry count, last reindex date, stale count)
- Portfolio pulse (pending tasks across projects from tasks-portfolio.json)
- Knowledge freshness (days since last dimension doc update)

Statusline reads these from cache — never queries ruflo directly.

### Phase 3 — Context-adaptive display (weeks)

Show different signals based on current job. Detection via:
- `build_step` set → BUILD job
- No in_progress task → DECIDE job
- Skills write job hint to cache on entry (opt-in, not automatic detection)

| Job | Statusline emphasis |
|-----|--------------------|
| DECIDE | Next unblocked task, blocked count |
| BUILD | Build step, TDD state, correction count |
| Other jobs | Default display (add as needed) |

Start with 2 jobs (DECIDE, BUILD). Add others only when signals become available.

### Phase 4 — Auto-learning signals (later, only if Phase 1-3 stick)

| Signal | Source |
|--------|--------|
| Session corrections rate | Session state counter |
| Patterns stored this session | Written by close skill |
| Knowledge decay queue | Scheduled job cache |

All read from cache. Statusline never touches ruflo.

## Research findings

- **rz1989s/claude-code-statusline**: Multi-line layouts, 28 atomic components, burn rate tracking, MCP health, sub-50ms caching via multi-tier cache.
- **sirmalloc/ccstatusline**: Powerline rendering, token speed widgets, clickable branches via OSC 8.
- **Dan Does Code**: Minimal 60-line approach — solve actual problems, not generic ones.
- **Key insight**: No existing project integrates with a backlog/task system. Brana's statusline would be unique in showing *what* you're building, not just *where* you are.

## Risks (revised)

- **Performance**: Mitigated by replacing jq with brana-query (2ms) + self-populating cache (5ms reads)
- **Width overflow**: Mitigated by `tput cols` + progressive dropping
- **Hook fragility**: Eliminated — cache is self-populating, no PostToolUse dependency
- **Ruflo latency**: Eliminated — scheduled job writes cache, statusline never touches ruflo
- **Scope creep**: Phases 3-4 gated on Phase 1 proving value over 2+ weeks

## Engineering disciplines

- **DDD:** No ADR needed (incremental improvement to existing script).
- **TDD:** Test: cache freshness logic, width truncation, brana-query output parsing. Shell tests.
- **SDD:** Update `docs/reference/scripts.md` with new segments.

## Next steps

1. Create task for revised Phase 1 (S effort, code)
2. Implement and test for 2 weeks
3. If Phase 1 sticks, plan Phase 2 (scheduled slow-cache job)
4. Merge with t-459 (Interactive status line) if interactive features desired later
