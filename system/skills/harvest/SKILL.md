---
name: harvest
description: "Extract post ideas from recent work through positioning lens"
group: content
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Glob
  - Grep
  - AskUserQuestion
---

# Harvest

Extract content ideas from recent work artifacts, filter through the positioning lens, and save human-picked seeds.

## Usage

`/brana:harvest [window]`

- Default: `7d` (last 7 days)
- Accepts: `3d`, `7d`, `14d`, `30d`, `session`
- `session` = current session's handoff only

## Procedure

### Step 1 — Load lens

Read `docs/content/lens.md`. If missing, abort with: "No lens file found. Create docs/content/lens.md first."

### Step 2 — Determine window

Parse `$ARGUMENTS`:
- If empty → default to `7d`
- If `session` → scope to current session handoff only
- Otherwise parse `Nd` format → compute `--since` date

Compute the cutoff date:
```
SINCE_DATE = today minus N days (format: YYYY-MM-DD)
```

### Step 3 — Gather artifacts

Collect from 5 sources within the window. Read-only — never modify sources.

**3a. Commits**
```bash
git log --oneline --since="$SINCE_DATE"
```

**3b. Session handoff**

Read `~/.claude/projects/-home-martineserios-enter-thebrana-thebrana/memory/session-handoff.md`. Extract entries within date range — look for date headers, "Accomplished" and "Learnings" sections.

**3c. ADRs (new or modified)**
```bash
git log --since="$SINCE_DATE" --name-only --diff-filter=AM -- "docs/architecture/decisions/"
```
Read each ADR found.

**3d. Event log**

Read `system/state/event-log.md`. Extract entries within date range.

**3e. Completed tasks**

Read `.claude/tasks.json`. Find tasks where `completed` falls within the window. Note their subject, description, and notes.

### Step 4 — Apply lens

For each notable artifact (skip trivial commits, chore tasks, doc formatting):

1. **Pillar match:** Which pillar does this map to? (Case Study / How-To / Contrarian / Build-in-Public)
2. **Dual test:** Would a founder care? Would a CTO care? Neither → skip.
3. **Anti-topic check:** Does it drift toward no-code/wrapper/generic territory? → Skip or note a reframe.
4. **Component match:** Does it touch a named component from the shelf? Note it.
5. **Angle:** What makes this a story? Draft a one-line hook.

Group candidates by pillar.

### Step 5 — Present candidates

Use AskUserQuestion to show the candidates:

```
## Harvest: [SINCE_DATE] → today

### Case Study
- [ ] [hook] — source: commit abc1234, ADR-017
- [ ] [hook] — source: session 2026-03-10

### How-To
- [ ] [hook] — source: completed task t-350

### Contrarian
- [ ] [hook] — source: event log entry

### Build-in-Public
- [ ] [hook] — source: ADR-018, 5 commits

Pick which ideas to save (comma-separated numbers, or "none"):
```

Present as a numbered list. User picks by number. No auto-saving.

### Step 6 — Write ideas

Read `docs/content/ideas.md` first. Then append selected ideas under today's date:

```markdown
## YYYY-MM-DD

### [seed] Hook title
- **Angle:** What makes this a story
- **Pillar:** Case Study
- **Sources:** commit abc1234, ADR-017, session 2026-03-10
```

**Cap enforcement:** Count active `[seed]` entries in the file. If adding new seeds would exceed 10:
- Mark oldest `[seed]` entries as `[expired]` until count is at or below 10
- Notify user which seeds expired

Report what was saved.

## Rules

- **Read-only on all sources.** Only writes to `docs/content/ideas.md`.
- **No lens = no harvest.** Abort if `docs/content/lens.md` doesn't exist.
- **Human picks the ideas.** Never auto-save. AskUserQuestion is the gate.
- **Ideas only.** No draft writing — that's future `/brana:content-draft` territory.
- **Graceful without ruflo.** All sources are local files and git.
- **Skip noise.** Merge commits, doc formatting, chore tasks, WIP commits — filter out.
