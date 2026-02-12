# Work Preferences

## Parallelism

Spawn sub-agents and work in parallel whenever possible. Maximize concurrency for independent tasks. Take care of dependencies and execution order.

## Simplicity

Keep things simple. No over-engineering, no unnecessary abstraction. When in doubt, fewer lines beats more lines.

## Automation through usage

New capabilities should embed as steps in existing frequently-used commands, not standalone commands the user must remember. When developing a new capability, ask "which existing command should trigger this?" before creating a standalone command.

Anti-pattern: creating useful capabilities as standalone commands nobody remembers to run.
