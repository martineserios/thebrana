# Skill Tiering — Core Plugin + On-Demand Procedures

> Brainstormed 2026-04-06. Status: idea.

## Problem

28 skills (351KB total) loaded at startup cause 4+ minute cold start. Diagnostic confirmed: removing skills/ makes CC fast; everything else (hooks, rules, agents, MCP) is fast. CC loads full SKILL.md content at startup (confirmed bug #14882), not just frontmatter. With 4-5 cold cache API calls at startup (#42906), this becomes ~350K tokens processed before the first message.

Only 7 skills are used daily. The other 19 are situational (weekly or less).

## Proposed solution

Split skills into 2 tiers:

- **Core tier (7 skills):** Full SKILL.md with complete procedures. Always loaded at startup.
- **Extended tier (19 skills):** 3-line stub SKILL.md (frontmatter + "read procedure"). Procedure body in `system/procedures/{name}.md`. Loaded on invoke via Read tool.

### Core skills (always loaded)

| Skill | Lines | Usage |
|-------|-------|-------|
| build | 1159 | Every implementation session |
| backlog | 954 | Every session (task management) |
| close | 700 | Every session end |
| research | 686 | Regular (deep dives) |
| brainstorm | 449 | Regular (idea maturation) |
| sitrep | 190 | Regular (context recovery) |
| do | 68 | Router (loads extended on demand) |
| **Total** | **4,206** | |

### Extended skills (stub + procedure file)

Each gets a stub SKILL.md (~15 lines: frontmatter + 1-line body) and a procedure file.

| Skill | Lines | Usage frequency |
|-------|-------|----------------|
| reconcile | 580 | Weekly |
| notebooklm-source | 436 | Rare |
| review | 363 | Monthly |
| onboard | 348 | Per new project |
| plugin | 268 | Rare |
| docs | 265 | Occasional (composable) |
| acquire-skills | 264 | Rare |
| align | 215 | Per new project |
| ship | 210 | Per deployment |
| memory | 208 | Occasional |
| log | 204 | Occasional |
| harvest | 188 | Occasional |
| gsheets | 169 | Rare |
| challenge | 158 | Occasional |
| retrospective | 98 | End of sessions |
| export-pdf | 84 | Rare |
| scheduler | 75 | Rare |
| client-retire | 53 | Rare |
| + 3 acquired | ~700 | Reference only |

### Stub format

```yaml
---
name: reconcile
description: "Unified maintenance — detect drift, security checks, cascade spec propagation, knowledge hygiene."
group: brana
keywords: [maintenance, drift, consistency, security]
allowed-tools: [Agent, AskUserQuestion, Bash, Edit, Glob, Grep, Read, Skill, Write]
status: stable
---
Read and execute the full procedure from `system/procedures/reconcile.md`.
```

### Directory structure

```
system/
├── skills/                          ← 7 core (full) + 19 extended (stubs)
│   ├── build/SKILL.md               full (1159 lines)
│   ├── backlog/SKILL.md             full (954 lines)
│   ├── close/SKILL.md               full (700 lines)
│   ├── research/SKILL.md            full (686 lines)
│   ├── brainstorm/SKILL.md          full (449 lines)
│   ├── sitrep/SKILL.md              full (190 lines)
│   ├── do/SKILL.md                  full (68 lines)
│   ├── reconcile/SKILL.md           stub (15 lines)
│   ├── review/SKILL.md              stub (15 lines)
│   └── ... (16 more stubs)
│
├── procedures/                      ← full procedure bodies for extended skills
│   ├── reconcile.md                 580 lines
│   ├── review.md                    363 lines
│   └── ... (16 more)
```

### How it works

1. CC discovers all 26 skills at startup. Core 7 load full content (~4.2K lines). Extended 19 load stubs (~285 lines total). **Total: ~4.5K lines vs. current 10K+ lines — ~55% reduction.**
2. User invokes `/brana:reconcile` → CC loads the 15-line stub → stub says "Read procedures/reconcile.md" → Claude reads the full procedure → executes it.
3. `/brana:do reconcile` also works — router reads the procedure file directly.
4. All 26 commands appear in the skill index and system-reminder.

### Why stubs, not just procedure files

- **Triggerable:** `/brana:reconcile` works as a direct slash command
- **Discoverable:** CC lists all 26 in the skill index
- **Routable:** frontmatter keywords enable `/brana:do` semantic matching
- **Forward-compatible:** If CC adds lazy loading (SkillSearch), stubs are already the right size
- **Open source friendly:** Users see all 26 commands, no UX degradation

## Research findings

- CC loads full SKILL.md content at startup, not frontmatter-only (anthropics/claude-code#14882)
- 4-5 API calls with cold cache at startup multiply the context cost (anthropics/claude-code#42906)
- Skill description budget is ~15,700 chars / 42 skills max (empirical testing)
- Large plugin ecosystems (248+ skills) use domain bundles for selective install
- SkillSearch (lazy loading for skills) requested but not implemented (#43816)
- Plugin + bootstrap.sh is the standard open source distribution pattern

## Risks (updated after challenger review)

| Risk | Severity | Mitigation |
|------|----------|-----------|
| **Path resolution from wrong CWD** | CRITICAL | Stubs must resolve procedure path relative to plugin root, not CWD. Use `Glob("**/procedures/{name}.md")` or instruct Claude to find the plugin root first. Test from a non-repo directory. |
| Stub instruction not followed (Claude treats stub as complete skill) | WARNING | Test 10+ invocations, especially with haiku model. Make instruction unambiguous: structured comment `<!-- PROCEDURE_FILE: procedures/{name}.md -->` + explicit Read instruction. |
| `depends_on` frontmatter pre-loads extended skills | LOW | `depends_on` is brana-custom, not CC-native. CC ignores it. No risk. |
| 3 acquired skills not in either tier | WARNING | Delete or move to brana-knowledge. Add explicit step to implementation. |
| 47% reduction may not be enough for <30s | WARNING | Test after implementing. If still slow, delete 9 rarest skills (observation #7) for additional 19% reduction. |
| Plan bundles 5 changes | WARNING | Ship tiering alone first (t-964 steps 1-5). Other changes are separate follow-up phases. |
| Bug #28660 re-injects skill catalog per tool call | INFO | Tiering reduces re-injection payload (7 full + 19 one-liners vs. 28 full). Partial mitigation. CC-side fix needed for full resolution. |

## Expected results (final — universal stubs, amended ADR-034)

| Metric | Before | After (measured) |
|--------|--------|-----------------|
| Skills loaded at startup | 28 (8,392 lines, ~34K tokens) | 25 stubs (762 lines, ~3K tokens) |
| Startup context reduction | — | **91% reduction** |
| Cold start | 4+ minutes | Working — acceptable speed |
| Available commands | 28 | 25 (same capability, all as stubs) |
| Procedure files | 0 | 28 in system/procedures/ |

### Binary search results (2026-04-06)

| Skills | Lines | Startup |
|--------|-------|---------|
| 0 | 0 | 3-4s |
| 3 stubs | 98 | ~5s |
| 5 stubs | 155 | 15-20s |
| 10 stubs | 317 | ~60s |
| 28 stubs | 762 | 4+ min |
| 25 stubs (current, after pruning) | ~650 | Acceptable |

> Note: Startup scaling is non-linear per skill count, not per line count. CC's overhead is per-skill registration (file discovery, frontmatter parsing, tool schema, system prompt injection). The universal stub model was adopted after testing showed core/extended split (47% line reduction) was insufficient.

## Operating Model Alignment

Analyzed against the brana operating model (6 jobs + auto-learning loop):

- **Core 7 cover daily loop:** DECIDE (backlog, brainstorm, do), UNDERSTAND (research), BUILD (build), SESSION (close, sitrep)
- **Extended 19 load when their job triggers:** MAINTAIN (reconcile via close), SHIP (ship), GROW (review, harvest), CAPTURE (log)
- **Auto-learning loop unaffected:** LOAD→EXTRACT→EVALUATE→PERSIST lives in procedure bodies, runs identically via stub→Read
- **Semantic routing preserved:** ruflo indexes skill frontmatter (name + description), stubs keep the same frontmatter. `/brana:do` routing unchanged.
- **Job composability works:** `Skill()` invocations load stubs lazily. build→research→onboard chains work.
- **Reconcile stays extended:** Called by close at session end (not startup). 200ms Read is negligible in a 30-60s close flow.

## Knowledge Indexing Decision

**Decision:** Index changed docs at `/brana:close` time, not per-commit.

- Commits happen 10-20x per session. Post-commit hooks compound.
- Close already runs `git diff` for drift detection — add `brana knowledge reindex --changed` to the same step.
- One batch reindex per session vs. 20 individual runs.
- Tradeoff: docs not searchable in ruflo until session close. Grep fallback covers same-session lookups.
- Weekly cron (Sunday 3am) is the safety net.

## CC Bug Findings

- Skills load full SKILL.md content at startup, not frontmatter-only (anthropics/claude-code#14882, confirmed on v2.1.89)
- 4-5 API calls with cold cache at startup multiply context cost (anthropics/claude-code#42906)
- Skills registered twice from plugins (anthropics/claude-code#27721)
- Skill catalog re-injected on every tool call (anthropics/claude-code#28660)
- SkillSearch (lazy loading) requested but not implemented (anthropics/claude-code#43816)
- Skill description budget: ~15,700 chars / 42 skills max

## Task-Aware Skill & Knowledge Loading

### Current mechanism

`/brana:backlog start` step 5 already does task-aware skill matching:
1. Search ruflo `namespace: "skills"` with task subject + tags
2. If match > 0.5: suggest the skill
3. If no match: offer marketplace search via `/brana:acquire-skills`

### Generalization: LOAD step searches skills namespace

Move skill matching from backlog start step 5 into the **shared LOAD step** (operating model). All thinking skills (build, research, brainstorm, review) already have LOAD. Adding `namespace: "skills"` to the search gives every thinking skill automatic access to matching procedures.

### Execute agents: knowledge injection

`/brana:backlog execute` spawns agents with task prompts but no ruflo knowledge. Enhancement:
- Before spawning each agent, `memory_search(query: task.subject + task.tags, namespace: "knowledge", limit: 3)`
- Include top results in the agent prompt
- Gives domain context without loading full skills (agents don't invoke skills — they do direct work)

### Acquired skills resolution

Current acquired skills (cargo-machete, rust-skills, mcp-builder) are reference docs, not workflows. Move to brana-knowledge dimensions or procedures. Future acquired skills from marketplace go to `procedures/` as extended stubs — same tiering pattern.

### /brana:acquire-skills audit (2026-04-06)

Concept is sound but implementation is stale. Broken:
- Install path: writes to `~/.claude/skills/` (dead) instead of `system/skills/acquired/`
- References `deploy.sh` (doesn't exist) and `docs/guide/skills.md` (doesn't exist)
- No frontmatter fixup — marketplace skills lack `group`, `status`, `allowed-tools`
- Quarantine references `/brana:audit` (absorbed into reconcile)
- No ruflo indexing after install — skill not searchable until next session

Working: tech detection, skills.sh CLI search, trust tier classification, safety scan.

Fix needed: update install path, add frontmatter fixup, index in ruflo after install, remove stale references. Should install to `system/procedures/` (extended tier) with a stub in `system/skills/`, not as a full SKILL.md in skills/acquired/.

### Just-in-time skill acquisition via LOAD step

LOAD step becomes the single entry point for skill discovery AND acquisition:

```
LOAD step (runs in every thinking skill):
  1. ruflo search namespace:"skills" → match?
     YES → Read matching procedure → continue
     NO  → "No local skill for {tech}. Search marketplace?"
           → npx skills search "{tech}" → candidates
           → User picks one
           → Download → save to procedures/ + stub in skills/
           → Frontmatter fixup + ruflo index
           → Read procedure into current context
           → Continue working — no restart needed
```

acquire-skills becomes a **composable function called by LOAD**, not a standalone skill. The user never invokes it directly — LOAD triggers it when a gap is detected. The skill stays as a stub for direct invocation (`/brana:acquire-skills cloudflare`) but the primary path is through LOAD.

### Unify start + do + execute

Merge `/brana:do` into `/brana:backlog start` — accept both task IDs and freeform text. One entry point for interactive work.

`/brana:backlog execute` stays separate (batch autonomous), but start auto-detects when a phase is batch-eligible:
- Phase has 3+ unblocked tasks AND avg effort <= M AND blocked_by density < 0.3
- → Offer: "This phase has N parallelizable tasks. Run as batch (execute) or interactive?"
- Smart router: one entry point, system evaluates the right mode

Both share LOAD-step knowledge injection (ruflo search by task metadata).

## Interaction Model: Claude Proposes, User Validates

**Principle:** Claude leads, user approves/redirects. Never "what should I do?" — always "I'm going to do X because Y. OK?"

Apply to all decision points:
- Strategy classification: "This looks like tech-debt. Confirm?"
- Skill matching: "Matched /brana:build (0.71). Starting as feature. Confirm?"
- Execute vs interactive: "Phase has 5 parallelizable S-effort tasks. Running as batch. Approve?"
- Stream/tags: "Tech-debt, tags: refactor, hooks. Confirm?"

AskUserQuestion options become **confirmation of a recommendation**. First option is always the recommended one. Open-ended choices are last resort (Level 3 in smart router).

Same 3-level escalation as the smart router:
1. **Auto-decide** — signal match is unambiguous, just do it (e.g., `stream: bugs` for a bug-tagged task)
2. **Propose + confirm** — LLM has a recommendation, present it as default option
3. **Ask** — genuinely ambiguous, present real choices (rare, <10% of decisions)

## Unified Start Flow

```
/brana:backlog start <id|text|phase-id>
```

**INTERACTIVE path** (single task, human-in-the-loop):
1. LOAD — ruflo search knowledge + skills namespace
2. If procedure matches → Read into context
3. Invoke /brana:build — Claude leads the build loop with user validation
4. May spawn helpers (scouts, test runners) — fire-and-forget subagents

**EXECUTE path** (batch, autonomous):
1. Build DAG waves from blocked_by
2. Spawn parallel agents per wave (one per task)
3. Each agent gets: task desc + context + LOAD knowledge injection
4. Agents work independently — no skills, raw prompts with knowledge
5. Main context collects results, writes back, reports

**Auto-detection:** Phase with 3+ unblocked tasks, avg effort <= M, low dependency density → propose execute. Otherwise → interactive.

### Testing the propose-first behavior

1. **Static (validate.sh):** Every AskUserQuestion in SKILL.md must have `(Recommended)` on the first option. Fail if any question lacks a default recommendation.
2. **Dynamic (close EXTRACT):** Count propose vs. ask-open-ended ratio per session. Target: >90% propose. Add as a session metric.
3. **Dry run:** Start a task, observe if Claude proposes or asks. Manual validation during implementation.

## Challenger Review (2026-04-06, Opus)

Flavor: Simplicity challenger. Verdict: PROCEED WITH CHANGES.

Findings incorporated above:
- CRITICAL: Path resolution from wrong CWD → fix in stub format
- CRITICAL: Token math corrected (47% not 83%)
- WARNING: Ship tiering alone, defer bundled changes
- WARNING: Test stub compliance especially with cheaper models
- OBSERVATION: Deleting 9 rarest skills is a simpler first step

## Next steps

**Phase 1 — Tiering (ship alone, t-964):**
1. Write ADR-034 for skill tiering decision
2. Delete or move 3 acquired skills (cargo-machete, rust-skills, mcp-builder)
3. Create `system/procedures/` directory
4. Move 19 extended skill bodies to procedure files
5. Replace 19 SKILL.md files with stubs (with path resolution fix)
6. Test cold start with tiered layout
7. Test stub→Read execution from non-repo CWD
8. Update docs (CLAUDE.md, architecture, getting-started)
9. File CC bug report with timing data (confirms #14882 on v2.1.89)

**Phase 2 — Follow-ups (separate tasks, after tiering proves out):**
- LOAD step generalization (search skills namespace)
- Just-in-time skill acquisition via LOAD
- Unify start + do + execute
- Propose-first enforcement
- Doc reindex at close time
- Execute agent knowledge injection
