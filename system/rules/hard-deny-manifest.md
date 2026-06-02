# Hard Deny Manifest

Canonical list of commands that are **unconditionally blocked** in auto mode via
`settings.autoMode.hard_deny`. These are never-justified actions — no user intent,
context, or explicit allow exception overrides them.

Synced to `~/.claude/settings.json` by `bootstrap.sh` (Step 4c3).

---

## Entries

### 1. Force-push to main / master

```
Bash(git push --force origin main*)
Bash(git push --force origin master*)
Bash(git push -f origin main*)
Bash(git push -f origin master*)
```

**Why hard deny:** Rewrites shared history on the protected branch. No recovery
path for collaborators. git-discipline.md: "Never force-push to main or master —
HARD RULE." Force-push to feature branches (after rebase) is legitimate and not
blocked here.

---

### 2. Skip commit hooks (`--no-verify` / `-n`)

```
Bash(git commit --no-verify*)
Bash(git commit -n *)
```

**Why hard deny:** `--no-verify` bypasses the full hook chain — attribution
enforcement (`no-attribution-commit.sh`), TDD gate (`tdd-gate.sh`), branch verify
(`branch-name-warn.sh`), and config-change guard. Skipping hooks to "fix a quick
thing" is exactly how attribution leaks and TDD gates get silently bypassed.
There is no legitimate case where skipping hooks is safer than fixing the
underlying hook failure.

---

### 3. Force-delete protected branches

```
Bash(git branch -D main*)
Bash(git branch -D master*)
```

**Why hard deny:** Permanently deletes the canonical branch. Unlike feature
branches, main/master deletion cannot be recovered without a remote backup.

---

## Adding new entries

1. Add the entry here with its pattern(s) and a **Why hard deny** rationale.
2. Run `./bootstrap.sh` — Step 4c3 syncs the manifest to `settings.json`.
3. Commit both this file and the bootstrap change together.

## What belongs here vs. soft_deny / hooks

| Fits hard_deny | Fits soft_deny / hook |
|----------------|-----------------------|
| Never justified under any circumstances | Conditional — context can make it OK |
| Same answer every time | Requires reasoning about branch, task, or state |
| User intent doesn't change the answer | User explicit approval can override |
| `--force` to main, `--no-verify` | Worktree checkout with unstaged changes |
