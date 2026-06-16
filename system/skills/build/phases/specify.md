<!-- build phase: Feature strategy: SPECIFY (+ SPECIFY→DECOMPOSE gate) — loaded per the PHASES registry in ../SKILL.md (t-1942) -->

## Strategy: FEATURE

```
SPECIFY → DECOMPOSE → BUILD → CLOSE
```

### SPECIFY (interactive, open-ended)

The user controls the pace. Stay in the research→discuss loop until the user says to move on.

#### Research loop

**Seed from task metadata:** If attached to a task, extract research keywords from the task's `tags`, `description`, and `context` fields. These are the initial search vectors for all research tracks below.

**DDD activation (opt-in):** if `docs/domain/glossary.md` exists in the project, read it before research. Use the project's ubiquitous language consistently throughout the spec — don't invent new terms when an existing one exists. If the task description introduces a term not in the glossary, propose adding it during draft signal step 1.

Run research in this order — each layer adds context for the next:

1. **Knowledge base** — search ruflo memory + dimension docs using task tags and description keywords
   ```bash
   source "$HOME/.claude/scripts/cf-env.sh"
   cd "$HOME" && $CF memory search --query "{task tags + description keywords}" --namespace knowledge --format json
   ```
2. **Project docs** — grep/read the project's own documentation, existing implementations, CLAUDE.md. Search for task tags and related concepts.
3. **Cross-project patterns** — search claude-flow for patterns from other clients matching task tags
4. **Web research** — spawn scout agents for external research using task description + tags as search terms (parallel with discussion)

#### Present and discuss

- Present findings organized by relevance
- Discuss with the user naturally — goals, constraints, scope, edge cases
- Ask follow-up questions, challenge assumptions gently
- **While the user reads/thinks**, spawn scouts for the next research angle (parallel)

#### Auto-store findings

Every research finding gets stored immediately in ruflo:
```bash
cd "$HOME" && $CF memory store \
  -k "research:{project}:{topic}:{finding-slug}" \
  -v '{"finding": "...", "source": "...", "confidence": 0.3, "ttl_days": 30}' \
  --namespace knowledge \
  --tags "type:research,client:{project},topic:{topic}" \
  --upsert
```
Confidence 0.3 + 30-day TTL: intermediate findings age out if not promoted.

#### Draft signal

When the user says "draft it", "ready", "let's spec this", "move on", or similar:

1. **Auto-suggest dimension doc updates** — check which brana-knowledge dimension docs overlap with the research topics. Use AskUserQuestion:
   ```
   question: "Research touched topics X, Y. Update dimension docs?"
   options: ["Yes — update dim {N}, {M}", "Skip"]
   ```
   If approved, write the updates.

2. **Extract ADR if a load-bearing decision was made.** A "load-bearing" decision is one that constrains future implementation choices — picking a stack, a data model, an interface contract, a workflow ordering. If yes:
   - Allocate next ADR number: `ls docs/architecture/decisions/ADR-*.md | tail -1` → +1.
   - Write to `docs/architecture/decisions/ADR-{NNN}-{slug}.md` with sections: Status, Context, Decision, Consequences, Non-Actions.
   - Mark Status: Proposed (or Accepted if already validated).
   - The feature spec then references the ADR by filename instead of embedding the decision body.

   If no load-bearing decision: skip — the embedded "Decision Record" section in the feature spec is sufficient.

3. **Write feature spec** at `docs/architecture/features/{slug}.md`:
   ```markdown
   # Feature: {title}

   **Date:** YYYY-MM-DD
   **Status:** specifying
   **Task:** t-NNN

   ## Problem
   {from discussion}

   ## Decision Record (frozen YYYY-MM-DD)
   > Do not modify after acceptance.
   **Context:** ...
   **Decision:** ...
   **Consequences:** ...

   ## Constraints
   - {from discussion}

   ## Scope (v1)
   - {from discussion}

   ## Research
   {key findings that informed the decision — auto-populated}

   ## Assumptions
   Surface ambiguities before drafting. If a requirement can be interpreted two ways, ask — don't pick.
   - {assumption 1}

   ## Behavior (optional for S-effort)
   What does this feature do from the user's perspective? Describe the observable behavior.
   - {sentence 1 — what happens when the happy path runs}
   - {sentence 2 — what the user sees / what state changes}
   - {sentence 3 — how success is confirmed}

   ## Edge Cases (optional for S-effort)
   - {edge case 1 — what happens at the boundary}
   - {edge case 2 — what happens when inputs are missing/invalid}

   ## Design
   {technical approach — components, files, patterns}

   ## Boundaries
   | Always | Ask First | Never |
   |--------|-----------|-------|
   | {what this change always does} | {what requires confirmation} | {what this change never touches} |

   ## Testing Strategy
   - **Unit:** {pure logic, no I/O — target 70%+ of test budget}
   - **Integration:** {cross-component or DB/file I/O — target 25%}
   - **E2E:** {CLI smoke or UI flow — target 5%, only if behavior can't be captured lower}
   - **Mock policy:** Real > Fake > Stub > Mock — prefer real collaborators; mock only at system boundaries (network, time, external APIs)

   ## Documentation Plan
   - [ ] **User guide** — `docs/guide/features/{slug}.md`: {what users need — behavior, commands, config, examples}
   - [ ] **Tech doc** — `docs/architecture/features/{slug}.md`: {what contributors need — design rationale, extending, key files}
   - [ ] **Existing docs to update** — {list any affected workflow/command/feature docs}

   ## Challenger findings
   {auto-populated after challenger review}
   ```

4. **Challenger review** — spawn a separate challenger agent (context isolation):
   ```
   Agent(subagent_type="challenger", prompt="Review this feature spec: {spec content}")
   ```
   Incorporate findings into the spec's Challenger findings section.

5. **Promote research** — findings that survived into the final spec get upgraded:
   ```bash
   cd "$HOME" && $CF memory store \
     -k "research:{project}:{topic}:{finding-slug}" \
     -v '{"finding": "...", "confidence": 0.6}' \
     --namespace knowledge --upsert
   ```

6. **Persistence confirmation** (Medium/Large builds) — before presenting the spec, confirm all SPECIFY artifacts are persisted on disk. Use AskUserQuestion:
   ```
   question: "SPECIFY artifacts ready for DECOMPOSE?
     · dim doc updates: {N updated — list paths, or 'none — research did not touch dim docs'}
     · ADR: {ADR-NNN-slug.md, or 'none — no load-bearing decision'}
     · feature spec: {path}"
   options:
     - label: "Confirm — proceed to user review"
       description: "All artifacts present — move to user acceptance review."
     - label: "Missing artifact — back to draft (specify which)"
       description: "Return to draft mode to produce the missing artifact."
     - label: "Decision is load-bearing — extract ADR first"
       description: "Pause implementation and write an ADR before continuing."
   ```
   The "Decision is load-bearing" option loops back to step 2 to extract the ADR before continuing. This gate exists to catch the failure mode where a real architectural choice gets buried inside a feature spec and never surfaces to ADR review.

7. **Present spec to user** for approval. Wait for confirmation before proceeding.

8. Update spec status to `decomposing`.

> **☑ Checkpoint — SPECIFY** (M+ builds with task_id):
> ```bash
> printf '{"step":"SPECIFY","completed":"%s","task_id":"%s"}\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "{task_id}" >> ~/.claude/run-state/{task_id}.jsonl
> ```

### Gate: SPECIFY → DECOMPOSE (Medium/Large only)

Before entering DECOMPOSE, verify the SPECIFY artifact set is persisted on disk:

1. **Feature spec (mandatory)** — check that `docs/architecture/features/{slug}.md` or `docs/features/{slug}.md` exists.
2. **ADR (conditional)** — if step 2 of the Draft signal classified the decision as load-bearing, check that `docs/architecture/decisions/ADR-{NNN}-{slug}.md` exists. The feature spec must reference it by filename. If the spec embeds a populated `Decision Record` block AND no ADR file was written, treat as a load-bearing decision that escaped extraction → block.
3. **Dimension updates (conditional)** — if step 1 of the Draft signal selected dim docs to update, check that those files have a recent commit touching them on this branch (`git diff --name-only main...HEAD | grep brana-knowledge/dimensions/`).

Collect all failures, then gate:
```
question: "SPECIFY → DECOMPOSE gate. Missing: {list}. Fix before proceeding?"
options: ["Fix now (loop back to Draft signal step)", "Skip gate — reason required"]
```
If "Skip gate": require a reason via free text. Log to task notes: `brana backlog set {id} notes --append "SPECIFY→DECOMPOSE gate skipped: {reason}"`.

If all checks pass, proceed silently.

