<!-- build phase: Feature strategy: DECOMPOSE (+ DECOMPOSE→BUILD gate) — loaded per the PHASES registry in ../SKILL.md (t-1942) -->

### DECOMPOSE

0. **Assumption check** (after strategy confirmed, before decomposing):
   Scan docs related to the task's tags and description for tracked assumptions. Read frontmatter `assumptions:` sections from relevant docs (dimension docs, ADRs, reasoning docs).

   ```bash
   # Search ruflo for assumptions related to task tags
   source "$HOME/.claude/scripts/cf-env.sh"
   cd "$HOME" && $CF memory search --query "{task tags + description keywords}" --namespace assumptions --format json 2>/dev/null || true
   ```

   Also grep project docs for `assumptions:` YAML blocks in files matching the task's topic area.

   **If any assumption has `last_verified` older than its confidence tier threshold** (tech: 6 months, architecture: 18 months, methodology: 36 months), warn:
   ```
   ⚠ Stale assumption in [doc path]: "[claim]". Last verified: YYYY-MM-DD. Verify before proceeding.
   ```

   If no assumptions are stale or no tracked assumptions exist for this area, proceed silently.

1. **Impact analysis** (if `docs/spec-graph.json` exists):
   From the feature description, identify `system/` files likely to be modified. Read `docs/spec-graph.json` and find all nodes whose `impl_files` contain those paths. Display a blast radius table:

   | Doc | Type | Relevant because |
   |-----|------|-----------------|
   | docs/reflections/14-... | impl_files match | Contains system/skills/build references |

   Use this to inform the task breakdown — each affected doc area may need its own task.

   **Fallback:** If `docs/spec-graph.json` doesn't exist, skip impact analysis and proceed directly to task breakdown.

2. **Break spec into ordered tasks** with acceptance criteria.
   - Each task is small enough for one commit
   - Titles are imperative: "Implement X", "Add Y"
   - **AC: syntax** — use these parseable forms for auto-verification at session end:
     ```
     AC: {path} exists                                → H1: file exists
     AC: brana backlog get {id} returns {value}       → H2: task field check
     AC: validate.sh Check {N} passes                 → H3: validate check
     AC: hook {name}.sh exists in system/hooks/       → H4: hook file exists
     AC: file {path} contains "{string}"              → H5: file content check
     AC: jq '{expr}' {file} returns "{value}"         → H6: JSON field check
     AC: "{command}" passes                            → H7: test command (allowlisted)
     AC: changes to {file} committed                  → H8: git log check
     AC: commit message contains "{string}"           → H8: git log --grep check
     # Any other form → UNKNOWN (manual sign-off required)
     # Full reference: docs/conventions/ac-criteria.md
     ```
   - Dependencies are explicit
   - **Include documentation tasks** — for feature/greenfield/migration strategies, the task breakdown MUST include:
     - A user guide task (`docs/guide/features/{slug}.md`)
     - A tech doc task (`docs/architecture/features/{slug}.md`)
     - Tasks to update any existing docs affected by the feature
   - Doc tasks should depend on the implementation tasks they document

3. **Persist tasks** (size-gated):

   **Medium/Large builds:** Persist subtasks via CLI — same mechanism as `/brana:build decompose` mode.
   The spec from SPECIFY provides the decomposition context (no interactive prompts needed).
   ```bash
   # Create subtasks under the current task
   brana backlog add --json '{"subject":"...","type":"subtask","parent":"{task-id}","blocked_by":[...]}'
   ```
   Each subtask gets an ID, deps, and survives across sessions.

   **Trivial/Small builds:** Keep tasks inline in the conversation. No backlog persistence — the build completes in one session anyway.

4. **Sprint contract** (Medium/Large builds with task_id — skip for Trivial/Small and spike/investigation):

   Builder proposes a contract: scope for this build chunk + binary success criteria. Challenger reviews. Agreed contract is written to the task before user approval.

   **Draft the contract:**
   ```
   Sprint Contract — {task_id} — {date}
   ══════════════════════════════════════
   Scope: {one sentence — what will be built in this sprint}

   Success criteria (ISC):
   - {state, not action — "All tests green" not "Run tests"}
   - {measurable end-state verifiable with a command or artifact}

   Out of scope:
   - {what is explicitly deferred}
   ```

   **Challenger review:**
   ```
   Agent(subagent_type="brana:challenger", prompt="Sprint contract review for {strategy} build, task {task_id}.
   Spec summary: {2-3 sentences}
   Contract: {contract text}
   Check: (1) Are criteria binary testable states? (2) Scope aligned with spec? (3) Critical criteria missing? (4) Anything over-scoped? Return numbered findings or 'Contract looks good.'")
   ```
   If challenger raises issues, revise and re-run (max 2 iterations). Unresolved concerns after 2 iterations: surface to user before proceeding.

   **Write agreed contract:**
   ```bash
   brana backlog set {task_id} context --append "Sprint contract {date}: Scope: {scope}. ISC: [{criteria}]"
   brana backlog set {task_id} isc "+{criterion 1}"
   brana backlog set {task_id} isc "+{criterion 2}"
   ```

5. **Present the plan** for approval. Use AskUserQuestion:
   ```
   question: "Task breakdown ready. Approve?"
   options: ["Approve", "Adjust", "Cancel"]
   ```

6. Update spec status to `building`.

> **☑ Checkpoint — DECOMPOSE** (M+ builds with task_id):
> ```bash
> printf '{"step":"DECOMPOSE","completed":"%s","task_id":"%s"}\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "{task_id}" >> ~/.claude/run-state/{task_id}.jsonl
> ```

### Gate: DECOMPOSE → BUILD (Medium/Large only)

Before entering BUILD, verify the task breakdown includes test tasks:
- At least one subtask must mention "test" in its subject or description
- The Documentation Plan from the spec must have entries
- **If either missing:** hard block.
  ```
  question: "BUILD gate: {missing items}. Fix before proceeding?"
  options: ["Add missing items now", "Skip gate — reason required"]
  ```
  If "Skip gate": require a reason. Log: `brana backlog set {id} notes --append "DECOMPOSE→BUILD gate skipped: {reason}"`.

