# Skills System Guide

Quick reference for the brana skills system — shared scripts, the `/memory` skill, and skill metadata.

## Shared Scripts

`system/scripts/` deploys to `~/.claude/scripts/`. Three primitives extracted from 38 copy-pasted blocks:

| Script | Purpose | Usage |
|--------|---------|-------|
| `cf-env.sh` | Discover claude-flow binary, export `$CF` | `source "$HOME/.claude/scripts/cf-env.sh"` |
| `memory-store.sh` | Store a key-value pair in claude-flow memory (falls back to MEMORY.md) | `"$HOME/.claude/scripts/memory-store.sh" -k KEY -v VALUE -n NAMESPACE -t TAGS` |
| `backup-knowledge.sh` | Trigger brana-knowledge backup if repo exists | `"$HOME/.claude/scripts/backup-knowledge.sh"` |

**When writing a new skill or hook:**
- Need `$CF` for any claude-flow command: source `cf-env.sh`
- Need to store a memory entry: call `memory-store.sh` (don't source cf-env.sh separately)
- Need to trigger backup: call `backup-knowledge.sh`

## The `/memory` Skill

Replaces three former skills (`/pattern-recall`, `/cross-pollinate`, `/knowledge-review`):

| Command | What it does |
|---------|-------------|
| `/memory` or `/memory recall [query]` | Query patterns relevant to current context |
| `/memory pollinate [query]` | Pull transferable patterns from other projects |
| `/memory review` | Monthly knowledge health audit |

## Skill Metadata

Every skill has YAML frontmatter with:

```yaml
---
name: skill-name
description: "..."
group: execution      # brana | execution | venture | learning | utility
depends_on:           # optional — skills this one calls
  - debrief
  - challenge
allowed-tools:
  - Bash
  - Read
---
```

**Groups:** `brana` (self-building), `execution` (project work), `venture` (business ops), `learning` (knowledge), `utility` (tools).

## Interaction Diagram

Generate the full Mermaid diagram:

```bash
~/.claude/scripts/skill-graph.sh
```

Outputs a flowchart showing groups as subgraphs and dependency arrows between skills.

## Validation

`./validate.sh` checks:
- Script syntax (`bash -n`) and shebangs
- `depends_on` entries reference existing skill directories
- All standard checks (frontmatter, budget, secrets, hooks)
