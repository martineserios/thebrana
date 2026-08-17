# Feature: Loops Library — `system/loops/` catalog of committed loop definitions

**Date:** 2026-08-17
**Status:** decomposing
**Task:** t-2826
**Source doc:** [loops-library.md (idea, shape approved 2026-08-14)](../../ideas/drained/loops-library.md)
**Related ADRs:** [ADR-079](../decisions/ADR-079-backlog-drain-loop-handoff.md) (drain-loop substrate), [ADR-080](../decisions/ADR-080-plan-time-wave-graphs-epic-runner.md) §6 (scope split: loop-first owns "loops library catalog + entry schema + `records:` beat schema")

## Problem

Loop definitions are scattered and mostly ephemeral: ad-hoc `/loop` prompts carried in `ScheduleWakeup` calls die with their session and are invisible to other sessions. Three real loops already run in production, each already a committed file, but with no shared catalog, no shared entry schema, and no lint holding them to one shape:

- `docs/guide/workflows/drain-loop.md` (t-2813) — the first fully committed example, proves the "committed prompt" pattern works
- `system/loops/pipeline-digest.md` (t-2823) — an L0 Reporter gauge, already live in `system/loops/`, but predates any entry schema (no frontmatter, ad-hoc structure)
- `docs/guide/workflows/epic-drain.md` (t-2845) — the second proof the pattern generalizes (graph-walking runner over an epic's wave graph); already frontmattered, already proven (see its own Proof-of-life section), and already names itself as "the first proof the library holds more than one entry" — but it lives outside `system/loops/`, same as drain-loop.md, with no catalog file pointing at it

Like skills, loops need a library: versioned, discoverable, reviewable, with a shape contributors can follow instead of reinventing per loop. The gap this build closes is the catalog and its schema/lint — not the three loops themselves, which already exist and already work.

## Decision Record (frozen 2026-08-17)

**Context:** The architectural decision here already landed — ADR-080 §6 explicitly assigns "loops library catalog + entry schema + `records:` beat schema" to the loop-first epic (this task), and the idea doc (shape approved 2026-08-14) already worked through queue-adapter architecture, the pull interface, and risk mitigation. There is no new load-bearing decision in this spec; it distills an already-approved design into a buildable scope. No new ADR is written — this spec references ADR-079/ADR-080 rather than embedding a fresh Decision block.

**Decision:** `system/loops/` is the catalog directory. Each entry is one file: YAML frontmatter (`name`, `cadence`/`pacing`, `autonomy` L0–L3 + `supervised` flag, `drains:`/`fills:`, `spawns:`, `records:`) + body (beat procedure, cheap preflight, STOP conditions, denied verbs). The beat-record JSON shape is single-sourced in this file (see §Beat record schema below) — entries reference it, never redefine it. An entry is not "done" until it has real beats with emitted records (proof-of-life, scaled by autonomy).

**Consequences:** Writing a new entry is deliberately more expensive than an ephemeral `/loop` prompt (anti-sprawl brake, per the idea doc's pre-mortem). The upside: this build gets three seed entries essentially for free, because all three already have live run history — the work is retrofitting/extracting them into the schema, not inventing new loops from zero.

## Constraints

- Hybrid queue architecture (idea doc, approved): native stores stay authoritative (waves in tasks.json, `inbox/` dir, git refs) — no generic mirror store. Shared abstraction lives only at the pull interface (`peek/pull/ack/dead-letter/depth`).
- Records are always emitted; verbosity is a render toggle, never an emit toggle.
- Unattended mode is hard-gated on the ADR-062 executor sandbox — no entry in this build declares `supervised: false`.
- Model-per-beat-component is only partially resolved: the JUDGE slice defers to `system/skills/_shared/judge-sizing.md` (ADR-082, t-2895); `preflight`/`act`/`records` tiers stay deferred — this build does not force that decision.

## Scope (v1)

1. **`system/loops/` entry schema + lint.** Formalize the frontmatter shape (fields above) and a lint check (`system/scripts/loops-lint.py` or shell, decided in DECOMPOSE) that validates: required frontmatter keys present, `records:` is a *reference* to this file's schema (not a duplicate definition), a `denied verbs` section exists for any entry with `autonomy` above L0.
2. **Bring three already-live loops into the catalog, schema-compliant:**
   - **`pipeline-digest`** (L0 gauge, merge-radar) — already at `system/loops/pipeline-digest.md` (t-2823); retrofit frontmatter, no behavior change.
   - **`drain-loop`** (pump, supervised) — already committed at `docs/guide/workflows/drain-loop.md` (t-2813); the catalog entry *references* that file rather than forking its procedure — avoids duplicating ADR-079 §2b's denied-verbs table.
   - **`epic-drain`** (pump, supervised) — already committed at `docs/guide/workflows/epic-drain.md` (t-2845, already proven, already frontmattered, already forward-references this spec) — treated identically to `drain-loop`: the catalog entry references it, no re-derivation, no rewrite. There is nothing left to "extract" — ADR-080 §3's prose predates the committed file and is now redundant with it (candidate for ADR-080 to point at the file instead of restating it, see Documentation Plan).
3. **`system/loops/README.md`** — catalog index + "how to write and arm a loop" guide, mirroring the skills library's own README convention (operator-facing, lives in `system/` not `docs/`).
4. **Discoverability, scoped down.** `brana discover` has no existing subcommand for this (verified: no `Discover` command in `system/cli/rust/crates/brana-cli/src`) — wiring it is net-new CLI code, not a documentation change. v1 ships the catalog itself plus its README index; `brana discover` integration is deferred (see Out of scope) rather than silently assumed.

- New loop entries beyond the three above (e.g. `ac-proposer`, `knowledge-distiller`, `watchdog`/`lease-reclaimer`) — each is its own follow-on task once the catalog format exists to write them into.
- Full resolution of model-per-beat-component beyond the already-decided JUDGE slice.
- Unattended/autonomous execution (ADR-062 gate).
- Loop-calls-loop recursion-bound *enforcement* mechanics — `spawns:` is declared in frontmatter as a field, but nothing in this build enforces the bound at runtime; that's future work once a loop actually spawns another.
- `brana discover` CLI integration — no existing subcommand to extend; net-new code, filed as its own follow-on once the catalog format is stable enough to build a lister against.

## Research

- [loops-library.md (idea)](../../ideas/drained/loops-library.md) — entry schema draft, queue-type table, pull-interface verbs, risks/pre-mortem, shape approval
- [wave-pipeline.md](../../ideas/drained/wave-pipeline.md) — canonical philosophy (seven laws, two rooms, four primitives/rings) — not duplicated here
- [ADR-079](../decisions/ADR-079-backlog-drain-loop-handoff.md) — drain-loop handoff contract, denied-verbs pattern this catalog's lint borrows
- [ADR-080](../decisions/ADR-080-plan-time-wave-graphs-epic-runner.md) §3, §6 — epic-drain's beat procedure (currently prose-only) and the loop-first/backlog-drain scope split
- `system/loops/pipeline-digest.md` (t-2823) — live precedent for an L0 gauge entry, pre-schema
- `docs/guide/workflows/drain-loop.md` (t-2813) — live precedent for a supervised pump entry, pre-schema

## Assumptions

Per the no-silent-ambiguity rule — flagged, not picked:

1. **Directory vs skill-frontmatter.** The idea doc's own open question ("`system/loops/` dir vs skills-with-loop-frontmatter") is unresolved upstream. Assumption: keep the dedicated `system/loops/` directory (already exists, already has a real file in it) rather than retrofitting loops as skill frontmatter — because none of the three seed entries are skills. *Needs confirmation.*
2. **Lint implementation.** No prior art for a loops-specific lint exists. Assumption: a small Python script under `system/scripts/`, following the same shape as skill-validation-checklist tooling, wired into `validate.sh`. *Needs confirmation on language/wiring.*
3. **Proof-of-life bar for seed entries.** The idea doc's bar is "N real beats with emitted records," which reads as a forward-looking usage requirement, not a one-sitting deliverable. Assumption: for v1, proof-of-life is satisfied by pointing at each entry's *already-emitted* historical run evidence (pipeline-digest's live beats since t-2823, drain-loop's 8-beat t-2813 session + ongoing wave-drain use, epic-drain's t-2845 beats) rather than requiring fresh beats post-cataloging. *Needs confirmation* — the alternative reading (N beats *after* the entry is catalog-compliant) would make this task open-ended rather than closeable in one build.
4. **`drain-loop` and `epic-drain` catalog entries as references vs forks.** Assumption: the catalog file for both is a thin wrapper (frontmatter + a pointer to the authoritative procedure doc, which stays at `docs/guide/workflows/`) rather than a full copy or move, to avoid the exact duplication problem ADR-080 already flagged for the beat-record schema. *Needs confirmation* — an alternative is `git mv`ing both files into `system/loops/` outright, which would make the catalog the single home instead of a second location pointing at `docs/guide/workflows/`.

## Behavior

- A contributor opens `system/loops/` and finds one file per loop: frontmatter (name, cadence, autonomy, what it drains/fills) + a beat procedure they can run via `/loop`, or a thin pointer to where the procedure actually lives.
- `system/loops/README.md` surfaces the catalog as a human-readable index — name, one-line purpose, autonomy level (`brana discover` integration is future work, see Out of scope).
- Running `system/scripts/loops-lint.py` against any entry reports pass/fail with the specific missing field or malformed section, not a generic error.
- The three seed entries pass lint immediately after retrofit/referencing.

## Edge Cases

- An L0 gauge (pipeline-digest) has nothing to deny — lint must not require a denied-verbs table for `autonomy: L0` entries, only for entries above L0.
- `epic-drain.md` already exists, already proven, already frontmattered — this build must not touch its behavior or re-derive it from ADR-080's (now-redundant) prose. Any edit to it in this build is confirmation-only (e.g. adding a pointer from `system/loops/`), never a rewrite.
- If `drain-loop`'s or `epic-drain`'s catalog entry and their `docs/guide/workflows/` source ever drift, the lint should catch structural drift (missing denied-verbs table) even though it can't catch prose drift — noted as a known gap, not solved here.

## Design

### `system/loops/` entry frontmatter

```yaml
name: <loop-name>
cadence: <default pacing>       # or pacing: {active_delay, waiting_delay, empty_delay} for work-paced loops
autonomy: L0-L3
supervised: true                # false is unreachable until ADR-062 lands
drains: []                      # queue references this loop pulls from
fills: []                       # queue references this loop writes to
spawns: []                      # other loops/runners this loop may launch + max concurrency
records: "see ./RECORDS.md"     # pointer only — never redefine the schema inline
```

Body: beat procedure, cheap no-op-fast preflight, explicit STOP conditions (real signals — exit codes, error strings, never self-assessed confidence), denied verbs (human valves), required for `autonomy` above L0.

### Beat record schema (single-sourced here — do not redefine elsewhere)

Every committed loop entry emits one record per beat, always — verbosity is a render toggle (inline vs quiet), never an emit toggle. The record is the work-graph entry: what a beat did, traceable through objective → plan → artifact → decision → execution record.

```json
{
  "loop": "epic-drain",
  "instance": "backlog-drain",
  "beat": 3,
  "timestamp": "2026-08-14T18:02:11Z",
  "state": "active",
  "what_happened": "pulled t-2847 from wave-adr080-consumers, build framework entered (SPECIFY)",
  "progress": {
    "kind": "bounded",
    "remaining": 4,
    "total": 7
  },
  "escalations": [],
  "next_wake": "PT20M"
}
```

Field notes:
- `loop` — the catalog entry name (matches its frontmatter `name`).
- `instance` — what this beat ran against (epic slug, wave id, or other queue-instance identifier — entry-specific).
- `beat` — 1-based sequence number, monotonic per running instance.
- `state` — `active` (work found and pumped), `waiting` (blocked on a human valve or gate), `empty` (queue drained, nothing eligible), `stopped` (a real termination signal fired).
- `what_happened` — free-text summary of what the beat actually did (or found), one to two sentences.
- `progress.kind` — `bounded` (known denominator, render a progress bar) or `unbounded` (no denominator, render a heartbeat). Declared once per entry, not re-derived per beat.
- `progress.remaining` / `progress.total` — bounded only; null when unbounded.
- `escalations` — zero or more `{room: "digest"|"agenda", note: "..."}` entries raised this beat.
- `next_wake` — ISO-8601 duration (or absolute timestamp) before the next beat.

This is the single source for the shape above — every catalog entry and ADR-080 reference it, never redefine their own copy.

### Model per beat component (deferred, named not solved)

A per-step model tier belongs in each entry's frozen contract (`model: {preflight, act, judge, records}`), but no default table exists yet and this build does not create one. **Partial resolution (t-2895/ADR-082):** for the JUDGE component specifically, model-and-shape is decided and single-sourced in `system/skills/_shared/judge-sizing.md` — entries declaring `model.judge` should reference `resolve_judge_rung` rather than restate a tier. `preflight`/`act`/`records` tiers remain deferred pending a pass across more entries to calibrate against.

## Boundaries

| Always | Ask First | Never |
|--------|-----------|-------|
| Reference the single-sourced beat-record schema, never redefine it inline | Adding a 4th seed entry beyond pipeline-digest/drain-loop/epic-drain | Duplicate `drain-loop.md`'s procedure content into its catalog wrapper |
| Keep all three seed entries `autonomy` ≤ L1, `supervised: true` | Choosing the lint script's implementation language | Enable unattended mode (ADR-062 gate) |
| Treat `epic-drain.md` as already-proven — reference only, no rewrite | Changing `pipeline-digest.md`'s existing behavior while retrofitting frontmatter | Fork the beat-record schema into a second definition anywhere in the repo |

## Testing Strategy

- **Unit:** lint script — a valid entry passes; each required-field-missing case fails with a specific error; L0 entries don't require a denied-verbs table; entries above L0 without one fail.
- **Integration:** run the lint against all three real seed entries — all pass after retrofit/extraction.
- **Mock policy:** no I/O beyond reading local files — no mocks needed (Real > Fake > Stub > Mock, and there's nothing here but the filesystem).

## Documentation Plan

- [ ] **User guide** — `system/loops/README.md`: how to write and arm a loop entry, the frontmatter contract, how `/loop` picks it up (operator-facing, mirrors skill-authoring conventions, lives in `system/` not `docs/guide/`).
- [ ] **Tech doc** — this file, updated post-build with final design notes and any assumption resolutions.
- [ ] **Existing docs to update:**
  - `docs/guide/workflows/drain-loop.md` — add a header pointer to its catalog entry.
  - `docs/guide/workflows/epic-drain.md` — add a header pointer to its catalog entry (already has a `related:` frontmatter field pointing at this spec; the catalog file is the missing reverse link).
  - `docs/reference/skills.md` — add a "loops library" pointer alongside skills (this task's own framing: "parallel to the skills library").
  - ADR-080 §3 — its epic-drain beat-procedure prose now predates and duplicates the committed `epic-drain.md`; point at the file instead of restating the procedure (same duplication ADR-080 itself warns against for the records schema).

## Challenger findings

**Verdict (2026-08-17): RECONSIDER → fixed.** Critical finding: the draft's Problem/Scope treated `epic-drain` as needing extraction from ADR-080 §3 prose, but `docs/guide/workflows/epic-drain.md` (t-2845) already exists, complete, proven, and already forward-references this spec — building to the original scope risked re-deriving a stale copy missing a fix (an exit-status-check gap) present only in the committed file. Fixed: epic-drain now gets the same reference-only treatment as drain-loop; Problem/Scope/Edge-Cases/Boundaries/Assumption-4/Documentation-Plan all corrected.

Warnings addressed: (1) `brana discover` has no existing subcommand — moved from Scope to Out-of-scope (net-new CLI, not this build). (2) Verified the pre-existing stub's beat-record schema and model-per-beat-component sections survived this rewrite verbatim, per the stub's own "expand — don't replace" instruction.

Observations: proof-of-life-via-historical-evidence (Assumption 3) independently corroborated for all three entries — pipeline-digest (t-2823 run-state history), drain-loop (ADR-080's own citation of the 8-beat t-2813 session), epic-drain (t-2845's own Proof-of-life section + live tasks.json).
