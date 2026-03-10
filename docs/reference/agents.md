# Agent Reference

Complete reference for all 11 brana agents. Agents are specialized subagents that auto-delegate without a slash command. Definitions live in `system/agents/`.

## Agent Routing Table

| Agent | Model | Auto-Fires When | Read-Only |
|-------|-------|-----------------|-----------|
| memory-curator | Haiku | Starting work, familiar problem, stuck | Yes |
| client-scanner | Haiku | New client, client health check | Yes |
| venture-scanner | Haiku | New business project | Yes |
| challenger | Opus | Plan or architecture decision forming | Yes |
| debrief-analyst | Opus | End of implementation session | Yes |
| scout | Haiku | Research tasks (spawned by skills) | Yes |
| archiver | Haiku | Retiring a client | Yes |
| daily-ops | Haiku | Session start on venture project | Yes |
| metrics-collector | Haiku | `/brana:review` runs (weekly, monthly, check) | Yes |
| pipeline-tracker | Haiku | Pipeline tracking, deal events | Yes |
| pr-reviewer | Sonnet | PR creation (auto-triggered) | Yes |

All agents are read-only. They return structured findings to the main context. File modifications happen in main context after user approval.

---

## memory-curator

**Model:** Haiku
**Fires when:** Starting work on a topic, encountering a familiar problem, or when stuck.
**Not for:** Codebase search, project scanning, web research.

**Allowed tools:** Bash, Read, Glob, Grep
**Disallowed tools:** Write, Edit, NotebookEdit

**What it does:**
1. Searches claude-flow memory for relevant patterns using topic, project, and cross-project queries
2. Falls back to scanning `~/.claude/projects/*/memory/MEMORY.md` and portfolio.md when claude-flow is unavailable
3. Groups results by confidence tier: Proven (>= 0.7), Quarantined (0.2-0.7), Suspect (< 0.2)
4. Surfaces knowledge base results from brana-knowledge dimension docs

**Returns:** Structured pattern listing grouped by source (knowledge base, proven, quarantined, suspect) with confidence scores, recall counts, and transferability status.

**When to use vs not:**
- Use: before starting work on a topic to check if patterns exist
- Don't use: for searching code (use scout), for project diagnostics (use client-scanner), for web research (use scout or /brana:research)

---

## client-scanner

**Model:** Haiku
**Fires when:** Entering an unfamiliar client project or for project health checks.
**Not for:** Business stage classification, knowledge recall, web research.

**Allowed tools:** Bash, Read, Glob, Grep
**Disallowed tools:** Write, Edit, NotebookEdit

**What it does:**
1. Detects tech stack by reading manifest files (package.json, pyproject.toml, etc.)
2. Scans project structure (source layout, test dirs, config, CI/CD)
3. Runs 28-item alignment checklist across 6 groups:
   - Foundation (F1-F4): Git, CLAUDE.md, rules, conventional commits
   - SDD (S1-S5): docs/decisions/, ADR, PreToolUse hook, /decide, spec-first
   - TDD (T1-T4): Test framework, runner, tdd-guard, coverage
   - Quality (Q1-Q4): Linter, formatter, CI, security scanning
   - PM & Memory (P1-P5): Issues, patterns, portfolio, recall, MEMORY.md hygiene
   - Verification (V1-V3): Build passes, tests pass, hooks fire
4. Recalls relevant portfolio patterns from memory

**Returns:** Project scan with tech stack, alignment score (visual bars per group), prioritized key gaps, relevant patterns, and auto memory health status.

---

## venture-scanner

**Model:** Haiku
**Fires when:** First encountering a business project or for business health audits.
**Not for:** Tech stack assessment, daily operations, metrics collection.

**Allowed tools:** Bash, Read, Glob, Grep
**Disallowed tools:** Write, Edit, NotebookEdit

**What it does:**
1. Scans for business artifacts (docs/sops, docs/okrs, docs/metrics, decision logs)
2. Classifies business stage: Discovery, Validation, Growth, or Scale
3. Recommends stage-appropriate framework (Lean Startup for Discovery, EOS for Growth+)
4. Runs stage-cumulative gap analysis:
   - Foundation (all stages): F1-F4
   - Validation adds: V1-V4 (hypothesis, MVP, experiments, burn rate)
   - Growth adds: G1-G5 (OKRs, SOPs, meetings, hiring, decision framework)
   - Scale adds: S1-S5 (org chart, dept OKRs, automation, dashboard, onboarding)
5. Recalls venture-related patterns from memory

**Returns:** Venture scan with stage classification, framework recommendation, alignment score, prioritized gaps (critical/important/nice-to-have), and relevant patterns.

**Key rule:** Stage classification drives everything. Never recommend frameworks above the current stage.

---

## challenger

**Model:** Opus
**Fires when:** A significant plan or architecture decision is forming.
**Not for:** Data collection, project diagnostics, session debrief.

**Allowed tools:** Read, Glob, Grep
**Disallowed tools:** Write, Edit, Bash, NotebookEdit

**What it does:**
Adversarially reviews plans, architecture decisions, and approaches before commitment. Selects from four challenge flavors:

1. **Pre-Mortem:** "Assume this plan fails. What went wrong?" Identifies 3 most likely failure modes.
2. **Simplicity Challenge:** "What's the simplest version that still works?" Identifies unnecessary complexity.
3. **Assumption Buster:** "What assumptions is this plan making?" Lists and rates each assumption.
4. **Adversarial User:** "How would a real user break this?" Finds edge cases and confusion points.

**Returns:** Challenge report with findings classified as Critical (would block success), Warning (risk but manageable), or Observation (minor). Includes a verdict: PROCEED, PROCEED WITH CHANGES, or RECONSIDER.

**Key rules:** Be specific (cite exact steps, assumptions). Calibrate severity honestly. If the plan is solid, say so. Never modify files.

---

## debrief-analyst

**Model:** Opus
**Fires when:** End of an implementation session or when notable learnings emerge.
**Not for:** Adversarial review, project scanning, knowledge recall.

**Allowed tools:** Bash, Read, Glob, Grep
**Disallowed tools:** Write, Edit, NotebookEdit

**What it does:**
1. Gathers evidence from git log, diffs, reflog, and session event data (JSONL files)
2. Classifies findings into six categories:
   - **Errata:** Spec says X, reality is Y (with affected doc numbers)
   - **Process Learnings:** Reusable insights with confidence rating
   - **Issues:** Something broken, not a spec error
   - **Correction Patterns:** Repeated edits to the same file (retry loops)
   - **Cascade Patterns:** 3+ consecutive failures on the same target
   - **Test Coverage Gaps:** Implementation without corresponding tests
3. Applies confidence quarantine (new findings start low unless strong evidence)

**Returns:** Session debrief with all classified findings, counts per category, and a key insight summary.

**Key rules:** Be specific -- cite doc numbers, file paths, commit hashes. Don't inflate findings. Errata must cite which spec doc is wrong.

---

## scout

**Model:** Haiku
**Fires when:** Research tasks are spawned by skills (research, build, challenge).
**Not for:** Knowledge recall, project diagnostics, business analysis.

**Allowed tools:** Read, Glob, Grep, WebSearch, WebFetch
**Disallowed tools:** Edit, Write, Bash, NotebookEdit

**What it does:**
Fast research agent. Searches the codebase and web for information. Returns concise, structured findings.

**Returns:** Structured findings in 1,000-2,000 tokens. Reports what was found AND what was not found.

**Key constraints:** Cannot write files or run commands. Returns all findings inline in the agent result. Phase 1 scouts use WebSearch only (no WebFetch). Phase 3 scouts get max 2 WebFetch calls.

**When to use vs not:**
- Use: for parallel web research, codebase exploration, file finding
- Don't use: for knowledge recall (use memory-curator), for project diagnostics (use client-scanner)

---

## archiver

**Model:** Haiku
**Fires when:** Retiring a client.
**Not for:** Active project work, pattern recall, daily operations.

**Allowed tools:** Bash, Read, Glob, Grep
**Disallowed tools:** Write, Edit, NotebookEdit

**What it does:**
1. Gathers all project knowledge from claude-flow memory, MEMORY.md, portfolio.md, CLAUDE.md, and docs/decisions/
2. Categorizes each pattern:
   - **Transferable:** Confidence >= 0.7, not project-specific, worked reliably -- promote to cross-client
   - **Historical:** Project-specific but worth keeping for reference
   - **Deletable:** Low confidence, never validated, stale workarounds
3. Suggests portfolio.md updates

**Returns:** Archive report with categorized patterns, recommended actions (promote N, archive N, delete N), and portfolio update suggestions.

**Key rule:** When in doubt, classify as historical (safer than deleting).

---

## daily-ops

**Model:** Haiku
**Fires when:** Session start on a venture project.
**Not for:** Deep metrics analysis, pipeline management, project alignment checks.

**Allowed tools:** Bash, Read, Glob, Grep
**Disallowed tools:** Write, Edit, NotebookEdit

**What it does:**
1. Detects venture project artifacts
2. Pulls last health snapshot from docs/metrics/ and docs/reviews/
3. Checks pending action items and overdue follow-ups
4. Checks active experiment status
5. Queries claude-flow for historical metrics

**Returns:** Daily focus card with top 3 priorities, key metric + trend, blockers, overdue follow-ups, and active experiments.

**Key rules:** If no venture artifacts found, reports this and stops. Never fabricates metrics.

---

## metrics-collector

**Model:** Haiku
**Fires when:** `/brana:review` runs (weekly, monthly, or check).
**Not for:** Daily focus cards, deal-level analysis, general research.

**Allowed tools:** Bash, Read, Glob, Grep
**Disallowed tools:** Write, Edit, NotebookEdit

**What it does:**
1. Collects health snapshots from docs/metrics/
2. Collects experiment results from docs/experiments/
3. Collects pipeline data from docs/pipeline/
4. Collects financial data from docs/financial/ and monthly close reports
5. Queries claude-flow for historical data

**Returns:** Metrics collection organized by source (health snapshots, experiments, pipeline, financial) with trend data and a Data Gaps section listing missing metrics.

**Key rule:** Reports what exists and what is missing. Never fabricates data.

---

## pipeline-tracker

**Model:** Haiku
**Fires when:** Pipeline or deal-related work is happening.
**Not for:** Broad metrics aggregation, daily priorities, venture diagnostics.

**Allowed tools:** Bash, Read, Glob, Grep
**Disallowed tools:** Write, Edit, NotebookEdit

**What it does:**
1. Loads pipeline structure from docs/pipeline/
2. Reads individual deal records (stage, value, last activity, next action)
3. Identifies overdue follow-ups (past due date, or no activity in 14+ days)
4. Detects stage-stuck deals (Lead > 14d, Qualified > 7d, Proposal > 14d, Negotiation > 30d)
5. Computes conversion trends from closed deal records

**Returns:** Pipeline status with summary table (deals per stage + value), overdue follow-ups, stage-stuck deals, conversion trends, and recommended actions.

**Key rules:** Flag overdue items prominently. If conversion data is insufficient, say so rather than guessing.

---

## pr-reviewer

**Model:** Sonnet
**Fires when:** PR creation (auto-triggered).
**Not for:** Implementation, file editing, test writing.

**Allowed tools:** Read, Glob, Grep, Bash
**Disallowed tools:** Write, Edit, NotebookEdit

**What it does:**
1. Gets the PR diff via `gh pr diff`
2. Reads context files to understand the changes
3. Reviews against a 4-category checklist:
   - **Security (Critical):** Secrets, injection, unsafe deserialization, missing validation
   - **Logic (High):** Off-by-one, null handling, race conditions, swallowed exceptions
   - **Style & Convention (Medium):** Naming, dead code, missing error handling, inconsistency
   - **Completeness (Medium):** Missing tests, breaking changes, missing docs, untracked TODOs
4. Assigns a risk level: Low, Medium, or High

**Returns:** PR review with critical issues (must fix), suggestions (improve but not blocking), observations (informational), and a summary paragraph.

**Key rules:** Focus on the diff, not pre-existing code. Calibrate severity honestly. Uses `gh pr diff` and `gh pr view` only -- never write operations. If the PR is clean, a short "looks good" is valid.
