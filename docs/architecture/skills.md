# Skills Architecture

> Design principles and structure for brana skills. For the complete per-skill catalog, see [Skill Reference](../reference/skills.md). For the walkable idea → ship narrative these skills compose into, see [Idea → Ship: The Skill Flow](idea-to-ship.md). For the parallel catalog of committed **loops** (trigger + prompt + termination check, `/loop`-armed), see [system/loops/README.md](../../system/loops/README.md).

## Group Overview

| Group | Purpose | Examples |
|-------|---------|---------|
| **brana** | Core system management | backlog, reconcile, plugin, do |
| **core** | System foundations | docs, sitrep |
| **execution** | Development lifecycle | build, onboard, align |
| **learning** | Knowledge acquisition | challenge, research, memory |
| **thinking** | Reasoning and ideation | brainstorm, decide, pre-mortem, first-principles, inversion, second-order-thinking, six-thinking-hats, systems-thinking, jobs-to-be-done, swot-analysis, decision-matrix, critical-thinking-logical-reasoning |
| **venture** | Business operations | review, client-retire |
| **session** | Session lifecycle | close |
| **capture** | Event capture | log |
| **utility** | Specialized tools | scheduler, gsheets, export-pdf |

## Skill Layout (ADR-034, amended 2026-06-10)

Skills are **inline by default**: the full procedure body lives in `system/skills/{name}/SKILL.md` after the frontmatter. Native Claude Code lazy-loads SKILL.md bodies (frontmatter-only at session start), so inlining costs nothing at startup and removes the stub→Read hop that was the recurring failure layer behind procedure-Read errors.

**Phase-split layout — the big four:** `build`, `close`, `backlog`, `reconcile` exceed reliable single-load size, so each is a slim SKILL.md (flow overview, rules, and a machine-readable `<!-- PHASES -->` registry mapping steps/subcommands/scopes to files) plus per-phase bodies in `system/skills/{name}/phases/*.md` (each ≤400 lines). The SKILL.md's Phase Protocol governs loading: Read a phase file at every step boundary, never execute a phase from memory, and on resume-after-compression Read the current step's phase file first. Stubs no longer exist anywhere; `tests/skills/test_skill_inline_layout.sh` (empty allowlist) and `tests/skills/test_skill_phase_layout.sh` enforce both layouts.

`system/procedures/` retains only knowledge docs with no SKILL.md counterpart (migrate.md). Acquired skills under `system/skills/acquired/` are inline — same rule. Shared sections referenced by multiple procedures live in `system/skills/_shared/` (e.g. `challenger-gate.md`, extracted in t-1942 so the bug-fix and refactor strategies don't lose the gate across phase files).

Tests and validate.sh read a skill's **effective body** — the layout-agnostic concatenation of SKILL.md + phases/*.md (in PHASES-registry order) — via `tests/lib/effective_body.sh` and validate.sh's `effective_body()`.

History: ADR-034 originally stubbed all skills because CC loaded full SKILL.md content at startup (bug #14882, ~34K tokens, 4-minute cold starts). The ADR's Risks clause anticipated the reversal — CC fixed the loading behavior, so the bodies merged back (t-1941), and the big-four stub exception ended when their phase-split landed (t-1942).

## Skill Anatomy

Every skill lives at `system/skills/{name}/SKILL.md`:

```yaml
---
name: skill-name
description: "One-line description for discovery and help text."
argument-hint: "[optional args]"
group: execution
depends_on:
  - other-skill
allowed-tools:
  - Read
  - Write
  - Bash
  - AskUserQuestion
---

# Skill Name

Instructions for Claude when this skill is invoked...
```

For the big four, the SKILL.md body is the slim overview and the phase bodies live next to it:

```markdown
<!-- PHASES -->
| Step | File | Load when |
|------|------|-----------|
| LOAD | phases/load.md | Skill entry — always first |
| ... | ... | ... |
<!-- /PHASES -->
```

> Phase paths (`phases/{file}`) are base-dir-relative from `system/skills/{name}/SKILL.md` and resolve identically in the repo layout and the deployed-plugin layout. Do not use the absolute repo-root form — it breaks when the skill loads from the plugin. Do not create stubs — new skills are always inline; only split into phases when a body exceeds reliable single-load size (~500 lines).

Key fields:
- **`allowed-tools`** restricts which tools Claude can use during execution. Skills without Write, Edit, or Bash are read-only.
- **`depends_on`** declares skill dependencies (e.g., build depends on backlog, challenge, retrospective).
- **`argument-hint`** shows expected arguments in help text.
- **`group`** determines where the skill appears in the reference catalog.

## Composability

Skills compose with each other — each is a building block that other skills call:

| Caller | Callee | When |
|--------|--------|------|
| `/brana:build` CLOSE | `/brana:docs all` | Post-merge doc updates |
| `/brana:build` PLAN | `brana backlog add` | Persist subtasks (Medium/Large) |
| `/brana:backlog start` | `/brana:build` | Auto-enters build loop for code tasks |
| `/brana:close` | `debrief-analyst` agent | Session-end extraction |
| `/brana:challenge` | `challenger` agent | Adversarial review |

## Commands

Commands in `system/commands/` orchestrate multi-step spec workflows. They are agent-executed protocols, not slash commands.

| Command | Purpose |
|---------|---------|
| `maintain-specs` | Full spec correction cycle: errata -> reflections -> synthesis -> hygiene |
| `apply-errata` | Apply pending errata through the layer hierarchy |
| `re-evaluate-reflections` | Cross-check reflections against dimension docs |
| `repo-cleanup` | Commit accumulated spec changes: survey -> batch -> branch -> merge |
| `init-project` | Initialize a new project with brana structure |

See [Command Reference](../reference/commands.md) for details.

## MCP Tool Integration

Several skills now use ruflo MCP calls as their preferred data path (2026-04-01):

| Skill | MCP usage |
|-------|-----------|
| **close** | Step 9b: 3 MCP calls — `memory_store` (ns:session), `hive-mind_memory`, `claims_release`. Steps 5, 6, 10 prefer MCP paths over CLI fallbacks. |
| **sitrep** | Source 6: `hooks_intelligence_pattern-search` for recent patterns. Source 7: `hive-mind_memory list` for active swarm context. |
| **research** | Phase 0: `memory_search` (ns:all) for prior findings. Phase 2: `embeddings_compare` for dedup against existing knowledge. |
| **build** | `hive-mind` announce at strategy start and build completion for multi-agent coordination. |
| **backlog** | `claims_claim`/`claims_release` at task start/done. Step 5: `memory_search` (ns:skills) for semantic skill suggestion — configurable thresholds (suggest >0.5, mention >0.3, gap <0.3 triggers marketplace). CLI `brana skills suggest` as fallback. See ADR-026, feature brief `skill-routing-in-backlog-start.md`. |

When ruflo is unavailable, every skill degrades gracefully to CLI or native memory fallbacks.

## Acquired Skills

Skills installed from external marketplaces via `/brana:acquire-skills` live in `system/skills/acquired/{name}/SKILL.md`. They follow the same anatomy but are tracked separately for update management.

### Source-Tiered Trust Model (ADR-026)

External skills are classified by source into trust tiers that determine install behavior:

| Source | Tier | Install | Tool access |
|--------|------|---------|-------------|
| `anthropics/*` | Trusted | Auto with confirm | Full |
| `skills.sh` official, `trailofbits/*` | Verified | Review prompt | Default set |
| Other GitHub/npm | Community | Quarantine | Read, Glob, Grep only |
| Unknown | Blocked | Rejected | N/A |

Community skills install with `quarantine: true` in frontmatter and read-only tools. `/brana:reconcile --scope security` includes an incoming skill scan that checks acquired skills for dangerous allowed-tools, credential path references, suspicious MCP tool requests, and missing frontmatter (formerly `/brana:audit`, merged into reconcile's security domain).

### Installed Acquired Skills

| Skill | Source | Purpose | Installed |
|-------|--------|---------|-----------|
| `caveman` | `JuliusBrussee/caveman` | Ultra-compressed output (~50% token reduction on brana prompts). Trigger: `/caveman`. | 2026-04-13 |
| `pre-mortem` | Gary Klein / community | Prospective hindsight: imagine failure before committing, design preventions. | 2026-06-15 |
| `first-principles` | Aristotle/Musk/Feynman / community | Strip assumptions, interrogate each, rebuild from fundamentals. | 2026-06-15 |
| `inversion` | Jacobi/Munger / community | Design failure actively, then build avoidance strategy. | 2026-06-15 |
| `second-order-thinking` | Howard Marks / community | Trace consequences past the obvious through 3–4 order effects. | 2026-06-15 |
| `six-thinking-hats` | De Bono / community | 6 parallel perspectives: White/Red/Black/Yellow/Green/Blue. | 2026-06-15 |
| `systems-thinking` | Meadows / community | Stocks, flows, feedback loops (reinforcing vs balancing), leverage hierarchy. | 2026-06-15 |
| `jobs-to-be-done` | Christensen/Ulwick / community | Functional/emotional/social job dimensions; what is the customer hiring this for? | 2026-06-15 |
| `swot-analysis` | Humphrey / community | SW×OT cross-reference matrix → strategic moves. | 2026-06-15 |
| `decision-matrix` | Pugh / community | Weighted criteria scoring + sensitivity analysis for multi-alternative decisions. | 2026-06-15 |
| `critical-thinking-logical-reasoning` | Paul/Elder/Kahneman / community | Fallacies, assumptions, evidence quality; 8-step reasoning audit. | 2026-06-15 |

## Invocation Mode Audit (t-2832, 2026-08-17)

`disable-model-invocation` is native Claude Code frontmatter, not a brana invention — see [testing-validation.md](testing-validation.md) Check C for the field's contract. Omitted (the default) = **model-invoked**: the description stays loaded every turn and the agent may fire the skill autonomously. `true` = **user-invoked-only**: zero ongoing context cost, reachable only by the user typing `/brana:{name}`.

**This is a friction nudge, not a hard gate** ([ADR-076](decisions/ADR-076-build-receipts-as-executed-evidence.md) §Verified findings, #3): the field blocks only the `Skill` tool. A skill set to `true` is still a readable `SKILL.md` — the model can `Read` it and follow the steps inline via `Bash`/`Edit`/`Write` without invoking the skill itself. It raises the bar for opportunistic firing; it doesn't guarantee the effect is unreachable another way.

Before this audit, exactly 1 of the 40 skills under **`system/skills/`** (`challenge`) set the field. Every skill in that directory (excluding `_shared/` and `acquired/`) was classified against one question: **is autonomous, unprompted firing destructive, one-shot, external, or hard to reverse?** Seven skills answered yes and now carry `disable-model-invocation: true`: **ship**, **client-retire**, **plugin** (the task's own named minimum), plus **gsheets**, **meta-templates**, **scheduler**, and **onboard** — surfaced by this audit as equally clear-cut against the same criterion (see rationale below) and flipped in the same pass rather than left as a dangling recommendation.

Scope note: `system/skills/` is not the only model-invokable skill surface in this repo. `.agents/skills/` (15 skills, a separate vendor-managed tree registered in `skills-lock.json` and symlinked live at `.claude/skills/`) already sets the field on its own `domain-driven-design` copy — untouched and unaudited here; a stale claim that conflated the two trees is corrected below.

| Skill | Group | Classification | Rationale |
|---|---|---|---|
| acquire-skills | brana | model-invoked | Hard-codes "never auto-install, always present and let the user choose" — worst case of autonomous firing is a search/listing, no state change. |
| backlog | brana | model-invoked | Core task-tracking primitive the work-start protocol depends on firing opportunistically; writes are scoped to `.claude/tasks.json`, routinely reversible. |
| bash-defensive-patterns | brana | model-invoked | Quarantined community skill, `allowed-tools: Read, Glob, Grep, AskUserQuestion` only — advisory, no write capability. |
| cargo-machete | brana | model-invoked | Edits `Cargo.toml` to drop unused deps — routine, git-reversible dev-loop cleanup. |
| do | brana | model-invoked | Thin router/alias to `backlog start`; no independent side effects of its own. |
| mcp-builder | brana | model-invoked | Local build/test/registration guidance for MCP servers — despite "deploy" in the description, no real publish step. |
| **plugin** | brana | **user-invoked-only** | Writes `~/.claude/plugins/known_marketplaces.json` / `installed_plugins.json` — a shared registry that decides what third-party code loads into every future session; installing untrusted marketplace code autonomously is a supply-chain risk. |
| reconcile | brana | model-invoked | Fixes detected drift, but scope is repo-local and git-reversible — explicitly routine hygiene per this file's own CLAUDE.md cross-reference. |
| rust-skills | brana | model-invoked | Not quarantined (`allowed-tools` includes Edit/Write), but scope is repo-local Rust source and git-reversible — model-invoked is still the right call, just not for the "quarantined advisory, no write" reason that applies to the rows below it. |
| verify-docs | brana | model-invoked | `allowed-tools: Bash, Read, AskUserQuestion` — no Write/Edit; runs `validate.sh` and samples for review only. |
| discover | core | model-invoked | Read-only catalog listing of skills/agents/hooks. |
| docs | core | model-invoked | Generates/updates doc files, git-reversible, explicitly a composable CLOSE building block. |
| sitrep | core | model-invoked | Read-only situational-awareness/status recovery. |
| align | execution | model-invoked | Restructures a project toward brana conventions — reversible dev-loop work with AskUserQuestion checkpoints. |
| build | execution | model-invoked | The unified dev/build command — foundational; must stay reachable autonomously for the dev loop to function. |
| claudemd | execution | model-invoked | Audits/generates a `CLAUDE.md`; single-file, git-reversible edit. |
| **client-retire** | execution | **user-invoked-only** | Archives a client's live knowledge base as historical — a one-shot, business-affecting action on real client data. |
| fix | execution | model-invoked | Structured, test-first bug-fix workflow — routine, reversible dev work. |
| gemini | execution | model-invoked | Delegates to the external Gemini API for research/boilerplate — real egress (repo content leaves the machine), but transient: agy never runs git, writes only to `/tmp/`, and creates no persistent external grant the way `gsheets`' `share` does. |
| **onboard** | execution | **user-invoked-only** | Scan mode alone would stay model-invoked (read-only diagnostics — safe to auto-fire on a new project). But `onboard` is one skill, one flag: its `new` flow runs `git init` + an initial commit outside this repo, optionally `gh repo create --push` (a live, external GitHub remote), and writes two shared cross-project registries (`~/.claude/memory/portfolio.md`, `~/.claude/tasks-portfolio.json`) — the same registry-mutation risk that flags `plugin`. The parameter-collecting `AskUserQuestion` calls in `new` aren't a final confirm gate. Flipping costs the scan-mode auto-fire convenience; kept as one flag rather than splitting the skill, since the risk lives entirely in `new` and that's the deliberate, rarer path. |
| **ship** | execution | **user-invoked-only** | Deploys code, publishes packages, releases to production — the canonical irreversible action (a published package or live deploy can't be cleanly un-shipped), even with an internal pre-deploy confirmation gate. |
| challenge | learning | model-invoked | Was user-invoked-only (the one pre-existing flag at audit time); flipped by operator decision 2026-08-29 (t-3228) — adversarial review is read-and-report with no state mutation beyond agent runs, and blocking model invocation prevented the delegation-routing table's own "big decision forming → /brana:challenge" trigger from firing. |
| memory | learning | model-invoked | `recall`/`pollinate`/`review` are read-and-report; pollinate surfaces cross-client patterns for the user to validate, doesn't write across client boundaries. |
| research | learning | model-invoked | Read/web-research + writes findings docs — safe, reversible, exactly the shape of skill the model should reach for opportunistically. |
| retrospective | learning | model-invoked | Writes a learning to the memory taxonomy — additive, low-stakes, encouraged to fire often. |
| close | session | model-invoked | End-of-session handoff/pattern extraction — safe, expected to fire routinely. |
| brainstorm | thinking | model-invoked | Idea exploration with Write/Edit scoped to notes/docs — low risk. |
| decide | thinking | model-invoked | Read-only decision-support synthesis. |
| grad-mechanism-design | thinking | model-invoked | Quarantined advisory skill, `Read/Glob/Grep/AskUserQuestion` only. |
| product-brainstorming | thinking | model-invoked | Ideation/thinking-partner skill, Write scoped to brainstorm output. |
| log | capture | model-invoked | Append-only event log — lowest-friction, explicitly designed for opportunistic capture. |
| design-system | domain | model-invoked | Quarantined advisory skill, `Read/Glob/Grep/AskUserQuestion` only. |
| domain-driven-design | domain | model-invoked | Quarantined advisory skill, `Read/Glob/Grep` only by design (no Write/WebFetch). |
| impeccable | domain | model-invoked | Quarantined advisory/critique skill, `Read/Glob/Grep/AskUserQuestion` only. |
| web-design-guidelines | domain | model-invoked | Read-only UI compliance review (`Read, Glob, Grep, Bash, WebFetch`), no write capability. |
| export-pdf | utility | model-invoked | Converts a local markdown file to PDF — local, reversible, no external effect. |
| **gsheets** | utility | **user-invoked-only** | Its `share <spreadsheet> <email>` action grants an arbitrary external address access to a spreadsheet that may hold sensitive business data — an internal confirm gate exists, but the decision to reach for external sharing at all should be user-initiated. |
| **meta-templates** | utility | **user-invoked-only** | `submit`/`appeal` push WhatsApp Business template changes into Meta's live review queue against a real client's WABA account — external, business-facing, not easily undone once submitted. |
| **scheduler** | utility | **user-invoked-only** | Modifies persistent systemd timers/cron automation and can immediately `run` a configured job (itself potentially invoking build/ship); `teardown` removes all timers at once — persistent system-level side effects outside the repo. |
| review | venture | model-invoked | Reads/aggregates metrics into a health-check report — no state mutation beyond report files. |

`system/skills/acquired/` (24 skills: community reasoning frameworks and stack-specific references — `caveman`, `cloud-run-basics`, `critical-thinking-logical-reasoning`, `decision-matrix`, `event-driven-architect`, `fastapi`, `first-principles`, `gcp-cloud-run`, `inversion`, `jobs-to-be-done`, `llm-evaluation`, `nextjs-patterns`, `pre-mortem`, `second-order-thinking`, `six-thinking-hats`, `supabase`, `supabase-postgres`, `supabase-skill`, `swot-analysis`, `systems-thinking`, `vercel-react`, `vitest`, `web-design`, `webhook-handler-patterns`) sit outside the `/brana:*` surface and were not classified — quarantine's read-only tool grant already covers the same risk this audit targets.

Not resurrecting the killed `mode: execute-only` proposal (`docs/ideas/drained/gentle-ai-adoption-ladder.md` Rung 3, killed at t-2591's Phase 0 measurement) — that was a different axis (executor-vs-orchestrator role). This audit only systematizes the invocation-mode axis `disable-model-invocation` already covers.

## Field Notes

### 2026-06-01: Skill retirement requires updating 10 locations in one commit
When retiring a skill, the full checklist: SKILL.md + procedure file (delete), skills.md row, guide/commands/index.md row, brana-cli.md row, component-index.md row, architecture feature docs, guide workflow docs, ideas/drained/skill-tiering.md row, scripts.md section (if has a script). Do all in one commit — leaving any behind creates a window where docs reference deleted files.
Source: notebooklm-source retirement / close session 2026-06-01 / t-1813

### 2026-06-01: Procedure preamble ToolSearch audit — grep, not positional extraction
brana procedures place the `<!-- ruflo preamble -->` / `ToolSearch(...)` block inside the document body (after `##` headings), not before the first heading. An audit script that extracts "pre-heading content" misses all ToolSearch declarations and reports false gaps for every procedure. Correct approach: `grep -n 'ToolSearch\|mcp__brana__' "$file"` and compare sets directly.
Source: E2026-06-01-2 preamble audit / close session 2026-06-01

### 2026-05-14: system/skills/memory/ naming collision with auto-memory store
`system/skills/memory/` (the memory skill dir) shares a path component with `~/.claude/projects/.../memory/` (the auto-memory store). At least one writer created `system/skills/memory/MEMORY.md` — a spurious auto-memory index that doesn't belong in the skill tree. Deleted as a stale artifact. Risk of recurrence: any tool that walks `system/skills/` looking for `memory/` subdirs could land here. Guard: pre-commit should reject `system/skills/**/MEMORY.md`.
Source: sitrep investigation / close session 2026-05-14

### 2026-05-14: MCP tools in allowed-tools are project-scoped — use CLI when procedure already calls it
`allowed-tools` grants permission but not availability. MCP servers are registered per-project (`.mcp.json`). A skill loaded globally via plugin that lists a project-scoped MCP tool (e.g. `mcp__brana__backlog_set`) will silently fail in any session where that server isn't running. Root cause of 22 `backlog_set` failures: `/brana:fix` ran in `proyecto_anita` where brana-mcp wasn't registered. Fix: if the procedure already uses the CLI equivalent, don't add the MCP tool to `allowed-tools` — it adds failure surface with zero benefit.
Source: fix/mcp-backlog-allowed-tools / close session 2026-05-14

### 2026-06-08: Pre-edit challenger review catches category-1 spec gaps before a procedure ships
Invoke `brana:challenger` on the procedure spec **before** opening any Edit tool call — this is the mandatory pre-edit gate. The adversarial read catches structural gaps (missing write paths, ambiguous guard conditions, undefined fallbacks) that the author is blind to because they hold context. Challenger caught the missing `skill_gap_checked` write path in build.md Step 0.5 before it was committed; without the review, the token would never have been written and Step 0.5 would loop on every `/brana:build` invocation. The fix cost at draft time is one agent call; the fix cost after shipping is a debrief errata cycle + confusion for anyone following the procedure literally.
Source: t-1903 / E2026-06-08-9 / close session 2026-06-08

### 2026-06-08: Guard conditions in shared procedures must use testable artifact checks, not intent labels
"Skip for freeform tasks" is ambiguous — different callers have different definitions of "freeform." Use observable artifact checks instead: "Skip when `task_id` is absent." The condition is binary, independent of caller intent, and stays correct even as the set of callers grows beyond the original use case. Applied: build.md Step 0.5 guard changed from "skip for freeform tasks" → "skip when no task_id". General rule: if a guard condition can be rephrased as "when artifact X is present/absent," do so.
Source: t-1903 challenger review / close session 2026-06-08

### 2026-08-17: CLAUDE.md is unconditionally off-limits to every tool, no bypass; generated reference docs route through their generator, not a hand edit
`system/hooks/feedback-gate.sh` + `lib/layer1-paths.sh` deny **every** Write/Edit whose path ends in `CLAUDE.md` — project or global, any depth — with no sentinel, no override flag, no exception for build/CLOSE. When a task's acceptance criteria ask for a pointer inside a CLAUDE.md file, the correct move is: don't attempt the edit, log the exact one-line addition to the task's `context` field, and let a human paste it via PR. Separately, `docs/reference/*.md` carries a do-not-edit banner because `brana reference generate` overwrites it — the fix for "this generated doc needs a new line" is editing the generator source (`system/cli/rust/crates/brana-cli/src/commands/reference.rs`), rebuilding (`cargo build --release -p brana-cli`), regenerating with the local binary, and verifying with `reference generate --check`. The system-installed `~/.local/bin/brana` won't reflect a generator change made in a worktree until it's rebuilt from that branch post-merge — `validate.sh`'s "reference docs out of date" check will correctly flag that lag until then; it's expected, not a defect.
Source: t-2831 build session 2026-08-17
