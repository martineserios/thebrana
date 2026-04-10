# Brana Workspace Ecosystem

Brana works from any directory — but understanding how the pieces fit together helps you get the most out of it.

## What brana installs

Two layers. Both are optional but the plugin is where value lives.

| Layer | What it is | Where it goes |
|-------|-----------|--------------|
| **Plugin** | Skills, hooks, agents, rules | Loaded by Claude Code per-session via `--plugin-dir` or marketplace |
| **Identity layer** | Global CLAUDE.md, rules, scripts, scheduler | Deployed to `~/.claude/` via `./bootstrap.sh` |

The plugin provides what Claude can *do*. The identity layer provides how Claude *thinks* — consistent across every project.

## Optional: brana-knowledge

`brana-knowledge` is a separate companion repo containing the knowledge base — 33+ dimension docs on topics like testing, infrastructure, marketing, and system design. It is *not* required for the plugin to work. Without it, brana still learns within sessions via ruflo memory. With it, brana has a searchable foundation of curated knowledge.

```bash
git clone https://github.com/martineserios/brana-knowledge.git
```

The knowledge indexer (`brana knowledge reindex`) defaults to `~/enter_thebrana/brana-knowledge/dimensions`. If your clone is elsewhere, set the override before indexing:

```bash
export BRANA_KNOWLEDGE_DIR=/your/path/to/brana-knowledge/dimensions
brana knowledge reindex
```

## The portfolio concept

Brana tracks your work across multiple projects via `CLAUDE.md`. The global identity file (`~/.claude/CLAUDE.md`) includes a **portfolio** section that lists your active projects — clients, ventures, personal directories — with their type, location, and status.

This is how brana knows which project you're in, what happened last session, and which patterns from other projects might apply. The portfolio is not a required directory structure — it is a CLAUDE.md convention that you control.

**Example portfolio entry:**

```markdown
### my-startup
- **Type:** SaaS product
- **Location:** `~/projects/my-startup/`
- **Status:** Active
```

Each listed project can have its own `.claude/CLAUDE.md` with project-specific conventions. Brana's global rules combine with those local rules automatically.

## Reference workspace layout

This is the layout used in brana's own development. It is one example — not a requirement.

```
~/enter_thebrana/
├── thebrana/              ← plugin repo (this repo)
│   ├── system/            ← plugin: skills, hooks, agents
│   ├── docs/              ← design specs, guides, ADRs
│   └── bootstrap.sh       ← deploys identity layer
├── brana-knowledge/       ← knowledge base (optional companion repo)
│   └── dimensions/        ← 33+ deep-research docs
├── clients/               ← paid client work (external stakeholders)
│   ├── client-a/
│   └── client-b/
├── ventures/              ← personal IP (side projects, your own products)
│   ├── my-app/
│   └── my-research/
└── personal/              ← personal OS (journaling, goals, identity work)
```

**The key boundary:** `clients/` is for external stakeholders. `ventures/` is your own IP. `personal/` is non-work. This separation is a mental model — it helps you and brana's portfolio entries stay organized. It does not change hook behavior; hooks route by git root, not by parent directory name.

You do not need this structure. Brana works equally well with a single project directory. The structure pays off when you're running multiple active projects and want brana to route patterns correctly between them.

## brana-knowledge is a library, not a project

`brana-knowledge` has no backlog, no tasks, and no session state. It is a library — dimension docs are written there, indexed into ruflo memory, and searched during builds. You do not open Claude Code from inside `brana-knowledge/`. You open it from inside a project, and brana pulls relevant knowledge into context automatically.

## Where memory lives

| Store | What | Where |
|-------|------|-------|
| **Per-project** | Tasks, session state, MEMORY.md | `~/.claude/projects/{project-slug}/` |
| **Global** | CLAUDE.md portfolio, rules | `~/.claude/` |
| **Cross-project** | Patterns, knowledge, session history | ruflo `~/.swarm/memory.db` |

Cross-project memory (ruflo) is what enables brana to say "I remember this problem from another project" or "the pattern from client A applies here." It is the semantic layer over all your sessions.

## Starting in a new project

Open Claude Code in any directory:

```bash
cd ~/projects/my-project
claude
```

Brana loads. If `my-project` has a `.claude/CLAUDE.md`, those conventions layer on top of the global ones. If not, create one:

```bash
/brana:onboard   # scans the project, drafts a CLAUDE.md
```

Add the project to your portfolio in `~/.claude/CLAUDE.md` so future session-starts recall relevant patterns.
