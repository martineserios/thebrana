# CC Alignment Findings — Decisions Needed

**Date:** 2026-04-08
**Status:** Findings only — no implementation. Shape work in progress.
**Reads with:** [`2026-04-08-claude-code-leak-analysis.md`](./2026-04-08-claude-code-leak-analysis.md) (full research), [`2026-04-08-url-batch-findings.md`](./2026-04-08-url-batch-findings.md) (URL cluster synthesis).
**Shape docs:** [`../ideas/session-memory-cc-alignment.md`](../ideas/session-memory-cc-alignment.md), [`../ideas/memory-consolidation-kairos.md`](../ideas/memory-consolidation-kairos.md).

---

## Purpose of this doc

The leak analysis is 30KB of primary-source research mixed with proposals. This doc distills it down to the **decisions the user needs to make before any code moves** — what's verified vs speculated, which opportunities matter, and where the real tradeoffs are.

Nothing here is a plan. Nothing has been implemented. Task t-1074 was marked `in_progress` prematurely and has been returned to `pending`. No procedures, CLI, or schemas have been edited.

---

## What we verified (from primary sources)

> Primary sources = Zain Hasan blog + Kolkov DEV.to analysis, both directly quote leaked code. See leak-analysis doc for citation tags.

### The non-negotiable facts

1. **Claude Code ships a session_memory file** at `~/.claude/projects/<path>/.claude/session_memory` with **8 fixed sections**: Current State / Files / Workflow / Errors / Codebase Documentation / Learnings / Results / Worklog. Each section ~2K tokens, total ~12K. Updated by a background extractor after model sampling. Init at 8K tokens into a session, refresh every 15K. **[VERIFIED]**

2. **Claude Code's context thresholds are hard numbers**, not vibes:
   - Effective window = `modelContextWindow − 20K` (reserve for compaction calls)
   - Autocompact trigger = `effectiveWindow − 13K`
   - Warning = `effectiveWindow − 20K`
   - Token counting: `anthropic.beta.messages.countTokens()` primary, ~1 token/4 chars fallback. **[VERIFIED]**

3. **Kairos and autoDream exist in the leaked source but are feature-flagged off.** Kairos = always-on background memory daemon. autoDream = consolidation logic *inside* Kairos (merges duplicates, resolves contradictions, prunes). Neither is user-visible yet. **[REPORTED]** — primary sources describe them but no one has quoted the actual storage format or trigger code.

4. **25+ lifecycle hook events exist**, including `PreQuery`/`PostQuery` which brana does not currently use. Plugin hooks are hot-reloadable via `setupPluginHookHotReload()`. Brana uses only ~5 of the 25+ events. **[VERIFIED]**

5. **Undercover mode is a real setting**: `settings.json.attribution.commit` / `.pr` strip "Claude Code" and "Co-Authored-By" from commits. **[VERIFIED]** — and it matches the user's standing preference in MEMORY.md.

6. **Silent model downgrade**: 3 consecutive 529 errors → Opus drops to Sonnet with no user notification. Relevant to brana's cost/repro claims. **[VERIFIED]**

7. **Code-quality reality check**: zero test coverage across 64K LOC of TS, 5.4% orphaned tool calls, memory leaks (13–15 GB extended runs), `src/cli/print.ts` has 486 cyclomatic branch points. This is important context — it means **brana is not chasing a disciplined codebase**, it's chasing a feature-rich one with real brittleness. **[VERIFIED — Kolkov]**

### What we did NOT verify (despite widespread repetition)

| Claim | Source | Status |
|---|---|---|
| "Deny rules silently degrade past 50 subcommands" | Alex Rogov LinkedIn | **Unverified** — not in any primary source. Reproducibility test needed. |
| "GitHub MCP costs 54,000 tokens vs `gh --help` 562" | Vasilev post | **Unverified** — plausible order of magnitude, no leaked-code confirmation. |
| "11 steps" agent loop (vs 10) | Eric Vyacheslav via ccunpacked | **Partial** — Zain's enumeration shows ~10 phases, 11th is inferred (post-turn hook). |
| Cathedral.ai Kairos 3-gate / 4-phase pattern | Mike W DEV.to | **Conceptual reimplementation** — explicitly not the leaked code. Useful as a design reference, not as a description of Anthropic's implementation. |
| Kairos storage backend | multiple | **Pure speculation** — SQLite / JSON / markdown all guessed. |

**Implication:** Anything we build that assumes these claims is building on sand. In particular, `memory-consolidation-kairos.md` treats the 3-gate pattern as a *brana* design decision, not as "what Claude Code does."

---

## The 8 opportunities — restated as decisions

Each opportunity from the leak-analysis doc, restated as "what is the decision the user must make?" with the shape of the tradeoff underneath. **No recommendations.**

### D1. Session memory alignment (leak §5 Opp 1 / t-1074)

**The question:** How should brana's existing `session-state.json` (implemented via `unified-session-state.md`) relate to CC's `session_memory` file?

**The tradeoff space:** see `../ideas/session-memory-cc-alignment.md` for three shape options (Additive / Replace / Mirror). Each has a different cost profile for compatibility, migration, and redundancy. **This is the single biggest decision in the batch** because it affects close/sitrep/session-end/session-start all at once.

**Blocker to decision:** user preference on compat-vs-cleanliness tradeoff.

### D2. Memory consolidation / "Kairos before Kairos" (leak §5 Opp 2 / t-1075)

**The question:** Should brana build a consolidation job *now*, before Anthropic flips the Kairos flag? And if yes, what pattern — Cathedral reimplementation, minimal dedup, or wait-and-see?

**The tradeoff space:** see `../ideas/memory-consolidation-kairos.md` for four shape options (Cathedral clone / Minimal dedup / Wait-and-mirror / Do nothing). **Every option that builds ahead is building on sand** (Cathedral pattern is conceptual, not leaked). Risk of wasted work is real.

**Blocker to decision:** risk tolerance. If we build to Cathedral's spec and Anthropic ships something incompatible, we throw work away.

### D3. Context threshold documentation (leak §5 Opp 3 / t-1076)

**The question:** Add `docs/architecture/context-budget.md` with the exact CC numbers (20K/13K/8K/15K), update skills to reference them, trigger `/brana:close` before autocompact fires?

**The tradeoff space:** Near-zero cost, but the numbers are *CC version-specific*. If 2.1.89 changes them, our docs lie. Options:
- **(a)** Hard-code the numbers, accept staleness risk.
- **(b)** Parameterize — ship `brana context-budget status` CLI that reads live CC config if available.
- **(c)** Just document "CC reserves ~20K; autocompact fires ~13K below that" qualitatively.

**Blocker to decision:** low — any answer works.

### D4. PreQuery / PostQuery hooks (leak §5 Opp 4 / t-1077)

**The question:** Are `PreQuery` / `PostQuery` hook events actually exposed to *plugin* hooks, or are they internal-only? If exposed, migrate brana's per-turn checks (doc-gate / tdd-gate / main-guard) from PreToolUse to per-query hooks.

**The tradeoff space:** Depends entirely on a reproducibility test. Cheap to check (one-line hook entry), blocked until we try.

**Blocker to decision:** 10-minute test. Worth doing before deciding anything else.

### D5. Undercover mode auto-config (leak §5 Opp 5 / t-1078)

**The question:** Should new project onboarding (`init-project` or `/brana:onboard` or `/brana:align`) automatically write `{"attribution":{"commit":"","pr":""}}` into `.claude/settings.local.json`?

**The tradeoff space:**
- User preference is already stated in MEMORY.md ("NEVER sign commit messages")
- CC setting exists and is the intended path
- Decision is *which tool* writes it: `init-project` (every new project), `/brana:onboard` (diagnostic scans), `/brana:align` (explicit alignment), or all three?

**Blocker to decision:** trivial — just a placement choice.

### D6. Skill usage telemetry / pruning (leak §5 Opp 6 — already ADR-035 candidate)

**The question:** Port `skill-kit`'s JSONL-scanner pattern into `brana skills usage`. Cull skills with <5 invocations in 30 days.

**The tradeoff space:** Already shaped in earlier brana work (ADR-035 was a candidate). This opportunity is a *confirmation* from the leak (CC's `initBundledSkills()` is tight), not new information. Decision is about **scheduling**, not shape.

**Blocker to decision:** prioritization, not understanding.

### D7. Unreleased features tracker (leak §5 Opp 7 / t-1079)

**The question:** Create `docs/research/cc-unreleased-features-tracker.md` with a row per flagged feature (Kairos, autoDream, Coordinator, UltraPlan, Daemon, Remote Bridge, Voice, Buddy, Capybara, Numbat), reviewed quarterly via `/brana:review`.

**The tradeoff space:** This is just a doc. The only decision is whether `/brana:review` grows a "CC release signal" section. Low cost, low risk.

**Blocker to decision:** trivial.

### D8. Agent loop reflection doc (leak §5 Opp 8 / t-1080)

**The question:** Write `docs/reflections/33-agent-loop.md` capturing the 11-step (verified: 10 + 1 inferred) async-generator loop as brana's canonical mental model.

**The tradeoff space:** Documentation-only. Two risks:
- We formalize a model with an unverified step count → contributors build against a fiction.
- We don't write it → contributors keep inventing ad-hoc mental models (the current state).

**Blocker to decision:** whether reflections DAG needs a new R6 node (it currently ends at R5 Venture).

---

## The moat (things to keep, not change)

The leak confirms several things brana should **keep owning**, not align away from:

1. **Cross-project memory** — CC's session_memory is per-project. Brana's vault is cross-project, cross-client. The leak shows no sign of cross-project memory in CC.
2. **Spec-driven workflow (SDD/TDD/DDD)** — zero test coverage in CC's own source. Brana's dimension/reflection/ADR/spec-graph architecture is not a CC pattern. It's brana's differentiator.
3. **Venture/business layer** — `/brana:review`, `/brana:pipeline`, `/brana:brainstorm`, `/brana:harvest`. CC is a dev tool. Brana is a multi-client operating system.
4. **Knowledge graph over domain docs** — brana's `brana graph` + ontology is concept-centric. CC's memory is transcript-centric.
5. **Structured cross-project backlog** — CC's TaskCreate/TaskGet are in-session only. Brana persists, syncs to GitHub, has streams and priorities.
6. **"Harness with opinions" positioning** — CC is a toolbox, brana is a workflow system on top of the toolbox. The leak confirms this framing.

And things brana should **probably cede**:
- Voice mode (if CC ships it, wrap it)
- Remote Bridge / phone control (not brana's competency)
- Tamagotchi `/buddy` persona (not brana's register)
- Undercover mode (CC-native setting — brana only sets it, doesn't reimplement it)

---

## The real open questions (not in the leak analysis)

These emerged from this findings pass and are NOT answered by the leak analysis doc:

1. **What's the shape of the relationship between brana's existing `session-state.json` schema and CC's new 8-section `session_memory`?** This is D1 above. Not obvious. The three options in the shape doc each have real costs.

2. **Is building on unverified patterns (Cathedral Kairos reimplementation) a responsible move?** The leak tells us Kairos *exists*, but nothing about its actual trigger logic, storage, or consolidation algorithm. Every concrete Kairos spec floating around online is a community reconstruction. Do we wait, do we build, do we build but bracket the decision?

3. **Does the ~35-skill count actually need pruning, or is that assumption from Cluster D leaking into this analysis?** The leak doesn't tell us how many skills CC *bundles* — it just tells us the loader function exists. We're conflating URL-batch cluster findings ("CLIs have won the skills-vs-MCPs debate") with leak findings. Might be over-claiming.

4. **Should the reflections DAG grow an R6 node for execution/runtime model, or does it belong inside R2 (Architecture)?** D8 raises this. The current DAG ends at R5 Venture; adding R6 is a real structural change, not just a doc.

5. **How should the CC `session_memory` file at `~/.claude/projects/<path>/.claude/session_memory` interact with brana's existing `~/.claude/projects/<path>/memory/session-state.json`?** Note these are *almost the same path*. One is `.claude/session_memory` (CC), the other is `memory/session-state.json` (brana). There's a collision waiting to happen.

---

## What's missing (gaps in our research)

- **We never fetched ccunpacked.dev directly** — 403 to scripted fetch. All our "verified" claims route through secondary sources that quote it. If anyone has a saved copy or an ad-hoc fetch, a single hour there would improve confidence.
- **No reproducibility tests have been run.** We don't know if PreQuery/PostQuery hooks work for plugins. We don't know if the deny-rules-at-50 claim is real. These are cheap to test.
- **The `session_memory` file format is unspecified beyond "8 sections."** Is it markdown? JSON? YAML frontmatter + sections? Nobody quoted the actual parser. D1 options assume text-serialized markdown because that matches the closest user-visible convention, but we're guessing.
- **We don't know if Anthropic has a canonical reflection doc for their own agent loop.** We're about to write one — it might conflict with (or redundantly duplicate) something they already have.

---

## Decision menu (for the user)

Ordered by reversibility (cheapest to reverse first):

| # | Decision | Cost to defer | Cost to reverse if wrong |
|---|---|---|---|
| D5 | Undercover mode auto-config | Zero — user keeps setting manually | Trivial — delete one setting write |
| D7 | Unreleased features tracker doc | Low — we lose the snapshot | Trivial — delete doc |
| D3 | Context threshold documentation | Low — we stay qualitative | Low — rewrite doc |
| D4 | PreQuery/PostQuery test | Zero | Zero — just a probe |
| D8 | Agent loop reflection doc | Low — contributors stay confused | Medium — reflections are cross-referenced |
| D6 | Skill usage telemetry | Medium — skill rot grows | Medium — removing `brana skills usage` after shipping |
| **D1** | **Session memory shape (Additive/Replace/Mirror)** | **High — every close/sitrep session afterward is stuck with the pick** | **High — migration of historical state** |
| **D2** | **Kairos consolidation (Cathedral/Minimal/Wait/Nothing)** | **High — if CC flips the flag** | **Very high — we'd be throwing away weeks of work** |

**Suggested shape of the conversation:** Start with the two cheap decisions (D4 probe, D5 auto-config). Then the two structural ones (D1 and D2) — both have shape docs ready for you to read and direct. Everything else can wait or follow from those.

---

## What happens next (pending your direction)

Nothing, until you decide. Specifically:

- **No edits** to `system/procedures/close.md`, `system/procedures/sitrep.md`, or `brana-core/src/session.rs`.
- **No new tasks spawned** beyond what's already in t-1074..t-1080.
- **No ruflo / memory consolidation cron** scheduled.
- **No reflections-DAG growth.**

Task status: t-1074 returned to `pending`. t-1075..t-1080 untouched (still pending, never started).

Shape docs to read before deciding: `session-memory-cc-alignment.md` (D1), `memory-consolidation-kairos.md` (D2). Both exist as of this doc's timestamp and contain option trees, not plans.

---

## Addendum — 2026-04-08 11:35 — two new sources

Three more URLs added to the analysis after the initial findings doc was written. Two contribute, one is tangential.

### Source A — "12 Agentic Harness Patterns from Claude Code" (Aum, LinkedIn)

**URL:** https://www.linkedin.com/posts/that-aum_12-agentic-harness-patterns-that-you-can-share-7447616148759638017-wt44

**Status:** [REPORTED] — this is a community synthesis, not leaked code. But it independently corroborates several leak findings and names two patterns that directly shape D1 and D2. It's framed as descriptive of Claude Code ("patterns from Claude Code"), not prescriptive.

**The 12 patterns:**

1. **Persistent Instruction File** — CLAUDE.md auto-loads per session
2. **Scoped Context Assembly** — hierarchical CLAUDE.md imports (org → user → project)
3. **Tiered Memory** — compact index (always) + topic files (on-demand) + full transcripts (search-only)
4. **Dream Consolidation** — background process dedups, prunes, resolves contradictions "during idle periods"
5. **Progressive Context Compaction** — four compression layers (recent detailed → older light → ancient aggressive)
6. **Explore-Plan-Act Loop** — read-only exploration → user discussion → full tool access
7. **Context-Isolated Subagents** — per-agent context windows with role restrictions
8. **Fork-Join Parallelism** — parallel agents in isolated git worktrees with cached parent context
9. **Progressive Tool Expansion** — start <20 tools, activate MCP/remote on-demand
10. **Command Risk Classification** — safe auto-run / risky approval / dangerous blocked
11. **Single-Purpose Tool Design** — dedicated Read/Edit/Grep/Glob beats generic Bash routing
12. **Deterministic Lifecycle Hooks** — hard-coded actions fire reliably post-event

**What this adds to the findings:**

- **Pattern 3 (Tiered Memory) is already brana's architecture.** MEMORY.md is the compact index. `~/.claude/projects/*/memory/feedback_*.md` files are topic files. `event-log.md` and git history are the full-transcript search layer. This is a validation signal — brana's pre-existing pattern matches what Aum describes CC as doing. **Direct implication for D1:** Options A and C are closer to "brana is already here" than it initially looked. The gap is in the *section schema*, not in the layering.

- **Pattern 4 (Dream Consolidation) is the second source that names the autoDream-style behavior.** Aum names it "Dream Consolidation." Cathedral.ai calls it "Kairos 4-phase." DeepLearning.ai reports it as "autoDream inside Kairos." Three independent community sources converge on the *concept* but still don't quote the leaked code for any of: trigger, storage, or algorithm. **D2 conclusion unchanged** — the pattern is well-named, but every implementation detail is speculative. The Cathedral 3-gate / 4-phase is still a reconstruction.

- **Pattern 10 (Command Risk Classification)** is NOT a brana pattern. Brana uses tier-1 static settings rules from t-794-era `.claude/settings.json`. A risk classifier would be a new layer. Adds a potential D9 to the decision menu: *should brana grow a command risk classifier hook?* — low priority but flagged.

- **Pattern 9 (Progressive Tool Expansion)** corroborates the Cluster D "CLIs over MCPs" thesis. If CC's own pattern is "start with <20 tools, activate the rest on-demand," then brana's pinned always-loaded MCPs (ruflo, context7, linkedin-mcp, google-sheets) are the opposite of this pattern. Relevant to D6 (skill telemetry) and to any future MCP audit.

- **Patterns 1, 2, 6, 7, 8, 11, 12** are either already brana patterns (1, 2, 11, 12) or already shaped in prior docs (6, 7, 8 are in `multi-agent-orchestration-investigation.md`). No new decisions needed from these.

**Decisions shifted by this source:**
- D1: slightly *lower stakes* (brana's layering is already tiered — the alignment is narrower than I thought)
- D2: same tradeoffs, but slightly more *semantic support* for the general direction (three independent sources now name the consolidation pattern)
- D9 (new): command risk classifier hook — low-priority, park for later

### Source B — "AI coding agents are fast but reckless" (Vyacheslav, LinkedIn)

**URL:** https://www.linkedin.com/posts/eric-vyacheslav-156273169_ai-coding-agents-are-fast-but-reckless-they-share-7447313311886389248-e3pw

**Status:** [Already tracked as t-1081, logged 2026-04-08 09:56.] The URL was re-pasted in the batch so the user could ensure all three were in scope. Content is a general observation that coding agents move fast but miss edge cases — no specific technical claims. **Does not shift any decision in this doc.** Keep t-1081 as a future research task for when guardrails / oversight patterns come up separately.

### Source C — "Design, AI, Vibecoding" (Felix Lee, LinkedIn)

**URL:** https://www.linkedin.com/posts/felixleezd_design-ai-vibecoding-share-7440567045315977216-BKxK

**Status:** [TANGENTIAL] — designer tutorial for using Claude Code as a "vibecoding" amplifier. 11 principles: scoped single changes, negative constraints, variations-before-finalizing, CLAUDE.md as design-system anchor, commits as checkpoints, screenshots as spec input.

**What this adds to the findings:**

- **Nothing directly for D1–D8.** No memory, hook, or consolidation content.
- Confirms the CLAUDE.md-as-manifest pattern is now widespread even in non-technical audiences — supports the "CLAUDE.md = OS, not config" thesis from Cluster E, but brana already had that.
- Weakly supports the `/brana:brainstorm` + negative-constraint pattern in brana's existing challenger skill.

**Decision impact:** Zero. Archive as a creator-to-watch entry if Felix Lee produces more harness-adjacent content; otherwise de-prioritize.

### Net effect of the addendum on the decision menu

| Decision | Change | Why |
|---|---|---|
| D1 | **Slightly de-scoped** | Aum Pattern 3 confirms brana's tiered memory already matches CC's layering. D1 is now narrower — it's about section names and budgets, not layering architecture. |
| D2 | **Direction more supported, details still speculative** | Three independent sources now name the consolidation pattern. Trigger/storage/algorithm still unverified. The `B Minimal dedup` option is reinforced as the low-risk path. |
| D3–D8 | Unchanged | Addendum sources don't touch context thresholds, hooks, undercover mode, skill telemetry, tracker doc, or reflection doc. |
| **D9 (new)** | **Added** | Aum Pattern 10: command risk classifier. Low-priority, flag-and-park. Can live as a row in the decisions table without its own shape doc. |

### What the addendum does NOT change

- Still no primary source for Kairos trigger logic, storage, or consolidation algorithm.
- Still no verified file format for `session_memory`.
- Still no test showing `PreQuery`/`PostQuery` are exposed to plugin hooks.
- Still no shipping timeline from Anthropic for any of the feature-flagged features.

The experiments proposed in the D1 shape doc (E1–E4) and the cheap audit proposed in the D2 shape doc are still the right next moves regardless of these additional sources.

---

## Second addendum — Karpathy "Living Knowledge Base" methodology

**Source:** Infographic titled *"How LLMs Turn Raw Research Into a Living Knowledge Base"* by Andrej Karpathy. Shared by the user 2026-04-08 11:4x. Image-only, no URL attached. Cross-references prior event log entries for Karpathy's "autoresearch" / "dream tool" pattern.

**Status:** [REFERENCE ARCHITECTURE] — this is an individual researcher's knowledge-management stack, not an agent harness. Not directly comparable to brana or CC. But the shape corroborates several Cluster A findings and shifts weight on D2.

### The pipeline (as depicted)

**Main pipeline (left to right):**
1. **Sources** — articles, papers, repos, datasets, images, diagrams
2. **raw/** — unprocessed files stored as-is
3. **WIKI** (central) — `.md` knowledge base with summaries + backlinks, concept categories, auto-maintained index. ~100 articles / ~400K words.
4. **Q&A Agent** — complex questions against the full wiki, **"no RAG needed"**
5. **Output** — markdown files, Marp slide decks, matplotlib plots
6. **Feedback loop:** *"filed back — knowledge compounds"* — Q&A answers flow back into the wiki

**Support layer (all connected to the wiki):**
- **Obsidian** — IDE frontend, human reads, LLM writes
- **Lint + Heal** — finds inconsistent data, imputes missing info, suggests new articles, uses web search to fill gaps
- **CLI Tools** — search engine + web UI + CLI interface, *"vibe-coded, keeps growing"*

**Looking ahead:** Fine-tune LLM on wiki data — *"knowledge in weights, not just context"*.

**Core insight (quoted):** *"You never write the wiki. The LLM writes everything. You just steer — every answer compounds."*

### What this is (and isn't) comparable to

Karpathy's diagram is a *single-operator research knowledge base*. Brana is a *multi-client operating system with spec-driven enforcement*. These are different artifacts:

| Dimension | Karpathy wiki | Brana knowledge |
|---|---|---|
| Purpose | Compounding research artifact | Load-bearing specification (drives hooks, skills, rules) |
| Writer | Only the LLM | LLM proposes, human approves — plus humans pin rules directly |
| Readers | The owner (one person) | Brana's own skills + hooks + agents + the human operator |
| Quality gate | Lint + Heal finds inconsistencies | ADRs, spec-graph, reconcile, maintain-specs, field notes |
| Feedback loop | Q&A answers filed back | Session close writes learnings to patterns + dimensions |
| Anti-RAG position | Explicit: "no RAG needed" | Mixed: ruflo MCP for semantic, grep for ad-hoc |

Brana is not going to adopt Karpathy's stack wholesale — the goals are different. But several pipeline elements map to brana's existing or planned components, and a few reveal gaps.

### Where Karpathy's pipeline maps to brana

| Karpathy step | Brana equivalent | Gap |
|---|---|---|
| **Sources** (step 1) | Event log + `/brana:log` + feed/inbox ingestion | **Small gap** — brana has the inputs, but no formal "source" entity type. Feed entries, emails, URLs, and transcribed audio all land in the event log without a typed model. |
| **raw/** (step 2) | `inbox/` directory (per-project, gitignored) | **Matches** — brana has this. `inbox/` is explicitly a drop folder for raw files awaiting processing. |
| **WIKI** (step 3) | `brana-knowledge/dimensions/` + `docs/reflections/` + spec-graph | **Matches in shape, differs in role.** Brana's wiki is *authoritative specification*, not compounding research. Dimensions are stable. |
| **Q&A Agent** (step 4) | `/brana:research` + `/brana:memory` + ruflo semantic search | **Matches**, though Karpathy's "no RAG" position conflicts with brana's ruflo investment (see `feedback_complexity-audit.md`). |
| **Output** (step 5) | `/brana:docs` + `/brana:harvest` + `/brana:export-pdf` + `/brana:notebooklm-source` | **Matches** |
| **Feedback: Q&A → wiki** | `/brana:close` writes session learnings to patterns + field notes | **Partial** — brana's close loop captures session-scale learnings. Ad-hoc Q&A during a session does NOT feed back. **This is a real gap.** |
| **Obsidian** | None — brana uses VS Code + CLI | **Not planned** — brana's operator writes markdown directly in an editor. No IDE frontend for the knowledge base as an independent artifact. |
| **Lint + Heal** (scheduled) | `/brana:reconcile` + `/brana:maintain-specs` (manual) | **Gap: not scheduled, not ambient.** Both brana commands are user-triggered. Karpathy's Lint + Heal is continuous background work. |
| **CLI Tools** | `brana` CLI (Rust) | **Matches in shape, differs in discipline.** Karpathy's CLI is "vibe-coded, keeps growing." Brana's is typed Rust with tests. Deliberate difference — brana's CLI is part of the enforcement layer. |
| **Fine-tune LLM on wiki data** | None — not on brana's roadmap | **Not planned** — no fine-tuning infrastructure, no budget. |

### What this shifts in the decision menu

**On D1 (session memory shape):** No direct impact. Karpathy's diagram doesn't model session continuity — it models static research accumulation. The 8-section format question stays as-is.

**On D2 (Kairos / memory consolidation):** **Notable nudge.** Three signals now converge toward a scheduled maintenance layer:
- The Aum post's Pattern 4 ("Dream Consolidation")
- Cathedral.ai's 3-gate / 4-phase reconstruction
- Karpathy's Lint + Heal box (ambient, background, deterministic)

Karpathy's version is the most concrete of the three — it describes a **deterministic** maintenance loop (find inconsistencies, impute missing info, suggest new articles, web-search to fill gaps). This is closer to **Option B (minimal dedup)** than to **Option A (Cathedral full consolidation)** in the D2 shape doc. It reinforces that the *lint-and-heal* framing is the lower-regret path than the *LLM-consolidation* framing.

**Possible reframe of D2 Option B:** instead of "minimal dedup," rename it **"lint + heal"** and expand scope to include: find contradictions between patterns, impute missing frontmatter fields, suggest patterns that should graduate from `feedback_*.md` to dimension docs. Still deterministic. Still low-risk. But with a clearer name and a more ambitious scope. This is a **shape-doc edit candidate**, not an implementation change.

**On D3–D9:** No direct impact.

**On the broader "anti-RAG" Cluster A thesis:** Karpathy is a fourth voice (after claude-memory-compiler, Sirchmunk, Graphify) arguing that semantic embeddings are unnecessary at personal/team scale. The weight behind "test markdown+ripgpred recall vs ruflo" (Cluster A Opportunity 1) increases. This is *not* a D-level decision in this doc, but it's relevant context for whether brana should keep investing in ruflo or migrate.

### New question raised by Karpathy's framing

**Q: Does brana have a "sources → wiki" pipeline, or only a "sessions → patterns" pipeline?**

Current state:
- Sessions produce learnings → `/brana:close` → `feedback_*.md` + ruflo
- URLs/emails/audio produce event log entries → manual triage → maybe a research doc → maybe a dimension
- Dimension docs are written manually or via `/brana:research`

Karpathy's question is: can an LLM take a pile of raw sources (`inbox/`) and produce wiki entries (`brana-knowledge/dimensions/`) *without a human in the middle*? Brana's answer today is "no — humans approve dimension additions." Should it be?

Arguments for yes:
- The current manual triage is a bottleneck (URL batches accumulate, see this very session)
- `/brana:research` already does most of the work — it just stops short of writing the final dimension
- Pattern files are already LLM-written (via close)

Arguments against:
- Dimension docs are spec, not research — they influence hooks and skills downstream
- Uncurated LLM writes would create drift that `/brana:reconcile` can't keep up with
- The current MEMORY.md is already under pressure from accretion; more auto-writes compounds the problem

**This is a D10 candidate** — flag-and-park, no shape doc needed yet. It's a strategic question that affects `inbox/`, `/brana:research`, `/brana:maintain-specs`, and the knowledge pipeline as a whole. Worth raising when the knowledge architecture v2 work (`docs/architecture/features/knowledge-architecture-v2.md`) comes up next.

### What brana should NOT adopt from Karpathy

- **"You never write the wiki."** Brana's CLAUDE.md, MEMORY.md, and rules are deliberately human-authored pin points. This is load-bearing for enforcement. Do not delegate rule authorship to the LLM.
- **Fine-tuning LLM on wiki data.** No infrastructure, no budget, unclear value for a harness tool. Park indefinitely.
- **Obsidian as IDE.** VS Code + brana CLI is the editing stack. Obsidian would add a dependency without clear upside.
- **"Vibe-coded CLI."** Brana's CLI is part of the enforcement layer — typed Rust with tests is correct for that role.

### Net effect of this addendum on the decision menu

| Decision | Change | Why |
|---|---|---|
| D1 | Unchanged | Karpathy doesn't address session state |
| **D2** | **Reframe Option B: "minimal dedup" → "lint + heal" with expanded scope** | Karpathy's Lint + Heal box is the most concrete description of scheduled deterministic maintenance. Still Option B in shape, richer in scope. |
| D3–D9 | Unchanged | No direct impact |
| **D10 (new, flag-and-park)** | **Added** | Sources→wiki pipeline: should LLM write dimension docs from inbox/ without human approval? Strategic question, no shape doc yet. |
| Cross-cutting: anti-RAG thesis | Strengthened | Fourth independent voice arguing against embeddings at brana's scale |

### Shape-doc edit candidate (not done yet)

The `memory-consolidation-kairos.md` Option B section could be renamed "Lint + Heal" and expanded with:
- Find contradictions between pattern files (e.g., two `feedback_*.md` files giving opposite guidance)
- Impute missing frontmatter fields (`description`, `type`, `confidence`)
- Suggest patterns that should graduate to dimension docs
- Surface dimension docs with no recent reference (candidates for archival)

All deterministic. All archive-don't-delete. Token-cost-free. Still runs as a scheduled job on existing brana scheduler. **This is a larger scope than the original Option B** — would move effort estimate from ~4h to ~6-7h — so it's a real shape change, not just a rename.

**Not editing the shape doc yet** — waiting for user direction before touching any doc beyond this addendum.
