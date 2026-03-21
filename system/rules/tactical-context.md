# Tactical Context

After giving actionable advice related to a task (workaround, constraint, deadline, dependency, "do X and Y together"), persist it to the task's `context` field via `brana backlog set <id> context --append "note"`.

## Matching

- **Explicit ID** (user/you mentioned t-NNN) → direct match
- **Keyword/tag overlap** with task subject/description/tags → match
- **Active task** (in_progress with matching branch) → default target

## Actions

- **Single match** → auto-append silently, report inline: `(appended to t-XXX context)`
- **Multiple candidates** → AskUserQuestion with task subjects
- **No match** → skip. Advice lives in conversation/handoff.

## Scope

Format: `YYYY-MM-DD: <1-2 lines>`. Current project only. Don't duplicate existing context. Don't append generic programming advice, status updates, or code explanations.
