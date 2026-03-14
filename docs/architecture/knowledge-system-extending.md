# Extending the Knowledge System

How to extend the brana knowledge architecture: ontology, fitness functions, knowledge side-effects in skills, field notes, ruflo namespaces, and typed links.

## 1. Extend the Ontology

The ontology lives at `docs/brana-ontology.yaml` (ADR-021). It defines 5 entity types and 5 relationship types.

### Add a new entity type

Append to `entity_types` in `brana-ontology.yaml`:

```yaml
  - name: Metric
    description: Quantitative measure tracked over time
    examples: ["context budget utilization", "assumption staleness rate"]
```

### Add a new relationship type

Append to `relationship_types`:

```yaml
  - name: measures
    from: [Metric]
    to: [Component]
    description: Quantitative signal about a system element
```

### Update spec_graph.py

The typed edge extractor in `system/scripts/spec_graph.py` uses a frozen set of relationship names. Add yours:

```python
# system/scripts/spec_graph.py, line ~58
_RELATIONSHIP_TYPES = frozenset({"assumes", "implements", "informs", "enriches", "supersedes", "measures"})
```

Update the regex on the next line to include the new type:

```python
_TYPED_LINK_RE = re.compile(
    r"\[([^\]]+)\s+(assumes|implements|informs|enriches|supersedes|measures)\]\(([^)]+)\)"
)
```

### Add test coverage

Create a test that parses a doc with your new typed link and verifies `extract_typed_edges()` returns the correct edge. The existing test at `tests/test_spec_graph.py` (if present) or inline:

```python
from system.scripts.spec_graph import extract_typed_edges
from pathlib import Path

content = '[CPU usage measures](system/hooks/pre-tool-use.sh)'
edges = extract_typed_edges(content, Path("docs/test.md"), Path("/repo"))
assert edges[0]["type"] == "measures"
```

### When to extend

Per the ontology header: "Extend when ambiguity causes misclassification (see t-433)." Don't add types speculatively. Wait until existing types force awkward fits.

## 2. Add Fitness Functions

Fitness functions live in `validate.sh`. They are organized in numbered groups:

| Range | Purpose | Conditional flag |
|-------|---------|-----------------|
| 1-14 | Core validation | runs unless `--assumptions-only` or `--scale-triggers` |
| 15-18 | Knowledge architecture | runs unless `--scale-triggers` |
| 19-22 | Scale triggers | runs unless `--assumptions-only` |

### Adding check 23+

Pick the next sequential number and place it in the right conditional block. Pattern:

```bash
# Check 23: Your check name
echo "Check 23: Your check name..."

# ... your logic ...

if [ "$ISSUE_COUNT" -gt "$THRESHOLD" ]; then
    warn "Check 23: WARN — description ($ISSUE_COUNT > $THRESHOLD)"
else
    pass "Check 23: PASS — description ($ISSUE_COUNT/$THRESHOLD)"
fi
echo ""
```

### Using pass/warn/fail helpers

Three helpers defined at the top of `validate.sh`:

```bash
fail() { echo "  FAIL: $1"; ((ERRORS++)); }   # increments ERRORS, causes exit 1
warn() { echo "  WARN: $1"; ((WARNINGS++)); }  # increments WARNINGS, exit 0
pass() { echo "  PASS: $1"; }                   # informational only
```

Use `fail` for hard errors (broken config, missing files). Use `warn` for drift/staleness (things that should be fixed but don't block). Use `pass` for everything that checks out.

### Adding a flag filter

Add to the flag parser at the top of the file:

```bash
RUN_MY_CHECK=false

# In the while loop:
--my-check-only) RUN_MY_CHECK=true; shift ;;
```

Then wrap your checks in a conditional:

```bash
if ! $RUN_ASSUMPTIONS_ONLY && ! $RUN_SCALE_TRIGGERS || $RUN_MY_CHECK; then
    # Check 23: ...
fi
```

### Grace periods

Several checks use `GRACE_DAYS` (default 7, overridden with `--grace-days N`). The pattern:

```bash
mod_epoch=$(git -C "$SCRIPT_DIR" log --format=%at -1 -- "$doc" 2>/dev/null || echo "0")
if [ "$mod_epoch" != "0" ]; then
    local age=$((NOW_EPOCH - mod_epoch))
    if [ "$age" -lt "$GRACE_EPOCH" ]; then
        return 0  # recently modified, skip check
    fi
fi
```

`GRACE_EPOCH` is `GRACE_DAYS * 86400` (seconds). This skips checks on recently-modified files so new work isn't immediately flagged as stale.

## 3. Wire Knowledge Side-Effects into Skills

Any `/brana:*` skill can trigger knowledge actions (field notes, assumption checks, reindex). Two patterns exist.

### Pattern A: Field notes at session close (`/brana:close` Step 6)

File: `system/skills/close/SKILL.md`, Step 6.

1. Review learnings from earlier steps for practical discoveries.
2. Ask the user per-note: Keep (append to doc) / Archive (ruflo only) / Skip.
3. For "Keep": append a `### YYYY-MM-DD: title` entry under `## Field Notes` in the target doc.
4. For "Archive": store in ruflo namespace `field-notes` with tag `status:archived`.
5. After all notes appended, reindex affected docs in ruflo namespace `knowledge`.

### Pattern B: Internal search before external (`/brana:research` Phase 0)

File: `system/skills/research/SKILL.md`, Phase 0.

1. Query ruflo namespaces (`knowledge`, `assumptions`, `decisions`) for existing internal context.
2. Grep local docs for the topic.
3. Only then proceed to web search, using internal context to tag findings as CONFIRMED / CONTRADICTS / EXTENDS.

### Adding knowledge side-effects to a new skill

In your SKILL.md, add a step that follows one of these patterns:

```markdown
### Step N: Knowledge capture

Review outputs from previous steps for reusable findings.

**For assumption-sensitive work** (decisions, architecture):
1. Query ruflo `assumptions` namespace for related claims.
2. If any assumption is contradicted by this session's work, flag it.

**For discovery work** (research, investigation):
1. Store significant findings in ruflo with appropriate namespace.
2. Trigger reindex if a doc was modified:
   ```bash
   source /home/martineserios/.claude/scripts/cf-env.sh
   cd "$HOME" && $CF memory store \
     -k "knowledge:{doc-path}" -v "$(cat {doc-path})" \
     --namespace knowledge --tags "type:dimension,reindexed:$(date +%Y-%m-%d)" --upsert
   ```
```

Always include a ruflo-unavailable fallback (append to MEMORY.md or skip silently).

## 4. Modify the Field Notes Lifecycle

### Current lifecycle

Field notes flow through three actions:

| Action | Where it goes | When |
|--------|--------------|------|
| **Keep** | Appended to `## Field Notes` in the target doc | Learning is tied to a specific doc |
| **Archive** | Stored in ruflo namespace `field-notes`, tagged `status:archived` | Learning is useful but doesn't belong in any doc |
| **Skip** | Discarded | Not worth persisting |

### The 20-note cap

Each doc can hold at most 20 field notes (count `###` entries under `## Field Notes`). When the cap is hit, the skill prompts to archive the oldest 5. Archived notes move to ruflo with key format:

```
field-note:{project}:{date}:{slug}
```

Namespace: `field-notes`. Tags: `source:{doc-slug},type:field-note,status:archived`.

### Adding a new action

To add a fourth action (e.g., "Promote" to create a backlog task):

1. Add the option to the AskUserQuestion call in `/close` Step 6:
   ```
   Options: ["Keep", "Archive", "Promote to task", "Skip"]
   ```

2. Add handling logic after the existing if/elif chain:
   ```markdown
   **For "Promote" responses** — create a task in `.claude/tasks.json`:
   - Type: `task`, stream: `tech-debt` or `docs`
   - Description: the field note content
   - Tag: `from:field-note`
   ```

3. Include the new action in the Step 10 session report.

### Modifying the cap

Change the threshold in Step 6 of `system/skills/close/SKILL.md`. Search for "20 field notes" and "20+" — two places reference the number.

## 5. Add Ruflo Namespaces

Ruflo namespaces partition memory entries by purpose. The indexer at `system/scripts/index-assumptions.sh` populates three namespaces.

### Existing namespaces

| Namespace | Indexed by | Key format | Content |
|-----------|-----------|------------|---------|
| `assumptions` | `index-assumptions.sh` | `assumption:{doc-slug}:{claim-slug}` | Tracked claims from docs |
| `field-notes` | `index-assumptions.sh` + `/close` | `field-note:{doc-slug}:{title-slug}` | Practical learnings |
| `decisions` | `index-assumptions.sh` | `decision:{adr-slug}` | ADR summaries |
| `knowledge` | `index-knowledge.sh` | `knowledge:{doc-path}` | Full dimension doc sections |
| `patterns` | `/close` Step 5 | `pattern:{project}:{title}` | Reusable session learnings |
| `specs` | manual | varies | Specification patterns |

### Key naming convention

Keys follow `{namespace-singular}:{scope}:{identifier}`:

- Scope is usually the doc slug (`ADR-021`) or project name.
- Identifier is a slugified title, truncated to 60 chars.
- Slugification: lowercase, replace non-alphanumeric with `-`, collapse consecutive dashes.

```bash
key="assumption:${doc_slug}:$(echo "$claim" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | head -c 60)"
```

### How index-assumptions.sh works

1. Determines which files to scan (all ADRs + reflections, or `--changed` for git-diff only, or explicit file paths).
2. For each file, parses three sections:
   - `## Assumptions` table rows -> namespace `assumptions`
   - `## Field Notes` subsections -> namespace `field-notes`
   - ADR decision sections (files matching `ADR-*.md`) -> namespace `decisions`
3. Each entry is upserted via `$CF memory store --upsert` with tags `source:{slug},type:{type}`.

### Creating a new namespace indexer

1. Create `system/scripts/index-{your-namespace}.sh`. Follow the same structure as `index-assumptions.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

DOCS_DIR="${BRANA_DOCS_DIR:-$(cd "$(dirname "$0")/../.." && pwd)/docs}"
source "$(dirname "$0")/cf-env.sh"

[ -z "${CF:-}" ] && { echo "ERROR: ruflo not found." >&2; exit 1; }

# Determine files to scan
FILES=()
# ... (same --changed / explicit / default pattern)

store_entry() {
    local key="$1" value="$2" namespace="$3" tags="$4"
    cd "$HOME" && $CF memory store \
        -k "$key" -v "${value:0:2000}" \
        --namespace "$namespace" --tags "$tags" --upsert 2>/dev/null
}

for filepath in "${FILES[@]}"; do
    # Parse and extract entries
    # Call store_entry with your namespace
done
```

2. Make it executable: `chmod +x system/scripts/index-{your-namespace}.sh`.
3. Add a call from the appropriate trigger (post-commit hook, `/close`, or scheduled job).
4. Add a validate.sh check if the namespace has freshness or count constraints.

## 6. Typed Links in Docs

Typed links are markdown links with a relationship type keyword before the closing bracket.

### Syntax

```markdown
[Label relationship-type](path/to/target.md)
```

Examples:

```markdown
[ADR-019 assumes](../architecture/decisions/ADR-019.md)
[/brana:build implements](../architecture/decisions/ADR-006.md)
[dim-35 informs](../../brana-knowledge/dimensions/35-context-engineering.md)
[This doc supersedes](../old-doc.md)
[Field note enriches](../reflections/14-mastermind-architecture.md)
```

The five relationship types from the ontology: `assumes`, `implements`, `informs`, `enriches`, `supersedes`.

### How spec_graph.py extracts them

`extract_typed_edges()` in `system/scripts/spec_graph.py` scans each line (skipping fenced code blocks and inline code spans) with:

```python
_TYPED_LINK_RE = re.compile(
    r"\[([^\]]+)\s+(assumes|implements|informs|enriches|supersedes)\]\(([^)]+)\)"
)
```

For each match, it resolves the target path relative to the source file and emits an edge:

```json
{"from": "docs/reflections/14-architecture.md", "to": "docs/architecture/decisions/ADR-019.md", "type": "assumes"}
```

Edges are collected into `spec-graph.json` under `typed_edges`, deduplicated by (from, to, type), and sorted by type.

### Adding a new relationship type

1. Add it to `brana-ontology.yaml` (see section 1 above).
2. Add the keyword to both `_RELATIONSHIP_TYPES` and `_TYPED_LINK_RE` in `spec_graph.py`.
3. If the new type has validation semantics (like `assumes` triggers freshness checks), add a corresponding fitness function in `validate.sh`.
4. Regenerate the spec graph: `uv run python system/scripts/spec_graph.py generate`.
5. Run validation: `./validate.sh` to verify graph integrity (Check 18) passes.

### Validation

Check 18 in `validate.sh` validates graph integrity for typed edges:
- Orphaned edge targets (pointing to non-existent nodes)
- Orphaned edge sources
- Assumption references in typed_edges that don't match any `## Assumptions` section in docs

Check 21 monitors typed edges per node as a scale trigger (threshold: 10 edges per node).
