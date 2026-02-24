---
name: session-handoff
description: "Session lifecycle command — auto-detects pickup (start) or close (end). On close: extracts learnings, checks doc drift, writes handoff note. Part of the self-learning loop. Use when starting or ending a session."
allowed-tools: [Read, Glob, Grep, Bash, Edit, Write, Task]
---

# Session Handoff

Auto-detects mode based on session context. You don't need to specify — just call `/session-handoff` and the right thing happens.

## Mode Detection

1. Run `git log --oneline -5` and check commit timestamps.
2. Check if `session-handoff.md` already has an entry for today.
3. **Close mode** if ANY of: recent commits exist from this session, user said "done"/"bye"/"closing", or `$ARGUMENTS` contains "close".
4. **Pickup mode** if: no recent commits, session-handoff.md last entry is from a previous session, or `$ARGUMENTS` contains "open"/"start".
5. **When ambiguous:** default to **close** — it's better to capture learnings twice than to miss them.

---

## Close Mode (session end)

### Step 1: Gate check

```bash
git diff --stat HEAD~5..HEAD 2>/dev/null
git log --oneline --since="6 hours ago" 2>/dev/null
```

If both are empty (no commits, no changes in the last 6 hours):
- Write a minimal handoff entry: `## YYYY-MM-DD — read-only session` with just a **Next:** section from conversation context.
- Skip to Step 5.

### Step 2: Extract learnings

Spawn the `debrief-analyst` agent (existing Opus agent) via the Task tool:

```
Task(subagent_type="debrief-analyst", prompt="Debrief this session. Focus on: what was built, any errata or spec mismatches found, process learnings. Check git log and conversation context.")
```

The agent returns classified findings (errata / learnings / issues). It does NOT modify files.

If the agent is unavailable, do a quick manual scan:
1. `git log --oneline -10` — list what was committed
2. Review conversation for: errors hit, workarounds used, surprises
3. Classify into errata / learnings / issues (even if empty — "clean session" is valid)

### Step 2b: Graduation suggestions (Wave 3)

Check session JSONL for correction patterns worth promoting:

```bash
SESSION_FILES=$(ls /tmp/brana-session-*.jsonl 2>/dev/null)
```

For each session file, count corrections and identify files that were corrected multiple times. If a correction pattern appears 2+ times (same file re-edited, same error type resolved), suggest graduation:

- Include in the handoff note under **Learnings**: "Correction pattern: {file/error} corrected {N} times — eligible for fast-track promotion via `/retrospective`"
- These patterns resolved real errors during active work, giving higher confidence than recall-only promotion

Skip silently if no session JSONL files exist or no corrections found.

### Step 3: Doc drift heuristic

Check if system files were modified this session:

```bash
git diff --name-only HEAD~10..HEAD 2>/dev/null | grep -E '(skills/|agents/|hooks/|rules/|commands/|CLAUDE\.md|settings\.json|deploy\.sh)'
```

- **If matches found:** add to handoff note: `**Doc drift:** System files changed ({list}). Run /back-propagate next session.`
- **If no matches:** skip silently.

Also write a flag file for the session-start hook to pick up:

```bash
MEMORY_DIR=$(find ~/.claude/projects/ -maxdepth 2 -name "MEMORY.md" -path "*$(basename $(git rev-parse --show-toplevel))*" -exec dirname {} \; 2>/dev/null | head -1)
if [ -n "$MEMORY_DIR" ]; then
    echo "$(date +%Y-%m-%d) $(git diff --name-only HEAD~10..HEAD 2>/dev/null | grep -E '(skills/|agents/|hooks/|rules/|commands/)' | tr '\n' ',')" > "$MEMORY_DIR/.needs-backprop"
fi
```

### Step 4: Write handoff note

Find `session-handoff.md` in `~/.claude/projects/` for the current project's memory folder. Append a new dated section:

```markdown
## YYYY-MM-DD — <brief label>

**Accomplished:**
- {from git log + conversation context}

**Learnings:**
- {from debrief-analyst output, if any}
- {errata found, process insights, issues}
- {correction patterns eligible for graduation, if any}

**State:**
- Branch: {current branch}
- Key files touched: {from git diff --stat}
- Tests: passing / failing / N/A

**Doc drift:**
- {system files changed, or "None"}

**Next:**
- {follow-up actions, deferred items}
- {if errata found: "Run /apply-errata"}
- {if doc drift: "Run /back-propagate"}

**Blockers:**
- ... (or "None")
```

Rules for the handoff file:
- **Always append** — never delete or overwrite previous sections.
- **Same date, multiple sessions?** Use `## YYYY-MM-DD (2) — label` for the second session that day, `(3)` for the third, etc.
- **Keep each section concise** — 15 lines max. This is a handoff, not a journal.
- **Trim old sections** if the file exceeds ~200 lines: collapse sections older than 30 days into a single `## Archive (before YYYY-MM-DD)` summary at the top, preserving only key decisions and unresolved items.

### Step 5: Store and backup

Store approved learnings from Step 2 in claude-flow memory:

```bash
source "$HOME/.claude/scripts/cf-env.sh"

cd "$HOME" && $CF memory store \
  -k "session:{PROJECT}:{YYYY-MM-DD}" \
  -v '{"type": "session-close", "date": "{YYYY-MM-DD}", "commits": N, "learnings": N, "errata": N, "drift": true|false}' \
  --namespace patterns \
  --tags "project:{PROJECT},type:session-close"
```

If claude-flow unavailable, skip silently — the handoff note IS the fallback.

Then backup:

```bash
"$HOME/.claude/scripts/backup-knowledge.sh"
```

Skip silently if the script doesn't exist.

### Step 6: Report

```markdown
## Session Close Complete

**Commits this session:** {N}
**Learnings extracted:** {N} ({errata} errata, {learnings} learnings, {issues} issues)
**Doc drift detected:** {yes/no — files listed if yes}
**Handoff note updated:** {path}

### Follow-up suggestions
- {if errata: "Run `/apply-errata` to fix spec mismatches"}
- {if drift: "Run `/back-propagate` to sync specs with implementation"}
- {if learnings: "Run `/maintain-specs` to propagate through spec layers"}
- {if correction patterns: "Run `/retrospective` to promote correction patterns (fast-track eligible)"}
```

---

## Pickup Mode (session start)

### Step 1: Read context

1. **Read the handoff note** at the project's memory directory: find `session-handoff.md` under `~/.claude/projects/` for the current project's memory folder. Read it fully.
2. **Read MEMORY.md** in the same directory to understand the full project context.

### Step 2: Check for cross-session changes

Another session may have modified files since the handoff was written:
- `git log --oneline -10` to see recent commits
- `git diff HEAD~3..HEAD --stat` to see what changed
- Compare what the handoff says was done vs what's actually in the repo

### Step 3: Reconcile conflicts

If another session modified files that the handoff also touched:
- Compatible (additive): note what was added, incorporate it
- Conflicting: flag to user, don't auto-resolve

### Step 4: Check flags and correction patterns from previous session

Look for flag files left by the close mode or session-end hook:

```bash
MEMORY_DIR=$(find ~/.claude/projects/ -maxdepth 2 -name "MEMORY.md" -path "*$(basename $(git rev-parse --show-toplevel))*" -exec dirname {} \; 2>/dev/null | head -1)
[ -f "$MEMORY_DIR/.needs-backprop" ] && cat "$MEMORY_DIR/.needs-backprop"
```

If `.needs-backprop` exists, include in the report: "Previous session changed system files. Consider `/back-propagate`."

Also check claude-flow for high-confidence correction patterns from this project:

```bash
source "$HOME/.claude/scripts/cf-env.sh"
if [ -n "$CF" ]; then
    cd "$HOME" && $CF memory search --query "project:{PROJECT} type:correction" --namespace patterns
fi
```

If correction patterns with `confidence: 0.8` exist, surface them in the report: "[Priority recall] These correction patterns have proven reliable — apply early if similar errors arise: {pattern list}"

### Step 5: Report

- What the previous session accomplished
- What cross-session changes were found (if any)
- What flags were left (doc drift, pending errata)
- Where to continue next

---

## Rules

1. **Auto-detect mode.** Never ask the user "pickup or close?" — infer from context.
2. **Reuse existing tools.** Debrief-analyst agent for learning extraction, not a custom implementation.
3. **Gate on changes.** Read-only sessions get a one-line handoff note and no debrief.
4. **Don't block on failures.** If debrief agent fails, manual scan. If claude-flow fails, handoff note is the fallback. If backup fails, skip.
5. **Suggest, don't execute.** Doc drift → suggest `/back-propagate`. Errata → suggest `/apply-errata`. Let the user decide when.
6. **Every session feeds the loop.** Even trivial sessions produce a handoff note. The system never goes silent.
