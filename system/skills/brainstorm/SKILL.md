---
name: brainstorm
description: "Interactive idea maturation — explore, research, shape raw ideas into actionable plans. Use when you have a rough idea and want to think it through."
effort: high
keywords: [idea, explore, challenge, shape, opportunity, maturation]
task_strategies: [spike, feature]
stream_affinity: [roadmap, research, experiments]
argument-hint: "[idea or topic]"
group: thinking
allowed-tools:
  - Read
  - Glob
  - Grep
  - Bash
  - Write
  - Edit
  - Agent
  - WebSearch
  - WebFetch
  - AskUserQuestion
  - Task
  - TaskList
  - Skill
  - mcp__context7__resolve-library-id
  - mcp__context7__query-docs
  - mcp__ruflo__memory_search
  - mcp__ruflo__memory_store
status: stable
growth_stage: evergreen
---

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

## Procedure

### Step 0 — LOAD

Pull relevant knowledge into context before the brainstorm begins. Budget: 30K tokens max.

1. **Build query** from available context: `"{project} {task.subject} {task.tags joined} {user_input}"`
2. **Primary — ruflo MCP:**
   ```
   mcp__ruflo__memory_search(
     query: "{query}",
     namespace: "all",
     limit: 5,
     threshold: 0.4
   )
   ```
   Focus on: dimension docs, idea docs (`docs/ideas/`), and recent research findings.
3. **Fallback — tag-based grep** (if MCP unavailable):
   ```bash
   grep -rl "{keywords}" ~/enter_thebrana/brana-knowledge/dimensions/ --include="*.md" | head -5
   grep -rl "{keywords}" docs/reflections/ docs/ideas/ --include="*.md" | head -5
   ```
   Read the top 3 matching files (first 80 lines each).
4. **Summarize loaded knowledge** as a brief context preamble (2-5 bullets). Do not show raw results — synthesize what's relevant to the seed idea.

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

### Phase 2 — Expand

Explore the idea space. Run these in parallel:

**2a. Context scan** — search the codebase and project docs for related work:
- Grep for keywords from the seed across docs/, system/, and tasks.json
- Check if related tasks already exist in the backlog
- Report: "Found N related items" (list briefly)

**2b. Auto-research** — if the seed mentions any tool, platform, framework, or technical concept:
- Spawn a scout agent (subagent_type: Explore, model: haiku) to search codebase
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

**5a. Write idea doc**

Save to `docs/ideas/{slug}.md` (create `docs/ideas/` if it doesn't exist):

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

```
AskUserQuestion:
  question: "Plan this idea into the backlog?"
  header: "Backlog"
  options:
    - "Yes — plan phases & tasks"  → invoke /brana:backlog plan with the idea as input
    - "Not yet — just save the doc"
    - "Quick add (flat task only)"  → fallback: single task via brana backlog add
```

**If "Yes — plan phases & tasks"** (default, recommended):
Invoke `/brana:backlog plan` via the Skill tool immediately:
```
Skill(skill="brana:backlog", args="plan \"{idea title}\"")
```
The plan skill will interactively create the full phase/milestone/task hierarchy
using the brainstorm's phased rollout as input. This is the **mandatory default** —
a brainstormed idea with phases and next steps deserves structured planning, not a flat task.

**If "Quick add (flat task only)"** (escape hatch for trivial ideas):
Create a single task via `brana backlog add` with:
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
- **MEDIUM:** Inline eval — check for duplicates via `mcp__ruflo__memory_search(query: "{finding summary}", namespace: "all", limit: 3)`. If similar exists, skip or merge. Present remaining to user via AskUserQuestion.
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
