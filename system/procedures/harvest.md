
# Harvest

Extract content ideas from recent work artifacts, filter through the positioning lens, and save seeds.

## Usage

`/brana:harvest [window] [--auto]`

- Default: `7d` (last 7 days)
- Accepts: `3d`, `7d`, `14d`, `30d`, `session`
- `session` = current session's handoff only
- `--auto` = skip human gate, write all lens-passing seeds directly (for scheduled runs)

## Procedure

### Step 1 — Load lens

Read `docs/content/lens.md`. If missing, abort with: "No lens file found. Create docs/content/lens.md first."

### Step 2 — Determine window and mode

Parse `$ARGUMENTS`:
- If empty → default to `7d`
- If `session` → scope to current session handoff only
- Otherwise parse `Nd` format → compute `--since` date
- If `--auto` present → set AUTO_MODE=true (skip Step 5 human gate)

Compute the cutoff date:
```
SINCE_DATE = today minus N days (format: YYYY-MM-DD)
```

### Step 3 — Gather artifacts

Collect from sources within the window. Read-only — never modify sources.

#### 3a. Cross-project session handoffs (primary source)

Glob all project handoffs:
```bash
ls ~/.claude/projects/*/memory/session-handoff.md 2>/dev/null
```

For each handoff found, extract entries within date range — look for date headers, "Accomplished" and "Learnings" sections. Tag each finding with the project name (derived from directory slug).

#### 3b. Cross-project git logs

Read `~/.claude/memory/portfolio.md` to get repo paths for each client. For each repo that exists:
```bash
git -C "$REPO_PATH" log --oneline --since="$SINCE_DATE" 2>/dev/null
```

#### 3c. Cross-project ADRs (new or modified)

For each repo from portfolio.md, check both common ADR locations:
```bash
git -C "$REPO_PATH" log --since="$SINCE_DATE" --name-only --diff-filter=AM -- "docs/decisions/" "docs/architecture/decisions/" 2>/dev/null
```
Read each ADR found.

#### 3d. Cross-project completed tasks

For each repo from portfolio.md, check for tasks.json:
```bash
cat "$REPO_PATH/.claude/tasks.json" 2>/dev/null
```
Find tasks where `completed` falls within the window.

#### 3e. Thebrana-specific sources

These only apply when scanning the thebrana repo:
- Event log: `system/state/event-log.md` — entries within date range
- Errata: `docs/24-roadmap-corrections.md` — new entries within date range

#### 3f. Evergreen fallback

If Steps 3a-3e produced **zero notable artifacts** (nothing fresh this week):

1. Scan ruflo patterns with high confidence:
   ```bash
   source "$HOME/.claude/scripts/cf-env.sh" 2>/dev/null
   $CF memory search --query "pattern transferable" --namespace pattern --limit 10 2>/dev/null
   ```
   Fallback (no ruflo): grep `~/.claude/projects/*/memory/MEMORY.md` for pattern entries.

2. Scan errata doc for content-worthy entries never used as seeds:
   ```bash
   grep -c "\[seed\]" docs/content/ideas.md  # count existing seeds
   ```
   Read `docs/24-roadmap-corrections.md`, find entries with status `applied` that don't appear as sources in `ideas.md`.

3. Tag all evergreen candidates with `[evergreen]` in the angle field so the user knows these aren't fresh.

### Step 4 — Apply lens

For each notable artifact (skip trivial commits, chore tasks, doc formatting):

1. **Pillar match:** Which pillar does this map to? (Case Study / How-To / Contrarian / Build-in-Public)
2. **Dual test:** Would a founder care? Would a CTO care? Neither → skip.
3. **Anti-topic check:** Does it drift toward no-code/wrapper/generic territory? → Skip or note a reframe.
4. **Component match:** Does it touch a named component from the shelf? Note it.
5. **Systems pattern match:** Read the Systems Vocabulary section in `docs/content/lens.md`. Check both classical patterns (feedback loop, stocks/flows, delays, emergence, leverage point, adaptive cycle, resilience, isomorphism, quorum sensing, stigmergy) and agent-era patterns from [dim 49](../../../../brana-knowledge/dimensions/49-agent-era-systems-patterns.md) (assumption decay, artifact coordination, context rot, observation window, removable gate, pattern bleed, capability horizon). If a match is found, note it in the seed's **Systems** field. If no match, the seed stands on its own.
6. **Cross-domain check:** Does the same pattern appear in a different project within this harvest window? If so, flag it as a "same pattern, different skin" candidate — strongest content angle.
7. **Angle:** What makes this a story? Draft a one-line hook. If a systems pattern was identified, weave it into the hook naturally (never explain the term, just use it).

**Target:** ~50% of seeds should have a systems connection. Not forced — discovered.

Group candidates by pillar.

### Step 5 — Present candidates

**If AUTO_MODE:** Skip to Step 6 with all lens-passing candidates selected.

**If interactive (default):** Use AskUserQuestion to show the candidates:

```
## Harvest: [SINCE_DATE] → today

### Case Study
- [ ] [hook] — source: commit abc1234, ADR-017 (project: acme_corp)
- [ ] [hook] — source: session 2026-03-10 (project: my_project)

### How-To
- [ ] [hook] — source: completed task t-350 (project: thebrana)

### Contrarian
- [ ] [hook] — source: event log entry (project: thebrana)

### Build-in-Public
- [ ] [hook] — source: ADR-018, 5 commits (project: thebrana)

Pick which ideas to save (comma-separated numbers, or "none"):
```

Present as a numbered list. User picks by number. No auto-saving in interactive mode.

### Step 6 — Write ideas

Read `docs/content/ideas.md` first. Then append selected ideas under today's date:

```markdown
## YYYY-MM-DD

### [seed] Hook title
- **Angle:** What makes this a story
- **Pillar:** Case Study
- **Components:** "The silent bottleneck"
- **Systems:** feedback loop — output feeds back as input (omit if no pattern found)
- **Sources:** commit abc1234, ADR-017, session 2026-03-10 (acme_corp)
```

**Cap enforcement:** Count active `[seed]` entries in the file. If adding new seeds would exceed 10:
- Mark oldest `[seed]` entries as `[expired]` until count is at or below 10
- In auto mode: log which seeds expired
- In interactive mode: notify user which seeds expired

Report what was saved.

## Rules

- **Read-only on all sources.** Only writes to `docs/content/ideas.md`.
- **No lens = no harvest.** Abort if `docs/content/lens.md` doesn't exist.
- **Interactive mode: human picks.** AskUserQuestion is the gate.
- **Auto mode: lens is the gate.** All lens-passing candidates are saved directly.
- **Ideas only.** No draft writing — that's future `/brana:content-draft` territory.
- **Graceful without ruflo.** All sources are local files and git. Ruflo is optional enhancement.
- **Skip noise.** Merge commits, doc formatting, chore tasks, WIP commits — filter out.
- **Cross-project by default.** Always scan all projects via handoff glob + portfolio.md.
