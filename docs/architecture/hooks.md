# Hooks Architecture

> 25+ shell scripts that fire on Claude Code lifecycle events. Hooks enforce discipline, log events, and nudge agents -- all without requiring user action. For complete I/O specs, see [Hook Reference](../reference/hooks.md).

## How hooks work

Claude Code supports these hook events:

| Event | When it fires | Can block? |
|-------|---------------|------------|
| `SessionStart` | Beginning of every session | No |
| `SessionEnd` | End of every session | No |
| `PreToolUse` | Before a tool call executes | Yes |
| `PostToolUse` | After a tool call succeeds | No |
| `PostToolUseFailure` | After a tool call fails | No |
| `UserPromptSubmit` | Before Claude processes user input | No |
| `SubagentStart` | When a subagent is spawned | No |
| `SubagentStop` | When a subagent completes | No |
| `TaskCompleted` | When a CC Task is marked complete | No |
| `Stop` | After each clean turn completion | Advisory — can return `{"decision":"block"}` to continue, but brana hooks always approve |
| `StopFailure` | On API errors (rate limit, auth, billing) | No |
| `ConfigChange` | When a settings file is modified in-session | Yes (exit 2) |
| `PreCompact` | Before context compaction runs | Yes (exit 2 or `{"decision":"block"}`) |

Hooks receive session context as JSON on stdin, return JSON on stdout. A hook can pass through (`{"continue": true}`), inject context (`additionalContext`), or block (PreToolUse only, via `permissionDecision: "deny"`).

All brana hooks follow a safety principle: they never fail fatally. Every hook uses `|| true` fallbacks and graceful degradation.

### Hook entry format

Each hook entry in `hooks.json` requires a `command` field (string), not `args` (array):

```json
{ "type": "command", "command": "bash ${CLAUDE_PLUGIN_ROOT}/hooks/script.sh", "timeout": 5000 }
```

The `args: ["bash", "path"]` array form was removed from CC's hook schema. Using `args` causes a silent load failure — `/doctor` reports "expected string, received undefined" for every entry. Fix: join the array into a space-separated string under `command`. (E2026-05-31-2, promoted 2026-05-31)

## Plugin/bootstrap split (CC bug #24529)

CC v2.1.x silently drops PostToolUse and PostToolUseFailure events from plugin `hooks.json`. Only PreToolUse, SessionStart, and SessionEnd fire reliably from plugins.

| Installed via | Events | File |
|--------------|--------|------|
| Plugin `hooks.json` | PreToolUse, SessionStart, SessionEnd | `system/hooks/hooks.json` |
| Bootstrap `settings.json` | PostToolUse, PostToolUseFailure | `~/.claude/settings.json` |

When CC fixes #24529, all hooks move back to `hooks.json`. See [PostToolUse Workaround](posttooluse-workaround.md) for details.

## Shared library

**`lib/cf-env.sh`** -- Locates the `ruflo` binary. Source it to get `$CF`. Search order: nvm global install, PATH lookup, npx fallback. Used by session-start, session-end, session-start-venture, and post-sale hooks.

**`lib/ruflo-mcp.sh`** -- MCP server wrapper script that resolves the ruflo binary dynamically at launch time instead of hardcoding paths. Includes a PID lock (prevents concurrent SQLite corruption) and auto-restart on SIGTERM (up to 5 retries, mitigates CC bug #40207 which kills healthy MCP servers mid-session). `brana-mcp` uses a direct binary path in `.mcp.json` — no wrapper needed.

**`config-drift.sh`** -- Called by `session-start.sh` at every session start. Compares `system/` source files against deployed `~/.claude/` files (CLAUDE.md + rules/) and scans `~/.claude.json` for ADR-033 violations (npx/uvx in MCP server commands). Output JSON: `{status, count, drifted[], mcp_violations[], mcp_count}`. Any violations surface in `DRIFT_CONTEXT` at session start.

**`lib/git-helpers.sh`** -- Shared utilities for hooks that inspect git branch state. Provides `extract_git_c_dir()` (path from `git -C <path>`), `extract_cd_prefix_dir()` (path from a leading `cd <path> &&` / `;` / `||`), and `resolve_lookup_dir()` (3-tier lookup: `-C` > `cd` prefix > CWD). Sourced by `branch-verify.sh` and `main-guard.sh`. Prevents hooks from checking the session CWD instead of the target repo when CC issues either `git -C <worktree> …` or `cd <worktree> && git …` commands. Spec: `system/hooks/lib/git-helpers.spec.md`.

**`lib/layer1-paths.sh`** -- Layer 1 file classification. Provides `is_layer1_file()` that returns 0 for files that must never be LLM-written (currently: any path ending in `CLAUDE.md`). Sourced by `feedback-gate.sh`. Centralizes the Layer 1 boundary so all enforcement hooks stay in sync when the definition expands.

## Hook inventory

### Plugin hooks (hooks.json)

| Hook | Event | Matcher | Purpose |
|------|-------|---------|---------|
| `pre-tool-use.sh` | PreToolUse | `Write\|Edit` | Spec-before-code gate + cascade throttle |
| `tdd-gate.sh` | PreToolUse | `Write\|Edit` | TDD baseline — blocks impl writes when no test exists in project. Ordering enforcement (tests before impl) lives in procedure gates, not here |
| `plan-mode-gate.sh` | PreToolUse | `EnterPlanMode` | Enforce plan mode for non-trivial builds |
| `worktree-gate.sh` | PreToolUse | `Bash` | Gate A: block `git checkout -b` / `git switch -c` when dirty or worktrees active — **exception**: if the only dirty file is `.claude/tasks.json`, emits a warn (continue:true) instead of deny (t-1320). Gate B: block `git commit` when /tmp >95% full; warn on cross-session staged files |
| `branch-name-warn.sh` | PreToolUse | `Bash(git *)` | Hard-block: rejects `git switch -c` / `git checkout -b` / `git branch <name>` when the new name doesn't match `{epic-slug}/{work-type}/t-{NNN}-` convention. Skips: main, master, docs/*, hotfix/*. Escape hatch: `--force-name`. Shipped advisory (t-1620), upgraded to block (t-1718). |
| `doc-gate.sh` | PreToolUse | `Bash` | Block `git commit` on any branch when behavioral files (skills, hooks, agents, commands, cli, rules) are staged but no docs change is present. Spec-before-code enforcement. |
| `main-guard.sh` | PreToolUse | `Bash` | Block behavioral commits on main/master. Forces work onto feat/fix/* branches for proper gate enforcement. Uses `lib/git-helpers.sh` → `resolve_lookup_dir()` for worktree-aware repo detection. |
| `branch-verify.sh` | PreToolUse | `Bash` | Block `git add` of behavioral files when on main/master. Uses `lib/git-helpers.sh` → `resolve_lookup_dir()` to extract `git -C <path>` from the command and check the target repo's branch. Escape hatch: `# --force-main` comment. |
| `feedback-gate.sh` | PreToolUse | `Write\|Edit` | Block writes to `feedback_*.md` files outside the auto-memory procedure. Layer 1 guard (via `lib/layer1-paths.sh`) blocks `CLAUDE.md` writes unconditionally. Sentinel bypass: `/tmp/brana-memory-active`. Spec: ADR-037. |
| `memory-write-gate.sh` | PreToolUse | `Write\|Edit` | Block brana-procedure-driven typed-memory writes (`{type}_{slug}*.md`) in any `*/memory/` directory unless sentinel `/tmp/brana-memory-write-active` is present. **Pass-through exception**: paths under `~/.claude/projects/*/memory/` from the CC auto-memory system are allowed unconditionally — the hook distinguishes by write origin (sentinel present = brana procedure; no sentinel + CC auto-memory path = allowed). Spec: ADR-038. |
| `rust-skills-guard.sh` | PreToolUse | `Write\|Edit` | Block `*.rs` writes until `brana:rust-skills` is loaded this session. Sentinel: `/tmp/brana-rust-skills-loaded-{SESSION_ID}` (written by `skill-sentinel.sh`). Bypass: `/tmp/brana-rust-skills-guard-bypass`. Enforcement complement to build.md step 4a advisory gate. t-1480. |
| `no-attribution-commit.sh` | PreToolUse | `Bash` | Block `git commit` and `gh pr create` calls containing forbidden attribution signatures (Co-Authored-By, Signed-off-by). Keeps commit history clean. |
| `commit-msg-verify.sh` | PreToolUse | `Bash` | Advisory (non-blocking): warns when commit message mentions filenames not in the staged diff. Catches commit messages that describe more than what was actually staged. |
| `guard-explore.sh` | ~~PreToolUse~~ | ~~`Read\|Grep\|Glob`~~ | **Deregistered 2026-05-30** (t-1711). Gated behind "strict" profile — never ran in standard sessions. Observation period complete (t-639 2026-03-31). |
| `subagent-context.sh` | SubagentStart | `""` (all) | Inject active task + branch + plan + recent decisions into spawned agents |
| `subagent-tracker.sh` | SubagentStart+SubagentStop | `""` (all) | Track agent spawns and completions to session JSONL |
| `step-completed.sh` | TaskCompleted | `""` (all) | Track CC Task completions for guided execution |
| `task-completed.sh` | PostToolUse | `Bash` | Task completion pipeline: parent task rollup, close linked GitHub issue, log to decision log. Triggers on `brana backlog set <id> status completed`. |
| `hallucination-detect.sh` | PostToolUse | `Bash` | Advisory: warns when a commit message contains completion keywords (fix/done/complete/close/resolve) but no test files were staged. Never blocks. |
| `bash-output-compress.sh` | PostToolUse | `Bash` | Advisory: if Bash output exceeds 100 lines or 8000 chars, injects compressed view (first 30 + truncation marker + last 10) via `additionalContext`. Saves context budget on verbose CLI output. Never blocks. t-1716. |
| `skill-sentinel.sh` | PostToolUse | `Skill` | Write skill-loaded sentinel `/tmp/brana-{skill}-loaded-{SESSION_ID}` when a gated skill completes. Extension point: add entries to GATED_SKILLS case block for new skill gates. Paired with `rust-skills-guard.sh`. t-1480. |
| `preflight-model.sh` | UserPromptSubmit | `""` (all) | Advisory (non-blocking): warns when a heavy skill (`/brana:close`, `/brana:brainstorm`, `/brana:build`) is invoked while extra-usage is disabled. Silence: `BRANA_1M_WARN_OFF=1`. |
| `context-inject.sh` | UserPromptSubmit | `""` (all) | Advisory: detects t-NNN task IDs and file paths in the prompt. Injects task subject/description/context (max 3 IDs) and file `head -20` content (max 3 paths). Absolute, relative (resolved to project root), and `~` paths supported. |
| `signal-capture.sh` | UserPromptSubmit | `""` (all) | Advisory: detects explicit ratings (N/5, N/10, emoji) and implicit sentiment (English + Spanish phrases) in user prompts. Writes to `~/.claude/ratings/ratings.jsonl`; dumps failure context to `FAILURES/`. |
| `session-start.sh` | SessionStart | `""` (all) | Pattern recall (1 parallel job, 2s budget), task context, venture detection, recurring error surfacing, extra-usage warning. Reads `effort.level` from hook JSON (`CLAUDE_CODE_SESSION_ID` env fallback for session_id). Skips ruflo search at effort=low. |
| `session-end.sh` | SessionEnd | `""` (all) | Orchestrator — forks 4 sub-scripts: `session-end-metrics.sh` (flywheel metrics), `session-end-persist.sh` (ruflo + auto-memory), `session-end-drift.sh` (sync-state, spec graph, decisions log), `session-end-pattern-promotion.sh` (pattern confidence update — t-203) |
| `goal-completion.sh` | Stop | `""` (all) | Reads `~/.claude/run-state/active-goal.json` (written by `/brana:build` when `AC:` lines or `acceptance_criteria` are found). Validates each criterion via 8 heuristics: file-exists, `brana backlog get … returns …`, `validate.sh Check N`, hook-name-exists, file-contains, jq-query, command-exits-0 (allowlisted), git-log. Session binding (only fires for session that set the goal), 48h stale guard, CWD matching. Auto-marks task completed when all pass; surfaces failing criteria via `additionalContext`; never blocks stop. t-1779, t-1828, ADR-047. |
| `stopfailure-logger.sh` | StopFailure | `""` (all) | Log API errors (rate limit, auth, billing) to JSONL |

### Bootstrap hooks (settings.json)

| Hook | Event | Matcher | Purpose |
|------|-------|---------|---------|
| `post-tool-use.sh` | PostToolUse | `Write\|Edit\|Bash` | Log successes, detect corrections and test writes |
| `post-tool-use-failure.sh` | PostToolUseFailure | `Write\|Edit\|Bash` | Log failures, detect cascades (3+ consecutive), track error recurrence across sessions |
| `post-plan-challenge.sh` | PostToolUse | `ExitPlanMode` | Nudge challenger agent after plan finalization |
| `post-tasks-validate.sh` | PostToolUse | `Write\|Edit` | Validate tasks.json schema + auto-rollup parents |
| `post-sale.sh` | PostToolUse | `Write\|Edit` | Detect deal closures in pipeline files |
| `post-pr-review.sh` | PostToolUse | `Bash` | Nudge pr-reviewer agent after `gh pr create` |

### Inactive

| Hook | Status |
|------|--------|
| `session-start-venture.sh` | Logic absorbed into `session-start.sh`. Kept for reference. |

## Hook profiles

Hooks support tiered execution via the `BRANA_HOOK_PROFILE` environment variable. This allows running lighter hook sets in contexts where speed matters more than full enforcement.

| Tier | What runs | Effort level | Use case |
|------|-----------|-------------|----------|
| `minimal` | Nothing (all profiled hooks skip) | `max` | Fast CI runs, debugging hook issues |
| `standard` | `pre-tool-use.sh`, `worktree-gate.sh` | `high` | Default — production behavior, backward compatible |
| `strict` | All standard + `guard-explore.sh` | `low` | Observation mode — collects read pattern data |

**Default:** `standard` (no env var needed, no behavior change from pre-profile state).

**Set it:** `export BRANA_HOOK_PROFILE=strict` in your shell, or add to `~/.claude/settings.json` env section.

**Effort level:** Each tier maps to a CC effort level via `get_profile_effort()`. Exported as `BRANA_EFFORT_LEVEL` at session start. Agents override via frontmatter `effort:` field; users override with `/effort`. Direct override: `export BRANA_EFFORT_LEVEL=medium`.

**CC-native effort.level (t-1402):** CC v2.1.133 adds `effort.level` to hook JSON input and `$CLAUDE_EFFORT` to Bash subprocess env. Both `session-start.sh` and `post-tool-use-failure.sh` now read this field (`jq -r '.effort.level // "normal"'`) and skip non-critical slow operations when effort is `"low"`: session-start skips the ruflo memory search; post-tool-use-failure skips the ruflo rule-candidate escalation. CC v2.1.132 added `CLAUDE_CODE_SESSION_ID` to Bash subprocess env — both hooks fall back to this env var if session_id is absent from JSON: `SESSION_ID="${SESSION_ID:-${CLAUDE_CODE_SESSION_ID:-}}"`. All local JSONL writes and cascade detection are unaffected by effort level.

**Library:** `system/hooks/lib/profile.sh` provides `hook_should_run <tier>` and `get_profile_effort`. Any hook can source it:

```bash
source "${SCRIPT_DIR}/lib/profile.sh" 2>/dev/null || true
hook_should_run "standard" || { pass_through; exit 0; }
```

Only 3 hooks use profiles today. Hooks without profile gates (session-start, session-end, subagent-context, etc.) always run regardless of tier.

## Guard-explore (read pattern observability)

`guard-explore.sh` fires on every `Read`, `Grep`, and `Glob` call. It tracks whether agents search before reading implementation files — a quality signal from Agentic Scripts research (80% tool call reduction with search-first patterns).

**Current mode: logging only.** No blocking. After 1 week of data collection, enforcement can be enabled.

**How it works:**
1. **Grep/Glob calls** — recorded to `/tmp/brana-search-{SESSION_ID}.log`
2. **Read calls on impl files** (`src/`, `lib/`, `system/cli/`, `system/scripts/`) — checks if any search preceded it. If not, logs to `/tmp/brana-explore-{SESSION_ID}.log`
3. **Whitelisted files** always pass through: `*.md`, configs (`*.json`, `*.yaml`, `*.toml`), test files, `docs/`, `.claude/`, `system/skills/`, `system/hooks/`

**Analyzing results:** After a week, review `/tmp/brana-explore-*.log` files to see how often reads happen without searches. High counts indicate search-first enforcement would reduce wasted tool calls.

## Subagent context injection

`subagent-context.sh` fires on every `SubagentStart` event. Every scout, explorer, and delegated agent automatically receives context about the current work state — no manual briefing needed.

**What gets injected** (via `additionalContext`, capped at ~500 tokens):

| Data | Source | When included |
|------|--------|---------------|
| Active task (id, subject, strategy, build_step, tags) | `brana backlog query --status in_progress` | Always (if a task is active) |
| Current git branch | `git branch --show-current` | Always (if in a git repo) |
| Active plan title | First `*.md` in `~/.claude/plans/` | Only during plan mode |
| Last 3 decisions | `system/state/decisions/*.jsonl` (most recent) | Only if decision log exists |

If no in_progress task exists, the hook returns `{"continue": true}` with no injection — subagents start clean.

## Ruflo wiring in hooks

As of 2026-04-01, three hook scripts integrate with ruflo MCP via `cf-env.sh`:

- **`session-start.sh`** — Runs 1 parallel job (single `timeout 2` ruflo CLI query for patterns + corrections), down from 4 jobs with a 5s budget. Python dependencies (spec-graph staleness check, decisions.py) removed. Phase 5 launches `index-skills.sh --changed` in background. All `$CF` calls are preceded by `cd "$HOME"` to avoid CWD issues with npx resolution. As of 2026-04-06, also surfaces the next unblocked task's `context` field in the task summary output. As of 2026-04-08 (t-1034), reads `~/.claude.json` for `cachedExtraUsageDisabledReason` and emits `[Extra-usage]` warning when set — CC caches extra-usage state there, and if it's disabled at the org level, 1M-context models fail around the 200k-token mark mid-skill. Silence: `BRANA_1M_WARN_OFF=1`.
- **`session-end.sh`** — Same `cd "$HOME"` guard before `$CF` calls for metrics flush and session summary storage.
- **`post-sale.sh`** — Uses `cd "$HOME"` before ruflo CLI calls (fixed 2026-04-06 — previously used CWD-relative path, writing to wrong DB).
- **`cf-env.sh`** — Now exports a `cf_run()` wrapper function that handles `cd "$HOME"`, timeout, and error swallowing in one call. Hook scripts use `cf_run <args>` instead of raw `$CF` invocations.

## Design principles

**Enforcement vs advisory gate taxonomy (2026-05-15)** -- Every PreToolUse gate must declare its class at write time. Enforcement gates block unconditionally — bypassing them corrupts an invariant. Advisory gates reject but allow the agent loop to recover via `continueOnBlock: true`, feeding the rejection as context instead of terminating.

Differentiator: "Does bypassing this gate corrupt an invariant that cannot be repaired in the same session?" Yes → enforcement. No → advisory. When adding a new hook, declare its class in the hook file header comment.

**Gate classification (all PreToolUse and blocking PostToolUse hooks):**

| Hook | Matcher | Class | `continueOnBlock` | Invariant / why |
|---|---|---|---|---|
| `pre-tool-use.sh` | Write\|Edit | **Enforcement** | Never | Spec-before-code: impl without a spec cannot be undone in the same session |
| `tdd-gate.sh` | Write\|Edit | **Enforcement** | Never | Test-before-code: impl without a failing test violates the TDD contract |
| `rust-skills-guard.sh` | Write\|Edit | **Enforcement** | Never | Rust-skills load-before-code: writing *.rs without domain knowledge violates quality invariant; sentinel is session-scoped |
| `feedback-gate.sh` (Layer 1) | Write\|Edit | **Enforcement** | Never | CLAUDE.md files are human-authored load-bearing docs — LLM writes corrupt authorship |
| `feedback-gate.sh` (non-L1) | Write\|Edit | **Advisory** | Yes | Feedback memory is LLM-writable; rejection becomes context for retry |
| `plan-mode-gate.sh` | EnterPlanMode | **Advisory** | Yes | Planning encouragement; skipping plan mode is recoverable |
| `worktree-gate.sh` | Bash | **Enforcement** | Never | Branch discipline: behavioral changes must go through a worktree branch |
| `doc-gate.sh` | Bash | **Enforcement** | Never | Spec-in-same-commit: behavioral commits without docs corrupt the change record |
| `main-guard.sh` | Bash | **Enforcement** | Never | Behavioral commits must never land on main directly |
| `branch-verify.sh` | Bash | **Enforcement** | Never | Behavioral files must not be staged on main (caught before main-guard) |
| `no-attribution-commit.sh` | Bash | **Enforcement** | Never | Attribution lines in commits are a hard quality rule; no safe recovery path |
| `commit-msg-verify.sh` | Bash | **Advisory** | Yes | Commit hygiene guidance; loop continues with a formatted message suggestion |
| `guard-explore.sh` | Read\|Grep\|Glob | **Advisory** | Yes | Search-before-read nudge; currently logging only — not yet blocking |
| `post-plan-challenge.sh` | ExitPlanMode | **Advisory** | Yes | Challenger suggestion after plan exit; loop continues with review context |
| `post-tasks-validate.sh` | Write\|Edit | **Advisory** | Yes | Task format validation after write; loop continues with correction context |

**Spec-first enforcement** -- `pre-tool-use.sh` is the strongest feedback mechanism (a "Stop hook"). A PERMISSION DENY cannot be ignored. Projects opt in by having `docs/decisions/`.

**Session event pipeline** -- PostToolUse/PostToolUseFailure hooks append JSONL events to `/tmp/brana-session-{SESSION_ID}.jsonl`. The session-end hook consumes this file, computes 7 flywheel metrics (correction_rate, auto_fix_rate, test_write_rate, cascade_rate, test_pass_rate, lint_pass_rate, delegation_count), and persists to ruflo memory.

**Immediate response pattern** -- `session-end.sh` responds with `{"continue": true}` immediately, then forks heavy processing to background. CC cancels hooks during session teardown, so the response must come before any processing.

**Auto-populate PATTERN_LEARNINGS (t-1450)** -- Before calling `session-end-persist.sh`, `session-end.sh` calls `brana session read --json` and extracts `.learnings[]`. If `PATTERN_LEARNINGS` is not already set by the caller (or is `[]`), it is populated from the session state array. This makes the classify-then-route pipeline (t-1264) automatic — patterns.md is written at session end without any caller explicitly setting `PATTERN_LEARNINGS`. Pre-set values from callers are never overwritten (precedence: caller > session state). Both `PATTERN_LEARNINGS` and `KNOWLEDGE_FINDINGS` are included in the export list so `session-end-persist.sh` receives them. Previously these vars were missing from the export list, making classify-then-route dead code in production for ~6 weeks.

**Cascade detection** -- `post-tool-use-failure.sh` tracks consecutive failures on the same target. At 3+ failures, it flags a cascade so `pre-tool-use.sh` can inject a warning on the next attempt.

**Error recurrence tracking (t-679)** -- `post-tool-use-failure.sh` computes an error signature (md5 of tool_name + error_cat + first 80 chars of detail) and increments a counter in `~/.claude/logs/error-recurrence.jsonl`. When the same signature hits 3 occurrences across sessions, it stores to ruflo memory with tag `escalate:rule-candidate`. `session-start.sh` scans the recurrence file and surfaces errors with count >= 3 as "[Recurring errors -- rule/hook candidates]" in session context.

**File-targeted tool enumeration (promoted 2026-05-14, completed 2026-05-15)** -- The detail-extraction case statement in `post-tool-use-failure.sh` must explicitly enumerate every CC tool that takes a `file_path` or `notebook_path` input: `Read`, `Edit`, `Write`, `NotebookEdit`, `MultiEdit`. Any tool missing from the branch falls through to the `TOOL_NAME` fallback, making all its failures log `detail="<ToolName>"` — collapsing distinct failures into one indistinguishable signature bucket. History: `Read` was missing (572 failures, hash bc9058e8) before 4c21e36; `NotebookEdit` and `MultiEdit` were missing until 2026-05-15 (t-1397). Note: `NotebookEdit` uses `notebook_path` not `file_path` — extraction uses `.file_path // .notebook_path // empty`. Rule: when adding a new file-targeted tool to CC, update the case branch and the regression test. A regression test (`test-post-tool-use-failure-detail.sh`) guards this.

**Test signal extraction (t-467, 2026-05-17)** -- `post-tool-use.sh` reads `tool_response.content` when the Bash command matches a test runner pattern (`cargo test`, `uv run pytest`, `jest`, `vitest`). It parses pass/fail counts from each runner's summary line (cargo: `test result:`, pytest: `===…===`, jest/vitest: `Tests:`) and emits conditional `test_pass`/`test_fail` integer fields in the JSONL event. When all tests pass and no "N failed" pattern appears, `test_fail` defaults to `0` (not empty) — callers must distinguish "zero failures" from "no signal extracted" (empty field). Covered by `system/hooks/tests/test-post-tool-use-test-signal.sh` (21 tests).

**Agent nudging** -- Several hooks inject `additionalContext` that triggers auto-delegation to agents: post-plan-challenge (challenger), post-pr-review (pr-reviewer), session-start (daily-ops for venture projects).

## Hook registration format

Plugin hooks use `${CLAUDE_PLUGIN_ROOT}` for paths:

```json
{
  "hooks": [
    {
      "event": "PreToolUse",
      "matcher": "Write|Edit",
      "command": "${CLAUDE_PLUGIN_ROOT}/hooks/pre-tool-use.sh",
      "timeout": 5000
    }
  ]
}
```

Bootstrap hooks use absolute paths in `~/.claude/settings.json`:

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Write|Edit|Bash",
        "hooks": [
          { "type": "command", "command": "$HOME/.claude/hooks/post-tool-use.sh", "timeout": 5000 }
        ]
      }
    ]
  }
}
```

Multiple hooks can register for the same event. They run sequentially; if any PreToolUse hook blocks, the tool call is denied.

## Field Notes

> Archived 2026-05-09: 5 oldest entries (2026-04-08 × 2, 2026-04-09, 2026-04-12 nvm PATH, 2026-04-12 worktree-gate checkout/switch) moved to ruflo field-notes namespace (t-1388).
> Archived 2026-05-11: 5 entries (2026-04-10 × 5: doc-gate bash command, git checkout HEAD recovery, branch switches ephemeral, main-guard+doc-gate combo, tasks.json stash theirs) moved to ruflo knowledge namespace.


> Archived 2026-05-28: 5 entries (2026-04-13 commit-msg-verify advisory, 2026-05-09 × 4: stderr blocking, jq encoding, script-body-immediate, TDD fixture bleed) moved to ruflo field-notes namespace.

### 2026-05-11: Field notes live in docs/architecture/, not docs/reference/
Two files share the basename `hooks.md`: `docs/reference/hooks.md` (auto-generated, "Generated by brana reference generate — do not edit manually" banner) and `docs/architecture/hooks.md` (editable, owns the field-note log). Always target `docs/architecture/<topic>.md` for field notes and manual edits. Edits to `docs/reference/` are silently overwritten on next generation. Applies to hooks.md, skills.md, and any file with both an architecture and a reference version.

### 2026-05-14: PreCompact hook — brana has no immediate use case
CC v2.1.105 added `PreCompact` (exit 2 or `{"decision":"block"}` to block compaction). Evaluated for brana hooks: no immediate use case exists. Session state is written at session-end (not at compaction time), and compaction is not a predictable signal for flush operations. A future hook could block compaction when a structured session-state JSON is absent (forcing the user to run `/brana:close` first), but this would be intrusive and is not warranted. Added `PreCompact` to KNOWN_EVENTS table.
Source: t-1404, session 2026-05-14

### 2026-05-14: CC v2.1.126 removed per-file malware assessment on Read — explains Read x572
Prior to CC v2.1.126, each `Read` tool call triggered an internal malware-assessment step. These internal calls fired `PostToolUseFailure` when they hit errors, all logging `detail="Read"` (before the file_path extraction fix). This is the most likely explanation for the 572 Read tool-fail accumulation. Now on v2.1.141, this assessment is removed. Monitor `~/.claude/logs/error-recurrence.jsonl` for 2-3 sessions: if the Read count stops growing, root cause is confirmed (t-1405). If new Read failures appear with distinct file_paths (now captured post-fix), classify by path family to find the true source.
Source: t-1397/t-1405, CC changelog v2.1.126, session 2026-05-14
Source: reconcile / close session 2026-05-11

### 2026-05-15: Partial tool enumeration leaves silent diagnostic dark spots
When fixing a hook that enumerates file-targeted tools (`Edit|Write|Read`), stopping at the obvious cases leaves unlisted tools (e.g. `NotebookEdit`, `MultiEdit`) falling through to the `TOOL_NAME` fallback — producing `detail="NotebookEdit"` instead of the path. The dark spot is invisible until the missing tool fires in production. Rule: any enumeration fix must grep the full CC file-targeted tool list and assert all cases are covered in the same commit. Also add a test that loops over all listed tools. Applies to any hook with a case-based dispatch on tool names.
Source: t-1397, session 2026-05-15

### 2026-05-15: NotebookEdit uses notebook_path, not file_path
CC's `NotebookEdit` input uses `notebook_path` as the key, not `file_path`. Hooks extracting file targets from tool_input must handle both: `.file_path // .notebook_path // empty`. Same pattern likely applies to future tools with different path field names (e.g. `Glob`/`Grep` use `pattern`). Build the extraction as `jq -r '.file_path // .notebook_path // empty'` and document it in the case branch comment when adding any new file-targeted tool.
Source: t-1397, session 2026-05-15

### 2026-05-15: branch-verify.sh parent-dir glob fires on non-behavioral staged files [→ t-1424]
`is_behavioral()` has a reverse-direction check: `case "$bpath" in ${file}|${file}/*)`. If `file="system"` (bare dir name, e.g. from parsing text after a `git add` substring in a Bash command payload), `system/hooks` matches the glob `system/*` and the hook denies with "Files: system". Neither `.claude/tasks.json` nor `docs/ideas/*.md` is behavioral, but staging them alongside any command text containing "git add" + "system/" triggers this. Fix in t-1424: remove the reverse-direction case. Real staging always produces full blob paths (`system/hooks/foo.sh`), never bare parent dirs.
Source: t-1424, session 2026-05-15 (E2026-05-15-2)

### 2026-05-15: Worktree workflow confirmed for system/hooks/ changes — no friction
Feature branch via worktree + merge --no-ff with regression test included worked cleanly for a protected behavioral change. The worktree-gate fires, worktree is created, changes are committed and merged, worktree is reaped. No edge cases observed. Aligns with `feedback_worktree-for-rules.md`. Continue this pattern for all `system/hooks/` and `system/skills/` behavioral changes.
Source: t-1397, session 2026-05-15

### 2026-05-18: Background Phase 5 jobs write to inherited stdout — tests must extract first JSON line
`session-start.sh` forks its background Phase 5 block (`index-skills.sh`, `sync-state.sh`) via `( ... ) & disown`. `disown` removes the job from the shell job table but does NOT close the inherited stdout file descriptor. In test contexts using bash process substitution (`OUTPUT=$(bash hook.sh <<< input)`), the background job's stdout ("No skills to index.") appends to the same capture buffer after the JSON response, making `jq .` fail. Fix for consumers: `grep '^{' | head -1 | jq ...` extracts only the first JSON line. Fix for new hook code: redirect background work to a log file — `( work ) >>/tmp/brana-bg.log 2>&1 &` — to prevent stdout pollution.
Source: t-1434 Test 18, session 2026-05-18

**Hook test helpers** (`tests/hooks/_helpers.sh`) encode this distinction: `run_hook()` pipes input and merges stderr (for hooks with clean stdout); `run_hook_json()` extracts the first `{`-prefixed line with stderr suppressed (for hooks that spawn background jobs); `run_hook_timed()` is the timed JSON-extracting variant that returns `elapsed_ms|json`. Use `run_hook_json()` for `session-start.sh` and any hook that forks background work. Use `run_hook()` for all others.
Source: t-1441, session 2026-05-18

### 2026-05-18: brana skills list normalized to brana: prefix (fixed t-1440)
~~`brana skills list` returned unprefixed names (`close`, `sitrep`) while `brana skills usage` returned prefixed names (`brana:close`).~~ Fixed by t-1440: `brana skills list` now emits `brana:`-prefixed names, aligned with CC's canonical `/brana:close` invocation surface. `brana:` prefix is the canonical form for all skill name references across `list`, `usage`, and `search`.
Source: t-1437 (diagnosis), t-1440 (fix), session 2026-05-18

### 2026-05-18: Hook-chain export list parity — audit parent `export` before assuming child receives vars
When wiring a multi-stage hook chain (e.g., session-end.sh → session-end-persist.sh), the child's read logic and tests can pass while production is silent — because test harnesses set env vars directly, bypassing the parent's export. The parent's `export` list is the only thing that matters in production. Checklist: for every env var a child script reads, verify it appears in the parent's `export` list. Child-side tests that `export FOO=value` before calling the child will pass regardless. t-1264 classify-then-route was dead code for ~6 weeks because PATTERN_LEARNINGS/KNOWLEDGE_FINDINGS were missing from session-end.sh's export.
Source: t-1450, session 2026-05-18

### 2026-05-19: Same-commit hook-doc backprop is recurring — needs enforcement, not just policy
t-1480 shipped `rust-skills-guard.sh` + `skill-sentinel.sh` without updating `docs/architecture/hooks.md` inventory or gate classification. The rule "document behavioral changes in same commit" (feedback_always-document-behavioral-changes.md) already exists but was not followed. Cleanup cost: a full follow-up session (read 2 scripts, 3 doc edits, reconcile run). Enforcement gap: `/brana:close` does not grep the session's commit range for `system/hooks/*.sh` additions without a corresponding `docs/architecture/hooks.md` change. t-1490 tracks adding this grep gate to `/brana:close` Step 3b or Step 8.
Source: close session 2026-05-19

### 2026-05-28: Advisory hooks need an escalation task filed at ship time
`branch-name-warn.sh` shipped as advisory (`continue:true`) with a comment "escalate to hard-block after migration" — but no escalation task was filed. Without a task, the advisory phase silently becomes permanent. Rule: when shipping any advisory hook, file an escalation task in the same commit or immediately after (t-1718 was filed post-hoc at session close). Link the task ID in the hook header comment so the escalation condition is visible at the source.
Source: t-1620 / close session 2026-05-28

### 2026-05-28: Hook advisory→hard-block requires TWO sync points — shell and hooks.json
Escalating a PreToolUse hook from advisory to blocking requires changes in two places: (1) the shell script's output (`continue:false` instead of `continue:true`), and (2) `hooks.json`'s `continueOnBlock:true` field (must be removed). Both must be in sync. Updating only the shell script leaves `continueOnBlock:true` in hooks.json, which CC interprets as "keep running even if blocked" — effectively undoing the escalation. Also: `brana reference generate` must be run after any `docs/architecture/hooks.md` edit to keep `docs/reference/hooks.md` in sync (validate.sh Check 29).
Source: t-1718 / close session 2026-05-28

### 2026-05-30: Model version strings in hook warnings need periodic refresh (t-1711)
`preflight-model.sh` and `session-start.sh` embed the model name in their extra-usage warning ("Run /model to switch to standard Opus X.Y or Sonnet X.Y"). When Anthropic retires or renames a model, these strings go stale and direct users to a non-existent model. t-1711 caught Opus 4.6 → Opus 4.7 several sessions after the fact. Rule: when a Claude model family is deprecated or a new family ships, grep `system/hooks/` for hardcoded model names and update in the same patch that updates other model references.
Source: t-1711 / close session 2026-05-30

### 2026-06-03: `git status --porcelain` collapses new directories — use `-uall` for file-level hook scanning
Any hook that enumerates untracked files from `git status --porcelain` must add `-uall`. Without it, a brand-new untracked directory (one that has never been tracked) is folded into a single `?? parent/` token — individual files inside are invisible. `branch-verify.sh` had this bug: a behavioral file in a new directory could slip past the `git add` guard on main. Fix: `git status --porcelain -uall` ensures each untracked file is listed individually regardless of directory ancestry. (E2026-06-03-10)
Source: branch-verify.sh Tests 9/10 / close session 2026-06-03

### 2026-06-03: Hooks must live exclusively in plugin's hooks.json — never duplicate in settings.json
`~/.claude/settings.json` supports a `hooks` section, but it does NOT expand `${CLAUDE_PLUGIN_ROOT}`. That variable is only available in hooks defined inside a plugin's `hooks/hooks.json`. When the `brana@brana` plugin was disabled at some point, its hooks were copy-pasted into `settings.json` carrying the plugin-only variable — causing "Hook command references ${CLAUDE_PLUGIN_ROOT} but the hook is not associated with a plugin" errors after Claude Code added enforcement. Fix: re-enable the plugin, remove the `hooks` key from `settings.json`, run `./bootstrap.sh --sync-plugin` to push any diverged scripts to the plugin cache. The two are mutually exclusive: plugin enabled → hooks.json; plugin disabled → settings.json with absolute paths.
Source: E2026-06-03-9 / close session 2026-06-03
