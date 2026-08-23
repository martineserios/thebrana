---
title: Statusline Pipeline Awareness
status: draft
created: 2026-08-14
---
# Statusline Pipeline Awareness

> Brainstormed 2026-08-14. Successor to the drained `statusline-v2-backlog-intelligence`
> idea (2026-04-07) — that idea predates the wave mechanics of The Brana (ADR-080, shipped
> 2026-08-13/14) it would now be built around. Status: draft, ready for backlog planning.

## Problem

The statusline shows session-local info (model/project/branch/epic/session/CTX%) but
has zero visibility into the backlog wave mechanics (ADR-080): wave status (queued /
draining / shipped), gate blockers, approval-pending (VALVE) tasks, or which wave a
running drain-loop (PUMP) is currently beating on. Today, seeing any of that requires
manually running `brana backlog wave board`, `sitrep`, or `claims status`. The old
`statusline-v2` idea proposed similar orientation signals but never shipped its core
Phase 1 (build_step bracket, session score, self-populating cache) — only the Phase 2
slow-cache scaffolding (`system/scripts/statusline-slow-cache.sh`) actually landed and
is live today.

## Proposed solution

A two-tier display, matching "big picture is a must, intermediate layers are
negotiable":

**Tier 1 — always-on, cached pipeline chip** (new statusline segment, ~30s-stale is
acceptable):
```
🌊 4✓ 1◐ 5⏳ ◎2
```
- `✓` shipped waves (cleared the VALVE — ac-approved + merged)
- `◐` draining waves (a PUMP is actively beating)
- `⏳` queued waves (matched, GATE not necessarily open)
- `◎` tasks at `ac_state:proposed` across matched waves (VALVE-pending, awaiting your
  approval) — closes a real gap: the VALVE stage currently has zero statusline
  representation
- **Fixture-filtered**: waves named `fixture-*` (the live convention already used by
  wave-7..10 in this repo's own `tasks.json` today, all marked "FIXTURE — never ship")
  are excluded from all counts. v1 filters by name prefix; flagged as a fragile string
  convention (see Risks) — a structural `is_fixture` flag is the real fix, not a v1
  blocker.
- Escalates to an anomaly line, shown unconditionally (not gated behind an active
  drain), when something needs attention:
  ```
  ⚠ wave-6 drain-3 gate-blocked 6h (waiting on wave-4)
  ```

**Tier 2 — context-adaptive current-focus line** (only renders while a PUMP is
actively beating on a wave in *this* session or a linked worktree):
```
→ wave-4 adr080-consumers [adr080-core] │ 2/5 tasks │ t-2843 [VERIFY] │ ~3m
```
- Wave id + name, **tagged with its epic** (`[adr080-core]`) so you always know which
  initiative's pipeline is flowing — resolved the same way the epic segment already
  resolves it (nearest `type:"epic"` ancestor via `parent`)
- QUEUE size for this wave (matched/remaining)
- Which task the current beat's atomic pull picked up
- `build_step` of the `/brana:build` cycle running inside this one beat
- PUMP's beat countdown (idempotent — a countdown, not a promise, per loop-operating-law #4)
- **Worktree suffix**, shown only when the beat is happening somewhere other than the
  viewing session's own cwd — e.g. `(in ../thebrana-t-2895)`. Confirmed live during
  this brainstorm: `~/.claude/run-state/{task-id}.jsonl` beat-state files are already
  centrally stored and **task-ID-keyed, not worktree-path-keyed** (loop-operating-law
  #3's "durable record outside the loop it guards" shape) — so the statusline never
  needs to walk `git worktree list` or read across checkouts, it just reads the same
  central file the pump already writes. The one gap: those files don't yet record
  *which* worktree wrote them — needs one new `worktree` field at the write site.

Idle state (no waves matched in this project) renders neither tier — zero clutter cost
when the feature isn't relevant.

## Pipeline → statusline mapping

```
QUEUE (wave selector match)  →  ⏳ count
GATE  (wave sequencing)      →  ⚠ gate-blocked flag
PUMP  (drain-loop beat)      →  ◐ count + the whole current-focus tail
VALVE (human ac-approve/ship)→  ◎ count (previously unrepresented — new)
```

## Research findings

- The wave pipeline already has a read-only computation for most of this: `brana
  backlog wave board` (ADR-080 §6f, "L0 cockpit gauge") — reuse its
  `resolve_wave_selector` / `WaveSelector::matches` / topo-order logic via
  `brana-query` rather than re-implementing selector parsing in bash. Re-implementing
  it would risk the exact bug class ADR-080 already fixed once (`wave_pull_decision`
  hand-stripping `tag:` and silently defeating `wip_limit`).
- The prior `statusline-v2` idea's own post-mortem is directly relevant: Phase 1
  (the genuinely new signals) never shipped despite being fully planned; only Phase 2
  (slow-cache scaffolding) shipped and is live. The forcing function this time is to
  extend that same already-running job rather than propose new infrastructure that can
  stall the same way.
- No existing open-source statusline project (rz1989s/claude-code-statusline,
  sirmalloc/ccstatusline) integrates with a backlog/task pipeline system — this stays
  a from-scratch design, not an adaptation.

## Risks

- **Cache never gets wired up** (history: this is literally what happened to
  `statusline-v2` Phase 1). Mitigation: extend `statusline-slow-cache.sh` — an
  already-running, already-proven 5-minute job — rather than building new scheduled
  infrastructure.
- **Fixture/test wave pollution.** Confirmed live and current, not hypothetical:
  wave-7 through wave-10 in this repo's own `tasks.json` are explicitly marked
  "FIXTURE — never ship" today. v1 filters by the `fixture-*` name-prefix convention
  those waves already use. Follow-up: formalize as a structural field rather than a
  string-matching convention a future wave author could forget.
- **Real-estate overflow.** Mitigated by keeping Tier 1 fixed-width and gating Tier 2
  strictly behind an active-drain condition; carries forward the width-detection idea
  from the original statusline-v2 plan (`tput cols` + progressive segment dropping).
- **Two data-freshness tiers to keep straight**: Tier 1 (pipeline-wide) is a 5-min
  cache; Tier 2 (current-focus) must be near-real-time, sourced from the session-local
  beat-state file, not the slow cache. Conflating the two sources was flagged
  explicitly during discussion — keep them architecturally separate.

## Engineering disciplines

- **DDD:** No new ADR for the core statusline extension (incremental, same
  determination the original statusline-v2 idea made). If the fixture-filtering
  follow-up becomes a structural schema field later, that's a small ADR amendment at
  that time, not now.
- **TDD:** Unit tests first: chip formatting + fixture filtering, gate-blocked /
  approval-pending anomaly thresholds, current-focus rendering with/without the
  worktree suffix, Tier 1 vs Tier 2 freshness separation. Push computation into the
  Rust CLI (`brana-query`) rather than bash/jq, per the v2 lesson about parse-logic
  duplication.
- **SDD:** Update `docs/architecture/features/wave-board.md` cross-links (or a new
  sibling doc) and `docs/reference/scripts.md` with the new segments; document the
  `worktree` field addition to the beat-state write path.
- **Docs:** User-guide update — this is a workflow-visible feature, not internal-only.

## Second-order effects

- Extend the slow-cache job to include wave data → chip becomes ambiently visible →
  **behavioral 2nd-order effect**: VALVE-pending (◎) approvals, invisible today until
  someone runs `wave board` or the batch-approve tool, become something you notice
  passively every prompt — likely shortening the time waves sit at `ac_state:proposed`
  and nudging toward smaller, more frequent approval batches instead of large
  infrequent ones. Not just information delivery — a plausible change in your own
  approval cadence.

## Next steps

1. Extend `statusline-slow-cache.sh` (or its consumer) to compute and cache the Tier 1
   chip fields via `brana-query`/wave-board logic — fixture-filtered, gate-blocked and
   approval-pending flags included.
2. Add a `worktree` field to the beat-state write path (`~/.claude/run-state/{task-id}.jsonl`)
   and wire the current-focus line to show it only when it differs from the viewing
   session's cwd.
3. Write anomaly-escalation threshold tests (gate-blocked age, approval-pending age)
   before wiring them into the render path.
4. Fast-follow (explicitly out of scope for this pass): an interactive TUI as the
   natural home for on-demand drill-down, seeded from today's flat `wave board` text
   output, once the statusline chip proves itself.
