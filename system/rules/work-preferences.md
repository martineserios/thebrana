# Work Preferences

## Parallelism

Spawn sub-agents and work in parallel whenever possible. Maximize concurrency for independent tasks. Take care of dependencies and execution order.

## Subagent strategy

Deploy subagents frequently to preserve main context capacity. Delegate investigation, exploration, and concurrent analysis to specialized agents. One focus per subagent — don't overload a single agent with multiple unrelated tasks.

## Plan before building

Activate plan mode for non-trivial tasks involving 3+ steps or architectural choices. Plan verification phases, not just development. If issues arise mid-execution, halt and reassess the approach rather than pushing forward.

## Autonomous execution

Fix bugs directly — reference logs and failing tests, then implement the fix. Don't ask the user for procedural guidance on how to debug. Resolve failing CI/tests independently before reporting back.

## Simplicity

Keep things simple. No over-engineering, no unnecessary abstraction. When in doubt, fewer lines beats more lines.

## Automation through usage

New capabilities should embed as steps in existing frequently-used commands, not standalone commands the user must remember. When developing a new capability, ask "which existing command should trigger this?" before creating a standalone command.

Anti-pattern: creating useful capabilities as standalone commands nobody remembers to run.
