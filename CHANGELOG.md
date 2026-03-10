# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
