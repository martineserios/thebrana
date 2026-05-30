# thebrana — Design and Build the Brain

> The unified brana system repo. Design specs live in `docs/`, implementation lives in `system/`. One repo, one feedback loop. (Merged from enter + thebrana per ADR-006.)

## Two Workspaces, One Repo

| Workspace | Location | Purpose |
|-----------|----------|---------|
| **Architect** | `docs/` | Research, design, plan — dimension/reflection/roadmap docs |
| **Operator** | `system/` | Build, deploy, maintain — skills, hooks, rules, agents |

**Branch naming convention:**
```
{epic-slug}/{work-type}/t-{NNN}-{description-slug}
```

- **epic-slug** — kebab-case theme grouping the task (e.g. `session`, `backlog-git`, `harness`)
- **work-type** — one of: `feat` · `fix` · `chore` · `research` · `test` · `docs` · `refactor`
- **t-{NNN}** — backlog task ID (required for all implementation branches)
- **description-slug** — 2–4 word kebab summary

Examples:
- `session/fix/t-1700-epic-scoped-path-assertion`
- `harness/chore/t-1717-context-budget-skip-reference`
- `backlog-git/feat/t-1619-branch-convention-docs`

Special branches (no task ID required): `main`, `docs/{topic}` (spec-only, no `system/` edits).

## Inbox

`inbox/` is a processing drop folder (gitignored). Drop files here for Claude to process: audio for transcription, docs for analysis, PDFs for review, data for import. Files are transient — process and delete or move to permanent storage.

> IMPORTANT: Before spec work, read [ARCHITECTURE.md](../docs/reflections/ARCHITECTURE.md) — layer diagram, Reflection DAG, spec lifecycle.

## Commands

### The 6 Jobs

| Job | Question | Entry Point |
|-----|----------|-------------|
| DECIDE | "What should I work on?" | `/brana:backlog`, `/brana:brainstorm` |
| UNDERSTAND | "What do I need to know?" | `/brana:research`, `/brana:onboard` |
| BUILD | "Make the thing" | `/brana:build` |
| SHIP | "Get it to users" | `/brana:ship`, `./bootstrap.sh`, `./validate.sh` |
| MAINTAIN | "Keep it healthy" | `/brana:reconcile`, `/brana:verify-docs` |
| GROW | "Build the business" | `/brana:review` |

> Full command reference: [docs/reference/skills.md](../docs/reference/skills.md)

## Specs Reference

| Topic | Doc |
|-------|-----|
| Architecture (layers, hooks, skills) | [ARCHITECTURE.md](../docs/reflections/ARCHITECTURE.md) |
| Lifecycle (DDD → SDD → TDD workflow) | [32-lifecycle.md](../docs/reflections/32-lifecycle.md) |
| Roadmap and next steps | [18-lean-roadmap.md](../docs/18-lean-roadmap.md) |
| Errata and corrections | [24-roadmap-corrections.md](../docs/24-roadmap-corrections.md) |
| ADR index | [docs/architecture/decisions/](../docs/architecture/decisions/) |

## Ecosystem

| Repo | Role | You go here to... |
|------|------|-------------------|
| **thebrana** (here) | Design + Build | Research, plan, implement, deploy |
| **brana-knowledge** | Knowledge base | General knowledge, research, backups |
| **clients/** | Paid work | External stakeholder projects (`~/enter_thebrana/clients/`) |
| **ventures/** | Your IP | Side projects, learning, monetizing (`~/enter_thebrana/ventures/`) |
| **personal/** | Personal OS | Journal, goals, identity (`~/enter_thebrana/personal/`) |

## Rules

- **Never edit `~/.claude/` directly** — edit `system/` (plugin loads it) or re-run `./bootstrap.sh` (identity layer)
- Changes propagate: dimension → reflection → roadmap (run `/brana:reconcile --scope propagation` to check for drift)
- Spec changes push to implementation (`/brana:reconcile`)
- Implementation changes update docs in the same commit (no separate back-propagation step)
- When adding new docs, update `docs/README.md`
- Ruflo namespaces: query `knowledge` + `pattern` in parallel (use `namespace: "all"` only with `threshold: 0.55` in v3.6 — session records score constant 0.5 and contaminate below that). `specs` namespace is unindexed — skip.
- Use `.claude/CLAUDE.local.md` (gitignored) for personal/machine-specific overrides — loaded last, wins on conflict. Never commit it.

<!-- Field Notes archived to ~/.claude/projects/*/memory/ and ruflo patterns. Query via /brana:memory. New gotchas go there, not here. -->

