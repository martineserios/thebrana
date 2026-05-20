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

Smart daily pick ranked by initiative match + priority + effort + blocking depth.

```
brana backlog focus [--top <N>] [--json] [--work-type <TYPE>] [--initiative <SLUG>]
```

### Flags

| Flag | Default | Description |
|------|---------|-------------|
| `--top` | 3 | Number of tasks to show |
| `--json` | false | Output JSON array |
| `--work-type` | — | Filter by cognitive mode: implement, research, design, ops, review |
| `--initiative` | — | Override active initiative (defaults to tasks-config.json `active_initiative`) |

When `active_initiative` is set, focus shows ★-marked tasks from that initiative first, then P0/P1 overflow from other initiatives.

### Examples

```bash
brana backlog focus
brana backlog focus --top 5 --initiative cc-alignment
brana backlog focus --work-type implement
```

---

## brana backlog set active

Set the active initiative for the current session and beyond.

```
brana backlog set active <SLUG>
```

### Examples

```bash
brana backlog set active cc-alignment
brana backlog set active notebooklm
```

Writes `active_initiative` to `~/.claude/tasks-config.json`.

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
| `--initiative <SLUG>` | Filter by initiative slug (exact match) |

### Examples

```bash
brana backlog query --work-type implement --status pending
brana backlog query --initiative cc-alignment --priority P0
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
| `--initiative <SLUG>` | Assign to an initiative (e.g. "cc-alignment") |
| `--work-type <TYPE>` | Cognitive mode: implement, research, design, ops, review |

### Examples

```bash
brana backlog add --subject "wire new filter" --initiative cc-alignment --work-type implement --effort M
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
