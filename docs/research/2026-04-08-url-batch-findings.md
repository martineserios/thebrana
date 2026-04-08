# URL Batch Research — 2026-04-08

**Scope:** Analysis of 222 URLs accumulated in the event log (Apr 6–8 new batch + older entries). Filtered to 141 across 5 thematic clusters. Each cluster researched by a parallel agent with brana context.

**Companion doc:** [2026-04-08-claude-code-leak-analysis.md](./2026-04-08-claude-code-leak-analysis.md) — deep dive on the CC leaked-code URLs (separate, higher priority).

## Cluster Summaries

### Cluster A — Memory & Context Engineering (21 entries, 16 fetched)

**Cross-cutting themes:**
1. **Embedding/RAG backlash is converging.** Karpathy's wiki, claude-memory-compiler (coleam00), Sirchmunk, Graphify, three-pillar posts all argue: at personal/team scale, markdown + LLM reading beats vector DB + semantic search. Directly contradicts brana's ruflo investment.
2. **Forgetting as first-class engineering.** AnimaWorks (Mark/Merge/Archive), Letta ("what to forget is engineering too"), memory compiler — all treat decay as the key design problem, not retention. Brana has no decay mechanism.
3. **Separation of generator and evaluator.** Anthropic's harness article, Kitaru checkpoints, Codex Ralph Wiggum loops all insist agent cannot grade its own work.
4. **Feedback-to-constraint conversion.** Every session failure should become a persistent artifact (linter rule, hook, doc, test).
5. **Progressive disclosure as token budget.** Claude-mem's 50-100 token index returns, Graphify's 71.5x reduction — return pointers/indices, not content.

**Top 3 opportunities:**
1. **HIGH/LOW — Test markdown-index recall vs ruflo.** `brana knowledge recall --markdown` using index.md + ripgrep + small LLM rerank. Compare against memory_search on 20 real queries. If quality comparable, path off ruflo fragility.
2. **HIGH/MEDIUM — Nightly consolidation + decay job.** Adopt AnimaWorks Mark/Merge/Archive loop. Promotes episodes → memory_entries, decays unused patterns by confidence × age. (Now subsumed by Kairos alignment — see leak analysis doc §5 Opportunity 2.)
3. **MEDIUM/LOW — Feedback-to-constraint pass in /brana:close.** Detect recurring failures, propose rule/hook/test updates via AskUserQuestion.

**Reject:** MemPalace AAAK dialect (unverified benchmark claims), Letta-style memory-as-git-commits for self-edits (GDPR + history bloat), "40K stars" hype, spatial metaphors.

**Key URLs:**
- https://github.com/coleam00/claude-memory-compiler — 4-stage pipeline (Capture/Extract/Organize/Inject), rejects vectors at personal scale
- https://www.anthropic.com/engineering/harness-design-long-running-apps — "context resets > compaction," Planner/Generator/Evaluator split, "context anxiety"
- https://www.linkedin.com/posts/alindnbrg_autonomousagents-memorysystems-multiagent — AnimaWorks 3-stage consolidation (Mark → Merge → Archive)
- https://www.linkedin.com/posts/alindnbrg_sirchmunk-embeddingfree-rag — Ripgrep + on-demand LLM reasoning, no embeddings, DuckDB clusters, 2-5s FAST mode
- https://www.linkedin.com/posts/eric-vyacheslav-156273169_someone-built-andrej-karpathys-dream-tool — Graphify: folders → KG + Obsidian vault, 71.5x token reduction, edges tagged extracted/inferred/ambiguous

---

### Cluster B — Ontology, Knowledge Graphs, Metadata (16 entries, 15 fetched)

**Cross-cutting themes:**
1. **Ontology-first beats prompt-first.** Lindenberg, Jorgenson, Iusztin, Seale, Marques da Silva all converge: write the noun/verb/rule contract before generation. Brana's CLAUDE.md is ahead but treats it as prose, not formal contract.
2. **The "knowledge retrieval tax" frame is load-bearing.** Marques da Silva coined it, Lindenberg amplified. Tax = agents re-inferring domain constraints every session. This is *exactly* what brana solves for CC sessions — but brana has never named it this way. Cleanest positioning frame in cluster.
3. **Model vs delivery layer distinction is missing.** Kumar's semantic-model-vs-layer cut applies directly: spec-graph.json = model, MCP tools / brana graph = layer. Brana blurs these.

**RDF vs LPG verdict:** No clean answer from the cluster. Practitioner community has moved past the dichotomy. Pragmatic judgment: **LPG via GraphMind** — keep formal semantics out of scope unless a reasoner becomes necessary.

**Top 3 opportunities:**
1. **Write system/ontology.yaml and enforce it** — adopt Jorgenson's Design Ontology Spec (nouns, verbs, rules, compositional logic). Populate with brana's real types (dimension, reflection, adr, skill, hook, agent) and edges. Wire `brana graph validate`. ADR candidate.
2. **Reframe positioning around "knowledge retrieval tax"** — gift-wrapped angle truer to brana than "harness engineering" or "metadata is the new code" alone. Draft landing-page headline, LinkedIn post, tag Lindenberg + Marques da Silva.
3. **GraphMind spike with ontology-as-programmable-backend framing** — use {Language, Engine, Toolchain} × {Data, Logic, Action, Security} grid. Default schema = Iusztin Option 3 (edges as first-class docs) + append-only reflection log. ADR-035 candidate.

**Names to add to research-sources.yaml:**
- Paul Iusztin (`pauliusztin`) — GraphRAG + ontology modeling
- Francisco Marques da Silva (`franciscomarquessilva`) — knowledge retrieval tax
- Animesh Kumar (`anismiles`) — semantic model vs layer
- cognee.ai — open-source memory engine (tool, not creator)
- Grafeo (Vanderseypen) — GraphMind alternative
- Knwler — KG extraction tool

**Key URLs:**
- https://www.linkedin.com/posts/pauliusztin_langchain-gave-me-a-knowledge-graph-in-10 — 17 node types / 34 edges from 5 docs when unconstrained; fix is ontology-first
- https://www.linkedin.com/pulse/ontology-layer-design-jens-jorgenson-3o06c — Design Ontology Spec format
- https://www.linkedin.com/posts/alindnbrg_ontology-aiengineering-aip — ontology-as-product via {Language/Engine/Toolchain}
- https://www.linkedin.com/posts/tonyseale_ontology-is-in-danger-of-losing-its-meaning — "McOntology" warning

---

### Cluster C — Multi-agent & Orchestration (32 entries, 19 fetched)

**Cross-cutting patterns:**
1. **Isolation is the real primitive.** Scion, Agent Orchestrator, cmux, Deep Agents, Adam Berrio all converge on per-agent isolation via worktrees + containers + separate credentials + separate context. Brana is on the right side but container/credential dimensions not enforced.
2. **Durability is underbuilt everywhere.** Kitaru (@Checkpoint/@Flow) is the crispest answer. Brana has no resume story for long skill runs.
3. **Deterministic aggregation beats LLM aggregation.** LangGraph 5-node, cmux polling, agentic-scripts grep gate, Goose Recipes — all separate LLM reasoning from deterministic orchestration.
4. **Knowledge graphs are a data-modeling problem.**
5. **Hooks as enforcement beat prompts as instruction.**

**Which Google multi-agent framework?** TWO Google things:
- **Scion** — harness-agnostic hypervisor. Per-agent containers, credentials, worktrees, context windows. CLI manages a "Grove" of agents. tmux for HITL. OTEL telemetry normalized across harnesses. Kubernetes support.
- **Google ADK (Agent Development Kit)** — pattern library on Gemini 3.1 Pro. Provides Sequential / Coordinator / Parallel / Hierarchical / Generator-Critic / Iterative Refinement / HITL patterns.

**Top 3 orchestration primitives to adopt:**
1. **Checkpoint/Resume for skill procedures (from Kitaru).** Minimal JSONL step log with idempotent step IDs, written by procedures at phase boundaries, read by `brana session` on resume. Solves mid-build crashes.
2. **Generator-Critic loop with early-exit tool (from Google ADK).** Wrap challenger agent in LoopAgent with `critic_approved` tool. Natural fit for /brana:build and /brana:brainstorm.
3. **guard-explore hook + codebase compaction (from agentic-scripts).** PreToolUse hook denies raw Read calls until agent runs ≥2 distinct Grep patterns. Pair with `brana compact` CLI for skeletal index.

**Reject:** "Agents replace engineers" hype (Read:Edit regression proves otherwise), Stop-hook infinite loops without checkpointing (cost bomb), "framework for framework's sake" (Deep Agents, Goose, Kitaru, cmux, Scion all reinvent the same primitives — brana should stay "harness with opinions," not become another framework), generic "AI memory" promises (Cognee, AnimaWorks as reference only).

---

### Cluster D — Architecture, Skills, MCP, CLI (23 entries, 14 fetched)

**Cross-cutting themes:**
1. **The harness is the product.** Railly Hugo, Graphify, CLI-Anything, Skill Seekers, Google Workspace CLI all variations on: productivity gains come from scaffolding around the model, not from the model. Market converging on brana's answer.
2. **CLIs have won the skills-vs-MCPs debate for narrow tools.** Vasilev's 54K→562 token argument, Rauch's Google CLI, CLI-Anything's 26.9K stars, `skills.sh` distribution channel.
3. **Lifecycle interception > workflow orchestration.** Ralph Loop (Stop hook), Graphify parse-then-extract — autonomy from stateless hooks on filesystem state.
4. **Measurement precedes pruning.** Skill-kit, code-review-graph, Cowork weekly scan.

**Top 3 ADR-worthy architectural opportunities:**
- **ADR-035: Skill usage telemetry & evidence-based pruning.** Port skill-kit's JSONL scanner into `brana skills usage`. Decide pruning based on 30-day invocation data.
- **ADR-036: MCP-or-CLI decision rule.** Vasilev: if interaction is stateless help/command, CLI wins. If stateful session/connection/live index, MCP wins. Audit every current MCP. linkedin-mcp already proven brittle — prime migration candidate.
- **ADR-037: Stop-hook autonomy loop.** Sanctioned bounded-autonomy via Stop hook interception (Ralph Loop pattern). Fits "hooks = stateless invariants" philosophy.

**"I deleted everything" post steel-manned:** Vasilev's core argument — most MCPs are help-surface layers for tools that already have CLIs. Help-surface MCP consumes context budget agent needs for reasoning. CLIs (version-controlled, debuggable, `--help` self-documenting) don't have this tax.

**Applied to brana:** Mostly yes. brana-mcp itself is the counter-example (structured JSON saves 65%, battle-tested). Keep. But linkedin-mcp (brittle, CLI viable), context7 (help surface?), google-sheets (could be CLI + keyring) are prime candidates for migration.

**Key URLs:**
- https://github.com/crafter-station/skill-kit — local CLI reading CC JSONL logs for skill usage stats
- https://www.linkedin.com/posts/ownyourai_i-just-deleted-all-my-mcps-skills-cli — 54K→562 token argument
- https://www.linkedin.com/posts/rauchg_google-has-shipped-a-cli-for-google-workspace — Rust CLI, dual CLI+skill distribution
- https://www.linkedin.com/posts/alex-lieberman_stupid-simple-but-most-powerful-claude-skill — weekly skill-candidate scan

---

### Cluster E — Claude Code Patterns & Tooling (49 entries, 22 fetched)

**Cross-cutting patterns:**
1. **CLAUDE.md as OS, not config.** Serious practitioners have layered .claude/ with commands/skills/hooks/agents/rules. Brana already here.
2. **Multi-agent is the new prompting.** Distribution trivial, aggregation/synthesis is where everyone fails.
3. **Context discipline > token tricks.** Context resets between phases, fresh sessions, handoff artifacts, sprint contracts.
4. **Security posture is cargo-culted.** Zammit (.env loads before deny rules) + Rogov (deny rules degrade past 50 subcommands) = broken.

**Cost optimization concrete tips:**
- **Offload research to NotebookLM free tier** (notebooklm-mcp-cli, 16 tools in CC) — "0 token burn on context gathering"
- Route easy tasks to Haiku
- Fresh sessions > follow-ups (edit original, don't chain)
- `/compact` at phase boundaries
- **Rudel.ai analytics:** 26% of sessions abandoned in first 60s; initial skill activation rate 4% → 61% with config work
- Paul Duvall's 291 sessions: ~1 commit/session (leading indicator of session productivity)

**Top 3 CC workflow patterns to adopt:**
1. **Session analytics / /brana:insights** — friction classifier on brana session history (session_history MCP exists). Categorize every session: wrong-approach / misunderstood-scope / buggy-code / shipped-clean. Surface in /brana:review. **Highest-leverage addition.**
2. **Context reset contracts at phase boundaries** — Anthropic's own guide prefers resets over compaction, enforced by sprint contracts between planner/generator/evaluator. Enforce fresh-session handoff in /brana:build between spec → plan → implement phases. *(Now subsumed by leak analysis §5 Opportunity 3.)*
3. **Security posture assuming deny rules broken** — /brana:reconcile --scope security checks: .env without vault integration, recommend setfacl/dedicated user, track subcommand count in long sessions.

**Unverified but worth tracking:**
- **Kairos, Coordinator Mode, UltraPlan, Daemon Mode, Remote Bridge** → *NOW VERIFIED, see leak analysis doc*
- **Auto Dream** → *NOW VERIFIED as autoDream*
- **Deny-rules-degrade-at-50** → still unverified, reproducibility test needed

**Emerging memes vs real techniques:**
- REAL: multi-agent with explicit aggregation, session analytics, four-layer programmable surface, security as runtime isolation, sub-agent parallel via worktrees, brain-and-hands split
- NOISE: "you're using CC wrong," maturity taxonomies, generic cheat sheets, "I used CC for X months and learned" without numbers, "AI second brain" branding

---

## Consolidated Task List

See individual tasks t-1035..t-1080. The leak-analysis doc drives the P1 work (t-1074, t-1075). The broader URL findings are captured as lower-priority research tasks in the earlier batches.

**Highest-priority actions (from all clusters combined):**
1. **t-1074, t-1075** — CC memory alignment (Kairos/session_memory)
2. **ADR candidate** — ontology.yaml + "knowledge retrieval tax" positioning (Cluster B opportunities 1+2)
3. **ADR-035** — skill usage telemetry (Cluster D + E convergence)
4. **Test markdown-index recall vs ruflo** (Cluster A opportunity 1)
5. **Checkpoint/resume for skill procedures** (Cluster C opportunity 1)
