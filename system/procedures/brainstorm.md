
# Brainstorm

Interactive idea maturation. You have a rough idea — this skill helps you explore it,
research what exists, challenge assumptions, and shape it into something concrete.

## Usage

`/brana:brainstorm [idea]`

- With idea: start exploring immediately
- Without idea: ask what's on your mind

## Principles

1. **The user leads.** They own the idea. You research, challenge, and structure — never hijack.
2. **Interactive always.** Every phase uses AskUserQuestion for direction. Never monologue.
3. **Research proactively.** When a tool, framework, or concept is mentioned, auto-fetch context.
4. **Diverge then converge.** First widen (explore angles), then narrow (pick direction).
5. **Concrete over abstract.** Push toward specifics — who, what, how, when.

## Step Registry

On entry, create a CC Task step registry. Follow the [guided-execution protocol](../_shared/guided-execution.md).

Register these steps: LOAD, SEED, EXPAND, DISCUSS, SHAPE, OUTPUT, EXTRACT, EVALUATE, PERSIST.

<!-- ruflo preamble -->
ToolSearch("select:mcp__ruflo__memory_search,mcp__ruflo__agent_spawn,mcp__ruflo__hive-mind_init,mcp__ruflo__hive-mind_spawn,mcp__ruflo__hive-mind_consensus,mcp__ruflo__hive-mind_shutdown")

## Procedure

### Step 0 — LOAD

Pull relevant knowledge into context before the brainstorm begins. Budget: 30K tokens max.

1. **Build query** from available context: `"{project} {task.subject} {task.tags joined} {user_input}"`
2. **Primary — ruflo MCP (run both in parallel — `namespace: "all"` only returns session records; `specs` namespace is unindexed):**
   ```
   mcp__ruflo__memory_search(query: "{query}", namespace: "knowledge", limit: 4, threshold: 0.4)
   mcp__ruflo__memory_search(query: "{query}", namespace: "pattern",   limit: 3, threshold: 0.4)
   ```
   Merge results, rank by similarity. Focus on: dimension docs, idea docs (`docs/ideas/`), and recent research findings.
2b. **Graph edge traversal** — see `build.md` LOAD step 2b. Follow `depends_on`/`informs` edges from knowledge results. Max 3 graph-derived docs. Best-effort, never blocks.
3. **Fallback — tag-based grep** (if MCP unavailable):
   ```bash
   grep -rl "{keywords}" ~/enter_thebrana/brana-knowledge/dimensions/ --include="*.md" | head -5
   grep -rl "{keywords}" docs/reflections/ docs/ideas/ --include="*.md" | head -5
   ```
   Read the top 3 matching files (first 80 lines each).
4. **Skill match handling** — if any result has `namespace: "skills"` and score >= 0.5, mention inline: "Matching skill: /brana:{name} ({score})." Informational only — don't auto-invoke or block.
4a. **JIT skill acquisition** — if no skills match and topic involves a specific technology, offer marketplace search via `Skill(skill="brana:acquire-skills", args="{tech}")`. Read installed procedure into context immediately. See `build.md` LOAD step 4a for full logic and guard rails.
5. **Summarize loaded knowledge** as a brief context preamble (2-5 bullets). Do not show raw results — synthesize what's relevant to the seed idea.

### Phase 1 — Seed

Parse `$ARGUMENTS`:
- If provided: use as the seed idea, proceed to Phase 2
- If empty: ask the user

```
AskUserQuestion:
  question: "What's the idea you want to explore?"
  header: "Seed"
  options:
    - "A product or feature"        → "What problem does it solve?"
    - "A business opportunity"      → "Who's the customer?"
    - "A process improvement"       → "What's broken today?"
    - "Something else"              → free text
```

Capture the seed. Restate it back in one sentence to confirm understanding.

If `--goal` was passed, derive the slug (lowercase, hyphenated from the seed) and call `/goal`:

```
/goal "brainstorm {slug}: explore → challenge → shape → save — idea doc committed at docs/ideas/{slug}.md"
```

### Phase 2 — Expand

Explore the idea space. Run these in parallel:

**2a. Context scan** — search the codebase and project docs for related work:
- Grep for keywords from the seed across docs/, system/, and tasks.json
- Check if related tasks already exist in the backlog
- Report: "Found N related items" (list briefly)

**2b. Auto-research** — if the seed mentions any tool, platform, framework, or technical concept:
- Spawn a scout agent via ruflo for cost tracking:
  ```
  mcp__ruflo__agent_spawn(agentType: "Explore", model: "haiku", domain: "{active_project}", task: "Search codebase for: {seed keywords}")
  ```
  Fall back to `Agent(subagent_type: "Explore", model: "haiku")` if ruflo is unavailable.
- Run WebSearch for the concept (1-2 queries max)
- Summarize findings in 3-5 bullets
- If a library is mentioned, use context7 MCP to get latest docs

**2c. Ask for dimensions** — use AskUserQuestion:

```
AskUserQuestion (batch up to 4 questions):

  question: "Who benefits most from this?"
  header: "Audience"
  options: [contextual — inferred from the seed]

  question: "What's the scale? Quick experiment or long-term investment?"
  header: "Scale"
  options:
    - "Quick experiment (hours/days)"
    - "Small project (1-2 weeks)"
    - "Significant investment (weeks+)"
    - "Not sure yet"

  question: "What does success look like?"
  header: "Success"
  options: [contextual — inferred from the seed, e.g., "Revenue", "Time saved", "User engagement", "Learning"]

  question: "Any constraints or non-negotiables?"
  header: "Constraints"
  options:
    - "Budget limited"
    - "Time pressure"
    - "Must integrate with existing system"
    - "None / not sure"
```

### Phase 3 — Discuss & Challenge

This is the core of the brainstorm — an interactive back-and-forth dialogue.
Not a list of risks. A real conversation where you push back, ask hard questions,
and help the user stress-test their thinking.

**This phase loops until the user is ready to move on.**

#### Round 1 — Proactive challenge

Pick the **weakest assumption** in the idea so far. State it directly, then ask:

```
AskUserQuestion:
  question: "You're assuming {assumption}. What if that's wrong?"
  header: "Challenge"
  options:
    - "Good point — let me rethink"     → discuss alternatives together
    - "I've validated this because..."  → user defends, you probe deeper
    - "It's a bet I'm willing to take"  → acknowledge, move to next challenge
    - "Actually, let me explain..."     → free text, then respond to their reasoning
```

**Respond to their answer.** Don't just acknowledge — engage:
- If they rethink: suggest 2 alternative approaches, ask which resonates
- If they defend: ask a follow-up that tests the defense ("How would you know if...")
- If they accept the risk: name what failing would look like, ask if that's survivable

#### Round 2 — Flip the perspective

Take the opposite position. If the user wants to build something, argue for buying.
If they want to go fast, argue for going slow. If they want simple, argue for comprehensive.

State the counter-position in 2-3 sentences, then:

```
AskUserQuestion:
  question: "Playing devil's advocate: {counter-position}. What's wrong with this argument?"
  header: "Counter"
  options:
    - "That's actually a good point"     → explore the counter-position together
    - "Here's why that won't work..."    → free text defense
    - "Both could work — help me decide" → comparative analysis
    - "Skip — I'm confident in my direction"
```

#### Round 3+ — Follow the thread

Based on the discussion so far, either:

**A) Drill deeper** — if an interesting tension surfaced, explore it:
- "You said {X} but earlier you said {Y} — how do those fit together?"
- "What would {audience} say about this?"
- "If you had to cut one thing, what goes?"

**B) Widen the lens** — if the idea survived all challenges without contradiction, explore adjacent territory:
- "Who else has tried something like this? What happened?"
- "What's the version of this that's 10x simpler?"
- "What would make this a must-have instead of a nice-to-have?"

Each round uses AskUserQuestion with contextual options. Keep rounds short — one
question at a time, real responses, not lectures.

#### Exit

After each round, offer an exit:

```
AskUserQuestion:
  question: "Keep discussing, or ready to shape this into something concrete?"
  header: "Continue?"
  options:
    - "Keep going — I want to explore {aspect}"
    - "Challenge me harder on {topic}"
    - "Ready to shape it"               → proceed to Phase 4
    - "Let me think — save what we have" → jump to Phase 5 with current state
```

If the user mentions a new concept during any round, **auto-research it**
(WebSearch, 1 query) and fold findings into the next response before asking
the next question.

#### 3b — Incremental persistence

After each round (Round 1 always, Round 2+ whenever new ground was covered):

1. **If `docs/ideas/{slug}.md` does not exist yet:** create it now with the frontmatter stub and the first section derived from what was just discussed.
   ```markdown
   ---
   title: {Title}
   status: idea
   created: {date}
   ---
   # {Title}
   > Brainstormed {date}. Work in progress.
   ```
2. **If it already exists:** append or update the relevant section (Problem, Solution, Risks, etc.) based on the current discussion.
3. Tell the user: "Saved to `docs/ideas/{slug}.md` — continuing."

The doc grows section-by-section throughout Phase 3. By the time Phase 5 runs, most content is already written. **Context compression cannot lose discussion output because it was persisted immediately.**

#### Discussion behavior rules

- **One question at a time.** Never stack 3 challenges — ask one, respond, ask the next.
- **React to their answers.** Reference what they said. "You mentioned X — that changes things because..."
- **Escalate, don't repeat.** Each round goes deeper than the last. Never re-ask the same challenge.
- **Name your role.** Say "Playing devil's advocate here..." or "Pushing back on this..." so the user knows you're challenging, not disagreeing.
- **Acknowledge strong defenses.** When the user addresses the specific objection with evidence or logic, say so: "That answers the [specific concern] — it holds up because [reason]."
- **Research mid-discussion.** If the user mentions a competitor, tool, or reference you don't know, search for it immediately and bring findings into the next question.

### Phase 4 — Shape

Synthesize everything into a structured summary. Present it as a preview:

```
## Idea: {title}

**Problem:** {one sentence}
**Solution:** {one sentence}
**Audience:** {who}
**Scale:** {effort level}
**Success metric:** {what good looks like}

### Key insights from research
- {finding 1}
- {finding 2}
- {finding 3}

### Risks and mitigations
- {risk → mitigation}

### Engineering disciplines
- **DDD (Decision):** {ADR needed? What architectural decision does this encode?}
- **TDD (Tests):** {What tests should be written before implementation?}
- **SDD (Spec/Docs):** {What docs need updating after implementation?}
- **Docs (/brana:docs):** {Which doc types apply per strategy table below?}
  - Tech doc: `docs/architecture/features/{slug}.md` — {yes/no, why}
  - User guide: `docs/guide/features/{slug}.md` — {yes/no, why}
  - Shared docs: `docs/guide/commands/index.md` updates? workflow docs? — {list}
  - Overview: `docs/guide/philosophy.md` — {only if system-level patterns changed}
  - Spec-graph routing: {files whose `impl_files` overlap with expected changes}

### Possible next steps
1. {step 1}
2. {step 2}
3. {step 3}
```

Then ask:

```
AskUserQuestion:
  question: "How does this look? What should we adjust?"
  header: "Review"
  options:
    - "Looks good — save it"
    - "Adjust the direction"       → loop back to specific section
    - "Research more on {topic}"   → run targeted research, then re-present
    - "Scrap it — not worth pursuing"
```

Allow multiple refinement loops. Each loop re-presents the updated summary.

### Phase 5 — Output

When the user approves ("Looks good — save it"):

**5a. Finalize idea doc**

The idea doc at `docs/ideas/{slug}.md` was built incrementally during Phase 3b. Phase 5 refines and completes it — it does not start from scratch. Open the existing file and:
- Fill in any sections that are still placeholders
- Replace "Work in progress" status with `idea` (or `draft` if well-formed)
- Add the full Phase 4 shape summary if not yet present

If `docs/ideas/{slug}.md` does not exist (brainstorm was short or Phase 3b was skipped), create it now at `docs/ideas/{slug}.md`:

```markdown
# {Title}

> Brainstormed {date}. Status: idea.

## Problem

{problem statement}

## Proposed solution

{solution description}

## Research findings

{key findings from Phase 2}

## Risks

{risks and mitigations from Phase 3}

## Next steps

{action items from Phase 4}
```

**5b. Plan the backlog**

**GATE: Check effort level from Phase 4 SHAPE.** If effort is M+ (Small project / 1-2 weeks or higher):

```
AskUserQuestion:
  question: "This is an M+ effort. Confirm governance tasks before backlog planning?"
  header: "Governance Gate"
  options:
    - "Yes — include DDD/TDD/SDD/Docs tasks" → proceed to backlog plan
    - "Override (skip + file tech-debt task)" → skip governance tasks AND add a P2 tech-debt task to backlog: 'Add DDD/TDD/SDD/Docs coverage to {idea slug} plan'
    - "Back to SHAPE"                        → return to Phase 4 to reassess
```

This gate catches brainstorms that identified engineering disciplines in SHAPE but would
otherwise forget to create the corresponding backlog tasks. It's the last checkpoint before
planning commits the idea to structured execution.

**M+ challenger review** — before backlog planning, run a hive-mind 3-worker challenge on the shaped idea:
```
mcp__ruflo__hive-mind_shutdown(force: true)
mcp__ruflo__hive-mind_init(consensus: "quorum", topology: "hierarchical")
mcp__ruflo__hive-mind_spawn(count: 3, role: "specialist", prefix: "brainstorm-challenger")
mcp__ruflo__hive-mind_consensus(action: "propose", strategy: "quorum", quorumPreset: "majority", type: "brainstorm-findings", value: "{shaped idea summary}")
```
Worker roles: convergent (what must hold?), systems (second-order effects?), critical (failure modes?).
Findings confirmed by ≥2 workers surface as HIGH confidence — present these before the backlog question.
**Fallback:** If ruflo unavailable, invoke `Skill(skill="brana:challenge", args="{shaped idea title}")` instead.

---

```
AskUserQuestion:
  question: "Plan this idea into the backlog?"
  header: "Backlog"
  options:
    - "Yes — plan phases & tasks"  → invoke /brana:backlog plan with the idea as input
    - "Not yet — just save the doc"
    - "Quick add (flat task only)"  → single task via backlog_add() (MCP) or brana backlog add
```

**If "Yes — plan phases & tasks"** (default, recommended):
Invoke `/brana:backlog plan` via the Skill tool immediately:
```
Skill(skill="brana:backlog", args="plan \"{idea title}\"")
```
The plan skill will interactively create the full phase/milestone/task hierarchy
using the brainstorm's phased rollout as input. This is the **mandatory default** —
a brainstormed idea with phases and next steps deserves structured planning, not a flat task.

**DDD/TDD/SDD/Docs tasks are mandatory when planning.** For any effort M+ idea, the planned
phase must include:
- **DDD task:** Write an ADR documenting the decision (before implementation tasks)
- **TDD tasks:** Write tests before implementation (blocked_by: ADR, blocks: impl tasks)
- **SDD tasks:** Update specs that the implementation changes (blocked_by: impl tasks)
- **Docs tasks:** Generate living docs via `/brana:docs` strategy (blocked_by: impl tasks).
  Use the `/brana:docs all` strategy table to determine which doc types apply:
  - `feature`/`greenfield`: tech doc + user guide + shared doc updates + overview (if system-level)
  - `migration`: tech doc + user guide + overview (if architecture changed)
  - `refactor`: tech doc only (if architecture changed)
  - `bug-fix`: skip docs entirely
  Each applicable doc type becomes a task (or one combined `/brana:docs all` task).
  Include spec-graph routing candidates as a checklist in the docs task context.
- **Dependency order:** ADR → tests → implementation → specs + docs → validation

These come from the "Engineering disciplines" section in the SHAPE summary. If that section
identified specific ADRs, test strategies, docs, or spec-graph routing targets, turn each
into a concrete task with proper `blocked_by` relationships enforcing the
DDD → TDD → impl → SDD + docs flow.

**If "Quick add (flat task only)"** (escape hatch for trivial ideas):
Create a single task via `backlog_add()` (MCP) or `brana backlog add` with:
- Subject from idea title
- Description from problem + solution
- Context linking to the idea doc
- Tags inferred from the brainstorm content
- Stream: roadmap (default) or research (if chosen)

**5c. Report**

```
Saved: docs/ideas/{slug}.md
Backlog: {phase ID + task count if planned, or t-NNN if quick-added, or "none"}
```

### Step 6 — EXTRACT

At skill end, identify what was learned during the brainstorm session:

1. Review the brainstorm output — what facts were learned, what decisions were made, what patterns observed
2. Classify each finding using ontology entity types as vocabulary:
   - **Pattern** — reusable solution or approach
   - **ADR** — architecture decision that was made or implied
   - **Dimension** — new topic area worth a knowledge doc
   - **FieldNote** — practical gotcha or surprise
3. Skip if brainstorm was purely exploratory with no concrete findings

### Step 7 — EVALUATE

Score each finding (0-10) on two axes:

| Axis | SMALL (0-1) | MEDIUM (2-4) | LARGE (5+) |
|------|------------|-------------|------------|
| **Scope** | This brainstorm only | This project | Multiple projects/clients |
| **Novelty** | Already known | New on existing topic | New topic or contradicts existing |

**Gate by size:**
- **SMALL:** Auto-persist (no prompt). Tags, URLs, task context.
- **MEDIUM:** Inline eval — check for duplicates via `mcp__ruflo__memory_search(query: "{finding summary}", namespace: "knowledge", limit: 2)` and `mcp__ruflo__memory_search(query: "{finding summary}", namespace: "pattern", limit: 2)`. If top result similarity > 0.9, skip or merge. Present remaining to user via AskUserQuestion.
- **LARGE:** Present to user with recommendation via AskUserQuestion. For ADRs or cross-client patterns, suggest `/brana:challenge` review.

### Step 8 — PERSIST

Route each accepted finding by type:

| Type | Destination | Auto/Prompted |
|------|------------|---------------|
| Pattern | `mcp__ruflo__memory_store(namespace: "pattern")` + memory file | SMALL: auto, MEDIUM+: prompted |
| ADR | Draft in `docs/architecture/decisions/` | Always prompted |
| Dimension | Note for `brana-knowledge/dimensions/` | Always prompted |
| FieldNote | Append to relevant dimension doc `## Field Notes` | MEDIUM: prompted |
| Tags/URLs/context | Task context field | Auto |

For ruflo stores, use:
```
mcp__ruflo__memory_store(
  key: "pattern:{PROJECT}:{slug}",
  value: '{"finding": "...", "source": "brainstorm", "confidence": 0.5}',
  namespace: "pattern",
  tags: ["client:{PROJECT}", "source:brainstorm"],
  upsert: true
)
```

If ruflo unavailable, write to `~/.claude/projects/{project}/memory/` as markdown file.

## Anti-patterns

- **Don't monologue.** If you've written more than 2 paragraphs without asking a question, stop and ask.
- **Don't over-research.** 1-2 web searches per concept, not 10. The goal is grounding, not exhaustive review.
- **Don't force convergence.** If the user wants to keep exploring, let them. The shape phase waits.
- **Don't skip the challenge.** Even if no obvious flaws exist, present at least 2 counterarguments (market risk, execution complexity, alternative approaches).
- **Don't create tasks without asking.** The idea doc is always written. The task is always offered, never auto-created.
- **Step registry.** Follow the [guided-execution protocol](../_shared/guided-execution.md). Register steps on entry, update as each completes.

---

## Resume After Compression

If context was compressed and you've lost track of progress:

1. Call `TaskList` — find CC Tasks matching `/brana:brainstorm — {STEP}`
2. The `in_progress` task is your current phase — resume from there
3. Check `docs/ideas/` for any idea doc already written (Phase 5)
