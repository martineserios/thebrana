# Goal-Completion Heuristics H5–H8 + AC: Authoring Guide

> Brainstormed 2026-06-03. Status: idea.
> Spawned from: t-1821 (wire active-goal.json into fix/brainstorm/ship)
> Related: `system/hooks/goal-completion.sh` (H1–H4), `docs/conventions/` (AC: convention doc to create)

## Problem

`goal-completion.sh` has 4 heuristics but ~10 of 17 AC: lines in the backlog fall through
to UNKNOWN — the hook surfaces them for manual sign-off rather than auto-completing. Two
root causes:

1. **Missing heuristics** — file-contains, jq-query, command-exits, and git-log patterns
   are common in AC: lines but not implemented.
2. **No authoring guidance** — the model writes AC: lines without a syntax reference, so
   forms like `"ADR-045 Status = Accepted"` are natural-language but not parseable.

## Proposed Heuristics

### H5 — File contains string

**Trigger:** `file {path} contains "{string}"`

**Implementation:**
```bash
if echo "$criterion" | grep -qiE '^file .+ contains "'; then
    path=$(echo "$criterion" | grep -oE 'file [^ ]+' | awk '{print $2}')
    search=$(echo "$criterion" | grep -oE '"[^"]+"' | tr -d '"')
    target="${WORK_DIR}/${path}"
    if [ -f "$target" ] && grep -qF "$search" "$target" 2>/dev/null; then
        PASSED=$((PASSED + 1))
    else
        FAILED=$((FAILED + 1))
    fi
fi
```

**Safety:** path sandboxed to WORK_DIR (prepend WORK_DIR, reject paths starting with `/` or `..`).

**Example AC:** `file docs/architecture/decisions/ADR-045.md contains "Status: Accepted"`

---

### H6 — jq query returns value

**Trigger:** `jq '{expr}' {file} returns "{value}"`

**Implementation:**
```bash
if echo "$criterion" | grep -qiE "^jq '.+' .+ returns"; then
    expr=$(echo "$criterion" | grep -oE "'.+'" | tr -d "'")
    file=$(echo "$criterion" | sed "s/jq '[^']*' //" | grep -oE '[^ ]+' | head -1)
    expected=$(echo "$criterion" | grep -oE 'returns "[^"]+"' | grep -oE '"[^"]+"' | tr -d '"')
    target="${WORK_DIR}/${file}"
    result=$(jq -r "$expr" "$target" 2>/dev/null) || result=""
    if [ "$result" = "$expected" ]; then
        PASSED=$((PASSED + 1))
    else
        FAILED=$((FAILED + 1))
    fi
fi
```

**Safety:** file path sandboxed to WORK_DIR. jq errors → UNKNOWN (not FAILED).

**Example AC:** `jq '.jobs["feed-poll"].enabled' system/scheduler/scheduler.template.json returns "false"`

---

### H7 — Command exits 0

**Trigger:** `"{command}" passes` (quoted command)

**Allowlist** (only these command prefixes are executed):
- `cargo test`
- `pytest` / `python -m pytest`
- `bun test` / `npm test` / `yarn test`
- `bash tests/` / `./tests/`

Non-matching command → UNKNOWN (surfaces for manual sign-off, never executed).

**Implementation:**
```bash
if echo "$criterion" | grep -qiE '^"[^"]+" passes$'; then
    cmd=$(echo "$criterion" | grep -oE '"[^"]+"' | tr -d '"')
    # Allowlist check
    if echo "$cmd" | grep -qE '^(cargo test|pytest|python -m pytest|bun test|npm test|yarn test|bash tests/|\./tests/)'; then
        if (cd "$WORK_DIR" && eval "$cmd" >/dev/null 2>&1); then
            PASSED=$((PASSED + 1))
        else
            FAILED=$((FAILED + 1))
        fi
    else
        UNKNOWN=$((UNKNOWN + 1))
    fi
fi
```

**Example AC:** `"cargo test --test hooks" passes`

---

### H8 — Git log check

**Trigger forms:**
- `changes to {file} committed` → `git log --oneline -- {file}` non-empty
- `commit message contains "{string}"` → `git log --oneline --grep="{string}"` non-empty

**Safety:** git log is read-only. No sandboxing needed.

**Implementation:**
```bash
if echo "$criterion" | grep -qiE "^changes to .+ committed$"; then
    file=$(echo "$criterion" | sed 's/^changes to //' | sed 's/ committed$//')
    result=$(cd "$WORK_DIR" && git log --oneline -- "$file" 2>/dev/null | head -1) || result=""
    [ -n "$result" ] && PASSED=$((PASSED + 1)) || FAILED=$((FAILED + 1))
elif echo "$criterion" | grep -qiE '^commit message contains "'; then
    search=$(echo "$criterion" | grep -oE '"[^"]+"' | tr -d '"')
    result=$(cd "$WORK_DIR" && git log --oneline --grep="$search" 2>/dev/null | head -1) || result=""
    [ -n "$result" ] && PASSED=$((PASSED + 1)) || FAILED=$((FAILED + 1))
fi
```

**Example AC:** `commit message contains "t-1821"` / `changes to system/hooks/goal-completion.sh committed`

---

## AC: Authoring Convention

### Inline hint (to add to build.md DECOMPOSE step)

```
# AC: syntax — use these forms for auto-verification at session end:
AC: {path} exists                              → H1: file exists
AC: brana backlog get {id} returns {value}    → H2: task field check
AC: validate.sh Check {N} passes              → H3: validate check
AC: hook {name}.sh exists in system/hooks/   → H4: hook file exists
AC: file {path} contains "{string}"           → H5: file content check
AC: jq '{expr}' {file} returns "{value}"      → H6: JSON field check
AC: "{command}" passes                         → H7: test command (allowlisted)
AC: changes to {file} committed               → H8: git log check
AC: commit message contains "{string}"        → H8: git log --grep check
# Any other form → UNKNOWN (manual sign-off required)
```

### Convention doc

`docs/conventions/ac-criteria.md` — full examples, allowlist details, sandbox rules,
UNKNOWN fallback behavior, guidance on when to use each heuristic.

## Coverage After H5–H8

Re-scoring the 17 AC: lines from the backlog audit:

| Before | After |
|--------|-------|
| H1–H4 covers ~7/17 | H1–H8 covers ~15/17 |
| UNKNOWN rate ~59% | UNKNOWN rate ~12% |

Remaining UNKNOWN: behavioral AC like "sessions start without blocking" and "claude -p on
remote server confirmed working" — require live execution or remote access, not checkable
deterministically.

## Next Steps

1. Implement H5–H8 in `system/hooks/goal-completion.sh` (in order: H5 → H8, each with its own test)
2. Add inline AC: syntax hint to `build.md` DECOMPOSE / SPECIFY step
3. Write `docs/conventions/ac-criteria.md`
4. Backport well-formed AC: to the t-1412–t-1422 cluster (currently UNKNOWN, now expressible)
5. Re-run the coverage audit after implementation to verify the 12% UNKNOWN rate
