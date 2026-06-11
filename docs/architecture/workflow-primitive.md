# Workflow Primitive — Verified API Surface

> Field note, 2026-06-11. Source: direct observation of the `Workflow` tool contract in a live Claude Code session, plus smoke-test run `wf_859926e3-bd2` (below). Created to resolve challenger finding C3 on the [loop-native redesign](../research/2026-06-11-loop-native-redesign.md): the primitive had zero references in brana's corpus, so agents grepping for it concluded it might not exist. It does.

## What it is

`Workflow` is a native Claude Code tool (peer of Bash/Read) that executes a plain-JavaScript orchestration script spawning subagents deterministically. It is the "crew" half of the factory model — `/loop` is the trigger, `Workflow` is the muscle.

## Verified by smoke test (run `wf_859926e3-bd2`, 2026-06-11)

Two parallel agents, schema-validated output, one worktree-isolated:

| Probe | Result |
|---|---|
| `agent()` with JSON `schema` | Returned validated object (no parsing) — both agents |
| `parallel()` | Both agents ran concurrently; 14.5s wall clock, ~70k subagent tokens |
| `isolation: 'worktree'` | Agent executed in auto-created worktree `.claude/worktrees/wf_859926e3-bd2-2` (git toplevel = the worktree, confirmed isolated) |
| Worktree cleanup | Auto-removed after run (unchanged worktree); `git worktree list` clean |
| Background execution | Tool returns immediately with run ID; completion arrives as task-notification |

Note: workflow worktrees live under `.claude/worktrees/`, NOT the manual `../repo-slug` convention from git-discipline. Both coexist; the close-step sweep does not need to manage workflow worktrees (auto-cleaned).

## API surface (as observed 2026-06-11)

- **Script contract**: plain JS (no TypeScript), starts with `export const meta = {name, description, phases}` (pure literal). Body is async; no filesystem/Node API access. `Date.now()`, `Math.random()`, argless `new Date()` throw (resume safety).
- **Hooks**: `agent(prompt, {label, phase, schema, model, isolation, agentType})`, `pipeline(items, ...stages)` (no barrier — default), `parallel(thunks)` (barrier), `phase(title)`, `log(msg)`, `args` (input passthrough), `budget` (`total`/`spent()`/`remaining()` against "+500k"-style directives), `workflow(nameOrRef, args)` (one-level nesting only).
- **Caps**: concurrent agents min(16, cores−2); 1000 agents per run lifetime; 4096 items per pipeline/parallel call.
- **Persistence**: every run saves its script under the session dir; named workflows resolve from `.claude/workflows/`. Resume via `{scriptPath, resumeFromRunId}` — unchanged agent-call prefix returns cached results.
- **Failure semantics**: erroring/skipped agents resolve to `null` (filter with `.filter(Boolean)`); a throwing pipeline stage drops that item.

## Opt-in rule (load-bearing for the factory)

The tool may only be invoked when the user explicitly opts in. The recognized paths:

1. "ultracode" keyword in the prompt (or on for the session)
2. user asks for a workflow / multi-agent orchestration in their own words
3. **user invoked a skill or slash command whose instructions call Workflow**
4. user names a saved workflow

Path 3 is what legitimizes the factory crew: a foreman recipe the user starts (via `/loop`) that dispatches `Workflow` per task satisfies the opt-in. An agent deciding on its own that a task "would benefit" does not.

## Constraints relevant to the factory design

- Headless/cron runs may lack interactively-authenticated MCP servers — reinforces the per-session foreman decision in [ADR-050](decisions/ADR-050-loop-request-protocol.md).
- Subagents return raw data (their final text is the return value, not a user-facing message) — AC verdicts should use `schema` for machine-checkable output.
- Stability caveat: this documents the surface as of CC ~v2.1.x, 2026-06-11. Re-verify on major CC upgrades before extending factory designs that lean on uncommon corners (nesting, budget, resume).
