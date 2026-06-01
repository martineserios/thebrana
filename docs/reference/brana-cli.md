# brana CLI Reference

The `brana` binary is the primary CLI for brana operations. Built in Rust at
`system/cli/rust/crates/brana-cli/`. Installed to `~/.local/bin/brana` via
`bootstrap.sh`.

Top-level subcommands: `backlog`, `skills`, `ops`, `doctor`, `validate`, `portfolio`,
`run`, `queue`, `agents`, `transcribe`, `files`, `version`.

---

## brana backlog triage-stale

Bulk-close pending tasks whose task ID appears as the **scope** of a
conventional commit (`feat(t-NNN):`, `fix(t-NNN):`) or as the branch name in a
merge commit (`merge(feat/t-NNN…):`) anywhere in `git log --all --oneline`.

Useful after a session where tasks were shipped without running `/brana:close`.

### Usage

```
brana backlog triage-stale [OPTIONS]
```

### Flags

| Flag | Default | Description |
|------|---------|-------------|
| `--dry-run` | false | Show matched tasks without closing anything |
| `--batch <N>` | 10 | Tasks to display per confirmation prompt |
| `--yes` | false | Close all matches without interactive prompts |
| `--git-dir <PATH>` | CWD | Override repo path for `git log` lookup |
| `--file <PATH>` | auto | Override path to `tasks.json` |

### Matching logic

Two patterns are recognised in commit subjects:

1. **Conventional commit scope** — `<type>(t-NNN):` where `<type>` contains no
   `/` (excludes branch-name false-positives like `docs(research/t-NNN)`).
2. **Merge commit** — `merge(feat/t-NNN…):` or `merge(fix/t-NNN…):`.

Casual task mentions (`closes t-NNN`, `see t-NNN`) are intentionally **not**
matched — only commits where the scope IS the task ID qualify.

### Interactive flow

1. Matched tasks are displayed in batches of `--batch` size.
2. Per batch: `[y/n/q]` prompt — yes closes the batch, no skips it, quit stops.
3. Each closed task gets `status: completed` and `completed: <today>` written to
   `tasks.json`.

### Examples

```bash
# Preview what would be closed (safe — no writes)
brana backlog triage-stale --dry-run

# Close all matches without prompting
brana backlog triage-stale --yes

# Triage a different repo's tasks
brana backlog triage-stale --git-dir ~/enter_thebrana/ventures/proyecto_anita

# Smaller batches for careful review
brana backlog triage-stale --batch 5
```

---

## brana backlog stale

List tasks that have been pending for longer than N days (no git correlation —
purely age-based).

```
brana backlog stale [--days <N>]   # default: 14
```

---

## brana backlog burndown

Created vs completed counts over time.

```
brana backlog burndown [--period week|month|day]
```

---

## brana backlog focus

Smart daily pick ranked by epic match + priority + effort + blocking depth.

```
brana backlog focus [--top <N>] [--json] [--work-type <TYPE>] [--epic <SLUG>]
```

### Flags

| Flag | Default | Description |
|------|---------|-------------|
| `--top` | 3 | Number of tasks to show |
| `--json` | false | Output JSON array |
| `--work-type` | — | Filter by cognitive mode: implement, research, design, ops, review |
| `--epic` | — | Override active epic (defaults to tasks-config.json `active_epic`) |

When `active_epic` is set, focus shows ★-marked tasks from that epic first, then P0/P1 overflow from other epics.

### Examples

```bash
brana backlog focus
brana backlog focus --top 5 --epic cc-alignment
brana backlog focus --work-type implement
```

---

## brana backlog set active

Set the active epic for the current session and beyond.

```
brana backlog set active <SLUG>
```

### Examples

```bash
brana backlog set active cc-alignment
brana backlog set active notebooklm
```

Writes `active_epic` to `~/.claude/tasks-config.json`.

---

## brana backlog query

Filter tasks with AND logic across multiple dimensions.

```
brana backlog query [OPTIONS]
```

### Flags (new in v3)

| Flag | Description |
|------|-------------|
| `--work-type <TYPE>` | Filter by cognitive mode: implement, research, design, ops, review |
| `--epic <SLUG>` | Filter by epic slug (exact match) |

### Examples

```bash
brana backlog query --work-type implement --status pending
brana backlog query --epic cc-alignment --priority P0
```

---

## brana backlog add

Add a new task from JSON or shorthand flags.

```
brana backlog add [OPTIONS]
```

### Flags (new in v3)

| Flag | Description |
|------|-------------|
| `--epic <SLUG>` | Assign to an epic (e.g. "cc-alignment") |
| `--work-type <TYPE>` | Cognitive mode: implement, research, design, ops, review |

### Examples

```bash
brana backlog add --subject "wire new filter" --epic cc-alignment --work-type implement --effort M
```

---

## brana skills list

List all installed skills (from `system/skills/` and `~/.claude/skills/`).

```
brana skills list [--human]
```

### Flags

| Flag | Default | Description |
|------|---------|-------------|
| `--human` | false | Human-readable grouped table instead of JSON |

### Output modes

**Default (JSON):** Array of objects with `name`, `description`, `effort`, `group`, `keywords`. `name` is `brana:`-prefixed (e.g. `"brana:close"`, `"brana:sitrep"`).

**`--human`:** Fixed-width table sorted by group → name within group. Blank line between groups. Columns:

```
GROUP  SKILL  DESCRIPTION  ARGS
```

- `DESCRIPTION` truncated to 48 chars with `…`
- `ARGS` shows the `argument-hint` field from `SKILL.md` frontmatter, or `—` if absent

### Examples

```bash
# Machine-readable (default)
brana skills list

# Grouped table for humans
brana skills list --human
```

## brana memory write

Write a memory entry routed by type and scope (ADR-038). Content containing a version claim is automatically stamped with the live tool version at write time.

### Usage

```bash
brana memory write --type <type> --scope <scope> --slug <slug> --content <content>
```

### Flags

| Flag | Required | Description |
|------|----------|-------------|
| `--type` | yes | Memory type: `feedback`, `project`, `user`, `pattern` |
| `--scope` | no (default: `project`) | `project` or `global` |
| `--slug` | yes | Kebab-case identifier (stable across sessions) |
| `--content` | yes | Memory content to write |

### Version-stamp injection

When `--content` contains a version-like pattern (`v` followed by a digit, e.g. `v3.5.1`) **and** mentions at least one brana ecosystem tool (`ruflo`, `brana`, or `claude`), the write path automatically appends a verified-version block:

```
---
**Verified at write time (YYYY-MM-DD):**
- `ruflo --version`: ruflo v3.6.30
```

The block reflects the live `--version` output at the moment of writing. If the tool is absent from PATH, the stamp notes "not found in PATH" rather than failing the write. Content without a version pattern, or with no known tool name, is written unchanged.

### Routing (ADR-038)

| Type | Scope | File |
|------|-------|------|
| `feedback` | `project` | `{project_memory}/feedback_{slug}_{ts}.md` (dated, parallel-safe) |
| `feedback` | `global` | `~/.claude/memory/feedback_{slug}_{ts}.md` |
| `project` | `project` | `{project_memory}/project_{slug}.md` (upsert) |
| `user` | `global` | `~/.claude/memory/user_{slug}.md` (upsert) |
| `pattern` | any | `~/.claude/memory/pattern_{slug}.md` (upsert) |

### Examples

```bash
# Write a project memory — version claim triggers live-stamp injection
brana memory write --type project --scope project \
  --slug ruflo-agentdb-status \
  --content "ruflo agentdb is currently at v3.5.1"
# → written file will contain live ruflo --version output

# Write feedback (global scope)
brana memory write --type feedback --scope global \
  --slug use-uv-for-python \
  --content "always use uv run python, never python3 directly"
```

## brana memory index

Regenerate `MEMORY.md` from the filesystem — picks the newest dated file per slug.

### Usage

```bash
brana memory index --scope <scope>
```

### Flags

| Flag | Default | Description |
|------|---------|-------------|
| `--scope` | `project` | `project` or `global` |

---

## brana knowledge ingest

Queue URLs into pipeline state (`pipeline-state.json`). Accepts direct URLs, file paths
(URL lists, WhatsApp exports, any plain text), or stdin. Extracts all `https://`/`http://`
URLs from text input. Skips duplicates already in state.

### Usage

```bash
# Direct URLs
brana knowledge ingest https://example.com https://other.com

# File with URL list (or any text containing URLs)
brana knowledge ingest inbox/dump.txt

# Stdin
cat urls.txt | brana knowledge ingest
```

### Flags

| Flag | Default | Description |
|------|---------|-------------|
| `--source <tag>` | — | Tag all ingested URLs with a source label (e.g. `telegram`) |
| `--dry-run` | false | Extract and report URLs without writing state |

### Output

```
  brana knowledge ingest
  3 URL(s) extracted

  ✓ 2 new URL(s) queued
  · 1 duplicate(s) skipped

  Next: brana knowledge process --status
```

---

## brana knowledge next

Emit the single next pipeline command to run. Pure read — never modifies state.

Priority order (first match wins):
1. `unprocessed > 0` → `brana knowledge process --tier1`
2. `tier1_passed > 0` → `brana knowledge process --tier2`
3. drafts on disk → `brana knowledge promote <path>`
4. `tier2_clustered > 0` (no drafts) → `brana knowledge process --report`
5. all current → `brana knowledge ingest <url>`

### Usage

```bash
brana knowledge next
```

### Examples

```bash
# Shows exactly one command to copy-paste
$ brana knowledge next
brana knowledge process --tier1

$ brana knowledge next
brana knowledge promote brana-knowledge/drafts/2026-05-24-agent-tooling.md
```

---

## brana knowledge process

Run a pipeline stage: tier1 relevance filter, tier2 clustering, or generate cluster report.
Requires `agy` CLI (`npm install -g agy`) for LLM calls.

### Usage

```bash
brana knowledge process --tier1          # score URLs 1-5, filter below threshold
brana knowledge process --tier2          # cluster tier1-passed URLs into topics
brana knowledge process --report         # generate dimension draft from clusters
brana knowledge process --status         # print pipeline state summary (no writes)
```

### Tier1 behavior (parallel)

Tier1 runs up to **5 concurrent workers** against the agy Gemini Flash CLI. Each URL is
scored 1–5 for relevance to brana's known dimension topics (AI systems, agent design,
developer tooling, knowledge management). URLs scoring ≥ 3 are promoted to `tier1_passed`.

- **Checkpoint saves** after every URL — a crash or timeout mid-batch does not lose work.
- **Version check** — runs `agy --version` once before spawning workers; fails fast if the
  installed version doesn't match the pinned constraint.
- **Platform tagging** — each entry is tagged with its detected platform (linkedin, github,
  arxiv, youtube, etc.).
- **Batch cap**: 50 URLs per run. Run again if the queue is larger.

### Flags

| Flag | Default | Description |
|------|---------|-------------|
| `--dry-run` | false | Show what would be scored without calling agy or writing state |
| `--tier1` | — | Run Tier1 relevance filter |
| `--tier2` | — | Run Tier2 clustering |
| `--report` | — | Generate cluster report / dimension drafts |
| `--status` | — | Print pipeline state counts |

---

## brana knowledge run

Auto-advance tier1 and tier2 automatically; stops at human gates (cluster report, draft
review). Reads `pipeline-state.json`, auto-runs scored steps, and emits the gate message
when a judgment call is needed.

### Usage

```bash
brana knowledge run
```

### Behavior

- If `unprocessed > 0`: runs tier1, then checks again. If tier1 passes yield tier2-ready items, runs tier2 immediately, then stops at the cluster report gate.
- If `tier1_passed > 0` (and no unprocessed): runs tier2 only, then stops at gate.
- If already at a human gate: prints the gate message and exits without running anything.

### Human gates (stops here)

| Gate | Message |
|------|---------|
| Cluster report ready | `brana knowledge process --report` |
| Draft ready for review | `brana knowledge promote <path>` |
| Pipeline idle | `brana knowledge ingest <url>` |

---

## brana session

Unified session state management. Subcommands: `write`, `read`, `history`, `path`,
`migrate`, `mark-consumed`, `insights`, `initiative`.

---

## brana session initiative

Initiative accumulator — merge, read, or archive cross-day initiative state. An
initiative accumulator aggregates `accomplished[]`, `next[]`, and `resolved[]` items
across multiple sessions that share the same initiative slug.

### Subcommands

#### upsert

Merge current session state into the named initiative accumulator. Runs Pass 1 pruning:
task IDs supplied via `--completed` are moved from `next[]` to `resolved[]` with a
`"task completed"` note.

```bash
brana session initiative upsert <SLUG> [--completed <TASK_IDS>] [--resolved-texts <JSON>]
```

| Argument / Flag | Required | Description |
|-----------------|----------|-------------|
| `<SLUG>` | yes | Kebab-case initiative identifier (e.g. `"session-continuity"`) |
| `--completed` | no | Comma-separated task IDs completed this session — Pass 1 pruning (default: `""`) |
| `--resolved-texts` | no | JSON array of Pass 2 resolved text items: `'[{"text":"...","resolution":"..."}]'` (default: `"[]"`) |

#### read

Print the current initiative accumulator for a slug.

```bash
brana session initiative read <SLUG> [--json]
```

| Flag | Description |
|------|-------------|
| `--json` | Output raw JSON instead of formatted text |

#### archive

Archive the initiative accumulator (move to `archive/` with datestamp). Use when an
initiative is fully complete.

```bash
brana session initiative archive <SLUG>
```

#### read-marker

Read the session-start marker written by `brana run`. Outputs the initiative slug, or
empty string if no marker exists. Used by close Step 9c Tier 1 and sitrep Step 4b.

```bash
brana session initiative read-marker
```

#### clear-marker

Delete the session-start marker. Called by close Step 9c after the slug is consumed.

```bash
brana session initiative clear-marker
```

### Examples

```bash
# Upsert at close — merge this session into "session-continuity" initiative
brana session initiative upsert session-continuity --completed t-1461,t-1683

# Read initiative state (human-readable)
brana session initiative read session-continuity

# Read initiative state as JSON (used by sitrep.md §4b)
brana session initiative read session-continuity --json

# Archive when initiative is complete
brana session initiative archive session-continuity

# Read session-start marker (written by brana run, used by close Tier 1)
brana session initiative read-marker

# Clear marker after consuming the slug at close
brana session initiative clear-marker
```
