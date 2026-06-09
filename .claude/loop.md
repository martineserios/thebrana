# brana Maintenance Loop

Autonomous maintenance mode for the thebrana system repo. Each iteration performs
a health sweep and surfaces repair actions without auto-executing risky operations.

Prefer finding and reporting over fixing. Surface blockers that cleared. Flag drift.
Don't commit, merge, or delete without explicit user approval.

---

## Per-Iteration Checklist

Run each section sequentially. Collect all findings before reporting.

### 1. Git Health

```bash
# Branches merged to main that can be deleted
git branch --merged main | grep -v "^\* \|^  main$"

# Stale worktrees
git worktree list

# Unexpected uncommitted changes
git status --short
```

Flag: merged branches, stale worktrees, untracked files in system/ or docs/.

### 2. Backlog Health

```bash
# Tasks pending > 21 days
brana backlog stale --days 21

# Tasks stuck in_progress
brana backlog query --status in_progress --output json

# Blocked tasks whose blockers may have resolved
brana backlog blocked
```

For each in_progress task: check if `started` date is > 7 days ago — flag as stale if so.
For each blocked task: check if all `blocked_by` IDs are now `completed` — surface as "ready to unblock".

### 3. Reconcile Check (dry-run only)

```bash
brana reconcile --scope consistency --dry-run 2>/dev/null || true
```

Report drift signals. Never apply changes in autonomous mode.

### 4. Doc Drift Signals

```bash
# Recent system/ changes
git log --oneline -20 -- system/

# Check for system/ changes without docs/ counterpart in same commit
git log --oneline -10 --diff-filter=M -- system/skills/ system/hooks/ system/rules/
```

Flag commits that touch `system/skills/`, `system/hooks/`, or `system/rules/` without
a corresponding `docs/` change in the same commit. These may represent undocumented
behavioral changes.

### 5. Knowledge Hygiene

```bash
# MEMORY.md line count (truncates at 200 in context)
wc -l ~/.claude/projects/-home-martineserios-enter-thebrana-thebrana/memory/MEMORY.md

# Memory files referenced in MEMORY.md that no longer exist
grep -oP '\[.*?\]\(\K[^)]+' ~/.claude/projects/-home-martineserios-enter-thebrana-thebrana/memory/MEMORY.md \
  | while read f; do
      [ -f "$(dirname ~/.claude/projects/-home-martineserios-enter-thebrana-thebrana/memory/MEMORY.md)/$f" ] || echo "MISSING: $f"
    done
```

Flag: MEMORY.md > 180 lines (approaching truncation), missing memory files.

> **Trimming entries requires two steps** — `mcp__brana__memory_index` rescans the filesystem at every session start and re-adds any `.md` file present in the memory directory. Removing only the index line is a no-op reversed on the next startup. To truly remove an entry: (1) `rm` the `.md` file from disk, then (2) remove the index line from MEMORY.md. (E2026-06-08-2)

### 6. Intelligence Feed

```bash
# Check if new intelligence feed items exist
[ -f ~/.claude/intelligence-feed-digest.md ] && wc -l ~/.claude/intelligence-feed-digest.md || echo "no feed"
```

Surface count of unread feed items if > 0.

---

## Output Format

After running all checks, report as a single punch list:

```
## Maintenance Sweep — {ISO timestamp}

**Git**
- Merged branches to delete: {list or "none"}
- Stale worktrees: {list or "none"}
- Uncommitted changes: {list or "none"}

**Backlog**
- Stale in_progress (>7d): {list or "none"}
- Stale pending (>21d): {list or "none"}
- Ready to unblock: {list or "none"}

**Reconcile**
- Drift signals: {summary or "none"}

**Docs**
- Undocumented system changes: {list or "none"}

**Knowledge**
- MEMORY.md: {N} lines {ok / WARNING: near limit}
- Missing memory files: {list or "none"}

**Feed**
- Unread items: {N or "none"}

---
**Queued actions** (requires your approval before executing):
1. {action — e.g. "delete merged branch feat/t-1234-slug"}
2. {action}
```

If all checks are clear: report "All clear — no maintenance needed." and stop.

---

## Rules

1. **Never auto-commit** — surface, don't fix
2. **Never auto-merge or auto-delete branches** — queue for user approval
3. **Never run `brana reconcile` without `--dry-run`** in this mode
4. **Never push** — local only
5. **One sweep per iteration** — don't loop internally; the `/loop` harness controls cadence
6. **Stale in_progress gate** — if a task has been in_progress > 14 days with no recent
   commits on its branch, flag it as abandoned and suggest: set to pending or cancelled
7. **Scope limit** — only thebrana repo and brana system paths. Never touch clients/ or ventures/
