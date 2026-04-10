# ADR-035: Skill Usage Telemetry — `brana skills usage`

**Date:** 2026-04-10
**Status:** Accepted
**Deciders:** Martin Rios

## Context

Brana has grown to 25+ skills. Without usage data, pruning decisions are guesswork — skills that feel important may be unused, and rarely-invoked skills waste context budget. CC writes session telemetry to `~/.claude/projects/{encoded-path}/*.jsonl`. Each skill invocation appears as an `assistant` message with a `tool_use` content item where `name == "Skill"` and `input.skill` is the skill name.

## Decision

Add `brana skills usage` as a CLI subcommand (Rust, `brana-cli`). It:

1. Scans `~/.claude/projects/` recursively for `.jsonl` files (two-level: project subdirs + files directly in projects/).
2. Filters events to a rolling window (default: 30 days, configurable via `--days`).
3. Counts invocations per skill, tracks last-used date.
4. Flags skills below a cull threshold (default: <5, configurable via `--cull-threshold`) as removal candidates.
5. Outputs a sorted table (by count desc) or JSON (`--json`).

The implementation lives in `commands::skills` alongside the existing suggest/search/list/reindex handlers. All logic is pure Rust — no subprocess, no MCP dependency.

## Alternatives Considered

- **Shell script scanning JSONL with `jq`**: Works but slow on large history (>1K sessions), no tests, not composable.
- **MCP-based analytics**: Introduces ruflo dependency and startup cost. CLI is the right layer per ADR-036.
- **Manual audit**: Not scalable. The whole point is to make this automatic.

## Consequences

- Skill cull decisions are now data-driven, not intuition-driven.
- `brana skills usage --days 90` run before any `/brana:reconcile` provides evidence for pruning.
- The `--cull-threshold` default of 5 is conservative. Adjust up if too many skills get flagged.
- Telemetry only covers skills invoked via the `Skill` tool. Skills called by agents (which use `Task` or `Agent` tools) are not counted — this undercounts some skills.
- Entries with names like `backlog`, `close`, `morning` (no `brana:` prefix) are project-local skills — treat cull candidates in this group separately.
