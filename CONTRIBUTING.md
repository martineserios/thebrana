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
/brana:tasks    # should show the task list
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

There's no test suite yet (it's a Claude Code plugin — the "tests" are using the skills and hooks). To verify your changes:

1. Start a session with `claude --plugin-dir ./system`
2. Exercise the skill/hook/agent you changed
3. Confirm it works as expected
4. Check that `./validate.sh` passes

```bash
./validate.sh    # runs pre-deploy checks (frontmatter, budget, secrets)
```

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

## Questions?

Open an issue or start a discussion. We're happy to help.

## License

By contributing, you agree that your contributions will be licensed under the [MIT License](LICENSE).
