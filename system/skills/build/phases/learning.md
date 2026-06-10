<!-- build phase: Auto-learning: EXTRACT → EVALUATE → PERSIST — loaded per the PHASES registry in ../SKILL.md (t-1942) -->

<!-- ruflo preamble -->
ToolSearch("select:mcp__ruflo__memory_search,mcp__ruflo__memory_store")

## Shared: Auto-Learning (EXTRACT → EVALUATE → PERSIST)

Runs after main build work, before CLOSE (or before REPORT/ANSWER for investigation/spike). All strategies execute these steps.

### EXTRACT

Identify what was learned during the build.

1. **Diff review** — run `git diff --stat` (or `git diff --stat main...HEAD` on a branch) to see what changed.
2. **Process review** — reflect on the build: what worked, what didn't, what was surprising, what took longer than expected.
3. **Classify findings** using ontology types:
   | Type | When to use |
   |------|-------------|
   | **Pattern** | Reusable solution, workaround, or approach |
   | **ADR** | Architectural decision made during implementation |
   | **FieldNote** | Practical discovery, gotcha, dependency behavior |
   | **Dimension** | New topic area or significant expansion of existing knowledge |
4. **Build-specific signals** — look for: architectural decisions made under pressure, dependency behaviors discovered empirically, error paths that weren't documented, performance characteristics observed.

> **☑ Checkpoint — EXTRACT** (M+ builds with task_id):
> ```bash
> printf '{"step":"EXTRACT","completed":"%s","task_id":"%s"}\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "{task_id}" >> ~/.claude/run-state/{task_id}.jsonl
> ```

### EVALUATE

Score each finding on a 0-10 scale across three dimensions:

| Size | Scope | Novelty | Gate |
|------|-------|---------|------|
| **SMALL** (0-1) | This task only | Already known | Auto-persist |
| **MEDIUM** (2-4) | This project | New twist on existing topic | Inline dedup check via ruflo |
| **LARGE** (5+) | Cross-project | New topic or contradicts existing knowledge | User review, suggest challenger |

**Dedup check** (MEDIUM and LARGE findings — run in parallel):
```
mcp__ruflo__memory_search(query: "{finding summary}", namespace: "knowledge", limit: 2)
mcp__ruflo__memory_search(query: "{finding summary}", namespace: "pattern",   limit: 2)
```
If top result similarity ≥ 0.85, skip persistence (already captured). Otherwise proceed to PERSIST.

> Threshold 0.85 calibrated 2026-05-24 (t-1589): max distinct-pair similarity = 0.59, gap = 0.26.

> **☑ Checkpoint — EVALUATE** (M+ builds with task_id):
> ```bash
> printf '{"step":"EVALUATE","completed":"%s","task_id":"%s"}\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "{task_id}" >> ~/.claude/run-state/{task_id}.jsonl
> ```

### PERSIST

Route each finding by type:

| Type | Destination | Auto/Prompted |
|------|------------|---------------|
| **Pattern** | `mcp__ruflo__memory_store(namespace: "pattern")` + append to relevant memory file | SMALL: auto, MEDIUM+: prompted |
| **ADR** | Draft in `docs/architecture/decisions/` | Always prompted |
| **FieldNote** | Append to relevant doc's Field Notes section | Prompted |
| **Tags/context** | Task context via `brana backlog set {id} context --append "{finding}"` | Auto |

**Pattern persistence format:**

Dedup gate (run before every pattern memory_store — including SMALL auto-persists):
```
mcp__ruflo__memory_search(query: "{finding summary}", namespace: "pattern", limit: 1, threshold: 0.85)
```
- **Hit (similarity ≥ 0.85):** reuse the existing key with `upsert: true` — update confidence, append source_task. Do NOT create a new entry.
- **Miss (< 0.85) or MCP unavailable:** write new entry with a fresh key.

```
mcp__ruflo__memory_store(
  key: "pattern:{project}:{finding-slug}",   # or existing key on hit
  value: "{\"problem\": \"...\", \"solution\": \"...\", \"confidence\": 0.5, \"source_task\": \"{task-id}\"}",
  namespace: "pattern",
  tags: ["client:{project}", "type:{ontology-type}", "strategy:{build-strategy}"],
  upsert: true
)
```

If ruflo unavailable, fall back to appending to project auto memory (`~/.claude/projects/*/memory/`).

**Frontmatter relationships:** If PERSIST created or updated a markdown file (ADR, FieldNote, or doc), add YAML frontmatter relationships to that file:
- `produced_by: [source-doc-path]` — the doc or task that triggered this finding
- `applies_to: [project-or-client]` — if the finding is cross-client transferable
- `depends_on: [related-doc-path]` — if the finding extends or refines an existing doc

If the file already has frontmatter (`---` block), merge into it. If not, prepend a new block. Only add relationships that actually apply — don't force all three on every file.

Post-commit hook will rebuild `spec-graph.json` — new edges appear automatically.

**Graceful degradation:** If no findings worth persisting (trivial build, nothing surprising), skip EVALUATE and PERSIST silently. Don't force learnings where none exist.

> **☑ Checkpoint — PERSIST** (M+ builds with task_id):
> ```bash
> printf '{"step":"PERSIST","completed":"%s","task_id":"%s"}\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "{task_id}" >> ~/.claude/run-state/{task_id}.jsonl
> ```

---

