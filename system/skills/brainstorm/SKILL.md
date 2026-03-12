---
name: brainstorm
description: "Interactive idea maturation — explore, research, shape raw ideas into actionable plans. Use when you have a rough idea and want to think it through."
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
  - mcp__context7__resolve-library-id
  - mcp__context7__query-docs
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

### Phase 3 — Challenge

Play devil's advocate. Present 2-3 risks or counterarguments:

```
AskUserQuestion:
  question: "Here are potential challenges. Which concern you most?"
  header: "Risks"
  multiSelect: true
  options:
    - "{risk 1 — derived from research + seed}"
    - "{risk 2 — derived from research + seed}"
    - "{risk 3 — derived from research + seed}"
    - "None of these worry me"
```

For each selected risk, briefly propose a mitigation. Keep it to 1-2 sentences each.

If the user mentions a new concept during any phase, **auto-research it** (WebSearch, 1 query)
and fold findings into the conversation.

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
