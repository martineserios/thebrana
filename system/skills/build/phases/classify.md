<!-- build phase: Step 1: CLASSIFY + Step 2: APPROVE + Task Integration — loaded per the PHASES registry in ../SKILL.md (t-1942) -->

## Step 1: CLASSIFY

Mandatory. One interaction. Never skip.

### Detection rules

Analyze the description (and task metadata if from `/brana:backlog start`) to propose a strategy:

| Strategy | Stream signal | Description signal |
|----------|-------------|-------------------|
| **Feature** | `roadmap` | Default — anything that adds capability |
| **Bug fix** | `bugs` | "fix", "broken", "crash", "bug", "error", "wrong", "fails" |
| **Greenfield** | — | "start", "new project", "create project", "from scratch" |
| **Refactor** | `tech-debt` | "refactor", "restructure", "clean up", "simplify", "reorganize" |
| **Spike** | `experiments` | "can we", "test if", "try", "spike", "prototype", "feasibility" |
| **Migration** | — | "migrate", "switch from", "move to", "upgrade", "replace X with Y" |
| **Investigation** | `research` | "why", "investigate", "understand", "debug", "diagnose", "analyze" |

### 3-Level Detection (per smart-router pattern)

**Level 1 — Signal match.** Apply the table above. If stream or description keywords produce a clear match (one strategy scores highest), propose it with confidence: high.

**Level 2 — Ask user.** If no signal matches or multiple strategies tie, present all viable options via AskUserQuestion.

The existing AskUserQuestion confirmation always runs regardless of level — but with Level 1, the recommended option is pre-selected. Without Level 1, all options are equal weight.

> See `system/skills/_shared/smart-router.md` for the shared 2-level pattern. /build and /research both use this pattern.

### Confirmation

Use AskUserQuestion:
```
question: "Detected: {strategy}. Correct?"
options:
  - label: "{detected strategy} (Recommended)"
    description: "Use the auto-detected build strategy."
  - label: "Feature"
    description: "New functionality — will need tests and docs."
  - label: "Bug fix"
    description: "Corrects a defect in existing behavior."
  - label: "Refactor"
    description: "Restructures code without changing behavior."
  - label: "Spike"
    description: "Time-boxed exploration to validate an approach."
```
Header: "Strategy"

### Mid-stream reclassification

At any point during the build, the user can say "this is actually a {type}" and Claude shifts strategy. When reclassifying:
- If moving TO a strategy with SPECIFY: start SPECIFY from current knowledge (don't lose work)
- If moving FROM spike to feature: the spike findings become SPECIFY context
- If moving FROM investigation to bug fix: the report becomes REPRODUCE evidence

> **☑ Checkpoint — CLASSIFY** (M+ builds with task_id):
> ```bash
> printf '{"step":"CLASSIFY","completed":"%s","task_id":"%s"}\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "{task_id}" >> ~/.claude/run-state/{task_id}.jsonl
> ```

---

## Step 2: APPROVE

**Mandatory for Medium/Large builds.** After CLASSIFY confirms the strategy, present the step sequence and get approval before executing. **Do NOT use CC plan mode (EnterPlanMode) — use AskUserQuestion for approval.**

### Lifecycle gate (always — even S-effort)

Before planning the steps, assess which disciplines apply. State the result explicitly — even if all are "no."

| Discipline | Apply when | Skip when |
|-----------|-----------|-----------|
| **DDD** (Domain-Driven Design) | `docs/domain/` exists AND task introduces or refines a domain entity, aggregate, bounded context, or cross-context change | `docs/domain/` absent, or task is correction/single-file patch |
| **SDD** (Spec-Driven Development) | Behavioral decision with architectural trade-offs (ADR needed) | Pure correction where the task description IS the spec |
| **TDD** (Test-Driven Development) | Code that can be tested (hooks, CLI, scripts, functions) | Docs-only, config-only, procedure files |

Output one line per discipline:
```
DDD: skip — no docs/domain/ in this project (opt-in)
SDD: skip — task description serves as spec (correction, no ADR needed)
TDD: apply — hook code change, write failing test first
```

If DDD applies, read `docs/domain/glossary.md` and use the ubiquitous language consistently. Propose glossary additions for any new terms introduced by the task.
If SDD applies, write or reference the ADR/spec **before** the first Edit/Write call.
If TDD applies, the BUILD step must follow red-green-refactor.

> See [docs/reflections/32-lifecycle.md](../../../../docs/reflections/32-lifecycle.md) §"The Development Workflow" for the full DDD → SDD → TDD → Code rationale.

### Backlog lifecycle check (M+ tasks with task_id)

For tasks with effort M, L, or XL that have a `task_id`, verify lifecycle artifacts are planned in the backlog before building:

```bash
brana backlog query --tag "sdd,ddd,test,tdd" | grep -i "<task-id or subject keywords>"
# OR
brana backlog search "<subject keywords>" | grep -E "sdd|spec|ddd|test"
```

- **DDD applies and no DDD task in backlog:** surface warning — "No DDD task found for this M+ build. Domain glossary update may be missing."
- **SDD applies and no SDD/spec task in backlog:** surface warning — "No SDD/spec task found. Behavioral spec should be planned before implementation."
- **TDD applies and no test task in backlog:** hard gate — mirror the plan step 11 TDD gate (AskUserQuestion before proceeding).
- **If lifecycle tasks exist:** proceed silently.
- **If task has no task_id or effort < M:** skip this check.

1. **Present the strategy's step sequence** inline:
   ```
   ## Build Steps: {task subject}
   Strategy: {detected strategy}
   Size: {sizing}

   Steps:
   1. SPECIFY — research loop, draft feature spec
   2. DECOMPOSE — break spec into ordered tasks
   3. BUILD — TDD loop per task
   4. CLOSE — validate, retrospective, docs, merge
   ```
   Adapt the steps to the detected strategy (bug fix uses REPRODUCE → DIAGNOSE → FIX → CLOSE, etc.).
2. **Get approval** via AskUserQuestion:

   **For S/XS tasks:**
   ```
   question: "Build steps above. Proceed?"
   options: ["Approve", "Adjust", "Cancel"]
   ```

   **For M+ tasks**, include a premortem option:
   ```
   question: "Build steps above. Proceed?"
   options:
     - "Approve — start building"
     - "Run premortem first — assume this fails, find out why (uses /brana:challenge --premortem)"
     - "Adjust the plan"
     - "Cancel"
   ```

   If "Run premortem first" is chosen:
   - Invoke `/brana:challenge --premortem` with the planned task/spec as target.
   - After the premortem report is presented, re-ask the approval question.
   - Premortem findings become context — the user decides whether to adjust the plan or proceed.
   - This is NOT a blocking gate: the user can review premortem findings and proceed anyway.

3. **If the user adjusts**, incorporate changes and re-present.
4. **Proceed to the first step** of the approved strategy.

For **Trivial/Small** builds: skip the approval gate, proceed directly. State the steps inline: "This is small — I'll SPECIFY (light) → BUILD → CLOSE."

---

## Task Integration

### Entry via /brana:backlog start

When `/brana:backlog start <id>` invokes this skill:

1. **Task metadata is pre-loaded:**
   - `subject` → seeds the description
   - `stream` → informs strategy detection
   - `tags` → inform research scope
   - `description` → additional context
   - `context` → prior research, notes, links; `AC:` lines drive goal injection (Step 0 sub-step 0)
   - `blocked_by` → verified all resolved

2. **Skip cross-reference** (task already identified).

3. **CLASSIFY uses the 2-level smart router** (signal match → ask user):
   - Level 1 — stream as primary signal: `roadmap` → feature, `bugs` → bug fix, `tech-debt` → refactor, `experiments` → spike, `research` → investigation. Description signals override if clearer.
   - Level 2 — AskUserQuestion if signal is ambiguous or missing.

4. **Branch created from task convention** (handled by `/brana:backlog start` — see the backlog skill's `phases/start.md` §Branch creation):
   `{epic-slug}/{work-type}/t-{NNN}-{subject-slug}`

5. **CLOSE auto-completes the task.**

### Task fields updated during build (via CLI)

The build loop updates fields via `brana backlog set`:

```bash
# CLASSIFY
brana backlog set <id> status in_progress
brana backlog set <id> started 2026-03-14
brana backlog set <id> strategy feature
brana backlog set <id> build_step classify

# SPECIFY → DECOMPOSE → BUILD (update build_step as loop progresses)
brana backlog set <id> build_step specify
brana backlog set <id> build_step decompose
brana backlog set <id> build_step build
brana backlog set <id> branch "feat/t-123-slug"

# CLOSE
brana backlog set <id> status completed
brana backlog set <id> completed 2026-03-14
brana backlog set <id> build_step null
brana backlog set <id> notes --append "Retrospective findings here"
```

### Creating tasks automatically

When `/brana:build` is invoked WITHOUT `/brana:backlog start`:

1. After CLASSIFY, create via CLI:
   ```bash
   brana backlog add --json '{"subject":"{description}","work_type":"{from strategy}","type":"task","execution":"code"}'
   # Then set status + dates:
   brana backlog set t-{N} status in_progress
   brana backlog set t-{N} started YYYY-MM-DD
   brana backlog set t-{N} build_step specify
   ```
2. Confirm with user: "Created t-{N} for this work. Proceeding."
3. CLOSE updates this task to completed.

### Strategy transitions create linked tasks

- **Spike → Feature:** spike ANSWER creates a feature task with context: "Validated in spike t-{N}"
- **Investigation → Bug fix:** investigation REPORT creates a bug fix task with context: "Root cause from investigation t-{N}"
- Linked via `context` field, not `blocked_by` (the predecessor is already complete).

---

