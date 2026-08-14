# Judge-panel probe — retrospective measurement (t-2887)

> Spike deliverable, 2026-08-14. Design: [docs/ideas/loop-task-multiagent.md](../ideas/loop-task-multiagent.md) §Probe design.
> Question: does a diverse blind judge panel surface **verified real findings** that the
> recorded single challenger missed, on the same diffs? Decision rule pre-registered:
> ≥1 verified unrecorded miss → go; zero → no-build.

## Verdict: GO — decisively

**4 clean verified misses (3 at severity 4), from a 6-diff corpus whose every diff had
already passed a single fresh-context challenger.** Two additional candidates verified
real but qualified (one pre-recorded elsewhere, one severity-downgraded). Verification
killed zero candidates outright — but did correct one severity inflation and filtered
~19 of 29 raw panel findings before verification was even attempted.

## Method

- **Corpus:** the 6 completed wave-3/4 diffs (t-2840…t-2845, including their subtask
  commits), reconstructed from dev history with `.claude/tasks.json` excluded — the
  recorded challenger verdicts live in task notes, so excluding it enforced blinding.
- **Panel per diff:** 2 Claude judges with narrow briefs (security/injection lens;
  contract/AC-fidelity lens) + 1 Gemini judge via the agy lane (model diversity).
  Parallel, independent, blind — forbidden from reading task notes, backlog, or git
  history. Empty findings explicitly legitimized ("a respectable answer").
- **Ground truth:** the single challenger's recorded findings in each task's notes.
- **Filter:** re-catches of recorded/tracked findings and intermediate-state noise
  removed by hand; 6 strongest candidates advanced.
- **Verification:** 6 adversarial skeptics (full repo access, instructed to refute,
  default-refuted) — one per candidate.

## Results

### Verified misses (single challenger passed these; panel caught them)

| # | Task | Sev | Finding | Verification evidence |
|---|------|-----|---------|----------------------|
| 1 | t-2842 | 4 | `yes \| brana backlog wave approve` auto-confirms **all** batches — no `is_terminal()` check on the interactive prompt (`backlog.rs:1254`), strictly more permissive than the `--yes` flag whose one-batch-per-invocation fix the recorded challenger demanded. Resurrects the exact "cap enforced, not advisory" sev-4 through a second variant. | CONFIRMED_REAL, unrecorded |
| 2 | t-2842 | 4 | MCP `backlog_wave_approve` validates-and-applies per id in one loop (`backlog_wave_approve.rs:68-77`): `confirm_ids=[valid, invalid]` approves the valid id on disk, then errors claiming "(nothing applied)" — partial application plus a false error message. Ordering untested. | CONFIRMED_REAL, unrecorded |
| 3 | t-2845 | 4 | `status cancelled` is denied in **neither** epic-drain.md nor drain-loop.md denied-verbs tables (only `completed` is). A cancelled task exits wave eligibility (`wave.rs:127` pending-only resolver) **and counts toward contract-met** (ADR-080:112 "completed/cancelled"), routed to the cockpit digest — a stuck loop can silently shrink a wave and have it read as done. t-2827's enforcement list also omits cancel. | CONFIRMED_REAL, unrecorded |
| 4 | t-2844 | 3 | The "strictly read-only" wave board can write: `find_tasks_file()` auto-creates `tasks.json` when absent (`util.rs:131/145`), violating the zero-writes AC. The recorded challenger passed t-2844 with zero findings. | CONFIRMED_REAL |

### Verified but qualified

| Task | Sev | Finding | Qualification |
|------|-----|---------|---------------|
| t-2841 | 4 | `cmd_run`/`cmd_agents_kill` RMW is unlocked (load → `git worktree add` subprocess → save, no `lock_tasks`) — can silently clobber a concurrent locked wave-pull's lease write. | Real (file:line confirmed) but the defect class was already recorded repo-wide as pending **t-2175**. In-context challenger miss; not net-new knowledge. |
| t-2843 | 2–3 | The `--contract` quoting note is advisory prose; its own template shows the unsafe form; apostrophe uncovered. | Real, but panel's sev-4 was inflated — LLM-composed commands cap it at s2–s3. Verification corrected the score. |

### Panel-quality observations (feed the wiring design)

- **Signal concentrated in the narrow-brief Claude judges.** 3 of 4 clean misses came
  from the security/contract lens pair. The Gemini lane returned 0 findings on 4 of 5
  diffs it actually ran on and over-reported on the fifth (9 findings on t-2845, mostly
  procedure misreadings; 1-2 defensible). One Gemini wrapper silently fell back to
  Claude — the agy lane needs a health check in any wired version.
- **Blind + "empty is respectable" worked:** t-2840 got three defended clean verdicts —
  no invented findings on the strongest diff.
- **Verification is not optional:** it filtered severity inflation and would have been
  the only defense had candidates been fabricated. Raw panel output (29 findings) was
  ~4× the verified-miss count.
- **The misses cluster in a known class:** 3 of 4 are second-variant / parallel-path
  blindness (a fix audited on one path, its sibling unaudited) — exactly what a
  same-model single reviewer is structurally worst at, and what narrow adversarial
  briefs are best at.

## Cost

~1.60M subagent tokens for 18 judges + ~0.45M for 6 verifiers ≈ **2.05M total,
~340K/diff** — versus a recorded single-challenger cost of roughly 100–150K/diff:
**~2.5–3.5× cost multiplier**, consistent with the literature's 3–10× and at the cheap
end of it. For that multiplier the panel produced 4 verified real defects on
already-challenger-passed code, three of them severity 4.

## Consequences (proposed — see t-2887 ANSWER)

1. **File the 4 verified defects as fix tasks immediately** (plus a context append to
   t-2175 for the lease-race interaction; quoting fix folded in at s2-s3).
2. **Go on the two S build tasks** from the idea doc: (a) JUDGE wiring —
   disagreement-surfacing verify-findings variant + agy lane with health check;
   (b) PLAN/DECOMPOSE hive-mind wiring.
3. **Escalation-valve ADR** (ADR-080 amendment) — panels on demand via hard signals,
   not per-beat fixtures; this probe's cost figure is the budget anchor.
4. **Escaped-defect log at the merge valve starts now** — this probe just seeded it
   with 4 entries.
