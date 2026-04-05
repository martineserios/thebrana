---
depends_on:
  - docs/architecture/features/cli-composable-tool.md
---
# t-527: Add --limit and filter flags to backlog next

## Problem
`brana backlog next` hardcodes 3 results and lacks --priority, --type, --effort, --parent filters.

## Solution
Add --limit N (default 5) and filter flags to the next subcommand.
