# Loop Engineering Repository — Complete Examples Catalog

**Repository:** https://github.com/cobusgreyling/loop-engineering  
**Cloned:** 2026-07-20  
**Scope:** ALL concrete loop examples, patterns, tools, and ecosystem

---

## 1. KNOWN 7 PRODUCTION PATTERNS (CORE)

### 1.1 Daily Triage
- **Name:** Daily Triage Loop
- **What:** Eliminates manual checking of CI, issues, PRs, and chat by surfacing prioritized, actionable signals each morning or sprint interval
- **Trigger/Schedule:** `/loop 1d` (morning) or `/loop 2h` (active sprints); GitHub Action cron `0 8 * * 1-5` (weekdays 8am)
- **Queue Drained:** CI failures (24h), open issues/tickets, recent commits, prior state file
- **Stop Conditions:**
  - Human decisions override loop actions
  - Ambiguous items flagged for human review
  - Items surface 3+ days without resolution → escalate
  - Design decisions, security, multi-file refactors → halt
- **Verifier (Maker/Checker):** Phase 1 (human reads STATE.md); Phase 2+ (sub-agent verifier confirms fix scope and tests before marking complete, never self-approval)
- **Autonomy Level:** L1 report-only (Phase 1); phased to L2 (Phase 2) with minimal fixes + verification
- **State/Memory:**
  - Central `STATE.md` tracking: last run timestamp, high-priority items with loop actions, watch list (stalled PRs), noise/ignored categories, post-run critique (false positives, repeated items, one improvement)
- **Code/Prompt Snippet Structure:**
  - Core skills: `loop-triage` (reads signals; produces prioritized findings), `minimal-fix` (optional Phase 2, drafts small fixes only), reviewer sub-agent (Phase 2, validates changes)
  - Grok Build: Use worktree + implementer + verifier for obvious bugfixes only
  - Claude Code: Report-only first week; defer auto-fix
  - Codex: Call `$loop-triage` daily; output to inbox + state
  - GitHub Actions: See `examples/github-actions/daily-triage.yml`
- **Cost Profile:** ~5k–200k tokens per run (no-op to assisted fix); suggested daily cap 100k tokens
- **Tool Coverage:** Grok, Claude Code, Codex, OpenClaw, Cursor, Windsurf, Opencode, Hermes, GitHub Actions

---

### 1.2 PR Babysitter
- **Name:** PR Babysitter Loop
- **What:** Reduce human time spent herding pull requests through review, CI, rebase, and merge while maintaining human judgment on all decisions
- **Trigger/Schedule:** `/loop 5m /pr-babysit check` (every 5–15 minutes during work hours); faster (2–5m) during active review; slower overnight sweeper runs
- **Queue Drained:** Open pull requests authored by team or on watched list, ordered by staleness and blocking status
- **Stop Conditions:**
  - Watchlist empty → loop self-terminates
  - Token budget exceeded → early exit required
  - PR merged or closed → pruned from state on next run
- **Verifier (Maker/Checker):** Separate verifier sub-agent confirms (1) changes address comment/failure, (2) no unrelated files touched, (3) tests/lint pass—before proposing merge
- **Autonomy Level:** L2 semi-autonomous (proposes, discovers issues, stages minimal fixes; never merges without explicit human approval or pre-approved allowlists)
- **State/Memory:**
  - Small markdown file (`pr-babysitter-state.md`) or Linear board tracking: PR ID, current status, last action taken, outcome, human overrides
- **Code/Prompt Snippet:**
  ```bash
  /loop 5m /pr-babysit check
  npx @cobusgreyling/loop-cost --pattern pr-babysitter --cadence 10m --level L1 --conservative
  ```
- **Implementation Notes:**
  - Use worktree isolation for fix attempts
  - Mark loop comments clearly ("🤖 Loop Engineering — PR Babysitter")
  - High-risk changes (auth, security, payments) always escalate to human
  - Limit rebase attempts per PR to prevent infinite loops
  - Target ~3k tokens for no-op runs; ~250k for full fix attempts
- **Cost Profile:** ~3k (no-op) to ~250k (full fix)
- **Tool Coverage:** Grok, Claude Code, Codex, OpenClaw, Cursor, Windsurf, Opencode, Hermes, GitHub Actions

---

### 1.3 CI Sweeper
- **Name:** CI Sweeper Loop
- **What:** Automated detection and minimal-fix proposal for CI failures on main/active branches, with circuit-breaker escalation to prevent looping
- **Trigger/Schedule:** 15m cadence during development, 5m when main is red; event-driven GitHub Actions `workflow_run` failure trigger; off-hours 30–60m acceptable; early exit required when CI is green
- **Queue Drained:** Failing jobs on watched branches (main, release/*, active PRs)
- **Stop Conditions:**
  - Same failure exceeds 3 attempts → escalate
  - Infrastructure issue detected → human handoff
  - Change touches >5 files or core architecture → escalate
- **Verifier (Maker/Checker):** Sub-agent validation checklist:
  1. Proposed fix addresses root cause (not symptom masking)
  2. Only relevant changes included
  3. Local test pass in worktree before PR opening
  4. Flake detection: if test passed on retry without code change, do not auto-fix
- **Autonomy Level:** L2 (propose fixes; cannot merge; human approval required)
- **State/Memory:**
  - `ci-sweeper-state.md` or `STATE.md` section tracking per failure: commit SHA, failing job name, attempt count (cap: 3), worktree/PR link, outcome (resolved/waiting/escalated); resolved entries pruned after 7 days
- **Code/Prompt Snippet (Grok Integration):**
  ```bash
  /loop 15m Check CI on main and open PRs. For new failures: classify, 
  and if actionable draft minimal fix in worktree with verifier. 
  Update ci-sweeper-state.md. Escalate after 3 attempts.
  ```
- **Implementation Notes:**
  - Loop-guard circuit breaker runs before each retry (`loop-context --check`)
  - Cost control: At 15m cadence without early-exit, worst-case spend exceeds 5M tokens/day
  - Flake classification prevents auto-fixing intermittent failures
  - Success metrics: mean time to first fix proposal post-failure, percentage of failures resolved autonomously (trivial cases only), repeat failure rate within 48h
- **Tool Coverage:** Grok, Claude Code, Codex, OpenClaw, Opencode, GitHub Actions (NOT Cursor, Windsurf, Hermes)

---

### 1.4 Dependency Sweeper
- **Name:** Dependency Sweeper Loop
- **What:** Identify and safely apply outdated/vulnerable dependency updates while escalating risky changes to humans
- **Trigger/Schedule:** 6–12 hours (or daily during business hours); on-demand triggers from Dependabot, OSV, or npm audit; pause conditions after N failed attempts on same package
- **Queue Drained:** Outdated/vulnerable dependencies from lockfile; ordered by severity
- **Stop Conditions:**
  - High/critical CVEs (even with patches available)
  - Lockfile changes affecting >N transitive dependencies
  - Packages on explicit denylist (auth, payments, core infrastructure)
  - Test or type-check failures in isolated worktree
  - After 2 failed attempts on same dependency in 24h
- **Verifier (Maker/Checker):** Always run verifier sub-agent (or explicit `npm test && npm run build`) in isolated worktree; never accept implementer declarations; include `npm audit` post-update to catch secondary vulnerabilities
- **Autonomy Level:** L2 semi-autonomous (applies patch-level updates and minor bumps with verification; escalates major versions, high-severity CVEs, breaking changes to human)
- **State/Memory:**
  - `dependency-sweeper-state.md` (compact log): package name, current→target version, risk classification, CVE links, resolution status, in-flight updates, last action timestamp, human decisions
- **Workflow:** Scan → triage (patch/minor/major grouping) → apply minimal fix → verify → propose PR
- **Cost Profile:** ~5k tokens (no-op), ~60k (triage), ~300k (patch+verify); suggest 500k daily cap
- **Tool Coverage:** Grok, Claude Code, Codex, OpenClaw, Cursor, Opencode, GitHub Actions (NOT Windsurf, Hermes)

---

### 1.5 Changelog Drafter
- **Name:** Changelog Drafter Loop
- **What:** Automates discovery of merged PRs and commits since last release, produces categorized draft release notes, routes to human review—eliminating manual changelog compilation
- **Trigger/Schedule:** `/loop 1d` (daily for active projects), manual trigger or webhook on release/tag events, weekly for slower-moving projects
- **Queue:** None specified; runs independently on a timer or event
- **Stop Conditions:**
  - No new merges since last release tag → exit early
  - Draft review backlog exceeds threshold (e.g., 3 unreviewed runs) → escalate to human
  - Scan window > ~50 items → human curates or splits release
- **Verifier (Maker/Checker):** Separate verifier skill (or human reviewer) validates:
  - Accuracy (no invented features)
  - Completeness (high-impact items not omitted)
  - Tone and project voice
  - Breaking changes, security notes, major bumps, marketing-heavy releases always require human eyes
- **Autonomy Level:** L1 proposal-only (scans, drafts, flags items; never publishes without explicit human approval)
- **State/Memory:**
  - `changelog-drafter-state.md`: last run timestamp, release tag, pending draft status and location, post-run critique (missed items, false positives, grouping errors, prompt adjustments)
- **Implementation Notes:**
  - Required skills: `changelog-scan`, `draft-release-notes`, `loop-verifier`
  - Extracts conventional commit types, labels (`breaking`, `security`), linked issues
  - Groups into: Features, Fixes, Performance, Breaking, Security, Docs, Chores
  - Cost: ~35k tokens (scan) + ~80k (draft+verify); ~100k daily cap recommended
  - Success metric: zero "surprise" user-facing items omitted from notes
- **Tool Coverage:** Grok, Claude Code, Codex, OpenClaw, Opencode, GitHub Actions (NOT Cursor, Windsurf, Hermes)

---

### 1.6 Post-Merge Cleanup
- **Name:** Post-Merge Cleanup Loop
- **What:** Systematically address follow-up work after code merges—deprecations, TODOs, tech debt, stale flags, doc gaps—without delaying merge velocity
- **Trigger/Schedule:** Event-driven (GitHub merge webhook) or time-based (1d/6h cadence, weekly for small teams); timing off-peak to avoid development interference
- **Queue Source:** Recent merges to main + linked tickets
- **Stop Conditions:**
  - Test suite failures → immediate human handoff
  - Large diffs (>10 files) → require human approval
  - Architectural debt or external API impacts → escalate
  - Loop has failed twice on same item → defer to ticket
- **Verifier (Maker/Checker):** "Cleanup must not alter behavior unless explicitly removing dead code paths." Verifier runs full test suite; regressions trigger escalation. Confirms no behavioral changes except intentional removals
- **Autonomy Level:** L2 (propose + verify minor fixes; escalate architectural decisions)
- **State/Memory:**
  - `post-merge-state.md` tracking: pending cleanup items (with source commit, risk/effort labels), completed work (last 14 days), deferred items requiring human decision
- **Implementation Notes:**
  - Scan diffs for `TODO`, deprecations, `// remove after`, feature flags
  - Prioritize: small + low-risk → worktree fix; large → ticket
  - Cap auto-PRs per day (~2)
  - Typical cost 40k–150k tokens per run
  - Daily token budget cap: 200k
- **Tool Coverage:** Grok, Claude Code, Codex, OpenClaw, Cursor, Opencode, GitHub Actions (NOT Windsurf, Hermes)

---

### 1.7 Issue Triage
- **Name:** Issue Triage Loop
- **What:** Continuously processes incoming issues, discussions, and feature requests to maintain a clean, prioritized backlog by deduplicating, assigning priority levels, suggesting labels without manual overhead
- **Trigger/Schedule:** 2h intervals or 1d (morning + end-of-day); GitHub Actions on `issues`/`discussion` events + scheduled fallback
- **Queue:** Open issues, discussions, optionally Linear/Jira tickets since last run
- **Stop Conditions:**
  - Context overload (> X new items in single run)
  - Issues touching security, auth, billing, or infra
  - Uncertain duplicate detection (>30% confidence threshold)
  - Stale items older than N days proposed for closure
- **Verifier (Maker/Checker):** Light or human review of "needs attention" bucket; sanity-checks proposed triage actions and label applications before execution. Escalates ambiguous deduplication and sensitive priority assignments
- **Autonomy Level:** L1 (report/propose mode); L2 can apply allowlisted labels only. Humans retain final say on P0/P1, security, auth, billing, infra
- **State/Memory:**
  - `issue-triage-state.md`: rolling backlog health snapshot—counts, top 5 prioritized items, flagged duplicates, timestamp of last run
- **Implementation Notes:**
  - Uses `issue-triage` skill (summarize, dedupe, extract signals) + `loop-verifier`
  - Never auto-labels or closes in L1
  - Feeds Daily Triage loop with actionable queue
  - Surfaces "possible duplicate" for human confirmation rather than auto-merging
- **Tool Coverage:** Grok, Claude Code, Codex, OpenClaw, Opencode, GitHub Actions (NOT Cursor, Windsurf, Hermes)

---

## 2. LOOP-INIT SCAFFOLD STRUCTURE

**Command:** `npx @cobusgreyling/loop-init . --pattern <pattern> --tool <tool>`

**Supported Patterns:** daily-triage, pr-babysitter, ci-sweeper, dependency-sweeper, post-merge-cleanup, changelog-drafter, issue-triage

**Supported Tools (with scaffold):**
- `grok` (default) — `.grok/skills/`
- `claude` — `.claude/skills/` + `.claude/agents/`
- `codex` — `.codex/skills/` + `.codex/agents/`
- `opencode` — `skills/` + `AGENTS.md`

**Tools Requiring Manual Copy:**
- `cursor` — copy skills + `STATE.md`; use Automations
- `windsurf` — copy skills + `STATE.md`; use Workflows
- `openclaw` — copy `skills/` + `STATE.md`; use `openclaw cron`

**Files Created by loop-init:**
1. **Pattern-specific state file:**
   - `daily-triage` → `STATE.md`
   - `pr-babysitter` → `pr-babysitter-state.md`
   - `ci-sweeper` → `ci-sweeper-state.md`
   - `dependency-sweeper` → `dependency-sweeper-state.md`
   - `post-merge-cleanup` → `post-merge-state.md`
   - `changelog-drafter` → `changelog-drafter-state.md`
   - `issue-triage` → `issue-triage-state.md`

2. **Core Documentation:**
   - `LOOP.md` — pattern description, cadence, limits, handoff
   - `loop-budget.md` — pattern-specific daily caps and kill switch
   - `loop-run-log.md` — append-only run history

3. **Skills Directory (per tool):**
   - `loop-triage` (triage & summarize)
   - `minimal-fix` (L2 patterns only)
   - `loop-verifier` (maker/checker validation)
   - Pattern-specific skills: `pr-review-triage`, `ci-triage`, `issue-triage`, etc.

4. **Circuit Breaker (Fix-Capable Patterns):**
   - `loop-guard` skill — logs each attempt to `loop-ledger.json` and runs `loop-context --check` before retrying
   - `loop-ledger.json` — seeded with pattern goal, pattern/level, empty attempts array

5. **Intake Skill (Underspecified Input Patterns):**
   - `loop-intake` — for `issue-triage` and similar, clarifies vague input one question at a time

6. **Agents/Configurations:**
   - Claude Code: `.claude/agents/` with agent definitions for skill invocation
   - Codex: `.codex/agents/` or automation tab configuration
   - Opencode: `AGENTS.md` + `opencode.json`

**Optional Enhancement:**
- `--with-foundry` flag scaffolds [harness-foundry](https://github.com/cobusgreyling/harness-foundry) stack:
  - `.foundry/stack.yaml` (declarative runtime)
  - Outerloop hook stub
  - Foundry README
  - Maps L1 patterns (daily-triage, issue-triage, changelog-drafter) to `minimal` preset
  - Maps L2 patterns (pr-babysitter, ci-sweeper, dependency-sweeper, post-merge-cleanup) to `implementer` preset

---

## 3. TOOL-SPECIFIC IMPLEMENTATIONS (EXAMPLES DIRECTORY)

### Tool Coverage Matrix

| Tool | Tools Supported | Path | Notes |
|------|-----------------|------|-------|
| **Grok Build TUI** | All 7 patterns | `examples/grok/` | Native `/loop` scheduling, full starter support |
| **Claude Code** | All 7 patterns | `examples/claude-code/` | Native `/loop` + `$skill` invocation |
| **Codex App** | All 7 patterns | `examples/codex/` | Automations tab for scheduling |
| **OpenClaw** | All 7 patterns | `examples/openclaw/` | Manual setup; uses `openclaw cron` |
| **Cursor** | Partial (5/7) | `examples/cursor/` | Missing CI Sweeper, Changelog Drafter, Issue Triage; uses Automations |
| **Windsurf** | Partial (2/7) | `examples/windsurf/` | Only Daily Triage + PR Babysitter; uses Cascade Workflows |
| **Opencode** | All 7 patterns | `examples/opencode/` | Cron/systemd + `opencode run` |
| **Hermes Agent** | Partial (2/7) | `examples/hermes/` | Only Daily Triage + PR Babysitter; manual trigger; channel delivery |
| **GitHub Actions** | All 7 patterns | `examples/github-actions/` | Workflow YAMLs; schema-complete, needs agent invocation wiring |
| **Gemini CLI** | Referenced | `docs/primitives-matrix.md` | Terminal-based loops via `gemini` + external scheduling |
| **Aider CLI** | Referenced | `docs/primitives-matrix.md` | CLI-first loops via cron + `--read` skills |
| **MCP Connectors** | All | `examples/mcp/` | Config example `loop-engineering.mcp.json`; reference server in `tools/mcp-server/` |

### Example File Naming Convention
- Tool-specific pattern implementation: `examples/<tool>/<pattern>.md`
- Example: `examples/grok/daily-triage.md`, `examples/claude-code/pr-babysitter.md`, `examples/github-actions/ci-sweeper.yml`

---

## 4. CLI TOOLS ECOSYSTEM

### 4.1 loop-init
- **Purpose:** Scaffold loop starters into any project by pattern and tool
- **Usage:** `npx @cobusgreyling/loop-init . --pattern <pattern> --tool <tool>`
- **Key Options:**
  - `--pattern` (required): one of 7 patterns
  - `--tool` (default: grok): grok | claude | codex | opencode
  - `--dry-run`: preview without creating files
  - `--with-foundry`: scaffold harness-foundry stack alongside loop files
- **Output:** Copy skills, create STATE.md, LOOP.md, loop-budget.md, loop-run-log.md; prints Loop Ready score

### 4.2 loop-audit
- **Purpose:** Score project's Loop Readiness (0–100) and suggest next steps
- **Usage:** `npx @cobusgreyling/loop-audit . --suggest`
- **Key Options:**
  - (default): human-readable output
  - `--json`: machine-readable
  - `--md`: markdown report
  - `--suggest`: copy-from-template commands + activity tips
  - `--badge`: markdown README badge (Loop Ready level + score)
- **Exit Code:** 2 if score < 40 (useful for CI gates)
- **Signals Checked:** state file, triage skill, verifier skill, LOOP.md/config, safety docs, workflows, MCP/connectors, worktree evidence, loop-budget.md, loop-run-log.md, activity proof, harness runtime presence

### 4.3 loop-cost
- **Purpose:** Estimate token spend for a loop at a given cadence and autonomy level
- **Usage:** `npx @cobusgreyling/loop-cost --pattern <pattern> --level <L1|L2|L3> --cadence <interval>`
- **Example:** `npx @cobusgreyling/loop-cost --pattern daily-triage --level L1 --cadence 1d`
- **Output:** Token estimate per run, daily cap recommendation

### 4.4 loop-context
- **Purpose:** Circuit breaker for L2+ loops; check if loop should escalate instead of retrying
- **Usage:** `npx @cobusgreyling/loop-context --check --ledger loop-ledger.json`
- **Exit Codes:** 0 (continue), 2 (escalate to human)
- **Breaker Trips On:** max iterations, same error repeating N× in a row, too many consecutive failures, token budget cap

### 4.5 loop-sync
- **Purpose:** Detect drift between STATE.md and LOOP.md before scheduling L2 loops
- **Usage:** `npx @cobusgreyling/loop-sync .`
- **Output:** Score (70+ healthy, 40–69 warning, <40 needs attention); warns about inconsistencies and suggests fixes

### 4.6 loop-worktree
- **Purpose:** Track isolated git worktrees for L2 fix attempts; prevent collisions
- **Usage:**
  - `npx @cobusgreyling/loop-worktree create --run-id <id> --pattern <pattern>`
  - `npx @cobusgreyling/loop-worktree mark --run-id <id> --status <rejected|escalated|approved>`
  - `npx @cobusgreyling/loop-worktree cleanup --older-than <24h>`
  - `npx @cobusgreyling/loop-worktree list`

### 4.7 loop-gate
- **Purpose:** Enforce safety constraints (denylist + auto-merge allowlist) mechanically
- **Usage:** `loop-gate check` from `gate.yaml` config
- **Applied In:** loop-engineering reference repo for safety validation

### 4.8 loop-mcp-server
- **Purpose:** Runtime MCP server for agents to query patterns, skills, state on demand
- **Usage:** `LOOP_PROJECT_ROOT=. npx @cobusgreyling/loop-mcp-server`
- **Config:** Copy stub from `examples/mcp/loop-engineering.mcp.json`
- **Resources:** Provides pattern registry, skill docs, state snapshots to MCP clients

---

## 5. CORE LOOP PRIMITIVES (8 PRIMITIVES)

### 1. Automations/Scheduling
- **Tools:** Grok (`/loop`), Claude Code (native `/loop` + schedule), Codex (Automations tab), Hermes (cron), Opencode (cron/systemd)
- **Concept:** Discovers and triages work on a cadence

### 2. Run-Until-Done
- **Implementation:** `/goal` commands (Grok, Claude Code, Codex) or bounded sessions with explicit stop conditions
- **Concept:** Keeps agents working until verifiable condition holds

### 3. Worktrees
- **Pattern:** `git worktree add` for safe parallel execution; isolation per session or per fix attempt
- **Tools:** All major platforms support; Devin provides implicit VM isolation per session

### 4. Skills
- **Storage:** `SKILL.md` files in tool-specific directories (`.grok/skills/`, `.claude/skills/`, `~/.hermes/skills/`, etc.)
- **Concept:** Persistent project knowledge, authored once, reused across runs

### 5. Plugins & Connectors
- **Standard:** MCP servers (standardized interface across nearly all tools)
- **Native:** GitHub, Slack, Linear, Jira integrations
- **Concept:** Reaches external tools and data sources

### 6. Sub-Agents
- **Pattern:** Maker/checker splits; specialized roles with restricted toolsets
- **Concept:** Implements verification and prevents self-approval

### 7. State/Memory
- **Storage:** Committed markdown files (`STATE.md`, pattern-specific state files) + platform-native memory
- **Concept:** Tracks progress across runs

### 8. Verification Split
- **Pattern:** Separate verification agents before acceptance
- **Concept:** Prevents unattended code changes from bypassing review

---

## 6. ANTI-PATTERNS & FAILURE MODES

### Anti-Patterns (10 Documented)

1. **Same Agent Implements and Verifies**
   - Problem: Confirmation bias allows weak tests to pass
   - Solution: Deploy separate verifier with default rejection stance

2. **No Attempt Cap**
   - Problem: Infinite fix cycles, token waste, incorrect solutions
   - Solution: Hard limit (e.g., 3 attempts) then escalate with context

3. **Vague Triage Output**
   - Problem: Loops cannot parse priorities; humans skip reading STATE.md
   - Solution: Structured markdown with single-line items and explicit `Suggested loop action` sections

4. **L3 Before L1 Quality**
   - Problem: Poor signal quality leads to widespread bad decisions and technical debt
   - Solution: Start report-only for week one; validate accuracy before advancing

5. **Shared State Without Schema**
   - Problem: Multiple loops append unstructured entries; state degradation
   - Solution: One state file per pattern or clearly demarcated sections with pruning rules

6. **MCP with Write-Everything Scope**
   - Problem: Single triage error cascades with enormous blast radius
   - Solution: Begin read-only; gradually expand permissions only after proving reliability

7. **No Kill Switch**
   - Problem: Alert fatigue, budget overruns, unmanaged incidents
   - Solution: Document pause/kill procedures in LOOP.md; use templates like `loop-budget.md.template`

8. **Fixing Flakes with Code Changes**
   - Problem: Masks underlying infrastructure issues; introduces unrelated diffs
   - Solution: Classify flakes → implement quarantine/retry logic → escalate infra issues separately

9. **Auto-Merge Without Allowlist**
   - Problem: Security and business-logic vulnerabilities slip through weak verifiers
   - Solution: Maintain explicit allowlist of safe paths; require human review for denylisted paths

10. **No Run Log**
    - Problem: Impossible to audit or debug decision history after incidents
    - Solution: Append each run to `loop-run-log.md` per operating-loops.md practices

### Failure Modes (3 Critical Scenarios with Severity)

1. **Infinite Fix Loop (S2 — Harmful)**
   - Scenario: Same PR or CI job gets automated fix attempts 5+ times; never converges
   - Root Cause: Weak verification, symptom-based fixes, flaky tests misclassified as regressions
   - Prevention: Hard-cap attempts at 3, use independent verification models, quarantine flaky tests

2. **State Rot (S1→S2)**
   - Scenario: State file tracks merged PRs, closed tickets, stale branches that no longer exist
   - Root Cause: Missing pruning steps, state not validated against live APIs
   - Prevention: Prune stale references on every run; timestamp state with API validation

3. **Verifier Theater (S2)**
   - Scenario: Verification passes but tests fail in CI or obvious bugs slip through
   - Root Cause: Vague verification prompts, skipped test execution, same model as implementer
   - Prevention: Run actual test/lint commands; use adversarial review posture; deploy stronger models

### Scope Issues

- **Over-Reach (S2→S3):** Refactor unrelated modules; enforce safety constraints, file allowlists, triage discipline
- **Token Burn (S1):** Avoid sub-minute cadence with heavy sub-agents, unnecessary retries, processing empty watchlists
- **Notification Fatigue (S1→S2):** Alert only on human decisions; use digest mode for reporting-only loops

### Long-Term Risks

- **Comprehension Debt Spiral & Cognitive Surrender (S2 cultural):** Mandatory human review prevents rubber-stamping; weekly digests and explicit quality gates preserve team ownership

---

## 7. STARTERS CATALOG

### L1 Report-Only Starters (Daily Triage)

| Starter | Tool | Path | Contents |
|---------|------|------|----------|
| minimal-loop | Grok | `starters/minimal-loop/` | `.grok/skills/` |
| minimal-loop-claude | Claude Code | `starters/minimal-loop-claude/` | `.claude/skills/` + `.claude/agents/` + `LOOP.md` |
| minimal-loop-codex | Codex | `starters/minimal-loop-codex/` | `.codex/skills/` + `.codex/agents/` |
| minimal-loop-opencode | Opencode | `starters/minimal-loop-opencode/` | `skills/` + `AGENTS.md` + `opencode.json` |

### L2 Assisted Patterns Starters (Shared Multi-Tool Skills)

| Starter | Pattern | Tools | Readiness | Path |
|---------|---------|-------|-----------|------|
| pr-babysitter | PR Babysitter | Grok, Claude, Codex | L2 assisted | `starters/pr-babysitter/` |
| pr-babysitter-opencode | PR Babysitter | Opencode | L1 → L2 | `starters/pr-babysitter-opencode/` |
| ci-sweeper | CI Sweeper | Grok, Claude, Codex | L2 cautious | `starters/ci-sweeper/` |
| ci-sweeper-opencode | CI Sweeper | Opencode | L2 cautious | `starters/ci-sweeper-opencode/` |
| dependency-sweeper | Dependency Sweeper | Grok, Claude, Codex | L2 patch-only | `starters/dependency-sweeper/` |
| dependency-sweeper-opencode | Dependency Sweeper | Opencode | L2 patch-only | `starters/dependency-sweeper-opencode/` |
| post-merge-cleanup | Post-Merge Cleanup | Grok, Claude, Codex | L1 → L2 | `starters/post-merge-cleanup/` |
| post-merge-cleanup-opencode | Post-Merge Cleanup | Opencode | L1 → L2 | `starters/post-merge-cleanup-opencode/` |
| changelog-drafter | Changelog Drafter | Grok, Claude, Codex | L1 draft → L2 | `starters/changelog-drafter/` |
| changelog-drafter-opencode | Changelog Drafter | Opencode | L1 draft → L2 | `starters/changelog-drafter-opencode/` |
| issue-triage | Issue Triage | Grok, Claude, Codex | L1 propose-only | `starters/issue-triage/` |
| issue-triage-opencode | Issue Triage | Opencode | L1 propose-only | `starters/issue-triage-opencode/` |

### Using Starters

```bash
# Copy directly
cp -r starters/minimal-loop ./your-project/.grok/skills/

# OR use loop-init
npx @cobusgreyling/loop-init . --pattern daily-triage --tool grok
npx @cobusgreyling/loop-audit .
npx @cobusgreyling/loop-audit . --suggest
```

---

## 8. LOOP-ENGINEERING REPOSITORY'S OWN LOOPS

**Self-Dogfooding Active Loops (as of 2026-07-10):**

1. **Daily Triage (L1)** ✅
   - Cadence: Weekdays via `daily-triage.yml`
   - Updates: `STATE.md` + `loop-run-log.md`
   - Skill: `loop-triage`

2. **Changelog Drafter (L1)** ✅
   - Cadence: Mondays or manual release-prep trigger
   - Output: `RELEASE_NOTES_DRAFT.md`
   - Described as "low-risk companion" to post-merge work

3. **Validate + Audit (L1)** ✅
   - Cadence: On every PR and push
   - Files: `validate-patterns.yml`, `audit.yml`
   - Purpose: Dogfood pattern validation; readiness scores on PRs

4. **Dependabot (L1)** ✅
   - Cadence: Weekly
   - Scope: `loop-audit` and `loop-init` npm packages + GitHub Actions
   - Config: `.github/dependabot.yml`

5. **Star History (L1)** ✅
   - Cadence: Daily
   - Output: Auto-generates PR updating star history data
   - Requires: `STAR_HISTORY_TOKEN` secret (personal access token)

**Paused/Partial Loops:**

6. **PR Babysitter (L2)** ⏸
   - Status: Manual trigger only; no Action yet
   - Starter: `starters/pr-babysitter` (Grok, Claude Code, Codex)

7. **Dependency Sweeper (L2)** ⏸
   - Status: Dependabot handles patches; full sweeper is manual
   - Starter: `starters/dependency-sweeper`

8. **CI Sweeper (L2)** ⏸
   - Status: Partial; reacts to failing audit runs but lacks dedicated retry workflow
   - Starter: `starters/ci-sweeper`

**Multi-Loop Coordination Priority (docs/multi-loop.md):**
1. CI Sweeper
2. PR Babysitter
3. Dependency Sweeper
4. Post-Merge / Changelog Drafter (off-peak)
5. Daily Triage (report)

---

## 9. PATTERNS BEYOND THE KNOWN 7 (IF ANY)

**Finding:** The repository documents **exactly 7 canonical production patterns** with no additional major patterns beyond these. However:

### Extended Ecosystem (Companion Systems, Not Standalone Patterns)

1. **memory-engineering** (referenced companion project)
   - Persistent state management for loops
   - Integrates with loop STATE.md

2. **harness-foundry** (referenced companion project)
   - Versioned runtime stacks and tracing
   - Declarative loop execution, outerloop hooks
   - `loop-init --with-foundry` scaffolds integration
   - Presets: `minimal` (L1 patterns), `implementer` (L2 patterns)

3. **outerloop** (referenced system)
   - Governance and verdict systems
   - Integrates with harness-foundry

4. **fleet-engineering** (referenced system)
   - Multi-agent population management
   - Coordinates multiple loop instances

5. **goal-engineering** (referenced system)
   - Goal discovery and completion
   - Enhances loop `/goal` semantics

### No Standalone Novel Patterns Found

The repository does **not** document additional loop patterns beyond the 7 core ones. All 7 patterns are:
- Fully specified in `patterns/` directory
- Implemented across multiple tools in `examples/`
- Scaffoldable via `loop-init`
- Auditable via `loop-audit`

---

## 10. DOCUMENTATION STRUCTURE & REFERENCE

### Core Specification Files

| File | Purpose |
|------|---------|
| `LOOP.md` | How loop-engineering repo operates itself (dogfooding) |
| `patterns/README.md` | Pattern registry and how to use patterns |
| `patterns/registry.yaml` | Machine-readable pattern index |
| `docs/primitives.md` | 8 core loop primitives explained |
| `docs/primitives-matrix.md` | Primitive implementation across tools (Grok vs Claude vs Codex vs OpenClaw vs Opencode vs Cursor) |
| `docs/pattern-picker.md` | Interactive tool selection guide |
| `docs/loop-design-checklist.md` | Production readiness rubric |
| `docs/failure-modes.md` | Incident-style catalog of issues |
| `docs/anti-patterns.md` | Design mistakes to avoid (10 documented) |
| `docs/loop-init-validation.md` | Validated pattern × tool matrix |
| `docs/operating-loops.md` | When to kill a loop |
| `docs/multi-loop.md` | Coordinating multiple loops |
| `docs/safety.md` | Unattended automation risk protocols |
| `docs/architecture-diagrams.md` | Actor sequences and lifecycle states |
| `docs/concepts.md` | Foundational concepts |
| `docs/RELEASE.md` | Release process and npm publish tags |
| `stories/` | Real-world case studies and failure narratives |

### Key Tool Directories

| Directory | Purpose |
|-----------|---------|
| `tools/loop-init/` | Scaffolding CLI + package publish |
| `tools/loop-audit/` | Readiness scoring CLI |
| `tools/loop-cost/` | Token budget estimation |
| `tools/loop-context/` | Circuit breaker for retries |
| `tools/loop-sync/` | STATE.md ↔ LOOP.md drift detection |
| `tools/loop-worktree/` | Isolated worktree tracking |
| `tools/loop-gate/` | Safety constraint enforcement |
| `tools/mcp-server/` | MCP runtime server (patterns/skills/state on demand) |

### Starters & Examples

| Directory | Purpose |
|-----------|---------|
| `starters/` | Clone-and-run scaffolds by pattern and tool |
| `examples/` | Tool-specific pattern implementations (Grok, Claude, Codex, OpenClaw, Cursor, Windsurf, Opencode, Hermes, GitHub Actions) |
| `resources/` | Reference materials and external sources |
| `templates/` | Reusable skill templates (pattern-template.md, skill templates) |

---

## 11. QUICKSTART SUMMARY

### The Week-One Flow (from docs/QUICKSTART.md)

1. **Pick pain** (30s) → Choose pattern via [pattern picker](https://cobusgreyling.github.io/loop-engineering/#interactive) or start with Daily Triage
2. **Scaffold** (60s) → `npx @cobusgreyling/loop-init . --pattern daily-triage --tool grok`
3. **Check cost** (30s) → `npx @cobusgreyling/loop-cost --pattern daily-triage --level L1 --cadence 1d`
4. **Audit readiness** (30s) → `npx @cobusgreyling/loop-audit . --suggest` (target ≥80 for harness-foundry)
5. **Run report-only** (2m) → `/loop 1d Run loop-triage...` (no auto-fix in week one)
6. **Read output & commit** (1m) → Review STATE.md, commit scaffold + first run

### Progression Path

- **End of week one:** Re-run audit, aim for L1 (score ~40+)
- **Week two:** Add verifier skill; try one assisted fix in worktree (L2)
- **Before unattended (L3):** `loop-budget.md` + `loop-run-log.md` filled, human gates in `LOOP.md`, proven runs
- **Optional harness runtime:** When score ≥80, wire to harness-foundry: `npx @cobusgreyling/loop-init . --with-foundry`

---

## 12. MCP INTEGRATION

### MCP Server (loop-mcp-server)

**Purpose:** Runtime lookup for patterns, skills, state on demand (instead of stuffing docs into every prompt)

**Config:** Copy stub from `examples/mcp/loop-engineering.mcp.json`

**Usage:**
```bash
LOOP_PROJECT_ROOT=. npx @cobusgreyling/loop-mcp-server
# Or from cloned repo:
cd tools/mcp-server && npm ci && npm run build
LOOP_PROJECT_ROOT=/path/to/project node dist/index.js
```

**Provides:**
- Pattern registry queries
- Skill documentation
- State file snapshots
- Validation rules

---

## 13. VALIDATION & TESTING

### loop-init Validation Matrix

Documented in `docs/loop-init-validation.md`: which pattern × tool combinations are validated/implemented vs manual setup required.

### Before-After Demo

Script: `bash scripts/before-after-demo.sh` — shows scores climbing from empty → L1 starter → L2 verifier

---

## SUMMARY: WHAT EXISTS BEYOND THE 7 PATTERNS

**Finding:** The loop-engineering repository is **tightly focused on the 7 core production patterns** with NO additional standalone loop patterns documented. Beyond the 7:

1. **Tool-specific implementations of the same 7 patterns** (9 tools covered, different levels of support)
2. **Companion systems** (memory-engineering, harness-foundry, outerloop, fleet-engineering, goal-engineering) that **integrate with** the 7 patterns but are not standalone patterns themselves
3. **Anti-patterns and failure modes** (10 anti-patterns, 3 critical failure scenarios) documented to teach what NOT to do
4. **Ecosystem tools** (loop-init, loop-audit, loop-cost, loop-context, loop-sync, loop-worktree, loop-gate, loop-mcp-server) that **enable** the 7 patterns but are not patterns themselves

The repository practices **extreme discipline**: every pattern is specified, every pattern is scaffoldable, every pattern is auditable, every pattern is implementable across multiple tools. No pattern ships half-baked or unvalidated.

---

**END OF COMPREHENSIVE NOTES**
