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
| `/knowledge [cmd]` | Managing the knowledge base | Browse, review staleness, annotate, reindex brana-knowledge dimension docs |
| `/refresh-knowledge` | Dimension docs might be stale | Spawns parallel agents to web-search for updates to each doc's topics |
| `/retrospective` | Session produced a notable learning | Stores pattern with quarantine metadata; promotes/demotes recalled patterns |
| `/tasks [command]` | Planning or tracking work | Manage tasks with hierarchy — plan, status, roadmap, start, done. NL is primary; commands are shortcuts |

## Venture/Business Skills

For the complete task management guide, see **[task-guide.md](task-guide.md)**.

For the complete usage guide, see **[venture-guide.md](venture-guide.md)**.

| Skill | Trigger | What It Does |
|-------|---------|-------------|
| `/venture-onboard` | First session on a business project | Diagnoses stage, recommends framework, identifies gaps (read-only) |
| `/venture-align` | After `/venture-onboard` identifies gaps | Creates business structure: metrics, meetings, SOPs, OKRs (stage-aware) |
| `/venture-phase [type]` | Executing a business milestone | Plans and executes: launch, hiring, fundraise, expansion, process, custom |
| `/growth-check` | Monthly/quarterly health check | AARRR funnel + stage-appropriate metrics + trend tracking |
| `/sop [name]` | Process repeated 3+ times | Creates versioned SOP in docs/sops/ with auto-incrementing number |
| `/morning` | Daily session start on venture project | Stage-aware focus card: priorities, blockers, key metric, calendar |
| `/weekly-review` | Friday or Monday | Portfolio update, kill zombies, metrics delta, ship log, plan next week |
| `/pipeline` | Sales tracking | Stage-aware CRM: leads, deals, conversions, follow-ups |
| `/experiment` | Growth testing | Hypothesis → test → ICE score → success criteria → results → learning |
| `/financial-model` | Fundraise or monthly planning | 3-scenario revenue projection, P&L template, unit economics, cash flow |
| `/content-plan` | Quarterly content strategy | Content calendar, channels, distribution checklist, performance tracking |
| `/monthly-close` | End of month | P&L summary, actuals vs projections, trend analysis, runway update |
| `/monthly-plan` | End of month (after close) | Forward-looking plan: revenue targets, priorities, experiments, pipeline actions, budget |
| `/gsheets [action]` | Direct Sheets operations | Read, write, create, list, share spreadsheets via MCP (performance-optimal) |

## Project Commands (thebrana)

In `thebrana/.claude/commands/`. Available when working in the thebrana repo.

| Command | What It Does |
|---------|-------------|
| `/apply-errata` | Applies pending doc 24 errors to affected spec docs |
| `/maintain-specs` | Full correction cycle: re-evaluate reflections, apply errata layer by layer, check doc 25 |
| `/re-evaluate-reflections` | Cross-checks reflection docs (08, 14) against dimension docs for gaps |
| `/refresh-knowledge` | Project-scoped version — refreshes enter dimension docs specifically |

## Skill Categories

**Knowledge lifecycle:** pattern-recall → retrospective → knowledge-review → cross-pollinate
**Build workflow:** build-phase → debrief → maintain-specs
**Task management:** tasks
**Quality:** challenge
**Project lifecycle:** project-onboard → project-retire
**Knowledge management:** knowledge → research → refresh-knowledge
**Spec maintenance:** refresh-knowledge → maintain-specs → apply-errata → re-evaluate-reflections
**Venture lifecycle:** venture-onboard → venture-align → venture-phase → growth-check → sop
**Venture operations:** morning → weekly-review → monthly-close → monthly-plan
**Venture growth:** pipeline → experiment → financial-model → content-plan
**Integrations:** gsheets
**Universal (work for both):** decide, debrief, challenge, retrospective, pattern-recall, cross-pollinate

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
