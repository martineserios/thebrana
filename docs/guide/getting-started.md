# Getting Started

## Install

Brana is a system of skills, rules, hooks, and agents for Claude Code.

```bash
git clone https://github.com/martineserios/thebrana.git
cd thebrana
./deploy.sh
```

`deploy.sh` copies everything to `~/.claude/` where Claude Code picks it up.

## First session

Just start working. The session-start hook automatically:
- Recalls relevant patterns from the knowledge system
- Shows active tasks and next steps
- Detects project type (code, venture, or hybrid)

## Core workflow

```
/brana:tasks plan [project]     — plan what to build
/brana:tasks start <id>         — pick a task and start building
/brana:build                    — the build loop runs automatically
/brana:close                    — end the session, capture learnings
```

## Key commands

| Command | What it does |
|---------|-------------|
| `/brana:build` | Build anything — 7 strategies for different work types |
| `/brana:close` | End session — extract learnings, write handoff |
| `/brana:tasks` | Manage tasks — plan, track, navigate |
| `/brana:log` | Capture events — calls, meetings, ideas, links |
| `/brana:research` | Research a topic — recursive discovery |
| `/brana:memory` | Query the knowledge system |
| `/brana:onboard` | Diagnose a new project |
| `/brana:align` | Set up project structure |

See [commands/index.md](commands/index.md) for the full list.

## Concepts

See [concepts.md](concepts.md) for the glossary of terms.
