# Harness Simplification Audit (t-1711)
**Date:** 2026-05-30
**Model context:** Claude Sonnet 4.6 / Opus 4.7 (claude-sonnet-4-6 at time of audit)

## Purpose

Identify harness components that were built to compensate for older model limitations but are now redundant given Claude 4's improved long-context coherence, implicit multi-step reasoning, and native task management.

---

## Candidates for removal/simplification

| Component | File | Current purpose | Why model handles it now | Confidence |
|-----------|------|-----------------|--------------------------|------------|
| `hallucination-detect.sh` | `system/hooks/hallucination-detect.sh` | PostToolUse Bash: detects "fix/done/complete" commit message keywords when no test files were modified — catches model lying about completeness | Sonnet 4.6 / Opus 4.7 are significantly less prone to completion hallucination, particularly around TDD discipline. The `tdd-gate.sh` already enforces test existence. This hook's regex parse of commit messages is brittle (can't parse heredocs reliably) and produces false positives. Its signal overlaps with the already-enforced TDD gate. | Medium |
| `guard-explore.sh` | `system/hooks/guard-explore.sh` | PreToolUse Read/Grep/Glob: logs when a Read call happens without a prior Grep/Glob (search-before-read discipline) | Currently **logging-only** (strict tier, Week 1 mode — never enforces). The file comment says "Week 2+: Optionally enforce." It never graduated. Modern Claude 4 models naturally search before reading implementation files — this behavior is now model-native, not a gap needing enforcement. It's dead code at standard tier. | High |
| `bash-output-compress.sh` | `system/hooks/bash-output-compress.sh` | PostToolUse Bash: compresses outputs >100 lines / >8000 chars by injecting a summary via additionalContext | The context budget rule and Claude 4's improved long-context handling reduce the need for this. Claude 4 models are better at ignoring/summarizing noisy output without this intermediary. More critically, compressing output via additionalContext can hide information Claude needs to diagnose failures — the cure is worse than the disease in many cases. | Low |
| `smart-router.md` Level 2 (LLM Classify) | `system/skills/_shared/smart-router.md` + `system/procedures/build.md:369-374` | Middle tier of 3-level strategy detection: fires an LLM classification prompt when signal matching fails | Opus 4.7's improved implicit reasoning means the model can classify strategy from task context without a separate inner-loop LLM prompt. Level 2 (LLM classify) is now just the model doing what it would do anyway. Level 1 (signal table) and Level 3 (ask user) remain valid. The 3-level framing can collapse to 2-level: signal → ask. | Medium |
| `subagent-context.sh` — decision log section | `system/hooks/subagent-context.sh` lines 58-72 | Injects last 3 decision log entries from `system/state/decisions/*.jsonl` into every subagent spawn | The directory `system/state/decisions` is referenced here but is not a documented decision-log convention in this repo. The code silently no-ops when the dir doesn't exist. The active task + branch injection (parts 1 and 2) is valuable; the decisions-log injection is dead infrastructure. | High |
| `preflight-model.sh` — model version string | `system/hooks/preflight-model.sh` | Warns "switch to standard Opus 4.6 or Sonnet 4.6" when extra-usage is disabled and a heavy skill is invoked | The warning text hardcodes "Opus 4.6" as the alternative. The current model is Sonnet 4.6 / Opus 4.7. The version string is stale and will confuse users. (Not a removal candidate — the check is still valid — but needs update.) | High (update, not remove) |
| `session-start.sh` — extra-usage warning | `system/hooks/session-start.sh` lines 149-154 | Warns at session start when `cachedExtraUsageDisabledReason` is set that "1M-context models fail at 200k" | Same stale model references as preflight-model.sh. Also: with Sonnet 4.6 as the default model (not 1M-context Opus), the 200k-token claim is incorrect for the standard context window. The warning logic is still structurally valid but the message text needs updating. | High (update, not remove) |

---

## Keep as-is (structural, not model workarounds)

| Component | Reason to keep |
|-----------|----------------|
| `pre-tool-use.sh` (spec-before-code gate) | Structural process gate — enforces SDD→TDD→impl order. Not a model limitation workaround; it's a discipline gate on the development lifecycle. ADR-031 explicitly mandates this. |
| `tdd-gate.sh` | Structural quality gate — blocks impl writes when no test infrastructure exists in the project. Independent of model capability; catches new-project cold-starts. |
| `feedback-gate.sh` | Structural routing gate — blocks direct writes to `feedback_*.md` legacy paths. Enforces the memory taxonomy (ADR-037). Model does not know the routing taxonomy by default. |
| `memory-write-gate.sh` | Structural routing gate — routes typed memory writes through `brana memory write` CLI (ADR-038). Enforces gateway pattern; model bypasses by default without it. |
| `plan-mode-gate.sh` | Structural conflict gate — prevents CC plan mode from racing with `/brana:build`'s step registry. Plan mode is a CC feature that genuinely conflicts with the build state machine. |
| `worktree-gate.sh` | Structural git discipline gate — prevents branch creation when dirty working tree or active worktrees exist (disk check, cross-session staging warning). These are environmental facts the model can't reliably detect. |
| `doc-gate.sh` | Structural commit gate — blocks behavioral file commits without co-staged documentation. This is a process rule (same-commit doc updates), not a model limitation. |
| `main-guard.sh` | Structural protection gate — blocks behavioral file commits on `main`. Independent of model capability; guards the branch convention. |
| `branch-verify.sh` | Structural git gate — blocks `git add` of behavioral files on `main`. Catches staging-time mistakes before `main-guard.sh` fires at commit time. |
| `branch-name-warn.sh` | Structural naming gate — enforces branch naming convention `{epic}/{work-type}/t-{NNN}-{slug}`. Model drift on naming is consistent across all versions. |
| `no-attribution-commit.sh` | Structural compliance gate — hard-blocks AI attribution trailers (Co-Authored-By, etc.). Has triggered in real sessions; model still adds these despite CLAUDE.md rules. Needs hook enforcement. |
| `commit-msg-verify.sh` | Structural accuracy gate — warns when commit message mentions files not in staged diff. Advisory; catches real drift (field note: commit f7b10bd). |
| `rust-skills-guard.sh` + `skill-sentinel.sh` | Structural skill-gate pattern — enforces `/brana:rust-skills` loading before Rust file edits. Not a model limitation; it's a skill prerequisite check. |
| `context-inject.sh` | Structural context enrichment — injects task context (from backlog) and file previews into UserPromptSubmit. The model can't pull this data without tool calls; the hook saves tokens and turn count. |
| `signal-capture.sh` | Structural feedback loop — captures explicit user ratings and negative signals to `ratings.jsonl` / `FAILURES/`. This is instrumentation, not a model limitation workaround. |
| `subagent-context.sh` (active task + branch parts) | Structural context propagation — subagents start with no awareness of the parent session's active task. The hook bridges that gap. CC Managed Agents (Opus 4.7 Auto Dream) may eventually provide this natively, but it's not available yet in CC's hook API. |
| `subagent-tracker.sh` | Structural observability — logs subagent spawn/stop events to session JSONL for metrics and debugging. No model capability substitutes for event logging. |
| `post-plan-challenge.sh` | Structural adversarial review trigger — nudges challenger agent after plan finalization. The challenger agent is a deliberate process step, not a model limitation workaround. |
| `post-pr-review.sh` | Structural PR review trigger — not fully read but fires on `gh pr create`; wires the `pr-reviewer` agent. Process hook, not a model limitation. |
| `task-completed.sh` | Structural pipeline automation — runs parent rollup, GitHub issue sync, and decision log on task completion. Orchestration logic that belongs in a hook, not inline model output. |
| `step-completed.sh` | Structural step registry — logs CC Task completions to session JSONL. Feeds the metrics/flywheel pipeline. |
| `post-tool-use.sh` | Structural session telemetry — logs tool outcomes to session JSONL. Powers correction rate, test-write rate, cascade detection. This is observability infrastructure. |
| `post-tool-use-failure.sh` | Structural failure telemetry — cascade detection, cross-session error recurrence tracking, rule-candidate escalation to ruflo. Catches real recurring problems. |
| `post-tasks-validate.sh` | Structural data integrity — validates `tasks.json` schema after every write. JSON corruption is a real failure mode; validation is structural. |
| `post-hooks-json.sh` | Structural reference regen — triggers `brana reference generate` when `hooks.json` or `SKILL.md` files are edited. Prevents doc drift (validated: field note 2026-05-19). |
| `memory-index-sync.sh` | Structural memory index sync — updates `MEMORY.md` pointer list when a typed memory file is written. Auto-index is structural; model won't do this inline. |
| `session-start.sh` | Structural session bootstrap — binary sync, task context injection, session handoff recap, ruflo pattern recall, drift detection, lint-heal gate, skill hints. This is high-value structural infrastructure; the model cannot perform these tasks at session start without consuming context budget. |
| `session-end.sh` | Structural session close — metrics computation, ruflo persistence, state sync, spec-graph update. These are post-session side effects that belong in a hook. |
| `config-change-guard.sh` | Structural security gate — blocks `ANTHROPIC_BASE_URL` manipulation (CVE-2026-21852). Security enforcement; not a model limitation. |
| `stopfailure-logger.sh` | Structural error logging — logs API-level failures (rate limits, auth errors) to persistent JSONL + Telegram alerts. Infrastructure logging. |
| `context-budget.md` rule | Structural guidance — context budget thresholds are objective measurements the model should act on. Not a model limitation; it's operational policy. |
| `delegation-routing.md` rule | Structural compute routing — who-runs-what decisions (Claude vs Gemini vs ruflo) are project conventions, not model limitations. |
| `skill-routing.md` rule | Structural workflow guidance — always-ask before invoking skills is a deliberate process gate. |
| `sdd-tdd.md` rule | Structural quality rule — TDD is a practice, not a model capability workaround. |
| `git-discipline.md` rule | Structural process rule — branch/commit/worktree conventions are project policies. |
| `universal-quality.md` rule | Structural quality standards — general engineering standards, not model limitations. |
| `parallel-bash.md` rule | Structural tooling guidance — CC's `|| true` requirement for parallel Bash is a platform behavior, not a model limitation. |
| `smart-router.md` Level 1 + Level 3 | Structural routing — signal table (deterministic) and ask-user (explicit confirmation) are good design regardless of model capability. Only Level 2 (LLM inner-loop classify) is redundant. |
| `guided-execution.md` shared skill | Structural resilience protocol — CC Task step registry survives context compression. This is a platform mechanism (CC Tasks), not a model limitation workaround. Remains valuable for M+ builds. |
| `delegation-tdd-checklist.md` shared skill | Structural delegation quality gate — an explicit checklist in agent delegation prompts enforces acceptance criteria that agents otherwise skip. Still needed. |

---

## Recommended next tasks

- **t-1711-A** `chore/t-1711-A-remove-guard-explore` — Remove `guard-explore.sh` from `hooks.json` and delete the file. It has been logging-only (strict-tier, never enforcing) since its creation. Zero enforcement value. Verify no tests reference it in `system/hooks/tests/`.
- **t-1711-B** `chore/t-1711-B-update-model-strings` — Update stale model version references in `preflight-model.sh` (line 66) and `session-start.sh` (line 152). Replace "Opus 4.6" with "claude-opus-4-7" / "claude-sonnet-4-6" per installed model IDs. Same-commit update to `docs/reference/`.
- **t-1711-C** `chore/t-1711-C-remove-dead-decisions-log` — Remove the dead `system/state/decisions/*.jsonl` injection block from `subagent-context.sh` (lines 58-72). The directory doesn't exist and the block silently no-ops. Reduces hook complexity.
- **t-1711-D** `research/t-1711-D-hallucination-detect-effectiveness` — Before removing `hallucination-detect.sh`, measure its true positive rate. Query `~/.claude/logs/` for sessions where the hook fired — check if warnings changed model behavior or were noise. If <10% true positive rate, proceed to remove. Medium effort spike.
- **t-1711-E** `chore/t-1711-E-smart-router-2level` — Collapse smart-router from 3-level to 2-level in both `smart-router.md` and `build.md:365-380`. Remove Level 2 (LLM classify inner loop). Level 1 (signal table) + Level 3 (AskUserQuestion) remain. Document the change in `docs/architecture/skills.md`.
- **t-1711-F** `research/t-1711-F-bash-output-compress-audit` — Audit sessions where `bash-output-compress.sh` fired. Measure: did compression hide information needed for failure diagnosis? If evidence shows more harm than good, file removal task. Low priority (advisory-only hook, no blocking behavior).

---

## Notes on Opus 4.7 Managed Agents

Opus 4.7 ships "Managed Agents with Auto Dream" per the task context. This may eventually reduce the need for `subagent-context.sh` (active task injection at SubagentStart) if CC's Managed Agent API propagates parent session context to subagents natively. Watch for CC changelog entries on SubagentStart context propagation. Until confirmed, keep `subagent-context.sh` as-is.

The 3-level smart-router pattern (Level 2 LLM classify) is the clearest casualty of improved implicit reasoning. Opus 4.7 performs the Level 2 classification inline during its response, making the explicit classification prompt loop an unnecessary token cost.
