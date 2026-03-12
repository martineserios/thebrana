# 24 — Roadmap Corrections & Errata

Errors and mismatches found during implementation. Each entry logs the finding, its impact, and the proposed fix. Status tracks resolution through the formal process.

**Status values:**
- `pending` — logged, not yet addressed
- `applied (date)` — spec fix applied by `/brana:apply-errata` or `/brana:maintain-specs`
- `code-fix` — fix lives in implementation code, not specs
- `informational` — no fix needed, awareness for implementers

**Workflow:** `/debrief` logs findings as `pending` → `/brana:apply-errata` processes them, marks `applied`, adds comments.

---

## Severity Summary

| # | Error | Severity | Status | Comments |
|---|---|---|---|---|
| 1 | Settings merge bug in deploy.sh | **High** | code-fix | Fixed in deploy.sh additive merge |
| 2 | Stop vs SessionEnd mismatch | **High** | applied (2026-02-10) | [Docs 08](reflections/08-diagnosis.md), 14, 17, 18 updated |
| 3 | Hook format not specified | **Medium** | informational | Roadmaps cross-ref [doc 09](dimensions/09-claude-code-native-features.md) |
| 4 | Event list incomplete | **Medium** | informational | PostToolUseFailure now in hooks |
| 5 | CLAUDE_ENV_FILE not in specs | **Low** | informational | Used in session-start.sh |
| 6 | Async hook limitations | **Low** | informational | Design-compatible |
| 7 | Context budget calc incomplete | **Low** | code-fix | Agent desc added to validate.sh |
| 8 | Roadmap docs missing [doc 00](00-user-practices.md) / user feedback loop | **Low** | applied (2026-02-10) | Already in both docs (17 line 327, 18 line 103) — missed during earlier review |
| 9 | claude-flow hooks recall/learn don't exist in v3 | **High** | applied (2026-02-10) | All 7 files fixed to memory API |
| 10 | [Doc 14](reflections/14-mastermind-architecture.md) doesn't acknowledge ReasoningBank alpha risk | **Medium** | applied (2026-02-10) | Blockquote caveat added |
| 11 | [Doc 14](reflections/14-mastermind-architecture.md) doesn't scope MCP tool surface | **Medium** | applied (2026-02-10) | Scope note in Context7 entry |
| 12 | [Doc 14](reflections/14-mastermind-architecture.md) background learning assumes daemon reliability | **Low** | applied (2026-02-10) | Note in open question #8 |
| 13 | `grep -c` + `|| echo 0` double output under `set -e` | **Medium** | code-fix | session-end.sh fixed, test covers it |
| 14 | `npx claude-flow` from `$HOME` downloads on every call | **Medium** | code-fix | Smart binary discovery in both hooks |
| 15 | claude-flow CLI debug output pollutes hook stdout | **Medium** | code-fix | stdout suppressed/filtered in hooks |
| 16 | Roadmaps don't schedule testing from [docs 22](dimensions/22-testing.md)/23 | **Low** | applied (2026-02-10) | Testing note + test scripts added to [docs 17](17-implementation-roadmap.md), 18; exit criteria updated |
| 17 | `memory search` preview truncates stored JSON values | **Medium** | code-fix | Tests use `memory retrieve` instead of search for verification |
| 18 | `memory retrieve` requires `--namespace` flag | **Low** | informational | Positional arg form also broken; must use `-k KEY --namespace NS` |
| 19 | [Doc 14](reflections/14-mastermind-architecture.md) conflates Context7 MCP with claude-flow scoping | **Medium** | applied (2026-02-10) | Split into two separate table rows |
| 20 | [Doc 08](reflections/08-diagnosis.md) doesn't mention native subagent `memory:` field | **Low** | informational | ReasoningBank still justified for semantic search; native `memory:` is simpler fallback |
| 21 | [Doc 14](reflections/14-mastermind-architecture.md) doesn't reference [doc 07](dimensions/07-claude-flow-plus-claude-4.6.md) or mention v3.1 Agent Teams hooks | **Medium** | applied (2026-02-10) | Team-level hooks section + [doc 07](dimensions/07-claude-flow-plus-claude-4.6.md) cross-ref added |
| 22 | [Doc 08](reflections/08-diagnosis.md) "essential hooks" list missing development discipline enforcement | **Medium** | applied (2026-02-10) | Added to essential list + PreToolUse caveat note |
| 23 | [Doc 08](reflections/08-diagnosis.md) open question #12 answered by [docs 11](dimensions/11-ecosystem-skills-plugins.md), 14, 22 | **Low** | applied (2026-02-10) | Resolved with hybrid answer + cross-refs |
| 24 | `validate.sh` frontmatter extraction matches all `---` lines | **Medium** | code-fix | awk-based first-block extraction |
| 25 | claude-flow sql.js dependency missing after upgrade | **Medium** | code-fix (2026-02-12) | Root cause: npx creates separate package cache. Fixed: direct binary in .mcp.json + deploy.sh auto-install |
| 26 | claude-flow alpha.34 breaks `-q` flag for `memory search` | **High** | code-fix (2026-02-12) | Global `-Q`/`--quiet` shadows `-q`. All 15 files fixed to `--query`. |
| 27 | [Doc 14](reflections/14-mastermind-architecture.md) skill templates use `npx claude-flow` anti-pattern | **Medium** | applied (2026-02-12) | Replaced with `$CF` + binary discovery preamble |
| 28 | [Doc 14](reflections/14-mastermind-architecture.md) ReasoningBank caveat missing sql.js post-install step | **Medium** | applied (2026-02-12) | sql.js install command added to caveat |
| 29 | `session-end.sh` fallback writes to global path instead of project-scoped | **Medium** | code-fix (2026-02-12) | Fallback `pending-learnings.md` now in `$LAYER0_DIR/` |
| 30 | enter/README.md document count off by one (32 vs 33) | **Low** | code-fix (2026-02-12) | Corrected to 34 when adding [doc 33](dimensions/33-research-methodology.md) |
| 31 | [Doc 08](reflections/08-diagnosis.md) missing triage entry for [doc 33](dimensions/33-research-methodology.md) | **Low** | applied (2026-02-12) | Cascade from [doc 33](dimensions/33-research-methodology.md) creation — triage verdict added |
| 32 | [Doc 14](reflections/14-mastermind-architecture.md) doesn't acknowledge /brana:research skill | **Low** | applied (2026-02-12) | Cascade from [doc 33](dimensions/33-research-methodology.md) — "Beyond the Six" subsection added |
| 33 | [Doc 32](reflections/32-lifecycle.md) missing source registry cadence in maintenance table | **Low** | applied (2026-02-12) | Cascade from [doc 33](dimensions/33-research-methodology.md) — row added to Connectome table |
| 34 | [Doc 05](dimensions/05-claude-flow-v3-analysis.md) version pinned at alpha.28 in opening paragraph | **High** | applied (2026-02-13) | Refresh cascade — alpha.34 already in Refresh Targets but not in prose |
| 35 | [Doc 10](dimensions/10-statusline-research.md) wrong repo URLs for ccstatusline and claude-powerline | **High** | applied (2026-02-13) | Refresh cascade — Versions table had wrong GitHub orgs, URLs section had correct ones |
| 36 | [Doc 11](dimensions/11-ecosystem-skills-plugins.md) stale ecosystem counts | **Medium** | applied (2026-02-13) | Refresh cascade — skills.sh 53,764→56,414, plugins 28→36, Trail of Bits 23→29 |
| 37 | [Doc 20](dimensions/20-anthropic-blog-findings.md) missing zero-day vulnerability discovery post | **Medium** | applied (2026-02-13) | Refresh cascade — Anthropic red team published 500+ 0-days finding (Feb 5, 2026) |
| 38 | [Doc 04](dimensions/04-claude-4.6-capabilities.md) context window misleading — 1M not default | **Medium** | applied (2026-02-13) | Refresh cascade — 200K default, 1M requires API beta header |
| 39 | [Doc 26](dimensions/26-git-branching-strategies.md) worktree recommendation contradicts implementation | **Low** | applied (2026-02-13) | Back-propagated: "Don't adopt yet" → "Adopted" after git-discipline.md updated |
| 40 | git-discipline.md exceeded context budget (4928 bytes) | **Medium** | reverted (2026-02-13) | Trim was applied then reversed — user decided full examples are worth the bytes. Budget raised 15,360→18,432 to accommodate. See erratum #41. |
| 41 | Context budget cap too conservative (15,360 bytes) | **Low** | code-fix (2026-02-13) | Research confirmed 15KB is <1% of 200K context window. Real pressure is MCP tool defs (30-67K tokens), not rules. Budget raised to 18,432 bytes in validate.sh. |
| 42 | [Doc 08](reflections/08-diagnosis.md) missing triage entry for [doc 34](dimensions/34-venture-operating-system.md) | **Low** | applied (2026-02-13) | Maintain-specs cascade — [doc 34](dimensions/34-venture-operating-system.md) (venture OS) added but never triaged in R1 |
| 43 | [Docs 08](reflections/08-diagnosis.md), 14 recommend Agent Teams despite experimental status | **High** | applied (2026-02-15) | Caveat added to [doc 08](reflections/08-diagnosis.md) (items 5, 6) + [doc 14](reflections/14-mastermind-architecture.md) (Pattern D) |
| 44 | [Doc 31](reflections/31-assurance.md) missing prompt injection testing for hooks | **High** | applied (2026-02-15) | Adversarial Input Validation section added to [doc 31](reflections/31-assurance.md) Structural Assurance |
| 45 | [Doc 31](reflections/31-assurance.md) missing instruction poisoning assurance | **High** | applied (2026-02-15) | Skill Instruction Quarantine section added to [doc 31](reflections/31-assurance.md) Behavioral Assurance |
| 46 | [Doc 32](reflections/32-lifecycle.md) missing Context Autopilot in lifecycle | **High** | applied (2026-02-15) | Context Autopilot + Notification hook note added to [doc 32](reflections/32-lifecycle.md) |
| 47 | [Doc 29](reflections/29-venture-management-reflection.md) /growth-check missing business model type detection | **High** | applied (2026-02-15) | Step 1 updated to include business model type detection |
| 48 | [Docs 08](reflections/08-diagnosis.md), 14 missing AGENTS.md invocation rate data | **Medium** | applied (2026-02-15) | 100%/79%/53% spectrum added to [doc 08](reflections/08-diagnosis.md) (item 1) + [doc 14](reflections/14-mastermind-architecture.md) (Pattern C) |
| 49 | [Doc 29](reflections/29-venture-management-reflection.md) /venture-align missing framework stacking warning | **Medium** | applied (2026-02-15) | Framework discipline paragraph added after /venture-align checklist |
| 50 | Venture skills have model detection but no non-SaaS metric tables | **High** | code-fix (2026-02-15) | Parallel metric tables, adapted AARRR, channel attribution, COGS check added to 4 skills |
| 51 | [Doc 14](reflections/14-mastermind-architecture.md) agent roster has swapped models (memory-curator / debrief-analyst) | **Medium** | applied (2026-02-16) | memory-curator Sonnet→Haiku, debrief-analyst Haiku→Sonnet |
| 52 | [Docs 14](reflections/14-mastermind-architecture.md), 31, 32 reference stale 15KB context budget (now 19KB) | **Low** | applied (2026-02-16) | Updated to ~19KB in all three docs. Note: [doc 14](reflections/14-mastermind-architecture.md) line 730 was missed (still said 15KB). |
| 53 | Context budget refs stale again after skill triggers (19KB → 21KB) | **Low** | applied (2026-02-17) | Back-propagated: [docs 14](reflections/14-mastermind-architecture.md), 31, 32 updated to ~21KB. Also fixed [doc 14](reflections/14-mastermind-architecture.md) line 730 missed by erratum #52. |
| 54 | Context budget refs stale again (21KB → 23KB) — 3rd consecutive session | **Low** | applied (2026-02-18) | Systemic pattern: every validate.sh budget change leaves docs behind. Fixed in backprop. See learnings #46. |
| 55 | [Doc 08](reflections/08-diagnosis.md) missing triage for [doc 35](dimensions/35-context-engineering-principles.md) + stale challenger model | **Medium** | applied (2026-02-18) | Maintain-specs cascade: [doc 35](dimensions/35-context-engineering-principles.md) triage added, "Sonnet" → "Opus" for challenger |
| 56 | [Doc 35](dimensions/35-context-engineering-principles.md) stale budget (21KB) and skill count (29) — same pattern as #54 | **Medium** | applied (2026-02-18) | Three refs: intro 21→23KB, decision tree 21→23KB, v0.5 row 29→31 skills |
| 57 | [Docs 14](reflections/14-mastermind-architecture.md), 31, 32 missing cross-refs to new [doc 35](dimensions/35-context-engineering-principles.md) | **Medium** | applied (2026-02-18) | Maintain-specs cascade: [doc 14](reflections/14-mastermind-architecture.md) context engineering xref, [doc 31](reflections/31-assurance.md) pre-commit + 35 failure modes, [doc 32](reflections/32-lifecycle.md) /usage in lifecycle |
| 58 | [Doc 14](reflections/14-mastermind-architecture.md) missing scheduler/automation architecture | **High** | applied (2026-02-20) | Maintain-specs cascade: "Scheduled Automation" section added after hooks |
| 59 | [Doc 32](reflections/32-lifecycle.md) missing scheduler in lifecycle maintenance | **Medium** | applied (2026-02-20) | Maintain-specs cascade: "Scheduled Automation" subsection added to Maintenance Cadences |
| 60 | Backlog #38 description stale — "personal side project" vs Personal Life OS | **Low** | applied (2026-02-20) | [Doc 30](30-backlog.md) item #38 updated + marked done |
| 61 | /personal-check journal check reports "no entries" when template file exists | **Low** | code-fix (2026-02-20) | Step 4 now distinguishes empty template from missing file |
| 62 | [Doc 35](dimensions/35-context-engineering-principles.md) instruction density warn threshold 200 vs actual 150 | **Medium** | applied (2026-02-20) | Backprop: missed by prior backprops when validate.sh added density check |
| 63 | [Doc 14](reflections/14-mastermind-architecture.md) skill count 31 vs actual 36 — 5th instance of count drift | **Low** | applied (2026-02-20) | Backprop: same systemic pattern as #52-54. Fixed alongside #62. |
| 64 | Bulk regex replacement breaks embedded code blocks | **Medium** | code-fix (2026-02-22) | Python regex expected standalone fenced blocks; 9 files had patterns inside larger blocks. Manual fix required. |
| 65 | Python frontmatter script dedup logic strips list items | **Medium** | code-fix (2026-02-22) | bulk-frontmatter.py dedup logic removed `  - dep` lines, leaving empty `depends_on:` in 8 skills. Second fix script needed. |
| 66 | Bash `declare -A` fails when env variable name conflicts | **Low** | code-fix (2026-02-22) | `GROUPS` conflicted with existing env var. Rewrote skill-graph.sh with embedded Python. |
| 67 | [Doc 14](reflections/14-mastermind-architecture.md) skill count 36 vs actual 33 after consolidation | **Low** | applied (2026-02-24) | Systemic count drift — same pattern as #52-54, #63. [Doc 14](reflections/14-mastermind-architecture.md) now shows 34, matching actual count (34 skills in thebrana/system/skills/). Self-corrected via subsequent backprop + skill additions. |
| 68 | Feature shipped without user-facing documentation | **Medium** | code-fix (2026-02-22) | Skills refactor (#44) merged with no human-readable guide. Caught by user. Fixed: docs/skills-system.md + mandatory doc step in build-feature/build-phase. |
| 69 | Deploy pipeline missing `commands/` artifact type | **Medium** | code-fix (2026-02-23) | `session-handoff`, `init-project` existed only in `~/.claude/commands/` with no source in `system/`. Violates "never edit ~/.claude/ directly" rule. |
| 70 | Pre-commit Check 3 can't parse doc number ranges in CLAUDE.md | **Medium** | code-fix (2026-02-23) | Fixed via backlog #66: Check 3 now uses Python range expansion to build a flat list of all referenced doc numbers before checking membership. |
| 71 | GITHUB_TOKEN can't bypass branch protection rulesets | **High** | informational | `github-actions[bot]` is not admin — RepositoryRole:5 bypass only covers human users/PATs. Tag+release-only semantic-release is the workaround. |
| 72 | `persist-credentials: false` contradicts semantic-release push | **Medium** | code-fix (2026-03-09) | Removed from release.yml. With tag-only mode (no commits to push) it's moot. |
| 71 | Lesson #36 over-broad — `bypassPermissions` agents CAN write cross-repo | **High** | applied (2026-02-24) | Lesson #36 annotated with supersession note pointing to lesson #68, which documents the nuanced rule: default-mode agents sandboxed by hooks, `bypassPermissions` agents bypass hooks entirely. |
| 72 | Portfolio tasks.json schema inconsistent across clients | **Low** | informational | Palco/somos/nexeye use bare `[{...}]` array. Tinyhomes/thebrana use `{"tasks": [...]}` wrapper. `/brana:backlog status --all` handles both via normalize step. Should standardize during next `/project-align` pass. |
| 73 | [Doc 08](reflections/08-diagnosis.md) missing triage for [docs 38](dimensions/38-design-thinking.md), 39 | **Medium** | applied (2026-02-25) | Maintain-specs cascade — two new dimension docs added without triage entries |
| 74 | [Doc 08](reflections/08-diagnosis.md) "PM Separation: preserve the pattern" contradicted by [doc 39](39-architecture-redesign.md) | **High** | applied (2026-02-25) | [Doc 39](39-architecture-redesign.md) supersedes with directory-based separation. Supersession note added to item 2. |
| 75 | [Doc 14](reflections/14-mastermind-architecture.md) missing cross-reference to [doc 39](39-architecture-redesign.md) | **Medium** | applied (2026-02-25) | Forward reference added with note that sections will need updating when migration phases execute |
| 76 | [Doc 14](reflections/14-mastermind-architecture.md) AgentDB presented without stalled status | **High** | applied (2026-02-25) | Last npm publish Jan 2, 2026. Fallback (embeddings + SQLite) is primary. Note added to Foundation Stack table. |
| 77 | [Doc 08](reflections/08-diagnosis.md) missing triage for 8 dimension docs (36-37, 39-Kapso, 40-44) | **High** | applied (2026-03-11) | Dimension docs added across multiple sessions without triage entries. Same pattern as #73. |
| 78 | [Doc 14](reflections/14-mastermind-architecture.md) skill count 24 vs actual 25, tasks/ path vs backlog/ | **Low** | applied (2026-03-11) | 6th instance of count drift (#52, #54, #63, #67, #78). Also: SONA trajectories → BM25 hybrid search. |
| 79 | [Doc 25](25-self-documentation.md) All Commands table references 10+ retired skill names | **High** | applied (2026-03-11) | /debrief, /session-handoff, /back-propagate, /refresh-knowledge, /build-phase, /build-feature, /morning, /weekly-review, /monthly-close, /monthly-plan all renamed. Full table + workflow examples rewritten. |
| 80 | [Doc 29](reflections/29-venture-management-reflection.md) "7 of 12 skills" framing with obsolete baseline | **Medium** | applied (2026-03-11) | System has 25 skills, not 12. Updated to "6 of 25". /decide and /debrief references also updated. |
| 81 | [Doc 14](reflections/14-mastermind-architecture.md) missing ADR-015 state sync layer | **High** | applied (2026-03-11) | New section "Operational State Sync (ADR-015)" added with 5 subcommands, hook-driven model, companion files, recovery. |
| 82 | [Doc 32](reflections/32-lifecycle.md) missing tactical-context feedback path | **High** | applied (2026-03-11) | Three feedback paths clarified: maintain-specs (document layer), tactical-context (execution layer), retrospective (knowledge layer). |
| 83 | [Doc 29](reflections/29-venture-management-reflection.md) missing state sync for machine recovery | **High** | applied (2026-03-11) | "State Transfer and Recovery" subsection added with push/pull/export/import workflow and team onboarding via snapshot. |
| 84 | [Doc 14](reflections/14-mastermind-architecture.md) hook responsibilities incomplete — missing sync additions | **Medium** | applied (2026-03-11) | SessionStart step 8 (fork push), SessionEnd steps 9-10 (snapshot + sync companions) added to hook sequences. |
| 85 | [ADR-015](architecture/decisions/ADR-015-state-consolidation-plugin-first.md) sync trigger matrix omits session-end push for global state | **Medium** | applied (2026-03-11) | Matrix listed session-end as MEMORY.md snapshot only. Reality: session-end now also pushes global state (event-log, portfolio, tasks). Matrix + "Why both?" paragraph updated. |
| 86 | [Doc 08](reflections/08-diagnosis.md) "SHA-512 embeddings" — factual error | **High** | applied (2026-03-11) | Should be "all-MiniLM-L6-v2 384-dim embeddings (local ONNX)". SHA-512 is a cryptographic hash, not an embedding model. |
| 87 | [Doc 08](reflections/08-diagnosis.md) missing triage entry for [doc 11](../../../brana-knowledge/dimensions/11-ecosystem-skills-plugins.md) | **High** | applied (2026-03-11) | Referenced 3x in body but skipped in triage section. Same pattern as #73, #77. |
| 88 | [Doc 08](reflections/08-diagnosis.md) missing triage entry for [doc 45](../../../brana-knowledge/dimensions/45-turboflow-agent-orchestration.md) | **Medium** | applied (2026-03-11) | New dimension doc from TurboFlow integration. Routine maintenance gap. |
| 89 | [Doc 08](reflections/08-diagnosis.md) "claude-flow is a hard constraint" — outdated framing | **Medium** | applied (2026-03-11) | Current arch: plugin + bootstrap independent, claude-flow is enhancement layer. Updated to "enhancement layer, not a hard dependency." |
| 90 | [Doc 08](reflections/08-diagnosis.md) "47 KB of modules" stale, doc 27 "5-phase" should be 6-phase | **Medium** | applied (2026-03-11) | System is ~26KB now. Doc 27 triage updated to 6-phase + `/brana:align`. |
| 91 | [Doc 08](reflections/08-diagnosis.md) `.claude/skills/` path should be `system/skills/` | **Medium** | applied (2026-03-11) | Plugin architecture uses system/skills/, not .claude/skills/. |
| 92 | [Doc 14](reflections/14-mastermind-architecture.md) rules count 12 vs actual 13 | **Medium** | applied (2026-03-11) | 7th instance of count drift. Updated both tree and prose to 13 with full list. |
| 93 | [Doc 32](reflections/32-lifecycle.md) `/project-onboard` and `/debrief` retired names | **High** | applied (2026-03-11) | Updated to `/brana:onboard` and `/brana:close`. Build cycle step 5 rewritten. |
| 94 | [Doc 32](reflections/32-lifecycle.md) `/usage-stats` doesn't exist, `deploy.sh` deprecated, `/morning` retired | **Medium** | applied (2026-03-11) | Token usage row rewritten. Deploy pipeline updated to plugin + bootstrap.sh. `/morning` → `/brana:review`. |

---

## Error 1: deploy.sh Settings Merge Bug

**Severity:** High — blocks Phase 2

**File:** `thebrana/deploy.sh` line 49

**Bug:** The merge command uses brana as base [0] and user as overlay [1]:

```bash
jq -s '.[0] * .[1]' "$SYSTEM_DIR/settings.json" "$TARGET_DIR/settings.json"
```

User's `hooks: {}` overwrites brana's hooks entirely because jq's `*` operator replaces objects at the same key — it doesn't merge nested keys additively.

**Impact:** When Phase 2 adds hooks to brana's `settings.json`, deploying would erase them. The user's existing `hooks: {}` wins and brana's hook configs vanish silently.

**Fix:** Merge hooks additively — brana hooks overlay user hooks, user wins for everything else:

```bash
jq -s '(.[0].hooks // {}) as $brana | (.[1].hooks // {}) as $user |
  .[0] * .[1] * {hooks: ($user * $brana)}' \
  "$SYSTEM_DIR/settings.json" "$TARGET_DIR/settings.json"
```

This ensures:
- Brana's hooks are always present after deploy (brana overlays user)
- User's non-hook settings take precedence (user overlays brana for everything else)
- User's custom hooks are preserved unless brana defines the same event

---

## Error 2: Stop vs SessionEnd Mismatch

**Severity:** High — changes hook architecture in [docs 14](reflections/14-mastermind-architecture.md), 17, 18

**Spec says:** "Three critical hooks: SessionStart, **Stop**, PostToolUse" — described as firing at session end to extract learnings.

**Reality:** Claude Code's `Stop` event fires after **every Claude response**, not at session end. There is a separate `SessionEnd` event that fires once on session termination.

**Impact:** Using `Stop` for learning extraction would fire dozens of times per session — massive overhead, repeated pattern storage, performance degradation.

**Correct mapping:**

| Spec concept | Correct Claude Code event | Why |
|---|---|---|
| "Session end learning" | `SessionEnd` | Fires once on termination, non-blocking |
| NOT | `Stop` | Fires every response — wrong granularity |

**Docs to update:** 14 (mastermind architecture), 17 (roadmap), 18 (lean roadmap) — all reference "Stop hook" for learning extraction.

---

## Error 3: Hook Format Not Specified in Roadmap Docs

**Severity:** Medium — implementation detail, [doc 09](dimensions/09-claude-code-native-features.md) covers it

**Gap:** [Docs 17](17-implementation-roadmap.md) and 18 describe what hooks should DO but never specify the actual JSON format for `settings.json`. The hook system has a specific nested structure:

```json
{
  "hooks": {
    "EventName": [
      {
        "matcher": "regex_pattern",
        "hooks": [
          {
            "type": "command",
            "command": "path/to/script",
            "async": true,
            "timeout": 600
          }
        ]
      }
    ]
  }
}
```

Key details missing from the roadmap specs:
- **Three hook types:** `command` (shell script), `prompt` (single LLM turn), `agent` (multi-turn LLM)
- **Exit code protocol:** 0 = success, 2 = block action, other = non-blocking error
- **Async constraint:** `async: true` only works for `type: "command"`
- **Stdin contract:** Receives JSON with session context, tool inputs, etc.
- **Output contract:** JSON with `hookSpecificOutput` containing event-specific fields

**Fix:** [Docs 17](17-implementation-roadmap.md) and 18 should cross-reference [doc 09](dimensions/09-claude-code-native-features.md) for hook technical details rather than duplicating them.

---

## Error 4: Full Hook Event List Not in Specs

**Severity:** Medium — missing opportunities, `PostToolUseFailure` is needed

**Gap:** Specs reference 3 hooks but Claude Code has 14 events. Several are relevant to brana's architecture:

| Event | Relevance to Brana | In Specs? |
|---|---|---|
| `SessionStart` | Recall patterns | Yes |
| `SessionEnd` | Store learnings | No (specs say "Stop") |
| `PostToolUse` | Notice outcomes | Yes |
| `PostToolUseFailure` | Notice failures (separate event!) | No |
| `PreToolUse` | Could guard dangerous commands | [Doc 09](dimensions/09-claude-code-native-features.md) only |
| `SubagentStop` | Could capture subagent learnings | No |
| `PreCompact` | Could extract knowledge before compaction | No |
| `UserPromptSubmit` | Could auto-trigger recall | No |

**Most critical miss:** `PostToolUseFailure` is a separate event from `PostToolUse`. Failures are often more valuable than successes for learning — they're where anti-patterns live. Phase 2 needs hook configs for both events.

---

## Error 5: SessionStart Can Set Environment Variables

**Severity:** Low — enhances design, doesn't block anything

**Discovery:** SessionStart hooks can write to `$CLAUDE_ENV_FILE` to set environment variables that persist across all subsequent Bash commands in the session.

**Not in specs:** This is useful for hooks coordination. The recall hook at `SessionStart` can set env vars like `BRANA_PROJECT` and `BRANA_SESSION_LOG` that downstream hooks (`PostToolUse`, `SessionEnd`) can read. Without this, each hook would need to re-detect the project on every invocation.

**Design implication:** The recall hook becomes the coordination point — it detects the project once and shares context via environment variables for the entire session.

---

## Error 6: Async Hook Limitations

**Severity:** Low — design constraint, already compatible with Phase 2 plans

**Discovery:** Async hooks (`"async": true`) cannot return:
- `decision` (block/allow actions)
- `permissionDecision` (override permissions)
- `continue: false` (stop processing)

They can only return `systemMessage` or `additionalContext`, delivered on the next turn.

**Impact on specs:** The `PostToolUse` notice hook MUST be async to avoid blocking Claude's work. This means it can only log and provide feedback — it cannot block or modify behavior. This aligns with Phase 2's design (notice hook observes, doesn't control), but the constraint should be explicit in the architecture.

---

## Error 7: Context Budget Calculation Incomplete

**Severity:** Low — small gap, grows with more agents

**Current:** `validate.sh` counts CLAUDE.md + rules + skill description lines.

**Missing:** Agent descriptions (the `description` field in agent YAML files) are also loaded into context. Currently only the scout agent exists with a short description, so the impact is minimal.

**Impact:** Will matter as more agents are added in later phases. The validation script should include agent description sizes in its budget calculation.

**Fix:** Add agent description line counting to `validate.sh`:

```bash
# Count agent description lines
AGENT_LINES=0
for agent_file in "$SYSTEM_DIR/agents/"*.md 2>/dev/null; do
  AGENT_LINES=$((AGENT_LINES + $(wc -l < "$agent_file")))
done
TOTAL=$((TOTAL + AGENT_LINES))
```

---

## Error 8: Roadmap Docs Missing [Doc 00](00-user-practices.md) / User Feedback Loop

**Severity:** Low — no phase blocked, but graduation pathway has no implementation step

**Gap:** [Doc 14](reflections/14-mastermind-architecture.md) (mastermind architecture) now declares the user feedback loop as part of the architecture — [doc 00](00-user-practices.md) captures field practices, and manual practices graduate to automated hooks/checks over time. [Doc 08](reflections/08-diagnosis.md) (diagnosis) says "manual practices are a signal for automation." But none of the roadmap docs (17, 18, 19) mention [doc 00](00-user-practices.md), user practices, or the graduation pathway.

**Impact:** Someone following either roadmap won't know to:
- Create [doc 00](00-user-practices.md) (or its equivalent) as part of project setup
- Establish the practice-to-automation graduation workflow
- Monitor [doc 00](00-user-practices.md) entries for clustering (repeated pain = automation signal)

**Fix:** Add [doc 00](00-user-practices.md) reference to Phase 1 setup steps in [docs 17](17-implementation-roadmap.md) and 18. The graduation workflow (manual practice → hook/check) is a Phase 2+ concern but should be mentioned as a design intent from Phase 1.

---

## Error 9: claude-flow `hooks recall`/`hooks learn` Don't Exist in v3

**Severity:** High — blocks Phase 1 completion and Phase 2 learning loop

**Discovery:** The hook scripts and 5 skill files reference `npx claude-flow hooks recall` and `npx claude-flow hooks learn`. These commands don't exist in claude-flow v3. The actual v3 API is:

| Spec command | Actual v3 command |
|---|---|
| `hooks recall --query "..."` | `memory search --query "..."` |
| `hooks learn --domain "..." --patterns "..."` | `memory store -k "key" -v "value" --namespace ns --tags "..."` |

**Files affected:**
- `system/hooks/session-start.sh` (line 31) — recall at session start
- `system/hooks/session-end.sh` (lines 51-57) — learn at session end
- `system/skills/pattern-recall/SKILL.md` — `hooks recall --query`
- `system/skills/retrospective/SKILL.md` — `hooks learn --patterns`
- `system/skills/cross-pollinate/SKILL.md` — `hooks recall --cross-client --query`
- `system/skills/project-onboard/SKILL.md` — `hooks recall --query`
- `system/skills/client-retire/SKILL.md` — `hooks recall --query`

**Additional issue:** Hook scripts ran `npx claude-flow` from the project CWD, but the global memory DB lives at `$HOME/.swarm/memory.db`. Commands must run from `$HOME` (via `cd "$HOME" &&`) for the global DB to be found.

**Fix:** Replace all `hooks recall`/`hooks learn` calls with `memory search`/`memory store`, and prefix with `cd "$HOME" &&` for portability.

---

## Error 10: [Doc 14](reflections/14-mastermind-architecture.md) Doesn't Acknowledge ReasoningBank Alpha Risk

**Severity:** Medium — doesn't block current work but affects implementation trust decisions

**Source:** [Doc 05](dimensions/05-claude-flow-v3-analysis.md) (claude-flow v3 analysis) vs [Doc 14](reflections/14-mastermind-architecture.md) (mastermind architecture)

**Gap:** [Doc 05](dimensions/05-claude-flow-v3-analysis.md) explicitly classifies SONA/ReasoningBank as alpha status (line 178-181) and recommends "Wait for Stability" before relying on SONA self-learning. [Doc 14](reflections/14-mastermind-architecture.md) builds the entire intelligence layer on ReasoningBank as a stable dependency without acknowledging this known limitation or proposing degraded-mode strategies inline.

**Impact:** An implementer following [doc 14](reflections/14-mastermind-architecture.md) alone would treat ReasoningBank as production-ready, missing the need for: error handling wrappers around every call, graceful degradation to Layer 0 (auto memory), and acceptance that early phases will have unreliable learning.

**Fix:** [Doc 14](reflections/14-mastermind-architecture.md) should note in the ReasoningBank sections that claude-flow is alpha and all calls must be wrapped with fallback to Layer 0. [Doc 14](reflections/14-mastermind-architecture.md) already has "Resolved Questions" noting "Accept the alpha risk" — but this caveat needs to be visible at the point of use, not just in a Q&A section.

**Docs to update:** 14 (inline caveat near ReasoningBank references)

---

## Error 11: [Doc 14](reflections/14-mastermind-architecture.md) Doesn't Scope MCP Tool Surface

**Severity:** Medium — affects Phase 1 plugin install decisions

**Source:** [Doc 05](dimensions/05-claude-flow-v3-analysis.md) (claude-flow v3 analysis) vs [Doc 14](reflections/14-mastermind-architecture.md) (mastermind architecture)

**Gap:** [Doc 05](dimensions/05-claude-flow-v3-analysis.md) explicitly recommends (line 186): "Skip... Full 170+ MCP tool surface (use only what's needed)." [Doc 14](reflections/14-mastermind-architecture.md) references available MCP tools without this caution, which could lead to installing the full tool surface when only a handful of commands are needed.

**Fix:** [Doc 14](reflections/14-mastermind-architecture.md)'s plugin/tool recommendations should explicitly state to use only the memory commands (`memory search`, `memory store`, `memory init`) and skip the broader MCP surface.

**Docs to update:** 14 (plugin recommendations section)

---

## Error 12: [Doc 14](reflections/14-mastermind-architecture.md) Background Learning Assumes Daemon Reliability

**Severity:** Low — affects "advanced ideas" section only, not current implementation

**Source:** [Doc 05](dimensions/05-claude-flow-v3-analysis.md) (claude-flow v3 analysis) vs [Doc 14](reflections/14-mastermind-architecture.md) (mastermind architecture)

**Gap:** [Doc 05](dimensions/05-claude-flow-v3-analysis.md) (line 180) flags the daemon system as needing reliability guarantees before use. [Doc 14](reflections/14-mastermind-architecture.md)'s "Advanced Ideas" section (open question #8: "Background learning — the night shift") proposes background workers that re-analyze old sessions, which depends on daemon stability that [doc 05](dimensions/05-claude-flow-v3-analysis.md) says isn't there.

**Fix:** [Doc 14](reflections/14-mastermind-architecture.md) should note that background learning is post-daemon-stabilization. The idea is sound but blocked by claude-flow alpha status.

**Docs to update:** 14 (open questions section)

---

## Error 13: `grep -c` + `|| echo 0` Produces Double Output Under `set -e`

**Severity:** Medium — caused session-end hook to crash with `jq: invalid JSON`

**Discovery:** `session-end.sh` had:
```bash
FAILURES=$(grep -c '"outcome":"failure"' "$SESSION_FILE" 2>/dev/null || echo 0)
```

When `grep -c` finds 0 matches, it outputs `0` AND exits with code 1. Under `set -e`, the `|| echo 0` fallback fires, producing `"0\n0"` (two lines). This broke `jq --argjson fail "$FAILURES"` downstream.

**Fix:** Use assignment-or pattern instead:
```bash
FAILURES=$(grep -c '"outcome":"failure"' "$SESSION_FILE" 2>/dev/null) || FAILURES=0
```

**Files affected:** `system/hooks/session-end.sh` (lines 32-33)

---

## Error 14: `npx claude-flow` from `$HOME` Downloads on Every Call

**Severity:** Medium — caused 5-second timeout in hooks, making claude-flow silently unreachable

**Discovery:** Hooks used `cd "$HOME" && npx claude-flow memory ...`. From `$HOME`, there's no local `node_modules` with claude-flow. `npx` attempts to download the package every time, which exceeds the hook timeout (5s) and silently falls back to Layer 0.

Meanwhile, claude-flow is globally installed via nvm at `$HOME/.nvm/versions/node/v20.19.0/bin/claude-flow` but not on `$PATH` in hook subprocess contexts.

**Fix:** Smart binary discovery — check nvm global bin first, then PATH, then npx as last resort:
```bash
CF=""
for candidate in "$HOME"/.nvm/versions/node/*/bin/claude-flow; do
    [ -x "$candidate" ] && CF="$candidate" && break
done
[ -z "$CF" ] && command -v claude-flow &>/dev/null && CF="claude-flow"
[ -z "$CF" ] && command -v npx &>/dev/null && CF="npx claude-flow"
```

**Files affected:** `system/hooks/session-start.sh`, `system/hooks/session-end.sh`

---

## Error 15: claude-flow CLI Debug Output Pollutes Hook Stdout

**Severity:** Medium — hook test caught this; hooks must output clean JSON

**Discovery:** After switching from `npx` to the direct binary, claude-flow's `[DEBUG]` and `[INFO]` lines went to stdout, mixing with the hook's `{"continue": true}` JSON output. Hook consumers expect pure JSON on stdout.

**Fix:**
- `session-end.sh`: redirect both stdout and stderr with `>/dev/null 2>&1` (we only need the exit code)
- `session-start.sh`: filter debug lines with `grep -v '^\['` (we need the search results but not the debug prefix)

**Files affected:** `system/hooks/session-start.sh`, `system/hooks/session-end.sh`

---

## Error 16: Roadmaps Don't Schedule Testing from [Docs 22](dimensions/22-testing.md)/23

**Severity:** Low — informational, no phase blocked

**Discovery:** [Docs 22](dimensions/22-testing.md) (testing) and 23 (evaluation) describe a 7-layer testing pyramid, BATS framework, Promptfoo eval config, and eval methodologies. [Docs 17](17-implementation-roadmap.md) and 18 (roadmaps) only mention record/playback and RAG metrics from these docs — the rest is never scheduled.

**Impact:** The gap is intentional (pain-driven: add tests as failures motivate them), but it should be documented as a conscious decision rather than an oversight. A basic 3-layer test suite was implemented: validate.sh (static), test-hooks.sh (smoke), test-memory.sh (round-trip).

**Files affected:** [Docs 17](17-implementation-roadmap.md), 18 (informational — no change needed if pain-driven approach is accepted)

---

## Error 17: `memory search` Preview Truncates Stored JSON Values

**Severity:** Medium — caused Phase 2 metadata tests to fail on first run

**Discovery:** `claude-flow memory search --query "..."` returns results with a `preview` field that truncates stored values after ~50 characters:

```json
{"preview": "{\"project\":\"thebrana\",\"session\":\"e76be094-9600-4415-90f3-4d9..."}
```

Phase 2's session-end stores quarantine metadata (`confidence`, `transferable`, `recall_count`) at the END of the JSON object. The preview cuts off before reaching those fields. Tests that grep search results for `"confidence"` or `"recall_count"` always fail.

**Fix:** Use `memory retrieve -k KEY --namespace NS --format json` instead. The response includes a `content` field with the full, untruncated stored value:

```json
{"content": "{\"project\":\"thebrana\",...,\"confidence\":0.5,\"recall_count\":0}"}
```

**Files affected:** `thebrana/test-hooks.sh`, `thebrana/test-memory.sh` — both updated to use `retrieve` instead of `search` for field verification.

---

## Error 18: `memory retrieve` Requires `--namespace` Flag

**Severity:** Low — informational, discovered while fixing error #17

**Discovery:** `claude-flow memory retrieve -k "key"` without `--namespace` returns "Key not found" even when the key exists. The namespace scopes the lookup and is required for retrieval (even though it's not required for search).

Additionally, the positional form `memory retrieve KEY` (without `-k`) also fails — must use the flag form `-k KEY`.

**Working syntax:** `memory retrieve -k KEY --namespace NS --format json`

**Impact:** Skills and documentation that reference `memory retrieve` must include the namespace. The `--format json` flag is needed to get machine-parseable output (default is a table).

---

## Error 19: [Doc 14](reflections/14-mastermind-architecture.md) Conflates Context7 MCP with Claude-Flow Scoping

**Severity:** Medium — causes confusion about which tool does what

**Discovery:** [Doc 14](reflections/14-mastermind-architecture.md) line 483 (Plugin & Skill Recommendations table) had a single row that combined two unrelated tools:

> **Context7 MCP** (Upstash) — Real-time library docs — the mastermind always has current knowledge. **Scope:** use only the memory commands (`memory search`, `memory store`, `memory init`) from claude-flow's 170+ MCP tool surface...

Context7 is an Upstash MCP server for fetching real-time, version-specific library documentation. The "Scope" note about `memory search/store/init` is about claude-flow's MCP surface. These are completely different tools that got merged into one table row.

**Fix:** Split into two rows — Context7 for library docs, claude-flow for memory commands.

**Files affected:** `14-mastermind-architecture.md` (line 483)

---

## Error 20: [Doc 08](reflections/08-diagnosis.md) Doesn't Mention Native Subagent `memory:` Field

**Severity:** Low — informational, doesn't change the architecture

**Discovery:** [Doc 09](dimensions/09-claude-code-native-features.md) (lines 464-487, 739, 1175) documents a native `memory:` field on custom subagents with three scopes (`user`, `project`, `local`). [Doc 09](dimensions/09-claude-code-native-features.md) even maps: "ReasoningBank (claude-flow) → Subagent `memory: user` field."

[Doc 08](reflections/08-diagnosis.md) recommends ReasoningBank as "#1 value-add" (line 108) without mentioning this native alternative exists.

**Impact:** Low — ReasoningBank provides semantic search with SHA-512 embeddings, tags, namespaces, and cross-client queries that native `memory:` doesn't offer. The recommendation is still valid. But [doc 08](reflections/08-diagnosis.md) should acknowledge native `memory:` as a simpler fallback (which is what the implementation already does as Layer 0).

**No fix needed** — the implementation handles this correctly. Logged for awareness.

---

## Error 21: [Doc 14](reflections/14-mastermind-architecture.md) Doesn't Reference [Doc 07](dimensions/07-claude-flow-plus-claude-4.6.md) or Mention v3.1 Agent Teams Hooks

**Severity:** Medium — doesn't block current work but hook architecture is incomplete

**Source:** [Doc 07](dimensions/07-claude-flow-plus-claude-4.6.md) (v3.1 update) vs [Doc 14](reflections/14-mastermind-architecture.md) (mastermind architecture)

**Gap:** [Doc 07](dimensions/07-claude-flow-plus-claude-4.6.md)'s v3.1 update confirms two new Claude Code hook events are real and shipped in claude-flow v3.1.0-alpha.28:

- **TeammateIdle** — fires when a teammate goes idle; claude-flow's `teammate-idle` hook auto-assigns pending work
- **TaskCompleted** — fires on task completion; claude-flow's `task-completed` hook trains patterns from successful tasks

[Doc 14](reflections/14-mastermind-architecture.md)'s "Hooks That Make the Brain Work" section (lines 122-181) describes three core hooks (SessionStart, SessionEnd, PostToolUse/PostToolUseFailure) but doesn't mention these team-level hooks. [Doc 14](reflections/14-mastermind-architecture.md) has no cross-reference to [doc 07](dimensions/07-claude-flow-plus-claude-4.6.md) anywhere.

**Impact:** An implementer following [doc 14](reflections/14-mastermind-architecture.md) alone would build a 3-hook learning system without knowing that v3.1 adds team-aware hooks that extend the learning loop to multi-agent workflows. When teams are used, individual teammate sessions fire their own SessionStart/SessionEnd — but the team-level coordination (which teammate gets what task, which completions trigger pattern training) requires the v3.1 hooks.

**Fix:** Add cross-reference to [doc 07](dimensions/07-claude-flow-plus-claude-4.6.md) in [doc 14](reflections/14-mastermind-architecture.md)'s hook section. Note TeammateIdle and TaskCompleted as optional extensions to the 3-hook core, relevant when using Agent Teams.

**Docs to update:** 14 (hook architecture section, plugin recommendations)

---

## Error 22: [Doc 08](reflections/08-diagnosis.md) "Essential Hooks" List Missing Development Discipline Enforcement

**Severity:** Medium — could cause implementer to skip the enforcement hook

**Source:** [Doc 11](dimensions/11-ecosystem-skills-plugins.md) (SDD/TDD enforcement tools) + [Doc 14](reflections/14-mastermind-architecture.md) (Project Enforcement) vs [Doc 08](reflections/08-diagnosis.md) (Diagnosis)

**Gap:** [Doc 08](reflections/08-diagnosis.md) line 32 recommends: "Strip down to essential hooks only (crash recovery, branch protection, session tracking)." This list was written before [doc 11](dimensions/11-ecosystem-skills-plugins.md)'s SDD/TDD enforcement tools research. Now that [doc 14](reflections/14-mastermind-architecture.md) establishes PreToolUse as the enforcement gate for spec-before-code discipline, "development discipline enforcement" belongs in the essential hooks list.

Additionally, [doc 08](reflections/08-diagnosis.md) line 98-99 says "Custom PreToolUse hooks for git commands add latency without adding safety" (specifically about branch protection). While correct for that use case, an implementer might over-generalize this to all PreToolUse hooks and skip the SDD enforcement hook that [doc 14](reflections/14-mastermind-architecture.md) establishes as essential.

**Fix:** Add "development discipline enforcement" to [doc 08](reflections/08-diagnosis.md)'s essential hooks list (line 32). Add a note to the "Custom Branch Protection Hooks" entry (line 98-99) distinguishing branch protection PreToolUse (drop) from SDD enforcement PreToolUse (keep, see [doc 14](reflections/14-mastermind-architecture.md)).

**Docs to update:** 08 (hook lifecycle, custom branch protection)

---

## Error 23: [Doc 08](reflections/08-diagnosis.md) Open Question #12 Answered by [Docs 11](dimensions/11-ecosystem-skills-plugins.md), 14, 22

**Severity:** Low — doesn't block implementation but misleads by presenting a resolved question as open

**Gap:** [Doc 08](reflections/08-diagnosis.md) line 212 asks: "Native Agent Teams or claude-flow swarms for coordination? Or a hybrid where native teams handle execution and claude-flow handles memory/learning?"

This is now answered:
- [Doc 14](reflections/14-mastermind-architecture.md) "Project Enforcement" establishes: Native Agent Teams for execution, claude-flow for memory/learning (the hybrid option)
- [Doc 22](dimensions/22-testing.md) "Multi-Agent TDD" provides the first concrete team pattern: separate test-writer and implementer agents with tool-scoped isolation
- [Doc 11](dimensions/11-ecosystem-skills-plugins.md) section 5 catalogs the multi-agent context isolation pattern as "worth borrowing"

**Fix:** Move question #12 from "Open Questions" to "Resolved Questions" with the answer: hybrid — native Agent Teams for execution coordination, claude-flow ReasoningBank for cross-session memory. First concrete pattern: multi-agent TDD (see [docs 14](reflections/14-mastermind-architecture.md), 22).

**Docs to update:** 08 (open questions section)

---

## Error 24: `validate.sh` Frontmatter Extraction Matches All `---` Lines

**Severity:** Medium — blocks deployment of any skill with markdown horizontal rules

**Discovery:** `validate.sh` used `sed -n '/^---$/,/^---$/p'` to extract YAML frontmatter. This pattern matches ALL pairs of `---` lines in the file, not just the first two. Skills that use `---` as markdown section separators (horizontal rules) produced multi-document YAML output, which python's `yaml.safe_load()` rejected with "expected a single document in the stream."

**Impact:** All 5 venture skills and `/project-align` failed validation, blocking deployment. Existing skills happened to only have 2 `---` lines (the frontmatter delimiters) and were never affected.

**Fix:** Replace `sed` with awk-based extraction that stops at the first closing `---`:
```bash
frontmatter=$(awk 'NR==1 && /^---$/{in_fm=1; next} in_fm && /^---$/{exit} in_fm{print}' "$skill_file")
```

**Files affected:** `thebrana/validate.sh` (skill, rule, and agent frontmatter extraction — 3 locations)

---

## Error 25: claude-flow sql.js Dependency Missing After Upgrade

**Severity:** Medium — ReasoningBank completely non-functional

**Discovery:** Both MCP (`mcp__claude-flow__memory_store`) and CLI (`claude-flow memory store`) fail with: "Cannot find package 'sql.js' imported from .../memory-initializer.js". sql.js is dynamically imported (19+ call sites in `memory-initializer.js`) but never declared in any `package.json`. Every `npm install -g claude-flow` leaves it missing.

**Root cause (discovered 2026-02-12):** When `.mcp.json` uses `npx claude-flow@version`, npx creates a **separate** package cache (`~/.npm/_npx/{hash}/`) from the global install (`~/.nvm/.../lib/node_modules/claude-flow/`). sql.js must be installed in **both** locations independently. Fixing one leaves the other broken.

**Impact:** All ReasoningBank operations fail. The system falls back to Layer 0 (auto memory files), which works but loses semantic search, tagging, and cross-client queries.

**Fix (root):** Eliminate the dual-path problem entirely:
1. Point `.mcp.json` to the global binary directly (not npx): `"command": "/home/.../.nvm/versions/node/v20.19.0/bin/claude-flow"`
2. `deploy.sh` auto-installs sql.js in the global package dir on every deploy
3. One binary, one package dir, one place to fix

**Status:** code-fix (2026-02-12) — `.mcp.json` files updated across 3 projects, `deploy.sh` ensures sql.js on deploy.

**Relevance:** Validates lesson #3 ("Database schema drift breaks things silently") — dependency drift is the same class of problem. See also lesson #17 (npx anti-pattern).

---

## Error 26: claude-flow alpha.34 Breaks `-q` Flag for `memory search`

**Severity:** High — silently breaks all memory search operations across hooks and skills

**Discovery:** Upgrading from alpha.28 to alpha.34, `memory search -q "query"` fails with "Required option missing: --query". The alpha.34 release added global `-Q`/`--quiet` flag, which shadows the `-q` shorthand that `memory search` previously used for `--query`. The `--help` text still shows `-q` in examples, making this doubly confusing.

**Impact:** Every hook and skill that calls `memory search -q` silently fails (returns empty or errors). The session-start recall hook, pattern-recall, retrospective, cross-pollinate, project-onboard, client-retire, build-phase, venture-onboard, venture-phase, growth-check, and test-memory.sh — all broken. 15 files total across implementation and spec docs.

**Fix:** Replace all `-q` with `--query` in every file that calls `memory search`:
```bash
# Before (alpha.28)
$CF memory search -q "client:$PROJECT" --format json

# After (alpha.34)
$CF memory search --query "client:$PROJECT" --format json
```

**Files affected:** 11 in thebrana (1 hook, 9 skills, 1 test), 4 spec docs (07, 14, 17, 18, 24).

**Lesson:** This is the same class of problem as error #9 (API changes between versions). Pin versions in production and test after upgrades. The `-q` → `--query` change was undocumented — no changelog exists for the 3.1.0-alpha series.

---

## Error 27: [Doc 14](reflections/14-mastermind-architecture.md) Skill Templates Use `npx claude-flow` Anti-Pattern

**Severity:** Medium — implemented skills would be slow or broken

**Discovery:** `/brana:maintain-specs` cycle found [doc 14](reflections/14-mastermind-architecture.md) lines 311, 336, 372 use `cd $HOME && npx claude-flow memory search/store`, the exact anti-pattern documented in lesson #17. The implemented skills (thebrana) already use smart binary discovery, but the spec doc still shows the old pattern.

**Impact:** Anyone implementing skills from [doc 14](reflections/14-mastermind-architecture.md)'s templates would create hooks/skills that: (a) download claude-flow on every invocation (~10s, exceeding hook timeouts), (b) use a separate npx cache missing sql.js, (c) potentially run a different version than the CLI.

**Fix:** Replace `npx claude-flow` with `$CF` (smart binary discovery variable) and add a binary discovery preamble above the skill templates section.

**Files affected:** `14-mastermind-architecture.md` lines 311, 336, 372

**Status:** applied (2026-02-12) — `$CF` variable + discovery preamble added

---

## Error 28: [Doc 14](reflections/14-mastermind-architecture.md) ReasoningBank Caveat Missing sql.js Post-Install Step

**Severity:** Medium — ReasoningBank silently non-functional after upgrade

**Discovery:** `/brana:maintain-specs` cycle found [doc 14](reflections/14-mastermind-architecture.md) line 215 says "pin your version and run `memory init --force` after upgrades" but omits the sql.js installation step. An implementer would upgrade, run `memory init --force`, and still have a broken ReasoningBank because sql.js was never declared as a dependency.

**Impact:** All memory store/search operations fail silently. Layer 0 fallback masks the failure — the system appears to work but ReasoningBank provides zero value.

**Fix:** Add sql.js install command to the alpha caveat.

**Files affected:** `14-mastermind-architecture.md` line 215

**Status:** applied (2026-02-12) — sql.js install step added to caveat

---

## Error 29: `session-end.sh` Fallback Writes to Global Path Instead of Project-Scoped

**Severity:** Medium — data isolation violation, not blocking

**Discovery:** The CLAUDE.md vs MEMORY.md framework audit revealed that `session-end.sh`'s Layer 1 fallback (when claude-flow is unavailable) wrote to `~/.claude/memory/pending-learnings.md` — a global file. Meanwhile, the primary path (Layer 1) stored data in project-namespaced keys. The fallback broke project scoping.

**Files affected:** `thebrana/system/hooks/session-end.sh` (lines 76-87)

**Fix:** Moved Layer 0 directory discovery above the fallback write. Fallback now writes to `$LAYER0_DIR/pending-learnings.md` (project auto-memory directory) instead of the global path. Fallback only fires if the project directory is found.

**Status:** code-fix (2026-02-12)

---

## Error 30: enter/README.md Document Count Off by One

**Severity:** Low — cosmetic, no implementation impact

**Discovery:** README.md Status section said "32 documents total" but [docs 00](00-user-practices.md)-32 = 33 documents (inclusive count). The count was likely set when [doc 00](00-user-practices.md) was added but the total wasn't incremented.

**Impact:** None — no spec or implementation decision depended on this count.

**Fix:** Corrected to 34 during the [doc 33](dimensions/33-research-methodology.md) addition session.

**Status:** code-fix (2026-02-12)

---

## Error 43: [Docs 08](reflections/08-diagnosis.md), 14 Recommend Agent Teams Despite Experimental Status

**Severity:** High — could lead to adopting unstable feature for production use

**Discovery:** /brana:maintain-specs re-evaluate-reflections (2026-02-15). [Doc 08](reflections/08-diagnosis.md) says "Replace with: Native Agent Teams." [Doc 14](reflections/14-mastermind-architecture.md) underexplores Teams as an architecture option. But [doc 09](dimensions/09-claude-code-native-features.md) shows Agent Teams are experimental (disabled by default, `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`), 2x token cost (~800k vs ~440k for 3-worker team), no file locking (last-write-wins), no resumption for in-process teammates.

**Fix:** Add caveat to [docs 08](reflections/08-diagnosis.md) and 14: "Agent Teams remain experimental as of Feb 2026. Use subagents for production patterns; escalate to Teams only for genuinely parallel multi-file work where coordination benefits outweigh 2x token cost and experimental status."

**Docs to update:** 08, 14

**Status:** applied (2026-02-15)

---

## Error 44: [Doc 31](reflections/31-assurance.md) Missing Prompt Injection Testing for Hooks

**Severity:** High — security gap in assurance framework

**Discovery:** /brana:maintain-specs re-evaluate-reflections (2026-02-15). [Doc 31](reflections/31-assurance.md) validates hook syntax (`bash -n`) and tests learning loop round-trips, but never tests adversarial input payloads. Hooks process JSON from tool calls — without adversarial testing, shell metacharacters, escape sequences, or injection payloads could pass through. [Doc 22](dimensions/22-testing.md) identifies "Instruction poisoning incidents: 0 promoted" as a critical safety metric and recommends Promptfoo red team plugins.

**Fix:** Add "Adversarial Input Validation" section to [doc 31](reflections/31-assurance.md)'s Behavioral Assurance: test hooks with payloads containing shell metacharacters, deeply nested JSON, and escape sequences. Reference Promptfoo red team plugins (doc 22).

**Docs to update:** 31

**Status:** applied (2026-02-15)

---

## Error 45: [Doc 31](reflections/31-assurance.md) Missing Instruction Poisoning Assurance

**Severity:** High — external skills can override safety rules undetected

**Discovery:** /brana:maintain-specs re-evaluate-reflections (2026-02-15). [Doc 16](dimensions/16-knowledge-health.md) identifies Vector 8: "When a skill is installed from an external source, its SKILL.md content becomes part of Claude's instructions. A malicious or poorly written skill could override safety rules." [Doc 31](reflections/31-assurance.md) covers pattern quarantine (knowledge entering ReasoningBank) but has zero assurance for skill instruction quarantine (instructions entering the context).

**Fix:** Add "Skill Instruction Quarantine" section to [doc 31](reflections/31-assurance.md) after quarantine behavior tests. Verify external skills enter quarantine before deployment, SKILL.md content doesn't override CLAUDE.md or rules, conflicts are flagged. Reference [doc 12](dimensions/12-skill-selector.md)'s three-tier trust model.

**Docs to update:** 31

**Status:** applied (2026-02-15)

---

## Error 46: [Doc 32](reflections/32-lifecycle.md) Missing Context Autopilot in Lifecycle

**Severity:** High — could lead to implementing manual context strategies redundantly

**Discovery:** /brana:maintain-specs re-evaluate-reflections (2026-02-15). [Doc 32](reflections/32-lifecycle.md)'s "Keeping Sessions Healthy" section describes three context management strategies (compaction, structured note-taking, sub-agent architectures) but doesn't mention Context Autopilot — a native Claude Code feature that auto-manages the context window. Also misses the Notification hook type (`permission_prompt`, `idle_prompt`, `auth_success`).

**Fix:** Update [doc 32](reflections/32-lifecycle.md)'s context management section to acknowledge Context Autopilot and clarify which manual strategies remain relevant when Autopilot is enabled. Add Notification hook type to the hook lifecycle discussion.

**Docs to update:** 32

**Status:** applied (2026-02-15)

---

## Error 47: [Doc 29](reflections/29-venture-management-reflection.md) /growth-check Missing Business Model Type Detection

**Severity:** High — could cause health misdiagnosis for non-SaaS ventures

**Discovery:** /brana:maintain-specs re-evaluate-reflections (2026-02-15). [Doc 28](dimensions/28-startup-smb-management.md) lesson #20: "Metric frameworks must adapt to business model type. A cycle-based service with 95% 'churn' looks catastrophic in SaaS terms but is normal." [Doc 29](reflections/29-venture-management-reflection.md)'s `/growth-check` detects stage but not business model type, applying SaaS-centric metrics to all ventures.

**Fix:** Update [doc 29](reflections/29-venture-management-reflection.md) `/growth-check` Step 1 from "Detect stage" to "Detect stage AND business model type (subscription, cycle/project, marketplace, consulting, service)." Move the existing business model adaptation note from afterthought into core logic.

**Docs to update:** 29

**Status:** applied (2026-02-15)

---

## Error 48: [Docs 08](reflections/08-diagnosis.md), 14 Missing AGENTS.md Invocation Rate Data

**Severity:** Medium — affects optimal knowledge architecture split

**Discovery:** /brana:maintain-specs re-evaluate-reflections (2026-02-15). Vercel's evaluations (doc 11) show static markdown (AGENTS.md) achieves 100% invocation vs 53% for default skills, 79% with explicit "Use when..." descriptions. This data changes the optimal split between always-in-context CLAUDE.md and lazy-loaded skills. [Doc 08](reflections/08-diagnosis.md)'s triage and [doc 14](reflections/14-mastermind-architecture.md)'s architecture don't cite this empirical finding.

**Fix:** [Doc 08](reflections/08-diagnosis.md): update "Proven Patterns Worth Preserving" CLAUDE.md entry to cite 100% vs 79% vs 53% spectrum. [Doc 14](reflections/14-mastermind-architecture.md): expand Pattern C to reference Vercel's finding and clarify that passive context beats skill retrieval for always-needed knowledge.

**Docs to update:** 08, 14

**Status:** applied (2026-02-15)

---

## Error 49: [Doc 29](reflections/29-venture-management-reflection.md) /venture-align Missing Framework Stacking Warning

**Severity:** Medium — common early-stage failure mode not prevented

**Discovery:** /brana:maintain-specs re-evaluate-reflections (2026-02-15). [Doc 28](dimensions/28-startup-smb-management.md) resolved question #2 with explicit guidance: "Layer, don't stack. Maximum 3 active layers. Don't run EOS Rocks + OKRs as parallel systems — Rocks already ARE quarterly goals." [Doc 29](reflections/29-venture-management-reflection.md)'s `/venture-align` creates OKRs and meeting cadences but never warns against framework stacking.

**Fix:** Add "Framework Discipline" paragraph to [doc 29](reflections/29-venture-management-reflection.md)'s `/venture-align` section: maximum 3 active framework layers, EOS Rocks + OKRs are mutually exclusive, drop a framework when maintenance time exceeds value.

**Docs to update:** 29

**Status:** applied (2026-02-15)

---

## Error 50: Venture Skills Have Model Detection but No Non-SaaS Metric Tables

**Severity:** High — skills can detect non-SaaS business model but have no alternative metrics to use

**Discovery:** Real-world application of `/growth-check` to psilea (cycle-product microdosing business, validation stage). Erratum #47 added business model type detection to Step 1, and the reconcile applied it. But the skill still only contained SaaS metric tables (MRR, churn, DAU/MAU, net retention). Detection without alternative metrics means the skill warns about model mismatch but can't provide the right analysis.

**Fix:** Added parallel non-SaaS capabilities across 4 venture skills:
- `/growth-check`: non-SaaS validation metrics table (recompra rate, AOV, channel attribution, concentration risk), metric routing note by business model, adapted AARRR funnel for cycle businesses, channel attribution analysis, revenue risk signals table
- `/monthly-close`: external data source detection (Google Sheets), cash flow reconstruction from transactions, AR/AP tracking, COGS reality check
- `/venture-onboard`: data completeness audit for external data stores
- `/venture-align`: V5 referrer/partner tracking as Validation+ checklist item with implementation template

**Docs to update:** 29 (skill templates describe the new sections)

**Status:** code-fix (2026-02-15) — implemented in `feat/venture-data-patterns` branch, merged to main, deployed

---

## Error 51: [Doc 14](reflections/14-mastermind-architecture.md) Agent Roster Has Swapped Models

**Severity:** Medium — could lead to wrong model selection during rebuild from specs

**Discovery:** `/brana:maintain-specs` cross-check of [doc 14](reflections/14-mastermind-architecture.md) agent roster (lines 144-155) against deployed agents in `~/.claude/agents/`. Two models are swapped:
- `memory-curator`: spec says **Sonnet**, deployed is **Haiku**
- `debrief-analyst`: spec says **Haiku**, deployed is **Sonnet**

The global `CLAUDE.md` agent table matches the deployed (correct) models. The swap likely happened during Phase 5 implementation — memory-curator was downgraded to Haiku (sufficient for knowledge lifecycle ops), debrief-analyst was upgraded to Sonnet (needs stronger reasoning for errata extraction). `/back-propagate` should have caught this.

**Files affected:** `14-mastermind-architecture.md` (agent roster table)

**Fix:** Update [doc 14](reflections/14-mastermind-architecture.md) agent roster: memory-curator → Haiku, debrief-analyst → Sonnet.

**Status:** applied (2026-02-16) — both model fields corrected in agent roster table

---

## Error 52: [Docs 14](reflections/14-mastermind-architecture.md), 31, 32 Reference Stale 15KB Context Budget

**Severity:** Low — implementation uses `validate.sh` value, not spec prose

**Discovery:** `/brana:maintain-specs` cross-check. Three docs reference "15KB context budget":
- [Doc 14](reflections/14-mastermind-architecture.md), line 700: "The 15KB context budget is a first-order architectural constraint"
- [Doc 31](reflections/31-assurance.md), line 32: "stays under the 15KB ceiling"
- [Doc 32](reflections/32-lifecycle.md), line 76: "The 15KB context budget isn't arbitrary"

The budget was raised twice: 15,360 → 18,432 (erratum #41, 2026-02-13) → 19,456 (gsheets skill addition). [Doc 24](24-roadmap-corrections.md) only records the first raise.

**Files affected:** `14-mastermind-architecture.md`, `31-assurance.md`, `32-lifecycle.md`

**Fix:** Update all three docs to reference ~19KB (or "19KB"). The exact number lives in `validate.sh`; spec prose should say approximately 19KB.

**Status:** applied (2026-02-16) — "15KB" → "~19KB" in [docs 14](reflections/14-mastermind-architecture.md), 31, 32

---

## Error 54: Context Budget Refs Stale Again (21KB → 23KB) — Third Consecutive Session

**Severity:** Low — systemic pattern, implementation uses `validate.sh` value

**Discovery:** `/back-propagate` after raising budget to 23,552 bytes. [Docs 14](reflections/14-mastermind-architecture.md), 25, 35 all referenced 21KB. This is the same pattern as errors #52 (15KB→19KB) and #53 (19KB→21KB) — every `validate.sh` budget change leaves spec docs behind.

**Files affected:** `14-mastermind-architecture.md`, `25-self-documentation.md`, `35-context-engineering-principles.md`

**Fix:** Updated during backprop session. The systemic fix is either: (a) enter's pre-commit hook validates budget references against validate.sh, or (b) a single source of truth (validate.sh) is referenced by prose instead of hardcoding numbers.

**Status:** applied (2026-02-18) — back-propagated 21KB → 23KB in [docs 14](reflections/14-mastermind-architecture.md), 25, 35

---

## Note: [Doc 14](reflections/14-mastermind-architecture.md) Line Number Shifts

The reflection layer redesign (docs 31, 32) removed ~160 lines from [doc 14](reflections/14-mastermind-architecture.md) — "Evaluating the Brain," DDD/SDD/TDD workflows, "Self-Describing Configuration," "User Feedback Loop," resolved questions, and lifecycle open questions were moved to [docs 31](reflections/31-assurance.md) (R3: Assurance) and 32 (R4: Lifecycle). Errata entries that reference [doc 14](reflections/14-mastermind-architecture.md) line numbers (errors #10, #11, #12, #19, #21, #27, #28) now point to lines that have shifted. All these errata are already `applied` — the line numbers in the error descriptions are historical, not current.

---

## Recommendations

1. **Fix deploy.sh** (error #1) — must happen before Phase 2 adds hooks to settings.json
2. ~~**Update [docs 14](reflections/14-mastermind-architecture.md), 17, 18** to use `SessionEnd` instead of `Stop` for learning extraction (error #2)~~ — **applied 2026-02-10** (docs 08, 14, 17, 18)
3. **Add cross-references** from [docs 17](17-implementation-roadmap.md)/18 to [doc 09](dimensions/09-claude-code-native-features.md) for hook format details (error #3)
4. **Add `PostToolUseFailure`** to the hook design in roadmap docs (error #4)
5. **Add agent descriptions** to context budget check in `validate.sh` (error #7)
6. Errors #5 and #6 are informational — documented here for reference during implementation
7. **Add [doc 00](00-user-practices.md) reference** to Phase 1 setup in [docs 17](17-implementation-roadmap.md) and 18 — mention graduation pathway as Phase 2+ design intent (error #8)
8. ~~**Replace all `hooks recall`/`hooks learn`** with `memory search`/`memory store` (error #9)~~ — **applied 2026-02-10** (docs 14, 17, 18; implementation code applied earlier)
9. ~~**Add alpha risk caveat** to [doc 14](reflections/14-mastermind-architecture.md) ReasoningBank sections (error #10)~~ — **applied 2026-02-10** (blockquote above ReasoningBank schema)
10. ~~**Scope MCP tool surface** in [doc 14](reflections/14-mastermind-architecture.md) plugin recommendations (error #11)~~ — **applied 2026-02-10** (note in Context7 MCP table entry)
11. ~~**Note daemon dependency** on [doc 14](reflections/14-mastermind-architecture.md) background learning ideas (error #12)~~ — **applied 2026-02-10** (note in open question #8)
12. ~~**Add development discipline enforcement** to [doc 08](reflections/08-diagnosis.md)'s essential hooks list (error #22)~~ — **applied 2026-02-10** (essential list + PreToolUse note)
13. ~~**Resolve open question #12** in [doc 08](reflections/08-diagnosis.md) — answered by [docs 11](dimensions/11-ecosystem-skills-plugins.md), 14, 22 (error #23)~~ — **applied 2026-02-10** (strikethrough + hybrid answer)

---

## Cross-References

- **[Doc 05](dimensions/05-claude-flow-v3-analysis.md)** (`05-claude-flow-v3-analysis.md`): claude-flow alpha assessment — source for errors #10-12
- **[Doc 08](reflections/08-diagnosis.md)** (`08-diagnosis.md`): Hook lifecycle — Stop→SessionEnd fixed (error #2)
- **[Doc 09](dimensions/09-claude-code-native-features.md)** (`09-claude-code-native-features.md`): Hook format details, all 14 events, stdin/stdout contracts
- **[Doc 14](reflections/14-mastermind-architecture.md)** (`14-mastermind-architecture.md`): Skill commands fixed (error #9). Alpha risk caveat (#10), MCP scope (#11), daemon note (#12) — all applied 2026-02-10
- **[Doc 17](17-implementation-roadmap.md)** (`17-implementation-roadmap.md`): All API commands fixed (errors #2, #9)
- **[Doc 18](18-lean-roadmap.md)** (`18-lean-roadmap.md`): All API commands fixed (errors #2, #9)
- **[Doc 00](00-user-practices.md)** (`00-user-practices.md`): User feedback loop — graduation pathway from manual practice to automated hook/check
- **[Doc 07](dimensions/07-claude-flow-plus-claude-4.6.md)** (`07-claude-flow-plus-claude-4.6.md`): v3.1 Agent Teams bridge analysis — source for error #21
- **[Doc 11](dimensions/11-ecosystem-skills-plugins.md)** (`11-ecosystem-skills-plugins.md`): SDD/TDD enforcement tools — source for errors #22, #23
- **[Doc 22](dimensions/22-testing.md)** (`22-testing.md`): Multi-agent TDD, TDD-Guard — source for error #23
- **[Doc 16](dimensions/16-knowledge-health.md)** (`16-knowledge-health.md`): Eight infection vectors — Vector 8 (instruction poisoning) source for error #45
- **[Doc 28](dimensions/28-startup-smb-management.md)** (`28-startup-smb-management.md`): Business model detection, framework stacking — source for errors #47, #49
- **[Doc 29](reflections/29-venture-management-reflection.md)** (`29-venture-management-reflection.md`): Venture transfer reflection — target for errors #47, #49, #50
- **[Doc 31](reflections/31-assurance.md)** (`31-assurance.md`): Verification framework — target for errors #44, #45
- **[Doc 32](reflections/32-lifecycle.md)** (`32-lifecycle.md`): Lifecycle reflection — target for error #46
- **[Doc 35](dimensions/35-context-engineering-principles.md)** (`35-context-engineering-principles.md`): Context engineering dimension — target for error #54
- **Phase 1 code** (`thebrana/deploy.sh`): Settings merge bug location

---

## Error 58: [Doc 14](reflections/14-mastermind-architecture.md) Missing Scheduler/Automation Architecture

**Severity:** High — architecture gap
**Status:** applied (2026-02-20)

**Discovery:** Maintain-specs re-evaluation (2026-02-20). ADR-002 was accepted, 5 scheduler items shipped (#45, #48, #49, #50, #51), but [doc 14](reflections/14-mastermind-architecture.md) (R2 Architecture) has zero mentions of scheduler, automation, systemd, or timer. Someone reading the architecture blueprint wouldn't know the automation layer exists.

**Files affected:**
- `14-mastermind-architecture.md` — "Scheduled Automation: The Out-of-Session Layer" section added after hooks

**Fix applied:** New section covering architecture diagram, relationship table (hooks vs scheduler vs skills vs agents), ADR-002 reference, output-to-memory pipeline, and current job list.

---

## Error 59: [Doc 32](reflections/32-lifecycle.md) Missing Scheduler in Lifecycle Maintenance

**Severity:** Medium — lifecycle coverage gap
**Status:** applied (2026-02-20)

**Discovery:** Maintain-specs re-evaluation (2026-02-20). brana-scheduler runs weekly staleness checks and can run any headless job on a cadence, but [doc 32](reflections/32-lifecycle.md) (R4 Lifecycle) doesn't mention scheduled jobs in its maintenance coverage.

**Files affected:**
- `32-lifecycle.md` — "Scheduled Automation" subsection added under Maintenance Cadences

**Fix applied:** Job table, memory integration note, and exit code design principle (cross-ref to learning #59).

## Error 60: Backlog #38 Description Stale — "Personal Side Project" vs Personal Life OS

**Severity:** Low — backlog hygiene, no implementation impact
**Status:** applied (2026-02-20)

**Discovery:** Debrief (2026-02-20). Backlog item #38 in [doc 30](30-backlog.md) says "define and bootstrap a personal side project. Scope TBD — use `/project-onboard` + `/project-align` to set up once scope is decided." What was actually built is a Personal Life OS with tasks.md, life.md, journal/, and a `/personal-check` skill. Neither `/project-onboard` nor `/project-align` were used — challenger review stripped them as unnecessary overhead.

**Files affected:**
- `30-backlog.md` — item #38 description and status

**Fix applied:** [Doc 30](30-backlog.md) item #38 description updated to reflect what was built, status changed to `done (2026-02-20)` with notes.

---

## Error 61: /personal-check Journal Check Reports "No Entries" When Template File Exists

**Severity:** Low — minor UX confusion, no data loss
**Status:** code-fix (2026-02-20)

**Discovery:** Debrief (2026-02-20). Running `/personal-check` with `2026-W08.md` present (77 bytes, valid template with headers and dashes) produced "No journal entries yet" instead of acknowledging the file. The skill's Step 4 checks for file existence but not content completeness, conflating "no files" with "no written content."

**Files affected:**
- `thebrana/system/skills/personal-check/SKILL.md` — Step 4 journal freshness check

**Fix applied:** Step 4 now checks file content beyond template markers. Empty templates get "Journal template created for {week} but not yet filled in." Missing files get "No journal entries yet."

---

## Error 62: [Doc 35](dimensions/35-context-engineering-principles.md) Instruction Density Warn Threshold 200 vs Actual 150

**Severity:** Medium — wrong threshold in spec leads to wrong validate.sh configuration
**Status:** applied (2026-02-20)

**Discovery:** Back-propagation (2026-02-20). [Doc 35](dimensions/35-context-engineering-principles.md) line 143 said "warn 200, error 300" but `validate.sh` uses warn 150, error 300 since the instruction density check was added (feat/context-budget-real-limits). The backprop for that feature missed updating [doc 35](dimensions/35-context-engineering-principles.md)'s threshold.

**Files affected:**
- `35-context-engineering-principles.md` — instruction density section

**Fix applied:** "warn 200" → "warn 150" in backprop-20260220-2.

---

## Error 63: [Doc 14](reflections/14-mastermind-architecture.md) Skill Count 31 vs Actual 36 — 5th Instance of Count Drift

**Severity:** Low — informational, same systemic pattern as #52-54
**Status:** applied (2026-02-20)

**Discovery:** Back-propagation (2026-02-20). [Doc 14](reflections/14-mastermind-architecture.md) Pattern C still said "All 31 deployed skills" when the actual count was 36. Five skills added across multiple sessions without updating this specific reference. Same pattern as errata #52, #53, #54 (budget/count refs go stale on every addition).

**Files affected:**
- `14-mastermind-architecture.md` — Pattern C skill count

**Fix applied:** "31" → "36" in backprop-20260220-2.

---

## Error 64: Bulk regex replacement breaks embedded code blocks

**Severity:** Medium — required manual rework on 9 files
**Status:** code-fix (2026-02-22)

**Discovery:** Python script (`/tmp/bulk-cf-replace.py`) used regex to find standalone fenced code blocks containing the cf-discovery pattern and replace them with a `source` one-liner. The regex expected ````bash\n...cf-discovery...\n``` `` as a standalone block, but 9 files had the cf-discovery embedded inside larger code blocks with additional commands (e.g., setup sections with both discovery and memory store). The regex either missed them entirely or ate surrounding text (knowledge-review lost its heading, client-retire lost indentation).

**Files affected:** 9 skills where cf-discovery was part of a larger fenced block, notably `knowledge-review/SKILL.md` and `client-retire/SKILL.md`.

**Fix applied:** Manual editing of all 9 remaining files after bulk pass.

---

## Error 65: Python frontmatter script dedup logic strips list items

**Severity:** Medium — left 8 skills with empty `depends_on:` fields
**Status:** code-fix (2026-02-22)

**Discovery:** `bulk-frontmatter.py` inserted `group:` and `depends_on:` after the `description:` line in YAML frontmatter. The dedup logic (meant to prevent double-injection on re-runs) checked for existing lines and stripped them — but it also stripped the `  - dep` child items of `depends_on:`, leaving empty `depends_on:` fields in all 8 skills that should have had dependencies. A second script (`/tmp/fix-depends-on.py`) was needed to repair.

**Files affected:** 8 skills with depends_on (build-feature, build-phase, monthly-close, monthly-plan, morning, weekly-review, venture-align, back-propagate).

**Fix applied:** Second Python script replaced empty `depends_on:` with correct lists or removed the field entirely.

---

## Error 66: Bash `declare -A` fails when env variable name conflicts

**Severity:** Low — one script, caught immediately
**Status:** code-fix (2026-02-22)

**Discovery:** `skill-graph.sh` used `declare -A GROUPS` for an associative array. Bash errored: "cannot convert indexed to associative array" because `GROUPS` already existed as an environment variable (likely from the shell profile or a parent process).

**Files affected:** `system/scripts/skill-graph.sh`

**Fix applied:** Rewrote the entire script using embedded Python instead of bash associative arrays. More reliable for YAML parsing anyway.

---

## Error 67: [Doc 14](reflections/14-mastermind-architecture.md) skill count 36 vs actual 33 after consolidation

**Severity:** Low — informational, same systemic pattern as #52-54, #63
**Status:** applied (2026-02-23)

**Discovery:** Skills refactor consolidated 3 skills into 1 (`/brana:memory`), reducing count from 36 to 33. [Doc 14](reflections/14-mastermind-architecture.md) still references the old count. 6th instance of count drift.

**Files affected:** `14-mastermind-architecture.md` — Pattern C skill count

**Fix applied:** Updated "All 33 deployed skills" → "All 34 deployed skills" in [doc 14](reflections/14-mastermind-architecture.md) line 151. Also removed stale "(282 bytes remaining)" since budget headroom changes frequently.

---

## Error 68: Feature shipped without user-facing documentation

**Severity:** Medium — caught by user post-merge
**Status:** code-fix (2026-02-22)

**Discovery:** Skills refactor (#44) was merged with full Phase 4 documentation (CLAUDE.md, backlog, tasks.json, delegation-routing) but zero human-readable guides. The SKILL.md files serve as Claude-facing docs, but there was nothing explaining the new `/brana:memory` skill, shared scripts convention, or skill metadata to the human user. User caught it and flagged it.

**Files affected:** No guide existed. Created `docs/skills-system.md`.

**Fix applied:** (1) Created `docs/skills-system.md` as the missing guide. (2) Added mandatory documentation step to `/build-feature` (Phase 6c-2) and `/build-phase` (Step 7c). (3) Added backlog #63 for future task-level auto-detection. Convention: "shipped without docs means not shipped."

---

## Error 69: Deploy pipeline missing `commands/` artifact type

**Severity:** Medium — untracked artifacts violate core workflow
**Status:** code-fix (2026-02-23)

**Discovery:** `session-handoff.md` and `init-project` lived only in `~/.claude/commands/` — the deployed target — with no source copy in `system/`. The deploy pipeline (`deploy.sh`, `validate.sh`) had no concept of commands. CLAUDE.md's component table and deploy flow diagram didn't mention them either. This meant commands were edited directly in the target directory, violating thebrana's core rule: "Never edit `~/.claude/` directly — always edit `system/` and deploy."

**Files affected:**
- `deploy.sh` — no commands deployment step
- `validate.sh` — no commands validation check
- `.claude/CLAUDE.md` — component table and deploy diagram missing commands/
- `system/commands/` — directory didn't exist

**Fix applied:** (1) Created `system/commands/` with `session-handoff.md` and `init-project`. (2) Added commands deploy step to `deploy.sh` (copies all files, chmod +x for scripts with shebangs). (3) Added Check 10 to `validate.sh` — validates YAML frontmatter for `.md` commands, shebang + syntax for shell script commands. (4) Updated `.claude/CLAUDE.md` component table and deploy flow diagram.

## Error 70: Pre-commit Check 3 can't parse doc number ranges in CLAUDE.md

**Severity:** Medium — forces `--no-verify` on commits touching docs inside ranges
**Status:** code-fix (2026-02-23)

**Discovery:** During `/back-propagate`, editing [doc 12](dimensions/12-skill-selector.md) (`12-skill-selector.md`) triggered pre-commit Check 3: "[Doc 12](dimensions/12-skill-selector.md) not referenced in CLAUDE.md dimension/reflection/roadmap lists." But [doc 12](dimensions/12-skill-selector.md) IS listed — CLAUDE.md line 18 says `01-07, 09-13, 20-23, 26-28, 33, 35`. The check does `grep -q "$DOC_NUM" CLAUDE.md` which looks for literal "12" — it can't parse range notation `09-13`.

**Files affected:**
- `pre-commit.sh` — Check 3 (lines 41-45)
- Affects any doc inside a range: 01-07 (except 00), 09-13, 20-23, 26-28

**Fix applied:** Replaced literal `grep -q "$DOC_NUM"` with Python range expansion that builds a flat list of all referenced doc numbers from CLAUDE.md. Ranges like `09-13` are expanded to `09 10 11 12 13` before membership check. See backlog #66.

---

## Error 71: GITHUB_TOKEN can't bypass branch protection rulesets

**Severity:** High — blocks automated releases entirely
**Status:** informational

**Discovery:** During first release pipeline setup (v1.0.0). Migrated from legacy branch protection to GitHub rulesets with `RepositoryRole: 5 (admin)` bypass. `@semantic-release/git` still failed with `GH013: Repository rule violations` when pushing version bump commits to main.

**Root cause:** `GITHUB_TOKEN` (associated with `github-actions[bot]`) is NOT treated as an admin user by rulesets. Admin bypass only covers actual admin-role human users or Personal Access Tokens from admin accounts. The bot operates with workflow-scoped permissions, not a repository role.

**Files affected:**
- `.github/workflows/release.yml`
- `.releaserc.json`

**Resolution:** Removed all semantic-release plugins that push commits to protected branches (`@semantic-release/git`, `@semantic-release/changelog`, `@semantic-release/exec`). Kept only `commit-analyzer` + `release-notes-generator` + `@semantic-release/github` (creates releases + tags without pushing to the branch). If commit-pushing is required, use a PAT from an actual admin user stored as a repo secret.

---

## Error 72: `persist-credentials: false` contradicts semantic-release push

**Severity:** Medium — contributed to release pipeline debugging cycle
**Status:** code-fix (2026-03-09)

**Discovery:** During release pipeline debugging. `actions/checkout` was configured with `persist-credentials: false` (common security template), but semantic-release needs the token persisted in git config to push tags.

**Files affected:**
- `.github/workflows/release.yml`

**Fix applied:** Removed `persist-credentials: false` from checkout step. With tag-only mode (no commits to push to main), the default credential persistence is sufficient for tag creation.

---

## Error 73: github-issues-sync spec diverged from shipped implementation

**Severity:** Medium — spec readers will look for `system/scripts/gh-sync.sh` but actual sync runs via `system/hooks/task-sync.sh` + `task-sync.py`
**Status:** pending

**Discovery:** Debrief agent comparison of spec vs. implementation (2026-03-11). Feature brief specifies `system/scripts/gh-sync.sh` as the sync helper with a specific CLI interface. Implementation shipped as a PostToolUse hook pair instead.

**Files affected:**
- `docs/architecture/features/github-issues-sync.md` — File changes table (line 229-238) and Design section

**Fix:** Update spec to reflect dual implementation: `gh-sync.sh` for manual/bulk operations (if kept), `task-sync.sh` + `task-sync.py` as PostToolUse hook for automatic incremental sync.

---

## Error 74: github-issues-sync spec lists retroactive issue creation as out-of-scope but it shipped

**Severity:** Low — parenthetical note acknowledges the contradiction but structure is misleading
**Status:** pending

**Discovery:** Debrief agent (2026-03-11). Line 51 says "Retroactive issue creation for completed tasks" is out of scope, while a parenthetical acknowledges bulk sync did create them.

**Files affected:**
- `docs/architecture/features/github-issues-sync.md` — Out of scope section

**Fix:** Move retroactive creation to "In scope" with note: "Bulk sync creates issues for completed tasks with Status=Done (closed immediately)."

---

## Lessons Learned

Process insights from implementing the corrections. These apply to brana's development going forward.

### 1. Specs that aren't tested against the real API will drift silently

Error #9 existed across 7 files and nobody caught it until we tried to actually run the hooks. The spec docs described `hooks recall`/`hooks learn` with full flag syntax, confidently and consistently — but the commands never existed. **Rule: every CLI command in a spec must be tested against the real tool before the spec is committed.** A spec that reads well but doesn't run is worse than no spec, because it breeds false confidence.

### 2. `2>/dev/null` hides real failures behind silent fallbacks

The session-end hook appeared to succeed (exit 0, output `{"continue": true}`) even when `memory store` failed — because the error was swallowed by `2>/dev/null` and the fallback to `pending-learnings.md` kicked in silently. Without explicitly verifying the store round-trip (search for what you just stored), we would have shipped a hook that silently never learned anything. **Rule: after implementing a store-then-retrieve pipeline, always test the round-trip, not just the exit code.**

### 3. Database schema drift breaks things silently

The `$HOME/.swarm/memory.db` file existed (from a previous claude-flow version) but had a stale schema — missing the `type` column that v3 expects. `memory search` still worked (read-only, tolerant), but `memory store` failed. This meant the recall hook worked fine while the learning hook was silently broken. **Rule: `memory init --force` should be a documented step whenever claude-flow is upgraded.** Old DBs don't auto-migrate.

### 4. claude-flow discovers its DB relative to CWD

This isn't documented anywhere in claude-flow. Hooks run from the project directory, but the global memory DB lives at `$HOME/.swarm/memory.db`. Without `cd "$HOME" &&` before every `npx claude-flow memory` call, the hooks would create per-project DBs or fail to find the global one. **Rule: any hook that calls claude-flow must explicitly set CWD to `$HOME`.** This should be a documented pattern in the hook template.

### 5. claude-flow `--help` doesn't show subcommand flags

`npx claude-flow memory search --help` prints the top-level `memory` help, not the `search` subcommand flags. You have to test commands directly or read the source to discover `-q`, `--format`, `--namespace`, etc. **Impact: spec authors can't discover the real API from `--help` alone.** This partially explains how Error #9 happened — someone described the API they expected rather than the one that exists.

### 6. Hook testing requires full pipeline simulation

`bash -n script.sh` catches syntax errors but not logic errors. To properly test a hook you need to: (a) create a fake event file in `/tmp/`, (b) pipe the right JSON to stdin, (c) run the hook, (d) verify the external side effect (search for the stored entry). **Rule: every hook should have a test script or at minimum a documented manual test procedure.** `validate.sh` checks 9 things but all are static — no hook is actually executed.

### 7. `((var++))` under `set -e` exits when var is 0

Bash arithmetic `((PASSED++))` post-increments — the expression value is the **old** value (0), which bash treats as falsy (exit code 1). Under `set -e`, this silently kills the script. **Rule: never use `((var++))` in scripts with `set -e`. Use `VAR=$((VAR + 1))` instead.** This affected both test scripts and would affect any counter pattern.

### 8. `npx` is not a reliable binary locator in subprocesses

`npx claude-flow` works interactively because your shell has nvm initialized. Hook subprocesses often don't — `$PATH` may not include nvm bins, and `npx` falls back to downloading the package fresh (taking 10+ seconds, exceeding hook timeouts). **Rule: for tools installed globally via nvm, locate the binary directly at `$HOME/.nvm/versions/node/*/bin/toolname` rather than relying on `npx`.** The smart discovery pattern (nvm bin → PATH → npx fallback) should be standard in all hook scripts.

### 9. Write tests first, then discover they test the right thing

The hook smoke test immediately caught the grep-c bug (error #13), the stdout pollution (error #15), and the `((++))` exit-under-set-e issue. These bugs existed since the hooks were written but were invisible because no test exercised them. The 10 minutes spent writing tests paid back immediately — they found 3 bugs in 3 test runs. **Rule: add `./test.sh` to the merge workflow. The test suite takes seconds and catches things that static validation and manual review miss.**

### 10. MCP and CLI are complementary, not competing

claude-flow runs as MCP server (`.mcp.json`) for in-session tool calls and has a CLI binary for hooks/scripts. They share the same backend DB. Hooks must use CLI (they're subprocesses, not Claude tools). In-session agents should use MCP (faster). Testing can use either (same DB, same logic). **Rule: don't force one transport for everything. MCP for in-session, CLI for hooks/scripts, both hit the same DB.**

### 11. `memory search` is for discovery, `memory retrieve` is for verification

`memory search` returns a `preview` field that truncates stored values (typically after ~50 chars). This is fine for humans scanning results but breaks any test or script that needs to verify specific JSON fields in stored content. **Rule: use `memory retrieve -k KEY --namespace NS --format json` for field-level verification.** The `content` field in the retrieve response contains the full, untruncated stored value. Tests that grep search output for JSON fields will fail on any value longer than ~50 characters.

### 12. Maintain-specs materiality filtering is essential

6 parallel Haiku agents cross-checked dimension→reflection doc pairs and returned dozens of findings. After strict materiality filtering ("would this lead to a wrong implementation decision?"), only 2 were genuine errors. Most findings were enhancement suggestions, already-decided architectural choices, or testing methodology that belongs in specialized docs. **Rule: when collecting parallel agent results in maintain-specs, apply the materiality test ruthlessly.** Without it, you'd make unnecessary doc changes that dilute the errata log and waste review time.

### 13. Precise roadmaps eliminate implementation ambiguity

Phase 4's 8 work items in [doc 18](18-lean-roadmap.md) were detailed enough (file paths, logic flows, exit criteria, template content) that the plan and implementation were nearly 1:1 translations. No rework, no design decisions during coding, no blocked tasks. Phase 2 had rougher specs and required multiple correction rounds. **Rule: invest time in roadmap precision — detailed WIs with file paths, logic pseudocode, and exit criteria. The implementation session should be typing, not thinking.**

### 14. Validation scripts must exercise the patterns they validate

`validate.sh`'s `sed`-based frontmatter extraction worked for 12 skills because none of them used `---` horizontal rules in the body. The 13th skill broke it. The extractor was never tested against markdown with body `---` separators — it was tested against files that happened to avoid them. **Rule: validation logic needs edge-case test data, not just happy-path data.** A validation script that passes on all current inputs gives false confidence if it hasn't been tested against the patterns it's supposed to reject.

### 15. Graceful degradation is not optional — it's the feature

When ReasoningBank broke (sql.js missing), every operation that tried to store or recall patterns failed. But the system kept working: skills were created, deployed, tested, and documented using Layer 0 (auto memory files). The two-layer architecture from [doc 17](17-implementation-roadmap.md) — "anything critical enough to survive claude-flow outage should ALSO be written to Layer 0" — proved exactly right. **Rule: always implement the degraded path first. The enhanced path (ReasoningBank, SONA, etc.) is a bonus. If the floor (Layer 0) works, the system survives anything.**

### 16. Alpha tool upgrades must be followed by smoke tests

Upgrading claude-flow from alpha.28 to alpha.34 silently broke `memory search` — the `-q` flag was shadowed by a new global `--quiet` flag. There was no changelog, no deprecation warning, and the `--help` text still showed the old syntax. 15 files broke at once. **Rule: after every alpha tool upgrade, run the smoke test suite (`./test.sh`) before deploying. Also run `$CF memory search --query "test"` and `$CF memory store -k "test" -v "test"` manually to verify the memory API still works.** Alpha means the API surface is unstable — treat every version bump as a potential breaking change.

### 17. Never use `npx` to run MCP servers

`.mcp.json` entries using `npx tool@version` create a separate npx cache directory (`~/.npm/_npx/{hash}/`), completely independent of the global install. Any dependency manually installed in one path is missing from the other. When `npx tool@version` is pinned, the MCP server runs a **different version** than the CLI — in our case, alpha.22 (MCP) vs alpha.34 (CLI). This caused: (a) sql.js installed in CLI path but missing in MCP path, (b) version mismatch between MCP and CLI hitting the same DB. **Rule: always point `.mcp.json` at the globally-installed binary (`"command": "/full/path/to/binary"`) instead of using npx. One binary, one package directory, one version.** The minor inconvenience of updating the path on node version changes is far better than debugging ghost dependencies across npx caches.

### 18. Spec docs describe what and why, not how

[Doc 14](reflections/14-mastermind-architecture.md)'s skill templates were updated to use a `$CF` variable with a 7-line bash discovery block. The user flagged it as over-engineered — and they were right. The architecture doc should show the concept (`claude-flow memory search --query "..."`); the implementation code (thebrana's actual skill files) handles the how (binary discovery, fallback chains, error handling). Mixing levels of abstraction in spec docs adds noise without value. **Rule: keep spec docs at the concept level. Implementation details belong in implementation code. A one-line note pointing to the deployed code is better than duplicating it in the spec.**

### 19. Pain-driven development needs real usage data

After completing v0.5.0 (all 5 lean phases), `/build-phase lean` correctly identified zero pain signals — [doc 00](00-user-practices.md) had no usage entries, ReasoningBank had only build-learnings, no real-project patterns existed. Building more would have been building in anticipation, not in response. **Rule: after completing a roadmap's structured phases, stop building and start using. Pain-driven mode requires accumulated friction from real work. Without it, you're guessing at what to build next.**

### 20. Metric frameworks must adapt to the business model

`/growth-check` templates assume subscription/SaaS dynamics: MRR, churn rate, DAU/MAU, net revenue retention. Psilea is a cycle-based service (2-3 month microdosing cycles). "Churn" of 95% looks catastrophic in SaaS terms but is normal for a cycle business — clients complete their cycle and leave. "Retention" means recompra (buying another cycle), not "didn't cancel." DAU/MAU is meaningless. The health check still produced useful output, but required significant reframing to avoid misdiagnosis. **Rule: before applying metric templates, identify the business model type (SaaS, cycle/project, marketplace, consulting, e-commerce) and adapt accordingly. A cycle-based business with 5% "retention" might be healthy — what matters is acquisition rate and recompra rate, not monthly churn.**

### 21. Knowledge extraction before alignment produces real content, not templates

Running `/venture-onboard` + completing `KNOWLEDGE_EXTRACTION.md` before `/venture-align` meant every alignment artifact contained real data: actual prices ($130-180K ARS), actual processes (WhatsApp → info → guia → DIM → entrega), actual suppliers (Diego Moral at $7K/g), actual team roles. The SOPs were immediately usable, not placeholder templates. Without the knowledge extraction, venture-align would have produced generic docs requiring a second pass to fill in real values. **Rule: always complete knowledge extraction (founder interview, data gathering) before running venture-align. The alignment quality is directly proportional to input specificity. Generic in → generic out.**

### 22. Cross-reference related SOPs with a flow diagram

Psilea's three core SOPs (production, onboarding, sales) are interconnected: onboarding leads to sales, sales triggers production, production feeds back to sales for delivery. Without an explicit flow diagram in the SOP index, each SOP would be an island — a reader couldn't see how they chain together. The flow diagram (`Client → SOP-002 → SOP-003 → SOP-001 → SOP-003 delivery`) made the handoffs visible. **Rule: when creating 2+ related SOPs, always create an index with a flow diagram showing the connections. SOPs are steps in a pipeline, not isolated procedures.**

### 23. Domain knowledge needs `domain:` tags, not `project:` tags

During `/brana:retrospective`, 3 venture management patterns (stage detection, framework layering, Cardone vs Sullivan/Hardy) were stored with `project:brana` tags because they were discovered during brana spec work. But these are domain knowledge — any business project should recall them, not just brana. A search from a different project wouldn't find them. After catching this, patterns were re-stored with `domain:venture-management` tags and `transferable: true`, keeping `source_project` as a metadata field for origin tracking. **Rule: distinguish system patterns (`project:{name}`, non-transferable, about how the system works) from domain patterns (`domain:{name}`, transferable, about what the system knows). The key prefix convention is `pattern:{project}:*` for system and `pattern:{domain}:*` for domain knowledge.**

### 24. claude-flow `memory store` supports `--upsert` for updates

Attempting to re-store a pattern with the same key and namespace fails with `UNIQUE constraint failed` by default. The `--upsert` flag exists and works — it updates the value and regenerates the vector embedding. `--force` does NOT work (silently ignored, still hits UNIQUE constraint). When parallel store calls fail, siblings show "Sibling tool call errored" — shared failure propagation. **Rule: use `memory store --upsert` when updating existing entries. Never use `--force` (doesn't work for this). Avoid parallel stores to the same key — even with `--upsert`, concurrent writes are a race condition.**

### 25. Triage-then-extract beats deep-reading everything

422 LinkedIn links in the backlog. Deep-reading all would cost ~400 agent calls and yield mostly noise. Instead: bulk-classify first (cheap Haiku scouts, ~12 links per agent), then deep-extract only from the `noted` subset. 144 links → 35 noted → 4 actionable changes applied. Yield rate ~3%. The two-pass funnel (classify → extract) is 10x more efficient than single-pass deep reads because 60%+ of links are irrelevant and can be discarded at classification cost (~1K tokens) instead of extraction cost (~5K tokens). **Rule: for large research queues, always triage before extracting. The classification pass should be fast and cheap (Haiku), the extraction pass slower and targeted (Haiku with full system context). Never deep-read a queue — funnel it.**

### 26. Bulk regex edits need a two-pass verification strategy

The Python bulk-edit script caught 32 of 41 replacements. The remaining 9 had variations the regex didn't anticipate: embedded blocks, different indentation, mixed content. The fix was manual editing — one file at a time. The broken files (knowledge-review lost its heading, client-retire lost indentation) were only caught by reviewing the diff, not by validation. **Rule: after any bulk regex replacement across 10+ files, run a verification pass: (1) count expected vs actual replacements, (2) `git diff` every changed file for formatting damage, (3) grep for any remaining instances of the old pattern. The bulk script is the first pass, not the only pass.**

### 27. Embedded Python in bash scripts beats associative arrays

Bash associative arrays (`declare -A`) are fragile: they conflict with environment variables of the same name, have inconsistent behavior across bash versions, and can't parse YAML. The skill-graph.sh rewrite from bash to embedded Python (`python3 - <<'PYEOF'`) was more reliable, more readable, and handled YAML frontmatter parsing natively. **Rule: when a bash script needs structured data (maps, YAML, JSON parsing), embed Python instead of fighting bash data structures. The `python3 - "$@" <<'PYEOF'` pattern gives you a real language inside a bash wrapper.**

### 28. Shipped without docs means not shipped

The skills refactor completed 4 phases, passed validation, deployed successfully — and was called incomplete by the user because there was no human-readable guide. The SKILL.md files are Claude-facing docs; they're invisible to the human operator. Documentation for the user is a separate deliverable that must be part of the close phase, not an afterthought. **Rule: every feature that introduces or changes user-facing behavior must include a guide update in `docs/` before it can be called "shipped." Add the documentation step to both `/build-feature` and `/build-phase` close phases so it can't be forgotten.**

### 26. Maximize parallelism within each approval gate

This session ran mostly sequential: triage → extract → apply skill edits → backprop, one step at a time. Within each step, there was untapped parallelism: the 3 skill edits could have been 3 parallel agent worktrees; [docs 29](reflections/29-venture-management-reflection.md) and 25 could have been edited concurrently; the backprop plan could have been prepared while skill edits were merging. The real dependency chain is between approval gates (can't backprop until you know what was built), not between independent edits within a gate. **Rule: after user approval, launch all independent work within that gate in parallel — separate worktrees, separate agents, merge when all complete. Sequential work within a gate is wasted wall-clock time.**

### 27. Scout prompts need explicit system context to produce actionable results

Extraction scouts launched without brana architecture context returned generic advice ("add a router agent", "build a task graph schema"). The same scouts relaunched with a 3-line system description ("brana has skills, hooks, agents, deploys to ~/.claude/") returned implementable changes ("add input metrics section to OKR template in /venture-align"). **Rule: when spawning scouts for insight extraction, always include a concise system description in the prompt — what exists, how it's structured, what the constraints are. Without this framing, Haiku optimizes for breadth (sounds smart) instead of depth (actually useful). The framing cost is ~50 tokens; the value difference is binary.**

### 26. Meta-rules stored in MEMORY.md violate their own framework

The CLAUDE.md vs MEMORY.md framework rule ("prescriptive content goes in rules/, descriptive content goes in MEMORY.md") was itself stored in MEMORY.md — a prescriptive rule living in a descriptive file. This went undetected for multiple sessions because the content was correct and useful. The violation was structural, not content-level. An audit comparing file classification against content classification caught it. **Rule: after establishing a new framework or convention, immediately check whether the framework itself is stored in the right place. Meta-rules about where content goes are still rules — they belong in `~/.claude/rules/`, not MEMORY.md.**

### 27. Hook fallback paths must respect the same scoping as primary paths

`session-end.sh` stored session data via claude-flow to project-namespaced keys (Layer 1, correct) but its fallback wrote to `~/.claude/memory/pending-learnings.md` — a global file outside any project's auto-memory directory. The primary path was project-scoped; the fallback was global. This meant fallback data couldn't be associated with the right project when claude-flow recovered. **Rule: fallback paths must mirror the scoping of primary paths. If the primary path writes to a project-specific namespace, the fallback must write to the project's auto-memory directory, not a global file.**

### 29. Background Task agents cannot edit .claude/ directory files

Phase B's agent (general-purpose, bypassPermissions mode) was blocked by security policy from editing `thebrana/.claude/CLAUDE.md` — Write, Edit, and Bash sed all denied. This appears to be a Claude Code security boundary: spawned agents cannot modify their own instruction files in `.claude/` directories. The main context had to handle the edit. **Rule: when planning parallel agent work, identify `.claude/` directory edits upfront and reserve them for the main context or a follow-up step. Never assign `.claude/` file modifications to background agents.**

### 30. User feedback during implementation improves deliverables more than plan precision

The original plan for the source registry had `last_checked` dates and yield history — good for tracking when sources were checked. Mid-implementation, the user pointed out that version tracking matters more: when [doc 05](dimensions/05-claude-flow-v3-analysis.md) says "claude-flow v3.1.0-alpha.34", what matters isn't when we last checked the repo but whether that version is still current. This led to `version_observed` + `date_observed` fields and a "Version Drift Detection" section in [doc 33](dimensions/33-research-methodology.md) — the most architecturally significant addition to the registry, and it wasn't in the plan. **Rule: treat user feedback during implementation as a feature, not an interruption. Pause, integrate the feedback into the current branch, and continue. The plan is a starting point, not a contract.**

### 28. Multi-repo sessions require explicit CWD per git command

When working across multiple git repos in the same session (enter + psilea), the CWD silently resets between Bash calls. A `git checkout -b` intended for psilea ran in the enter repo instead — creating a branch in the wrong project. This happened twice: first checking git status of the parent brana repo instead of the psilea child, then creating a branch in enter instead of psilea. **Rule: never rely on CWD being correct when switching between repos. Always prefix git commands with `cd /full/path/to/repo &&`. Verify with `pwd` before any destructive git operation. The cost of an extra `cd` is zero; the cost of a branch in the wrong repo is confusion and cleanup.**

### 31. Spawned agents with bypassPermissions can commit to master

A background agent spawned with `bypassPermissions` mode merged an existing branch to master and committed new changes directly there — violating git discipline. The agent wasn't given explicit branch instructions, so it operated on whatever branch it found (the agent's CWD started on the branch, a hook merged it, and subsequent commits landed on master). **Rule: when spawning agents that will make git commits, always include explicit branch instructions in the prompt: which branch to work on, whether to commit, and never to merge or switch branches. `bypassPermissions` bypasses user approval, not git discipline.**

### 32. Implementation changes must immediately trigger back-propagation

After updating `git-discipline.md` in thebrana to adopt worktrees, the corresponding spec doc (doc 26) still said "Don't adopt worktrees yet." The user caught the drift. The `delegation-routing.md` rule already listed this trigger ("After changing a rule, hook, skill, or config → `/back-propagate`"), but it wasn't followed. **Rule: after any implementation change to rules, skills, agents, or config in thebrana, immediately check whether the corresponding spec doc in enter needs updating. Don't wait for the user to notice the drift. This is the back-propagation pattern — implementation → specs, the reverse of maintain-specs.**

### 33. Worktrees eliminate the stash/checkout friction that causes branch mistakes

The session needed to merge a branch to master, but unstaged changes from a previous session blocked `git checkout`. This required `git stash` → `checkout master` → `merge` → `stash pop` — four commands where one (`git merge` from a worktree) would suffice. The stash dance is also where things go wrong: the spawned agent hit the same problem and resolved it by committing directly to master. Worktrees make the correct workflow (branch isolation) the easy workflow. **Rule: use `git worktree add` for all branch operations. Merge from the main worktree without ever switching branches. Clean up with `git worktree remove`. Never stash to switch branches.**

### 34. Never modify user-facing system files without explicit approval

A previous session trimmed `git-discipline.md` from 4,928→2,133 bytes to fit a 15KB context budget — removing worktree examples, the "Two types of work" section, and the "Why this matters" closing. The user reversed it: the examples are valuable, the budget was wrong. The file was restored and the budget raised instead. **Rule: before reducing, trimming, or simplifying any file in `~/.claude/rules/`, `~/.claude/skills/`, `~/.claude/agents/`, or `CLAUDE.md`, present the proposed change and get explicit user approval. These files represent user preferences and workflow — optimizing them for token count without consent loses trust.**

### 35. Context budget research: rules files are a rounding error vs. MCP tool definitions

Research found MCP tool definitions consume 30-67K tokens (15-34% of 200K window). The entire `~/.claude/rules/` directory at 10,466 bytes is ~2,600 tokens — about 1.3% of context. The 15KB self-imposed budget was treating rules as a scarce resource when the actual constraint is elsewhere. Raising to 18KB still leaves 99% of context for working memory. **Rule: when optimizing context usage, measure all contributors (system prompt, MCP tools, rules, skills, agents, MEMORY.md) before trimming any one. Optimize the largest contributor first. Don't sacrifice content quality to save tokens in a component that's <2% of the budget.**

### 36. Background agents cannot write to cross-repo worktree paths

> **Partially superseded by lesson #68.** The sandboxing described below is hook-enforced, not platform-enforced. Agents spawned with `bypassPermissions` mode skip pre-tool-use hooks entirely and CAN write cross-repo. Default-mode agents remain sandboxed as described.

Venture OS Phase 2 planned 3 background agents to parallelize edits across enter and thebrana worktrees. All 3 agents were spawned from the enter repo CWD but needed to write files in `../thebrana-feat-venture-ops-p2/`. The pre-tool-use hook blocked every Write/Edit/Bash call — agents inherit the spawning repo's permission boundary and cannot write outside it. This extends lesson #29 (agents can't edit `.claude/` dirs) to a broader principle: agents are sandboxed to their spawning repo's directory tree. **Rule: when planning parallel agent work across multiple repos or worktrees, reserve all cross-repo writes for the main context. Agents can read and research across repos but cannot write outside their CWD's repo boundary. Design parallelization around this constraint — use agents for content preparation, main context for cross-repo edits.**

### 37. Edit tool requires reading the exact target file path, not an equivalent copy

After reading SKILL.md files at their original thebrana paths (`thebrana/system/skills/*/SKILL.md`), Edit calls targeting the worktree copies (`thebrana-feat-venture-ops-p2/system/skills/*/SKILL.md`) failed with "File has not been read yet." The Edit tool tracks reads by exact path — a worktree copy at path B is a distinct file from the original at path A, even though the content is identical. **Rule: when editing files in a worktree, always Read the worktree path first, not the original repo path. The Edit tool's read-before-edit safety check matches on exact file paths, not content.**

### 38. Shell `echo` with literal `\n` in JSON breaks `jq` — use `jq -n` for test fixtures

Dry-run testing `post-sale.sh` with `echo '{"content":"line1\nline2"}'` failed: jq treated the literal `\n` as JSON escape producing a newline character, but the `$15,000` substring was also problematic with shell interpolation concerns. Switching to `jq -n '{content:"line1\nline2"}'` to build the test input solved all issues — jq handles its own escaping correctly. **Rule: when constructing JSON test fixtures for hook dry-runs, always use `jq -n` to build the JSON rather than shell `echo` with raw strings. `jq` handles escaping, quoting, and special characters correctly; shell string manipulation doesn't.**

### 39. Haiku agents fabricate specific source references that look authoritative

During maintain-specs, 5 parallel Haiku agents returned 12 findings. The R1 agent claimed [doc 14](reflections/14-mastermind-architecture.md) uses `memory search -q` syntax — grep verification found zero matches. The R2 agent claimed [doc 14](reflections/14-mastermind-architecture.md) has broken CLI examples — also zero matches. These weren't vague suggestions; they cited specific sections and line numbers that didn't exist. The fabrications were plausible enough to waste verification time. **Rule: every Haiku agent finding that cites a specific code pattern, line number, or file content must be grep-verified before acting on it. Haiku agents fabricate authoritative-sounding references at ~90% rate in cross-checking tasks. The materiality filter (lesson #12) catches the false positives, but only if you verify instead of trusting the citation.**

### 40. Reconcile adds awareness but not capability — a second implementation pass is needed

Erratum #47 reconcile added "detect business model type" to `/growth-check` Step 1, and erratum #49 added a framework stacking warning to `/venture-align`. Both were correct but incomplete: detection without alternative metric tables is like adding a type check without implementing the branch. When psilea was analyzed, the skill said "this is a cycle-product business" but then ran SaaS metrics anyway. **Rule: when reconcile adds a detection or warning, immediately check whether the corresponding capability (alternative logic path, different templates, adapted benchmarks) also exists. If it doesn't, create a follow-up task for the implementation pass. Detection without capability is a partial fix that creates false confidence.**

### 41. User preferences must be persisted to auto memory immediately, not deferred

A Co-Authored-By preference from a previous session was lost when context compacted. The user had to repeat themselves. The preference wasn't saved to MEMORY.md because the retrospective that would have captured it never ran (session ended first). **Rule: when the user expresses any durable preference ("always X", "never Y"), save it to auto memory immediately — don't wait for end-of-session `/brana:retrospective`. Preferences are cheap to store (~1 line in MEMORY.md) and expensive to violate (user frustration, repeated corrections). Treat explicit user preferences as higher priority than pattern storage.**

### 42. Real-project work is the best skill-improvement methodology

Four venture skills were improved more in one psilea work session than in three spec-driven reconcile passes. The spec-driven passes added detection, warnings, and framework references — useful but abstract. The real-project session revealed concrete gaps: no recompra rate metric, no channel attribution analysis, no COGS reality check, no data completeness audit, no referrer tracking. Each gap was discovered because the skill failed to capture something real. **Rule: after building or reconciling skills from specs, schedule a real-project application session. Use the skills on an actual business project and note every point where the skill output was incomplete, misleading, or missing a dimension. One real session produces more actionable improvements than multiple spec reviews.**

### 43. Context compaction loses intermediate computation — re-derive cheaply instead of preserving

A continuation session lost the exact link→doc classification mappings from 3 Haiku agents (previous session's results compacted away). Instead of trying to preserve intermediate results across sessions, re-ran 3 parallel Haiku agents in ~6 seconds for ~$0.01. The re-classification was trivially cheap compared to the complexity of trying to persist and restore intermediate state. **Rule: when context compaction loses intermediate computation results (classification maps, routing decisions, extracted lists), prefer re-deriving them cheaply over building persistence infrastructure. If re-derivation takes <30 seconds and costs <$0.05, it's not worth saving. Reserve persistence for expensive or irreproducible results (human decisions, multi-hour analyses, external API responses).**

### 44. Separate mutation scripts from normalization scripts

The link distribution task needed two operations: (1) move 198 rows from [doc 30](30-backlog.md) into 11 dimension docs, (2) normalize Research Resources sections (add headers, merge numbering schemes, renumber sequentially). Combining both into one script would have made debugging harder — the move script produced formatting issues (missing headers, mixed `LI-xxx` and sequential numbering) that only became visible after running it. A second cleanup script fixed formatting independently. **Rule: for bulk file mutations, split into mutation (move/insert/delete data) and normalization (fix formatting/headers/numbering) as separate scripts. Run mutation first, inspect results, then normalize. Each script stays simple and testable. The cost of two scripts is zero; the cost of debugging a combined script that both moved and reformatted is significant.**

### 45. Back-propagation misses accumulate silently — maintain-specs is the safety net

Erratum #51 (agent model swap: memory-curator Sonnet→Haiku, debrief-analyst Haiku→Sonnet) existed since Phase 5 implementation but wasn't caught until a maintain-specs cross-check compared the [doc 14](reflections/14-mastermind-architecture.md) roster against deployed agent files. The mismatch was harmless in practice (the deployed agents were correct), but the spec was wrong for potentially weeks. **Rule: treat `/brana:maintain-specs` as the safety net for `/back-propagate` failures. Back-propagation is voluntary and easy to forget after implementation sessions. Maintain-specs is systematic and catches accumulated drift. Run maintain-specs at least once per week or after every 2-3 implementation sessions, regardless of whether back-propagation was done.**

### 46. Budget changes need automated propagation — three occurrences is a pattern

Errata #52 (15KB→19KB), #53 (19KB→21KB), and #54 (21KB→23KB) are the same bug on three consecutive days. Each time `validate.sh` budget changes, multiple spec docs reference the old number. The backprop fixes it, but only after someone notices. **Rule: when a value is referenced across 3+ files and changes frequently, either (a) add it to the enter pre-commit hook as a cross-reference check, or (b) use approximate language ("~23KB, see validate.sh") so prose doesn't go stale on exact-number changes. The current pre-commit hook for enter checks file cross-references but not budget references — this is the gap.**

### 47. Parallel Haiku scouts for backlog feasibility assessment

Four pending backlog items needed complexity/value assessment before starting. Spawning 4 Haiku Explore agents in parallel — one per item, each with codebase access — produced comprehensive feasibility reports (hook inventory, data structure analysis, doc gap assessment, validation coverage) in under 10 seconds total. **Rule: for multi-item backlog assessment, spawn one Haiku scout per item in parallel. Give each scout the item description + access to explore the codebase. The reports provide enough signal to prioritize without spending main-context tokens on 4 separate deep-dives.**

### 48. Steerable errors: capture, classify, guide

Four hooks called claude-flow with `2>/dev/null` or `|| true`, silently swallowing failures. Replacing this with exit code capture and classification (124=timeout, 127=not found, general failure) plus actionable next-step commands produced hooks that surface guidance instead of hiding problems. **Rule: every hook that calls an external binary should: (a) capture stderr into a variable, (b) check the exit code with classification, (c) build a warning message with the exact command the user should try, (d) surface via additionalContext (session-start) or session log (session-end). The pattern is `CMD 2>&1 || true; CF_EXIT=$?; case $CF_EXIT in 124) timeout_msg;; 0) process_output;; *) error_msg;; esac`.**

### 49. Pre-commit hooks as shift-left validation

Validation that runs only at deploy-time (`validate.sh`, `deploy.sh`) catches errors late — after the code is committed and sometimes after multiple commits compound the issue. Moving the highest-value checks to pre-commit (YAML frontmatter, JSON syntax, secrets, context budget, cross-references, README coverage) catches errors at commit time with zero false positives. **Rule: when adding a new validation to deploy.sh or validate.sh, also add a lightweight version to the pre-commit hook. The pre-commit should catch definite errors (syntax, missing references, budget overflow); the deploy-time validation handles heavier checks (full integration, deployment readiness).**

### 50. Batch backlog items in one branch to reduce merge friction

Four backlog items (#16, #27, #29, #30) were implemented in a single branch rather than four separate ones. This avoided 3 extra merge cycles and the merge conflict that would have compounded in [doc 30](30-backlog.md) (each branch updating different item statuses). The one merge conflict that did occur (HEAD had partial progress on #29, branch had "done") was straightforward. **Rule: when doing multiple independent backlog items in one session, use one branch for all. Update [doc 30](30-backlog.md) status once at the end. The merge friction of N branches touching the same status-tracking file exceeds the benefit of branch isolation for small, independent work items.**

### 51. Haiku scouts can't write temp files — design the protocol to tolerate inline returns

The `/brana:research` skill mandates scouts write findings to `/tmp/research-{target}-{N}.md` and return only a 2-line summary. In practice, Haiku and Sonnet scouts (subagent_type: "scout") lack Bash access and can't write files. They return findings inline in the task result. This happened across 8 scouts in two consecutive research sessions — the pattern is consistent, not a fluke. The skill procedure still works: triage from task notifications instead of temp files. **Rule: when designing multi-phase research with scout agents, treat temp-file output as aspirational — always have a fallback plan to triage from task result data. Scout agents are read-only by design. If file persistence is truly needed, use a general-purpose agent (which has Write/Bash) instead of a scout, at the cost of higher token usage.**

### 52. Clean main before merging worktree branches — or the merge will conflict with itself

When creating new files in the main working directory, then copying those same files to a worktree branch for committing, the merge back to main fails because main still has the uncommitted originals. The fix is mechanical: `git checkout -- modified-file && rm new-file` on main before `git merge --no-ff`. This happened twice in one session (doc 08 and [doc 09](dimensions/09-claude-code-native-features.md) commits). **Rule: when using the pattern "create content on main → copy to worktree → commit on branch → merge back", always restore main to its clean state before the merge. The worktree branch now owns the canonical version; main's uncommitted copies are just drafts that must be discarded. Add this as an explicit step in the worktree workflow.**

### 53. Research across sessions compounds — prior docs ground the recommendation

[Doc 09](dimensions/09-claude-code-native-features.md) (mobile vs desktop criteria) was dramatically stronger than [doc 08](reflections/08-diagnosis.md) (AI mobile platforms) because [doc 08](reflections/08-diagnosis.md) existed as grounding. The recommendation in [doc 09](dimensions/09-claude-code-native-features.md) could cite ADR-002, reference [doc 02](dimensions/02-nexeye-skill-selection.md)'s original analysis, and show how new data (Airbnb 58% mobile 2024, Argentina 69% mobile e-commerce) validates or challenges prior decisions. A standalone research doc without project context produces generic findings; a research doc that reads prior ADRs and planning docs first produces project-specific insights. **Rule: always read the project's existing research and decision docs before launching external research scouts. External findings without internal context produce generic advice; external findings cross-referenced against internal decisions produce actionable validation or challenge.**

### 54. The "mobile vs web" question is actually 3 separate questions

Users asking "should I launch mobile or desktop?" conflate three distinct decisions: (1) which platform to build first (mobile app vs responsive web), (2) what the design paradigm should be (mobile-first CSS vs desktop-first), and (3) when to add the second platform. Answering only #1 leaves #2 and #3 ambiguous and creates confusion — "web-first" sounds like it means "desktop-first design," but it shouldn't. The criteria framework must address all three explicitly. **Rule: when structuring platform strategy research, decompose the question into build-order, design-paradigm, and expansion-trigger. A recommendation of "web-first" must clarify that it means mobile-responsive web with mobile-first CSS, not desktop-only — and must include explicit trigger criteria for when to build the native app.**

### 55. Reconcile catches what back-propagate misses — and vice versa

Backlog #25 upgraded the challenger agent from Sonnet to Opus. `/back-propagate` updated spec docs (13, 14, 25) but missed the `/brana:challenge` SKILL.md description — because backprop focuses on specs (enter), not implementation files (thebrana). The subsequent `/brana:reconcile` caught it: specs said "Opus" but the skill still said "Sonnet." One command alone doesn't close the loop; running both in sequence does. **Rule: after any model/config change that touches both repos, run `/back-propagate` (impl→specs) then `/brana:reconcile` (specs→impl). Backprop updates what the spec docs say; reconcile updates what the implementation files say. Neither alone catches everything — they're complementary halves of a bidirectional sync.**

### 56. Uncommitted changes from previous sessions accumulate silently

Learnings #51-54 from a prior research session were left unstaged in `24-roadmap-corrections.md`. They survived because no conflicting branch touched that file region. But they could have been lost to a `git checkout`, overwritten by a merge conflict, or simply forgotten. `git status` showed them only because the current session's merge also modified the same file. **Rule: before ending any session that produces [doc 24](24-roadmap-corrections.md) entries, run `git status` and commit everything. Uncommitted learnings in the working directory are at risk of loss — they're not in git history, not in claude-flow memory, and invisible to the next session unless it happens to touch the same file.**

### 57. jq `!=` operator breaks under zsh — use alternative patterns

Running jq filters with `!=` in Claude Code's Bash tool on zsh causes syntax errors: zsh's history expansion escapes `!` to `\!`, producing `\!=` which jq can't parse. This happened twice in one session — once in an inline jq filter and once in a heredoc-style invocation. Workaround: use positive-logic alternatives like `select(.field // empty | . == "value")` instead of `select(.field != null)`, or `select(.field | IN("a","b") | not)` instead of `select(.field != "a")`. **Rule: when writing jq filters in Claude Code Bash calls, avoid `!=` entirely. Use positive-match patterns with `// empty`, `| not`, or `== null` negation. The zsh history expansion is invisible (no warning) and the jq error message points at `\!` which doesn't appear in the source — confusing to debug.**

### 58. Same-repo validation scripts drift independently on shared thresholds

`validate.sh` (deploy-time) and `pre-commit.sh` (commit-time) both enforce the context budget limit but hardcode it separately. When the budget was raised to 24,576 bytes in `pre-commit.sh`, `validate.sh` stayed at 23,552. Deploy failed with a confusing "budget exceeded" error even though the pre-commit had passed. This is a variant of lesson #46 (budget changes need propagation) but within a single repo — the threshold value has no single source of truth. **Rule: when two scripts in the same repo validate the same constraint, either extract the threshold to a shared config file (e.g., `BUDGET_LIMIT` in a sourced `.env`) or have one script derive the limit from the other. Two hardcoded copies of the same number will drift — it's not a question of if, but when.**

### 59. Exit code semantics depend on the consumer context

`staleness-report.sh` exited 1 when dep-stale findings existed — correct for a CI linter ("attention needed"), but wrong for a scheduler job ("job FAILED" → OnFailure notification → desktop alert every Monday). The same exit code meant different things to different consumers. After fixing to exit 0 on dep-stale (only truly stale docs trigger exit 1), the scheduler reports SUCCESS and the findings are captured in output/memory instead of exit code. **Rule: when writing scripts consumed by multiple systems (CI, scheduler, manual), design exit codes for the most sensitive consumer. For scheduler jobs, reserve non-zero for actual failures; use output, logs, or memory to surface informational findings — never exit codes.**

### 60. Challenger review compresses design scope by ~40% with zero functionality loss

The Personal Life OS design started with 7 moving parts. Challenger review eliminated 3 (scheduler job, portfolio entry, CLAUDE.md) — a 43% reduction with no feature loss. The eliminated parts were premature (no remote yet), procedural (happen naturally), or wouldn't auto-load (CLAUDE.md from other CWDs). This is the second clear data point after Phase 4's zero-rework execution. **Rule: for any design with >4 moving parts, run challenger review before implementation. Expect 30-50% scope compression, mostly from premature or procedural items.**

### 61. Budget-first calculation prevents rework on constrained additions

Before writing the /personal-check skill, the description was pre-calculated at 123 bytes against 405 bytes remaining. Final landing: 24,294/24,576 (282 remaining). No rework needed. In contrast, sessions without pre-calculation have required post-hoc description trimming. **Rule: for any new skill, calculate `current_budget + description_bytes` before writing code. The context budget is the binding constraint — check it first, not last.**

### 62. Edit-in-place before branching causes merge conflicts in worktree workflow

Twice this session, editing files in the main worktree (enter/) before creating the branch worktree caused "local changes would be overwritten by merge" errors. The fix is `git checkout -- files` before merging, but it's easy to forget. **Rule: when using the worktree workflow with files already modified in the main worktree, always run `git checkout -- <files>` in the main worktree immediately after copying them to the branch worktree — before you forget and hit the merge error.**

### 63. Backprop misses accumulate across sessions — functional thresholds worse than counts

Errata #52-54 documented budget number drift (counts going stale). But this session revealed a worse variant: [doc 35](dimensions/35-context-engineering-principles.md)'s instruction density warn threshold was 200 when the implementation used 150 — a functional spec error, not just a stale count. Budget amounts are informational; thresholds affect behavior. **Rule: when back-propagating, prioritize functional values (thresholds, limits, flags) over informational ones (counts, sizes). A wrong count is confusing; a wrong threshold causes wrong implementations.**

### 64. Untracked artifacts accumulate silently outside the deploy pipeline

`session-handoff.md` and `init-project` were created directly in `~/.claude/commands/` without source copies in `system/`. They worked fine but violated the single source of truth principle — any `./deploy.sh` run could have overwritten them (if it cleaned the directory), and they weren't version-controlled. The same pattern appeared with `docs/features/scheduler-hardening.md` and `system/skills/meta-template/SKILL.md` — shipped artifacts that existed in the working tree but were never `git add`ed. All four were discovered only because `git status` showed untracked files. **Rule: after creating any new artifact type or file outside the existing deploy pipeline, immediately (1) add the source path to `system/`, (2) add the deploy step to `deploy.sh`, (3) add the validation check to `validate.sh`, and (4) update CLAUDE.md's component table. Treat `git status` showing untracked files as a signal that something was created outside the pipeline.**

### 65. Parametric financial model scripts enable zero-effort cascade updates

TinyHomes commission changed from 10%→13%, then MP fee changed from 3.99%→1.49%. Each change required recalculating ~50 derived numbers across the financial model. A Python script (`/tmp/generate_financial_model.py`) with constants at the top (`COMMISSION_RATE=0.13`, `HOST_FEE=0.10`, `MP_FEE_PER_BOOKING=2.97`) regenerated the entire markdown document in seconds — both times. Without the script, each change would have been 30+ minutes of manual arithmetic with high error risk. **Rule: when a document contains >10 derived numbers from shared constants, generate it from a parametric script — not by hand-editing. Store the script alongside the output (or in `/tmp/` with a note in the doc footer). The second change is free; the third is free; the pattern pays for itself on the first recalculation.**

### 66. Cached project facts in MEMORY.md become liabilities the moment source data changes

This session changed TinyHomes commission from 10%→13%. If MEMORY.md had cached "commission: 10% (8% host + 2% guest)" it would have been silently wrong from that point forward. The user independently identified this: "why the memory? isn't it better to reference files where info is?" This led to trimming MEMORY.md from 86→38 lines and codifying the "reference, don't cache" principle in `rules/memory-framework.md`. **Rule: never cache project-specific facts (rates, stacks, endpoints, financial numbers, task status) in MEMORY.md. Store a pointer to the authoritative file instead. The cost of one Read call to get current data is trivial; the cost of acting on stale cached data can cascade through an entire session.**

### 67. Pre-commit hooks that parse structured text need structure-aware parsing

Enter's pre-commit Check 3 validates that staged doc numbers appear in CLAUDE.md. CLAUDE.md uses range notation (`09-13`) but the check uses `grep -q "12"` — literal string search that can't parse ranges. This forced `--no-verify` on a legitimate [doc 12](dimensions/12-skill-selector.md) edit during `/back-propagate`. The same class of bug would hit any validation that greps for values encoded in ranges, lists, or structured formats. **Rule: when a pre-commit check validates membership in a list, it must understand the list's actual format. If the list uses ranges, expand them before checking. If it uses comma-separated values, split them. `grep` is for flat text, not structured data — use `awk`, `python`, or bash range expansion for anything more complex.**

### 68. Agent sandboxing is hook-enforced, not platform-enforced — `bypassPermissions` bypasses it

Lesson #36 concluded "agents are sandboxed to their spawning repo's directory tree" after observing agents blocked from cross-repo writes. This session disproved it: 4 general-purpose agents spawned from thebrana CWD with `mode: bypassPermissions` successfully edited 6 files in `/home/martineserios/enter_thebrana/clients/tinyhomes-docs-notion-truth-audit/docs/notion/`. The original constraint was enforced by pre-tool-use hooks, not by Claude Code's runtime — `bypassPermissions` skips hooks entirely. **Rule: when planning parallel agent work across repos, use `bypassPermissions` mode for agents that need cross-repo write access. Default-mode agents are still blocked by pre-tool-use hooks. Lesson #36's "agents compose content → main context writes" pattern is still the safe default, but `bypassPermissions` is available when the work is well-scoped and the agent prompts are precise.**

### 69. Plan for ~20% leader gap-fill after parallel agent work

4 agents assigned to audit 6 docs completed ~80% of planned edits autonomously. The remaining ~20% (backfills, cross-doc consistency flags, commission rate fix) required leader intervention. The gap pattern was consistent: agents handled direct annotations (SIN FUENTE, CORREGIDO) well but missed some backfill insertions and cross-document cross-references. `git diff` immediately after agents went idle was the fastest way to identify gaps. **Rule: when parallelizing document edits across agents, budget a leader gap-fill phase. Check `git diff --stat` when agents go idle, compare against the plan checklist, and fill remaining items from the main context. Don't re-prompt agents for stragglers — it's faster to do 5-10 manual edits than to context-switch an agent back to a partially-done task.**

### 70. Cross-repo edits during a feature branch are invisible to that branch's git

While building `/brana:backlog status --all` on a thebrana feature branch, edits to `enter/30-backlog.md` (adding items #67-69) were lost when the thebrana branch auto-merged. Enter is a separate git repo — its working tree changes aren't tracked by thebrana's branch lifecycle. The edits had to be re-applied manually. **Rule: when a feature touches multiple repos (e.g., thebrana implementation + enter backlog), commit cross-repo edits immediately in their own repo before continuing work in the primary repo. Don't rely on "I'll commit it all at the end" — branch events (merge, hook, checkout) in the primary repo can reset the other repo's working tree.**

### 71. Challenger review is most valuable for SKILL.md instructions — not just code

The challenger caught a real schema inconsistency (bare array vs `{tasks: [...]}`) across portfolio clients that would have caused silent failures at runtime. For SKILL.md instructions (not code), the challenger also correctly identified that 3 flags was over-complex — Claude interpreting flag combinations is harder than code implementing them. The simplification from 3 flags to 1 reduced instruction ambiguity without losing capability. **Rule: run challenger review on SKILL.md instruction changes, not just code. The failure mode for instructions is ambiguity (Claude interprets differently each time), not bugs. Challengers catch ambiguity that the author can't see.**

### 72. Automated dual-mention audits catch what manual planning misses

A detailed plan specified exactly which handoff_context values to add to each agent's action file. Two values were missed: `greeting_no_clear_intent` in Agent 1 and `rejection_after_info` in Agent 2. Both existed in instructions.md but weren't listed in the plan's D3 edits. A Sonnet subagent running a systematic dual-mention audit (instructions vs actions) caught both in seconds. Manual plan authoring tends to miss values that appear in "obvious" code paths — the planner assumes they're already covered. **Rule: after editing instruction/action file pairs, run an automated dual-mention audit as a verification step. Don't rely on the plan being complete — cross-reference programmatically. A subagent with both files and clear instructions ("find every handoff_context value in instructions, verify it appears in actions") is the fastest approach.**

### 73. Parallel multi-file string-match edits scale reliably when old_string is unique

22 Edit tool calls across 7 files were executed in 2 parallel batches (11 + 9 calls) with zero failures. The key was ensuring each `old_string` was unique within its file — no ambiguous matches. For documentation files with repetitive structure (like action property tables), including 3+ surrounding context lines in `old_string` prevented false matches. This pattern — read all files first, design all edits with unique anchors, fire in parallel — is strictly faster than sequential read-edit cycles. **Rule: for multi-file documentation edits, design all edits upfront with unique `old_string` anchors (3+ context lines), then fire in parallel batches. Sequential read→edit per file wastes roundtrips when the edit targets are known in advance.**

### 74. Action prompt char limits need per-edit validation — budgets are tighter than they appear

Respond.io action prompts have a hard 1,000-char limit. Agent 3's Assign action hit 981/1000 after adding 4 new Cierre routing paths — leaving only 19 chars of headroom. The char limit wasn't part of the original plan's verification checklist; it was added as a parallel verification step during execution. At 98% utilization, any future edit to that action prompt will need to shorten existing text before adding new content. **Rule: when editing Respond.io action prompts, check char count immediately after editing — don't defer to a final audit. Include per-action char counts in the commit message or PR description so future editors know the budget state. Flag any action above 900 chars as "tight budget" in comments.**

---

## Reconcile Runs

### Reconcile Run — 2026-02-13

**Trigger:** manual (first run, testing `/brana:reconcile` command)
**Drift found:** 3 findings across 1 area (Deploy)
**Applied:** 0 auto-fixes
**Deferred:** 3 (aspirational spec claims about safety scripts)

| # | Area | Type | Finding | Resolution |
|---|------|------|---------|-----------|
| 1 | Deploy | Missing | `rollback.sh` described in [doc 17](17-implementation-roadmap.md) (Phase 0 exit criteria marks `[x]`) but doesn't exist in thebrana | Deferred — add to [doc 30](30-backlog.md) backlog |
| 2 | Deploy | Missing | `backup-knowledge.sh` described in [docs 17](17-implementation-roadmap.md) & 32 but backup logic lives in `brana-knowledge/backup.sh` | Deferred — spec should reference actual location |
| 3 | Deploy | Stale | `skill-catalog.yaml` described in [docs 12](dimensions/12-skill-selector.md) & 17 but implementation has `skill-catalog.md` (markdown, not YAML) | Deferred — format difference, nothing parses it yet |

**Notes:** First `/brana:reconcile` run. System is broadly in sync — 19 skills, 5 hooks, 8 rules, 7 agents, CLAUDE.md, settings.json, deploy.sh all match spec expectations. The 3 findings are low-materiality: aspirational safety scripts from [doc 17](17-implementation-roadmap.md)'s directory tree that were either deferred, implemented in a different location, or built in a different format.

### Reconcile Run — 2026-02-15

**Trigger:** post-maintain-specs (errata #47, #49 updated venture skill specs in [doc 29](reflections/29-venture-management-reflection.md))
**Drift found:** 3 findings across 1 area (Skills)
**Applied:** 3 auto-fixes
**Deferred:** 0

| # | Area | Type | Finding | Resolution |
|---|------|------|---------|-----------|
| 1 | Skills | Stale | `/growth-check` Step 1 says "Detect Stage" but spec now requires "Detect stage AND business model type" | Applied — updated heading, added model type prompt and adaptation guidance |
| 2 | Skills | Incomplete | `/growth-check` missing business model adaptation note (SaaS metrics misdiagnose non-subscription businesses) | Applied — included in Step 1 update |
| 3 | Skills | Incomplete | `/venture-align` missing framework stacking warning (max 3 layers, EOS Rocks + OKRs redundant) | Applied — framework discipline paragraph added after Phase 0 DISCOVER |

**Notes:** Focused reconcile after `/brana:maintain-specs` applied errata #47 and #49 to [doc 29](reflections/29-venture-management-reflection.md). All 3 findings were auto-fixable text updates to existing SKILL.md files. No new capabilities needed.

### Reconcile Run — 2026-02-18

**Trigger:** post-maintain-specs (errata #55 updated challenger model in [doc 08](reflections/08-diagnosis.md), #56 fixed stale refs in [doc 35](dimensions/35-context-engineering-principles.md))
**Drift found:** 1 finding across 1 area (Skills)
**Applied:** 1 auto-fix
**Deferred:** 0

| # | Area | Type | Finding | Resolution |
|---|------|------|---------|-----------|
| 1 | Skills | Stale | `/brana:challenge` SKILL.md says "Spawn a Sonnet subagent" (lines 3, 15) but challenger agent uses `model: opus` since backlog #25 | Applied — "Sonnet" → "Opus" in both description and body |

**Notes:** Clean reconcile. 31 skills, 10 agents, 8 hooks, 9 rules all match specs. Budget 22,404/23,552. The only drift was the /brana:challenge skill description not updated when the agent model was upgraded.

### Back-Propagation — 2026-02-23

**Trigger:** `/back-propagate` after adding `system/commands/` to thebrana deploy pipeline
**Docs updated:** 14 (directory tree + context composition), 17 (system tree)
**Finding:** Spec docs had no concept of `commands/` as an artifact type. The directory trees in [docs 14](reflections/14-mastermind-architecture.md) and 17 listed skills, agents, rules, hooks, and scripts but not commands. The context composition list in [doc 14](reflections/14-mastermind-architecture.md) didn't mention commands as an available-on-demand layer. All three gaps would lead an implementer to overlook commands when building or extending the deploy pipeline.

### Reconcile Run — 2026-02-23

**Trigger:** manual (after heavy session: errata #67 #70 fixes, back-propagation of directory trees, scheduler fix)
**Drift found:** 0 material findings
**Applied:** 0
**Deferred:** 0

| # | Area | Type | Finding | Resolution |
|---|------|------|---------|-----------|
| — | — | — | No material drift detected | — |

**Notes:** Clean reconcile. 34 skills, 10 agents, 10 rules, 9 hooks, 4 scripts all match specs. Budget 24KB enforced. Three informational items noted: (1) Extra hook scripts (post-sale, post-plan-challenge, post-tasks-validate, session-start-venture) exist in implementation but aren't individually described in spec — not material since spec describes hook types, not scripts. (2-3) CLAUDE.md header wording and "After Completing Work" section differ slightly from [doc 14](reflections/14-mastermind-architecture.md) description — semantically equivalent, no behavioral impact.

### Back-Propagation — 2026-02-25

**Trigger:** `/back-propagate` after respondio-prompts expansion, design thinking integration, Wave 1-4 implementation, workflow practice rules
**Docs updated:** 14 (budget reference ~24→~26KB, repo tree range 00-32→00-38), 35 (budget constraint 24,576→26,624 across all references, version history row)
**Finding:** `validate.sh` enforces 26,624 bytes since workflow practice rules were added, but [doc 35](dimensions/35-context-engineering-principles.md) still documented 24,576. [Doc 14](reflections/14-mastermind-architecture.md) repo tree said "00-32 spec docs" but docs now go up to 38 (design-thinking). Waves 1-4, agent roster, rules list, and skill count were already accurate in specs.
