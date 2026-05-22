---
title: Claude-Gemini Orchestrator-Worker Integration
status: idea
created: 2026-05-22
---

# Claude-Gemini Orchestrator-Worker Integration

> Brainstormed 2026-05-22. Status: idea.

## Problem

Claude's token pool is the sole compute source. Gemini subscription tokens go unused.
Parallel, bulk, and speed-sensitive tasks block Claude's context instead of running
alongside it. The value is dual: token pressure relief in long sessions AND non-blocking
parallel execution for research-heavy or repetitive work.

## Solution

A three-layer stack — Bash for quick/scheduled calls, an MCP server as the typed
invocation contract, and a `/brana:gemini` skill as the full lifecycle orchestrator.
Claude plans and routes; Gemini executes as a stateless worker. Every result flows
back through Claude into the brana system.

## Architecture

```
LAYER A — Bash (today, always)
  agy -p "..." > /tmp/agy-output-{ts}.md
  Used for: quick tests, scheduled sweeps, spike validation

LAYER B — brana-mcp tools: agy_delegate (add to existing crate)
  Typed contract: task + context + output_format
  Handles: prompt file, timeout, error detection, audit
  Used for: all skill-driven delegations

LAYER C — /brana:gemini skill (builds on B)
  ROUTE → ENRICH (ruflo) → DELEGATE (mcp__agy) → APPLY → EXTRACT → PERSIST
  Used for: explicit orchestrated delegations with full lifecycle
```

```
Claude (orchestrator)
  │
  ├── Quick/scheduled → Bash: agy -p "..."
  │
  └── Skill-driven   → brana-mcp: mcp__agy__delegate()
                              │
                              └── agy (stateless worker)
                                    input:  /tmp/agy-prompt-{ts}.md
                                    output: /tmp/agy-output-{ts}.md
                                    never touches: system/ .claude/ tasks.json git
```

## Routing Heuristic

Four questions before delegating to agy:

1. **Atomic?** — completable in one `agy -p` call, no mid-task state
2a. **System-isolated?** — no writes to system/, git, hooks, tasks.json during execution
    (agy receives brana *context* via ENRICH — that is fine. It must not make brana *system calls*.)
2b. **Context-enrichable?** — ENRICH (ruflo + task context) can supply enough background for
    useful output, without needing in-session implicit state only Claude holds.
3. **Speed/token benefit?** — repetitive, fast, or token-heavy for Claude

All four yes → agy. Any no → Claude.

## Task Type Taxonomy

### agy-eligible

| Task type | Why | Example |
|-----------|-----|---------|
| Research sweep | Atomic, read-only, Flash speed | "Summarize TrackingMore webhook docs — capabilities, rate limits, event types." |
| Boilerplate generation | Repetitive patterns, deterministic | "Generate Rust structs for this JSON schema: {schema}" — ⚠️ requires convention context in ruflo (naming, derive macros, crate structure); generic output likely without it |
| Doc first draft | Fast iteration, Claude polishes | "Write a first draft of this ADR from context: {context}" — ⚠️ ADR "why" section needs explicit in-session context; pass it in the task description or quality suffers |
| Conversion/translation | Deterministic, speed matters | "Convert these TypeScript types to Python dataclasses" |
| Batch summarization | Parallel, repetitive | "Summarize each of these 10 items. One bullet per item." |
| Test scaffolding | Formulaic, Claude reviews | "Write unit test signatures (no impl) for these function specs" — ⚠️ requires convention context in ruflo (test module structure, assert patterns, async test attributes); generic scaffolding won't match codebase |
| Competitive/market analysis | Research-heavy, brana-agnostic | "Compare X and Y on speed, pricing, reliability. Return scorecard." |

### Claude-native (never delegate)

| Task type | Why |
|-----------|-----|
| brana `system/` changes | Hook enforcement required |
| Git operations | Bypasses branch-guard, main-guard |
| Task management (tasks.json) | Race condition risk (t-1507) |
| Architectural decisions | Requires in-session state + judgment (fails 2b): current tasks.json, in-flight work, implicit constraints from this session that ENRICH cannot reconstruct |
| Multi-step stateful refactors | agy is stateless in headless mode |
| Memory/session writes | brana system boundary |

## Full System Integration Map

| Component | Integration | Rule |
|-----------|-------------|------|
| **Skills** | research, build, brainstorm, docs, fix, reconcile can delegate sub-tasks | close, ship, backlog, memory — never |
| **Agents** | scout overlaps for web research — route by brana-context need | all other agents Claude-only |
| **Hooks** | agy bypasses all CC hooks | mitigation: agy → /tmp/ only, Claude applies to repo |
| **Rules** | `delegation-routing.md` gets 4-question heuristic | `git-discipline.md`, `cwd-discipline.md` get agy constraints |
| **brana CLI** | Claude calls after reading agy output | agy never calls brana CLI |
| **tasks.json** | Never touched by agy | t-1507 required before `--bg` v2 (parallel sessions); not needed for v1 foreground-only |
| **Scheduler** | brana-scheduler fires agy sweeps via shell script | Layer A only |
| **Scripts** | feed-ruflo, index-knowledge, sweep-feedback can call agy for enrichment | output always /tmp/ first |
| **ruflo/memory** | Claude mediates: extract from agy output → store via MCP tools | agy never writes to ruflo directly |
| **Plugin** | `/brana:gemini` registered in plugin.json when built | |

## /brana:gemini Skill Design

**Usage:**
```
/brana:gemini "task description"  # inline task
/brana:gemini t-XXXX              # pull task from backlog
```
> `--bg` (fire-and-continue) is out of scope for v1. The full lifecycle (APPLY/EXTRACT/PERSIST)
> requires Claude to be present when agy finishes — background mode has no trigger for those steps.
> Use Layer A (Bash + scheduler) for fire-and-forget sweeps.

**Steps:**

```
ROUTE → ENRICH → DELEGATE → APPLY → EXTRACT → PERSIST
```

- **ROUTE:** validate 4-question heuristic (Atomic? System-isolated? Context-enrichable? Speed/token benefit?). Abort with reason if not eligible.
  Hard-block for ⚠️ task types (boilerplate, ADR draft, test scaffolding) when ruflo is
  unavailable — convention context is required; generic output would silently violate
  codebase conventions. Error: "ruflo required for convention-sensitive task — use Claude directly."
- **ENRICH:** query ruflo (knowledge, limit=3), construct `/tmp/agy-prompt-{ts}.md` with task + context + output format + constraints.
- **DELEGATE:** call `mcp__agy__delegate(task, context, output_format)`. Foreground-only in v1 — wait for result before proceeding to APPLY.
- **APPLY:** Claude reads `/tmp/agy-output-{ts}.md`. Two outcomes:
  - **CONTEXT** (default) — output informs Claude's reasoning for the current session.
    No file written to repo. Used for: research sweep, competitive analysis, batch summarization.
  - **ARTIFACT** (explicit) — task description includes a target path ("write to {path}").
    Claude uses its own Write/Edit tool to land the result. All CC hooks fire normally.
    agy output never lands in the repo without Claude's explicit Write/Edit call.
  > **Deferred (v2):** TASK NOTE outcome — store agy findings directly in a task's context
  > field via `brana backlog set`. Deferred because PERSIST already handles this for the
  > calling task; a dedicated APPLY branch adds complexity without a clear v1 use case.
- **EXTRACT:** scope + novelty scoring (same rules as build/brainstorm). SMALL: auto-persist. MEDIUM: prompt. LARGE: prompt + challenger.
- **PERSIST:** `brana backlog set t-XXXX context "agy findings: {summary}"` + ruflo pattern store (`tags: ["source:agy-delegation"]`) + session log at close.

## MCP Tool Design (brana-mcp)

One new tool added to the existing `brana-mcp` Rust crate — no new binary.

```
system/cli/rust/crates/brana-mcp/src/tools/
  agy_delegate.rs   ← new (~50 lines)
  mod.rs            ← add one export
```

> `agy_status` is cut from v1 — in foreground-only mode, `agy_delegate` blocks until
> agy exits, so status is always "complete" by the time it could be called. Add back
> alongside `--bg` in v2.

**agy is the only surface coupled to Google's CLI — if agy's interface changes, only
`agy_delegate.rs` needs updating. The skill and rules are unchanged.**

```rust
// agy_delegate: version-check → write prompt → /tmp/ → spawn agy -p → validate → return
// Step 0: version pin — hard-error if agy version doesn't match pinned constant.
// If `agy --version` is unavailable (closed-source, no flag), fall back to sha256 of binary.
const AGY_PINNED_VERSION: &str = "1.0.1";  // update on each verified upgrade

// Critical: stdio must be explicitly captured — never inherited from MCP's stdio pipe.
let output = Command::new("agy")
    .arg("-p").arg(&prompt_content)
    .stdin(Stdio::null())    // never inherit MCP's stdin pipe
    .stdout(Stdio::piped())  // capture; agy stdout must NOT bleed into MCP stream
    .stderr(Stdio::piped())  // capture for structured error reporting
    .output()?;
```

Hardcodes `/tmp/` output — callers cannot override. Validates output contract before
returning — validator spec is derived from the adversarial spike (step 1.5), not assumed.
Known unknowns until spike runs: whether agy prints errors to stdout vs stderr, whether
quota/auth/rate-limit failures exit 0 or non-zero, what the error string patterns look like.
Structured error on timeout or contract violation.

**Version pinning discipline:** `AGY_PINNED_VERSION` is updated manually after each agy
upgrade — bump pin, re-run adversarial spike (C2), confirm output contract unchanged, then
commit. If `agy --version` flag doesn't exist, pin via `sha256sum $(which agy)` stored as
a constant instead. Version mismatch → hard error: `"agy version mismatch: expected {pin},
got {actual} — update AGY_PINNED_VERSION in agy_delegate.rs after re-running spike"`.

**Post-build verification:** after `cargo build --release`, confirm `~/.local/bin/brana-mcp`
reflects the new build before testing MCP tools from Claude. Stale binary = "tool not found"
with no useful error message.

## Risks and Mitigations

| Risk | Mitigation |
|------|-----------|
| agy bypasses all brana hooks | Invariant: agy output → /tmp/ only. Claude applies to repo. |
| agy interface changes silently (closed-source, no semver) | `agy --version` check at spawn; hard-error on mismatch. Re-run adversarial spike on each upgrade before bumping pin. |
| tasks.json race (t-1507 unresolved) | agy never touches tasks.json. Claude does all brana writes. |
| Bad agy output applied without review | MCP server validates output contract. APPLY step is always Claude. |
| agy error output on stdout exits 0 (quota, auth, rate limit) | Adversarial spike defines error patterns empirically before MCP tool ships (see C2 below). Validator built from observed evidence. |
| extract/persist skipped under pressure | Mandatory steps in skill — not optional. |
| Prompt injection from raw user content | Claude constructs all prompts. No raw user string interpolation. |
| agy writes directly to repo paths | MCP server hardcodes /tmp/ output — callers can't override. |
| agy hangs (rate limit, transient network) | `tokio::time::timeout(120s)` in agy_delegate. Structured error: `{"error":"agy_timeout","elapsed_secs":120}`. |
| /tmp/ accumulation (500+ files after 90 days) | `cleanup_agy_tmp()` removes prompt + output files after APPLY reads them. |

## Research Findings

- `agy` installed at `~/.local/bin/agy` v1.0.1. `agy -p "PROMPT"` works today, returns
  stdout, exit 0.
- `--print-timeout` defaults to 5 minutes. No session ID surfaced in headless mode —
  tasks must be atomic (no mid-task resume).
- Bash `run_in_background` enables true parallel execution — CC notifies on completion.
- Antigravity = Gemini CLI replacement (announced Google I/O 2026-05-19). Powered by
  Gemini 3.5 Flash at 289 tokens/sec. Closed-source.
- Existing `docs/ideas/agent-interaction-architecture.md` established Planner→Generator
  pattern with Claude Agent SDK. This extends that: Gemini replaces the SDK-based generator
  for brana-agnostic tasks.

## Build Order

```
1. ✅ Spike (happy-path)  — agy holds format + copy-paste ready output (2026-05-22)
1.5. Adversarial spike    — run agy under: no-network, malformed prompt, oversized input,
                            quota exhaustion (if reachable). Document: exit codes, stdout
                            patterns for each failure mode, stderr vs stdout split.
                            Output: failure-mode spec committed to docs/architecture/features/
                            claude-gemini-orchestration.md before step 2 starts.
                            GATE: agy_delegate.rs validator is written from this spec — not before it.
2. brana-mcp tool         — add agy_delegate to existing Rust crate (~half day)
3. /brana:gemini          — Layer C skill, full lifecycle on top of MCP (~1 day)
4. Rules update           — delegation-routing.md + git-discipline.md + cwd-discipline.md
5. Scheduler hook         — agy sweep template for overnight runs
```

> t-1507 (atomic tasks.json write) is NOT a prerequisite for v1. v1 is foreground-only —
> no concurrent writer is introduced. t-1507 becomes a prerequisite only when `--bg` mode
> ships (v2), where two sessions could call backlog_add simultaneously.

## Engineering Disciplines

- **DDD:** ADR — "agy invocation contract and routing criteria." Decisions: Layer A vs B
  per context, routing heuristic, output file convention, /tmp/ invariant.
- **TDD:** Tests for `agy_delegate` (happy path, timeout, malformed output, /tmp/ path
  enforcement, stdio isolation — MCP stream must not be contaminated by agy stdout,
  version mismatch → hard error, version match → proceeds, binary-hash fallback when
  `--version` flag absent), skill ROUTE check (ruflo-unavailable hard-block for ⚠️ types),
  PERSIST step.
- **SDD:** `docs/architecture/features/claude-gemini-orchestration.md` + update
  `docs/ideas/agent-interaction-architecture.md`.
- **Docs:** Tech doc only (internal system feature). Update `delegation-routing.md` rule.

## Next Steps

1. ✅ Spike passed (2026-05-22) — agy holds format + produces copy-paste ready output.
2. **Adversarial spike** — run agy under failure conditions (no-network, malformed prompt,
   oversized input, quota exhaustion). Commit observed exit codes + stdout/stderr patterns
   as failure-mode spec. Gates step 3.
3. Add `agy_delegate` tool to `brana-mcp` Rust crate (validator built from step 2 spec).
   Verify `brana backlog set` CLI syntax before writing skill.
4. Build `/brana:gemini` skill.
5. Update rules: `delegation-routing.md`, `git-discipline.md`, `cwd-discipline.md`.
6. Add agy sweep template to `system/scheduler/templates/`.

## Related

- `docs/ideas/agent-interaction-architecture.md` — Planner→Generator→Evaluator pattern
- `system/rules/delegation-routing.md` — routing criteria (update target)
- t-1507 — atomic tasks.json write (prerequisite for parallel safety)
