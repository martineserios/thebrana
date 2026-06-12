<!-- close phase: Step 8b: PROPAGATE — layered propagation-debt audit — loaded per the PHASES registry in ../SKILL.md (t-2003, ADR-056) -->

## Step 8b: PROPAGATE

Audit knowledge-propagation debt before the handoff is written, so every gap
feeds the single Step 9 `next[]` write. Origin: proyecto_anita t-1306 — a
clean 18-commit close that left 7 undetected gaps. Full design: ADR-056.

**Gate (from the Step 1 announcement — instruction context, no env vars
survive phase boundaries):**

| Announced state | Action |
|---|---|
| `CLOSE_MODE` = NANO, or orientation `--abort` | Announce `PROPAGATE: skip ({reason})` → go to Step 9 |
| orientation `--finish`, or `CLOSE_MODE` = FULL | L1 + L2 |
| any other non-NANO close | L1 only (entry stays `propagate: true` for the nightly L3 audit) |

This gate is **orientation/weight-keyed, not Steps-4-8-gate-keyed** — L2 runs
on `--finish` even though `--finish` forces weight INSTANT. Declaring work
finished is exactly when unfulfilled promises must be checked (ADR-056 §1,
amending ADR-053).

**Re-entry guard (resume after compression):** before running anything, check
whether this session already announced propagation gaps (a `PROPAGATE-L1:`
line in recent context) or a `fix(propagate):` commit sits at HEAD
(`git log -1 --format=%s | grep -q '^fix(propagate)'`). If so, skip — L2 is
LLM judgment; re-running is not a no-op and duplicates `next[]` entries.

### L1 — deterministic checks (every non-skipped close)

Compose and run the block below as **one bash invocation**, setting the env
vars from instruction context:

- `CLOSE_MODE`, `ORIENTATION` — from the Step 1 gate announcement (empty
  orientation for bare invocations).
- `CHANGED_FILES` — the newline-separated list captured in Step 1.
- `ACTIVE_TASK_ID` — the session task, if any. Empty when task-less;
  if multiple tasks are `in_progress`, pass the primary one only and note
  the others for L2.
- `ACTIVE_TASK_STATUS` — the **intended post-close state**, not the live
  field (at Step 8b the task is still `in_progress`; Step 9 sets the final
  state). Pass `completed` when orientation is `--finish` or the task's work
  is done; `in_progress` otherwise. Empty when task-less.

The block is flat bash between extraction markers (no code fences inside —
`tests/procedures/test-close-propagate.sh` extracts and executes it; that
test is the contract).

<!-- L1-BLOCK -->
# PROPAGATE L1 — deterministic propagation-debt checks (ADR-056).
# env in: CLOSE_MODE ORIENTATION CHANGED_FILES ACTIVE_TASK_ID ACTIVE_TASK_STATUS
# stdout: PROP-GAP|... / PROP-CANDIDATE|... / PROPAGATE-L1 summary. Always exits 0.
if [ "${CLOSE_MODE:-}" = "NANO" ]; then
    echo "PROPAGATE: skip (NANO)"
elif [ "${ORIENTATION:-}" = "abort" ]; then
    echo "PROPAGATE: skip (abort)"
else
    GAPS=0
    CANDS=0
    # Origin gap #7 — task state modified but uncommitted
    if git status --porcelain 2>/dev/null | grep -qE '(^|[ /])[^ ]*tasks\.json'; then
        echo "PROP-GAP|tasksjson|tasks.json has uncommitted changes — task state not persisted"
        GAPS=$((GAPS + 1))
    fi
    # Per touched markdown doc: checkboxes, status field, promise heuristic
    while IFS= read -r f; do
        [ -n "$f" ] && [ -f "$f" ] || continue
        case "$f" in *.md) ;; *) continue ;; esac
        # Origin gap #3 — unchecked Documentation Plan items
        UNCHECKED=$(awk '/^#+ Documentation Plan/{flag=1; next} /^#+ /{flag=0} flag' "$f" | grep -c '^- \[ \]')
        if [ "${UNCHECKED:-0}" -gt 0 ]; then
            echo "PROP-GAP|checkbox|$f|$UNCHECKED unchecked Documentation Plan item(s)"
            GAPS=$((GAPS + 1))
        fi
        # Origin gap #1 — Status field contradicts the task's post-close state.
        # Skip when task-less or multi-task-ambiguous (HIGH-1 rule).
        if [ -n "${ACTIVE_TASK_ID:-}" ] && [ "${ACTIVE_TASK_STATUS:-}" = "completed" ]; then
            SVAL=$(grep -m1 -iE '^[*]*status' "$f" | sed -E 's/^[*]*[Ss]tatus:?[*]*:?[[:space:]]*//')
            if [ -n "$SVAL" ] && echo "$SVAL" | grep -qiE 'pending|specifying|decomposing|building|in.progress|draft|proposed'; then
                echo "PROP-GAP|status|$f|Status '$SVAL' vs task $ACTIVE_TASK_ID '$ACTIVE_TASK_STATUS'"
                GAPS=$((GAPS + 1))
            fi
        fi
        # Promise heuristic — candidates for L2 judgment, never auto-flagged as gaps
        PROMISES=$(grep -niE 'al cerrar|on close' "$f" | head -5)
        if [ -n "$PROMISES" ]; then
            while IFS= read -r line; do
                echo "PROP-CANDIDATE|promise|$f|$line"
                CANDS=$((CANDS + 1))
            done <<EOF_PROMISES
$PROMISES
EOF_PROMISES
        fi
    done <<EOF_FILES
${CHANGED_FILES:-}
EOF_FILES
    echo "PROPAGATE-L1: $GAPS gap(s), $CANDS candidate(s)"
fi
true
<!-- /L1-BLOCK -->

### L2 — session-bounded LLM audit (`--finish` / FULL only)

Bounded inputs only — no repo-wide sweeps (ADR-056 §3):

| Category | Read | Detect |
|---|---|---|
| (a) committed artifacts | Documentation Plans of touched specs; L1 promise candidates | promised artifacts (`- [ ]` items, "al cerrar X" / "on close X") that were never produced |
| (b) status semantics | Status/phase fields and tables of touched specs/shapes | claims contradicting the task's post-close state (beyond L1's vocabulary match) |
| (c) cross-references | only docs **named** in touched specs' "Existing docs to update" lines | named docs that don't mention the new work |
| (d) memories | current project's `.claude/memory/` files | claims contradicted by current state (e.g. "pending go" for completed work) |
| (e) challenger findings | the current conversation only | verdicts/routings ("route to X") that never landed anywhere |

**Output contract — zero silent drops.** Every gap becomes exactly one of:

1. **Inline fix** — small doc edits only (>3 files or any non-doc file →
   ask first). After applying, **commit immediately**:
   `git add {fixed files} && git commit -m "fix(propagate): inline propagation gaps [close: {task_id}]"`.
   Uncommitted fixes are invisible to the Step 1b snapshot and drift into
   the next session (ADR-056 §2).
2. **`next[]` entry** — carried to Step 9 as
   `{"text": "{gap + proposed fix}", "task_id": null, "category": "maintenance"}`.

**On L2 success** (audit ran to completion, regardless of gap count), clear
the L3 flag so the nightly cron doesn't re-audit this close:

    "$(git rev-parse --show-toplevel)/system/cli/rust/target/release/brana" close-queue mark-propagated \
        --project "{project}" --branch "{branch}" --git-range "{git_range}" 2>/dev/null \
        || brana close-queue mark-propagated --project "{project}" --branch "{branch}" --git-range "{git_range}" 2>/dev/null \
        || true

(`{git_range}` is the range Step 1b queued. Best-effort — if the clear fails,
L3 re-audits; redundant but safe. If L2 failed or was interrupted, do NOT
call this: the flag staying set is the fail-safe, ADR-056 §4.)

### Report

Carry to Step 12's report line: `**Propagation gaps:** {N found} ({M fixed
inline + committed, K → next[])}` — and hand the `next[]` entries to Step 9
as instruction context. Never end this step with a detected gap that is
neither fixed nor in the handoff payload.

---
