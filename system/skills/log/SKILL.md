---
name: log
description: "Capture events — links, calls, meetings, ideas, observations — into a searchable append-only log. Includes bulk mode for WhatsApp dumps and URL-to-task promotion. Use when something happened and you want to capture it quickly."
effort: low
keywords: [logging, events, capture, meetings, links, observations, whatsapp, bulk]
task_strategies: [feature, spike]
stream_affinity: [roadmap, docs]
argument-hint: "[event text or bulk]"
group: capture
model: haiku
allowed-tools:
  - Read
  - Write
  - Edit
  - Glob
  - Grep
  - Bash
  - AskUserQuestion
status: stable
growth_stage: evergreen
---

# Log — Event Capture

Append-only event log. The lowest-friction entry point into brana — no need to know tasks.json schema, pipeline stages, or memory conventions. Just `/brana:log "something happened"`.

## When to use

- Something happened (call, meeting, idea, observation) and you want to record it
- You received links or references to capture for later
- Pasting a WhatsApp or chat dump to triage
- Anything that doesn't fit `/brana:backlog add` (not a commitment yet) or `/brana:pipeline` (not a qualified lead yet)

## Commands

```
/brana:log "text with optional #tags"     — quick append
/brana:log bulk                           — paste multi-line content, parse + deduplicate
```

## File

Per-project log with global fallback.

### Resolution order

1. **CWD project**: `git rev-parse --show-toplevel` → basename → find matching CC project memory dir → `{dir}/event-log.md`
2. **Tag routing**: if entry has `#projectslug` matching a registered project in `tasks-portfolio.json`, route to that project's log
3. **Global fallback**: `~/.claude/memory/event-log.md` — when no project context is detected

### Finding the CC project memory dir

```
~/.claude/projects/-{sanitized-path}/memory/event-log.md
```

Where `sanitized-path` is the absolute project path with `/` replaced by `-` and leading `-`. Example: project at `/home/user/enter_thebrana/thebrana` → `~/.claude/projects/-home-user-enter-thebrana-thebrana/memory/event-log.md`.

Create the file on first use if it doesn't exist.

---

## /brana:log "text"

Quick append — the default mode.

### Steps

1. **Parse input.** Extract the quoted text from the argument.

2. **Extract tags.** Find all `#word` tokens in the text. Remove the `#` prefix and collect as tags. Leave the `#tag` inline in the entry text — tags are visible, not hidden metadata.

3. **Resolve the log file** using the resolution order above (CWD project → tag routing → global fallback). Read it.
   - If it doesn't exist, create it with a header:
     ```markdown
     # Event Log
     ```

4. **Find or create today's section.** Look for a `## YYYY-MM-DD` heading matching today's date.
   - If it exists, append after the last entry under that heading.
   - If it doesn't exist, append a new section at the bottom of the file:
     ```markdown

     ## YYYY-MM-DD
     ```

5. **Format the entry.** Use this template:
   ```
   - HH:MM — {text}
   ```
   Timestamp is current time (24h format). The text is verbatim from the user's input (including inline #tags).

6. **URL detection.** If the text contains one or more `https://` URLs:
   - Read the current project's `.claude/tasks.json` (if it exists) and the portfolio's tasks files
   - Check if any URL already exists in a research task's description, context, or notes
   - For each **new** URL (not already in any task):
     - Use AskUserQuestion: "Found {N} new URL(s). Create research tasks?"
       - Options: "Yes — create tasks", "No — just log"
     - If yes: for each URL, run `/brana:backlog add` with stream=research, the URL in context, and tags from the log entry
   - For URLs that already exist in tasks: note "(already tracked as {task-id})" silently in the log entry

7. **Write the entry** using the Edit tool (append to the day section).

8. **Archival check.** Count total lines in the file.
   - If >500 lines: identify entries older than 90 days
   - Move them to `~/.claude/memory/event-log-archive-YYYY.md` (year of the oldest moved entry)
   - Use AskUserQuestion to confirm before archiving: "Log has {N} lines. Archive {M} entries older than 90 days?"

9. **Report.** Confirm the entry was logged:
   ```
   Logged: "text" [#tag1, #tag2] at HH:MM
   ```

### Example

User: `/brana:log "Call with Juan from Kapso — interested in automation for their onboarding flow #somos #call"`

Result in `~/.claude/memory/event-log.md`:
```markdown
## 2026-03-07

- 14:32 — Call with Juan from Kapso — interested in automation for their onboarding flow #somos #call
```

Report: `Logged: "Call with Juan from Kapso..." [#somos, #call] at 14:32`

---

## /brana:log bulk

Paste and parse multiple entries at once — designed for WhatsApp dumps, meeting notes, or batched captures.

### Steps

1. **Prompt for content.** Use AskUserQuestion:
   ```
   question: "Paste the content to log (WhatsApp dump, meeting notes, etc.)"
   options: ["Ready — I'll paste below"]
   allowFreeText: true
   ```

   The user pastes multi-line text.

2. **Parse entries.** Split on line boundaries. For each line:
   - Strip WhatsApp metadata (timestamps like `[DD/MM/YY, HH:MM:SS]`, sender names before `:`)
   - Strip empty lines and media placeholders (`<Media omitted>`, `image omitted`, etc.)
   - Keep the content text
   - Extract any inline `#tags`
   - Detect URLs

3. **Deduplicate.** Read the existing log file. For each parsed entry:
   - Check if the same text (fuzzy: ignore whitespace, case) already exists in the log
   - Mark duplicates for exclusion

4. **URL cross-reference.** For entries containing URLs:
   - Read tasks.json files (current project + portfolio)
   - Check if each URL already exists in a research task
   - Mark as "already tracked" or "new"

5. **Present for confirmation.** Use AskUserQuestion with a summary:
   ```
   question: "Parsed {total} entries from your paste. {new} new, {dupes} duplicates (skipped), {urls_new} new URLs."
   options: ["Confirm — log all new entries", "Edit — let me adjust", "Cancel"]
   ```

   If "Edit": ask which entries to exclude or modify, then re-present.

6. **Write entries.** For each confirmed new entry:
   - Format as `- HH:MM — {text}` under today's date section
   - Use the original timestamp from the paste if available, otherwise use current time

7. **URL task creation.** If new URLs were found:
   - Use AskUserQuestion: "Create research tasks for {N} new URLs?"
     - Options: list each URL with a checkbox-style selection
   - For confirmed URLs: run `/brana:backlog add` with stream=research

8. **Report.**
   ```
   Bulk log complete:
     {N} entries logged
     {M} duplicates skipped
     {K} research tasks created
   ```

---

## Rules

- **Append-only.** Never edit or delete existing entries. The log is a historical record.
- **CWD first, tags second.** Route by project (CWD), fall back to `#tag` matching, then global. Works from anywhere — global log catches entries with no project context.
- **No auto-detection.** Don't try to classify entries as "call", "meeting", "idea" automatically. The user adds `#call`, `#meeting`, `#idea` if they want to categorize.
- **Confirm URLs.** Never silently create tasks from URLs. Always ask first via AskUserQuestion.
- **Chronological within each day.** New entries go at the bottom of the day's section.
- **Per-project files.** Each project gets its own `event-log.md` in its CC memory dir. Tags still provide cross-project filtering (grep across all logs).
- **Archival is conservative.** Only archive entries >90 days old, only when the file exceeds 500 lines, and only after user confirms.

## What /brana:log is NOT

- Not a replacement for `/brana:backlog add` — tasks are commitments, log entries are observations
- Not a replacement for MEMORY.md — memory stores patterns, log stores events
- Not a replacement for `/brana:pipeline` — pipeline tracks deals, log captures first contact
- Not a calendar, reminder system, or analytics tool

The log is an **inbox**. Other commands are the **outbox**. Capture fast, route later.
