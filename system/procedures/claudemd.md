# claudemd — Audit or Generate CLAUDE.md

Two modes:
- **audit** (default if CLAUDE.md exists): Read existing file, flag bloat and misplaced content, propose a leaner version.
- **generate** (default if no CLAUDE.md): Interview the user and produce a lean CLAUDE.md from scratch.

## When to use

- User wants to create a CLAUDE.md for a new project
- Existing CLAUDE.md has grown bloated or Claude is ignoring parts of it
- User wants to know what belongs in CLAUDE.md vs rules/, skills/, or hooks/
- After `/brana:onboard` surfaces that no CLAUDE.md exists

---

## Mode routing

Parse the first argument:
- `audit` or `audit <path>` → run **Audit** flow
- `generate` or `generate <path>` → run **Generate** flow
- No argument → check if `./CLAUDE.md` or `./.claude/CLAUDE.md` exists → if yes, **Audit**; if no, **Generate**

---

# Audit Flow

## Step 1: READ

Read the CLAUDE.md at the given path (default: `./CLAUDE.md`, then `./.claude/CLAUDE.md`).
Also read any files it imports (`@path` syntax).
Note total line count.

## Step 2: CLASSIFY

For each line/block, classify into one of:

| Category | Keep in CLAUDE.md? | Better home |
|----------|--------------------|-------------|
| Project identity (one-liner, stack) | ✅ Yes | — |
| Commands CC can't guess (non-standard build/test/lint) | ✅ Yes | — |
| Code style that differs from language defaults | ✅ Yes | — |
| Architectural decisions specific to this project | ✅ Yes | — |
| Env var requirements, non-obvious setup quirks | ✅ Yes | — |
| Branch naming, PR conventions (team-specific) | ✅ Yes | — |
| Known gotchas, non-obvious behaviors | ✅ Yes | — |
| Standard language conventions CC already knows | ❌ Delete | nowhere — it's noise |
| Detailed API docs or long tutorials | ❌ Delete | link to external docs |
| Task-specific workflows (only relevant sometimes) | ❌ Move | `system/skills/` |
| "Always X" behavioral rules | ❌ Move | `.claude/rules/` |
| Deterministic enforcement (must happen every time) | ❌ Move | hooks |
| File-by-file codebase descriptions | ❌ Delete | let CC read the code |
| Frequently-changing information | ❌ Delete | MEMORY.md or task context |
| Anything CC infers correctly without it | ❌ Delete | it's redundant |

## Step 3: SCORE

Report:
- Total lines
- Lines to keep as-is
- Lines to delete (redundant/noise)
- Blocks to move to rules/
- Blocks to move to skills/
- Blocks to move to hooks/
- Estimated lines after cleanup

Flag if over 300 lines (warn) or under 60 lines after cleanup (healthy target).

## Step 4: REPORT

Present findings as a concise audit report:

```
## CLAUDE.md Audit — <path>

Total lines: X
After cleanup: ~Y (target: <300, healthy: <100)

### Delete (redundant/noise)
- Lines N-M: "<excerpt>" — CC already knows this / standard convention

### Move → .claude/rules/
- Lines N-M: "<excerpt>" — behavioral directive, not project context

### Move → system/skills/
- Lines N-M: "<excerpt>" — task-specific, not needed every session

### Move → hooks/
- Lines N-M: "<excerpt>" — deterministic enforcement

### Keep
- Everything else
```

## Step 5: ACT (with approval)

Ask the user with AskUserQuestion:
- Option A: Apply all changes (delete redundant, leave moves as TODOs with comments)
- Option B: Show me a cleaned version to review first
- Option C: Just the report, I'll edit manually

If A or B: produce the cleaned CLAUDE.md. For each "move" item, replace with a comment:
`<!-- TODO: move to .claude/rules/rule-name.md → "<first line of content>" -->`

Do not create the rules/skills/hooks files automatically — surface them as TODOs. The user decides.

---

# Generate Flow

## Step 1: DETECT

Before interviewing, scan the project to inform defaults:
- `package.json`, `Cargo.toml`, `pyproject.toml`, `go.mod` → detect stack
- `Makefile`, `justfile`, `.github/workflows/` → detect build/test commands
- `README.md` → detect project description
- `.eslintrc`, `prettier.config`, `ruff.toml` → detect linting (note: if linter exists, code style rules belong there, not CLAUDE.md)
- `git remote -v` → detect repo URL

Report detected stack to user before interviewing.

## Step 2: INTERVIEW

Use AskUserQuestion. Batch into 2-3 calls max.

**Batch 1 — Project identity:**
- "One-line description of this project?" (pre-fill from README if found)
- "Tech stack?" (pre-fill from detected files)
- "Any non-standard commands CC wouldn't guess? (build, test, lint, deploy)" (pre-fill from detected)

**Batch 2 — Conventions:**
- "Code style rules that differ from language defaults? (or none)"
- "Branch naming / PR conventions? (or use defaults)"
- "Any architectural decisions or patterns Claude must know?"

**Batch 3 — Quirks (only ask if needed):**
- "Required env vars or setup steps that aren't obvious?"
- "Known gotchas or non-obvious behaviors?"
- "Anything Claude keeps getting wrong that you want to enforce?"

Skip batch 3 if the user says "none" or "no" to batch 2 items.

## Step 3: WRITE

Produce a CLAUDE.md using only the answers. Apply the include/exclude rules:

**Template structure:**
```markdown
# <Project name>

<One-line description.>

## Stack
<Only if non-obvious from file structure.>

## Commands
<Only non-standard commands CC can't guess.>

## Code Style
<Only rules that differ from language defaults. If linter enforces it, omit.>

## Conventions
<Branch naming, PR rules, commit format — only team-specific ones.>

## Architecture
<Decisions Claude must know to avoid making wrong choices.>

## Quirks
<Gotchas, env vars, non-obvious behaviors.>
```

Omit any section with no content. Do not add headers for empty sections.

**Hard constraints:**
- No standard language conventions
- No file-by-file descriptions
- No detailed explanations or tutorials
- No "write clean code" style platitudes
- No linting rules (linter enforces those)
- No information CC can infer from reading the code

## Step 4: REVIEW

Show the generated CLAUDE.md to the user before writing.
Ask: "Write to ./CLAUDE.md?" with options: yes / yes and add to git / edit first / cancel.

Write only on explicit approval.

---

## Reference: The Three-Layer Pattern

For anything too long for CLAUDE.md, recommend progressive disclosure:

```
CLAUDE.md              ← identity, commands, key conventions (< 100 lines)
  @agent_docs/         ← task-specific guides (linked, not inlined)
    building.md
    testing.md
    deploying.md
  .claude/rules/       ← behavioral directives ("always X", "never Y")
  system/skills/       ← domain workflows (loaded on demand)
  hooks/               ← deterministic enforcement
```

Surface this pattern when the user's CLAUDE.md has grown past 200 lines.
