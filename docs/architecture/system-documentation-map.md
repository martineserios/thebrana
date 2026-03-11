# System Documentation Map

> Enforcement layer reference — what enforces what, what lives where.

## System Layers

Brana operates as two deployment layers plus a knowledge repo:

```
thebrana/system/                      PLUGIN (loaded by Claude Code)
├── .claude-plugin/plugin.json        manifest
├── skills/                           /brana:* slash commands
├── commands/                         agent commands
├── hooks/hooks.json + *.sh           event hooks (10 scripts)
├── agents/                           specialized agents (11)
├── rules/                            behavioral rules (12)
├── scripts/                          shared helpers
├── scheduler/                        scheduled jobs
├── statusline.sh                     status bar
└── CLAUDE.md                         mastermind identity

bootstrap.sh                          IDENTITY LAYER → ~/.claude/
├── CLAUDE.md                         global identity (synced from system/)
├── rules/                            behavioral rules (synced from system/)
├── scripts/                          helper scripts
├── statusline.sh                     status bar
└── scheduler/                        scheduled jobs

brana-knowledge/dimensions/           KNOWLEDGE REPO (separate)
├── 01-38 + topic docs                research dimensions
└── research-sources.yaml             tracked external sources
```

**Plugin** = toolkit. Loaded by Claude Code natively via `claude --plugin-dir ./system` or marketplace install. Contains skills, hooks, agents, commands.

**Identity layer** = personality. Deployed once via `./bootstrap.sh`. Syncs CLAUDE.md, rules, and scripts to `~/.claude/`. Idempotent, safe to re-run.

**Knowledge repo** = research base. Indexed into claude-flow memory (315+ sections, 384-dim ONNX embeddings). Separate repo at `~/enter_thebrana/brana-knowledge/`.

## Enforcement Mechanisms

### Hook-Based Enforcement

Hooks fire on Claude Code lifecycle events. Three are registered in the plugin `hooks.json`; the rest run via `settings.json` (installed by bootstrap.sh, because CC v2.1.x doesn't dispatch PostToolUse from plugins).

| Hook | Event | Trigger | Enforces | Action |
|------|-------|---------|----------|--------|
| `pre-tool-use.sh` | PreToolUse | Write\|Edit | **Spec-first gate** | DENY if: project has `docs/decisions/`, branch is `feat/*`, no spec/test activity on branch yet. Always allows docs/test/spec files. |
| `post-tool-use.sh` | PostToolUse | Write\|Edit\|Bash | Correction tracking | Detects corrections (re-edits), test-file writes, test/lint passes, PR creates. Clears cascade flags on success. |
| `post-tool-use-failure.sh` | PostToolUseFailure | Write\|Edit\|Bash | **Cascade detection** | After 3+ consecutive failures on same target, writes flag file. `pre-tool-use.sh` reads flag and injects "stop and reassess" nudge. |
| `post-tasks-validate.sh` | PostToolUse | Write\|Edit on `*/tasks.json` | Task schema | Validates JSON, checks required fields, auto-rollup of parent task status. |
| `post-plan-challenge.sh` | PostToolUse | ExitPlanMode | Plan review | Nudges challenger agent for adversarial review after plan finalization. |
| `post-pr-review.sh` | PostToolUse | Bash (`gh pr create`) | PR review | Nudges pr-reviewer agent for automated code review. |
| `post-sale.sh` | PostToolUse | Write\|Edit on pipeline files | Deal tracking | Detects deal closures, snapshots to memory. |
| `session-start.sh` | SessionStart | Every session | Context injection | Recalls patterns from claude-flow, injects task context, detects venture projects, checks for pending learnings. |
| `session-end.sh` | SessionEnd | Every session | Metrics persistence | Computes flywheel metrics, stores session summary to claude-flow and auto memory. Responds instantly, forks heavy work to background. |

### Plugin hooks.json vs settings.json

Only three events work from plugin `hooks.json` (CC v2.1.x limitation):
- **PreToolUse** — `pre-tool-use.sh`
- **SessionStart** — `session-start.sh`
- **SessionEnd** — `session-end.sh`

All PostToolUse/PostToolUseFailure hooks must be installed via `bootstrap.sh` into `~/.claude/settings.json` with absolute paths.

### Rule-Based Enforcement

Rules are always-loaded markdown directives in `system/rules/`. They shape behavior but don't block tool calls — only hooks can deny.

| Rule | What it enforces |
|------|-----------------|
| `sdd-tdd.md` | Test-first: write the test before implementation. Bug fix = failing test first. Enhanced on `feat/*` with `docs/decisions/`. |
| `git-discipline.md` | Every change on a branch. Worktrees over checkout. `--no-ff` merges. Conventional commits. |
| `task-convention.md` | Read `tasks.json` before branching. Branch naming from stream. Status lifecycle. |
| `context-budget.md` | Thresholds: <55% normal, 55-70% yellow, 70-85% compact, >85% delegate. Expensive-op awareness. |
| `delegation-routing.md` | Auto-delegate to agents when triggers match. Invoke skills directly when applicable. |
| `memory-framework.md` | CLAUDE.md = human rules, MEMORY.md = Claude facts. Reference, don't cache. 200-line cap. |
| `universal-quality.md` | Test before commit. No secrets. Error handling. Type safety. |
| `work-preferences.md` | Parallelism, subagent strategy, plan before building, simplicity. |
| `self-improvement.md` | Capture corrections immediately. Read MEMORY.md on start. Write learnings on end. |
| `research-discipline.md` | Project docs first, then external. Never parallel. |
| `doc-linking.md` | `[doc NN](relative-path.md)` format. Relative paths from source file. |
| `pm-awareness.md` | Check issues before work. Link commits. Update progress. |

### Validation Script

`validate.sh` runs 12 pre-deploy checks:

| Check | What it validates |
|-------|------------------|
| 1. Skill frontmatter | YAML valid, `name` matches directory |
| 2. Rule files | Valid frontmatter if present |
| 3. JSON validity | `settings.json` |
| 4. Agent frontmatter | Has `name` and `description` fields |
| 5. Context budget | Always-loaded content < 28KB |
| 5b. Instruction density | Directive count < 200 warn, < 300 fail |
| 6. Secrets | No API keys, passwords, tokens in `system/` |
| 7. Duplicate skills | No two skills share a name |
| 8. File sizes | No file over 50KB |
| 9. Hook scripts | Valid shebang, no syntax errors, valid event names, `${CLAUDE_PLUGIN_ROOT}` usage |
| 10. Commands | Valid frontmatter or shebang |
| 11. Shared scripts | Valid shebang, no syntax errors |
| 12. Skill dependencies | `depends_on` references resolve to existing skills |

## Document Architecture

### Three Document Types

| Type | Location | Nature | Example |
|------|----------|--------|---------|
| **Dimension** | `brana-knowledge/dimensions/` | Research/knowledge — deep dives on a topic | `22-testing.md`, `27-project-alignment-methodology.md` |
| **Reflection** | `thebrana/docs/reflections/` | Cross-cutting synthesis — connects multiple dimensions | `14-mastermind-architecture.md`, `31-assurance.md` |
| **Roadmap** | `thebrana/docs/` | Implementation plans — what to build and when | `18-lean-roadmap.md`, `30-backlog.md` |

### Propagation Direction

```
Dimension (knowledge)
    ↓  /brana:maintain-specs
Reflection (synthesis)
    ↓  /brana:maintain-specs
Roadmap (implementation)
    ↓  /brana:reconcile
Code (system/)
```

Changes flow downward. Implementation changes update docs in the same commit (no separate back-propagation step). The `/brana:maintain-specs` skill cascades spec changes. The `/brana:reconcile` skill detects spec-vs-implementation drift.

### Numbering Scheme

Documents are numbered but split across repos:

- **brana-knowledge**: 01-07, 09-13, 16, 20-23, 26-28, 33-38, topic docs
- **thebrana/docs**: 00, 15, 17-19, 24, 25, 30, 39
- **thebrana/docs/reflections**: 08, 14, 29, 31, 32

### Reflection DAG

```
R1(08 Triage) → R2(14 Architecture) → R3(31 Assurance)
                                     → R4(32 Lifecycle)
                                     → R5(29 Venture)
```

### Architecture Docs

Located at `thebrana/docs/architecture/`:

| File | Purpose |
|------|---------|
| `overview.md` | System guide — architecture, lifecycle, deploy model, getting started |
| `skills.md` | Full skill catalog with categories and descriptions |
| `hooks.md` | Hook details — trigger, behavior, output format |
| `agents.md` | Agent roster — model, tools, auto-delegation triggers |
| `extending.md` | How to add new skills, rules, hooks, agents |
| `decisions/` | ADRs (ADR-001 through ADR-014) |
| `features/` | Feature briefs |

## Key File Index

### Plugin Core

| File | Purpose |
|------|---------|
| `system/.claude-plugin/plugin.json` | Plugin manifest — name, version, entry point |
| `system/CLAUDE.md` | Mastermind identity — principles, agents table, portfolio |
| `system/hooks/hooks.json` | Plugin hook registration (PreToolUse, SessionStart, SessionEnd) |
| `system/statusline.sh` | Status bar for terminal |

### Hooks

| File | Purpose |
|------|---------|
| `system/hooks/pre-tool-use.sh` | Spec-first gate + cascade throttle |
| `system/hooks/post-tool-use.sh` | Success logging, correction/test detection |
| `system/hooks/post-tool-use-failure.sh` | Failure logging, cascade detection |
| `system/hooks/post-tasks-validate.sh` | Task schema validation + auto-rollup |
| `system/hooks/post-plan-challenge.sh` | Challenger agent nudge after plan exit |
| `system/hooks/post-pr-review.sh` | PR reviewer agent nudge after `gh pr create` |
| `system/hooks/post-sale.sh` | Deal closure detection |
| `system/hooks/session-start.sh` | Pattern recall, task context, venture detection |
| `system/hooks/session-start-venture.sh` | Legacy venture detection (absorbed into session-start.sh) |
| `system/hooks/session-end.sh` | Flywheel metrics, session summary persistence |
| `system/hooks/lib/` | Shared hook library (cf-env.sh) |

### Top-Level Scripts

| File | Purpose |
|------|---------|
| `bootstrap.sh` | Deploy identity layer to `~/.claude/` |
| `validate.sh` | Pre-deploy validation (12 checks) |

### Enforcement Chain Summary

```
User action
  │
  ├─ Write/Edit on feat/* branch
  │   └─ pre-tool-use.sh → DENY if no spec/test activity
  │       └─ enforces: sdd-tdd.md rule
  │
  ├─ Write/Edit (any branch)
  │   └─ post-tool-use.sh → logs corrections, test writes
  │   └─ post-tool-use-failure.sh → logs failures, flags cascades
  │       └─ pre-tool-use.sh reads cascade flag → injects "stop and reassess"
  │
  ├─ Write/Edit on tasks.json
  │   └─ post-tasks-validate.sh → validates schema, rollup
  │       └─ enforces: task-convention.md rule
  │
  ├─ ExitPlanMode
  │   └─ post-plan-challenge.sh → nudges challenger agent
  │
  ├─ gh pr create (via Bash)
  │   └─ post-pr-review.sh → nudges pr-reviewer agent
  │
  ├─ Session start
  │   └─ session-start.sh → injects patterns, tasks, venture context
  │
  └─ Session end
      └─ session-end.sh → computes metrics, persists summary
```
