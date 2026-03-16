# Philosophy

Brana is a system that makes AI development partners better over time. Not a framework to learn — an environment that learns with you.

## Core Principles

### Infrastructure over prompts

Prompts drift, get forgotten, lose context. Infrastructure persists: hooks enforce rules without asking, skills encode workflows without re-explaining, rules shape behavior without repeating. When something matters enough to say twice, it should be a hook or a rule — not a prompt you copy-paste.

### Composability over monoliths

Every capability is a building block. Skills invoke other skills. Commands pipe into commands. Agents delegate to agents. The CLI is a composable tool, not a monolithic app. If a new capability can't be used by other capabilities, it's not ready.

### Learn from everything

Every session produces learnings worth storing. A bug fix reveals a pattern. A research spike answers a question. A failed approach narrows the search space. The system captures these — not as logs to scroll past, but as indexed knowledge that informs future work.

### Cross-pollination

Solutions from one project inform others. A WhatsApp template formula discovered for one client becomes reusable knowledge. An infrastructure evaluation becomes a reference for future decisions. Knowledge flows across projects, weighted by confidence and relevance.

### Test-first, always

The test is the spec. Write it before the code. See it fail. Then implement. This isn't ceremony — it's the shortest path to knowing whether something works. When a test seems wrong, investigate the code before weakening the assertion.

## Design Decisions That Matter

### Two layers: plugin + identity

The plugin (`system/`) is the toolkit — skills, hooks, agents. The identity layer (`~/.claude/`) is who the AI is — rules, memory, scripts. They deploy separately. You can update the toolkit without changing identity, or tune identity without touching the toolkit.

### Spec-driven development

Design docs aren't documentation — they're executable specifications. Changes cascade: dimension docs feed reflections, reflections feed the roadmap, the roadmap feeds implementation. When specs drift from code, `/brana:reconcile` detects it. The spec graph (`docs/spec-graph.json`) maps every document to the code it governs.

### Confidence-weighted knowledge

Not all memories are equal. Fresh research gets low confidence (0.3) and a TTL. Patterns that survive multiple builds get promoted (0.6+). Battle-tested knowledge that's been verified across projects gets high confidence. The system prefers high-confidence, recent patterns over stale or unverified ones.

### Skills as the unit of capability

Every repeatable workflow is a skill. Skills have frontmatter (name, description, allowed tools), a SKILL.md that defines behavior, and a namespace (`/brana:*`). Skills compose — `/brana:build` invokes `/brana:docs`, which invokes templates. New capabilities embed as steps in existing skills, not standalone commands nobody remembers.

## How It All Connects

```
User request
  → Rules shape behavior (always active, no invocation needed)
  → Skills encode workflows (invoked explicitly or by other skills)
  → Agents handle specialized tasks (auto-delegated based on context)
  → Hooks enforce constraints (block bad actions before they happen)
  → Knowledge system provides context (patterns, research, field notes)
  → Task system tracks progress (backlog, build steps, dependencies)
```

The build loop is the heartbeat: CLASSIFY what you're doing, SPECIFY what it should look like, DECOMPOSE how to get there, BUILD it with tests, CLOSE by documenting and reflecting. Each step stores knowledge. Each future build benefits from past builds.

Documentation isn't a separate activity — it's a build artifact. Tech docs, user guides, and this philosophy document are generated and updated as part of the build loop, not as an afterthought.
