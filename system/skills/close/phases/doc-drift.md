<!-- close phase: Step 8: doc drift detection (parallel block 3/3) — loaded per the PHASES registry in ../SKILL.md (t-1942) -->

### Step 8: Detect doc drift

> **Skip entirely** if `$CLOSE_MODE` is `NANO` or `LIGHT-INLINE` (`--patterns` runs Steps 4–5 only — ADR-053).

Check if system files were modified this session:

```bash
# Preferred: use brana CLI if available
uv run brana ops drift 2>/dev/null || \
git diff --name-only HEAD~10..HEAD 2>/dev/null | grep -E '(skills/|agents/|hooks/|rules/|commands/|CLAUDE\.md|settings\.json|deploy\.sh)'
```

**Graph-aware detection:** If `docs/spec-graph.json` exists and system files were changed, query the graph to find which specific docs are affected:

```bash
# For each changed system file, find docs that reference it
jq --arg f "system/skills/build/SKILL.md" '.nodes | to_entries[] | select(.value.impl_files | index($f)) | .key' docs/spec-graph.json
```

Include the affected doc list in the drift report instead of just "system files changed." If the graph doesn't exist, fall back to the generic message.

Collect drift results for the session state JSON (Step 9):
- **backprop.files**: system files that changed this session
- **doc_drift.stale_docs**: docs affected by those changes (from spec-graph)

**When `doc_drift.stale_docs` is non-empty**, also auto-insert into the Step 9 `next[]` payload so sitrep surfaces it regardless of whether the user creates a task at Step 12:
```json
{"text": "Update stale docs: {comma-separated stale_docs list}", "task_id": null, "category": "maintenance"}
```

**Validate stale_docs paths before writing:** Before adding any path to `stale_docs`, verify it exists on the filesystem:
```bash
test -f "<path>" && echo "exists" || echo "skip"
```
Discard paths that don't exist — they represent stale heuristic mappings (e.g., `docs/architecture/cli.md`) or outdated spec-graph entries. A non-existent path in `stale_docs` is noise; it will produce false drift signals in the next session.

**Do NOT write `.needs-backprop` flag file.** The `backprop` field in session-state.json replaces it.

#### Feature doc staleness check

After detecting system-level drift, also check if session changes affect existing feature docs:

1. **Get changed implementation files** from this session:
   ```bash
   git diff --name-only HEAD~10..HEAD 2>/dev/null | grep -E '\.(ts|js|py|sh|json)$'
   ```

2. **Scan feature docs** in `docs/architecture/features/` and `docs/guide/features/`:
   - For each feature doc, check the **Key Files** table (tech doc) or content references
   - If any changed implementation file appears in a feature doc's Key Files or is referenced by path, that doc is **potentially stale**

3. **Report stale docs:**
   - Add stale feature docs to the `doc_drift.stale_docs` list in the session JSON
   - Offer via AskUserQuestion: "Stale feature docs detected: {list}. Run /brana:reconcile now?"
     Options: ["Yes — run reconcile", "Skip — defer to next session"]
     If yes: invoke `Skill(skill="brana:reconcile")`. If no: include in session state only.

4. **Skip if:** no feature docs exist yet, or no implementation files changed

#### Auto-trigger /reconcile

If system files were changed this session AND the project is brana (git root basename is "thebrana"):

1. Check if behavioral files include any of: `system/skills/`, `system/hooks/`, `system/agents/`, `system/commands/`, `system/cli/`, `**/rules/`
2. If yes, auto-invoke reconcile:
   ```
   Skill(skill="brana:reconcile", args="--scope consistency,propagation")
   ```
3. Record in session state: `"auto_reconcile": {"triggered": true, "scope": "consistency,propagation", "reason": "system files changed"}`
4. If reconcile finds issues, include them in the session report (Step 12)

**Skip if:**
- No system files changed this session
- Not in thebrana project (other projects don't have /reconcile)
- User already ran /reconcile manually this session (check conversation context)

#### Knowledge reindex

After drift detection, batch-reindex any changed docs into ruflo so the knowledge base stays current. One reindex per session replaces per-commit hooks.

```bash
brana knowledge reindex --changed 2>/dev/null || true
```

**Skip if:** no docs changed this session (git diff shows no `docs/`, `brana-knowledge/`, or `system/procedures/` changes), or ruflo is unavailable.

