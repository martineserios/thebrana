# Test spec: /brana:close — weight-adaptive LIGHT/FULL classification (t-1623)

## Behaviour under test

Step 1 weight classification determines whether close spawns debrief-analyst (FULL) or
runs an inline scan (LIGHT). Classification uses `git diff --name-only`, not `--stat`.

## Acceptance criteria

### Case 1 — .sh edit → FULL

**Setup:** Session with one commit that modified a `system/hooks/*.sh` file and no other files.

**Expected:**
- `CHANGED_FILES` contains a `.sh` path
- `CLOSE_MODE` = `FULL`
- `debrief-analyst` is spawned (not inline scan)

**Verification:** Run close after committing only a `.sh` change. Confirm debrief-analyst
Agent() call appears in the close output.

---

### Case 2 — tasks.json only → LIGHT

**Setup:** Session with one commit that modified only `.claude/tasks.json`.

**Expected:**
- `CHANGED_FILES` contains only `tasks.json`
- `.json` path does NOT match `^(system|\.claude)/.*\.json$`... wait: `.claude/tasks.json`
  DOES match `^\.claude/.*\.json$`.

  **Exception:** `tasks.json` is a state file, not behavioral config. The classification
  treats it as LIGHT explicitly because it is the canonical state file, not a settings file.
  Add an exclusion before the behavioral-json check:
  ```bash
  elif echo "$CHANGED_FILES" | grep -qvE '^\.claude/tasks\.json$' \
       && echo "$CHANGED_FILES" | grep -qE '^(system|\.claude)/.*\.json$'; then CLOSE_MODE="FULL"
  ```
  Or equivalently: strip `tasks.json` from CHANGED_FILES before the json check.

  The authoritative rule: `tasks.json` only → LIGHT, even though it sits under `.claude/`.

**Expected:**
- `CLOSE_MODE` = `LIGHT`
- Inline scan runs, no debrief-analyst spawn

**Verification:** Run close after committing only `tasks.json`. Confirm no Agent() call
for debrief-analyst.

---

### Case 3 — settings.json → FULL

**Setup:** Session with one commit that modified `.claude/settings.json`.

**Expected:**
- `CHANGED_FILES` contains `.claude/settings.json`
- Matches `^\.claude/.*\.json$` (after tasks.json exclusion)
- `CLOSE_MODE` = `FULL`
- `debrief-analyst` is spawned

**Verification:** Run close after committing only `settings.json`. Confirm debrief-analyst
Agent() call appears.

---

### Case 4 — escape hatches override classification

**Setup:** Any session, invoked as `/brana:close --light` or `/brana:close --full`.

**Expected:**
- `--light` → `CLOSE_MODE` = `LIGHT` regardless of changed files
- `--full` → `CLOSE_MODE` = `FULL` regardless of changed files
- Escape hatch is checked first, before any file-based rules

---

### Case 5 — ≥2 commits → FULL

**Setup:** Session with 2 or more commits, all touching only `.md` files.

**Expected:**
- `COMMIT_COUNT` ≥ 2 → `CLOSE_MODE` = `FULL`
- File extension check is irrelevant (commit count already triggered FULL)

---

## Implementation note: tasks.json exclusion

The bash block in close.md Step 1 needs a tasks.json exclusion to make Case 2 work.
The behavioral-json rule `^(system|\.claude)/.*\.json$` matches `tasks.json` — so an
explicit exclusion is required before that check fires:

```bash
# Strip tasks.json from the set before behavioral-json check
BEHAVIORAL_JSON=$(echo "$CHANGED_FILES" | grep -E '^(system|\.claude)/.*\.json$' \
                 | grep -v '^\.claude/tasks\.json$')
elif [[ -n "$BEHAVIORAL_JSON" ]]; then CLOSE_MODE="FULL"
```

This makes the behavioral-json check: "any .json under system/ or .claude/, EXCEPT tasks.json."
