# Knowledge System

How brana manages what it knows -- and how you interact with it.

## What it does

Every time you work with brana, knowledge is created: a gotcha you hit, a decision you made, a workaround that saved time. The knowledge system captures these things, puts them where they belong, and surfaces them when they matter again.

You do not need to manage this manually. Most of it happens as a side effect of commands you already use (`/brana:build`, `/brana:close`, `/brana:research`). This guide explains what happens under the hood so you know what to expect and how to get the most out of it.

## The 5 layers

The system is organized in layers, each building on the one below:

```
Layer 5: Automated Cadence        scheduled checks that surface issues
Layer 4: Embedded Maintenance      every command maintains knowledge as a side effect
Layer 3: Knowledge Graph           typed connections between docs, assumptions, components
Layer 2: Reasoning Docs            docs with tracked assumptions, field notes, changelogs
Layer 1: Raw Materials             dimension docs, ADRs, rules, system files
```

**Layer 1** is your documentation -- research docs, architecture decisions, code, config. This is where knowledge lives as files.

**Layer 2** adds structure to those files. Docs carry metadata (when was this last verified? what does it assume?) and include field notes -- practical learnings appended during work sessions.

**Layer 3** connects everything. A typed relationship graph tracks which docs inform which decisions, which assumptions underpin which designs, and which code implements which specs.

**Layer 4** makes maintenance invisible. When you run `/brana:close`, it captures field notes. When you run `/brana:research`, it checks internal knowledge before searching the web. When you run `/brana:build`, it verifies assumptions during planning.

**Layer 5** runs on a schedule without you doing anything. Morning reports surface stale assumptions. Weekly reviews summarize knowledge health. Monthly checks watch for scale thresholds.

## Field notes

Field notes are practical learnings captured during work -- gotchas, workarounds, surprising behaviors, environment-specific quirks. They bridge the gap between "things you learn while coding" and "things documented in specs."

### How they get captured

When you run `/brana:close` at the end of a session, Step 6 reviews the session's learnings and proposes field notes. For each one, you choose:

| Option | What happens |
|--------|-------------|
| **Keep** | Appended to the relevant doc's `## Field Notes` section |
| **Archive** | Stored in ruflo memory only (searchable but not in the doc) |
| **Skip** | Discarded |

Example prompt you will see:

```
Capture as field note? 'gh CLI --jq piped output crashes in sandbox (exit 134)'
  -> dimension doc 09 (Claude Code Native Features)
Options: [Keep (append to doc)] [Archive (store in memory only)] [Skip]
```

### What a field note looks like in a doc

```markdown
## Field Notes

### 2026-03-10: gh CLI --jq piped output fails in sandbox
Piped `gh issue list --json number --jq '.[0].number'` crashes with exit 134.
Fix: redirect to temp file first, then jq from the file.
Source: t-428 session
```

### The 20-note cap

Each doc holds a maximum of 20 field notes. When a doc hits this limit, brana prompts you to archive the 5 oldest unactioned notes. Archived notes remain searchable in ruflo -- they just leave the doc to keep it manageable.

A doc consistently hitting 20 notes is a signal that the doc itself needs revision -- the field notes are filling gaps the doc should cover.

## What surfaces automatically

You do not need to remember to check anything. The system surfaces items through channels you already use.

### Daily (morning report)

When you start a session, the morning check shows:

```
Knowledge status:
 - 0 scale triggers crossed
 - 2 assumptions approaching staleness
 - 3 field notes pending review
```

### Weekly (review)

The weekly review includes a knowledge health section:

```
Knowledge health this week:
 - Assumptions: 23 tracked, 21 fresh, 2 approaching threshold
 - Field notes: +2 added (via /close), 1 promoted, 1 archived
 - Scale: 172/500 nodes, 650/10K entries -- nominal
```

### Monthly (knowledge audit)

Monthly checks run deeper: scale triggers evaluate whether the system needs heavier tooling (graph databases, advanced search). These fire only when thresholds cross -- no false alarms.

### Scale triggers

Some features are intentionally deferred until the system grows enough to need them. Thresholds are checked automatically:

| Feature | Activates when | What happens |
|---------|---------------|-------------|
| Graph database (Cypher) | > 500 graph nodes | Auto-creates a backlog task |
| GraphRAG | > 10 typed edges per node | Auto-creates a backlog task |
| Cross-client witness chains | > 50 cross-client field notes | Auto-creates a backlog task |
| Memory temperature tiering | > 10K ruflo entries | Auto-creates a backlog task |

When a threshold crosses, you see it in your morning report and it shows up when you run `/brana:backlog next`.

## How commands interact with knowledge

Every major command touches the knowledge system. Here is what each one does:

| Command | Knowledge actions |
|---------|------------------|
| `/brana:build` | Searches internal knowledge before starting (Phase 0). Checks assumptions during planning. Captures field notes and updates changelogs on close. |
| `/brana:close` | Extracts learnings from the session. Proposes field notes. Updates doc changelogs. Verifies assumptions. Reindexes modified docs. |
| `/brana:research` | Searches internal knowledge first (ruflo + spec-graph), then goes to the web. Findings become field notes. Contradictions flag assumptions. |
| `/brana:review` | Includes a knowledge health section automatically. Reports assumption staleness and field note counts. |
| `/brana:backlog` | Factors assumption staleness into task priority. Attaches field notes to task context. |
| `/brana:reconcile` | Traces typed dependencies between docs. Flags assumption-stale drift. |
| `/brana:onboard` | Surfaces cross-client field notes relevant to the new project. |

The pattern: **internal knowledge first, then external.** Every command that needs context checks what brana already knows before reaching out.

## Dimension doc types

Dimension docs (research documents in `brana-knowledge/dimensions/`) fall into two classes:

### Maintain docs

Actively evolving topics. Staleness enforcement applies -- if a "maintain" doc has not been verified within its confidence tier window, `validate.sh` flags it.

Examples: Claude Code capabilities, testing strategy, context engineering principles, knowledge architecture.

### Snapshot docs

Point-in-time research. Timestamped when created, no enforcement. These capture what was true at research time and do not need ongoing updates.

Examples: Anthropic blog findings, git branching strategies, design thinking literature reviews.

The classification lives in `brana-ontology.yaml` under `dimension_classes`. When you create a new dimension doc, classify it as `maintain` or `snapshot` so the system knows whether to enforce freshness.

## Typed relationships

Docs connect to each other through 5 relationship types. These replace bare `[doc NN](path.md)` links with typed links that the knowledge graph can traverse.

### The 5 types

| Type | From | To | Meaning |
|------|------|----|---------|
| **assumes** | Document | Assumption | This doc relies on this claim being true |
| **implements** | Component | Document | This code realizes this documented decision |
| **informs** | Document | Document | This research shaped this decision |
| **enriches** | FieldNote | Document | This practical learning adds depth to this doc |
| **supersedes** | Document | Document | This newer doc replaces this older one |

### How to write typed links

In any reasoning doc (ADR, reflection, architecture doc), use the relationship type in the link text:

```markdown
<!-- Instead of this -->
See [doc 14](../reflections/14-mastermind-architecture.md) for details.

<!-- Write this -->
This decision [informs](../reflections/14-mastermind-architecture.md) the architecture design.
```

More examples:

```markdown
This design [assumes](../assumptions.md#ruflo-optional) ruflo is an enhancement,
not a hard dependency.

The PreToolUse hook [implements](../decisions/ADR-015-spec-first.md) the spec-first gate.

ADR-021 [supersedes](../decisions/ADR-008-triage.md) the original triage decision.
```

`validate.sh` checks that reasoning docs use typed links. It warns (but does not block) when it finds untyped references.

## Assumptions tracking

An assumption is an explicit claim that a doc relies on -- something believed to be true that, if wrong, would require changes.

### Where assumptions live

In the doc's frontmatter:

```yaml
assumptions:
  - claim: "ruflo is enhancement, not hard dependency"
    if_wrong: "graceful degradation section needs rewrite"
    last_verified: 2026-03-14
  - claim: "160 graph nodes won't hit 500 in 6 months"
    if_wrong: "scale trigger fires too early"
    last_verified: 2026-03-14
```

And in ADR assumption tables:

```markdown
| # | Claim | If Wrong | Last Verified |
|---|-------|----------|---------------|
| 1 | Solo operator maintains 3 frontmatter fields | Fields go stale | 2026-03-14 |
```

### How freshness is checked

Each doc has a confidence tier that determines how long assumptions stay fresh:

| Tier | Window | Typical docs |
|------|--------|-------------|
| `tech` | 6 months | Tool-specific docs, API references |
| `architecture` | 18 months | System design docs, ADRs |
| `methodology` | 36 months | Process docs, principles |

`validate.sh` Check 15 compares each assumption's `last_verified` date against the tier window. When an assumption approaches staleness, it shows up in your morning report. When it crosses the threshold, it is flagged as stale.

### What happens when an assumption goes stale

1. Morning report flags it: "2 assumptions approaching staleness"
2. Weekly review lists the specific assumptions
3. Next time you work on the related doc or task, `/brana:build` surfaces the stale assumption during planning
4. You verify it (still true? update `last_verified`) or invalidate it (update the doc that depends on it)

### When assumptions get contradicted

If a field note or research finding contradicts an assumption, the system flags it immediately rather than waiting for staleness. The contradiction appears inline during the command that discovered it.

## Next steps

- [Getting Started](getting-started.md) -- install and first session
- [Concepts](concepts.md) -- glossary of all brana terms
- [Commands](commands/) -- full command reference
- [Configuration](configuration.md) -- display themes, task portfolio, scheduler setup
