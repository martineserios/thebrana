<!-- build phase: CLOSE (shared step) — loaded per the PHASES registry in ../SKILL.md (t-1942) -->

<!-- ruflo preamble -->
ToolSearch("select:mcp__ruflo__autopilot_learn")

## CLOSE (shared step)

Runs at the end of: feature, bug fix, greenfield, refactor, migration. NOT spike or investigation.

### Steps

1. **Validate acceptance criteria:**
   - All tasks/acceptance criteria met
   - Tests pass
   - No regressions
   ```markdown
   ### Validation
   - [x] Task 1: {title} — {how verified}
   - [x] All tests pass
   ```

2. **Log build outcome to decision log:**
   ```bash
   brana decisions log main decision \
     "Built {task-id} ({strategy}): {one-line summary of what was built}" \
     --refs "{task-id}" 2>/dev/null || true
   ```

3. **Retrospective** — look back on the build process:
   - What errors or re-approaches happened?
   - What surprised us?
   - What patterns should we store for next time?
   - Store learnings in ruflo:
     ```bash
     cd "$HOME" && $CF memory store \
       -k "pattern:{project}:{slug}" \
       -v '{"problem": "...", "solution": "...", "confidence": 0.5}' \
       --namespace pattern \
       --tags "client:{project},type:build-learning" \
       --upsert
     ```
   If ruflo unavailable, append to project's auto memory MEMORY.md.

   After storing learnings, call:
   ```
   mcp__ruflo__autopilot_learn()
   ```
   This seeds the autopilot pattern registry from completed task outcomes — no params needed.

4. **Knowledge maintenance** (after tests pass, before docs/merge):

   a. **Field notes**: Review session learnings from the build. If any practical discoveries emerged (unexpected behavior, workarounds, integration gotchas, performance findings), prompt the user:
      ```
      question: "Capture any of these as field notes?"
      options: ["Yes — I'll specify which", "No learnings worth capturing", "Auto-capture all"]
      ```
      Only flag obvious, reusable learnings — don't prompt for every mini-debrief. Store approved field notes:
      ```bash
      source "$HOME/.claude/scripts/cf-env.sh"
      cd "$HOME" && $CF memory store \
        -k "field-note:{project}:{slug}" \
        -v '{"observation": "...", "context": "{task-id}", "date": "YYYY-MM-DD"}' \
        --namespace field-notes \
        --tags "client:{project},source:build" \
        --upsert 2>/dev/null || true
      ```
      If ruflo unavailable, append to the relevant doc's Field Notes section (if it has one) or to project auto memory.

   b. **Assumption verification**: If the build touched code related to tracked assumptions (check docs with `assumptions:` frontmatter whose `claim` overlaps with modified files/topics), update `last_verified` date to today in the relevant doc's frontmatter. Only update assumptions the build actually exercised — don't blanket-refresh.

   c. **Changelog update**: If the build changed behavior documented in a reasoning doc (reflections, ADRs, architecture docs), append a changelog entry to that doc:
      ```markdown
      ## Changelog
      - YYYY-MM-DD: {what changed} ({task-id}, {commit hash})
      ```
      If the doc has no Changelog section, add one at the end.

   d. **Reindex**: After any doc updates (field notes, assumption verification, changelog), trigger ruflo reindex for affected files:
      ```bash
      source "$HOME/.claude/scripts/cf-env.sh"
      cd "$HOME" && $CF memory store \
        -k "reindex:{project}:{doc-slug}" \
        -v '{"updated": "YYYY-MM-DD", "reason": "build-close", "task": "{task-id}"}' \
        --namespace knowledge \
        --upsert 2>/dev/null || true
      ```
      If no docs were updated, skip reindex silently.

5. **Update feature spec** (feature, greenfield, migration only):
   - Set status to `shipped`
   - Add learnings from retrospective

6. **Generate documentation** via `/brana:docs`:

   Always invoke — strategy determines scope:

   | Strategy | Args | What gets generated |
   |----------|------|-------------------|
   | Feature / Greenfield / Migration | `all {task-id}` | Tech doc + user guide + shared doc updates |
   | Bug fix | `update {task-id}` | Changelog entry + affected doc updates only |
   | Refactor | `update {task-id}` | Changelog entry + architecture doc updates |

   ```
   Skill(skill="brana:docs", args="{args from table above}")
   ```

   **Shipped without docs means not shipped.**

7. **Update task** (if entered via `/brana:backlog start`):
   - Set status → `completed`
   - Set completed date
   - Add notes from retrospective

8. **GitHub sync** (if `github_sync.enabled` in `~/.claude/tasks-config.json`):
   - If task has `github_issue`: run `system/scripts/gh-sync.sh close {issue-number}`.
   - If sync fails: warn "GitHub issue not closed. Close manually: gh issue close #{issue-number}" — do NOT block CLOSE.

9. **Pre-merge doc check** (feature, greenfield, migration only):
   - Run: `git diff --name-only main...HEAD | grep -E '(docs/architecture/features/|docs/guide/features/)'`
   - **If no doc files in diff:** warn clearly:
     ```
     ⚠ No feature docs found in this branch.
     "Shipped without docs means not shipped."
     Generate docs now? (yes / skip — I'll add them later)
     ```
     If user says yes: invoke `Skill(skill="brana:docs", args="all {task-id}")`.
     If user says skip: proceed to merge (soft enforcement, not a hard block).
   - **If doc files present:** proceed silently.
   - **Bug fix / refactor branches:** skip this check entirely.

10. **Merge** — present the command, do NOT auto-execute:
   ```bash
   git checkout main
   git merge --no-ff feat/{branch-name} -m "{type}: {description}"
   git branch -d feat/{branch-name}
   ```

10b. **Post-merge targeted validate** (t-1485) — after the merge completes, derive which checks apply to the changed files and run only those:
   ```bash
   # Get files changed in the merge (guard: HEAD~1 may not exist on first commit)
   CHANGED=$(git diff --name-only HEAD~1 HEAD 2>/dev/null || true)

   # Map files → check numbers
   CHECKS=$(echo "$CHANGED" | bash system/scripts/check-selector.sh | tr '\n' ' ')

   if [ -n "$CHECKS" ]; then
       echo "Running targeted checks for changed files: $CHECKS"
       for check in $CHECKS; do
           ./validate.sh --check "$check" || echo "⚠ Check $check failed — review before shipping"
       done
   else
       echo "No targeted checks detected for changed files — skipping."
   fi
   ```
   Present any failures inline. This is advisory (individual check failures surface as warnings, not blocks) — the full `./validate.sh` run at the BUILD→CLOSE gate is the authoritative pass. Skip for spike and investigation strategies.

11. **Reconcile check** (post-merge, before docs):
   If `docs/spec-graph.json` exists, check whether merged files appear in any spec-graph node's `impl_files`. If matches found, offer to run `/brana:reconcile`:
   ```
   question: "Merged files touch spec-documented systems: {list}. Run reconcile?"
   options: ["Yes — run /brana:reconcile", "Skip — I'll reconcile later"]
   ```
   If the user says yes, invoke `Skill(skill="brana:reconcile")`.
   If no spec-graph hits, skip silently.

12. **Update living docs** (post-merge, on main):
   Invoke `/brana:docs all` to update system-level documentation:
   - `reference` — regenerate catalogs from frontmatter (deterministic)
   - `marketplace` — sync plugin marketplace metadata (counts, version)
   - `guide` — update affected user guide docs (from spec-graph `guide_files`)
   - `tech` — update affected architecture docs (from spec-graph `arch_files`)
   - `overview` — refresh philosophy.md (only if core behavior changed)

   For **existing shared docs**: show a diff preview before committing.
   For **new per-feature docs**: auto-commit (already handled in step 6).
   Commit on main: `docs: update living docs after {task-id}`

   Skip silently if no spec-graph hits (not every build touches documented systems).

13. **Report:**
   ```markdown
   ## Build Complete: {title}

   **Strategy:** {type}
   **Branch:** {branch}

   ### What was built
   | # | Task | Commit | Verified |
   |---|------|--------|----------|
   | 1 | {description} | {hash} | {how} |

   ### What was learned
   - {key learnings stored}

   ### Docs updated
   - {list of doc changes}

   ### Knowledge maintained
   - {field notes captured, assumptions verified, changelogs updated}
   ```

> **☑ Checkpoint cleanup — CLOSE:** Delete run-state on successful close (M+ builds with task_id):
> ```bash
> rm -f ~/.claude/run-state/{task_id}.jsonl
> ```

---

