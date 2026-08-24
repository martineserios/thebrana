---
always-load: true
---
# Work Preferences

## Parallelism

Spawn sub-agents and work in parallel when tasks are independent; respect dependencies and ordering.

## Subagent strategy

Delegate investigation, exploration, and concurrent analysis to specialized agents to preserve main context. One focus per subagent.

## Plan before building

Use plan mode for non-trivial tasks (3+ steps or architectural choices). Plan verification phases, not just development. Halt and reassess if issues arise mid-execution — don't push forward.

## Autonomous execution

Fix bugs directly — reference logs and failing tests, then implement. Don't ask for debugging guidance; resolve failing CI/tests independently before reporting back.

## Simplicity

Keep things simple. No over-engineering, no unnecessary abstraction. When in doubt, fewer lines beats more.

## Automation through usage

New capabilities embed as steps in existing frequently-used commands, not standalone commands nobody remembers to run. Ask "which existing command should trigger this?" before adding a new one.

## Terminal diagrams

Structural answers (architecture, flow, hierarchy, comparison) get an inline box-drawing diagram, not prose alone — see system/skills/terminal-diagrams/SKILL.md.
