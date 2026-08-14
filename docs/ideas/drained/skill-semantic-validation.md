# Skill Semantic Validation Layer

> Brainstormed 2026-03-30. Status: idea.

## Problem

Brana's 31+ markdown skills have structural validation (frontmatter YAML, budget, secrets, dependencies) via validate.sh's 22 checks, but no semantic validation. Tool references inside skill bodies don't match `allowed-tools` frontmatter. File path links go unchecked. Frontmatter enum values aren't validated. Step registries in guided-execution skills drift from section headers. These issues surface only at runtime — and only for whoever runs the skill.

## Proposed solution

Add 4 semantic checks to validate.sh, integrated into the existing check pipeline. Pure bash + grep, no external dependencies. Available via `--semantic` flag (also included in the default full run).

### Check A — allowed-tools consistency (body vs frontmatter)

Scan each SKILL.md body for tool name patterns (Read, Write, Bash, Agent, AskUserQuestion, WebSearch, WebFetch, Glob, Grep, Edit, TaskCreate, TaskUpdate, Skill, etc.). Compare against `allowed-tools:` in frontmatter.

- Tool mentioned in body but missing from `allowed-tools` → **FAIL**
- Tool in `allowed-tools` but never referenced in body → **WARN** (dead permission)

Mitigation for false positives: word-boundary regex, scan code blocks and structured instruction sections only (skip prose paragraphs).

### Check B — file path references exist

Extract file path references from skill bodies:
- Markdown links: `[text](relative/path.md)`
- Include references: `@path/to/file`
- Explicit path patterns in code blocks

Resolve relative to the skill's directory. Flag:
- Referenced file doesn't exist → **FAIL**
- Broken markdown link → **FAIL**

### Check C — frontmatter schema completeness

Enforce required fields beyond existing check 1: `name`, `description`, `group`, `allowed-tools`, `status`.

Validate enum values:
- `status` ∈ {stable, experimental, seed, deprecated}
- `growth_stage` ∈ {evergreen, prototype, seed}
- `group` ∈ {execution, session, learning, business, integration, content, brana, utility, thinking, venture, core, domain}

Flag missing required fields or invalid enum values → **FAIL**.

### Check D — step registry consistency

For skills that reference `guided-execution.md` (guided-execution protocol):
- Extract step names from "Register these steps:" line
- Cross-check against `### Phase` / `### Step` section headers

Flag:
- Registered step with no corresponding section → **WARN**
- Section with no registered step → **WARN**

## Design decisions

- **Extend validate.sh, don't create a parallel system.** Same `fail()`/`warn()`/`pass()` functions, same output format.
- **`--semantic` flag** for focused iteration during development. Full run includes semantic checks by default.
- **Each check is a function** — future checks (golden path diff, cross-skill reference validation) slot in by adding a function + call.
- **Hard boundary: parse markdown, never invoke Claude.** Behavioral testing is a future layer, not this layer.

## Risks

| Risk | Mitigation |
|------|------------|
| False positives from tool name detection (e.g., "Read the docs") | Word-boundary regex + scan only code blocks and structured sections |
| Path extraction fragility in markdown | Start with explicit patterns only: `](path)` and `@path` |
| Maintenance of enum lists | Extract valid values from existing skills (self-documenting) |
| Scope creep into behavioral testing | Checks parse markdown only — no Claude invocation, ever |

## Future layers (not now)

These become relevant at specific inflection points:

- **Golden path snapshots** (inflection: contributor growth) — Record tool sequences from successful runs of critical skills (build, close, backlog). Detect regression when skill changes break expected flow.
- **Cross-skill reference validation** (inflection: 50+ skills) — Verify `depends_on` skills' outputs match this skill's expected inputs.
- **Marketplace quality score** (inflection: plugin marketplace launch) — Aggregate check results into a badge/score for published skills.

## Next steps

1. Implement checks A-D as functions in validate.sh
2. Run against all 31 skills, fix any findings
3. Add to pre-deploy workflow (already runs validate.sh)
4. Document in docs/architecture/testing-validation.md
