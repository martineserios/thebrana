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
  - mcp__context7__resolve-library-id
  - mcp__context7__query-docs
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

Register these steps: SEED, EXPAND, DISCUSS, SHAPE, OUTPUT.

## Procedure

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

**B) Widen the lens** — if the idea is solid, explore adjacent territory:
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
- **Celebrate good thinking.** When the user gives a strong defense, say so. "That's a solid answer — it holds up because..."
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

**5b. Offer backlog task**

```
AskUserQuestion:
  question: "Create a backlog task from this idea?"
  header: "Task"
  options:
    - "Yes — add to backlog"       → create task via /brana:backlog add flow
    - "Not yet — just save the doc"
    - "Yes, as a research task"    → create with stream: research
```

If yes: create the task with:
- Subject from idea title
- Description from problem + solution
- Context linking to the idea doc
- Tags inferred from the brainstorm content
- Stream: roadmap (default) or research (if chosen)

**5c. Report**

```
Saved: docs/ideas/{slug}.md
Task: {t-NNN if created, or "none"}
```

## Anti-patterns

- **Don't monologue.** If you've written more than 2 paragraphs without asking a question, stop and ask.
- **Don't over-research.** 1-2 web searches per concept, not 10. The goal is grounding, not exhaustive review.
- **Don't force convergence.** If the user wants to keep exploring, let them. The shape phase waits.
- **Don't skip the challenge.** Even if the idea seems solid, present at least 2 counterarguments.
- **Don't create tasks without asking.** The idea doc is always written. The task is always offered, never auto-created.
- **Step registry.** Follow the [guided-execution protocol](../_shared/guided-execution.md). Register steps on entry, update as each completes.

---

## Resume After Compression

If context was compressed and you've lost track of progress:

1. Call `TaskList` — find CC Tasks matching `/brana:brainstorm — {STEP}`
2. The `in_progress` task is your current phase — resume from there
3. Check `docs/ideas/` for any idea doc already written (Phase 5)
