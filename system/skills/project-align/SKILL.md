---
name: project-align
description: "Actively align a project with brana development practices — assess gaps, plan fixes, implement structure, verify, and document. Use when setting up a new project or when an existing project needs structural alignment."
group: execution
allowed-tools:
  - Bash
  - Read
  - Write
  - Glob
  - Grep
  - Edit
  - AskUserQuestion
---

# Project Align

Active alignment pipeline: DISCOVER → ASSESS → PLAN → IMPLEMENT → VERIFY → DOCUMENT.

Unlike `/project-onboard` (diagnostic, read-only), this skill creates files, configures structure, and implements practices. See [27-project-alignment-methodology.md](~/enter_thebrana/brana-knowledge/dimensions/27-project-alignment-methodology.md) for the full methodology.

---

## Phase 0: DISCOVER

Before any assessment, gather context from the user. This shapes tier suggestion, CLAUDE.md content, rules selection, and domain modeling depth.

**Ask what can't be inferred. Skip what's obvious from the codebase.**

### Greenfield Questions (new project, minimal codebase)

1. **What is this project?** — one-sentence description. Goes into CLAUDE.md preamble.
2. **What's the tech stack?** — language, framework, database, deployment target. Informs rules, test framework, linter config.
3. **What's the scale and lifecycle?** — experiment / side project / production / long-lived system? Solo / small team / growing? Informs tier recommendation.
4. **What's the domain?** — the business problem, not the tech. Informs whether DDD tier is warranted, glossary seeding, bounded context hints.
5. **What are you building first?** — immediate goal. Informs first ADR suggestion, initial domain terms.

### Brownfield Questions (existing project)

1. **Any existing conventions you want to keep?** — commit style, branch naming, test location, folder structure. Preserve these.
2. **What's the domain?** (if not obvious from the codebase)
3. **What are you building next?** — immediate goal.

### Using the Answers

- Pre-populate `.claude/CLAUDE.md` with project description, stack, conventions
- Suggest the right tier (e.g., "Production app with payments? Full tier — DDD glossary for payment terms alone saves hours")
- Seed `docs/domain/glossary.md` with initial terms from the domain description
- Create a relevant first ADR (e.g., "ADR-001: tech-stack-and-architecture" pre-filled with stack choices)
- Set up appropriate rules based on stack

---

## Phase 1: ASSESS

Spawn the `project-scanner` agent for the diagnostic scan. Pass it the project path and any context from DISCOVER. Use its structured report (alignment scores, gaps, portfolio patterns) as the assessment input.

If the agent is unavailable, run the assessment manually:

### Step 1: Detect Tech Stack

Reuse the `/project-onboard` pattern — read manifest files:

```bash
# Check for common manifests
for f in package.json pyproject.toml Cargo.toml go.mod composer.json Gemfile build.gradle pom.xml; do
    [ -f "$f" ] && echo "Found: $f"
done
```

Cross-reference detected stack with DISCOVER answers.

### Step 2: Run Checklist

Check each of the 28 items. For each, classify as:
- **present** — fully satisfied
- **partial** — exists but incomplete (e.g., CLAUDE.md exists but has no project description)
- **missing** — not found

Group results by category:

```
Foundation:  ■■■□  3/4
SDD:         □□□□□  0/5
DDD:         □□□□  0/4
TDD:         ■□□□  1/4
Quality:     □□□□  0/4
PM & Memory: □□□□□ 0/5
Verification: □□□  0/3
```

### Step 3: Determine Current Tier

Based on what's present:
- All Foundation items → at least Minimal
- Foundation + SDD + TDD → at least Standard
- All groups → Full

### Step 4: Output Gap Report

List missing items grouped by priority (Foundation gaps first, then SDD, then TDD, etc.).

---

## Phase 2: PLAN

Generate an ordered implementation plan from the gaps.

### Dependency Order

Foundation must come before SDD (need CLAUDE.md before referencing it in ADRs). SDD must come before TDD (need `docs/decisions/` before enforcement activates). Follow this order:

1. Foundation items (F1-F4)
2. SDD items (S1-S5)
3. DDD items (D1-D4) — if Full tier selected
4. TDD items (T1-T4)
5. Quality items (Q1-Q4) — if Full tier selected
6. PM & Memory items (P1-P4) — if Full tier selected
7. Verification items (V1-V3)

### Brownfield Priority

For existing projects, prioritize items that unblock the most downstream items. Example: creating `docs/decisions/` (S1) unblocks S2-S5 and enables PreToolUse enforcement.

### Tier Selection

Present the user with tier options and your recommendation based on DISCOVER answers:

- **Minimal** — 4 items, quick setup, good for experiments
- **Standard** — 13 items, recommended for anything that ships
- **Full** — 28 items, for long-lived/complex projects

Ask the user which tier they want. Respect their choice.

### Output

Numbered action list with what will be created/modified for each item.

---

## Phase 3: IMPLEMENT

Execute the plan item by item.

### Foundation Items

**F1 — Git repo:** Skip if `.git/` exists. Otherwise `git init`.

**F2 — `.claude/CLAUDE.md`:**
```markdown
# {Project Name}

{One-sentence description from DISCOVER}

## Tech Stack

{Stack details from DISCOVER or detected manifests}

## Conventions

{Detected conventions + user-specified ones}

## Domain

{Domain description from DISCOVER, if applicable}
```

For brownfield: if `.claude/CLAUDE.md` exists, read it and merge new information. Never overwrite — ask the user if there's a conflict.

**F3 — `.claude/rules/`:** Copy relevant rules from `~/.claude/rules/`. For stack-specific rules, create path-scoped rules (e.g., `api-conventions.md` with `paths: "src/api/**"`).

**F4 — Conventional commits:** Document in CLAUDE.md. No external tooling needed — CLAUDE.md instructions achieve high compliance for commit format.

### SDD Items

**S1 — `docs/decisions/`:** `mkdir -p docs/decisions`

**S2 — First ADR:** Create `docs/decisions/ADR-001-{slug}.md` using the Nygard template. Pre-populate with relevant decisions from DISCOVER (tech stack choices, architecture approach). Use the same ADR creation logic as `/decide`.

**S3 — PreToolUse hook:** Verify `~/.claude/settings.json` has the PreToolUse entry and hook script exists. If not, report: "Run `deploy.sh` in the brana repo to install the hook."

**S4 — `/decide` skill:** Verify skill is available. If not, report same as S3.

**S5 — Spec-first convention:** Document in CLAUDE.md. Enforced by PreToolUse hook when S1 + S3 are present.

### DDD Items (Full tier only)

**D1 — Domain glossary:**
```markdown
# Domain Glossary

Terms and definitions for {project domain}.

| Term | Definition | NOT (common confusion) |
|------|-----------|----------------------|
| {term1} | {definition from DISCOVER} | |
| {term2} | {definition from DISCOVER} | |
```

Seed with terms extracted from the DISCOVER conversation about the domain.

**D2 — Bounded context docs:** Create `docs/domain/` directory. For each bounded context identified in DISCOVER, create a brief description. This is lightweight — not full Context Mapper CML, just markdown describing the contexts and their relationships.

**D3 — Ubiquitous language in CLAUDE.md:** Add a "Domain Language" section to the project's `.claude/CLAUDE.md` referencing the glossary: "See `docs/domain/glossary.md` for domain terminology. Use these terms consistently."

**D4 — Domain model:** Future enhancement. For now, report as "manual" and suggest creating domain model documents in `docs/domain/MODEL-NNN-context-name.md`.

### TDD Items

**T1 — Test framework:** Detect from stack, initialize if missing:
- JS/TS: `vitest` or `jest` (check package.json for existing preference)
- Python: `pytest` (check pyproject.toml)
- Rust: built-in (`cargo test`)
- Go: built-in (`go test`)

**T2 — Test runner works:** Run the test command and verify exit 0. If it fails, diagnose and fix configuration.

**T3 — TDD-Guard:** Check `command -v tdd-guard`. If missing, recommend: `npm install -g tdd-guard && tdd-guard on`.

**T4 — Coverage baseline:** Configure coverage reporting in the test runner config.

### Quality & CI Items (Full tier only)

**Q1-Q4:** Check for existence of each item. Create basic configs where straightforward (linter config). For CI pipeline and security scanning, recommend specific tools but don't create configs (too project-specific).

### PM & Memory Items (Full tier only)

**P1 — PM integration:** Check for GitHub Issues, suggest enabling if not present.

**P2 — ReasoningBank patterns:** Store initial alignment patterns using claude-flow binary:

```bash
source "$HOME/.claude/scripts/cf-env.sh"
```

Store: `cd $HOME && $CF memory store -k "alignment:{PROJECT}:{date}" -v '{...}' --namespace alignment --tags "project:{PROJECT},type:alignment"`

Fallback (claude-flow unavailable): append to `~/.claude/projects/{project-hash}/memory/MEMORY.md`.

**P3 — portfolio.md:** Add or update project entry in `~/.claude/memory/portfolio.md`.

**P4 — Pattern recall:** Verify patterns return. If P2 succeeded, P4 should pass.

**P5 — MEMORY.md hygiene:** Read `~/.claude/projects/*/memory/MEMORY.md` for this project:
   - If over 200 lines, move detailed content into topic files (only first 200 lines load at session start)
   - If it contains behavioral directives ("always do X", "never do Y", "must/should"), move them to `~/.claude/rules/` or the project's `.claude/CLAUDE.md`
   - The distinction: **MEMORY.md = facts Claude discovered** (descriptive). **CLAUDE.md / rules/ = instructions humans wrote** (prescriptive).

### Important Rules

- **Ask for confirmation before each major step** (creating directories, writing files)
- **Never overwrite existing files** — read first, merge, or ask the user
- **Brownfield: respect existing conventions** — adapt to what's there, don't impose

---

## Phase 4: VERIFY

Re-run the alignment checklist to confirm gaps are closed.

### Steps

1. Run the same 28-item checklist from Phase 1
2. Compare before/after scores per group
3. Run `./test.sh` or equivalent if it exists
4. Check that enforcement hooks fire correctly (verify PreToolUse blocks on `feat/*` without spec activity)
5. Output before/after comparison:

```
ALIGNMENT REPORT
================
Tier: Standard

                Before    After
Foundation:     ■■□□      ■■■■    2/4 → 4/4
SDD:            □□□□□     ■■■■□   0/5 → 4/5
TDD:            ■□□□      ■■■□    1/4 → 3/4
                ──────    ──────
Total:          3/13      11/13

Remaining gaps:
  S5 — Feature branches start with spec (convention, builds over time)
  T4 — Test coverage baseline (configure coverage reporter)
```

---

## Phase 5: DOCUMENT

Record the alignment for future reference and cross-project learning.

### Steps

1. **Store in ReasoningBank:** Using the binary discovery pattern above:
   ```
   Key: alignment:{PROJECT}:{date}
   Value: { tier, score_before, score_after, items_created, duration_minutes }
   Namespace: alignment
   Tags: project:{PROJECT}, type:alignment, tier:{TIER}
   ```

2. **Update portfolio.md:** Add or update the project entry in `~/.claude/memory/portfolio.md` with current alignment state.

3. **Generate alignment report:** Save to `.claude/alignment-report.md` in the project root. Include:
   - Date, tier selected, before/after scores
   - Items created with file paths
   - Remaining gaps and recommended next steps
   - Time taken

4. **Write `.claude/alignment.json`:** Machine-readable alignment state for statusline integration (future).

5. **Suggest next steps:**
   - "Run `/retrospective` after your first real work session to start building patterns"
   - "Use `/pattern-recall` before starting work on a topic to leverage past experience"
   - "Run `/debrief` at the end of sessions to capture learnings"

---

## Difference from `/project-onboard`

| Aspect | `/project-onboard` | `/project-align` |
|--------|-------------------|-----------------|
| **Purpose** | Diagnostic (read-only) | Active (creates files, configures) |
| **Speed** | Seconds | Guided session (minutes) |
| **Output** | Gap report | Implemented structure + report |
| **When** | Quick health check | Initial setup or major realignment |
| **Files modified** | None (or minimal CLAUDE.md) | Many: CLAUDE.md, rules, docs, tests |
| **User interaction** | Minimal | Discovery interview + confirmations |

Use `/project-onboard` for a quick look. Use `/project-align` when you want to fix what `/project-onboard` finds.

---

## Rules

- **Ask for clarification whenever you need it.** If the project structure is unusual, the domain is unclear, or you're unsure which tier to recommend — ask.
- **Never overwrite existing files.** Read first. Merge if possible. Ask if there's a conflict.
- **Respect the user's tier choice.** Recommend, but don't override. If they want Minimal for a production app, that's their call.
- **Brownfield: preserve existing conventions.** The project had a life before alignment. Respect what's already there.
- **Store results in ReasoningBank when available, fall back to auto memory when not.** Same graceful degradation pattern as all brana skills.
