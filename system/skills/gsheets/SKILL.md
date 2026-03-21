---
name: gsheets
description: "Google Sheets via MCP — read, write, create, list, share spreadsheets. Use when reading, writing, or managing Google Sheets data."
effort: low
keywords: [google-sheets, spreadsheet, csv, data, read, write, mcp]
task_strategies: [feature, spike]
stream_affinity: [roadmap, research]
argument-hint: "[list|read|write|create|summary|share] [args]"
group: utility
status: stable
growth_stage: evergreen
---

# Google Sheets — MCP Operations

Direct interface to Google Sheets via MCP. Read, write, create, and manage spreadsheets with performance-optimal tool usage.

## When to use

- User wants to read, write, or manage Google Sheets
- Another skill needs Sheets access (growth-check, pipeline, financial-model, morning, monthly-close)
- Discovering what spreadsheets exist
- Creating or sharing a new spreadsheet

## Usage

`/brana:gsheets [action] [args...]`

Actions:
- `/brana:gsheets list` — list spreadsheets or folders
- `/brana:gsheets read <spreadsheet> [sheet] [range]` — read data
- `/brana:gsheets write <spreadsheet> <sheet> <range>` — update data
- `/brana:gsheets create <title>` — create new spreadsheet
- `/brana:gsheets summary <spreadsheet>` — quick overview (sheets, headers, row counts)
- `/brana:gsheets share <spreadsheet> <email> [role]` — share access
- `/brana:gsheets` (no args) — ask user what they need

---

## Step 1: Check MCP Availability

Use `ToolSearch` to probe for `mcp__google-sheets__*` tools:

```
ToolSearch query: "+google-sheets list"
```

If no `mcp__google-sheets__*` tools are found:
- Tell the user: "Google Sheets MCP is not configured."
- Point to setup guide: `thebrana/docs/google-sheets-mcp-setup.md`
- Stop here.

If tools are found, load the ones needed for the requested action and proceed.

---

## Step 2: Route Action

Parse `$ARGUMENTS` to determine the action. If no arguments, ask the user what they need.

### `list` — Discover Spreadsheets

```
ToolSearch query: "+google-sheets list"
```

- Use `mcp__google-sheets__list_spreadsheets` to show recent spreadsheets
- Use `mcp__google-sheets__list_folders` to browse by folder
- Present results as a table: Title | ID | Last Modified

### `read <spreadsheet> [sheet] [range]` — Read Data

```
ToolSearch query: "+google-sheets get_sheet"
```

- If only spreadsheet given: use `mcp__google-sheets__list_sheets` to show available sheets, then ask which one
- If sheet given but no range: use `mcp__google-sheets__get_sheet_data` with a sensible default range (A1:Z1 for headers, then A1:Z100 for data preview)
- If full range given: use `mcp__google-sheets__get_sheet_data` with the exact range
- For cross-sheet reads: use `mcp__google-sheets__get_multiple_sheet_data` in a single call

### `write <spreadsheet> <sheet> <range>` — Update Data

```
ToolSearch query: "+google-sheets update"
```

- **Always confirm with the user before writing.** Show what will be written and where.
- For a single range: use `mcp__google-sheets__update_cells`
- For multiple ranges: use `mcp__google-sheets__batch_update_cells` in a single call
- For adding rows at the end: use `mcp__google-sheets__add_rows`
- For adding columns: use `mcp__google-sheets__add_columns`
- For structural changes (formatting, dimensions, conditional formatting): use `mcp__google-sheets__batch_update`

### `create <title>` — Create Spreadsheet

```
ToolSearch query: "+google-sheets create"
```

- Use `mcp__google-sheets__create_spreadsheet` with the given title
- If the user specifies sheets to add: use `mcp__google-sheets__create_sheet` for each additional sheet
- Return the spreadsheet URL after creation

### `summary <spreadsheet>` — Quick Overview

```
ToolSearch query: "+google-sheets summary"
```

- Use `mcp__google-sheets__get_multiple_spreadsheet_summary` (works for one or many)
- Show: spreadsheet title, sheet names, row/column counts
- For a deeper look: read A1:Z1 from each sheet to show column headers

### `share <spreadsheet> <email> [role]` — Share Access

```
ToolSearch query: "+google-sheets share"
```

- Default role: `reader` if not specified
- Use `mcp__google-sheets__share_spreadsheet`
- Confirm with user before sharing

---

## Step 3: Performance Rules

These rules apply to ALL Sheets operations, whether invoked via `/brana:gsheets` or by other skills.

1. **Always specify a range when reading.** Never fetch an entire sheet unless the user explicitly asks for all data. Default to reading headers (row 1) first, then expand as needed.

2. **Never set `include_grid_data: true`** unless the user specifically asks about formatting, colors, or cell styles. Grid data inflates response tokens dramatically.

3. **Batch over individual.** Use `batch_update_cells` for writing to multiple ranges — never loop `update_cells` cell-by-cell or range-by-range.

4. **Use `get_multiple_sheet_data`** when reading from 2+ sheets in the same spreadsheet. One call, not N calls.

5. **Use `get_multiple_spreadsheet_summary`** for discovery and overview. It returns structure without data — much cheaper than reading actual cell contents.

6. **Use `batch_update`** for structural changes (formatting, conditional formatting, column dimensions, merges). Don't mix structural operations with data writes.

7. **Use `add_rows` for appending** — don't calculate the next empty row manually and then use `update_cells`.

8. **Prefer `list_sheets` before `get_sheet_data`** when the user hasn't specified which sheet to read. Don't guess sheet names.

---

## Step 4: Output Conventions

- **Render data as markdown tables.** Format sheet data into readable tables with headers.
- **Show spreadsheet URLs** after create, share, or any operation where the user might want to open the sheet.
- **Confirm writes.** After a successful write, summarize what was written and where (sheet, range, row count).
- **Truncate large datasets.** If reading returns more than 50 rows, show the first 20 and tell the user how many more exist. Ask if they want the full dataset.

---

## Rules

- **Never write or overwrite without user confirmation.** Always show what will change before executing writes.
- **Performance-first.** Batch over individual, ranges over full sheets, summaries over full reads. Follow Step 3 strictly.
- **Reuse known spreadsheet IDs.** If a spreadsheet ID is referenced in `docs/venture/`, `.claude/CLAUDE.md`, or `docs/pipeline/`, use it directly — don't ask the user to provide it again.
- **Graceful degradation.** If MCP is unavailable, say so clearly and stop. Don't attempt workarounds.
- **No fabricated data.** If a read returns empty cells or errors, report exactly what happened. Never fill in guessed values.
- **Ask for clarification.** If the spreadsheet name is ambiguous, the range is unclear, or the action could affect important data — ask before acting.
