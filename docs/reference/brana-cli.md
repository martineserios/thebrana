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

**Default (JSON):** Array of objects with `name`, `description`, `effort`, `group`, `keywords`.

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
