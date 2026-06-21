<!-- build phase: Step 0: LOAD + CROSS-REFERENCE + STEP REGISTRY + RESUME CHECK + READINESS — loaded per the PHASES registry in ../SKILL.md (t-1942) -->

<!-- ruflo preamble -->
ToolSearch("select:mcp__ruflo__memory_search,mcp__ruflo__agent_spawn,mcp__ruflo__claims_claim,mcp__ruflo__claims_release,mcp__ruflo__memory_store,mcp__ruflo__autopilot_learn,mcp__brana__agy_delegate")

## Step 0: LOAD

Pull relevant architecture, decision knowledge, and skill matches into context before building. Budget: 30K tokens max.

0. **Goal injection** (task_id known only — skip for freeform builds):
   Collect acceptance criteria from two sources (merge, deduplicate):
   - **Source 1 — `acceptance_criteria` field** (preferred; available after t-1778 ships):
     ```bash
     brana backlog get {task_id} --field acceptance_criteria 2>/dev/null
     # Returns JSON array or null. Parse with: jq -r '.[]?' if array, skip if null.
     ```
   - **Source 2 — `AC:` lines in context** (fallback; always available):
     ```bash
     brana backlog get {task_id} | python3 -c "
     import json, sys
     t = json.load(sys.stdin)
     lines = [l[3:].strip() for l in (t.get('context') or '').splitlines() if l.startswith('AC:')]
     print('\n'.join(lines))
     "
     ```
   Merge both sources. If either yields criteria:
   - **Call** `/goal "{task.subject} — Done when: {criteria joined with ' AND '}"` to anchor the session.
   - **Write** `~/.claude/run-state/active-goal.json`:
     ```json
     {"task_id": "{task_id}", "cwd": "{git_root}", "session_id": "$BRANA_SESSION_ID", "criteria": ["{criterion1}", "{criterion2}"]}
     ```
     This state file is read by the Stop hook (`goal-completion.sh`) to auto-complete the task.
   - **If no criteria found in either source:** still anchor the session — call `/goal "{task.subject}"` (subject only, no `Done when:` clause). Do **not** write `active-goal.json`: the Stop hook (`goal-completion.sh:40`) exits at zero criteria, so a criteria-less state file does nothing. The session gets a focus anchor; auto-complete stays gated on `AC:` lines.
   - **Skip for:** freeform builds (no task_id), spike strategy, investigation strategy.

0.5. **Tech-stack pre-detection** (task_id present only — skip when no task_id):
   Run tech detection _before_ the ruflo search so the loaded skill's context is available to interpret results.
   <!-- SUNSET: Remove this step when Skill Registry (t-608) ships — same as Steps 4 and 4a. -->

   **Step A — Tech detection** (3-signal chain; first match wins — skip 0.5 entirely if no signal fires).
   Use the **domain-mapping table** in step 4a for canonical signal→tech→skill mappings.
   - **Signal 1** — task description + tags: match against "File signals" column of the domain-mapping table.
   - **Signal 2** — project manifest files: match manifest filenames against the table.
   - **Signal 3** — file path extensions in task description/context: match extensions against the table.

   **Step B — Skill match**: look up detected tech in the domain-mapping table. If no row matches or the mapped skill is not installed: skip 0.5 silently (no message).

   **Step C — Ask** (delegate to `skill-routing.md` gate, same as Step 4):
   ```
   question: "Detected {tech} context. Load {skill} before search?"
   header: "Skill Gap"
   options:
     - "Load {skill} now (Recommended)"
     - "Search marketplace for alternatives"
     - "Skip"
   ```
   On any terminal choice (Load / Skip / Search), write breadcrumb to prevent Step 4a re-firing:
   ```bash
   brana backlog set {task_id} context --append "skill_gap_checked: true (step 0.5, pre-detection, $(date +%Y-%m-%d))"
   ```

   **Guard rails:**
   - Skip when no `task_id` present (no task metadata to seed detection)
   - Skip if task context already contains `skill_gap_checked` (step 0.5 or backlog Step 5 already ran)
   - Only trigger for `code` execution tasks (skip external/manual)
   - If zero signals fire in Step A: skip 0.5 silently

1. **Build query** from available context: `"{project} {task.subject} {task.tags joined} {user_input}"`
2. **Primary — run all three in one message (two MCP calls + one Bash call, all parallel):**
   ```
   mcp__ruflo__memory_search(query: "{query}", namespace: "knowledge", limit: 5, threshold: 0.3)
   mcp__ruflo__memory_search(query: "{query}", namespace: "pattern",   limit: 3, threshold: 0.3)
   Bash("brana recall '{query}' --top 3 --json 2>/dev/null || true")
   ```
   Use `smart: false` (default). `smart: true` is **not recommended for precision recall** — t-1699 spike (2026-05-28): smart:false 56-95ms / top-sim 0.57-0.64 on-topic; smart:true 275-879ms / top-sim 0.47 off-topic (MMR over-diversifies; Feynman physics surfaced as #1 for "hook enforcement"). MMR runs before limit slice (`afterMmrCount` fixed), so `limit:1` mitigation also fails. MMR diversity param not exposed in ruflo schema (confirmed). ControllerRegistry ESM crash fixed in v3.10.36/Node 22 (2026-06-03) — smart:true is now operational but still degrades precision. Use it only when topic diversity is the explicit goal. Re-evaluate if ruflo exposes `mmr_lambda` or equivalent.
   Merge results, rank by similarity. Results span: knowledge (dimension docs, ADRs, feature briefs, reflections — all indexed here), pattern (past session learnings).

   **brana recall** (ADR-058): HybridProvider = FTS5 (`~/.claude/memory/*.md`) + ruflo `knowledge` namespace in parallel with RRF k=20 merge. Adds FTS5 hits (auto-memory not in ruflo) and knowledge results. **Does NOT cover the `pattern` namespace** — the pattern MCP call above remains essential for session learnings and cannot be dropped. Parse the JSON array: `.[] | .snippet` (truncate to 200 chars per entry to stay within token budget).
2b. **Graph edge traversal** (after ruflo search, if `docs/spec-graph.json` exists):
   Collect doc paths from knowledge results. Map ruflo key → file path:
   - `knowledge:dimension:{slug}:*` → `brana-knowledge/dimensions/{slug}.md`
   - `knowledge:decision:{slug}:*` → `docs/architecture/decisions/{slug}.md`
   - `knowledge:reflection:{slug}:*` → `docs/reflections/{slug}.md`
   - `knowledge:feature:{slug}:*` → `docs/architecture/features/{slug}.md`

   For each doc path, find 1-hop neighbors via inline graph query:
   ```bash
   uv run python3 -c "
   import json, sys
   with open('docs/spec-graph.json') as f:
       g = json.load(f)
   doc = sys.argv[1]
   seen = set(sys.argv[2:])  # already-loaded paths from ruflo results
   deps = [e for e in g['edges'] if (e['from']==doc or e['to']==doc) and e['type']=='depends_on']
   infs = [e for e in g['edges'] if (e['from']==doc or e['to']==doc) and e['type']=='informs']
   neighbors = []
   for e in deps + infs:
       n = e['to'] if e['from']==doc else e['from']
       if n not in seen:
           neighbors.append(n)
           seen.add(n)
       if len(neighbors) >= 3:
           break
   for n in neighbors:
       print(n)
   " "{doc_path}" "{already_loaded_1}" "{already_loaded_2}" ...
   ```
   For each returned neighbor:
   - Count lines: `wc -l < {neighbor_path}`
   - **If > 100 lines AND `mcp__brana__agy_delegate` is available:** call agy for targeted extraction:
     ```
     mcp__brana__agy_delegate(
       task: "Read this doc and extract the key architectural constraints, ADR decisions, and prior patterns relevant to: {task_subject}\n\n{full_doc_content}"
     )
     ```
     Use the agy response as context. Skip the `head -50` fallback.
   - **Else:** read first 50 lines via `head -50 {neighbor_path}`.
   - **Cap:** max 3 graph-derived docs total (across all ruflo results). `depends_on` edges checked before `informs`.
   - **Skip if:** spec-graph.json doesn't exist, no knowledge results from ruflo, or graph query returns no neighbors.
   - This is best-effort enrichment — never blocks LOAD.
3. **Fallback — brana recall then tag grep** (if MCP unavailable):
   Try `brana recall` first (FTS5 + knowledge ruflo; requires brana binary):
   ```bash
   brana recall '{query}' --top 3 --json 2>/dev/null || true
   ```
   If brana recall also unavailable, fall back to tag-based grep:
   ```bash
   grep -rl "{keywords}" ~/enter_thebrana/brana-knowledge/dimensions/ --include="*.md" | head -5
   grep -rl "{keywords}" docs/architecture/ docs/reflections/ --include="*.md" | head -5
   ```
   Read the top 3 matching files (first 80 lines each).
   For skills fallback: `brana skills suggest --query "{keywords}"`
4. **Skill match handling** — if any result has `namespace: "skills"` (or key starts with `skill:`):
   - Score >= 0.5: apply the **`skill-routing.md` gate** — use AskUserQuestion to confirm before loading the domain skill. LOAD is the information source (which skills matched); `skill-routing.md` owns the ask-before-loading gate. Never silently invoke a matched domain skill.
   - Score < 0.5: ignore (too weak to surface)
   - If entering via `/brana:backlog start`, skill suggestion already happened in step 5 — skip duplicate ask.

4a. **JIT skill acquisition** — deterministic tech detection + SKILL.md keywords gate. Triggers when a domain skill is installed but its knowledge was absent from LOAD results.
   <!-- SUNSET: Remove steps 4 and 4a entirely when Skill Registry (t-608) ships. Replace with skill_suggest(tech_context) calls. -->

   **Domain-mapping table** — canonical signal→tech→skill→match-keywords (t-1915):

   | File signals | Tech | Skill (if installed) | Match keywords for Step 3 |
   |---|---|---|---|
   | `.rs`, `Cargo.toml`, tag `rust` | Rust | `brana:rust-skills` | `rust`, `cargo`, `.rs` |
   | `.py`, `pyproject.toml`, `uv.lock`, tag `python` | Python | `brana:python-skills` | `python`, `pyproject`, `.py` |
   | `.ts`, `.tsx`, `tsconfig.json`, tag `typescript` | TypeScript | `brana:nextjs-patterns` | `typescript`, `nextjs`, `.ts`, `.tsx` |
   | `.sh`, `#!/usr/bin/env bash`, tag `shell` | Shell | `brana:shell-skills` | `shell`, `bash`, `.sh` |
   | `supabase/`, `supabase.ts`, tag `supabase` | Supabase | `supabase:supabase` | `supabase` |

   Use this table in Steps 1–3 below. Match keywords are domain-specific — a Rust task must match Rust keywords, not any keyword from the table.

   **Step 1 — Tech detection** (3-signal chain; first match wins — skip 4a entirely if no signal fires):
   - **Signal 1** — Task description + tags: scan for tech keywords using the "File signals" column above.
   - **Signal 2** — Project manifest files (filesystem-verifiable, most reliable): check presence of files in the "File signals" column (Cargo.toml, pyproject.toml/uv.lock, package.json+tsconfig.json).
   - **Signal 3** — File paths in task description/context: extract extensions from mentioned paths and match against the table.

   **Step 2 — Skill match**: look up the detected tech in the domain-mapping table. If no row matches or the mapped skill is not installed: skip 4a silently.

   **Step 3 — Domain-match LOAD check**: inspect LOAD result keys (from steps 2 and 2b above). A result satisfies the check ONLY if its key contains a keyword from the **"Match keywords"** column for the detected tech. Adjacent-domain keywords do NOT satisfy the check — a Python hit does not count as a Rust skill load.
   - Any key contains a match keyword for detected tech → skill knowledge already in context → **skip 4a**.
   - No key matches → skill knowledge absent → **proceed to Step 4**.

   **Step 4 — Ask**:
   ```
   question: "Detected {tech} context. {skill} knowledge not loaded. Load it now?"
   header: "Skill Gap"
   options:
     - "Load {skill} now (Recommended)"
     - "Search marketplace for alternatives"
     - "Skip"
   ```
   - **"Load now"**: invoke the skill via `Skill(skill="{matched-skill-name}")`.
     The Skill tool loads the full procedure and writes the session sentinel. No restart needed.
   - **"Search marketplace"**: invoke acquire-skills:
     ```
     Skill(skill="brana:acquire-skills", args="{tech keywords}")
     ```
     After completion: read the newly installed procedure file into context. Continue.
   - **"Skip"**: proceed without. LOAD never blocks. Append to task context:
     ```bash
     brana backlog set {task_id} context --append "skill-gap-warning: {skill} available but not loaded (skipped $(date +%Y-%m-%d))"
     ```
     Auditable via `brana backlog search "skill-gap-warning"`.

   **Guard rails:**
   - Only trigger for `code` execution tasks (skip external/manual)
   - If task context contains `skill_gap_checked`: skip 4a entirely (step 0.5 pre-detection or backlog Step 5 already ran)
   - If zero signals fire in Step 1: skip 4a entirely (no tech inferred)

5. **Summarize loaded knowledge** as a brief context preamble (2-5 bullets). Do not show raw results — synthesize what's relevant to the build task (prior decisions, related architecture, known constraints).

> **☑ Checkpoint — LOAD** (M+ builds with task_id):
> ```bash
> mkdir -p ~/.claude/run-state
> printf '{"step":"LOAD","completed":"%s","task_id":"%s"}\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "{task_id}" >> ~/.claude/run-state/{task_id}.jsonl
> ```

---

## Step 0a: CROSS-REFERENCE

Before anything else, check if this work already exists or relates to existing work.

1. **Search for related tasks** via CLI:
   ```bash
   brana backlog search "description keywords"
   brana backlog query --tag "relevant,tags"
   ```
2. **Analyze results** for:
   - Subject fuzzy match (significant words overlap)
   - Tag overlap (2+ shared tags)
   - File path overlap (if description mentions specific files)
   - URL match (if description contains URLs, check research stream)
3. **If matches found**, use AskUserQuestion:
   ```
   question: "Found related tasks. What to do?"
   options:
     - label: "This IS {id} — start it" (if exact match)
       description: "The existing task matches exactly — start it directly."
     - label: "Create new + link as related to {id}"
       description: "Add a new task and mark it related to the existing one."
     - label: "Merge into {id}"
       description: "Don't create a new task; add this scope to the existing task."
     - label: "No relation — create new"
       description: "Create a standalone task with no relation to the found task."
   ```
4. **If no matches**, proceed silently.
5. **If entering via `/brana:backlog start`**, skip cross-reference (task already identified).

---

## Step 0b: STEP REGISTRY

**Size gate:** Skip this for Trivial/Small sizes (see Sizing heuristics below). Only create the registry for Medium and Large builds.

Create a CC Task step registry. Follow the [guided-execution protocol](../../_shared/guided-execution.md).

Register these steps as CC Tasks (adapt based on detected strategy after CLASSIFY):

- **Feature/Greenfield/Migration:** LOAD, CLASSIFY, SPECIFY, DECOMPOSE, BUILD, EXTRACT, EVALUATE, PERSIST, CLOSE
- **Bug fix:** LOAD, CLASSIFY, REPRODUCE, DIAGNOSE, FIX, EXTRACT, EVALUATE, PERSIST, CLOSE
- **Refactor:** LOAD, CLASSIFY, SPECIFY, VERIFY-COVERAGE, BUILD, EXTRACT, EVALUATE, PERSIST, CLOSE
- **Investigation:** LOAD, CLASSIFY, SYMPTOMS, INVESTIGATE, EXTRACT, EVALUATE, PERSIST, REPORT
- **Spike:** LOAD, CLASSIFY, QUESTION, EXPERIMENT, EXTRACT, EVALUATE, PERSIST, ANSWER

Since strategy isn't known yet, create the CLASSIFY task first. After CLASSIFY confirms the strategy, create the remaining steps.

---

## Step 0c: RESUME CHECK

**Size gate:** Same as 0b — skip for Trivial/Small builds.
**Task gate:** Skip if no task ID is associated (freeform builds without a task).

1. **Check for a run-state file:**
   ```bash
   cat ~/.claude/run-state/{task_id}.jsonl 2>/dev/null
   ```
2. **If file exists and non-empty:**
   - Parse completed steps — each line is `{"step":"NAME","completed":"...","task_id":"..."}`
   - Display: "⏩ Resuming {task_id} from checkpoint. Completed: {step1}, {step2}, ..."
   - **Fast-forward:** skip all steps whose names appear in the completed list. Jump to the first step NOT in the file.
   - If CC Task registry from Step 0b exists, mark skipped steps as completed via `TaskUpdate`.
3. **If file is empty or missing:** proceed normally from Step 1.

---

## Step 0d: READINESS CHECK

**Task gate:** Skip if no task_id is present (freeform builds). Skip for spike and investigation strategies (strategy unknown at this point — re-run after CLASSIFY if needed; in practice, spikes and investigations rarely enter via `/brana:backlog start`).

Before CLASSIFY, verify the task is in a buildable state. Read the task via `backlog_get(task_id)` (or `brana backlog get {task_id}`) and check:

| Check | Severity | Signal | Remediation |
|-------|----------|--------|-------------|
| Description filled (>20 chars) | **Hard block** | `description` field empty or short | "Add a description to {task_id} before building: `brana backlog set {task_id} description '...'`" |
| All blocked_by resolved | **Hard block** | any `blocked_by` entry has status != completed | "Resolve blockers first: {list of open blocked_by IDs}" |
| Effort set | **Soft warn** | `effort` field null, AND task is M or L (infer from description length/scope) | "Consider setting effort: `brana backlog set {task_id} effort M`" |
| AC: lines in context (M/L) | **Soft warn** | no lines starting with `AC:` in `context` field, AND effort is M or L | "No AC: lines found — add acceptance criteria for /goal injection: `brana backlog set {task_id} context 'AC: ...'`" |

**Hard blocks** — collect all hard failures, then:
```
AskUserQuestion:
  question: "Readiness check failed for {task_id}: {list of failures}. Fix before building?"
  header: "Readiness"
  options:
    - label: "Fix now — I'll update the task"
      description: "Pause; update the task to match current state, then re-run checks."
    - label: "Skip — reason required"
      description: "Continue without fixing; provide a justification for the log."
```
If "Fix now": wait for user, then re-read the task and re-run checks.
If "Skip — reason required": require free text. Log to task notes and decision log:
   ```bash
   brana backlog set {task_id} notes --append "Readiness check skipped: {reason}"
   brana decisions log main concern "Readiness check skipped for {task_id}: {reason}" --severity LOW --refs "{task_id}" 2>/dev/null || true
   ```
   Proceed.

**Soft warns** — emit inline (no gate, no question):
```
⚠ {task_id}: effort not set. Consider: `brana backlog set {task_id} effort M`
⚠ {task_id}: no AC: lines in context. Session anchored with /goal "{subject}"; auto-complete disabled (add AC: lines to enable).
```

If all checks pass (or only soft warns remain), proceed silently.

---

