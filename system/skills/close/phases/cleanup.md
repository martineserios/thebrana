<!-- close phase: Steps 11b-12 + Session Close: worktree reap, task reconcile, stash/loop sweeps, report, follow-up — loaded per the PHASES registry in ../SKILL.md (t-1942) -->

> **Orientation guard (ADR-053, t-1990):** read the orientation from the gate's Step 1 announcement. Skip Steps 11b and 11d when the orientation is `--continue` or `--patterns` — branch, worktree, and stash state must survive for resumption. They run for `--finish`, FULL, and bare closes. REPORT (Step 12) always runs.

### Step 11b: Reap merged worktrees

Prune worktrees whose branches are fully merged into main. Prevents orientation cost at next session start.

```bash
MAIN_ROOT=$(git rev-parse --show-toplevel 2>/dev/null)
MERGED=$(git branch --merged main 2>/dev/null | grep -v '^\*' | sed 's/^[[:space:]]*//')
REAPED=0
SKIPPED=0

# Parse porcelain output — each stanza ends with a blank line
WT_PATH=""
WT_BRANCH=""
while IFS= read -r line; do
  case "$line" in
    worktree\ *)  WT_PATH="${line#worktree }" ;;
    branch\ *)    WT_BRANCH="${line#branch refs/heads/}" ;;
    "")
      if [ -n "$WT_PATH" ] && [ -n "$WT_BRANCH" ] && [ "$WT_PATH" != "$MAIN_ROOT" ]; then
        if echo "$MERGED" | grep -qx "$WT_BRANCH"; then
          if git -C "$MAIN_ROOT" worktree remove "$WT_PATH" 2>/dev/null; then
            echo "  Reaped: $WT_PATH ($WT_BRANCH)"
            (( REAPED++ )) || true
          else
            echo "  Skipped (unclean): $WT_PATH ($WT_BRANCH) — remove manually"
            (( SKIPPED++ )) || true
          fi
        fi
      fi
      WT_PATH=""; WT_BRANCH=""
      ;;
  esac
done < <(git worktree list --porcelain 2>/dev/null; echo "")
```

**Track for Step 12 report:** `{REAPED} reaped, {SKIPPED} skipped (unclean)`.

**Skip if:** `git worktree list` shows only 1 entry (just the main checkout).

### Step 11c: Pending-task reconcile

Tasks in `.claude/tasks.json` often lag code state when a previous `/brana:close` was skipped. Before writing the session report, find pending tasks whose IDs already appear in a commit message on main and prompt to mark them `completed`.

```bash
MAIN_ROOT=$(git rev-parse --show-toplevel 2>/dev/null)
PENDING_IDS=$(brana backlog query --status pending --output json 2>/dev/null \
  | jq -r '.[].id')

STALE=()
for id in $PENDING_IDS; do
  # Match only fix/feat/merge commits where the ID appears in the scope prefix, not just the body.
  # Precision > recall: "fix(t-123):" matches; "migrate t-123 to..." or "chore(tasks): add t-123" do not.
  if git -C "$MAIN_ROOT" log --all --oneline -E --grep "\\b$id\\b" 2>/dev/null \
    | grep -qE "^[0-9a-f]+ (fix|feat|merge)\($id\):"; then
    STALE+=("$id")
  fi
done
```

**If `STALE` is non-empty (up to 10 items):** batch via AskUserQuestion (multiSelect):
```
"These pending tasks appear in fix/feat/merge commits. Mark done?"
Options: ["{id} — {first-line of subject}", ...] — up to 4 per call
```

For each selected id:
```bash
brana backlog set "$id" status completed
brana backlog set "$id" notes --append "Reconciled 2026-MM-DD via /brana:close: commit {hash} matched."
```

**Track for Step 12 report:** `{N} reconciled pending → done`.

**Skip if:** no pending tasks match, or session was read-only.

**Why:** without this, the backlog query surface (sitrep, next, focus) stays contaminated between sessions and every future triage must re-verify by hand.

### Step 11e: Idea doc lifecycle check

When Step 11c detected a completed milestone (a parent task with completed children):

1. **Scan docs/ideas/:** `find docs/ideas/ -name "*.md" 2>/dev/null`
2. **For each idea doc**, check its `status:` frontmatter field (look for `status:` in the first 10 lines).
3. **If status is `idea`, `draft`, or `specifying`**, and the doc title or filename shares keywords with the completed milestone subject:
   - Prompt once per matching doc:
     ```
     AskUserQuestion:
       question: "Idea doc 'docs/ideas/{slug}.md' is still marked '{status}' but milestone '{milestone}' is complete. Update status?"
       options: ["Update to implemented", "Update to shipped", "Leave as-is", "Archive it"]
     ```
   - If user selects update: replace the `status:` frontmatter value and commit:
     ```bash
     # edit the status line in the file, then:
     git add docs/ideas/{slug}.md
     git commit -m "docs({slug}): update idea doc status to {new-status}"
     ```
   - If "Archive it": move to `docs/archive/ideas/{slug}.md` and commit.

**Track for Step 12 report:** `{N} idea docs updated`.

**Skip if:** docs/ideas/ does not exist or contains no .md files, or no milestone rollup was detected in Step 11c.

### Step 11d: Stale-stash cleanup

Offer to drop git stashes older than 7 days that reference completed or cancelled task branches.

```bash
MAIN_ROOT=$(git rev-parse --show-toplevel 2>/dev/null)
git -C "$MAIN_ROOT" stash list --date=iso-strict 2>/dev/null \
  | awk -v now="$(date +%s)" '
      {
        # Extract ISO date between parens; stashes are: stash@{N}: WIP on ... 2026-04-15T...
        match($0, /[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]+/)
        if (RSTART > 0) {
          d = substr($0, RSTART, 10)
          cmd = "date -d \"" d "\" +%s"
          cmd | getline ts
          close(cmd)
          if (now - ts > 604800) print $0
        }
      }'
```

**If any stashes returned:** list them, then prompt once:
```
AskUserQuestion: "Found N stashes older than 7 days. Drop them?"
Options:
  - label: "Drop all"
    description: "Delete all stashes older than 7 days immediately."
  - label: "Review each"
    description: "Inspect each stash individually before deciding whether to drop."
  - label: "Skip"
    description: "Leave all old stashes in place."
```

For "Review each": iterate per-stash with its own AskUserQuestion (batch up to 4). For "Drop all": `git stash drop stash@{N}` for each, in reverse order to preserve indices.

**Track for Step 12 report:** `{N} stashes dropped`.

**Skip if:** `git stash list` is empty, or no stashes are older than 7 days.

### Step 11f: Session-loop sweep (ADR-050)

Clean up any cron loops that were spawned during this session. This is the backstop — individual skill CLOSE steps should delete their own loops, but this step catches anything left over.

```
ToolSearch("select:CronList,CronDelete")
```

1. List active crons: call `CronList` (deferred tool — load schema first via ToolSearch above).
2. If any entries exist: delete each non-durable loop with `CronDelete`. Skip any with `durable: true` — those were explicitly requested by the user and survive intentionally.
3. If `CronList` returns empty or the tool is unavailable: skip silently. Non-durable loops are killed by session end anyway.

**Track for Step 12 report:** `{N} session loops swept` (or "none").

### Step 12: Report

```markdown
## Session Close

**Commits this session:** {N}
**Learnings extracted:** {N} ({errata} errata, {learnings} learnings, {issues} issues)
**Field notes:** {N kept} kept, {M archived} archived, {P skipped} skipped
**Patterns stored:** {N}
**Feature ideation:** {N ideas found}, {M added to backlog}
**Memory reviewed:** {N entries deleted}, {M feature ideas extracted}
**Worktrees reaped:** {N reaped}, {M skipped (unclean)} — or "none" if only 1 worktree
**Doc drift detected:** {yes/no}
**Auto-reconcile:** {triggered (N issues) / skipped}
**Handoff note updated:** {path}

### Follow-up
- {if errata: "/brana:reconcile --scope propagation to check for drift"}
- {if drift: "Specs may need updating for changed system files"}
- {if issues: "Issues logged for next session"}
- {if field notes kept: "Docs updated with field notes: {list of docs}"}
- {if features extracted: "New tasks from memory: {list of task IDs}"}
- {if ideation added: "Feature ideas added: {list of task IDs}"}
```

After presenting the report, **offer to create tasks from actionable follow-ups**.

Collect all follow-up items that are actionable (not just informational). Filter out items that already have tasks (e.g., "New tasks from memory" items were already created in Step 11, ideation items in Step 7). Present the remaining via AskUserQuestion (multiSelect: true):

```
AskUserQuestion:
  question: "Create tasks from these follow-ups?"
  header: "Follow-ups"
  multiSelect: true
  options:
    - label: "{follow-up description}"
      description: "Create a backlog task for this follow-up action."
    - label: "Skip all"
      description: "Discard all follow-up suggestions — nothing to file."
```

For each selected follow-up:
- Run `brana backlog add --json '{"subject":"{follow-up}","work_type":"chore","type":"task","tags":["{relevant tags}"],"effort":"S"}'`
- Report the created task ID inline

**Skip the offer if:** no actionable follow-ups exist (all items are informational or already have tasks).

**After the AskUserQuestion**, for every follow-up item the user did NOT select for task creation, still write it to `next[]` with `task_id: null` — items must never silently disappear because the user skipped task creation:
```json
{"text": "{follow-up description}", "task_id": null, "category": "follow-up"}
```
This ensures sitrep surfaces all follow-ups from the close report at the start of the next session.

---

