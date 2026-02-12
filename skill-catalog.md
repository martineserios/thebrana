# Skill Catalog

All skills and commands in the brana system. Skills deploy globally (`~/.claude/skills/`), commands are project-scoped (`.claude/commands/`).

## Global Skills

Deployed from `system/skills/` via `deploy.sh`.

| Skill | Trigger | What It Does |
|-------|---------|-------------|
| `/build-phase` | Ready to implement next roadmap phase | Full cycle: plan + recall + build loop + debrief + maintain-specs |
| `/challenge` | Big decision or plan | Spawns Sonnet to stress-test the approach; stores outcome in ReasoningBank |
| `/cross-pollinate` | Stuck, or starting work in a new domain | Searches ReasoningBank for transferable patterns from other projects |
| `/debrief` | End of implementation session | Extracts errata + process learnings, writes to doc 24 + ReasoningBank |
| `/decide <title>` | Before implementing a new feature | Creates ADR in docs/decisions/ (Nygard format); also enables spec-before-code enforcement |
| `/knowledge-review` | Monthly (or when curious) | Reports ReasoningBank health: confidence distribution, staleness, promotion candidates |
| `/pattern-recall` | Starting work on a topic | Queries ReasoningBank for relevant patterns, grouped by confidence tier |
| `/project-onboard` | First session in a new project | Scans structure, detects stack, recalls relevant portfolio patterns |
| `/project-retire` | Archiving a project | Preserves transferable patterns, archives project-specific ones |
| `/refresh-knowledge` | Dimension docs might be stale | Spawns parallel agents to web-search for updates to each doc's topics |
| `/retrospective` | Session produced a notable learning | Stores pattern with quarantine metadata; promotes/demotes recalled patterns |

## Project Commands (enter repo)

In `enter/.claude/commands/`. Only available when working in the enter repo.

| Command | What It Does |
|---------|-------------|
| `/apply-errata` | Applies pending doc 24 errors to affected spec docs |
| `/maintain-specs` | Full correction cycle: re-evaluate reflections, apply errata layer by layer, check doc 25 |
| `/re-evaluate-reflections` | Cross-checks reflection docs (08, 14) against dimension docs for gaps |
| `/refresh-knowledge` | Project-scoped version — refreshes enter dimension docs specifically |

## Skill Categories

**Knowledge lifecycle:** pattern-recall → retrospective → knowledge-review → cross-pollinate
**Build workflow:** build-phase → debrief → maintain-specs
**Quality:** challenge
**Project lifecycle:** project-onboard → project-retire
**Spec maintenance:** refresh-knowledge → maintain-specs → apply-errata → re-evaluate-reflections

## CLI Pattern

All skills use smart binary discovery for claude-flow:

```bash
CF=""
for candidate in "$HOME"/.nvm/versions/node/*/bin/claude-flow; do
    [ -x "$candidate" ] && CF="$candidate" && break
done
[ -z "$CF" ] && command -v claude-flow &>/dev/null && CF="claude-flow"
[ -z "$CF" ] && command -v npx &>/dev/null && CF="npx claude-flow"
```

Falls back to native auto memory (`~/.claude/projects/*/memory/`) when claude-flow is unavailable.
