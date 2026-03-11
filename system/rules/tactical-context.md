# Tactical Context

## When giving task-relevant advice

After giving actionable advice that relates to a pending or in-progress task — even if the user didn't mention a task ID — persist it to the task's `context` field.

## How it works

1. **Detect tactical advice.** You just said something actionable: a suggestion, a workaround, a "do X and Y together", a constraint, a deadline, a dependency insight. Not every response qualifies — only concrete, reusable guidance that would help the next session working on that task.

2. **Match to tasks.** Read the current project's `.claude/tasks.json`. Find related tasks by:
   - **Explicit ID**: user or you mentioned `t-NNN` → direct match
   - **Keyword overlap**: significant nouns from the advice appear in a task's subject/description/tags
   - **Tag overlap**: `#tags` in the conversation match task tags
   - **Active context**: if you're currently working on a task (in_progress with matching branch), that task is the default target

3. **Decide action:**
   - **Single confident match** → auto-append silently
   - **Multiple candidates** → suggest: "Append this to t-XXX (subject) or t-YYY (subject)?" via AskUserQuestion
   - **No match** → don't force it. The advice lives in the conversation and session handoff.

4. **Append format.** Use the existing `context` field:
   ```
   YYYY-MM-DD: <advice text, 1-2 lines max>
   ```
   If `context` is null, set it. If it exists, append with a newline separator.

5. **Scope: current project only.** Read tasks.json from CWD's project. Don't cross-reference other clients' tasks — that's `/brana:backlog status --all` territory.

## What qualifies as tactical advice

- "Cover t-024, t-025, and t-026 in one visit"
- "Ask Martin for the legal docs while you're there"
- "The pixel needs to be in the BM, not the personal account"
- "Use railway.com instead of Hetzner for this — cheaper for the scale"
- "This blocks the deploy — fix before Friday"

## What does NOT qualify

- Generic programming advice ("use async/await here")
- Responses to direct questions ("the file is at src/utils.ts")
- Status updates ("tests pass, 3 files changed")
- Explanations of existing code

## Rules

- **Silent when confident.** Single match → append without asking. Report inline: `(appended to t-XXX context)`
- **Ask when ambiguous.** Multiple candidates → AskUserQuestion with task subjects
- **Never fabricate.** Only append advice that was actually given in this conversation turn
- **Respect project boundaries.** Only match tasks in the current project's tasks.json
- **Keep it short.** 1-2 lines per append. Strip conversational filler. The context field is for quick reference, not transcripts
- **Don't duplicate.** Read existing context first. If the same advice is already there, skip
