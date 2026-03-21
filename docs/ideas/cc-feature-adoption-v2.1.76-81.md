# CC Feature Adoption — v2.1.76–v2.1.81

> Brainstormed 2026-03-21. Status: idea.

## Problem

Claude Code ships features faster than brana adopts them. No systematic intake process exists (t-471 pending). Features with direct brana impact go unnoticed until manually discovered.

## Proposed solution

Tiered adoption plan for 10 features from CC v2.1.76–v2.1.81, prioritized by impact on brana's skill/hook/plugin infrastructure.

## Research findings

### Tier 1 — Config Pass (<1 hour)

**`effort` frontmatter** (v2.1.80) — reasoning intensity dial for skills.
- Values: `low`, `medium`, `high`, `max` (max = Opus 4.6 only)
- Haiku ignores effort; only Sonnet 4.6 and Opus 4.6 support it
- Subagents don't inherit session effort — must set explicitly in frontmatter
- Precedence: env var > frontmatter > session > model default

Recommended mapping:

| Effort | Skills |
|--------|--------|
| `low` | log, gsheets, export-pdf, repo-cleanup, plugin, scheduler, sitrep |
| `medium` | backlog, onboard, align, pipeline, harvest, memory |
| `high` | build, close, review, research, brainstorm, maintain-specs, reconcile, proposal, financial-model, venture-phase |
| `max` | challenge (Opus adversarial review) |

### Tier 2 — Design + Build

#### StopFailure hook (v2.1.78)

Fire-and-forget hook for API-level errors. Complements existing `post-tool-use-failure.sh` (tool errors).

- 7 error types: `rate_limit`, `authentication_failed`, `billing_error`, `invalid_request`, `server_error`, `max_output_tokens`, `unknown`
- JSON on stdin: `session_id`, `transcript_path`, `error`, `error_details`, `cwd`
- Matchers filter by error type — can route different errors to different scripts
- No decision control — exit codes and output ignored
- Multiple hooks run in sequence

**Action:** Write `stopfailure-logger.sh` → JSONL log + Telegram alert for `auth`/`billing`. Add to plugin `hooks.json`. Estimated: 2 hours.

#### PLUGIN_DATA migration (v2.1.78)

Persistent directory at `~/.claude/plugins/data/{id}/` that survives plugin updates. Solves the manual binary copy problem.

- Lazy creation on first reference
- Works in dev mode (`--plugin-dir`) and installed mode
- SessionStart hook pattern: diff `Cargo.toml` → recompile only when deps change
- ADR-015 (state in `~/.claude/`) is about config/state, not build artifacts — complementary

**Action:** Move binary compilation to `${CLAUDE_PLUGIN_DATA}`. Update `hooks.json` SessionStart. Remove manual `cp` workaround. Estimated: 4 hours.

#### Session cron — revised assessment (v2.1.76+)

Session-scoped scheduling via `CronCreate`/`CronList`/`CronDelete`.

- Skills can't invoke CronCreate — only main conversation can
- Cron prompts CAN invoke skills (`"prompt": "/brana:build check-ci"` works)
- Each fire costs API tokens — no discount
- 3-day expiry non-configurable, no retry on failure
- Max 50 tasks per session

**Revised verdict:** Useful for ad-hoc user polling ("check CI every 5 min"), not for automated skill-driven workflows. Don't embed in `/brana:build`. Document as user-facing capability. Estimated: 1 hour (docs only).

### Tier 3 — Evaluate Later

| Feature | Notes |
|---------|-------|
| `--channels` permission relay (v2.1.81) | Push-based CI notification may be better than cron polling. Evaluate alongside session cron. |
| `--bare` flag (v2.1.81) | Useful when `brana run --spawn` matures. Skips hooks/LSP/plugin sync for scripted `-p` calls. |
| MCP Elicitation (v2.1.76) | AskUserQuestion covers current needs. Revisit if structured JSON schemas add value. |
| Session naming `-n` (v2.1.76) | Minor QoL for `brana run`. Could pass `-n t-NNN-slug` for named sessions. |
| Sparse checkout (v2.1.76) | No monorepo need. Revisit if portfolio grows. |
| Statusline rate limits (v2.1.80) | Informational only. Could add to `statusline.sh` during maintenance. |

## Risks

| Risk | Mitigation |
|------|-----------|
| `effort` miscalibration → skill underperforms | Test each skill after setting effort; adjust empirically |
| PLUGIN_DATA path changes across CC versions | Pin to `${CLAUDE_PLUGIN_DATA}` variable, not hardcoded path |
| Session cron forgotten mid-session | Don't automate — user-initiated only |
| StopFailure can't save meaningful state | Accept limitation — alerts only. `/brana:close` handles graceful shutdown |

## Related backlog

- **t-471** — CC changelog monitoring (this brainstorm is a manual instance)
- **t-197** — SubagentStart/Stop hooks (hook infrastructure)
- **t-200** — ConfigChange hook (same domain)
- **t-201** — Split session-end.sh (hook refactor)
- **t-465** — CC features research

## Next steps

1. Sweep all skills with `effort` frontmatter (Tier 1)
2. Build StopFailure hook + PLUGIN_DATA migration (Tier 2)
3. Document session cron as user-facing capability (Tier 2)
4. Create backlog tasks when ready to schedule work
