<!-- close phase: Steps 4-5: errata entries + pattern storage (parallel block 1/3) — loaded per the PHASES registry in ../SKILL.md (t-1942) -->

<!-- ruflo preamble -->
ToolSearch("select:mcp__ruflo__memory_search,mcp__ruflo__memory_store")

### Steps 4-8: Run in parallel

**Skip entirely** if `$CLOSE_MODE == "NANO"` — jump directly to Step 9.

Steps 4 through 8 (ERRATA, PATTERNS, FIELD-NOTES, IDEATE, DRIFT) are independent — each reads from Step 3 output but none depends on another. Execute all five simultaneously using parallel tool calls. Do not wait for one to finish before starting the next.

### Step 4: Write errata entries (if any)

**Skip entirely** if `$CLOSE_MODE == "NANO"`.

For each **errata** finding:

1. Find the errata doc: `Glob("**/*correction*")` or `Glob("**/*errata*")`
2. If found, read it for format and current error count
3. If not found, use `~/enter_thebrana/thebrana/docs/24-roadmap-corrections.md`
4. **Pre-write dedup check** — before writing any entry, grep the *committed* errata file for
   its key finding. This catches resume-after-compression where a prior close already committed
   the same errata:
   ```bash
   TODAY=$(date +%Y-%m-%d)
   # IDs already committed today
   COMMITTED_TODAY=$(git show HEAD:docs/24-roadmap-corrections.md 2>/dev/null \
     | grep -oP "E${TODAY}-[0-9]+")
   # For each errata finding from Step 3, check if its core problem phrase already appears
   # in the committed file. If yes, skip it (already filed). If no, proceed to write.
   ALREADY_FILED=$(git show HEAD:docs/24-roadmap-corrections.md 2>/dev/null \
     | grep -F "{key phrase from finding}" | wc -l)
   # ALREADY_FILED > 0 → skip this finding; it was committed in a prior session or earlier close
   ```
   If the same session closed partially (context compression) and resumed, errata may already
   be committed. Skip those; only write findings not already in the committed file.
5. Append entries following the existing format:
   - Timestamp-based ID: `E{YYYY-MM-DD}-{N}` where N starts at 1 for the day
   - **Always auto-read the committed state to find the next N:**
     ```bash
     LAST_N=$(echo "$COMMITTED_TODAY" | grep -oP "[0-9]+$" | sort -n | tail -1)
     NEXT_N=$(( ${LAST_N:-0} + 1 ))
     # Use E${TODAY}-${NEXT_N} as the new errata ID
     ```
   - Read from committed state (`git show HEAD:...`), never working tree — prevents parallel-session collisions
   - Title, severity (High/Medium/Low), discovery, affected files, fix
6. Add to severity summary table

**Status rules — close only logs, never resolves:**

| Finding | Status | Who resolves |
|---------|--------|-------------|
| Spec mismatch (needs doc edits) | `pending` | `/brana:reconcile` |
| Code bug (fixed this session) | `code-fix` | Already done |
| Code bug (not fixed) | `pending` | Next session |

**After writing each errata entry that the user approves**, run a debrief-flag extraction pass.
Scan the approved errata text for memory filenames using this pattern:
`\b(feedback|project|user|field-note)_[\w-]+\.md\b`

For each match that exists under `~/.claude/projects/*/memory/`:

```bash
python3 - "$ERRATA_TEXT" << 'PYEOF'
import re, json, os, sys
from datetime import datetime, timezone

errata_text = sys.argv[1]
FLAGS = os.path.expanduser("~/.swarm/debrief-flags.jsonl")
MEMORY_ROOT = os.path.expanduser("~/.claude/projects")

pattern = re.compile(r'\b(feedback|project|user|field-note)_[\w-]+\.md\b')
matches = set(pattern.findall(errata_text) if False else pattern.findall(errata_text))
# Re-extract full filenames (findall returns groups with the alternation above)
matches = set(re.findall(r'\b(?:feedback|project|user|field-note)_[\w-]+\.md\b', errata_text))

now = datetime.now(timezone.utc).isoformat()
written = 0
for fname in sorted(matches):
    # Verify the file exists somewhere under MEMORY_ROOT
    found = False
    for root, dirs, files in os.walk(MEMORY_ROOT):
        if fname in files:
            found = True
            break
    if not found:
        continue
    flag = {
        "timestamp": now,
        "type": "contradiction",
        "file": fname,
        "action": "archive",
        "acted_on": False,
        "confidence": "high",
        "session": "main",
        "source": "debrief-analyst"
    }
    with open(FLAGS, "a") as f:
        f.write(json.dumps(flag) + "\n")
    written += 1

if written:
    print(f"debrief-flags: {written} flag(s) written to {FLAGS}")
PYEOF
```

Skip silently if no matches, if the file doesn't exist under MEMORY_ROOT, or if Python fails.
This extraction only runs on **approved** errata — errata the user accepts and that the
debrief-analyst names a specific memory file. General behavioral contradictions without a
filename produce no flag (v1 constraint).

**After writing any errata**, auto-insert a reconcile reminder into the Step 9 `next[]` payload — this ensures sitrep surfaces it even if the user skips the Step 12 task offer:
```json
{"text": "Run /brana:reconcile --scope propagation (errata {E-IDs} filed this session)", "task_id": null, "category": "maintenance"}
```
Collect all E-IDs written this step into `{E-IDs}` (comma-separated). If no errata was written, skip this insert.

### Step 5: Store learnings as patterns

For each learning from Step 3, store via ruflo MCP (preferred) or CLI (fallback):

**Via MCP (preferred — durable, HNSW-indexed):**

```
mcp__ruflo__memory_store(
  key: "pattern:{PROJECT}:{short-title}",
  value: '{"problem": "...", "solution": "...", "confidence": 0.5, "transferable": false, "correction_weight": 0}',
  namespace: "pattern",
  tags: ["client:{PROJECT}", "type:{CATEGORY}", "outcome:{OUTCOME}", "tier:episodic"],
  upsert: true
)
```

**Fallback (CLI):**

```bash
source "$HOME/.claude/scripts/cf-env.sh"

cd "$HOME" && $CF memory store \
  -k "pattern:{PROJECT}:{short-title}" \
  -v '{"problem": "...", "solution": "...", "confidence": 0.5, "transferable": false, "correction_weight": 0}' \
  --namespace pattern \
  --tags "client:{PROJECT},type:{CATEGORY},outcome:{OUTCOME}" \
  --upsert
```

If both MCP and CLI are unavailable, the git file (below) is the sole durable copy.

**Step 5b: Write per-pattern file (always — regardless of MCP/CLI success)**

This is the git-durable source of truth. Per-pattern files survive ruflo corruption and scale
without a cap. The pattern indexer (t-1497) rebuilds ruflo from these files on demand.

**Transferability check (if debrief-analyst Step 2.5 was not already applied):**
Before writing, verify the pattern passed the "different codebase?" filter. If the debrief
returned a finding marked as "field note" (client-specific), skip Step 5b for that finding
and route it to Step 6 (field notes) instead.

**Before writing**, activate both sentinels so `feedback-gate.sh` and `memory-write-gate.sh` pass through:
```bash
touch /tmp/brana-close-active
touch /tmp/brana-memory-write-active
```
**After all Step 5b writes are done**, clean up both:
```bash
rm -f /tmp/brana-close-active
rm -f /tmp/brana-memory-write-active
```

**Slug:** derive from `{short-title}` — lowercase, hyphens, no special chars, max 40 chars.

**Dedup check** before writing (ruflo similarity):
```
mcp__ruflo__memory_search(query: "{pattern problem + solution summary}", namespace: "pattern", limit: 1, threshold: 0.85)
```
If similarity ≥ 0.85: skip write (near-duplicate exists). Note `similar_to: {key}` in the existing pattern's file if accessible.
If no match or MCP unavailable: proceed to write.

> Threshold calibrated 2026-05-24 (t-1589): 10 real pattern pairs tested. Max distinct-pair similarity = 0.59 (memory-routing vs cli-mcp-gateway). Gap to 0.85 = 0.26. 0% false-positive rate in sample. Threshold confirmed.

**Write** to `~/.claude/projects/{project-hash}/memory/pattern_{slug}_{YYYY-MM-DD}.md`:
```markdown
---
name: {slug}
description: {one-line summary — used to decide relevance in future sessions}
metadata:
  type: pattern
  confidence: {0.5 for clear patterns | 0.4 for borderline}
  source_task: {task-id or "close-{date}"}
  created: {YYYY-MM-DD}
  transferable: true
---

**Problem:** {problem}
**Solution:** {solution}
**Why:** {why it matters}
```

**Do NOT append to MEMORY.md.** Auto-extracted patterns are findable via ruflo semantic search.
MEMORY.md entries are added only at explicit human promotion (when a pattern recurs 3+ sessions).

**Skip if:** session was read-only (no commits), debrief returned no learnings, or all findings
were rerouted to field notes by the transferability filter.

