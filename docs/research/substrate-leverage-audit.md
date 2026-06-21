# Substrate Leverage Audit — Native CC vs ruflo vs /loop

**Task:** t-2141 · **Date:** 2026-06-20 · **Status:** findings (informs ADR-059)
**Method:** live probes on the subscription, mechanism-focused (haiku + trivial tasks). Evidence below is empirical unless marked (source) = read from ruflo package source v3.10.39.

---

## Bottom line

Three execution substrates, three distinct jobs — they do **not** compete, they **layer**:

- **Native CC (Workflow + Task)** — parallel, in-session, structured *brains*. Fast fan-out, cheap, dies with the session.
- **/loop + `claude -p`** — sequential, detached *autonomy you own*. Survives session end, fully controllable, fresh boot per iteration.
- **ruflo** — *persistence + shared memory*. The memory substrate is real and load-bearing; its execution layer (autopilot, `--claude`) is **redundant with /loop** for brana and carries integration cost.

**The leverage move is composition:** an outer `/loop` for "until all done," each iteration spawning an inner native **Workflow** for parallel structured work, with **ruflo memory** as the cross-iteration blackboard. That triad covers in-session, autonomous, and shared-state needs with no redundant parts.

**For brana specifically: native CC + /loop + ruflo-memory is sufficient. ruflo autopilot and `--claude` execution are redundant** (see §Overlap). This resolves ADR-059 open q#1 (t-2140) with evidence: **native /loop wins.**

---

## Per-substrate findings

### 1. Native CC — Workflow + Task

| Property | Measured |
|----------|----------|
| Subscription-native | ✅ |
| Concurrency cap | **6** = min(16, cores−2) on this 8-core box |
| Trivial fan-out | 6 agents returned in **3.3s** wall (all concurrent), ~189k tokens total (mostly cached context) |
| Real-work scale | sweep run: **19 agents, 1.07M tokens, 28 min** end-to-end |
| Nesting | 1 level works (sweep → `workflow('verify-findings')`, validated live); 2 levels throws (by design) |
| Structured output | schema-forced StructuredOutput tool, validated-with-retry |
| Control | deterministic — `pipeline`/`parallel`, budget, resume-from-runId |
| **Cannot** | run detached — everything dies when the session ends |

**Unique power:** concurrent, structured, schema-validated fan-out with deterministic control flow, in-session, no per-agent process boot. For N parallel sub-tasks this is ~orders faster wall-clock than booting N `claude -p` processes.

### 2. /loop + `claude -p`

Throwaway harness: a bash loop driving `claude -p --model haiku` over a synthetic 3-task list (sandboxed in `/tmp`).

| Property | Measured |
|----------|----------|
| Subscription-native | ✅ |
| Per-iteration boot floor | trivial call (minimal ctx): **$0.034, ~28s wall**, usage 10 in / 78 out but **~33k cache read+creation just to boot** (SessionStart, system prompt, memory) |
| Real iteration (4 turns, tool use) | **~37s wall, ~$0.045** each |
| Full loop | 4 iters → **$0.18 total**; correctly picked first-pending each time, did the work, updated state, **self-halted on ALLDONE** |
| State across iterations | none except a shared file (each iter is a fresh process) |
| Control | ✅✅ it's *your* bash loop — bound it (MAXITER), inspect `iter_N.json`, kill it, cron it |
| **Cost driver** | the per-iteration full-session **boot tax**, not the work |

**Unique power:** detached, persistent autonomy with total operator control, using the real backlog as its queue. Survives session end; trivially cron-able. Each iteration is fully isolated.

**Gotcha found (real):** `claude -p`'s `--allowedTools` is **variadic and swallows a trailing positional prompt** → "Input must be provided…". In a harness, **pass the prompt via stdin** (`printf '%s' "$P" | claude -p … --allowedTools "Read,Write,Edit"`), not as a positional after `--allowedTools`.

### 3. ruflo (v3.10.39)

| Subsystem | Reality |
|-----------|---------|
| **CLI `--claude`** | ✅ real, subscription-native — `child_process.spawn('claude', …)` a full CC subprocess (source: `commands/hive-mind.js:267`). Same boot tax as `/loop`, plus a ~4KB Queen-coordinator roleplay prompt. |
| **MCP `agent_execute`** | ❌ direct **API-key-gated** Anthropic call; "No LLM provider configured" with no key (source: `mcp-tools/agent-execute-core.js:85-100`). Never the subscription. |
| **MCP `hive-mind_spawn` / `agent_spawn`** | ❌ create JSON records only, no LLM (hollow under subscription). |
| **autopilot** | ✅ real re-engagement loop. Live: `enable`→`check` returns `CONTINUE: 95/234 (iteration 1/50)`→`disable`. BUT: `enable` only writes a flag to `./.claude-flow/data/autopilot-state.json` — **installs no Stop hook** (source: `commands/autopilot.js:107-120`); the loop is inert until you separately wire CC's Stop event to call `check`. |
| autopilot task-pick | heuristic — `predict` = "first incomplete task", hardcoded `confidence: 0.5` (source: `autopilot.js:303`). Live `predict` chose a task from **its own flat-file sources, not brana's backlog**. |
| autopilot sources | `~/.claude/tasks/*`, `./.claude-flow/swarm-tasks.json`, `./.claude-flow/data/checklist.json` — **not** brana backlog. Defaults 50 iter / 240 min. |
| **memory** | ✅ real — SQLite at `./.swarm/memory.db`, `UNIQUE(namespace,key)`, persists cross-session, **cross-process confirmed live** (P1 stored → P2 separate process retrieved). **CWD-scoped** by default (different cwds = isolated stores); override via `CLAUDE_FLOW_MEMORY_PATH`/`CLAUDE_FLOW_DB_PATH`. No daemon. |

**Unique power:** the shared-memory substrate (cross-session, cross-process, semantic search) — already load-bearing in brana via `mcp__brana__recall` / ADR-058. The execution layer adds nothing native + /loop don't.

---

## Capability matrix

| Dimension | Native CC | /loop + claude -p | ruflo |
|-----------|-----------|-------------------|-------|
| Execution model | in-session | detached process/iter | CLI subprocess / MCP records |
| Subscription | ✅ | ✅ | ✅ CLI only |
| Parallel fan-out | ✅ cap 6 | ❌ serial | ❌ serial |
| Persistence (survives session) | ❌ | ✅ | ✅ (autopilot) |
| Cost per unit | low (cached, in-session) | ~$0.045/iter boot tax | heavy (boot + roleplay) |
| Wall-clock for N parallel | ~seconds | ~N×37s | ~N×boot |
| Shared/cross-session memory | ❌ (use ruflo) | ❌ (use ruflo/files) | ✅ sqlite |
| Task queue source | caller-provided | **brana backlog** (direct) | flat JSON (needs sync) |
| Control (bound/inspect/kill/resume) | ✅ structured | ✅✅ you own the loop | ⚠️ flag-file + hook wiring |
| Structured/validated output | ✅ schemas | ✋ parse stdout | ✋ varies |
| Setup cost to use in brana | none | trivial bash/cron | hook wiring + source sync |

---

## Overlap → what replaces what

- **/loop REPLACES ruflo autopilot for brana.** Both are "keep working until done" loops. `/loop` uses the brana backlog directly, is fully operator-controlled, and needs zero wiring. autopilot needs a Stop-hook installed + its flat-file sources synced from the backlog, and its task-pick is the same heuristic `/loop` can do for free. autopilot offers nothing extra here.
- **/loop REPLACES ruflo `--claude` for brana.** `--claude` is `claude -p` + a roleplay prompt + ruflo-memory wiring. `/loop + claude -p` is the same mechanism without the ceremony; add ruflo memory explicitly if coordination is needed.
- **Native Task REPLACES ruflo MCP hive-mind/agent_execute** entirely (those are hollow/API-keyed under subscription — already settled in ADR-059).
- **Nothing replaces ruflo memory.** It is the one irreplaceable ruflo piece.

## Compose → synergy (more than the sum)

1. **Outer /loop → inner native Workflow** *(the headline combo).* Each autonomous iteration boots `claude -p` which runs a native Workflow (sweep / hive-mind / fan-out). You get **persistence × parallelism**: "until the backlog is clear, on each task run a parallel structured analysis." Neither substrate alone does this.
2. **ruflo memory as the blackboard for stateless loops.** `/loop` iterations and native agents are stateless across boundaries; pointing them at one ruflo memory namespace (fixed path) gives cross-iteration / cross-session shared state — accumulation, dedup-vs-seen, hand-off.
3. **Native Workflow + ruflo memory.** Parallel agents write findings to a shared namespace so discovery accumulates across runs/sessions instead of restarting cold.

## Anti-patterns

- Native Workflow for overnight/detached work — it dies with the session. Use /loop.
- /loop for parallel fan-out — serial boot tax makes it slow and pricey. Use native parallel/pipeline.
- ruflo `--claude` for in-session review — full boot per reviewer vs a light native Task. Use native.
- ruflo MCP `agent_execute`/`hive-mind_*` for anything — hollow under subscription.
- autopilot wired to flat-file sources duplicating the backlog — drift risk; /loop reads the backlog directly.

---

## Recommendation — the brana leverage doctrine

```
Need agents?
├─ Parallel, structured, results THIS session   → native Workflow / Task
├─ Autonomous / overnight / "until done"        → /loop + claude -p over the backlog
│     └─ heavy per-item work inside?             → that iteration runs a native Workflow
├─ Cross-session / cross-agent shared state      → ruflo memory (fixed namespace+path)
└─ Atomic, zero-reasoning                        → claude -p --model haiku (one shot)
```

- **Adopt** native Workflow/Task as the in-session multi-agent layer (done — ADR-059).
- **Build** a thin `/loop`-over-backlog autonomous runner (the t-2140 tier) — evidence says native beats autopilot. Key design notes from the probes: pass prompt via **stdin**; scope tools with `--allowedTools` (never `--dangerously-skip-permissions` in a loop); bound with a max-iter; cost ≈ $0.045/iter so a 50-task overnight ≈ $2–3.
- **Keep** ruflo for memory only; **drop** reliance on autopilot/`--claude`/MCP-execute.

## Resolves

- **ADR-059 open q#1 (autonomous tier, t-2140):** native `/loop + claude -p` over the backlog. Evidence: works (4-iter probe, correct pick + self-halt, $0.18), backlog-native, zero wiring; autopilot needs hook+source glue for a heuristic pick `/loop` matches free.
- **ADR-059 open q on substrate division:** confirmed empirically (matrix above).

## Follow-ups (proposed)

- t-2140 → implement the `/loop`-over-backlog runner using these design notes (stdin prompt, `--allowedTools`, max-iter, cost telemetry).
- Add the leverage doctrine (the decision tree above) to `delegation-routing.md` once the runner exists.
- Document the "outer /loop → inner Workflow" combo as a reusable pattern when first used.

## First real-token validation (2026-06-20, t-2167)

The substrate's first run outside the mocked smoke harness (`.claude/workflows/tests/smoke.mjs` mocks the runtime) — `hive-mind` (one question) + `sweep` (one ~300-LOC script), via t-2167 prompt 6. Confirms it works on subscription, with these calibration numbers:

| Run | Agents | Subagent tokens | Wall | Yield |
|-----|--------|-----------------|------|-------|
| hive-mind (3 workers) | 7 | ~0.42M | ~4 min | 1 calibrated answer, 3/3 survived verify |
| sweep (1 file) | 41 | ~2.13M | ~11 min | 17 raw → 3 confirmed, **9 FPs rejected** |

**When to reach for it (routing heuristic):**

- **Fresh / unreviewed targets only** — new code, undecided designs. On hardened, well-tested code a single reviewer wins: the sweep above burned 2.1M tokens to confirm 3 OBSERVATION nits (zero surviving WARNING/CRITICAL) on an already-40-tests-covered script.
- **The value is suppression, not volume** — verify-findings rejected 75% of raw findings and downgrades evidence-free severities (a finder's CRITICAL → OBSERVATION, grounded in "0/2057 tasks lack an id"). The verify phase is evidence-anchored, not self-voted — this is what separates it from the hollow ruflo MCP layer.
- **Cost is real, high-stakes only** — budget ~0.4M tokens per hive-mind question, ~2M per sweep of one file. Never a default pass.

Persisted as `pattern_native-workflow-substrate-calibration` (auto-recall). The substrate also produced its first real architectural finding → **t-2173** (runner executor capability-isolation gap: git-worktree isolation ≠ process isolation).

> The `delegation-routing.md` follow-up above is intentionally **not** done inline: that `always-load: true` rule bundle is at its 28 KB context ceiling, so this situational heuristic lives here (on-demand) + in memory, not in always-load context.

---

> Probe evidence captured live 2026-06-20; raw harness + ruflo-internals notes were in `/tmp/substrate-audit/` (ephemeral). Key numbers are inlined above.
