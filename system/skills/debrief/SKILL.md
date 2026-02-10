---
name: debrief
description: Extract errata, fixes, and process learnings from the current session and document them
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Glob
  - Grep
---

# Debrief

Review what happened in this session, extract everything worth documenting, and write it up. This is the structured version of "what did we learn?"

## When to use

After any implementation session where you hit unexpected issues, discovered spec-vs-reality mismatches, or learned something about the tools/process. Run `/debrief` before ending the session.

## Process

### Step 1: Gather evidence

Collect what happened this session from multiple sources:

1. **Git log + diffs** — run `git log --oneline -10` and `git diff HEAD~1` (or appropriate range) in each repo with changes. This shows what was done and what files were touched.
2. **Conversation context** — review the current conversation for: errors encountered, workarounds applied, surprises, things that didn't match expectations.
3. **If `$ARGUMENTS` is provided** — use it as a hint for what to focus on (e.g., `/debrief hooks` focuses on hook-related learnings).

### Step 2: Classify findings

Sort everything into three buckets:

| Bucket | Description | Example |
|--------|-------------|---------|
| **Errata** | Spec said X, reality is Y. A documented command, API, or behavior doesn't match what actually exists. | "Spec says `hooks recall`, actual API is `memory search`" |
| **Process learning** | A reusable insight about how to work effectively. Not a bug — a lesson. | "`2>/dev/null` hides real failures behind silent fallbacks" |
| **Issue** | Something is broken or wrong but not a spec mismatch — a bug, missing feature, or gap that needs fixing. | "DB schema doesn't auto-migrate on upgrade" |

### Step 3: Find the errata doc

Look for the errata/corrections document:

1. Check if the current project has a doc matching `*corrections*` or `*errata*` — use `Glob` with pattern `**/*correction*` and `**/*errata*`.
2. If found, read it to get the current error count and format.
3. If not found, check `~/enter_thebrana/enter/24-roadmap-corrections.md` (the brana specs errata doc).
4. If neither exists, create findings in a `DEBRIEF.md` file in the project root.

### Step 4: Write errata entries

For each **errata** finding, write a new error entry following the existing doc format. Each entry must have:

- **Error number** — next sequential number after existing entries
- **Title** — short, specific (e.g., "claude-flow `hooks recall` doesn't exist in v3")
- **Severity** — High (blocks work), Medium (wrong but workaround exists), Low (informational)
- **Discovery** — what you expected vs what actually happened
- **Files affected** — every file that contains the wrong assumption
- **Fix** — what the correct approach is

Also add each new error to the severity summary table at the top of the doc.

**Status rules — debrief only logs, never resolves:**

| Finding type | Initial status | Who resolves it |
|---|---|---|
| Spec mismatch (needs doc edits) | `pending` | `/apply-errata` or `/maintain-specs` |
| Code bug (already fixed this session) | `code-fix` | Already done — note what was fixed in Comments |
| Code bug (not yet fixed) | `pending` | Next implementation session |
| Informational (no action needed) | `informational` | N/A |

**Never mark a spec-level error as `applied` during debrief.** That's `/apply-errata`'s job — it does the formal edit, gate checks, and marks resolution with date and comments.

### Step 5: Write process learnings

For each **process learning**, append to the "Lessons Learned" section of the errata doc (create it if it doesn't exist). Each learning should:

- Have a short bold title stating the rule
- Explain what happened that taught this lesson (1-2 sentences)
- State the **rule** — a concrete, actionable directive for future work (bold, imperative)
- Be genuinely reusable — not session-specific trivia

Bad: "We had to run `memory init --force`."
Good: "Database schema drift breaks things silently — `memory init --force` should be a documented step whenever claude-flow is upgraded."

### Step 6: Store in claude-flow memory

For each finding, store it in claude-flow for cross-session recall:

```bash
CF=""
for candidate in "$HOME"/.nvm/versions/node/*/bin/claude-flow; do
    [ -x "$candidate" ] && CF="$candidate" && break
done
[ -z "$CF" ] && command -v claude-flow &>/dev/null && CF="claude-flow"
[ -z "$CF" ] && command -v npx &>/dev/null && CF="npx claude-flow"

cd "$HOME" && $CF memory store \
  -k "errata:{PROJECT}:{short-id}" \
  -v '{"type": "errata|learning|issue", "title": "...", "description": "...", "severity": "high|medium|low"}' \
  --namespace patterns \
  --tags "project:{PROJECT},type:errata,outcome:fixed"
```

If claude-flow is unavailable, append to `~/.claude/projects/{project-hash}/memory/MEMORY.md`.

### Step 7: Report

Summarize what was documented:

```markdown
## Debrief Complete

### Errata documented: N
- Error #X: [title]
- Error #Y: [title]

### Learnings documented: N
- [title]
- [title]

### Issues logged: N
- [title]

### Stored in claude-flow: N entries

### Follow-up suggestions
- "Run `/maintain-specs` to propagate these findings through the spec docs (re-evaluate reflections, apply errata layer by layer, update doc 25)."
- [Any other `/apply-errata`, `/re-evaluate-reflections`, or other actions recommended]
```

## Rules

- **Extract from evidence, don't invent.** Every finding must trace back to something that actually happened this session — a command that failed, a mismatch you observed, a workaround you applied.
- **Be specific.** "The API was wrong" is useless. "Spec says `hooks recall --query`, actual command is `memory search -q`" is useful.
- **Learnings must be actionable.** Each one should contain a **Rule:** that someone can follow next time. If you can't state it as a rule, it's not a learning yet.
- **Don't duplicate.** Read the existing errata doc first. If an error is already documented, skip it or note it was confirmed.
- **Errata entries follow existing format exactly.** Match the heading style, field names, and table format already in the doc.
- **Ask for clarification whenever you need it.** If a finding is ambiguous, you're unsure how to classify something, or the user's intent is unclear — ask. Don't guess.
