# Memory — enter_thebrana/enter

## Project structure

- **Spec docs**: `/home/martineserios/enter_thebrana/thebrana/docs/` — reflections in `docs/reflections/`, roadmaps in `docs/`, dimension docs in `brana-knowledge/dimensions/`
- **Source registry**: `research-sources.yaml` — sources, creators, trust tiers, cadence, version_observed tracking
- **Reflection DAG**: R1 (08 Triage) → R2 (14 Architecture) → R3 (31 Assurance) / R4 (32 Lifecycle) → R5 (29 Transfer)
- **Implementation**: `/home/martineserios/enter_thebrana/thebrana/` — `system/` deploys to `~/.claude/`
- **Knowledge base**: `/home/martineserios/enter_thebrana/brana-knowledge/` — dimension docs, research sources, backups. 27 docs indexed with semantic retrieval.
- **Errata**: `24-roadmap-corrections.md` — known errors, lessons learned
- **Self-docs**: `25-self-documentation.md` — maintenance commands, staleness detection

## Roadmap precision — proven by Phase 4 vs Phase 2

Phase 4 (v0.4.0) had the most detailed WIs — file paths, logic pseudocode, template content, exit criteria. Implementation was near-1:1 with zero rework. Phase 2 had rougher specs and required multiple correction rounds. Each `/maintain-specs` pass is an opportunity to add precision.

## Maintain-specs materiality filtering

Parallel Haiku agents cross-checking dimension→reflection pairs return many findings. Most are enhancement suggestions, not errors. Apply strict materiality test: "would this lead to a wrong implementation decision?" In Phase 4's cycle, only 2 of dozens survived filtering.

## claude-flow v3 (MCP + CLI)

- **In-session:** runs as MCP server (`.mcp.json`), use `mcp__claude-flow__memory_*` tools — <1ms latency
- **In hooks/scripts:** use CLI binary directly (not `npx` — too slow from `$HOME`)
- **Binary location:** `node $HOME/.nvm/versions/node/v20.19.0/lib/node_modules/claude-flow/bin/cli.js` (globally installed v3.1.0-alpha.44, latest npm: v3.1.0-alpha.50 as of 2026-02-25). No `claude-flow` symlink in bin/ — must use `node ...cli.js` directly.
- **DB location:** `.swarm/memory.db` relative to CWD
- CLI commands: `claude-flow memory search --query "query"`, `memory store -k key -v value --namespace ns --tags "tags"`, `memory init --force`
- **Updating entries:** use `memory store --upsert` to overwrite existing keys. Without `--upsert`, duplicate keys fail with UNIQUE constraint. `--force` does NOT work for this.

**Never use npx for MCP servers.** `.mcp.json` must point to the global binary directly (absolute path). npx creates a separate package cache — dependencies installed in one are missing from the other. `deploy.sh` auto-ensures sql.js on every deploy.

**Breaking change (alpha.34):** `-q` flag is shadowed by global `--quiet`. Always use `--query` for memory search.

## Embedding spike results (2026-02-25)

- **CLI works without MCP session:** `node .../cli.js embeddings generate --text "..."` — pure CLI, bash-hook compatible
- **Model:** all-MiniLM-L6-v2 via ONNX Runtime, 384 dimensions
- **Speed:** ~2.6s cold start (model load), ~300ms cached. NOT 3ms as claude-flow docs claim.
- **Requires:** `@claude-flow/embeddings` package (not installed by default). Upgraded to alpha.12 (from alpha.1).
- **Semantic accuracy confirmed:** cosine 0.65 for related text, 0.23 for unrelated. Real embeddings, not hash fallback.
- **Hash fallback:** if `@claude-flow/embeddings` missing, silently degrades to 128-dim hash (useless for semantic search). Model shows "hash-fallback" — check for this.
- **Provider flag:** `--provider transformers` forces real ONNX. Without it, may pick mock/hash if init was simulated.

## Agent-Skill Symbiosis (post-Phase 5)

- **10 agents** deployed: scout, memory-curator, project-scanner, venture-scanner, challenger, debrief-analyst, archiver, daily-ops, metrics-collector, pipeline-tracker. Model distribution: Haiku (8), Opus (2: challenger, debrief-analyst). All agents have "Not for..." boundaries.
- **Delegation routing** replaces skill-suggestions: agents auto-delegate, skills are user-invocable
- **4 integration patterns**: A (skill spawns agent), B (agent preloads skill), C (auto-delegation fills invocation gap), D (multi-agent via main context)
- **5 orchestrator skills** updated to spawn agents: build-phase, project-align, venture-align, venture-phase, maintain-specs
- **35 skills** deployed in thebrana/system/skills/ (all with "Use when..." triggers). Pre-commit hook in thebrana.
- Hooks have steerable error guidance — CF failures surface via additionalContext with actionable messages.

## User preference: system file changes

Never reduce/trim system files (rules, CLAUDE.md, skills, agents) without asking the user first. Always present the proposed change and get approval.

## User preference: no signing on commit messages

Never add `Co-Authored-By`, `Signed-off-by`, or any attribution/signing lines to commit messages.

## Personal Life OS (v1, shipped 2026-02-20)

- **Location:** `~/enter_thebrana/personal/` — separate git repo, no remote
- **Files:** `tasks.md` (active/someday), `life.md` (8 areas, Wheel of Life), `journal/YYYY-WNN.md` (3Ls)
- **Skill:** `/personal-check` — read-only focus card (tasks, life areas, journal freshness)
- **Integrations:** `/morning` Step 3d (personal tasks), `/weekly-review` Step 1c (life area ratings)
- **All conditional** on `personal/` existing — no breakage if absent

## Context budget

Budget raised from 15,360 → 18,432 → 19,456 → 21,504 → 23,552 → 24,576 → 26,624 bytes (26KB). Still <1% of 200K context window. The real context pressure comes from MCP tool definitions (30-67K tokens), not rules files. Latest bump: +1KB for 5 workflow practices (work-preferences +3 sections, universal-quality +2 items).

## Context overflow prevention (thebrana #1, #2)

- **Research skill:** 3-phase metadata-first protocol — Phase 1 WebSearch-only scouts, Phase 2 incremental triage, Phase 3 targeted WebFetch. Scouts write to temp files, return 2-line summaries.
- **Global rule:** context-budget.md — thresholds at 70% (compact), 85% (delegate to subagent). Bulk edits → Python script. Sequential read→edit per file.
- **Status line:** already shows CTX % at 70/85/95 thresholds.

## Bulk triage pattern — metadata-first classification

When triaging large link/content collections with parallel agents:
- **Never have agents fetch URLs** for classification — LinkedIn/web pages bloat context (14/14 agents hit limits in previous attempt)
- **Classify from metadata only** (title/slug, author, tags) — sufficient signal for skip/noted/read decisions
- **Use Haiku model** for classification tasks — fast, cheap, stays under 50K tokens per agent
- **Batch size ~25-50 items** per agent, embed data in prompt (no file reads needed)
- **Principle:** metadata-first → fetch only what survives triage. Content fetching is a second pass for `read` items.
- Previous failure: 14 Opus agents × WebFetch = 14 context limit crashes, 0 results. Fix: 5 Haiku agents × title-only = 5 completions in 3-6s, 280 items classified.
- **Bulk file edits:** when applying 200+ status changes, write a Python script instead of 200 Edit calls. Match on unique row identifiers (e.g. `| 223 |`), track section context for non-unique IDs. Script ran once → 275 changes in <1s.

## Backlog extraction pattern — thematic clustering

When extracting actionable items from large sets of triaged links:
- **Cluster by theme first** — group noted/read links into 3-5 topic clusters (e.g. "Claude Code ecosystem", "agent architectures", "tools & workflows")
- **Parallel agents per cluster** — each gets cluster context + existing backlog items (to avoid duplicates)
- **Provide anti-duplication list** — paste existing items into each agent's prompt so they don't re-propose what exists
- **Materiality filter after merge** — agents propose 3-5 each (~13 total), then main context deduplicates and filters for actionability. This session: 13 candidates → 7 kept, 6 demoted as too speculative.
- **Source attribution** — each item links back to the link numbers that inspired it, creating traceability from raw link → triage → backlog item.

## Link distribution pattern — classify then script then fix

When moving links from a central backlog to multiple destination files:
- **Two-phase cleanup:** purge (remove skip rows) then distribute (move noted/read) — separate concerns, separate scripts
- **Haiku agents for routing:** embed link metadata (author, topic slug) in prompt, ask for `{link_number: "doc_number"}` dict. 3 parallel agents classified 229 links in <6s total.
- **Section-aware parsing:** non-LinkedIn sections restart numbering (GH-1, Art-1, Tool-1), so Python scripts must track current section to disambiguate rows
- **Two-script approach for complex mutations:** Script 1 does the bulk move (insert rows into destination docs, remove from source). Script 2 normalizes formatting (add missing table headers, merge old rows into new numbering, renumber sequentially). Keeping each script simple prevents compounding errors.
- **Research Resources normalization:** when merging new rows into existing sections with different numbering schemes (e.g., old `LI-xxx` vs new sequential `1, 2, 3`), always renumber everything sequentially in a cleanup pass. Use `^\| \d+ \|` regex carefully — non-numeric prefixes like `LI-140` won't match.
- This session: 251 skip purged, 198 links distributed to 11 dimension docs, 30 general retained. Two Python scripts, zero manual edits.

## Scheduler (shipped 2026-02-19)

- **brana-scheduler** deployed: systemd user timers, bash+jq CLI, flock concurrency, per-job allowedTools+model
- Config: `~/.claude/scheduler/scheduler.json`. CLI: `brana-scheduler deploy|status|logs|enable|disable|run|validate|teardown`
- **Skills work in headless mode**: `claude -p "Execute /skill-name"` successfully invokes skills via `-p` flag (validated manually)
- **jq `//` treats false as falsy**: `false // true` returns `true`. Use `if has("enabled") then .enabled else true end` for boolean fields.
- **bash `((errors++))` with `set -e`**: first increment from 0 returns exit 1. Use `errors=$((errors + 1))` instead.
- **Requires**: `sudo loginctl enable-linger $USER` for timers after logout
- **Community alternatives**: scheduler-mcp, claudecron, claude-tasks (MCP-based schedulers). Agent SDK for Phase 6+ scaling.
- Context budget: 23,549/23,552 after adding /scheduler skill. Skill descriptions must be minimal.

## Architecture Redesign (ADR-006, Phases 0-3 done)

Content redistributed by nature:
- **Dimension docs** (26 files) → `brana-knowledge/dimensions/` (knowledge/research)
- **Reflection docs** (5 files) → `thebrana/docs/reflections/` (cross-cutting synthesis)
- **Roadmap docs** (7 files + 00, 39) → `thebrana/docs/` (implementation plans)
- **Commands, ADRs, features** → merged into thebrana

**Status:** Phases 0 through 3 DONE. Phase 2 rewrote `/back-propagate`, `/reconcile`, `/build-phase` for same-repo operation. Phase 3 wired knowledge retrieval pipeline. Next: Phase 4 (evolve brana-knowledge).
**Backlog #84:** Review reflection placement after Phase 3 validates retrieval.

## Knowledge retrieval pipeline (Phase 3, shipped 2026-02-25)

- **Indexer:** `system/scripts/index-knowledge.sh` — parses dimension docs by `##` sections, stores in claude-flow memory (namespace `knowledge`) with 384-dim ONNX embeddings
- **Stats:** 26 docs → 317 sections → 315 indexed entries. ~300ms per section, full index ~4 min.
- **Retrieval:** `claude-flow memory search --query "topic"` returns knowledge base results mixed with patterns. Score >0.5 = strong match.
- **Triggers:** post-commit hook in brana-knowledge (incremental), weekly scheduler (full reindex), manual (`index-knowledge.sh`)
- **Memory-curator agent** updated to surface `knowledge` namespace results as "Knowledge base: [topic]"
- **Any session** can now query dimension doc content via `memory_search` MCP tool or CLI.

## CWD-as-role model (backlog #82)

Claude Code loads `~/.claude/` (global brain) everywhere + project CLAUDE.md based on CWD. Start sessions from the project dir being worked on. Enter vs thebrana = architect vs operator role. Multi-project workflow rule drafted but not yet written to disk.

**Related backlog items:** #22 (session routing), #39 (repo architecture), #58 (project differentiation), #60 (per-project scoping), #64 (knowledge system), #68 (cross-project learning).

## CLAUDE.md vs MEMORY.md framework

Framework rule now lives in `~/.claude/rules/memory-framework.md` (deployed from thebrana). Key fact: skills use 3-level progressive disclosure (metadata → full instructions → resources) to avoid context bloat.
