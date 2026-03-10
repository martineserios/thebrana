# Security

## Reporting Vulnerabilities

If you discover a security vulnerability, please report it privately:

- **Email:** Open a GitHub issue marked `security` at [martineserios/thebrana](https://github.com/martineserios/thebrana/issues)
- Do not disclose publicly until a fix is available

## What brana accesses

- **Local filesystem:** reads/writes project files, `~/.claude/` config, and `/tmp/` for temp data
- **Git:** runs git commands in project directories
- **MCP servers:** optional integrations (claude-flow, context7, notebooklm) — user-configured, not bundled
- **No network calls** from plugin code itself — all external access goes through Claude Code's built-in tools or user-configured MCP servers

## Hook security

All hook scripts run locally and are visible in `system/hooks/`. They:
- Never send data to external services
- Never modify files outside the current project and `~/.claude/`
- Are gated by Claude Code's permission system
