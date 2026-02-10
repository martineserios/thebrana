# brana - Mastermind System

The brain that deploys to `~/.claude/`. Edit files here, deploy there.

## Development Workflow

1. Edit files in `system/`
2. Run `./validate.sh` to check for errors
3. Run `./deploy.sh` to deploy to `~/.claude/`
4. Start a new Claude Code session to test changes

## Key Commands

- `./deploy.sh` — validate + deploy system files to `~/.claude/`
- `./validate.sh` — check frontmatter, context budget, secrets, structure
- `./export-knowledge.sh` — export native memory and ReasoningBank

## Rules

- Never edit `~/.claude/` directly — always edit `system/` and deploy
- Run `validate.sh` before every deploy
- Test in a real Claude Code session after deploying

## Phase Status

Phase 1: Skills working, hooks disabled. See brana-v2-specs for full roadmap.
