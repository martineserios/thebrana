# ADR-011: Skills Bundling — Ship Scripts Alongside SKILL.md

**Date:** 2026-03-03
**Status:** accepted
**Task:** [t-045](../../.claude/tasks.json)

## Context

Skills are defined by `SKILL.md` files but often depend on external scripts located in `system/scripts/`. This creates a deployment gap: the skill definition ships to `~/.claude/skills/{name}/` but its helper scripts land in a separate `~/.claude/scripts/` directory. The coupling is implicit — a path string in SKILL.md points elsewhere.

DeAngelis (context engineering): "Skills should bundle scripts. Pure-markdown skills hit a ceiling. Bundling .sh/.py helpers alongside SKILL.md enables richer automation."

## Decision

### 1. Collocate scripts with their skill

Helper scripts that a skill depends on are copied into the skill's directory alongside SKILL.md:

```
system/skills/knowledge/
├── SKILL.md
├── index-knowledge.sh    ← bundled script
└── generate-index.sh     ← bundled script
```

Deployed to:

```
~/.claude/skills/knowledge/
├── SKILL.md
├── index-knowledge.sh    ← executable
└── generate-index.sh     ← executable
```

### 2. deploy.sh adds chmod +x for bundled scripts

After copying skills, deploy.sh makes all `.sh` and `.py` files under `skills/` executable:

```bash
find "$TARGET_DIR/skills" \( -name "*.sh" -o -name "*.py" \) -exec chmod +x {} +
```

### 3. SKILL.md references deployed paths

Skills reference their own scripts using the deployed path convention:

```bash
INDEXER="$HOME/.claude/skills/knowledge/index-knowledge.sh"
INDEX_GEN="$HOME/.claude/skills/knowledge/generate-index.sh"
```

### 4. Backward compatibility via originals in scripts/

Original scripts remain in `system/scripts/` with a deprecation header pointing to the canonical location. This preserves compatibility with:
- brana-knowledge post-commit hooks
- Scheduled tasks (cron/systemd)
- Direct CLI invocation

### 5. Scope: .sh and .py only

Only `.sh` and `.py` files are eligible for bundling. Other file types (configs, data) stay in their current locations.

## Alternatives Considered

- **Symlinks from skill dir to scripts/:** Breaks on deploy (target paths differ between source and deployed). Real copies are simpler.
- **Move scripts entirely:** Breaks external consumers (post-commit hooks, scheduler). Keeping originals with deprecation headers is safer.
- **Package scripts as a separate deploy step:** Adds complexity. `find + chmod` after the existing `cp -r` is minimal.

## Consequences

- Skills become self-contained — all dependencies ship together
- deploy.sh gains one line (`find ... chmod +x`)
- External consumers (hooks, scheduler) continue working via deprecated originals
- Future skills can bundle their own scripts without deploy.sh changes
- Deprecated scripts should be removed once all external consumers are updated

## References

- Context engineering: DeAngelis — "Skills should bundle scripts"
- Knowledge skill: [system/skills/knowledge/SKILL.md](../../system/skills/knowledge/SKILL.md)
- Deploy: [deploy.sh](../../deploy.sh)
