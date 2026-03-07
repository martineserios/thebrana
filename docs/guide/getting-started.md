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
/tasks plan [project]     — plan what to build
/tasks start <id>         — pick a task and start building
/build                    — the build loop runs automatically
/close                    — end the session, capture learnings
```

## Key commands

| Command | What it does |
|---------|-------------|
| `/build` | Build anything — 7 strategies for different work types |
| `/close` | End session — extract learnings, write handoff |
| `/tasks` | Manage tasks — plan, track, navigate |
| `/log` | Capture events — calls, meetings, ideas, links |
| `/research` | Research a topic — recursive discovery |
| `/memory` | Query the knowledge system |
| `/onboard` | Diagnose a new project |
| `/align` | Set up project structure |

See [commands/index.md](commands/index.md) for the full list.

## Concepts

See [concepts.md](concepts.md) for the glossary of terms.
