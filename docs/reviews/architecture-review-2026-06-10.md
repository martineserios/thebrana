# Architecture Review — 2026-06-10

> Full-system review of the brana harness. Method: three-pass (INTENT → REALITY → JUDGMENT), with the REALITY pass run as seven parallel read-only reviewers (rules, hooks, skills, agents/procedures, CLI/scheduler/state, memory/ruflo, portability), each judging against four axes: context/token cost, maintenance burden, reliability, design coherence. Operator-confirmed priorities: (1) the system must learn itself by doing, (2) make it public and portable so people can contribute. Scope: `system/`, `.claude/`, `docs/architecture/`, `docs/conventions/`. Reviewer: Claude (Fable 5), checkpointed with operator after INTENT pass.

## 1. What this system is

Brana is a personal operating system for a one-person software portfolio, built as a Claude Code harness. Its founding bet: an AI agent's work products — corrections, decisions, test results, session events — can be captured, persisted, and recalled so that the agent compounds in capability across sessions instead of starting from zero. Around that bet sit three concentric structures: a **discipline shell** (hooks and rules that physically block undisciplined work — spec-first, test-first, branch hygiene, no commits to main), a **workflow library** (47 skills and procedures encoding how the operator decides, researches, builds, ships, maintains, and grows), and a **memory organism** (ruflo's semantic database plus native memory plus flat-file pattern libraries, fed by a session-end flywheel that computes learning metrics).

What it is *trying* to be is ambitious and ahead of its time: not a config folder but a **self-improving exocortex** — the six-job taxonomy (ADR-029) organizes by operator intent rather than tool category, the gate-design rule ("does bypassing this corrupt an unrepairable invariant?") is a real engineering principle, and the validate.sh immune system means the harness checks its own structural integrity. The Rust CLI as the single sanctioned state interface is a decision many teams get wrong.

The review's central diagnosis cuts directly against the operator's top priority. **The system writes everything and reads almost nothing.** Across 6,259 rows in ruflo's memory DB, the high-value namespaces — 4,029 knowledge rows, 836 sessions, 700 patterns, 527 flywheel metric records — show `access_count = 0` and `last_accessed_at = NULL` on essentially everything. The flywheel computes seven learning metrics every session end and nothing ever consumes them. Agents declared with `memory: true` have nowhere to write — `~/.claude/agent-memory/` doesn't exist. The learning loop is half a loop: a ratchet that stores, not a flywheel that spins. The system *does*; it does not yet *learn from doing*.

The second structural truth: the system has grown past one person's maintenance capacity, and it knows it — it self-audited ten days before this review (t-1711) and most of the verdicts are still unacted. 14,320 lines of bash across 46 hooks. A 2,167-line validator with 59 checks that currently "passes" with **243 warnings** — the immune system has alert fatigue. 627KB of procedures, four of them over 1,000 lines. The dominant failure mode everywhere is the same: **polite, silent failure** (`set +e`, WARN-instead-of-FAIL, a scheduler job dead since June 9 with nobody alerted). For a system whose purpose is learning from its own behavior, silent failure is the one disease it cannot afford — it cannot learn from failures it never sees.

## 2. What is genuinely good — protect these

**The enforcement gate layer is the crown jewel.** `system/hooks/pre-tool-use.sh` (spec gate), `tdd-gate.sh`, `main-guard.sh`, `no-attribution-commit.sh` — 10 blocking gates, all syntactically clean, all wired, all firing. This is the part of brana that *cannot be replicated by prompting* — it is structural, not advisory. The gate-design principle in the docs is publishable thinking on its own.

**The Rust CLI and state isolation actually hold.** 26.7K LOC, compiles clean, 21 subcommands matching docs, and — verified by grep across all hooks and procedures — *nothing* writes `tasks.json` directly. The single-interface invariant is real, not aspirational. `system/state/schema-removals.json` (deleted fields can never silently return) is a genuinely clever regression guard.

**The scheduler runs.** 28 jobs, 30-day rolling logs, daily state sync committing on schedule. `brana doctor` reports 9/9 healthy.

**The challenger ecosystem is justified complexity.** Agent + calibration rubric + post-plan hook + council-mode skill looks accreted but reviews as four distinct, legitimate workflows (`system/agents/challenger.md`, `CALIBRATION.md`).

**The ruflo wrapper hardening.** flock mutex (commit b227ca4f) added after two real SQLite corruption events (2026-04-06, 2026-06-07), 14-day rolling backups, corruption recovery. Mature ops work.

**Rules budget discipline.** 18.5KB of 28KB always-loaded cap (64%), enforced at write time by validate.sh Check 5a with the opt-in `always-load:` contract.

## 3. What is too much

**The hooks layer is a second codebase.** 14,320 lines of bash for 46 scripts — half the size of the entire Rust CLI, in the least testable, least typed language in the system. Within it: `guard-explore.sh` (108 LOC, orphaned, never wired, t-1711 said delete — still present), `hallucination-detect.sh` and `bash-output-compress.sh` (flagged 2026-05-30, still wired 2026-06-10; the latter suspected by the system's own audit of *hiding diagnostic info Claude needs*). The 17 observability hooks feed the write-only memory described below — a large fraction of this bash exists to produce data nothing consumes. **Axis: maintenance burden — HIGH.**

**validate.sh has become an organism of its own.** 2,167 lines, 59 checks, ~45s runtime, and a passing state that tolerates 243 warnings — including Check 48 reporting 14 hooks.json↔hooks.md mismatches as WARN. A validator that always passes is a validator nobody reads. **Axis: reliability + maintenance — HIGH.**

**Four giant procedures defeat the model that executes them.** `build.md` 1,996 lines, `close.md` 1,371, `backlog.md` 1,209, `reconcile` also >500 — all far past what a model reliably follows. The recurring Read failures in session logs (45× close, 6× backlog, 5× build) cluster exactly on the giants. The close failure is the worst: session-end learning extraction silently breaks → the learning loop loses its input. **Axis: reliability — HIGH.**

**Five always-relevant rules govern "how to start work," with no precedence.** `skill-routing.md` (ask first) vs `delegation-routing.md` (route first) vs `task-convention.md` (read tasks.json first) vs `backlog-start-gate.md` vs `lifecycle-gate-assessment.md`. Three claim to be first. Accumulated scar tissue from individual corrections, never consolidated. **Axis: coherence — HIGH.**

**The memory topology exceeds curation capacity.** Seven distinct layers where a learning can live: ruflo DB (22 namespaces), its backups, HNSW index, four flat files in `~/.claude/memory/`, 1,428 project memory dirs, the brana-knowledge repo, and `.claude-flow/` state. The fragmentation is *why* the read side broke: no caller can know where to look, so callers don't look. **Axis: coherence + maintenance — HIGH.**

**~30 of 46 scripts in `system/scripts/` are wired to nothing**, and `system/procedures/` mixes skill entry points with domain-knowledge articles with no deprecation flow (orphan: `migrate.md`). **Axis: maintenance — MEDIUM.**

## 4. What is broken or drifting

**The flywheel is observability theater.** All 527 `flywheel:*` rows have access_count=0; `session-end-persist.sh` lines 50–110 swallow Layer-1 failures non-fatally. The docs' centerpiece loop — recall → log → metrics → improved recall — is true on the left half only.

**Agent memory never existed.** 11 of 14 agents declare `memory: true`; `~/.claude/agent-memory/` is absent. challenger, debrief-analyst, pr-reviewer have been amnesiac since birth, every run.

**Session recall is gated by an invisible threshold.** Session rows score a constant 0.5; `.mcp.json` instructions require `threshold: 0.55` — naive queries return empty *by design* (observed: `client:enter_thebrana` → `[]` at session start), and callers don't know the rule. Working as coded, broken as experienced.

**feed-ruflo-index has been failing since 2026-06-09** — `EACCES` spawning ruflo from the nvm path (`~/.claude/scheduler/logs/feed-ruflo-index/2026-06-09-191720.log`), surfaced only as an emoji in `brana ops status`. New knowledge is not being indexed.

**t-1711 drift:** the audit's removal verdicts are 10 days unexecuted; meanwhile it was *wrong* about subagent decision-log injection being dead — `system/state/decisions/` is alive with 400 entries, written daily… which, in turn, nothing reads. Even the decision log is write-only.

**Deployment drift:** `system/rules/reconcile-after-convention-change.md` exists in repo, absent from `~/.claude/rules/` — bootstrap hasn't propagated. A non-standard `alwaysApply:` field in `backlog-start-gate.md` is recognized by nothing.

**Skill count drift:** docs say 24, then 27; reality is 33 + 14 acquired = 47.

## 5. Strategic options

Two operator-stated desires: *the system should learn itself by doing*, and *make it public so people can contribute*. They point the same direction.

### Option A — Close the loop (heal in place)
Fix the read side: a recall step that actually queries patterns at task start with correct thresholds; make session-end consume last session's metrics and surface one insight; create agent-memory; convert silent failures to loud ones (validate.sh warns→fails, scheduler alerts). Cull what t-1711 already condemned.
**Wins:** directly serves "learn by doing"; smallest effort to restore the founding promise. **Sacrifices:** doesn't touch the bash sprawl or portability. **Evidence:** every "broken" finding above is on the read path — this is surgery on one organ.

### Option B — Extract the publishable core (shrink by shipping)
The portability audit found a clean 60/40 split: hooks, rules, 21 generic skills, 6 generic agents, the CLI, bootstrap and validate (after env-var refactor) are publishable; `system/state/`, `system/scheduler/`, `acquired/` skills, 8 venture agents, 207 hardcoded-path hits, 707 client-name hits are not (zero secrets found; git history needs one audit). Restructure as **public plugin + private overlay**: the OSS repo is the harness; ventures/clients/personal becomes a separate private plugin depending on it.
**Wins:** portability solved *structurally* (personal data can't leak into the public artifact again); contributors share the bash maintenance; publishing forces the deferred simplification. **Sacrifices:** 4–6 weeks of packaging instead of building; two-repo discipline.

### Option C — Collapse onto the 2026 platform
Claude Code now natively does much of what brana hand-rolled in 2025: memory directories, task tools, Explore agents, CronCreate/schedule, workflows. Keep gates + CLI + ruflo; delete custom memory flat-files, scheduler skill, sitrep, most observability hooks.
**Wins:** ~40% less surface. **Sacrifices:** the cross-client semantic learning layer — the one thing the platform doesn't give and the soul of the project. **Caution:** the parts duplicating the platform mostly work; the part the platform can't replace is the broken part. C fixes the wrong problem.

### Recommendation: A then B, as one program

Close the loop first (2–3 focused sessions): recall-at-task-start, metrics consumption, agent-memory, loud failures, plus the t-1711 culls and the three giant-procedure splits as the down payment on simplification. *Then* extract the public core, with the working learning loop as the flagship feature — "a Claude Code harness that provably learns from its own sessions" is a compelling OSS pitch; a write-only one is not. B without A publishes the aspiration; A without B leaves one person alone with 14K lines of bash forever.

## Appendix A — one-line findings

- `context-budget.md` and `self-improvement.md` rules partially restate native CC behavior — trim, don't delete (LOW).
- No-attribution's 3-layer enforcement reviewed as justified, not redundant (INFO).
- `/brana:do` vs `build` vs `fix` vs `backlog start`: four entry points to "start work" (MEDIUM; folds into rules consolidation).
- `/brana:scheduler` and `/brana:memory` overlap native CronCreate / native memory — deconflict in docs (LOW).
- hooks.json↔settings.json split survives only because CC bug #24529 status is untracked — re-check (LOW).
- `cwd-discipline`, `specify-check-ids`, `field-note-routing` reviewed as legitimate defenses, not scar tissue (INFO).
- 1,428 project memory dirs unsampled — likely mostly empty (UNCERTAIN).
- ruflo upstream (`ruvnet/claude-flow`, npm `ruflo@3.10.40`) is active and healthy; brana uses a small, sane subset of its surface (INFO).
- Challenger flavor-selection logic duplicated between `/brana:challenge` skill and `challenger.md` agent — extractable to shared doc (LOW).
- Skill SKILL.md→procedure references: 0 broken paths; the Read-failure pattern correlates with procedure size, not bad paths (INFO).

## Appendix B — evidence numbers (REALITY pass, 2026-06-10)

| Layer | Key numbers |
|---|---|
| Rules | 29 repo / 28 deployed (1 drift); 14 always-load, 18,561 bytes of 28KB cap (64%); ~146 directives; 5 overlapping work-start rules |
| Hooks | 46 scripts, 14,320 LOC bash; 39 wired (10 blocking, 9 advisory, 17 observability), 7 orphaned/indirect; est. 300–500 tokens/session injection (unbudgeted in context-budget.md) |
| Skills | 33 core + 14 acquired = 47; SKILL.md stubs 34.6KB; procedures ~627KB across 47 files; 8 procedures >500 lines, 4 >1,000 (build 1,996; close 1,371; backlog 1,209); 0 broken references; 1 orphan procedure (migrate.md) |
| Agents | 14 (+1 calibration doc), 88KB; 11 declare `memory: true`, `~/.claude/agent-memory/` does not exist; 3 hook auto-nudges; no registry duplication |
| CLI/state | 26.7K LOC Rust (17,676 cli + 8,997 core), compiles, 21 subcommands match docs; validate.sh 2,167 LOC / 59 checks / ~45s / 0 errors + 243 warnings; 400 decision-log entries (write-only); scheduler 28 jobs, 1 failing (feed-ruflo-index, EACCES since 06-09) |
| Memory | ruflo DB 6,259 rows / 22 namespaces (knowledge 4,029, session 836, pattern 700, metrics 527, skills 50) — access_count=0 across high-value namespaces; 7 distinct memory layers + 1,428 project dirs; flock mutex deployed 2026-06-07 after 2 corruption events; 14-day backups working |
| Portability | 207 hardcoded personal-path hits; 707 client/venture-name hits in `system/`; 0 secret-pattern hits; ~60% generic / 40% personal by LOC; publishable core = hooks + rules + 21 skills + 6 agents + CLI + refactored bootstrap/validate |

**Bottom line:** the discipline shell is excellent and rare; the workflow library is bloated but salvageable; the memory organism — the operator's stated priority — has a strong write side, a dead read side, and a culture of silent failure between them. The system does. Teach it to read what it wrote, and it will learn.
