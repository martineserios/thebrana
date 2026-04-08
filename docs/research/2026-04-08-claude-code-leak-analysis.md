# Claude Code Source Leak — Strategic Analysis for Brana Alignment

**Date:** 2026-04-08
**Status:** Primary research complete
**Source of leak:** Anthropic published Claude Code v2.1.88 to npm on 2026-03-30 with a source map file. A developer ("Shou") decoded the ~59.7 MB source map exposing ~512,000 lines across ~1,900 files. Anthropic's statement: "a release packaging issue caused by human error, not a security breach." Over 8,000 GitHub mirrors were taken down on request. The reconstructed codebase was mapped by "Zack" into the microsite **ccunpacked.dev**, which survived takedown.

**Why this matters for brana:** Brana is a harness built around Claude Code. Every significant decision about what brana *should* do depends on what Claude Code *actually* does internally. The leak gives us a one-time, primary-source view of that. This document extracts what was verified, maps it against brana's current state, and identifies concrete alignment and divergence opportunities.

**Source quality legend:**
- **[VERIFIED]** — fact taken from a primary source that directly quotes leaked code, file names, or function signatures (Zain Hasan blog, Kolkov DEV.to analysis, HN thread with code snippets)
- **[REPORTED]** — claim from secondary reporting on the leak (36kr, GIGAZINE, DeepLearning.ai, Roger Wong) without direct code quote
- **[CONCEPTUAL]** — reimplementation or interpretation by a third party, not the leaked code itself (Cathedral.ai's Kairos reimplementation)

---

## Part 1 — Verified Architecture

### 1.1 The query loop (agent loop)

**[VERIFIED — Zain Hasan blog]** The query loop is an **async generator**. It yields streaming events as they arrive from the Claude API. Sequential phases per turn:

1. Build system prompt + context (tools, skills, CLAUDE.md, git status, date)
2. Normalize message history
3. Apply compaction if needed
4. Stream API response
5. Detect `tool_use` blocks
6. Check permissions for each tool call
7. Execute tool
8. Return tool result to Claude
9. Loop back (repeat until response contains no tool calls)
10. Completion

**[REPORTED — Eric Vyacheslav via ccunpacked]** The LinkedIn post says "11 steps." Zain's enumeration above has 10 visible phases; the 11th is likely a post-turn hook or telemetry step (plausible, not verified).

**Key file:** `QueryEngine.ts` — controls LLM interaction + tool execution. **[VERIFIED — GIGAZINE]**

### 1.2 Tool registry

**[VERIFIED — Zain Hasan]** 50+ tools organized by category:

| Category | Tools |
|----------|-------|
| File | FileRead, FileEdit, FileWrite, Glob, Grep, NotebookEdit |
| Shell | Bash, PowerShell |
| Web | WebFetch, WebSearch |
| Agent | AgentTool, SendMessage, TeamCreate |
| Plan | EnterPlan, ExitPlan, Worktree |
| Task | TaskCreate, TaskGet, TaskUpdate, TaskList |
| MCP | MCPTool (dynamic), ListMCPResources, ReadMCPResource |
| System | AskUser, ToolSearch, Skill, Brief |

**[REPORTED — Eric Vyacheslav]** "52 built-in tools across 8 categories" — matches the 8 categories above.

**Base file:** `Tool.ts` — forms the basis of all tools. Uniform interface: schema, permissions, execution. **[VERIFIED — GIGAZINE]**

### 1.3 Memory system

This is the area brana cares about most. Two layers exist: **session_memory** (shipped) and **Kairos/autoDream** (unreleased, feature-flagged to false in the published build).

#### 1.3.1 Session memory (shipped) **[VERIFIED — Zain Hasan]**

- **Path:** `~/.claude/projects/<path>/.claude/session_memory`
- **Structure:** Fixed-schema file with 8 sections:
  1. Current State
  2. Files
  3. Workflow
  4. Errors
  5. Codebase Documentation
  6. Learnings
  7. Results
  8. Worklog
- **Budget:** Each section capped at ~2,000 tokens, total file capped at ~12,000 tokens
- **Update mechanism:** Background extraction runs after model sampling — the extractor reads the turn, updates the relevant section in place
- **Init trigger:** 8,000 tokens into a session
- **Refresh cadence:** Every 15,000 tokens thereafter
- **SM-Compact (Microcompaction Strategy A):** Preserves messages after the summarization boundary, expands backward to hit minimums, caps at 40K tokens. Minimum 10K tokens, minimum 5 text-block messages.

#### 1.3.2 Kairos (unreleased, feature-gated) **[REPORTED — DeepLearning.ai, Roger Wong, search results]**

- **What it is:** "Anthropic's internal always-on memory daemon for Claude Code. Keeps context coherent between sessions. Background daemon mode — runs in background, processes tasks, integrates memories when user not actively using CC."
- **Relationship to autoDream:** autoDream is the **logic layer inside Kairos**. Kairos provides the always-on runtime; autoDream does the consolidation work.
- **autoDream operations:** "Merges duplicate memories, eliminates contradictions, resolves speculations, prunes memory to make stored data more suitable for action."
- **Ship status:** Behind flags that compile to `false` in the published build. Not user-visible.

#### 1.3.3 Kairos consolidation pattern **[CONCEPTUAL — Cathedral.ai reimplementation, not leaked code]**

One team (Mike W on DEV.to, Cathedral.ai) reimplemented what they believe Kairos does, using the leaked source as a conceptual guide. Their version — which may or may not match the leaked code — uses:

- **3-gate trigger:**
  - Time gate: 24h since last consolidation
  - Session gate: 5+ new sessions since last run
  - Lock gate: no active lock file (single-writer invariant)
- **4 phases:** Orient → Gather → Consolidate → Prune
- **Hard cap:** Memory stays under 200 lines / 25 KB

Treat this as hypothesis, not fact. It is useful as a brana design reference, not as a description of what Anthropic actually did.

### 1.4 Context window management & prompt caching

**[VERIFIED — Zain Hasan]**

| Constant | Value |
|----------|-------|
| Effective context window | `modelContextWindow - 20,000` (reserve for compaction API calls) |
| Autocompact trigger | `effectiveWindow - 13,000 tokens` |
| Warning threshold | `effectiveWindow - 20,000 tokens` |

**Prompt caching:** Integrated via the Claude API's native `cache_edits`. Quote: *"Uses the cache_edits API to delete old tool results while keeping the prompt prefix cached."*

**Token counting (hybrid):**
- Primary: `anthropic.beta.messages.countTokens()`
- Fallback heuristic: ~1 token per 4 characters
- Canonical function: `src/utils/tokens.ts`

**Microcompaction behavior** (from HN thread, **[VERIFIED]**): clears old tool result content after 1-hour cache expiration, preserves the `tool_use` block but replaces output with `[Old tool result content cleared]`. JSONL flags `isCompactSummary`, `isVisibleInTranscriptOnly`, `isMeta` control what the API actually sees versus what's in the transcript file.

**Unreleased compaction modes (feature flags):** **[VERIFIED — Zain Hasan]**
- `HISTORY_SNIP` — content-clear old tool results
- `CACHED_MICROCOMPACT` — cache-edit microcompaction
- `CONTEXT_COLLAPSE` — model-side compression (internal, suppresses proactive autocompact when enabled)
- `REACTIVE_COMPACT` — only compact on API 413 errors (defer until necessary)

### 1.5 Hook system

**[VERIFIED — Zain Hasan]** 25+ lifecycle hook events. Known names:

- `PreToolUse`, `PostToolUse`
- `PreQuery`, `PostQuery`
- Session start / end
- Attribution hooks
- Plugin hooks (hot-reloadable)

**Loading:** `loadPluginHooks()` loads them at init. `captureHooksConfigSnapshot()` freezes the config before execution. `setupPluginHookHotReload()` enables runtime updates without restart.

**Brana currently uses:** PreToolUse, PostToolUse, SessionStart, Stop, UserPromptSubmit. **Brana does NOT use:** `PreQuery`, `PostQuery`, attribution hooks, the hot-reload mechanism.

### 1.6 Permission system

**[VERIFIED — Zain Hasan]** Cascading four-tier check:

1. **Static rules** from `settings.json` pattern matching
2. **Tool-specific logic** via `tool.checkPermissions()`
3. **Permission mode** (`bypassPermissions` / `auto` / `default` / `plan`)
4. **Auto-classifier** or user prompt as fallback

Note: the "deny rules silently degrade past 50 subcommands" rumor (from Alex Rogov LinkedIn) is **NOT** verified from the leaked source — it remains an unconfirmed community claim.

### 1.7 Plugin & skill loading

**[VERIFIED — Zain Hasan]**

- `initBundledSkills()` — bundled skills registered during init
- `initBuiltinPlugins()` — bundled plugins registered during init
- Plugin lifecycle: load → install → enable → disable
- Hot-reload: `setupPluginHookHotReload()`
- Plugins can expose hooks AND custom tools

**Startup order (6 phases, ~165 lines):**
1. Fast-path routing (`--version`, `--mcp` with zero imports)
2. Initialization (configs, telemetry, pre-connect)
3. Telemetry + permissions
4. Setup (CWD, hooks, file watcher)
5. Command/agent loading (parallel)
6. REPL launch

### 1.8 MCP

**[VERIFIED — Zain Hasan]** MCP Manager lives at `src/services/mcp/`. Responsibilities: server connections, OAuth, tool registration. External MCP tools are registered dynamically; `MCPTool` wraps external resources. Initialization happens during the `setup()` phase; tools discovered via `ListMCPResources` during command loading.

**Not verified from the leaked source:** the widely-cited "54K tokens to load GitHub MCP" figure. It's a plausible order of magnitude but hasn't been confirmed from primary code.

### 1.9 System prompt structure

**[VERIFIED — Zain Hasan]** Built each turn from:

1. Base system message ("You are Claude Code…")
2. Tool schemas (50+ tools' input/output definitions)
3. Context block: git status, CLAUDE.md files, user context, current date
4. Behavioral instructions: permission rules, tool usage guidance
5. Skill descriptions (bundled skills injected)

This is rebuilt on every API call — there is no multi-turn caching of the system prompt at the brana level.

### 1.10 Model routing

**[VERIFIED — Zain Hasan]** Single `mainLoopModel` in `AppState`. No per-task Opus/Sonnet/Haiku decision logic was found in the main loop — the main loop runs on one model. There is *fallback* logic on error.

**[VERIFIED — Kolkov]** Silent model downgrade: "3 consecutive 529 errors → silently switch from Opus to Sonnet" with no user notification. This is the only model routing logic in the main loop.

Agent subcalls (Task/AgentTool) can use different models per brana's own observation, but the main conversation runs on one model unless the silent-downgrade path fires.

### 1.11 Unreleased features (feature-flagged to false)

All **[REPORTED — DeepLearning.ai, Roger Wong, search]**:

| Feature | Description | Ship status |
|---------|-------------|-------------|
| **Kairos** | Always-on background memory daemon | Flag: false |
| **autoDream** | Memory consolidation logic inside Kairos | Flag: false |
| **Coordinator Mode** | Spawns parallel agents in separate worktrees | Flag: false |
| **UltraPlan** | Subagent that runs 30-min execution windows on Opus-class models, cloud-offloaded resource-intensive work | Flag: false |
| **Daemon Mode** | Runs sessions in background via tmux | Flag: false |
| **Remote Bridge** | Phone control for running sessions | Flag: false |
| **Voice Mode** | STT / TTS interface | Flag: false |
| **Buddy persona** | "Tamagotchi-style" pet behavior, `/buddy` slash command, user engagement commentary | Flag: false |
| **Undercover mode** | Strips "Claude Code" and "Co-Authored-By" from commit messages and PR descriptions | Configurable via `settings.json.attribution.commit` / `.pr` |
| **Capybara** | Internal variant of Claude 4.6 | Internal |
| **Numbat** | Unreleased model | Internal |

---

## Part 2 — Code Quality & Operational Findings (Kolkov analysis)

**[VERIFIED — DEV.to/kolkov, quoting leaked source]** These are not architectural features, but they are important context for how brittle the harness is under the hood. Relevant because they inform brana's "don't compete with CC on robustness — complement it."

- **Zero test coverage** across 64,464 lines of TypeScript
- **5.4% orphaned tool calls** — model requests a tool, execution completes, result silently dropped (never reaches the model). This matches brana's intuition that post-hoc task tracking matters.
- **Watchdog initialized after dangerous connection phase** — first 5+ months of the 2.x branch had the most vulnerable code unprotected
- **Memory leaks:** Sessions show 13.8–15.4 GB leaks during extended Bun runtime; 7 parallel CC processes = 5.3 GB RSS
- **REPL.tsx is a 5,005-line / 875 KB monolith** using React virtual DOM in a terminal app. 470 `useState` hooks, 372 `useEffect` hooks.
- **`src/cli/print.ts` is the architectural failure point:** 3,167 lines in a 5,594-line file, 12 nesting levels, ~486 cyclomatic complexity branch points. Handles agent run loop, SIGINT, rate limits, AWS auth, MCP lifecycle, and plugin management in nested callbacks.
- **Promise.race without .catch()** in concurrent tool execution — one rejected promise kills all pending tools
- **5 nested AbortController levels** for single HTTP requests
- **74 npm dependencies** for a CLI wrapper; both Axios AND fetch present
- **SSE ping heartbeats from Anthropic are currently ignored** by CC (Kolkov's proposed fix: 3-tier adaptive timeout — 30s connection / 120s network idle / 300s content idle)

---

## Part 3 — The Colorful Bits

### 3.1 Frustration regex **[VERIFIED — Kolkov]**

Regex that matches user messages for negative sentiment:

```
/(wtf|shit|fuck|horrible|awful|terrible)/bi
```

Purpose inferred (not confirmed): classify user frustration to route differently (more care, plan mode, escalation). This is what the HN thread was calling "frustration regexes" — the plural because there may be several.

### 3.2 Silent model downgrade **[VERIFIED — Kolkov]**

`3 consecutive 529 errors → silently switch from Opus to Sonnet`. No user notification. Important implication for brana: billing, performance, and reproducibility are non-deterministic in the presence of upstream overload.

### 3.3 Attestation sentinel **[VERIFIED — Kolkov]**

A Zig module scans HTTP request bodies for the sentinel `cch=b66e8` and replaces it with attestation tokens. Side effect: breaks prompt cache keys whenever the replacement happens. This is probably how CC proves to the API that the request came from the CC binary, not an impersonator.

### 3.4 Undercover mode **[VERIFIED — HN thread]**

System prompt contains: *"NEVER include in commit messages or PR descriptions: the phrase 'Claude Code' or any mention that you are an AI. Co-Authored-By lines or any other attribution."*

Controlled by user settings:
```json
{
  "attribution": {
    "commit": "",
    "pr": ""
  }
}
```

This matches the user's MEMORY.md preference ("NEVER sign commit messages. No Co-Authored-By, Signed-off-by") — the setting is already exposed, the user has discovered the UX-facing side of it.

### 3.5 `/buddy` Tamagotchi **[REPORTED — Roger Wong]**

Slash command `/buddy` enables a pet-style engagement layer. Not shipped.

---

## Part 4 — Gap Analysis: Brana vs Claude Code

| Subsystem | CC has | Brana has | Gap | Action |
|-----------|--------|-----------|-----|--------|
| Agent loop | 11-step async generator with permission check between tool detect and execute | Claude Code IS the loop — brana wraps it | Brana operates *around* this loop via hooks | Stay outside the loop; never try to replace it |
| Tool registry | 50+ tools, 8 categories, uniform `Tool.ts` base | 10 brana-mcp tools + CLI + skills | CC has many more tools; brana adds only what extends the domain | Don't duplicate File/Shell/Web tools; focus brana-mcp on structured domain operations (backlog, session, files tracking) |
| Session memory | `session_memory` file with 8 fixed sections, 2K/section cap, 12K total, 8K/15K cadence | `~/.claude/projects/*/memory/` — unstructured markdown + MEMORY.md index | **GAP: brana has no fixed-schema session state, no token budget discipline, no background extraction** | HIGH PRIORITY — align brana's close/sitrep output with CC's 8-section schema |
| Background memory daemon (Kairos) | Feature-gated off | `/brana:close`, scheduled jobs | **GAP: brana has no always-on consolidation** | Build brana's version before CC ships theirs — first-mover on the pattern |
| Memory consolidation (autoDream) | Feature-gated off | Manual /brana:retrospective | **GAP: no automatic dedup / contradiction resolution** | Build a scheduled `brana memory consolidate` job that dedups, resolves, prunes |
| Context window management | Hard-coded reserves (20K/13K), SM init at 8K | No explicit reserves; relies on CC's autocompact | No gap per se — brana delegates to CC | Document the thresholds in brana docs so skills understand the budget |
| Prompt caching | `cache_edits` API, keeps prefix cached | Delegated to CC | No gap | None |
| Hook events | 25+ events incl PreQuery/PostQuery, attribution, plugin hooks | ~5 events used (PreToolUse, PostToolUse, SessionStart, Stop, UserPromptSubmit) | **Gap: brana ignores PreQuery, PostQuery, attribution, hot-reload** | Audit: are PreQuery/PostQuery useful for brana? Likely yes — cleaner boundary than PreToolUse |
| Permissions | 4-tier cascade (static → tool → mode → classifier) | Uses tier 1 (static rules in settings) | CC handles the rest | No action unless brana wants to inject a tier 3.5 classifier |
| Plugins/skills | `initBundledSkills()`, hot-reload | 35+ skills, ADR-034 stub pattern | Brana has more skills than CC ships bundled — might be oversized | Pair with skill-kit usage telemetry (ADR-035) |
| MCP | Dynamic registration, OAuth, lazy tool discovery | Pinned wrapper scripts, blocking startup | CC is more lazy than brana's startup assumes | Confirm brana's wrappers don't double-block the already-blocking CC MCP init |
| Model routing | Single main loop model + silent 529 downgrade | Subagent model override (Haiku for cheap agents) | Brana is ahead here — more explicit per-agent routing | Keep; document it as differentiation |
| Unreleased features | Coordinator Mode, UltraPlan, Daemon Mode, Remote Bridge, Voice, Buddy | None of these | **Gap: brana doesn't yet have background/daemon/remote story** | Decide: match these or cede them to CC |

---

## Part 5 — Top Alignment Opportunities

Ranked by (strategic importance × concreteness × effort feasibility).

### Opportunity 1: Align brana session state with CC's 8-section schema

**What:** Rewrite `/brana:close` and `/brana:sitrep` output to match CC's `session_memory` format exactly: Current State, Files, Workflow, Errors, Codebase Documentation, Learnings, Results, Worklog. Enforce the 2K-per-section / 12K-total budget.

**Why:** When CC eventually ships `session_memory` as a user-visible feature, brana's handoffs become interchangeable with it. Users won't have to pick between brana and CC memory — they become the same file.

**Effort:** S — mostly a format change to existing procedures.

**Risk if skipped:** Brana's "close" becomes redundant once CC ships its own session memory UI. Brana's format diverges and forces users to choose.

### Opportunity 2: Build brana's Kairos/autoDream before CC ships theirs

**What:** A scheduled `brana memory consolidate` job that runs on the Cathedral.ai-style 3-gate trigger (24h / 5 sessions / no lock), does the 4 phases (Orient, Gather, Consolidate, Prune), targets the same kind of compact memory artifact.

**Why:** This is the single biggest unreleased-feature opportunity. CC has it feature-flagged off. Brana can ship it first, get real usage data, and either own the pattern or merge cleanly with CC when they turn their flag on. Directly addresses the "ruflo fragility" pain documented in brana's own memory.

**Effort:** M — cron job + existing brana memory export + LLM call + diff-based update.

**Risk if skipped:** When Anthropic flips the `KAIROS` flag, brana's knowledge vault becomes second-fiddle overnight.

### Opportunity 3: Match CC's 20K-reserve / 13K-autocompact thresholds in brana docs and skill budgets

**What:** Document the exact thresholds (effectiveWindow − 20K reserve, autocompact at effectiveWindow − 13K) in `docs/architecture/context-budget.md`. Update every skill's "when to compact / when to hand off" language to reference these constants. Adjust `/brana:close` to trigger earlier — context resets are preferred over compaction (Anthropic's own recommendation).

**Why:** Brana's current context rules are qualitative ("avoid bloat"). CC's thresholds are hard numbers. Aligning means brana's handoff triggers fire before CC's autocompact does — brana gets the session cleanly, not mid-compaction.

**Effort:** S — documentation + rule update.

**Risk if skipped:** Brana close/sitrep hooks fire too late, after CC has already mangled context.

### Opportunity 4: Adopt PreQuery / PostQuery hook events

**What:** Investigate whether CC exposes PreQuery/PostQuery to plugin hooks (not just internal). If yes, migrate the current PreToolUse/PostToolUse brana hooks that fire per-tool to PreQuery/PostQuery that fire per-turn. Simpler semantics.

**Why:** Brana's PreToolUse hooks fire dozens of times per turn (once per Read/Grep/Bash). This is expensive and produces noisy logs. Per-turn hooks are the right granularity for most brana checks (doc-gate, tdd-gate, main-guard all fire once per turn ideally).

**Effort:** M — requires verifying hook availability and rewriting matchers.

**Risk if skipped:** Brana hooks stay noisy and high-friction; users disable them.

### Opportunity 5: Make brana undercover-mode aware

**What:** Already a user preference in brana (MEMORY.md: "NEVER sign commit messages"). Make brana's `/brana:commit` helper write `{"attribution":{"commit":"","pr":""}}` into project `settings.local.json` automatically when a new project is onboarded.

**Why:** The user has stated this preference repeatedly. The CC-native config key exists. Brana should set it for them, not rely on them remembering.

**Effort:** XS — single settings write.

**Risk if skipped:** Minor — user continues to enforce manually.

### Opportunity 6: Skill usage telemetry (cross-cluster with earlier research)

**What:** Scan `~/.claude/projects/*.jsonl` to count how often each brana skill is actually invoked over 30 days. Cull skills with <5 invocations. (This was the `skill-kit` finding from the earlier Cluster D research — it's here for completeness.)

**Why:** Brana has ~35 skills; CC ships `initBundledSkills()` with a much smaller set. The leak suggests Anthropic keeps its skill bundle tight. Brana should instrument before pruning.

**Effort:** M — parser + CLI subcommand + reporting.

**Risk if skipped:** Brana keeps carrying dead skill weight into every session.

### Opportunity 7: Track the unreleased feature flags as a roadmap signal

**What:** Create `docs/research/cc-unreleased-features-tracker.md`. For each of Kairos, autoDream, Coordinator Mode, UltraPlan, Daemon Mode, Remote Bridge, Voice Mode, Buddy — record: what it does (as currently understood), when/if it ships, what brana's corresponding capability is, whether brana should match or cede. Review quarterly.

**Why:** Anthropic has already committed to these areas. Brana's roadmap should react to each flip of a feature flag, not be surprised by it.

**Effort:** S initially, ongoing.

**Risk if skipped:** Brana gets blindsided by each CC release.

### Opportunity 8: Formalize the agent loop as brana's execution model

**What:** Add a reflection doc (`docs/reflections/33-agent-loop.md`) that captures the 11-step loop as brana's canonical mental model for what happens during a Claude Code turn. Every new brana skill and hook should reference which step it operates on.

**Why:** Brana's skills currently have no shared vocabulary for *when* they run in the turn. "PreToolUse" is granular but not semantic. The 11-step loop gives a semantic map.

**Effort:** S — one reflection doc.

**Risk if skipped:** Brana contributors keep inventing their own mental models.

---

## Part 6 — Divergence Opportunities (brana's moat)

Things CC does NOT do that brana should keep owning.

1. **Cross-project memory.** CC's session_memory is per-project. Brana's knowledge vault is per-user, cross-project, cross-client. The leak contains no sign of cross-project memory in CC. **Keep investing.**

2. **Spec-driven workflow enforcement (SDD + TDD).** CC has no dimension/reflection/roadmap architecture, no spec-graph, no ADRs as code, no doc-gate hook. This is brana's architectural moat. The Kolkov "zero test coverage" finding is actually *positive* for brana: Anthropic itself doesn't dogfood test-first development. **Lean into SDD as positioning.**

3. **Venture/business layer.** `/brana:review`, `/brana:pipeline`, `/brana:brainstorm`, venture tracking — none of this exists in CC. CC is a developer tool. Brana is a multi-client operating system. **Keep investing; this is where brana is uniquely valuable.**

4. **Knowledge graph over domain docs.** Brana's `brana graph` + dimension ontology is not something CC touches. CC's memory is transcript-centric; brana's is concept-centric. **Keep building toward GraphMind migration.**

5. **Structured backlog across projects.** CC has `TaskCreate/TaskGet/TaskList` for *in-session* TODOs only — they disappear at session end. Brana's backlog persists, has cross-project views, GitHub Projects sync, streams, priorities. **Keep.**

6. **The "harness with opinions" positioning.** CC ships opinionated tools. Brana ships opinionated *workflows* on top of those tools. The leak confirms CC is a toolbox, not a workflow system. **That's the cleanest positioning angle brana has.**

### Things brana should probably cede

- **Voice mode.** If CC ships it, brana shouldn't reinvent STT/TTS. Wrap CC's voice.
- **Remote Bridge (phone control).** Not brana's core competency. If CC ships it, use it.
- **Tamagotchi persona (`/buddy`).** Not brana's register. Let CC do this.
- **Undercover mode.** Already a CC-native setting. Brana only needs to set it.

---

## Part 7 — Uncertainty & Rumors to Verify

Things primary sources did not confirm, despite being widely repeated:

1. **"Deny rules silently degrade past 50 subcommands"** (Alex Rogov LinkedIn) — NOT in Zain Hasan's writeup; not verifiable without direct source access. **Reproducibility test:** write a simple CC session with 60+ bash subcommands and measure whether deny rules fire. If real, file upstream bug.

2. **"GitHub MCP costs 54,000 tokens vs `gh --help` 562"** (Vasilev post) — plausible order of magnitude but unverified from leaked source. **Test:** run a fresh CC session with only github-mcp in `.mcp.json`, capture the system prompt token count, subtract baseline.

3. **The exact "11 steps" of the agent loop** — Zain's async generator enumeration shows ~10 phases. The 11th step is inferred (probably a post-turn hook). Would need ccunpacked.dev sub-pages to confirm.

4. **Auto Dream auto-activation trigger** — the Cathedral 3-gate model (24h / 5 sessions / lock) is a reimplementation, not the leaked code.

5. **Kairos storage backend** — no one has quoted the actual Kairos file format or storage schema. Claims that it uses SQLite or JSON or markdown are all speculation.

6. **Fake tools.** HN thread mentioned this but no primary source explained what they are. Guesses: tools that exist in the schema but always return static output (for model behavior shaping), or tools that appear in help but are deny-listed by default.

7. **The actual file `QueryEngine.ts` contents** — referenced by GIGAZINE, but no one has posted code.

---

## Part 8 — Action Items (tasks created)

See companion tasks created 2026-04-08 (t-1074..t-1080). Summary:

- **t-1074** P1 — Align brana session state with CC 8-section schema
- **t-1075** P1 — Build scheduled `brana memory consolidate` (Kairos/autoDream prototype)
- **t-1076** P2 — Document CC context thresholds in brana docs, trigger close earlier
- **t-1077** P2 — Verify PreQuery/PostQuery hook availability and migrate brana hooks
- **t-1078** P3 — Auto-set `attribution.commit/.pr` on new project onboard
- **t-1079** P2 — CC unreleased-features tracker doc + quarterly review cadence
- **t-1080** P3 — Add reflection doc 33: agent loop as execution model

## Sources (primary)

- [Inside Claude Code Architecture — Zain Hasan (blog)](https://zainhas.github.io/blog/2026/inside-claude-code-architecture/) — **VERIFIED source, quotes leaked code**
- [Claude Code Unpacked — ccunpacked.dev](https://ccunpacked.dev/) — primary visualization site (403 to scripted fetch but referenced by all secondary sources)
- [We reverse-engineered KAIROS from the Claude Code leak — Mike W (DEV.to)](https://dev.to/mike_w_06c113a8d0bb14c793/we-reverse-engineered-kairos-from-the-claude-code-leak-heres-the-open-version-48dc) — CONCEPTUAL Kairos reimpl
- [We Reverse-Engineered 12 Versions of Claude Code — Kolkov (DEV.to)](https://dev.to/kolkov/we-reverse-engineered-12-versions-of-claude-code-then-it-leaked-its-own-source-code-pij) — VERIFIED with code snippets, the best secondary source for Kolkov's findings
- [The Claude Code Source Leak: fake tools, frustration regexes, undercover mode — Hacker News](https://news.ycombinator.com/item?id=47586778) — community discussion
- [Claude Code's Source Code Leaked — DeepLearning.ai](https://www.deeplearning.ai/the-batch/claude-codes-source-code-leaked-exposing-potential-future-features-kairos-and-autodream/) — REPORTED, Kairos + autoDream + features list
- [Claude Code Unpacked — Roger Wong](https://rogerwong.me/2026/04/claude-code-source-leak) — REPORTED summary + /buddy detail
- [GIGAZINE Claude Code Unpacked article](https://gigazine.net/gsc_news/en/20260402-claude-code-unpacked/) — REPORTED, confirms QueryEngine.ts and Tool.ts file names
- [36kr: Chinese Dropout Doctor Finds 510k Line Claude Code Source Leak](https://eu.36kr.com/en/p/3750770295898630) — REPORTED, leak circumstances
