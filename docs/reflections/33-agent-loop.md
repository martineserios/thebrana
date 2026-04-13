---
last_verified: 2026-04-13
status: active
maturity: active
depends_on:
  - docs/reflections/14-mastermind-architecture.md
informs:
  - docs/reflections/31-assurance.md
---

# 33 - Agent Loop: The Runtime Execution Model

How CC's internal agent loop works and where brana hooks and skills plug into it. R6 in the reflection DAG: the runtime dimension beneath what [R2 (Architecture)](./14-mastermind-architecture.md) defines.

> **Convention:** Every new hook and skill should declare which step it operates on (see [Design implications](#implications-for-hook-and-skill-design)).

Source: CC v2.1.89 leak analysis via Zain Hasan blog (ccunpacked.dev), 2026-04-08.

---

## The Loop

CC's agent loop is an async generator with 10 verified steps + 1 inferred.

```
Step 1  — Build system prompt + context
Step 2  — Normalize history
Step 3  — Apply compaction (if context exceeds trigger)
Step 4  — Stream API response
Step 5  — Detect tool_use blocks in response
Step 6  — Check permissions
Step 7  — Execute tool
Step 8  — Return result to model
Step 9  — Loop  (repeat Steps 4–8 until no tool_use)
Step 10 — Completion (emit final assistant text)
Step 11 — Post-turn hook  [inferred — not directly confirmed in source]
```

Steps 4–9 repeat for every tool call within a turn. Steps 1–3 run once per turn at the start.

---

## Where Brana Hooks Fire

| Hook event | Fires at | Hook scripts |
|-----------|----------|--------------|
| `SessionStart` | Before loop begins | `session-start.sh` — loads state, lint-heal report, startup context |
| `UserPromptSubmit` | Before Step 1 | `preflight-model.sh` — env warnings, model check |
| `PreToolUse` (Write\|Edit) | Step 6 | `pre-tool-use.sh`, `tdd-gate.sh` — doc/test gates |
| `PreToolUse` (Bash) | Step 6 | `doc-gate.sh`, `main-guard.sh`, `branch-verify.sh`, `worktree-gate.sh`, `no-attribution-commit.sh`, `commit-msg-verify.sh` |
| `PreToolUse` (EnterPlanMode) | Step 6 | `plan-mode-gate.sh` |
| `PreToolUse` (Read\|Grep\|Glob) | Step 6 | `guard-explore.sh` |
| `PostToolUse` (any) | After Step 7 | `post-tool-use.sh` |
| `PostToolUse` (Bash) | After Step 7 | `task-completed.sh`, `post-pr-review.sh` |
| `PostToolUse` (Write\|Edit) | After Step 7 | `post-sale.sh`, `post-tasks-validate.sh` |
| `PostToolUse` (ExitPlanMode) | After Step 7 | `post-plan-challenge.sh` |
| `PostToolUseFailure` | When Step 7 fails | `post-tool-use-failure.sh` |
| `SubagentStart` | Nested loop begins | `subagent-context.sh`, `subagent-tracker.sh` |
| `SubagentStop` | Nested loop ends | `subagent-tracker.sh` |
| `TaskCompleted` | CC Task finishes | `step-completed.sh` |
| `SessionEnd` | Loop terminates | `session-end.sh` — writes session state, ruflo sync |
| `StopFailure` | Step 10 fails | `stopfailure-logger.sh` |

### Step 6 is the gate

`PreToolUse` fires at Step 6 — the permission check. This is the **strongest feedback point**: hooks can deny the tool call entirely (`{"decision":"deny"}`). Use Step 6 for:
- Invariant enforcement (branch discipline, test gates, attribution stripping)
- Guard rails on dangerous operations (git push, destructive writes)

`PostToolUse` fires after Step 7 — facts on the ground. Use it for:
- Side effects (GitHub sync, logging, notifications)
- Validation on produced artifacts
- **Never** for blocking — the action already happened

### PreToolUse is per-tool, not per-turn

Every tool call fires `PreToolUse` independently. Hooks like `doc-gate.sh` and `tdd-gate.sh` that want per-turn semantics are running once per tool — wasteful on turns with 6+ tools.

`PreQuery`/`PostQuery` (once-per-turn semantics) exist in the CC source but are **not yet exposed to plugin hooks** as of CC v2.1.89. Status tracked in t-1077 — re-test on each CC upgrade.

---

## Where Skills Operate

| Step | What happens | Skills/relevance |
|------|--------------|----------------|
| Step 1 — system prompt build | CLAUDE.md, rules, dimension docs loaded | All `/brana:*` frontmatter scanned here |
| Step 3 — compaction | CC auto-compacts when context hits trigger | `/brana:close` should fire **before** this — see [context-budget.md](../architecture/context-budget.md) |
| Step 6 — permissions | Hooks gate or deny tool execution | All `PreToolUse` gates act here |
| Step 7 — tool execution | The actual tool runs | MCP tools, Bash, Write, Read all execute here |
| Step 8 — return result | Tool result injected into model context | Retrieved knowledge becomes model input here |

---

## Implications for Hook and Skill Design

When adding a hook or skill, declare its step in the script/procedure header:

```bash
# agent-loop-step: 6 (PreToolUse — permission gate)
# fires-at: per-tool
# can-deny: yes
```

```markdown
<!-- In skill procedure header -->
<!-- agent-loop-step: 1 (system prompt — loaded at session start) -->
<!-- fires-at: per-session -->
```

This makes the hook surface auditable: which steps are covered, which are overloaded.

**Current coverage gap:** Steps 2, 4, 5, 9, 11 have no brana hooks. Step 3 (compaction) is handled indirectly by the close procedure + statusline.

---

## DAG Position

```
R1 (08 Triage) → R2 (14 Architecture) → R3 (31 Assurance)
                                       → R4 (32 Lifecycle)
                                       → R5 (29 Venture)
                                       → R6 (33 Agent Loop)  ← this doc
```

R6 is the runtime dimension of R2. Where R2 describes components and layers, R6 describes how those components execute inside CC's async generator loop. R6 informs R3 (Assurance): knowing which steps hooks cover is necessary for testing hook coverage exhaustively.
