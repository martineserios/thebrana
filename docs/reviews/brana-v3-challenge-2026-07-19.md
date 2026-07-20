# Brana v3 — Adversarial Challenge Reports (3-lens quorum)

> 2026-07-19 · Target: [brana-v3-redesign.md](../ideas/brana-v3-redesign.md) + [agentic-primitives.md](../architecture/agentic-primitives.md)
> Pattern: `_shared/adversarial-hive-mind.md` — 3 independent challenger agents (convergent / systems / critical), no cross-visibility, caller synthesis.
> **Verdict: unanimous RECONSIDER.** Corroboration matrix at the end.

---

## Lens 1 — SYSTEMS (second-order effects, cascades)

### Critical

1. **v3 re-derives an already-shipped sibling architecture instead of reconciling with it.** `docs/architecture/the-orbit.md`, `features/autonomous-runner.md` (t-2140), `features/learned-eligibility.md` (t-2142) — all ~4 weeks older — already specify and *partially ship* what v3 calls new: ADR-059 + ADR-060 (both accepted) define the autonomous substrate; autonomous-runner Stages 1–3 are **built** (OBSERVE → RUN-ONE → RUN-BATCH with validate.sh + build-evaluator AC-check as independent verifier); learned-eligibility Stage 4 is a **designed** graduation mechanic ("≥K live runs AND ≥95% merged-clean", soak ≥50 outcomes / ≥2 weeks). v3's ladder and Wave 2 verifier reinvent these under new vocabulary; neither v3 nor agentic-primitives.md mentions any of them. Risk: Waves 2/4 duplicate built work or ship a second, disagreeing graduation mechanism.
   *Fix:* reconciliation pass before Wave 1 — supersede those docs explicitly inside v3, or fold the ladder into learned-eligibility Stage 4 as its execution vehicle.

2. **"LEARN on cloud Routines" contradicts the local-state-coupled implementation it replaces.** close-extraction.sh (confirmed live, not dead) is HOME-dependent, invokes the local Rust binary, hard-ruled to access the queue only via `brana close-queue`. Cloud Routines have no access to `~/.claude`, local tasks.json, or the local CLI. Local consumers (memory-index-sync, pattern-promotion) are hook-triggered, not pollers — they won't see cloud writes without a new session-start reconciliation step (unscoped).
   *Fix:* scope "Routines" to an Agent-SDK process with the repo mounted, or add an explicit local↔cloud sync task inside the ≤10 budget. Verify the "dead cron" premise via `brana ops status` first.

3. **goal-completion.sh has ~10+ undeclared consumers; Wave 2 lists deletion, not migration.** Wired into hooks.json (blocking), ac-lint.sh, git pre-commit, red-verification.sh, presence-refresh.sh, 4 skill phases (build-loop, load, fix, reconcile), plus ADR-047, ADR-061, ADR-062-step-state-contract — which collides in filename with the unrelated ADR-062-runner-executor-sandbox.
   *Fix:* enumerate consumers as explicit Wave-2 tasks; resolve the ADR-062 numbering collision; port test-goal-completion.sh assertions.

### Warnings

1. **Cockpit approval queue not mapped onto ADR-060's 8-layer git gate chain** (worktree-per-actor, secret-scan, invariant tests, human-merge-gate…). If cockpit approval happens outside a PR, those git-lifecycle hooks never fire. *Mitigation:* cockpit approval = merging an ADR-060 PR (reuse), or re-verify every gate against the new surface.
2. **"Approvals ARE graduation evidence" risks approval-fatigue contamination.** learned-eligibility already solved this: an explicit outcome-recording step at review time, not raw approve clicks. *Mitigation:* reuse its outcome-ledger design.
3. **t-1994 (loop-native-redesign foreman/crew epic, ADR-050, pending P2) overlaps Wave 3 uncited** — two competing dispatch mechanisms if both proceed. *Mitigation:* re-parent or cancel t-1994/t-1995 against the v3 plan before Wave 3.

### Observations
- The wave contract is genuinely good anti-sprawl discipline — keep it.
- ADR-059's ruflo ban is consistent with delegation-routing — no conflict.

**Discipline:** DDD PASS · TDD WARNING (no test-task line; Wave 2 deletes tested code without port-forward) · SDD WEAK (no reconciliation task — the core finding) · Docs thin (acceptable pre-backlog).

**Verdict: RECONSIDER** — the north star isn't wrong; two overlapping accepted architectures sit unreconciled beneath it, and Wave 1's core mechanism contradicts the implementation it replaces.

---

## Lens 2 — CRITICAL (failure modes, kill-shots)

### Critical

1. **Wave 2 replaces a hardened anti-gaming apparatus, undifferentiated.** goal-completion.sh (330 lines) carries a presence interlock, grader-immutability (`base_ref` pin + Modified-vs-Added channel split so TDD-added tests aren't flagged as gaming), a command allowlist (H7), and a JSONL audit trail — each born from a real gaming attempt. An LLM verifier is a *new* attack surface (prompt injection, sycophancy), not inherently safer. *Fix:* the Wave-2 ADR must enumerate each guard as a named carry-forward.
2. **Verifier objectivity asserted, not measured:** ~233/2123 tasks (~11%) have any `AC:` line; of those, ~12% resist deterministic checking (goal-completion-heuristics doc). The ladder structurally touches ~a tenth of real work; unstated. *Fix:* scope L3 to AC-bearing types explicitly + add "drive AC: authoring adoption" as a line item.
3. **"Separate compute budget" unverified against org-disabled extra-usage.** If Routines bill to the subscription pool, Wave 1 cannot ship as scoped — LEARN silently competes with dev quota, the opposite of its purpose. *Fix:* same-day billing spike before the ADR. *(Resolved empirically same day: confirmed same-pool; see synthesis.)*
4. **Cockpit cost vs. interactive baseline unvalidated** — N-candidate prep multiplies spend before any judge pass, against the plan's own efficiency constraint. *Fix:* measure 3 real build tasks (interactive spend vs. N=2-3 prep + judge estimate); if prep exceeds a typical session, cut Wave 3 to judge-only (N=1).
5. **Wave 1 already breaks the ≤10-task rail:** ADR + billing spike + 4 distinct cron-job migrations + budget wiring + curation gate + DECAY scaling + 3 agent memory migrations = 12–14+ units before tests. *Fix:* split — memory-migration-only wave (~6-8 tasks, no billing dependency) first; Routines/SDK migration as its own gated wave with the spike as task 0.

### Warnings

1. **"N clean supervised runs" undefined** — may never accumulate for high-blast-radius processes under solo usage; fine if L2-permanent is stated as an expected outcome, not implied failure.
2. **"31 failed reads" may be misdiagnosed:** `agent-memory/brana-challenger/` contains no CALIBRATION.md — the real file is in-repo at `system/agents/CALIBRATION.md`. Points to a stale hardcoded read path, which native-memory migration won't fix unless the call site is corrected. *Mitigation:* locate the read-call site before counting this as "fixed by migration."
3. **TDD/Docs silent at wave level** — Wave 2 deletes a script with its own test suite; add "tests and docs ride inside the wave" language.

### Observations
- Cite t-1711-simplification-audit as precedent for net-negative waves (real, or the contract is aspirational).
- Single point of quiet reversion: if the Wave-1 billing dependency fails silently, LEARN reverts to nothing with no stated fallback — name the rollback scenario in the ADR.

**Verdict: RECONSIDER** — the two load-bearing waves each hinge on one unverified assumption (external billing; LLM verifier ≥ hardened deterministic gate). Both cheap to check; neither checked.

---

## Lens 3 — CONVERGENT (constraint synthesis vs. ADRs and shipped code)

### Critical

1. **Direct conflict with ADR-060 invariant #3** (universal, substrate-enforced): *"A human gates promotion to production. The agent never merges and never marks a task complete."* vs. v3: *"'Merge without a human' exists in v3 — but only when earned."* Flatly contradictory; ADR-060 never mentioned. *Fix:* scope "merge without a human" out of v3, or open an ADR-060 amendment before Wave 4, stating which invariant it revises.
2. **Wave 2 deletes goal-completion.sh as an atomic blob** — same guard-enumeration finding as the critical lens (presence interlock, base_ref pin, channel split, allowlist), backed by named calibration memories of the actual gaming attempts. *Fix:* per-mechanism carry-forward list, not "replace the file."
3. **close-extraction.sh is local-machine-bound and already `enabled: true`.** Resolves a compiled local Rust binary, local `agy`, `$HOME`; scheduler.json pins an absolute local path. The close-queue store (`~/.claude/close-queue.json`, advisory lock) is unreachable from a no-local-machine context without a store-portability sub-project that alone likely blows the task cap. *Fix:* either scope store portability explicitly, or drop the Routines migration and diagnose why an enabled job isn't processing — cheaper, matches the efficiency constraint.
4. **"Separate compute budget" stated as settled fact; its own source hedges it** ("*potentially* materially relevant"). Same failure class as calibration_subscription-zero-fee-viability. *Fix:* verify against the actual account tier before Wave 1. *(Resolved same day — see synthesis.)*
5. **The "2 live failures" justification fails inspection:** (a) close-extraction.sh shows recent hardening (t-1979/t-2085/t-2114 refs) — not abandoned; (b) the cited failing path doesn't exist; the real CALIBRATION.md (in-repo) reads fine. *Fix:* one live check each (`brana ops health`; grep the failing read call site) before leaning Wave 1 on "fixes 2 live failures."

### Warnings

6. **"L3 from day one" for LEARN contradicts the ladder's own taxonomy** — report-only output is L1 by definition; the earning mechanism (verifier, stops) ships Wave 2; graduation tracking Wave 4. The contract's "budgets are stop conditions from wave 1" is contradicted by the wave table. *Fix:* honest labels ("proves unattended execution on a low-risk loop") + a crude token/run ceiling inside Wave 1.
7. **≤10-task cap collides with the M+ discipline rule** (ADR + test-before-impl + spec-update + docs per feature) the moment the epic is planned. *Fix:* define what "1 task" means (disciplined feature-unit vs. raw step) before planning.
8. **AC-driven verifier covers a minority of the backlog** (~11%; ~12% residual UNKNOWN) — state the non-AC fallback (stay L2? AC: as precondition?).
9. **"Close FULL weight" deletion is ambiguous** vs. ADR-052's "without losing the FULL escape hatch" — dropping redundant sync-extraction (consistent) or removing the FULL debrief (regression)? Per spec-assumptions rule: ask, don't pick.
10. **Wave 2 ADR "extends ADR-059" mis-scopes it** — ADR-059 is substrate selection, says nothing about verifier semantics. Make the verifier ADR standalone, cross-referencing.

### Observations
11. Wave 3's judge step should point at the shipped `verify-findings` workflow (ADR-059 rule 5, "single source of truth for finding verification") — adopt, don't parallel-build.
12. Native subagent `memory:` frontmatter is the *least* risky CC-feature bet in the plan — documented field, not a billing/access-model bet. The plan is not over-claiming there.

**Discipline:** DDD partial (ADRs named but not stated as blocking — contrast ADR-052 §8) · TDD deferred-at-risk · SDD structurally present, no per-wave spec-update task · Docs absent per wave. All four under-specified; none fully absent.

**Verdict: RECONSIDER** — two unconditional blockers (ADR-060 contradiction; local-bound Wave-1 migration target), both cheap scope corrections.

---

## Synthesis — corroboration matrix

| # | Finding | Lenses | Confidence | Status |
|---|---|---|---|---|
| 1 | Unreconciled with accepted architecture (Orbit, ADR-059/060, autonomous-runner, learned-eligibility, ADR-047/061, t-1994) — incl. direct ADR-060 invariant contradiction | 3/3 | **HIGH** | Blocks planning — v3 must become the Orbit line's execution vehicle |
| 2 | Wave-1 Routines premise fails (local state + billing) | 3/3 | **HIGH** | **Empirically confirmed** via docs: Routines = same pool, zero local access, SDK pool SDK-only → LEARN worker = Agent SDK on local infra |
| 3 | "2 live failures" motivation wrong (cron live; path misdiagnosis) | 3/3 | **HIGH** | Wave 1 starts with 2 diagnoses, not rebuilds |
| 4 | goal-completion.sh: hardened guards + 10+ consumers; deletion unsafe | 3/3 | **HIGH** | Per-guard carry-forward enumeration; standalone verifier ADR; port tests |
| 5 | Wave 1 breaks ≤10-task cap; "task" undefined vs. M+ discipline | 2/3 | **HIGH** | Split waves; define task unit |
| 6 | Verifier reaches ~11% of tasks (AC coverage) | 2/3 | **HIGH** | Non-AC fallback + AC-adoption line item |
| 7 | TDD/docs silent at wave level | 3/3 | **HIGH** | "Tests and docs ride inside the wave" |
| 8 | "L3 day one" mislabeled; no stop conditions in Wave 1 | 2/3 | **HIGH** | Honest labels + crude ceiling in Wave 1 |
| 9 | Outcome ledger (not approve clicks) as graduation evidence | 1/3 | OBS (adopt) | Reuse learned-eligibility design |
| 10 | Cockpit approval must route through ADR-060 PR gates | 1/3 | OBS (adopt) | Reuse, don't bypass |
| 11 | Measure cockpit cost vs. baseline before building; N=1 fallback | 1/3 | OBS (adopt) | 3-task measurement spike |
| 12 | verify-findings workflow is the shipped judge primitive | 1/3 | OBS (adopt) | Point, don't rebuild |
| 13 | close FULL ambiguity vs. ADR-052 | 1/3 | OBS (ask) | Resolve with user |

**Process note:** all three agents' final reports initially failed to surface (harness issue); each was resumed and re-emitted its findings. Two flagged the resume message with appropriate suspicion and delivered genuine findings rather than fabricating prior work — the adversarial agents behaved correctly under an anomalous prompt.
