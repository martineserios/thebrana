# Commands Reference

Agent commands are markdown-defined procedures that Claude executes as multi-step workflows. They live in `system/commands/` and are loaded by the plugin.

## apply-errata

| Field | Value |
|-------|-------|
| **Purpose** | Apply pending errata from doc 24 through the layer hierarchy |
| **Usage** | `/brana:apply-errata` |
| **Reads** | `24-roadmap-corrections.md`, dimension docs (01-07, 09-13, 15-16, 20-23, 25), reflection docs (08, 14), roadmap docs (17, 18, 19) |
| **Writes** | Affected dimension, reflection, and roadmap docs; updates doc 24 status table |

### Process

1. **Classify** -- reads doc 24, buckets each error: `dimension-fix`, `reflection-fix`, `roadmap-fix`, `code-fix` (skip), `informational` (skip)
2. **Dimension fixes** -- applies corrections to dimension docs
3. **Gate check** -- spawns parallel Haiku agents to verify reflections still hold after dimension changes
4. **Reflection fixes** -- applies doc 24 fixes plus cascade findings from the gate check
5. **Gate check** -- spawns parallel Haiku agents to verify roadmaps still hold after reflection changes
6. **Roadmap fixes** -- applies doc 24 fixes plus cascade findings; deepens roadmap precision while editing
7. **Update doc 24** -- marks errors as applied, logs cascade findings as new entries

### Rules

- Only applies fixes explicitly described in doc 24 or surfaced by gate checks
- Preserves doc voice and structure; minimal edits
- Shows each fix before applying
- Gate checks are targeted (only sections touching corrected content), not exhaustive

---

## maintain-specs

| Field | Value |
|-------|-------|
| **Purpose** | Full spec repo correction cycle |
| **Usage** | `/brana:maintain-specs` |
| **Reads** | All docs read by apply-errata and re-evaluate-reflections, plus doc 25, doc 30 (backlog), MEMORY.md files, skills directory |
| **Writes** | All docs written by sub-commands, plus doc 25, MEMORY.md files, tasks.json |

### Steps

1. **Apply errata** -- runs `/brana:apply-errata`
2. **Re-evaluate reflections** -- runs `/brana:re-evaluate-reflections`
3. **Review significant findings** -- optionally spawns challenger agent for HIGH severity or multiple related findings
4. **Deepen reflections** -- improves synthesis quality: new cross-doc interactions, sharper abstractions, coverage gaps, cross-reflection coherence. Follows reflection DAG: R1 -> R2 -> R3/R4 -> R5
5. **Check doc 25** -- verifies self-documentation is current
6. **Memory hygiene** -- updates skill commands tables and removes stale facts from MEMORY.md
7. **Backlog review** -- shows pending items from doc 30, marks already-done items
8. **Surface findings** -- presents candidate learnings for `/brana:retrospective` storage (does not auto-store)

Each step exits early if nothing needs doing. After the report, suggests `/brana:reconcile` if changes touched implementation-relevant specs.

---

## re-evaluate-reflections

| Field | Value |
|-------|-------|
| **Purpose** | Cross-check reflection docs against dimension docs for gaps and contradictions |
| **Usage** | `/brana:re-evaluate-reflections` |
| **Reads** | All 5 reflection docs (08, 14, 29, 31, 32), all dimension docs they reference, doc 24 (to avoid re-discovering known errors) |
| **Writes** | New errata entries appended to doc 24 |

### Process

1. **Build dependency map** -- extracts which dimension docs each reflection references, key claims, and cited evidence
2. **Cross-check** -- spawns parallel Haiku agents (one per dimension-reflection pair) to find missed findings, contradictions, stale references, and implicit assumptions
3. **Check unreferenced docs** -- looks for dimension docs that should inform reflections but are not mentioned
4. **Compile findings** -- formats each gap as a doc 24 errata entry with severity, source, evidence, and suggested fix

### Rules

- Skips dimension docs 01-03 (internal systems, intentionally excluded from reflections)
- Focuses on material gaps that would cause wrong implementation decisions
- Reflections are opinionated synthesis, not summaries; deliberate exclusions are not gaps
- Reads doc 24 first to avoid duplicating known errors

---

## repo-cleanup

| Field | Value |
|-------|-------|
| **Purpose** | Commit accumulated spec doc changes across sessions |
| **Usage** | `/brana:repo-cleanup` |
| **Reads** | `git status`, `git diff` for all modified files |
| **Writes** | Git commits (branched, merged with `--no-ff`) |

### Process

1. **Survey** -- `git status` and `git diff --stat` to see scope; `git diff <file> | head -60` for each modified file
2. **Gitignore check** -- ensures `.swarm/`, `.claude/memory.db`, `.mcp.json`, `*.backup.*` are ignored
3. **Group by logical batch** -- infers cause from diff content (errata applications, new docs, frontmatter updates, knowledge refreshes). Asks user if grouping is unclear
4. **Branch, commit, merge** -- for each batch: `docs/<description>` branch, stage by filename (never `git add -A`), conventional commit, `--no-ff` merge, delete branch
5. **Report** -- lists commits, files committed, remaining uncommitted files

### Rules

- Never commits tooling artifacts
- Never uses `git add -A` or `git add .`
- One logical change per commit

---

## init-project

| Field | Value |
|-------|-------|
| **Purpose** | Scaffold a new project with CLAUDE.md and basic structure |
| **Usage** | `claude init-project <project-name> [project-type]` |
| **Reads** | `~/.claude/templates/CLAUDE.md` |
| **Writes** | New directory with CLAUDE.md, git repo, project structure |

This is a shell script (not a markdown command). Default project type is `python`.

### What it creates (Python type)

- `src/`, `tests/`, `docs/`, `data/`, `output/` directories
- `pyproject.toml` with pytest, ruff, mypy, coverage config
- `tests/test_example.py` starter test
- `.gitignore` for Python, IDE, and env files
- Initial git commit with all files

### Arguments

| Arg | Required | Default | Description |
|-----|----------|---------|-------------|
| `project-name` | Yes | -- | Directory name to create |
| `project-type` | No | `python` | Project template (currently only `python`) |
