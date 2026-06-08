---
depends_on:
  - docs/architecture/decisions/ADR-006-merge-enter-into-thebrana.md
informs:
  - docs/architecture/features/build-close-auto-docs.md
---
# Feature: Build Loop Redesign

**Date:** 2026-03-07
**Status:** specifying
**Task:** t-214

## Problem

Brana has 42 skills with 7 touching the build lifecycle (`/build-feature`, `/back-propagate`, `/brana:reconcile`, `/decide`, `/brana:challenge`, `/debrief`, `/brana:maintain-specs` [retired Phase 12]). Users must know which to invoke and when. The 7-phase `/build-feature` is heavy for small changes. `/back-propagate` was designed for a two-repo world that no longer exists (ADR-006 merged enter into thebrana). No industry tool requires 7 phases — the effective pattern is 4 steps.

Beyond the build flow, the full 42-skill surface has redundancies: `/pickup` duplicates what `session-start.sh` could do, `/debrief` and `/brana:retrospective` and `/session-handoff` all store learnings, 12 venture skills serve a solo founder, and documentation exists only for developers — not for users.

## Decision Record (frozen 2026-03-07)

> Do not modify after acceptance.

**Context:** Research on efficient development workflows (Shape Up, SDD paper arXiv:2602.00180, Addy Osmani's LLM workflow, GitHub Spec Kit, Martin Fowler's SDD analysis, inner/outer loop patterns) shows that effective AI-assisted development follows a 4-step inner loop: specify → decompose → build → close. Brana's current build flow maps to this but with unnecessary fragmentation across 7 commands.

Challenger review (Opus adversarial) identified:
- C1: Retiring back-propagate ignores 6 proven count-drift incidents → resolved by eliminating hardcoded counts from docs (fix the root cause, not the symptom) and keeping validate.sh as a structural linter
- C2: Merging ADR + feature brief loses archival property → resolved by frozen "Decision Record" section within the feature spec
- W1: Adaptive sizing heuristics are vague → resolved by concrete rules (file count, scope clarity)
- W2: Auto-storing all research creates noise → resolved by two-tier storage (low-confidence with TTL for intermediate, promoted for findings that survive into spec)
- W3: Reconcile demoted to lint loses remediation → resolved by keeping reconcile as on-demand skill
- W4: Challenge absorbed into SPECIFY loses context isolation → resolved by still spawning separate challenger agent

**Decision:**
1. Replace 7 build commands with one `/brana:build` command using a 4-step loop
2. Simplify 42 skills to ~25 by merging redundancies and retiring unused commands
3. Add 7 work-type strategies that adapt the loop (feature, bug fix, greenfield, refactor, spike, migration, investigation)
4. Integrate `/brana:backlog start` as the entry point to `/brana:build` for code tasks
5. Create two documentation trees: user guides (`docs/guide/`) and contributor docs (`docs/architecture/`)
6. Retire `/back-propagate` and `verify-counts.sh` — fix root cause (no hardcoded counts in prose)
7. Embed documentation as a mandatory CLOSE step — shipped without both docs means not shipped

**Consequences:**
- Easier: one command (`/brana:build`) replaces 7, with automatic strategy detection
- Easier: users have a guide that explains workflows, not just skill implementations
- Easier: `/brana:backlog start` flows directly into building — no gap
- Harder: migration from 42 to 25 skills requires careful phasing
- Risk: auto-detection misclassifies work type — mitigated by mandatory confirmation step

## Constraints

- Must preserve TDD enforcement (PreToolUse hook on all branches; feat/fix filter removed per ADR-031 revision 2026-04-04)
- Must preserve git discipline (branching, worktrees, --no-ff)
- Must work without ruflo (graceful degradation to auto memory)
- Must not break existing projects that reference current skill names
- Documentation is a build deliverable, not optional

## Scope (v1)

### The Build Loop

One command: `/brana:build "description"`

**Step 0: CLASSIFY** (mandatory, one interaction)
- Auto-detect work type from description + task metadata (if started via `/brana:backlog start`)
- Present classification for user confirmation
- Mid-stream reclassification allowed at any point

**7 strategies:**

| Strategy | Steps | Trigger |
|----------|-------|---------|
| Feature | SPECIFY → DECOMPOSE → BUILD → CLOSE | Default, stream: roadmap |
| Bug fix | REPRODUCE → DIAGNOSE → FIX → CLOSE | "fix/broken/crash/bug", stream: bugs |
| Greenfield | ONBOARD → SPECIFY → DECOMPOSE → BUILD → CLOSE | "start/new/create project" |
| Refactor | SPECIFY (light) → VERIFY COVERAGE → BUILD → CLOSE | "refactor/clean/restructure", stream: tech-debt |
| Spike | QUESTION → EXPERIMENT → ANSWER | "can we/test if/try/spike", stream: experiments |
| Migration | SPECIFY → DECOMPOSE → BUILD (parallel) → CLOSE | "migrate/switch/move/upgrade" |
| Investigation | SYMPTOMS → INVESTIGATE → REPORT | "why/investigate/understand", stream: research |

**SPECIFY** (interactive, open-ended — feature, greenfield, migration, refactor):
- Research loop: knowledge base → project docs → cross-client patterns → web
- Present findings, discuss with user — user controls pace
- Scout agents run web research in parallel while discussing
- Auto-store findings in ruflo (confidence: 0.3, ttl: 30d — ages out if not promoted)
- User signal ("draft it", "ready", "let's spec this") moves to draft
- At draft: auto-suggest dimension doc updates, write feature spec (includes Documentation Plan section with user guide, tech doc, and existing-docs-to-update checkboxes)
- Challenger review: spawned as separate agent (context isolation preserved)
- Findings that survive into final spec promoted to confidence: 0.6 (permanent)

**DECOMPOSE** (feature, greenfield, migration):
- Break spec into ordered tasks with acceptance criteria
- **Include documentation tasks** — user guide, tech doc, and existing-doc updates are mandatory in the task breakdown (not deferred to CLOSE)
- GitHub Issues if available, otherwise tasks.json entries
- Identify dependencies

**BUILD** (all strategies except spike and investigation):
- Branch (from task convention: feat/, fix/, refactor/)
- For each task: write failing test → implement → verify → commit
- Doc updates in same commit as code changes
- Mini-debrief after each task (what surprised, what to remember)

**REPRODUCE** (bug fix only):
- User describes symptom
- Find the failing case
- Write a failing test that reproduces it (TDD: test IS the spec)
- Confirm: test fails as expected

**DIAGNOSE** (bug fix only):
- Read the code path
- Identify root cause
- Present diagnosis to user for confirmation

**FIX** (bug fix only):
- Implement the fix
- Run failing test → should pass
- Run full test suite → no regressions
- Commit: fix(scope): description

**VERIFY COVERAGE** (refactor only):
- Run existing tests — all must pass
- If coverage gaps: write tests first
- Establish baseline: "N tests pass before refactor"

**QUESTION** (spike only):
- What are we trying to learn?
- What would yes/no look like?
- Timebox

**EXPERIMENT** (spike only):
- Quick prototype in /tmp/ or scratch directory
- No tests, no spec, no branch discipline
- Focus on answering the question

**ANSWER** (spike only):
- Did it work? Store finding via /brana:retrospective
- If yes → leads to /brana:build (feature) with validated approach
- If no → documented dead end
- Delete throwaway code

**SYMPTOMS** (investigation only):
- Describe what's happening
- Gather evidence: logs, errors, reproduction steps
- Form hypotheses

**INVESTIGATE** (investigation only):
- Test hypotheses one by one
- Read code, run experiments, check data
- No code changes — read-only

**REPORT** (investigation only):
- Root cause or candidates
- Recommended action: fix, refactor, accept, defer
- Store findings via /brana:retrospective
- If fix needed → leads to /brana:build --fix

**CLOSE** (all strategies except spike and investigation):
- Validate acceptance criteria
- Retrospective: what errors/re-approaches happened? What to remember?
- Store learnings (ruflo, confidence: 0.5)
- Update feature spec status → shipped (contributor doc)
- Write/update user guide (user doc)
- Update task status → completed (if started via /brana:backlog start)
- Merge (present command, don't auto-execute)

### /brana:backlog start integration

When `/brana:backlog start <id>` is invoked on a task with `execution: code`:
1. Read task metadata (subject, stream, tags, description, context)
2. Auto-classify from stream + description
3. Confirm classification with user
4. Create branch from task convention
5. Enter `/brana:build` with task context pre-loaded
6. `/brana:build` CLOSE updates task status → completed

Tasks with `execution: manual` or `execution: external` just get status updated — no build loop.

### Feature spec format (merged ADR + brief)

Location: `docs/architecture/features/{slug}.md`

```markdown
# Feature: {title}

**Date:** YYYY-MM-DD
**Status:** specifying | planning | building | shipped
**Task:** t-NNN

## Problem
Why this needs to exist.

## Decision Record (frozen YYYY-MM-DD)
> Do not modify after acceptance.

**Context:** ...
**Decision:** ...
**Consequences:** ...

## Constraints
- ...

## Scope (v1)
- ...

## Research
Key findings. Auto-populated from SPECIFY research loop.

## Design
Technical approach. Components, files, patterns.

## Challenger findings
Risks and resolutions. Auto-populated from challenger review.
```

### Command inventory (25, down from 42)

**Kept:**
`/brana:build`, `/brana:close`, `/brana:backlog`, `/brana:log`, `/brana:research`, `/brana:retrospective`, `/brana:memory`, `/brana:challenge`, `/brana:reconcile`, `/brana:pipeline`, `/brana:review`, `/brana:venture-phase`, `/brana:financial-model`, `/brana:onboard`, `/brana:align`, `/brana:client-retire`, `/brana:proposal`, `/brana:export-pdf`, `/brana:gsheets`, `/brana:respondio-prompts`, `/brana:meta-template`, `/brana:scheduler`, `/brana:acquire-skills`
(Note: `/brana:maintain-specs` was in this list but was retired in Phase 12, 2026-05-17 — absorbed into `/brana:reconcile --scope propagation`)

**Retired (17):**

| Command | Replacement |
|---------|-------------|
| `/pickup` | session-start hook reads handoff |
| `/session-handoff` | Renamed to `/brana:close` |
| `/debrief` | Absorbed into `/brana:close` and build CLOSE |
| `/build-feature` | Replaced by `/brana:build` |
| `/build-phase` | Replaced by `/brana:build` |
| `/back-propagate` | Same-commit doc updates + no hardcoded counts |
| `/decide` | Absorbed into build SPECIFY |
| `/knowledge` | Direct file operations + scripts |
| `/refresh-knowledge` | `/brana:research --refresh` |
| `/venture-onboard` | Merged into `/brana:onboard` |
| `/venture-align` | Merged into `/brana:align` |
| `/project-onboard` | Merged into `/brana:onboard` |
| `/project-align` | Merged into `/brana:align` |
| `/morning` | session-start hook |
| `/growth-check` | Merged into `/brana:review` |
| `/weekly-review` | Merged into `/brana:review` |
| `/monthly-close` | Merged into `/brana:review --monthly` |
| `/monthly-plan` | Merged into `/brana:review --monthly` |
| `/experiment` | `/brana:backlog add` + build loop (spike strategy) |
| `/content-plan` | `/brana:backlog plan` |
| `/sop` | Write docs directly |
| `/usage-stats` | Rarely used |
| `/personal-check` | Non-brana scope |

### Documentation structure

```
docs/
├── guide/                        ← USER DOCS
│   ├── getting-started.md        ← install, first session, concepts
│   ├── concepts.md               ← glossary
│   ├── workflows/
│   │   ├── build.md              ← how to build (all 7 strategies)
│   │   ├── capture.md            ← how to capture events
│   │   ├── research.md           ← how to research
│   │   ├── session.md            ← how sessions work
│   │   ├── venture.md            ← how to manage business projects
│   │   └── learn.md              ← how brana learns
│   └── commands/
│       ├── index.md              ← all commands, one-line each
│       └── {one .md per command}
│
├── architecture/                 ← CONTRIBUTOR DOCS
│   ├── overview.md               ← system architecture
│   ├── decisions/                ← ADRs (existing + new)
│   ├── features/                 ← feature specs (this file format)
│   └── reflections/              ← cross-cutting synthesis
│
└── roadmap/                      ← PLANNING DOCS
```

### Hooks and rules

| Hook/Rule | Change |
|-----------|--------|
| `session-start.sh` | Absorbs pickup logic (read session-handoff.md) + venture detection (absorbs session-start-venture.sh) |
| `session-start-venture.sh` | Retired — merged into session-start.sh |
| `pre-tool-use.sh` | Unchanged — TDD gate preserved |
| `post-tool-use.sh` | Unchanged |
| `session-end.sh` | Unchanged |
| `rules/sdd-tdd.md` | Unchanged — TDD discipline preserved |
| `rules/delegation-routing.md` | Updated — new command names, simplified trigger table |
| `rules/task-convention.md` | Updated — /brana:backlog start → /brana:build integration |
| `validate.sh` | Keep. Trim instruction density heuristic. |
| `verify-counts.sh` | Delete. Remove hardcoded counts from docs. |

## Deferred

- `/brana:log review` — show last 7 days, promote entries to tasks (v1.1)
- `/brana:log search` — keyword search (grep works for v1)
- Auto-generated command index from SKILL.md frontmatter
- Multi-agent build (parallel task execution via agent teams)
- Domain-Driven Design enforcement (docs/domain/ opt-in, per doc 32)

## Research

Key findings from the SPECIFY research loop:

**SDD paper (arXiv 2602.00180, Jan 2026):** Three levels — spec-first, spec-anchored, spec-as-source. Brana targets spec-first for features, with the frozen Decision Record providing spec-anchored archival.

**Addy Osmani (LLM workflow, 2026):** Spec.md first, break into sequential prompt plans, execute one by one. "Treat AI as a pair programmer that needs clear direction." Validates the SPECIFY → DECOMPOSE → BUILD approach.

**Martin Fowler (SDD analysis, Aug 2025):** SDD works well for larger features and greenfield but is overhead for small fixes. AI still drifts from specs mid-stream. Validates adaptive sizing — bug fixes skip SPECIFY.

**GitHub Spec Kit:** `/specify → /plan → /brana:backlog → code`. Open source, MIT. Validates the 4-step loop. Their format influenced the feature spec format.

**Shape Up (Basecamp):** Fixed time, variable scope. No backlog. Cooldown periods. Relevant for rhythm but brana keeps its backlog (tasks.json) — the solo developer context is different from a team.

**Inner/outer loop pattern:** Inner = code/test/debug (fast). Outer = branch/PR/merge (slower). The build loop IS the inner loop. Session flow IS the outer loop.

**Challenger (Opus adversarial, 2026-03-07):** 2 critical findings (count-drift, ADR archival), 4 warnings (sizing, noise, reconcile, challenge isolation). All addressed — see Decision Record.

Sources:
- [SDD paper](https://arxiv.org/abs/2602.00180)
- [Addy Osmani workflow](https://addyosmani.com/blog/ai-coding-workflow/)
- [Martin Fowler SDD tools](https://martinfowler.com/articles/exploring-gen-ai/sdd-3-tools.html)
- [GitHub Spec Kit](https://github.blog/ai-and-ml/generative-ai/spec-driven-development-with-ai-get-started-with-a-new-open-source-toolkit/)
- [Shape Up](https://basecamp.com/shapeup/0.3-chapter-01)

## Design

### System architecture after redesign

```
session-start.sh (hook, automatic)
├── Recall patterns from ruflo
├── Read session-handoff.md (absorbs /pickup)
├── Detect venture project (absorbs session-start-venture.sh)
└── Present context

/brana:backlog start <id> (entry point for code tasks)
├── Read task metadata
├── Auto-classify work type
├── Confirm with user
├── Create branch
└── Enter /brana:build

/brana:build (the loop — 7 strategies)
├── CLASSIFY → strategy selection
├── Strategy-specific steps (SPECIFY/REPRODUCE/QUESTION/etc.)
├── BUILD (TDD: test first, implement, verify)
├── Challenger Gate (mandatory semantic eval before CLOSE — see ADR-049)
│   ├── M+ effort: runs automatically
│   ├── S + sensitive paths (system/, hooks/, decisions/): runs automatically
│   ├── S + regular paths: prompt, default = run
│   ├── Input: task spec + git diff + AC only (trusted content)
│   └── Blocks CLOSE on score ≥ 4 (RECONSIDER); repair loop max 2 iterations
└── CLOSE (retrospect, docs, merge)

/brana:close (session end)
├── Write handoff note
├── Extract learnings (absorbs /debrief)
├── Store patterns
├── Compute metrics (session-end.sh hook)
└── Suggest follow-ups
```

### Migration path

Phase 1: Build the new `/brana:build` skill (SKILL.md)
Phase 2: Merge session hooks (session-start absorbs pickup + venture detection)
Phase 3: Rename `/session-handoff` to `/brana:close`, absorb `/debrief`
Phase 4: Merge project/venture onboard and align
Phase 5: Merge venture review skills into `/brana:review`
Phase 6: Restructure docs/ (guide/ + architecture/ split)
Phase 7: Retire old skills, update delegation-routing
Phase 8: Remove hardcoded counts from all docs, delete verify-counts.sh

## Challenger findings

See Decision Record for the full list. Key resolutions:
- Count drift → eliminate hardcoded counts (root cause fix)
- ADR archival → frozen Decision Record section in feature spec
- Auto-detect misclassification → mandatory confirmation step
- Research noise → two-tier storage with TTL
- Challenge context isolation → still spawns separate agent

## Open questions

- Should `/brana:build` auto-commit tasks.json changes or require explicit `/brana:backlog done`?
- Should the feature spec format be enforced by validate.sh (check for required sections)?
- How to handle interrupted builds — `/brana:build` started but session ended before CLOSE? (answered by t-1108: checkpoint/resume)
- Should mid-stream reclassification reset to step 0 or continue from current position?

## Field Notes

### 2026-04-10: SDD spec applies to procedure/.md files too
The SPECIFY gate added in this feature (SPECIFY → DECOMPOSE) was violated on t-1108 (checkpoint/resume) because the change was "just markdown." Procedure files that change runtime behavior ARE features — file type doesn't determine whether a spec is needed; behavioral impact does.
Source: t-1108
