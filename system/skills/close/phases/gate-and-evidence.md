<!-- close phase: Steps 0-3b: goal injection, gate check (CLOSE_MODE), gather evidence, extract+classify findings, doc-update check — loaded per the PHASES registry in ../SKILL.md (t-1942) -->

## Steps

### Step 0: Goal injection

Call `/goal "session closed: errata filed, learnings stored, tasks.json committed"` at close start. Fixed goal — no task context needed. Keeps every response during a long close oriented to completion rather than drifting into new work.

### Step 1: Gate check

Assess what happened this session:

```bash
git diff --stat HEAD~5..HEAD 2>/dev/null
git log --oneline --since="6 hours ago" 2>/dev/null
```

**State-file dirty check:** After the git commands above, also run:

```bash
git status --porcelain system/state/ 2>/dev/null
```

If any lines are returned (uncommitted changes in `system/state/`), warn and offer to auto-commit before proceeding:

```
AskUserQuestion:
  question: "system/state/ has uncommitted edits. Commit now before closing?"
  header: "State files dirty"
  options:
    - label: "Yes — auto-commit (chore(state): commit state files at session close)"
      description: "Stage and commit all system/state/ edits with standard message."
    - label: "No — skip and continue"
      description: "Leave state files uncommitted and proceed with close."
```

If "Yes":
```bash
git add system/state/
git commit -m "chore(state): commit state files at session close"
```

**If both empty** (no commits, no changes in 6 hours):
- Write a minimal handoff entry: `## YYYY-MM-DD — read-only session`
- Add only a **Next:** section from conversation context
- Skip to Step 9 (Write handoff note)

**Weight classification (NANO / LIGHT / FULL):**

Classify the session depth before spawning any agent. Use `git diff --name-only` — not
`--stat`, which outputs line counts requiring fragile extension parsing.

```bash
COMMIT_COUNT=$(git log --oneline --since="6 hours ago" 2>/dev/null | wc -l | tr -d ' ')
CHANGED_FILES=$(git diff --name-only HEAD~"${COMMIT_COUNT:-1}"..HEAD 2>/dev/null)
FILE_COUNT=$(echo "$CHANGED_FILES" | grep -c . || echo 0)
# Behavioral JSON: system/ or .claude/ JSON files, excluding tasks.json (state file)
BEHAVIORAL_JSON=$(echo "$CHANGED_FILES" | grep -E '^(system|\.claude)/.*\.json$' \
                 | grep -v '^\.claude/tasks\.json$')

# Escape hatches take priority
if [[ "$ARGUMENTS" == *"--light"* ]]; then CLOSE_MODE="LIGHT"
elif [[ "$ARGUMENTS" == *"--full"* ]]; then CLOSE_MODE="FULL"
elif [[ "$ARGUMENTS" == *"--nano"* ]]; then CLOSE_MODE="NANO"
# FULL: ≥2 commits in this session
elif [[ "${COMMIT_COUNT:-0}" -ge 2 ]]; then CLOSE_MODE="FULL"
# FULL: any code or behavioral config file changed
elif echo "$CHANGED_FILES" | grep -qE '\.(rs|ts|tsx|js|jsx|py|sh|toml|yaml|yml)$'; then CLOSE_MODE="FULL"
elif [[ -n "$BEHAVIORAL_JSON" ]]; then CLOSE_MODE="FULL"
# NANO: exactly 1 commit, ≤5 files, no code/config files, only .md / tasks.json / state files
elif [[ "${COMMIT_COUNT:-0}" -eq 1 ]] && [[ "${FILE_COUNT:-0}" -le 5 ]]; then CLOSE_MODE="NANO"
# LIGHT: only .md, tasks.json, state/*.json, or inbox/ changed
else CLOSE_MODE="LIGHT"
fi
```

Ambiguous cases (authoritative — do not infer):
- `.sh` edit → FULL (behavioral, high-stakes)
- `tasks.json` only → NANO (state file, single commit — write handoff and skip Steps 4-8)
- `settings.json` → FULL (behavioral config — matches `^\.claude/.*\.json$`)

**NANO mode:** write handoff note (Step 9) only. Skip Steps 3–8 entirely (no debrief agent, no errata, no patterns, no field notes, no ideation, no drift). NANO sessions have nothing worth extracting — the overhead costs more than the signal.

Announce: `Close mode: $CLOSE_MODE` before proceeding to Step 2.

### Step 2: Gather evidence

Collect from multiple sources:

1. **Git log + diffs:**
   ```bash
   git log --oneline --since="6 hours ago" 2>/dev/null
   git diff --stat HEAD~5..HEAD 2>/dev/null
   ```
2. **Conversation context** — review for: errors hit, workarounds used, surprises, things that didn't match expectations
3. **If `$ARGUMENTS` provided** — use as focus hint (e.g., `/brana:close hooks` focuses on hook-related findings)
4. **Scheduler sweep outputs** — check for unprocessed agy sweep results:
   ```bash
   ls system/scheduler/outputs/*.md 2>/dev/null
   ```
   If files exist: read each, extract findings (same EXTRACT rules as Step 3), then remove:
   ```bash
   rm system/scheduler/outputs/<processed-file>.md
   ```
   Fire-and-forget sweeps write here overnight; close is the only consumer.

### Step 3: Extract and classify findings

Branch on `$CLOSE_MODE` from Step 1.

**FULL mode** — spawn `debrief-analyst` (Sonnet):

```
Agent(subagent_type="debrief-analyst", prompt="Debrief this session. Focus on: what was built, any errata or spec mismatches found, process learnings. Check git log and conversation context.")
```

**LIGHT mode** — inline scan, no agent spawn:
1. `git log --oneline -10` — list what was committed
2. Review conversation for: errors, workarounds, surprises
3. Classify into the three buckets below

If debrief-analyst is unavailable in FULL mode, fall back to the LIGHT inline scan.

**Classification buckets:**

| Bucket | What it is | Example |
|--------|-----------|---------|
| **Errata** | Spec says X, reality is Y | "Spec says `hooks recall`, actual API is `memory search`" |
| **Learning** | Reusable insight about how to work | "DB schema drift breaks things silently" |
| **Issue** | Something broken, not a spec mismatch | "Deploy script doesn't handle symlinks" |

### Step 3b: Doc-update check

Detect behavioral changes that lack corresponding documentation updates.

**Skip if:** session was read-only (no commits).

1. **Get files changed this session:**
   ```bash
   git diff --name-only HEAD~10..HEAD 2>/dev/null
   ```

2. **Classify changed files:**

   | Category | Glob patterns |
   |----------|--------------|
   | **Behavioral** | `system/skills/**`, `system/hooks/**`, `system/agents/**`, `system/commands/**`, `system/cli/**`, `**/rules/**` |
   | **Documentation** | `docs/architecture/**`, `docs/guide/**`, `docs/reference/**`, `*CLAUDE.md` |

   Walk the changed file list and tag each matching file as `behavioral` or `documentation`. Files matching neither are ignored.

3. **Hook script additions check (t-1490):** If any `system/hooks/*.sh` files appear in the changed file list AND `docs/architecture/hooks.md` is NOT in the changed file list, warn — even if other docs were updated:

   ```bash
   HOOK_SCRIPTS=$(git diff --name-only HEAD~10..HEAD 2>/dev/null | grep '^system/hooks/.*\.sh$')
   HOOKS_MD_UPDATED=$(git diff --name-only HEAD~10..HEAD 2>/dev/null | grep -c 'docs/architecture/hooks\.md')
   ```

   If `HOOK_SCRIPTS` is non-empty AND `HOOKS_MD_UPDATED` is 0:
   ```
   ⚠ Hook script(s) added/modified without updating docs/architecture/hooks.md:
   {list of hook .sh files}
   Fix: update the inventory table and gate classification in docs/architecture/hooks.md.
   ```
   Add to `next[]` regardless of user choice:
   ```json
   {"text": "hooks.md update needed for: {hook scripts}", "task_id": null, "category": "maintenance"}
   ```

4. **If behavioral files changed but NO documentation files changed**, prompt:

   Build a mapping of each behavioral file to its most likely doc target. Use these heuristics:
   - `system/skills/{name}/SKILL.md` → `docs/architecture/skills.md`
   - `system/hooks/**` → `docs/architecture/hooks.md`
   - `system/agents/**` → `docs/architecture/agents.md`
   - `system/commands/**` → `docs/architecture/commands.md`
   - `system/cli/**` → `docs/reference/brana-cli.md`
   - `**/rules/**` → `docs/architecture/rules.md`

   Present via AskUserQuestion:
   ```
   AskUserQuestion:
     question: "Behavioral files changed without docs. Update now?"
     header: "Doc-update check"
     options:
       - label: "Draft doc updates now"
         description: "Read changed behavioral files and write doc updates inline."
       - label: "Add to session handoff (defer)"
         description: "Record doc update as a next[] item for the next session."
       - label: "Skip"
         description: "Defer with a low-priority reminder in next[] (not silently dropped)."
     context: |
       Changed behavioral files:
       - {file} → {suggested doc target}
       ...
   ```

   **If "Draft doc updates now":**
   - For each behavioral file, read it and draft a concise doc update suggestion
   - Present the drafted updates for approval before writing
   - Write approved updates via Edit

   **If "Add to session handoff (defer)":**
   - Add an entry to the session state `next` array (Step 9) with `category: "maintenance"`:
     ```json
     {"text": "Doc update needed: {behavioral file} → {doc target}", "task_id": null, "category": "maintenance"}
     ```

   **If "Skip":** still add a low-priority reminder to `next[]` (never silently drop):
   ```json
   {"text": "Doc update skipped at close: {behavioral file} → {doc target}", "task_id": null, "category": "maintenance"}
   ```
   Then continue to Step 5.

5. **If both behavioral AND documentation files changed**, or no behavioral files changed, skip silently.

6. **Track metrics** for session state (Step 9):
   - `behavioral_files_changed`: count of behavioral files in the diff
   - `doc_files_changed`: count of documentation files in the diff
   - `doc_prompts_accepted`: 1 if "Draft now", 0 otherwise
   - `doc_prompts_skipped`: 1 if "Skip", 0 otherwise

