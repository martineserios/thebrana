---
status: pre-registered
task: t-3515
epic: t-3513
created: 2026-10-14
approved: 2026-10-14 (owner, before any bundle was scored)
decision: docs/architecture/decisions/ADR-099-recall-bundle-and-usage-log.md
---

# Recall bundle gates v1 (pre-registered)

These thresholds were fixed **before any recall bundle existed or was scored**. They may not be
changed after a scored run; a change needs a new version (`gates-v2.md`) with the reason stated.
ADR-099 §7–8 defines what the gates mean: shadow gates can only kill, keep is decided by the
canary.

## Gold set

- File: [gold-v1.jsonl](gold-v1.jsonl), built by [build_gold.py](build_gold.py) from
  [labels-v1.tsv](labels-v1.tsv). See [README.md](README.md) for how it was mined and labelled.
- **Gated set: `pointed`**: 43 tasks, 49 notes. The ticket cited the note when it was written, so
  the note existed and its author judged it relevant.
- **Report-only set: `read`**: 6 tasks, 6 notes. Too small to gate on.
- **Query:** task subject + tags only. Description, context and notes are never part of the query,
  so the ticket's own pointer text cannot leak into retrieval.
- **Minimum n:** 30 gated tasks. Below that the verdict is INCONCLUSIVE.
- Baseline (b) "pointers already in the ticket" is **not used** on this set: it would score 100% by
  construction. The comparison is against today's `brana recall` only.

## Metrics

- **hit@8:** share of gated tasks with at least one gold note in the top 8 (the bundle cap).
- **MRR:** mean reciprocal rank of the first gold note in the top 20 (0 when absent).
- Every scored system runs **5 times**; the gate uses the mean of the 5 runs.
- Scorer: [score_baseline.py](score_baseline.py) (t-3518 reuses it for the bundle).

## Measured baseline (2026-10-14, installed brana 0.2.0, 5 runs each)

| Mode | hit@8 per run | hit@8 mean | MRR per run | MRR mean |
|---|---|---|---|---|
| Run set A (no `RUFLO_BIN`) | 0.279, 0.256, 0.256, 0.256, 0.256 | 0.261 | 0.174, 0.196, 0.192, 0.167, 0.190 | 0.184 |
| Run set B (`RUFLO_BIN` pinned) | 0.233, 0.256, 0.279, 0.233, 0.256 | 0.251 | 0.157, 0.156, 0.184, 0.132, 0.158 | 0.157 |

- **Reference baseline:** the better run set, hit@8 **0.261**, MRR **0.184**.
- **Noise:** runs differ by about one task of 43 (hit@8 range 0.233–0.279), even with identical
  inputs.
- See the correction below: the two run sets are the same system, not "vectors dropped" versus
  "vectors working".

## Shadow gates (kill-only)

| Verdict | Rule |
|---|---|
| **KILL** | bundle mean hit@8 < **0.233** or bundle mean MRR < **0.132** (below the baseline's worst run) |
| **PROCEED, lift** | bundle mean hit@8 ≥ **0.30** (≥ 13 of 43 tasks) and not KILL |
| **PROCEED, no offline lift** | neither of the above; goes to the canary flagged as such |
| **INCONCLUSIVE** | fewer than 30 gated tasks |

## Ranking changes (t-3519)

A ranking change (type quotas, MMR, supersession weighting, 1-hop links) is kept only if, against
the bundle without it, mean hit@8 rises by **≥ 0.047 (2 tasks)** and mean MRR does not fall by more
than **0.03**. One task is within run-to-run noise and does not count.

## Canary (t-3521)

- **Arms:** assigned by a hash of the task id, so a re-pulled task stays in its arm.
- **Minimum:** 15 tasks per arm within 4 weeks of the canary start, else INCONCLUSIVE.
- **KEEP** only if all hold:
  - median tokens per run in the shown arm is at most **5% above** the control arm;
  - AC-pass count in the shown arm is not lower than control by more than **1 task**;
  - use rate in the shown arm (used ÷ shown pointers) is at least **0.25**, reported together with
    the `no-answer` and `no-exit` counts.
- Otherwise DROP. The bundle stays computed in shadow mode only if a new gates version says so.

## Staleness (ADR-099 §8)

A note becomes a demotion candidate after **5 shown bundles with 0 use**. With fewer than 5
exposures it is unmeasured, never a candidate.

## Known limits

- The gated set is biased toward notes that authors remembered to cite. It measures "finds the note
  a knowledgeable author would point to", not "finds the note that would have helped". Only the
  canary's outcome rows measure usefulness.
- The installed binary (0.2.0) predates t-3510's memory-file vector leg. Re-run the baseline with
  the same scorer once t-3510 ships, before scoring the bundle, and record it here as an addendum
  (the thresholds stay fixed).
- The vector leg can drop silently under machine load (see the correction below). Per-leg status
  (ADR-099 §4, t-3516) makes this visible; until then, a baseline run that sits at the 2 s deadline
  must be discarded and repeated.

## Correction (2026-10-14, same day, before any bundle was scored)

Two statements in the first version of this file were wrong. The thresholds above do not depend on
either and are unchanged.

1. **The two run sets were mislabelled.** They were recorded as "vector leg drops" (no
   `RUFLO_BIN`) and "vectors working" (`RUFLO_BIN` pinned). Re-measured the same day: sourcing
   `cf-env.sh` takes 5–8 ms, and recall without `RUFLO_BIN` returns vector hits in about 0.77 s. The
   2.03 s calls and zero-result queries seen earlier were intermittent, most likely machine load
   pushing the Node embedder past the 2 s vector deadline. Both run sets measure today's recall; the
   ten runs together give the noise band.
2. **"Vectors do not improve this gold set" was an artefact.** The installed binary (0.2.0) has no
   memory-file vectors (that is t-3510). Its vector hits are knowledge-store rows, which can never
   match a memory-note gold slug; at most they compete for top-8 slots. Whether vectors help is
   only testable after t-3510 ships, when the baseline is re-run as required above.

The follow-up task t-3527 (filed on the wrong premise that ruflo resolution caused every drop) was
cancelled. The real defects are covered elsewhere: silent drops by per-leg status (t-3516), and the
small latency headroom by the in-process embedder spike (t-3522).

## Addendum 2026-10-15: baseline re-run after t-3510 shipped

Required by the section above. Same scorer and gold set, installed brana 0.2.0 built from `main`
(`a96fca15`: memory-file vector leg, per-leg status, `embed-memory` run first: 1,125 of 1,126 notes
embedded). Plain `brana recall <query> --top 20`, 5 runs. Thresholds above are unchanged.

| Set | hit@5 per run | hit@8 per run | hit@8 mean | MRR per run | MRR mean | recall@8 mean |
|---|---|---|---|---|---|---|
| pointed (n=43) | 0.465, 0.465, 0.512, 0.442, 0.419 | 0.581, 0.558, 0.581, 0.558, 0.558 | **0.567** | 0.316, 0.330, 0.307, 0.323, 0.294 | **0.314** | 0.518 |
| read (n=6) | 0.167 in every run | 0.167 in every run | 0.167 | 0.083 in every run | 0.083 | 0.167 |

- **The plain-recall baseline more than doubled** against the 2026-10-14 reference (hit@8 0.261 →
  0.567, MRR 0.184 → 0.314), because memory files now match by meaning as well as by keyword.
  The spread is tighter (hit@8 0.558–0.581).
- **What this does to the shadow gates:** the thresholds are absolute and stay as registered, but
  "PROCEED, lift" (≥ 0.30) is now below plain recall's own score, so passing it no longer shows the
  bundle beats plain recall. The t-3518 report must show the bundle's mean next to this baseline
  (0.567 / 0.314), and a bundle at or below it cannot claim an offline lift. Changing the
  threshold itself needs a `gates-v2.md` with the reason stated.
- Informational smoke on 2026-10-15 (keyword legs only, a copy of the live index): bundle hit@8
  0.581 against plain recall's 0.14–0.16 at that time. That comparison is superseded by this
  addendum and was not a gate run.
- The 43 gated tasks are the same; no per-leg degradation was observed (no call at the 2 s deadline
  in the recall-eval run made just before).
