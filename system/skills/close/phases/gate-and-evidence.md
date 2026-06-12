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

**Weight classification (NANO / LIGHT / INSTANT / FULL) — ADR-052 §5:**

Classify the session depth before spawning any agent. Use `git diff --name-only` — not
`--stat`, which outputs line counts requiring fragile extension parsing.

Since Track 1 (t-1973), sessions that previously auto-classified FULL now classify
**INSTANT**: snapshot + queue + handoff, no in-session extraction — the nightly cron
extracts from the queued diff instead. FULL (the in-session deep debrief) runs **only**
on explicit `--full`.

The classification logic lives in `system/scripts/close-classify.sh` — the
**single source of truth**, executed directly by both this gate and
`tests/procedures/test-close-weight-adaptive.sh`. Never inline or replicate the
matrix here (a replicated copy rotted silently once — t-1978).

```bash
COMMIT_COUNT=$(git log --oneline --since="6 hours ago" 2>/dev/null | wc -l | tr -d ' ')
CHANGED_FILES=$(git diff --name-only HEAD~"${COMMIT_COUNT:-1}"..HEAD 2>/dev/null)

CLOSE_MODE=$(echo "$CHANGED_FILES" | bash "$(git rev-parse --show-toplevel)/system/scripts/close-classify.sh" \
    --commit-count "${COMMIT_COUNT:-0}" --arguments "$ARGUMENTS")
```

**Orientation flags (ADR-053, t-1980).** `$ARGUMENTS` may carry an orientation — `--continue`, `--finish`, `--patterns`, `--abort` — saying WHY the session is closing. close-classify.sh maps orientation to a forced weight (continue/finish → INSTANT, patterns → LIGHT-INLINE, abort → NANO); the call above already passes `--arguments`, so the orientation reaches the classifier with no extra wiring (programmatic callers can equivalently pass `--mode-override <orientation>` — same mapping, same precedence). Set `ORIENTATION` to the flag name when present, `auto` otherwise.

| Orientation | Weight | Task state (Step 9, session-state.md) | Cleanup (Steps 11b/11d) |
|---|---|---|---|
| `--continue` | INSTANT | stays `in_progress` — resumable handoff | skipped |
| `--finish` | INSTANT | → `completed` | runs |
| `--patterns` | LIGHT-INLINE | unchanged | skipped |
| `--abort` | NANO | → `pending` + reason (via close-abort.sh) | script handles branch |

**`--finish` runs the in-session L2 propagation audit** (Step 8b, ADR-056) even though its weight is INSTANT — expect a short LLM pass over touched specs/memories before the handoff. This is the one deliberate exception to "INSTANT = no in-session LLM work"; surface it in the picker's `--finish` description so the user isn't surprised by the latency. Other INSTANT closes run only the ~1s deterministic L1 checks and defer the deep audit to the nightly cron.

**HARD GUARD — flag given means decision made.** If `$ARGUMENTS` contains ANY orientation or weight flag (`--continue`, `--finish`, `--patterns`, `--abort`, `--light`, `--full`, `--nano`): SKIP the entire "Bare-invocation detection and picker" block below. Do not show a picker, do not run detection — execute the flagged close immediately.

**Bare-invocation detection and picker** (no flag in `$ARGUMENTS` only):

1. Compute hard signals (each individually best-effort — a failed command is "no signal", never a block):
   ```bash
   DIRTY=$(git status --porcelain 2>/dev/null | head -1)
   MERGED=$(git branch --merged main 2>/dev/null | grep -v 'main' | grep -c "$(git branch --show-current)" || true)
   TASK_STATUS=$(brana backlog query --status in_progress --output json 2>/dev/null | jq -r '.[0].status // empty' 2>/dev/null || true)
   ```
2. Candidate set from signals: task in flight or dirty tree → `--continue`; branch merged or task completed → `--finish`; both kinds of signal present (conflict — likely stale task state) → all candidates, NO recommended option. `--patterns` is NEVER an auto-detected candidate (git state cannot signal "discoveries happened") — include it only if the conversation shows pattern-worthy material (a workaround found, a gotcha documented, a reusable approach discussed).
3. From conversation context, pick the recommended candidate ("done"/"bye" → `--finish`; "break"/"switching"/context pressure → `--continue`; abandoned approach → `--abort`).
4. Ask — options labeled with their flags (the picker teaches the flags; the user graduates to typing them):
   ```
   AskUserQuestion:
     question: "How should this session close?"
     header: "Close mode"
     options:
       - label: "{Recommended orientation} (--{flag}) (Recommended)"   # omit "(Recommended)" entirely on signal conflict
         description: "{why the signals point here}"
       - label: "{next-likely} (--{flag})"
         description: "..."
       # 2-4 options; AskUserQuestion's built-in Other covers the rest
   ```
5. Treat the chosen flag as if it had been passed in `$ARGUMENTS`: append it to `$ARGUMENTS` and re-run the close-classify.sh line above so `CLOSE_MODE` reflects the choice.

**`--abort` execution:** before anything else, require a reason (free text follows the flag, e.g. `/brana:close --abort "approach invalidated"`; none given → ask). If the tree is dirty, ask: stash / hard reset (show what's lost) / leave. Then run the tested sequence — never inline git commands:
```bash
bash "$(git rev-parse --show-toplevel)/system/scripts/close-abort.sh" \
    --task-id "{active task id}" --reason "{reason}" --dirty "{stash|reset|leave}"
```
The script archives the branch as a pushed `aborted/*` tag, lands on main, returns the task to pending. After it succeeds: write the minimal handoff (Step 9, reason only) and skip everything else.

Ambiguous cases (authoritative — do not infer):
- `.sh` edit → INSTANT (behavioral, high-stakes — cron extracts tonight; `--full` for in-session debrief)
- `tasks.json` only → NANO (state file, single commit — write handoff and skip Steps 4-8)
- `settings.json` → INSTANT (behavioral config — matches `^\.claude/.*\.json$`)

**NANO mode:** write handoff note (Step 9) only. Skip Steps 3–8 entirely (no debrief agent, no errata, no patterns, no field notes, no ideation, no drift). NANO sessions have nothing worth extracting — the overhead costs more than the signal. **NANO does not queue** (ADR-052 §5).

Announce: `Close mode: $CLOSE_MODE (orientation: $ORIENTATION)` before proceeding to Step 1b. The orientation is REQUIRED in the announcement — `--continue` and `--finish` share the INSTANT weight token, and downstream phases (session-state.md task-state mapping, cleanup.md skip rules) resolve behavior from the orientation, not the weight.

### Step 1b: Snapshot + queue (INSTANT / LIGHT / FULL — never NANO, never LIGHT-INLINE)

LIGHT-INLINE (`--patterns`) is structurally excluded here: extraction runs NOW in Step 3, so queueing the same session for the nightly cron would double-extract — the documented exception to ADR-052 §5 (ADR-053 §3). Skip this step entirely for LIGHT-INLINE.

Queue the session diff for tonight's extraction cron (ADR-052; one line, never blocks):

```bash
bash {GIT_ROOT}/system/scripts/close-snapshot.sh \
    --git-root "$(git rev-parse --show-toplevel)" \
    --branch "$(git branch --show-current)" \
    --project "$(basename "$(git rev-parse --show-toplevel)")" \
    --commit-count "${COMMIT_COUNT:-0}"
```

The script captures `git diff HEAD~N..HEAD` to `~/.claude/sessions/snap-*.diff`
(500KB cap), appends a queue entry via `brana close-queue append` (dedup-safe —
re-running close on the same range is a no-op), and degrades to a stderr warning
+ exit 0 if the brana binary is missing. Do not gate close on its output.
Zero commits → it exits silently without queueing.

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

**INSTANT mode** — skip Steps 3–8 entirely. No debrief agent, no errata, no
patterns, no field notes, no ideation, no drift: the queued snapshot carries the
session's diff to tonight's extraction cron (Track 2), which routes findings to
the reminder store. Proceed directly to Step 9 (handoff — `brana session write`
runs as always).

**FULL mode** (explicit `--full` only) — spawn `debrief-analyst` (Sonnet):

```
Agent(subagent_type="debrief-analyst", prompt="Debrief this session. Focus on: what was built, any errata or spec mismatches found, process learnings. Check git log and conversation context.")
```

**LIGHT mode** — inline scan, no agent spawn:
1. `git log --oneline -10` — list what was committed
2. Review conversation for: errors, workarounds, surprises
3. Classify into the three buckets below

**LIGHT-INLINE mode** (`--patterns` orientation) — the user explicitly asked to extract NOW. Run the same inline scan as LIGHT (steps 1–3 above), then Steps 4–5 (errata + patterns) inline. Skip Steps 6–8 (field notes, ideation, drift), skip Step 1b (no queue — ADR-053 §3), skip Step 9c and Steps 10–11, no task-state change, no cleanup. This mode is extraction and nothing else.

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

