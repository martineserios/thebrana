---
name: reconcile
description: "Unified maintenance — detect drift, run security checks, cascade spec propagation, knowledge hygiene. Scoped via --scope flag. Default: consistency."
effort: high
model: sonnet
keywords: [drift, specs, implementation, sync, mismatch, system, security, audit, propagation, maintain, knowledge]
task_strategies: [refactor, investigation]
stream_affinity: [tech-debt, docs]
argument-hint: "[--scope consistency|security|propagation|knowledge|all]"
group: brana
allowed-tools:
  - AskUserQuestion
  - Bash
  - Edit
  - EnterPlanMode
  - ExitPlanMode
  - Glob
  - Grep
  - Read
  - Skill
  - Task
  - TaskList
  - Write
  - mcp__ruflo__memory_search
  - mcp__ruflo__memory_delete
  - mcp__ruflo__memory_store
  - ToolSearch
status: stable
growth_stage: evergreen
---

# Reconcile

Unified maintenance command for the brana system. Four domains, one entry point.

| Domain | Scope flag | What it checks |
|--------|-----------|---------------|
| **Consistency** | `--scope consistency` | Spec docs vs `system/` implementation drift (default) |
| **Security** | `--scope security` | Secrets, permissions, MCP tax, dangerous settings, credential files, acquired skill safety |
| **Propagation** | `--scope propagation` | Doc fitness checks, reflection gaps, spec-graph consistency |
| **Knowledge** | `--scope knowledge` | Stale dimensions, event log bloat, ruflo noise (DECAY) |

`--scope all` runs every domain sequentially.

**Replaces:** `/brana:audit` (merged into security domain).

## Usage

```
/brana:reconcile                          — consistency (default, backward compatible)
/brana:reconcile --scope security         — security checks only
/brana:reconcile --scope propagation      — spec cascade + graph checks
/brana:reconcile --scope knowledge        — knowledge hygiene (DECAY)
/brana:reconcile --scope all              — run all domains
```

Parse `--scope` from `$ARGUMENTS`. If no `--scope` flag is present, default to `consistency`.

## Phase Protocol — how to execute this skill

The domain procedures live in per-phase files under `phases/` (this skill's base directory). **Never execute a scope from memory.** Three rules:

1. **On invocation:** resolve the scope from `$ARGUMENTS`, then Read its phase file from the PHASES registry below BEFORE doing any of its work. A phase you have not Read this session does not exist — do not improvise its steps.
2. **`--scope all`:** Read each domain's phase file as that domain begins — consistency → security → propagation → knowledge, one Read per boundary, not all upfront.
3. **On resume after compression:** identify the active scope and step (CC TaskList `/brana:reconcile — {STEP}` entries), then Read that scope's phase file before continuing. Previously loaded phase content did NOT survive compression.

<!-- PHASES -->
| Scope | File | Load when |
|------|------|-----------|
| consistency (default) | phases/consistency.md | Scope resolves to consistency, or its turn in `--scope all` |
| security | phases/security.md | Scope resolves to security, or its turn in `--scope all` |
| propagation | phases/propagation.md | Scope resolves to propagation, or its turn in `--scope all` |
| knowledge (DECAY) | phases/knowledge.md | Scope resolves to knowledge, or its turn in `--scope all` |
<!-- /PHASES -->

In the deployed-plugin layout the same relative paths apply: `{base-dir}/phases/{file}`. If a path doesn't resolve, use Glob: `**/skills/reconcile/phases/{file}`.

## When to use

- **consistency** — After manually editing specs, after implementation changes, periodically, or before a new `/build-phase`
- **security** — Before sharing config, after adding MCP servers, after installing acquired skills, or monthly
- **propagation** — After dimension doc edits, when errata accumulate, or as part of a full maintenance cycle
- **knowledge** — After bulk indexing, when ruflo memory is suspected stale, weekly as DECAY hygiene pass
- **all** — Full system health check

## Architecture

After the enter→thebrana merge (ADR-006), specs and implementation coexist in one repo:

```
thebrana/
├── docs/                      ← roadmap specs (00, 15, 17-19, 24, 25, 30, 39)
│   └── reflections/           ← reflection specs (08, 14, 29, 31, 32)
├── system/                    ← implementation (skills, hooks, rules, agents, config)
├── .claude/CLAUDE.md          ← identity + conventions
└── deploy.sh                  ← deployment

brana-knowledge/dimensions/    ← dimension docs (knowledge, cross-repo)
```

Most reconcile work is **intra-repo** (docs/ → system/). Dimension docs in brana-knowledge provide additional spec surface but rarely contain implementation-specific claims.

## Step Registry

On entry, create a CC Task step registry. Follow the [guided-execution protocol](../_shared/guided-execution.md).

Register steps based on scope:

- **consistency:** ORIENT, ROUTE, SCAN-SPECS, SCAN-IMPL, DIFF, PRESENT, APPLY, LOG, REPORT
- **security:** ORIENT, ROUTE, SEC-SCAN, SEC-REPORT
- **propagation:** ORIENT, ROUTE, PROP-SCAN, PROP-APPLY, PROP-REPORT
- **knowledge:** ORIENT, ROUTE, KNOW-1, KNOW-2, KNOW-3, KNOW-REPORT
- **all:** ORIENT, ROUTE, then all domain steps sequentially

**Plan mode:** Enter plan mode for scanning steps (SCAN-SPECS, SCAN-IMPL, DIFF, SEC-SCAN, PROP-SCAN). Exit plan mode before presenting results.

<!-- ruflo preamble -->
ToolSearch("select:mcp__ruflo__memory_search,mcp__ruflo__memory_store,mcp__ruflo__memory_delete")

## Rules

- **Read before writing.** Always read a file before editing it. Never assume file contents from spec descriptions alone.
- **Materiality filter is strict.** Only surface drift that would cause wrong behavior or wrong implementation decisions. Cosmetic differences are not drift.
- **Never auto-create new capabilities.** Reconcile fixes existing files. New skills, hooks, or agents require `/build-phase` or explicit user instruction.
- **Never auto-delete.** "Extra" items that specs don't mention get flagged for review, not removed. The user decides.
- **One branch, atomic commits.** All reconcile work happens on a single worktree branch with one commit per logical fix.
- **Plan then apply.** Always show the full drift report and get approval before making any changes.
- **Ask for clarification whenever you need it.** If a spec claim is ambiguous, a drift finding is borderline, or the right fix is unclear — ask. Don't guess.
- **Step registry.** Follow the [guided-execution protocol](../_shared/guided-execution.md). Register steps on entry, update as each completes. **Auto-advance through all non-interactive steps** (ORIENT → SCAN-SPECS → SCAN-IMPL → DIFF without pause). Only pause at steps marked [INTERACTIVE] or final REPORT.
- **Phase files are the procedure.** Read the registered scope's phase file before running it (Phase Protocol above). Never run a scope from this overview alone.

---

## Resume After Compression

If context was compressed and you've lost track of progress:

1. Call `TaskList` — find CC Tasks matching `/brana:reconcile — {STEP}`
2. The `in_progress` task is your current step — resume from there
3. **Read the active scope's phase file** (PHASES registry above) before executing anything — phase content loaded before compression is gone
4. Check the worktree branch for commits already applied

---

## Field Notes

> Routing: always append field notes to `docs/architecture/<topic>.md`, never `docs/reference/` (auto-generated — see `system/rules/field-note-routing.md`).

### 2026-04-09: Verify before wiring — check call chains first
When DIFF flags a script as "exists but not in hooks.json", grep sibling hook scripts before adding a hooks.json entry: `grep -r "script-name.sh" system/hooks/`. A script absent from hooks.json may already be called internally (e.g., config-drift.sh is called by session-start.sh line 157). Absence from hooks.json is necessary-but-not-sufficient evidence of a real gap.
Source: /brana:reconcile --scope consistency, 2026-04-09

### 2026-04-09: Exclude docs/archive from scan scope
Scan agents must exclude `docs/archive/**` and `docs/reflections/archive/**`. Stale archived content produces false positives — the archive copy of doc 14 said "13 rules" while the live doc already had "14 rules". Always include the full file path in findings so archive hits are obvious before fixes are applied.
Source: /brana:reconcile --scope consistency, 2026-04-09

### 2026-06-03: `brana graph build` must run from main repo root — not a git worktree
Running `brana graph build` from inside a worktree (e.g., `thebrana-chore/reconcile-YYYYMMDD/`) resolves `brana-knowledge/` relative to the worktree path, silently losing all 158+ dimension nodes. Always run `brana graph build` from the main repo checkout (`~/enter_thebrana/thebrana/`). PROP-2 step now explicitly documents this. t-1835 tracks adding a worktree-detection guard to the CLI.
Source: /brana:reconcile --scope propagation, 2026-06-03

### 2026-06-03: Errata same-day numbering can collide across concurrent sessions
Multiple sessions closing on the same day independently assign E{date}-N starting from 1, producing duplicate IDs across client repos or parallel thebrana sessions. The Step 4 pre-write dedup check in close.md already documents querying `git show HEAD:errata-doc` for LAST_N — but this only works within one repo. Cross-repo errata written to the same file on the same day must also check the index table at the top of docs/24-roadmap-corrections.md, not just the latest commit.
Source: /brana:reconcile --scope propagation merge conflict resolution, 2026-06-03
