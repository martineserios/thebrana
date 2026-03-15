# Contributing to brana

Thanks for your interest in contributing. This guide covers everything you need to get started.

## Architecture overview

Brana has two layers. You only need the first one to contribute.

```
┌──────────────────────────────────────────────────────────────────┐
│  Claude Code                                                     │
│                                                                  │
│  ┌────────────────────────────────┐  ┌────────────────────────┐  │
│  │  Plugin (system/)             │  │  Identity (~/.claude/)  │  │
│  │                                │  │                         │  │
│  │  What Claude can DO            │  │  How Claude THINKS      │  │
│  │                                │  │                         │  │
│  │  skills/  → slash commands     │  │  CLAUDE.md → personality│  │
│  │  hooks/   → event triggers     │  │  rules/    → behaviors │  │
│  │  agents/  → sub-agents         │  │  scripts/  → utilities │  │
│  │  commands/→ agent commands     │  │  scheduler/→ cron jobs │  │
│  │                                │  │                         │  │
│  │  You edit this.               │  │  Optional. For users    │  │
│  │  --plugin-dir ./system        │  │  who want the full      │  │
│  └────────────────────────────────┘  │  brana experience.      │  │
│                                       └────────────────────────┘  │
└──────────────────────────────────────────────────────────────────┘
```

**Plugin** = the toolbox (skills, hooks, agents). This is what you develop and test.
**Identity layer** = the mindset (rules, personality). Optional for contributors.

## Setup

```bash
# 1. Fork and clone
git clone https://github.com/<your-username>/thebrana.git
cd thebrana

# 2. Start Claude Code with the plugin loaded from source
claude --plugin-dir ./system

# 3. Verify it works
/brana:backlog    # should show the task list
```

That's it. Every edit you make to `system/` is live on the next Claude Code session.

**No bootstrap.sh needed.** The identity layer is optional — it's for users who want brana's full behavioral rules and personality. As a contributor, `--plugin-dir ./system` gives you everything you need to develop and test.

## What to work on

Check [open issues](https://github.com/martineserios/thebrana/issues) for things tagged `good first issue` or `help wanted`. If you want to work on something not listed, open an issue first to discuss it.

### Where things live

| You want to... | Edit files in... |
|----------------|-----------------|
| Add/fix a skill | `system/skills/<skill-name>/SKILL.md` |
| Add/fix a hook | `system/hooks/hooks.json` + `system/hooks/<script>.sh` |
| Add/fix an agent | `system/agents/<agent-name>.md` |
| Add/fix a command | `system/commands/<command>.md` |
| Fix the plugin manifest | `system/.claude-plugin/plugin.json` |
| Update docs | `docs/` |

## Making changes

### Branch naming

| Prefix | When |
|--------|------|
| `feat/` | New skill, hook, agent, or capability |
| `fix/` | Bug fix |
| `docs/` | Documentation only |
| `refactor/` | Same behavior, better code |
| `chore/` | Maintenance, config, CI |
| `test/` | Adding or fixing tests |

### Commit messages

We use [Conventional Commits](https://www.conventionalcommits.org/). This drives automatic versioning and changelog generation.

```
feat(skills): add /brana:deploy skill
fix(hooks): spec-first gate false positive on test files
docs: update getting-started guide
chore: update CI workflow
```

**Format:** `type(scope): description`

- `feat:` → minor version bump (0.7.0 → 0.8.0)
- `fix:` → patch version bump (0.7.0 → 0.7.1)
- `BREAKING CHANGE:` in the commit body → major version bump (0.7.0 → 1.0.0)

### Pull request process

1. Create a branch from `main`
2. Make your changes
3. Test with `claude --plugin-dir ./system`
4. Push and open a PR against `main`
5. Fill in the PR template
6. Wait for CI checks to pass
7. A maintainer will review and merge

### Testing your changes

#### Skills, agents, and commands

1. Start a session with `claude --plugin-dir ./system`
2. Exercise the skill/hook/agent you changed
3. Confirm it works as expected

#### Hooks

Test hooks locally by piping JSON to the script:

```bash
# Test a PreToolUse hook
echo '{"tool_name":"Write","tool_input":{"file_path":"src/app.ts"}}' | bash system/hooks/pre-tool-use.sh

# Test a SessionStart hook
echo '{}' | bash system/hooks/session-start.sh
```

The hook should print valid JSON to stdout. Check exit codes: 0 = allow, non-zero = block (for PreToolUse).

#### Validation

```bash
./validate.sh    # runs pre-deploy checks (frontmatter, budget, secrets, hook permissions)
```

Run `validate.sh` before every PR. CI runs it too, but catching issues locally saves time.

## Code style

- **Skills** are markdown files (`SKILL.md`) with YAML frontmatter. Keep them concise and opinionated.
- **Hooks** are shell scripts. Use `set -euo pipefail`. Keep them fast (hooks block Claude Code).
- **Agents** are markdown files defining personality and capabilities. Be specific about what the agent should and shouldn't do.
- Don't add features beyond what's needed. Simpler is better.

## Release process

You don't need to worry about releases. When your PR is merged to `main`:

1. CI runs `validate.sh`
2. [semantic-release](https://github.com/semantic-release/semantic-release) reads commit messages
3. Version is bumped automatically in `plugin.json` and `marketplace.json`
4. A git tag and GitHub Release are created
5. Users get the update on their next `/plugin update brana`

## Finding work

1. Browse [issues](https://github.com/martineserios/thebrana/issues) tagged [`good first issue`](https://github.com/martineserios/thebrana/labels/good%20first%20issue) -- these are scoped, well-described, and reviewed within 48h
2. Check [`help wanted`](https://github.com/martineserios/thebrana/labels/help%20wanted) for larger items where input is welcome
3. Have an idea? Open an issue using the **feature request** template first -- alignment before code saves everyone time

## Becoming a contributor

1. Open an issue or comment on an existing one expressing interest
2. A maintainer will add you as a collaborator (`write` access)
3. Once a second contributor joins, PR approval reviews will be enabled

## Maintainer checklist: adding a contributor

When the first external contributor joins, run these steps:

```bash
# 1. Add collaborator
gh api repos/martineserios/thebrana/collaborators/USERNAME -X PUT -f permission=write

# 2. Enable PR review requirement
gh api repos/martineserios/thebrana/branches/main/protection \
  -X PUT -H "Accept: application/vnd.github+json" --input - <<'EOF'
{
  "required_status_checks": { "strict": true, "contexts": ["validate"] },
  "enforce_admins": true,
  "required_pull_request_reviews": {
    "required_approving_review_count": 1,
    "dismiss_stale_reviews": true
  },
  "restrictions": null,
  "allow_force_pushes": false,
  "allow_deletions": false
}
EOF
```

## Recognition

When your first PR is merged, add yourself to the Contributors section in [README.md](README.md).

## Questions?

Open an issue using the **question** template, or start a discussion. We're happy to help.

## License

By contributing, you agree that your contributions will be licensed under the [MIT License](LICENSE).
