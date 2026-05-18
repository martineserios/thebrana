# Testing and Validation

> How to validate the brana system before deploying changes. Covers `validate.sh` checks, hook testing, and skill testing in dev mode.

## validate.sh

The primary pre-deploy validation tool. Run it from the repo root:

```bash
./validate.sh
```

It exits 0 on success, 1 if any check fails. Warnings do not cause failure.

### Check 1: Skill Frontmatter

For each `system/skills/*/SKILL.md` (excluding `acquired/`):

- File exists in the skill directory
- Has valid YAML frontmatter (between `---` markers)
- YAML parses without errors
- `name` field matches the directory name

**Common failures:**
- Renamed directory but forgot to update `name:` in frontmatter
- Invalid YAML syntax (missing quotes around descriptions with colons)

### Check 2: Rule Files

For each `system/rules/*.md`:

- If it has YAML frontmatter, the YAML is valid
- Rules without frontmatter are valid (they load unconditionally)

### Check 3: JSON Validity

- `system/settings.json` (if present) is valid JSON
- Since v1.0.0, `settings.json` is optional in the plugin (PostToolUse hooks live in `bootstrap.sh`)

### Check 4: Agent Frontmatter

For each `system/agents/*.md`:

- Has valid YAML frontmatter
- Has a `name` field
- Has a `description` field

### Check 5: Context Budget

Calculates the total always-loaded content size:

- `system/CLAUDE.md` (full file)
- Rules without `paths:` field (loaded unconditionally)
- Skill descriptions (just the `description:` line from each skill)
- Agent descriptions (from frontmatter)

**Budget limit:** 28,672 bytes (28KB). Exceeding this degrades Claude's performance because too much instruction text competes for context window space.

### Check 5b: Instruction Density

Counts the number of always-present directives (lines starting with `- **`, numbered lists with bold, table rows, imperative sentences).

- **Warning threshold:** 200 directives
- **Failure threshold:** 300 directives

Too many directives means Claude cannot follow all of them reliably. Prefer fewer, stronger rules.

### Check 6: No Secrets

Scans `system/` for patterns like `API_KEY=`, `SECRET=`, `PASSWORD=`, `TOKEN=`, `PRIVATE_KEY=`. Excludes comments, examples, and placeholder text.

### Check 7: Duplicate Skill Names

Ensures no two skills share the same `name:` field. Duplicate names would cause one skill to shadow the other.

### Check 8: File Size Sanity

Flags any file in `system/` over 50KB. Large files indicate content that should be split or externalized.

### Check 8b: Propose-First Convention

Scans all `system/procedures/*.md` for `AskUserQuestion` calls and verifies the propose-first rule:

- Every procedure file that contains `AskUserQuestion` must also contain at least one `(Recommended)` label on an option
- **Pass:** all procedures with AskUserQuestion calls have a `(Recommended)` option
- **Warn:** lists procedure filenames that have `AskUserQuestion` but no `(Recommended)` anywhere in the file
- Skip if no `system/procedures/` directory

**Common failures:** adding a new `AskUserQuestion` block without marking the default option `(Recommended)`.

### Check 9: Hook Scripts

For each `system/hooks/*.sh`:

- File is not empty
- Has a valid shebang (`#!/usr/bin/env bash` or `#!/bin/bash`)
- Passes `bash -n` syntax check (no parse errors)

For `system/hooks/hooks.json`:

- Valid JSON
- All event names are known CC events (`PreToolUse`, `PostToolUse`, `SessionStart`, etc.)
- Warns if `PostToolUse` or `PostToolUseFailure` appear (CC #24529 means these don't fire from plugins)
- Commands use `${CLAUDE_PLUGIN_ROOT}` (not relative paths)
- Referenced scripts exist and are executable

For `system/settings.json` (if present):

- Hook event names are valid
- Warns that settings.json hooks should be empty in v0.7.0+ (use hooks.json or bootstrap)

### Check 9b: Hook Shared Libs

Validates `system/hooks/lib/` (the shared library directory for hook scripts):

- Each `hooks/lib/*.sh` passes `bash -n` syntax check
- Source contract for `git-helpers.sh`: any hook that calls `resolve_lookup_dir` or `extract_git_c_dir` must `source` `git-helpers.sh`
- Source contract for `layer1-paths.sh`: any hook that calls `is_layer1_file` must `source` `layer1-paths.sh`
- Skip if no `system/hooks/lib/` directory (the shared lib is optional — older deployments may not have it)

**Common failures:** adding a new helper function to `hooks/lib/` and forgetting to `source` it from the hooks that use it.

### Check 10: Commands

For each file in `system/commands/`:

- Markdown files: valid YAML frontmatter
- Shell scripts: valid shebang and `bash -n` syntax check

### Check 11: Shared Scripts

For each `system/scripts/*.sh`:

- Valid shebang
- Passes `bash -n` syntax check

### Check 12: Skill Dependencies

For each skill with a `depends_on` field:

- Every listed dependency has a corresponding `system/skills/{dep}/` directory
- Catches typos and references to deleted skills

### Check 13: Count Drift

Scans `docs/reflections/*.md` and all `docs/architecture/**/*.md` (excluding `decisions/`):

- Counts actual items in `system/`: skills (excluding `acquired/`), rules (excluding `README.md`), agents, validate checks, hooks (`.sh` files)
- Three match patterns: (1) parenthesized `(N skills,`, (2) verb-prefixed `has N hooks`, (3) plain list `N skills, N agents.`
- **Warn** when a doc count differs from actual and is close enough to be a stale total:
  - `hooks`: 80% threshold — hooks grew from 10 to 35; stale totals can be far from actual
  - All others: 30% threshold
- Shows `skills=N, rules=N, agents=N, checks=N, hooks=N` in warning output

**Common failures:**
- Adding a skill/rule/agent/hook without updating architecture docs that mention the total
- Fix: remove hardcoded counts and link to the auto-generated reference, or write "all hooks" instead of "10 hooks"

### Check 14: Spec-Graph Coverage

Requires `docs/spec-graph.json`.

- Collects all `*.md`, `*.sh`, `*.json`, `*.py` files under `system/`
- Checks each against the `impl_files` arrays in all spec-graph nodes
- **Warn** for each undocumented file (up to 5 listed; `…and N more` for the rest)
- Skipped silently if `spec-graph.json` is absent

### Checks 15–18: Knowledge Architecture

Run in the full suite. Skipped only by `--scale-triggers`. Use `--assumptions-only` to run Check 15 in isolation.

```bash
./validate.sh --assumptions-only   # run only assumption freshness (Check 15)
./validate.sh                      # full run includes 15-18
```

### Check 15: Assumption Freshness

Scans `docs/**/*.md` and `brana-knowledge/dimensions/*.md` for `## Assumptions` sections with `last_verified` dates.

- Three tiers (per-row `Tier` column overrides doc-level `confidence_tier` frontmatter when present):
  | Tier | Max age |
  |------|---------|
  | `tech` (default) | 6 months |
  | `architecture` | 18 months |
  | `methodology` | 36 months |
- **Warn** when a verified date exceeds the tier threshold
- **Grace period**: docs modified within `--grace-days` (default 7 days) are skipped entirely

### Check 16: Changelog Currency

For docs that have a `## Changelog` section:

- Compares the doc's last git commit date against the most recent date in the changelog
- **Warn** if the doc was committed more than 24 hours after the latest changelog entry
- Skipped for docs modified within the grace period

### Check 17: Status Consistency

For docs with `status: active` in YAML frontmatter:

- Gets the last git modification date
- **Warn** if no changes in 12+ months — suggests updating to `status: historic`

### Check 18: Graph Integrity

Requires `docs/spec-graph.json`. Two sub-checks:

- **Orphaned edges**: each `typed_edges` `from`/`to` must reference a node that exists in the graph
- **Unresolvable assumptions**: assumption slugs in `typed_edges` (prefixed `assumption:`) must fuzzy-match a `## Assumptions` row in at least one doc (≥50% term overlap)
- Both are **Warn** (not Fail)
- Skipped if `spec-graph.json` not found

### Checks 19–22: Scale Triggers

Scale triggers fire when usage crosses a threshold that activates a deferred task. Use `--scale-triggers` to run only these.

```bash
./validate.sh --scale-triggers   # run scale triggers + Checks 23-26
./validate.sh                    # full run includes scale triggers
```

### Check 19: Graph Node Count

- Counts nodes in `spec-graph.json`
- **Warn** if `> 500` nodes — signals to evaluate AgentDB Cypher activation (see t-435)
- Skipped if `spec-graph.json` not found

### Check 20: Ruflo Entry Count

- Queries `~/.claude-flow/memory.db` for total entry count
- **Warn** if `> 10,000` entries — signals to consider knowledge pipeline temperature tiering
- Skipped if ruflo DB or `sqlite3` unavailable

### Check 21: Typed Edges Per Node

- Finds the spec-graph node with the most typed edge connections
- **Warn** if max `> 10` — signals to consider GraphRAG for dense subgraphs (see t-105)
- Reports the hotspot node name and edge count

### Check 22: Cross-Client Field Note Count

- Counts `## Field Notes` bullet items across `docs/`, `brana-knowledge/dimensions/`, and `clients/*/docs`
- **Warn** if total `> 50` — signals to consider witness chains for field note provenance (see t-436)

### Checks 23–24: Contract Enforcement

Always run regardless of flags (`--assumptions-only`, `--scale-triggers`, `--semantic` do not skip them).

### Check 23: Skill Routing Contract

Three sub-checks verifying the JIT skill acquisition flow is correctly wired. All are **Fail** (not Warn).

- **23a**: `system/procedures/backlog.md` contains "MANDATORY acquisition offer" in step 5d
- **23b**: `system/procedures/backlog.md` writes a `skill_gap_checked` breadcrumb to task context
- **23c**: `system/procedures/build.md` step 4a reads `skill_gap_checked` as a safety net when backlog step 5 is skipped

### Check 24: `.mcp.json` Entries

For each server in `.mcp.json`:

- **Fail** if `command` uses `npx` or `uvx` — ephemeral binaries break across environments
- All MCP servers must use pinned wrapper scripts per ADR-033
- **Warn** if `.mcp.json` is not found at the repo root

### Check 25: tasks.json Priority Enum Hygiene

Reads `.claude/tasks.json` and fails if any task has a `priority` value outside the canonical enum.

- **PASS:** every task has `priority` in `{P0, P1, P2, P3, null}`
- **FAIL:** legacy values (`high`, `medium`, `low`) or arbitrary strings detected — surfaces both bad values and offending task IDs

Pairs with `validate_priority` in `brana_core::tasks` (wired into `set_field`, `cmd_add`, MCP `backlog_add`). The check catches drift from manual JSON edits or pre-validation legacy data.

### Check 26: tasks.json Status Enum Hygiene

Reads `.claude/tasks.json` and fails if any task has a `status` value outside the canonical raw enum.

- **PASS:** every task has `status` in `{pending, in_progress, completed, cancelled, null}`
- **FAIL:** synthetic display values (`done`, `active`, `blocked`, `parked`) or arbitrary strings detected — surfaces both bad values and offending IDs

Pairs with `validate_status` in `brana_core::tasks`. Synthetic values come from `classify()` output and should never reach the raw `status` field. See also `raw_status()` accessor — the canonical reader for filter predicates and aggregations.

### Checks A-D: Semantic Skill Validation

Beyond structural checks (1-12), `validate.sh` includes semantic checks that analyze skill *content* for consistency. Run them standalone with `--semantic` or as part of the full suite.

```bash
./validate.sh --semantic    # run only semantic checks
./validate.sh               # full run includes semantic checks
```

#### Check A: Allowed-Tools Consistency

Compares tool references in the skill body against the `allowed-tools:` frontmatter list.

- **FAIL:** Tool referenced in body (backtick-wrapped, label pattern, or function-call pattern) but missing from `allowed-tools`
- **WARN:** Tool listed in `allowed-tools` but never referenced in body (dead permission)

Detection uses strict patterns to avoid false positives: `` `ToolName` ``, `ToolName:`, `ToolName(`, `"ToolName"`. Bare prose mentions (e.g., "Read the docs") are not matched.

#### Check B: File Path References

Resolves markdown link paths (`[text](path)`) relative to the skill directory.

- **FAIL:** Referenced file does not exist

Filters applied:
- Code blocks (` ``` `) are stripped to avoid matching placeholder paths in examples
- Known placeholder paths (`path`, `path.md`, `url`, `relative-path.md`) are skipped
- Cross-repo paths (`../../`) are resolved via the workspace root

#### Check C: Frontmatter Schema Validation

Enforces required fields and valid enum values.

**Required fields:** `name`, `description`, `group`, `allowed-tools`, `status`

**Valid enums:**

| Field | Valid values |
|-------|-------------|
| `status` | stable, experimental, seed, deprecated |
| `growth_stage` | evergreen, prototype, seed |
| `group` | execution, session, learning, business, integration, content, brana, utility, thinking, venture, core, domain, capture, tools |

#### Check D: Step Registry Consistency

For skills referencing the [guided-execution protocol](../../system/skills/_shared/guided-execution.md):

- Extracts registered step names from the "Register these steps:" line
- Checks each step name appears (case-insensitive substring) in at least one section header
- **WARN:** Registered step with no matching section header

Only checks the registered→section direction. Unregistered sections are not flagged (too noisy — many skills have supplementary sections).

### Test Suite

Semantic checks have their own fixture-based test suite:

```bash
./test-semantic-checks.sh    # 20 tests using 7 fixture skills
./test.sh semantic           # run via test runner
```

The test suite creates temporary skills with known issues and verifies each check detects them correctly.

## Pre-Deploy Validation Workflow

Before committing changes to the system:

```bash
# 1. Run validation
./validate.sh

# 2. Fix any errors (warnings are informational)

# 3. Test in dev mode
claude --plugin-dir ./system

# 4. Verify your changes work in a live session

# 5. Commit and push
```

For hook changes, add local testing (next section) between steps 1 and 3.

## Testing Hooks Locally

Hooks can be tested without starting a Claude Code session by piping JSON to them:

### PreToolUse Hook

```bash
# Should block (feat branch, no spec activity, implementation file)
echo '{
  "session_id": "test-1",
  "tool_name": "Write",
  "tool_input": {"file_path": "/home/user/project/src/main.py"},
  "cwd": "/home/user/project"
}' | bash system/hooks/pre-tool-use.sh

# Should pass (writing a test file)
echo '{
  "session_id": "test-1",
  "tool_name": "Write",
  "tool_input": {"file_path": "/home/user/project/tests/test_main.py"},
  "cwd": "/home/user/project"
}' | bash system/hooks/pre-tool-use.sh
```

### PostToolUse Hook

```bash
echo '{
  "session_id": "test-1",
  "tool_name": "Write",
  "tool_input": {"file_path": "/tmp/test.py"},
  "cwd": "/tmp"
}' | bash system/hooks/post-tool-use.sh
```

### SessionStart Hook

```bash
echo '{
  "session_id": "test-1",
  "cwd": "/home/user/project",
  "hook_event_name": "SessionStart"
}' | bash system/hooks/session-start.sh
```

### Validation Checklist for Hook Testing

1. **Valid JSON output** — pipe output through `jq .` to verify
2. **Graceful on empty input** — `echo '' | bash hook.sh` should return `{"continue": true}`
3. **Graceful on missing fields** — `echo '{}' | bash hook.sh` should return `{"continue": true}`
4. **Stays under timeout** — `time bash hook.sh < input.json` should complete in under 5s (tool hooks) or 10s (session hooks)
5. **No stderr noise** — redirect stderr to check: `bash hook.sh < input.json 2>/tmp/hook-errors`

## Testing Skills in Dev Mode

Skills cannot be tested outside Claude Code. Use dev mode:

```bash
claude --plugin-dir ./system
```

In the session:

1. Invoke the skill: `/brana:my-skill`
2. Verify it follows the instructions in SKILL.md
3. Check that only `allowed-tools` are used (Claude will refuse others)
4. Test edge cases: missing files, empty input, error conditions

Changes to SKILL.md require restarting Claude Code. Edit, restart, test.

### Quick Iteration Loop

```bash
# Terminal 1: Edit the skill
vim system/skills/my-skill/SKILL.md

# Terminal 2: Restart Claude Code and test
claude --plugin-dir ./system
# > /brana:my-skill
```

## Checking Session Logs

After testing hooks in a live session, check the session JSONL file for logged events:

```bash
# Find the session log
ls -la /tmp/brana-session-*.jsonl

# Read events
cat /tmp/brana-session-*.jsonl | jq .
```

This file is created by `post-tool-use.sh` and consumed by `session-end.sh` to compute flywheel metrics.

## Field Notes

### 2026-03-30: Fixture-based test design scales for bash validation
Create temporary fixture objects (skills, hooks, etc.) with known issues in a test script. 7 fixtures with 20 tests caught all Check A-D edge cases before live deployment. Pattern: temp dir per run, one fixture per failure mode, assert on FAIL/WARN/PASS output strings.
Source: t-747/748/749/750

### 2026-03-30: Strict tool name matching avoids prose false positives
Tool names like `Read`, `Write`, `Edit` are common English words. Only match backtick-wrapped (`` `Read` ``), colon-suffixed (`Read:`), paren-suffixed (`Read(`), or quoted (`"Read"`) patterns. Never bare word boundaries.
Source: t-747 (Check A implementation)

### 2026-03-30: Cross-repo relative paths need precise level counting
From `system/skills/X/` to workspace root is 4 levels up (`../../../../`). Common mistake: off by 1-2 levels. Always verify by resolving from the source file's actual directory, not from repo root.
Source: t-751 (harvest fix)

### 2026-04-08: Extract `_from(path)` variant from global-state helpers for testability
A Rust helper that calls `env::current_dir()` or similar global state is untestable without chdir tricks. Pattern: extract `find_tasks_file_from(start_dir: &Path)` as the real implementation; keep `find_tasks_file()` as a thin wrapper calling `_from(current_dir?)`. Unit tests target `_from` with fixture directories — enables 9 tests where 0 were previously possible. Applied in `brana-core/util.rs` (t-1088).
Source: t-1088

### 2026-04-13: Allowlist the target set, don't denylist known-large paths
The `find -size +50k` check over all of `system/` produced false positives on Rust build artifacts (`cli/rust/target/`), runtime state (`state/`), and procedure files (`procedures/`). Each required a new exclusion clause. The durable fix is to scan only the set that should be small: `system/skills/`, `system/hooks/`, `system/agents/`, `system/rules/`, `system/commands/`. Allowlisting the target is stable; denylisting known-large paths grows indefinitely.
Source: t-1183, 2026-04-13

### 2026-05-18: Count-drift plain-list pattern (Pattern 3) requires lookahead over all terminal punctuation
`(?=[,\.])` missed "N agents)" where `)` follows — causing false negatives in plain-list format "11 skills, 11 agents, 10 hooks.". Fix: `(?=[,\.\)])` — enumerate every terminal char (comma, period, close-paren). The same completeness rule applies to any lookahead anchoring a plain-list pattern.
Source: t-1443, 2026-05-18

### 2026-05-18: `%seen` Perl hash prevents duplicate warnings in multi-pattern extraction
When multiple Perl `while (/pattern/g)` loops can match the same line (e.g., Pattern 1 and Pattern 3 both match `(24 skills,`), each loop independently emits a match. Fix: derive a dedup key `"$.:$num:$component"` and gate every print with `unless $seen{$k}++`. The hash lives in Perl's package scope — one declaration covers all loops in the same invocation.
Source: t-1443, 2026-05-18

### 2026-05-18: Per-component threshold in count-drift detection
A single 30% threshold suppresses stale counts when a component grows rapidly. Hooks grew from 10 to 35 — a 30% threshold would let "10 hooks" (diff=25 vs threshold=10) pass silently. Fix: per-component thresholds — 80% for hooks (high-growth), 30% for skills/rules/agents/checks (stable). Add per-component cases whenever a new high-growth component joins the scanned set.
Source: t-1443, 2026-05-18
