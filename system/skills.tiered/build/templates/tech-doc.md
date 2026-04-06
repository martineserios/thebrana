# Feature: {feature-name}

**Date:** {date}
**Task:** {task-id}
**Status:** shipped
**Branch:** {branch}

## Goal

{1-2 sentences: what problem this solves and why it matters.}

## Design Decisions

{Key choices made during SPECIFY/PLAN. Format as decision + rationale pairs:}

- **{Decision}** — {rationale}
- **{Decision}** — {rationale}

## Code Flow

{Entry points, key modules, data flow. How a request/action travels through the code:}

1. **Entry:** {where execution starts — command, hook, skill, API endpoint}
2. **Core:** {main logic — what modules/functions handle the work}
3. **Output:** {what gets produced — files, state changes, side effects}

### Key Files

| File | Role |
|------|------|
| {path} | {what it does} |

## API Surface

{Public interface — commands, functions, hooks, config options exposed to users or other modules. Omit if purely internal.}

## Testing

{What tests exist, what they cover, how to run them:}

```bash
{test command}
```

## Known Limitations

{What this doesn't do, edge cases, deferred items. Be honest — saves future debuggers time.}
