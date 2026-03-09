---
name: close
description: "End a session — extract learnings, write handoff note, store patterns, detect doc drift. Absorbs /session-handoff close mode and /debrief. Use when ending a work session or when the user says done/bye/closing."
group: session
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Glob
  - Grep
  - AskUserQuestion
  - Agent
---

# Close — Session End

End a work session. Extracts what was learned, writes a handoff note for the next session, stores patterns, and detects doc drift. Replaces `/session-handoff` close mode and `/debrief`.

## When to use

- User says "done", "bye", "closing", "that's it", or similar
- End of a long implementation session
- Before switching to a different project
- Explicitly: `/brana:close`

## Steps

### Step 1: Gate check

Assess what happened this session:

```bash
git diff --stat HEAD~5..HEAD 2>/dev/null
git log --oneline --since="6 hours ago" 2>/dev/null
```

**If both empty** (no commits, no changes in 6 hours):
- Write a minimal handoff entry: `## YYYY-MM-DD — read-only session`
- Add only a **Next:** section from conversation context
- Skip to Step 5

### Step 2: Gather evidence

Collect from multiple sources:

1. **Git log + diffs:**
   ```bash
   git log --oneline --since="6 hours ago" 2>/dev/null
   git diff --stat HEAD~5..HEAD 2>/dev/null
   ```
2. **Conversation context** — review for: errors hit, workarounds used, surprises, things that didn't match expectations
3. **If `$ARGUMENTS` provided** — use as focus hint (e.g., `/brana:close hooks` focuses on hook-related findings)

### Step 3: Extract and classify findings

Spawn the `debrief-analyst` agent:

```
Agent(subagent_type="debrief-analyst", prompt="Debrief this session. Focus on: what was built, any errata or spec mismatches found, process learnings. Check git log and conversation context.")
```

If the agent is unavailable, do a manual scan:
1. `git log --oneline -10` — list what was committed
2. Review conversation for: errors, workarounds, surprises
3. Classify into the three buckets below

**Classification buckets:**

| Bucket | What it is | Example |
|--------|-----------|---------|
| **Errata** | Spec says X, reality is Y | "Spec says `hooks recall`, actual API is `memory search`" |
| **Learning** | Reusable insight about how to work | "DB schema drift breaks things silently" |
| **Issue** | Something broken, not a spec mismatch | "Deploy script doesn't handle symlinks" |

### Step 4: Write errata entries (if any)

For each **errata** finding:

1. Find the errata doc: `Glob("**/*correction*")` or `Glob("**/*errata*")`
2. If found, read it for format and current error count
3. If not found, use `~/enter_thebrana/thebrana/docs/24-roadmap-corrections.md`
4. Append entries following the existing format:
   - Sequential error number
   - Title, severity (High/Medium/Low), discovery, affected files, fix
5. Add to severity summary table

**Status rules — close only logs, never resolves:**

| Finding | Status | Who resolves |
|---------|--------|-------------|
| Spec mismatch (needs doc edits) | `pending` | `/brana:maintain-specs` |
| Code bug (fixed this session) | `code-fix` | Already done |
| Code bug (not fixed) | `pending` | Next session |

### Step 5: Store learnings as patterns

For each learning from Step 3, store via claude-flow:

```bash
source /home/martineserios/.claude/scripts/cf-env.sh

cd "$HOME" && $CF memory store \
  -k "pattern:{PROJECT}:{short-title}" \
  -v '{"problem": "...", "solution": "...", "confidence": 0.5, "transferable": false, "correction_weight": 0}' \
  --namespace patterns \
  --tags "project:{PROJECT},type:{CATEGORY},outcome:{OUTCOME}" \
  --upsert
```

If claude-flow is unavailable, append to the project's auto memory `MEMORY.md` under `~/.claude/projects/`.

**Skip if:** session was read-only (no commits), or debrief returned no learnings.

### Step 6: Detect doc drift

Check if system files were modified this session:

```bash
git diff --name-only HEAD~10..HEAD 2>/dev/null | grep -E '(skills/|agents/|hooks/|rules/|commands/|CLAUDE\.md|settings\.json|deploy\.sh)'
```

- **If matches found:** flag in handoff note and write a marker file:
  ```bash
  MEMORY_DIR=$(find ~/.claude/projects/ -maxdepth 2 -name "MEMORY.md" -path "*$(basename $(git rev-parse --show-toplevel))*" -exec dirname {} \; 2>/dev/null | head -1)
  [ -n "$MEMORY_DIR" ] && echo "$(date +%Y-%m-%d) $(git diff --name-only HEAD~10..HEAD 2>/dev/null | grep -E '(skills/|agents/|hooks/|rules/|commands/)' | tr '\n' ',')" > "$MEMORY_DIR/.needs-backprop"
  ```
- **If no matches:** skip silently

### Step 7: Write handoff note

Find `session-handoff.md` in `~/.claude/projects/` for the current project. Append:

```markdown
## YYYY-MM-DD — <brief label>

**Accomplished:**
- {from git log + conversation context}

**Learnings:**
- {from Step 3 classified findings}

**State:**
- Branch: {current branch}
- Key files touched: {from git diff --stat}
- Tests: passing / failing / N/A

**Doc drift:**
- {system files changed, or "None"}

**Next:**
- {follow-up actions, deferred items}
- {if errata found: "Run /brana:maintain-specs"}
- {if doc drift: "Consider updating specs"}

**Blockers:**
- ... (or "None")
```

**Rules for the handoff file:**
- Always append — never delete or overwrite previous sections
- Same date, multiple sessions: use `## YYYY-MM-DD (2) — label`
- Keep each section concise — 15 lines max
- Trim old sections if file exceeds ~200 lines: collapse entries older than 30 days into an `## Archive (before YYYY-MM-DD)` summary

### Step 8: Store session metadata

```bash
source /home/martineserios/.claude/scripts/cf-env.sh

cd "$HOME" && $CF memory store \
  -k "session:{PROJECT}:{YYYY-MM-DD}" \
  -v '{"type": "session-close", "date": "{YYYY-MM-DD}", "commits": N, "learnings": N, "errata": N, "drift": true|false}' \
  --namespace patterns \
  --tags "project:{PROJECT},type:session-close" \
  --upsert
```

If claude-flow unavailable, skip — the handoff note is the fallback.

Then backup:

```bash
"$HOME/.claude/scripts/backup-knowledge.sh" 2>/dev/null || true
```

### Step 9: Report

```markdown
## Session Close

**Commits this session:** {N}
**Learnings extracted:** {N} ({errata} errata, {learnings} learnings, {issues} issues)
**Patterns stored:** {N}
**Doc drift detected:** {yes/no}
**Handoff note updated:** {path}

### Follow-up
- {if errata: "/brana:maintain-specs to propagate findings"}
- {if drift: "Specs may need updating for changed system files"}
- {if issues: "Issues logged for next session"}
```

---

## Rules

1. **Extract from evidence, don't invent.** Every finding traces to something that happened — a command that failed, a mismatch observed, a workaround applied.
2. **Learnings must be actionable.** Each contains a concrete rule someone can follow. If you can't state it as a rule, it's not a learning yet.
3. **Don't duplicate.** Read existing errata before adding. If already documented, skip or note confirmation.
4. **Gate on changes.** Read-only sessions get a one-line handoff and no debrief.
5. **Don't block on failures.** Agent fails → manual scan. Claude-flow fails → handoff note is the fallback. Backup fails → skip.
6. **Suggest, don't execute.** Doc drift → suggest updating specs. Errata → suggest `/brana:maintain-specs`. Let the user decide when.
7. **Be specific.** "The API was wrong" is useless. "Spec says `hooks recall`, actual is `memory search`" is useful.
8. **Ask for clarification when needed.** Ambiguous findings → ask. Don't guess classifications.
