# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### 2026-10-05 — ship dev→main, PR #1091 (v1.86.0; brana-mcp drain also in PR #1092, v1.85.2; cockpit mods harness, brana-mcp, hook fix, ADR-095)

### Fixed
- Pattern-promotion hook reads by exact key and never writes after a failed or empty read; stops stubbing every promoted pattern (t-3455)
- `brana-mcp` answers unknown methods with `-32601` instead of going silent, and drains in-flight requests at stdin EOF (t-3414, t-3462)
- `bootstrap.sh --check` no longer exits 3 when no `./mods/` entry exists; the 7g ruflo guard runs only once the marketplace lists a mod (t-3427, Gate 3)

### Added
- Cockpit mods enforcement harness: `mods/_shared`, `mods-check.sh --static/--engine`, validate Checks 77a/77b, bootstrap steps 7g/7h, pinned CLI in CI, `mods-drift.yml` (t-3443..t-3449)
- ADR-096 cockpit surface as function-hook mods (accepted)
- ADR-095 revised after the t-3442 challenge (one owner machine, company-managed Mac profile) with the t-3435 divergence amendment; brana-knowledge fetch-first guard and section-union export ship in that private repo

### Notes
- Deployed from a temporary worktree at main: local dev carried unshipped t-3470 commits and could not fast-forward. The advisory macOS CI job is red (test portability bugs, t-3469).

### 2026-10-02 — ship dev→main, PR #1083 (macOS portability, epic t-3372)

### Fixed
- `bootstrap.sh` wires `statusLine` into `settings.json` instead of only copying `statusline.sh`; creates a 0600 `settings.json` on a brand-new machine; never clobbers a custom value (t-3388)
- Test suites run under a throwaway `HOME` in both runners and in `validate.sh` Checks 65/66 — no suite can write into the operator's `~/.claude` (t-3389, `system/scripts/lib/suite-home.sh`)
- Portability tests force the no-flock fallback on every host; `test-lock-stress.sh` no longer skips on a Mac with brew `flock` (t-3391)
- `p_timeout` ends the whole process group, escalates to KILL, prints a heartbeat; group mode without `-k` grants survivors a 2s grace (t-3390, Gate 3)
- ruflo MCP memory store pinned to `$HOME/.swarm` (peer session)

### Added
- ADR-095 two-machine memory sync (proposed)
- `tests/hooks/test-portable-flock-present.sh`, `tests/bootstrap/test-statusline-setting.sh`

## [1.0.0] - 2026-03-09

### Added
- Plugin marketplace publication (`marketplace.json`, install via `/plugin marketplace add`)
- `/brana:plugin` skill for plugin management and auto-registration in `bootstrap.sh`
- Background-fork pattern for session hooks (respond instantly, fork heavy work)
- First-principles building methodology documentation
- System documentation map for architecture reference

### Changed
- Renamed `/brana:tasks` to `/brana:backlog` with subcommand updates
- Renamed conceptual "projects" to "clients" across system (portfolio, agents, skills, memory tags)
- Enriched portfolio project registry with metadata

### Fixed
- Session-end hook responds immediately, forks processing to background
- Release workflow: removed plugins that push to protected main
- Release version bump script writes to closed file

## [0.7.0] - 2026-03-07

### Added
- **Plugin system**: distribute brana as a Claude Code plugin (`system/.claude-plugin/plugin.json`)
- **Bootstrap identity layer**: `bootstrap.sh` deploys CLAUDE.md, rules, scripts to `~/.claude/`
- Skill namespace migration: all skills prefixed `/brana:*` (e.g., `/build` became `/brana:build`)
- Plugin hook format (`hooks.json` in plugin directory)
- Marketplace install: `/plugin marketplace add martineserios/thebrana`
- Contributor onboarding docs and maintainer checklist (`CONTRIBUTING.md`)
- Post-ship errata tracking for plugin issues

### Changed
- Two-layer architecture: plugin (toolkit) + bootstrap (identity)
- Deprecated `deploy.sh` in favor of plugin system + `bootstrap.sh`
- PostToolUse hooks moved to `~/.claude/settings.json` (CC plugin bug workaround)

### Fixed
- `CLAUDE_PLUGIN_ROOT` not set by hook executor (absolute paths required)
- Plugin cache drift errata (E3) with `bootstrap --sync-plugin`
- Bootstrap removes stale `~/.claude/{skills,commands,agents}` directories

## [0.6.0] - 2026-03-06

### Added
- Unified `/brana:build` skill — auto-detects strategy (feature, bug fix, refactor, spike, migration, investigation, greenfield)
- Skill consolidation: merged onboard, align, review, research into fewer, smarter skills
- `--refresh` flag for `/brana:research` (batch dimension updates)
- Build loop integration with `/brana:backlog` (strategy + build_step fields)
- Pre-tool-use hook verifiable enforcement

### Changed
- Retired 22 old skills, updated routing and task convention
- Restructured documentation: `docs/guide/` for users, `docs/architecture/` for contributors

## [0.5.0] - 2026-03-04

### Added
- `/brana:reconcile` skill for spec-vs-implementation drift detection
- Agent-skill symbiosis: 6 agents with delegation routing and skill triggers
- Git worktree adoption for branch operations
- Venture management skills: morning, weekly-review, pipeline, experiment, content-plan, financial-model, monthly-close
- Venture guide documentation
- Google Sheets MCP integration (`/brana:gsheets` skill)
- Auto-challenge hook on `ExitPlanMode`
- Venture OS hooks: session-start-venture, post-sale
- Venture OS agents: daily-ops, metrics-collector, pipeline-tracker
- `/brana:research` skill with version tracking

### Changed
- CLAUDE.md rewritten as operator station (v0.5.0 framing)
- Memory framework rule extracted from MEMORY.md into `rules/`

### Fixed
- Resilient hooks: removed `set -euo pipefail`, added safe CWD fallback
- Context budget raised to accommodate full git-discipline rule

## [0.4.0] - 2026-03-01

### Added
- `/brana:debrief` skill for extracting errata and learnings from implementation sessions
- `/brana:decide` skill for ADR creation (Nygard format)
- PreToolUse spec-before-code enforcement on `feat/*` branches
- SDD/TDD development conventions rule
- Knowledge review skill for monthly ReasoningBank health checks
- Skill catalog documentation
- Quarantine metadata, recall logging, promotion tracking
- 5 venture management skills (venture-onboard, venture-align, venture-phase, sop, growth-check)
- `/project-align` skill (5-phase alignment pipeline)

### Fixed
- Smart binary discovery in all skills (replaced bare `npx`)
- Hook cascade prevention on deleted CWD
- grep double output and npx timeout issues in hooks
- validate.sh handles `---` horizontal rules in skill body content

## [0.3.0] - 2026-02-27

### Added
- Phase 1 working skeleton: hooks, refresh-knowledge skill, claude-flow v3 API integration
- Basic health check test suite (hooks smoke + memory round-trip)
- Ask-for-clarification rule in all skills
- Git discipline rule

### Fixed
- Additive hooks merge in deploy
- claude-flow alpha.34 compatibility (`-q` to `--query`)

[1.0.0]: https://github.com/martineserios/thebrana/compare/v0.7.0...v1.0.0
[0.7.0]: https://github.com/martineserios/thebrana/compare/v0.6.0...v0.7.0
[0.6.0]: https://github.com/martineserios/thebrana/compare/v0.5.0...v0.6.0
[0.5.0]: https://github.com/martineserios/thebrana/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/martineserios/thebrana/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/martineserios/thebrana/releases/tag/v0.3.0
