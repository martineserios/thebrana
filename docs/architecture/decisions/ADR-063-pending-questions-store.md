---
status: proposed
---
# ADR-063: Pending-Questions Store — Raised-Hand Queue for Autonomous Workflows

**Status:** Proposed (2026-06-21; one challenger pass — RECONSIDER → blockers F5/F6/F7 structurally resolved by the derive-block-from-store redesign below; not yet re-challenged, verify at build)
**Date:** 2026-06-21
**Deciders:** Martín Rios
**Tags:** loop-native, factory, autonomy, queue, substrate, hand-raising
**Tasks:** t-1993 (this ADR) · gates t-1994 (foreman recipe) alongside t-1981/t-1982/t-1992
**Extends:** [loop-native redesign](../../research/2026-06-11-loop-native-redesign.md) (Part 2 — hand-raising protocol) · [ADR-051](ADR-051-reminder-store-architecture.md) (Rust-owned locked-json store pattern)
**Relates:** [ADR-052](ADR-052-close-queue-architecture.md) (the close-queue sibling — shared-substrate decision in §7) · [ADR-050](ADR-050-loop-request-protocol.md) (autonomy caps — the foreman/crew that raises hands) · [ADR-061](ADR-061-goal-integration-three-primitive.md) (the supervised `/goal` tier whose loops also raise hands) · [ADR-054](ADR-054-reminder-delivery-channels.md) (reminder dispatch / notify channels — reused in §8)

---

## Context

The factory model ([loop-native redesign Part 2](../../research/2026-06-11-loop-native-redesign.md)) runs autonomous task-crew workflows in background worktrees. A background workflow **cannot ask an interactive question** — there is no human at the keyboard during a crew run. When a crew hits a human gate, an unverifiable `AC:`, a failed verify after its bounded repair cycle, or an interface-level ambiguity (the t-1991 rehearsal's "ambiguity severity" finding), it must **raise its hand**: park the question durably, take itself out of the dispatch pool so the foreman skips it (one stuck task never stalls the factory), and let the human answer **in batch** later. Answered tasks become dispatchable again.

This is a queue with the exact concurrency hazard ADR-051/052 already solved: a per-user store that **parallel crews append to concurrently** and that a single human drains in batch. The failure mode — silent loss of a raised hand — is identical to the reminder/close-queue failure modes, so the same Rust-owned-mutation discipline applies.

ADR-052's close-queue is the structural template (producer → queue → drainer), but its **schema is session-extraction-specific** (`git_range`, `snapshot_path`, the agy extraction contract, the nightly cron). None of that maps to "a workflow has a question." Per challenger W3 (2026-06-11), a full schema ADR was chosen over a lighter task-context-only convention. This ADR designs the **question-shaped sibling** and decides explicitly whether it shares plumbing with the close-queue (§7).

## Decision

### 1. A dedicated pending-questions store, Rust-owned mutation

`~/.claude/pending-questions.json` (per-user, cross-project — crews from any project raise hands into one human work-list) is mutated **only** by `brana hands` subcommands.

**Noun choice (resolved):** `brana queue` is already the live task-spawn command (`brana queue --max --auto`, `system/cli/rust/crates/brana-cli/src/cli.rs`), so — exactly as ADR-052 §1 took `close-queue` rather than colliding — the hand-raise surface takes the dedicated noun **`brana hands`**. This honors t-1974 C4 (a CLI subcommand-verb surface, no raw jq) while avoiding the collision. A **new** Rust core module **to be created at** `brana-core/src/hands.rs` will instantiate the **same locked-json substrate** the existing `brana-core/src/queue.rs` (close-queue) and `brana-core/src/remind.rs` (reminders) already use.

The Rust write path owns the invariants ADR-051 §1 / ADR-052 §1 settled:
- **Sidecar advisory lock** (`pending-questions.json.lock` — never the store inode, which atomic rename replaces).
- **Parse-before-write validation** — never replace the store from unparseable input.
- **mktemp-in-store-dir + atomic rename** (`/tmp` is tmpfs; cross-fs `mv` is copy+delete, not atomic).
- **serde evolution** identical to ADR-051 §4: no `deny_unknown_fields`; post-v1 fields `Option<T>`/`#[serde(default)]`; `version` parsed from `serde_json::Value` before strict deserialization; UTC RFC3339 timestamps.
- **Entry `id` is random** (`hq-` + 8 random bytes hex), never content- or time-derived — same-beat parallel raises would collide on a deterministic id (the ADR-051 id reversal). Idempotency is carried by `dedup_key` (§2).

### 2. Entry schema (v1)

```json
{
  "version": 1,
  "entries": [{
    "id": "hq-7c1f9a3b2e4d6088",
    "dedup_key": "t-2042:gate:merge-strategy",
    "task_id": "t-2042",
    "project": "thebrana",
    "branch": "substrate/feat/t-2042-x",
    "category": "gate",
    "severity": "interface",
    "question": "AC says 'merge to main' but ADR-060 forbids feature→main merges. Merge to dev?",
    "evidence": "ADR-060 §two-tier: feature branches merge to dev, never main.",
    "options": ["merge to dev (ADR-060 compliant)", "keep AC — needs ADR exception"],
    "raised_at": "2026-06-21T18:30:00Z",
    "run_id": "wf_46d92cbc-9fb",
    "state": "pending",
    "answer": null,
    "answered_at": null,
    "answered_by": null
  }]
}
```

- `task_id` (required) — the backlog task the crew was working. **The answer's source of truth is the task** (§6); the queue entry is the human's work-list pointer **and** the dispatch block (§5).
- `dedup_key = {task_id}:{category}:{slug}` — `slug` is computed crew-side and passed as a flag, opaque to the Rust layer (ADR-052 §3: dedup keys are mechanical, never re-derived at read time). A `raise` whose `dedup_key` matches an existing **pending** entry is a no-op returning that entry; answered/cancelled entries never absorb a re-raise.
- `category` ∈ `gate | unverifiable-ac | failed-verify | ambiguity` — the four hand-raise triggers, for human triage.
- `severity` ∈ `interface` (v1). **Only interface-severity blockers reach this store** — `micro` decisions are recorded in task context by the crew and **never raised** (see F10 resolution: `brana hands raise` rejects `--severity micro`). The enum is kept single-valued-but-typed for forward growth under §1's rules.
- `options` (`Option<Vec<String>>`) — enumerated choices for answer-by-selection; null when free-text.
- `run_id` (`Option<String>`) — the Workflow journal id, to trace a raise back to its crew run.
- `severity`, `options`, `run_id`, `answered_by` are post-v1-shaped (`Option`/`default`).

### 3. States and transitions

```
            raise                 answer <id> --answer …
   (none) ─────────▶  pending ───────────────────────────▶ answered ──(apply)──▶ task dispatchable
                         │
                         └── cancel <id> ──▶ cancelled   (question obsolete)
```

| State | Meaning | Set by |
|-------|---------|--------|
| `pending` | hand raised, awaiting human; **task is excluded from dispatch while any pending entry references it** (§5) | `brana hands raise` |
| `answered` | human supplied an answer; task not yet re-dispatched | `brana hands answer` |
| `cancelled` | question obsolete (task cancelled / answered out-of-band / re-scoped) | `brana hands cancel` |

Transitions are computed and persisted **only under the write lock** (ADR-051 §1). `prune` removes terminal entries (answered-and-applied / cancelled) older than 30 days.

### 4. The block is DERIVED from the store — not a `blocked_by` sentinel (challenger F5/F6 — BLOCKER resolution)

An earlier design injected a synthetic `needs-human:<id>` marker into the task's `blocked_by`. The challenger proved this **structurally inert**: `validate_task_runnable` (`brana-core/src/tasks.rs:1159`) resolves each `blocked_by` id to a task and treats unresolvable ids as *not blocking*, so the sentinel matched nothing and `queue_candidates` (`tasks.rs:1280`) would dispatch the task anyway — while `classify` (`tasks.rs:46`) showed it "blocked" in rollup. A write/display contradiction with a dispatch hole.

**Resolution: the dispatch block is a derived property of the pending-questions store, written once.** A task is "hand-blocked" **iff** the store holds a `pending` entry with that `task_id`. This is enforced in the dispatch path, not mirrored into `tasks.json`:

- **Required pre-Accepted Rust change:** `queue_candidates` (`tasks.rs:1280`) must exclude any task for which `hands::has_pending(task_id)` is true (a cheap read of the hands store). Equivalently, `validate_task_runnable` gains a hand-block check. This makes the block effective for **every** dispatcher — the foreman *and* `brana queue --spawn` — closing the hole the foreman-only sentinel left.
- **Required TDD:** a test asserting a task with a `pending` hand is absent from `queue_candidates`, and reappears once the entry leaves `pending`.
- **Rollup consistency:** `classify`/rollup show "blocked (hand raised)" from the same `hands::has_pending` source, so display and dispatch never disagree.

No sentinel, no `blocked_by` overload, no write/display contradiction. The block lives in exactly one place (the store) and is read, not mirrored.

### 5. The raise / answer / cancel transactions

**Raise (producer, crew):**
`brana hands raise --task-id <id> --category <c> --severity interface --question "…" --evidence "…" [--options "a|b"] [--dedup-key …] [--run-id …]`
Under the lock this: (1) appends the entry (or dedups against an existing `pending` one); (2) mirrors the question to task context as a `Q:` line (§6, best-effort); (3) pushes a notification (§8). **The block needs no extra write — it is the entry's `pending` existence (§4).** `--severity micro` is **rejected** (exit 1: "micro decisions are recorded in task context, not raised"). The crew issues one CLI call, never touches JSON, never runs git (ADR-052 §2; ADR-050 prompt-content rule).

**Drain (human, batch):**
1. `brana hands list --pending` — work-list grouped by `category`/`severity`.
2. `brana hands show <id>` — question + evidence + options + task link.
3. `brana hands answer <id> --answer "…"` (or `--option N`) — under the lock: sets `state=answered`, `answer`, `answered_at`, `answered_by`; mirrors the answer to task context as an `A:` line (§6). The task is now no longer `pending` in the store → **automatically dispatchable again** (§4), with no unblock write. The foreman's next beat re-queries `brana backlog query --status pending`, `queue_candidates` no longer excludes it, the crew re-dispatches and reads the answer from task context.

Each `answer` is an independent locked transaction; a parallel crew raising mid-drain serializes safely (ADR-052 §2). Nothing is auto-answered — answering is a human-only gate (ADR-050).

**Cancel:** `brana hands cancel <id>` → `state=cancelled` (question obsolete). **Doctor:** `brana hands doctor` is a `list`-time consistency check (§6).

### 6. Dual-write relationship — task is source of ANSWER, store is the WORK-LIST + the BLOCK

| | Task `context` | Pending-questions store |
|---|---|---|
| Holds | `Q:` / `A:` lines (human-readable, travels with the task forever) | structured entry + the dispatch block (§4) |
| Source of truth for | **the answer** (the crew re-reads it; survives prune; shown by `sitrep`/`backlog get`) | **the human's work-list** AND **whether the task is hand-blocked** |
| Lifecycle | permanent (task history) | transient (pruned 30d after terminal) |

The `Q:`/`A:` lines reuse the `AC:`-style machine-readable context convention. **Crucially, the context mirror is best-effort and NOT load-bearing for the block** (the §4 redesign): the block is the store entry, written atomically under one lock. So the F7 crash window shrinks to a cosmetic one — a crash after the entry write but before the context mirror leaves a correctly-blocked task whose `Q:` line is missing. `brana hands doctor` detects this (entry exists, no matching `Q:` line in task context) and re-mirrors. The block can never be lost to a partial write, because it is not a separate write.

### 7. Relation to ADR-052 — PARALLEL QUEUE, SHARED SUBSTRATE LIBRARY (explicit decision)

**Decision: a parallel, dedicated queue file — NOT a shared/generic queue store — built on a shared Rust substrate module, not copy-pasted plumbing.**

- **Separate store file & CLI noun.** `~/.claude/pending-questions.json` under `brana hands`, distinct from the close-queue under `brana close-queue`. The two queues have **disjoint schemas, producers, drainers, and cadence** (close-queue is machine-drained nightly by agy; pending-questions is human-drained on demand with judgment). A polymorphic `entries[]` with a `kind` discriminator would couple the agy extraction contract to the hand-raise contract — the schema-drift surface ADR-052 kept clean. The research doc states the close-queue schema "does not map to questions" (W3): a sibling, not a tenant.
- **Shared substrate, not shared file.** The locking + atomic-rename + serde-evolution + random-id machinery is already duplicated across `queue.rs` and `remind.rs`; `hands.rs` is the **third instance**. The t-1995 "generalized work queue" node (a real pending task, `blocked_by` t-1994 — not a vague deferral) should factor these three into one `store::locked_json<Entry>` substrate each store instantiates with its own typed `Entry`. This ADR's store is a *client* of that substrate (avoids the replicated-logic-tests-rot pattern).

### 8. Notification hook

A new (non-dedup) `raise` pushes a notification **through the existing reminder store** (ADR-051), not a new channel: the raise transaction calls the same core behind `brana remind write` with `--task-id <id> --priority high --dedup-key handraise:<task_id>:<category> --channels <…>` and text `"Crew raised a hand on <task_id> (<category>): <question first line>"`. Reminders already have session-start surfacing (ADR-051 §3) and delivery (ADR-054). A raised hand IS a "remind me to answer this"; the dedup_key collapses repeat raises into an occurrence count, not spam.

**Required implementation scope (challenger F11):** add a pure-`jq` dead-man line to `system/hooks/session-start.sh` (it is **not present today**), mirroring the close-queue dead-man check: `⚠ [Factory] N hands raised awaiting answers — brana hands list --pending` whenever `pending-questions.json` exists and the pending count > 0. The `jq` read is deliberately independent of the brana binary (a dead crew, a missing binary, and an orphaned raise all manifest as a non-empty pending queue; the monitor must not depend on the thing it monitors — ADR-052 §2 read-only exception).

### 9. Acceptance gate

Implementation (the `brana hands` surface, the §4 `queue_candidates` change, and crew/foreman wiring in t-1994) must not start until this ADR is **Accepted** (ADR-052 §8). Acceptance flips the frontmatter `status:` + the Status header. TDD for the implementation MUST include: (a) a **concurrent-raise race test** (two crews raise in the same instant, both survive — the test that encodes why this ADR exists, ADR-051 §6); (b) the **§4 dispatch-exclusion test** (pending hand ⇒ not in `queue_candidates`).

## Consequences

**Positive**
- A third store ships with day-one locking + race test — no deferred-hardening debt.
- One stuck task never stalls the factory; the block is a derived, single-write property — no inert sentinel, no rollup/dispatch contradiction.
- Reusing the reminder store for notification means zero new delivery surface; reusing the locked-json substrate means the implementation is mostly instantiation.
- The answer lives permanently with the task; the store stays a lean transient work-list + block.

**Negative / risks**
- **`queue_candidates` must read the hands store** — a new cross-store coupling in the dispatch hot path. Mitigated: `has_pending(task_id)` is a single cheap read; the alternative (the sentinel) was proven broken.
- **Third near-identical store** — justified only if the substrate is genuinely shared (§7); copy-pasted it's the replicated-logic-rot anti-pattern. Mitigation: §7 mandates the shared module; t-1995 generalizes it.
- **Best-effort context mirror** — a crash between entry write and `Q:` mirror leaves a blocked task with no visible question until `brana hands doctor` re-mirrors. Cosmetic (the block holds), but doctor must actually be implemented.
- **Severity gate is partly crew-side** — the store rejects `micro` at `raise` (F10), but the *decision* of micro-vs-interface is the crew's (t-1981/t-1994). Mis-tuning floods or starves the queue; the store only enforces "no micro stored."

## Alternatives considered

**Task-context-only convention (`Q:` lines + a `needs-human` tag) — the rejected lighter option (challenger W3, human decision).** Crew writes only `Q:` lines + a `needs-human` tag; foreman skips tagged tasks; human answers by editing context. **Rejected** by the human in favor of the full schema: (a) no structured `category`/`severity`/`options` → no triage, no answer-by-selection, nowhere typed for the severity line; (b) no `run_id`/`dedup_key` → no crew-run traceability, no same-beat dedup; (c) work-list and answer-of-record conflated in free text; (d) no notification surface. The full schema buys triage, idempotency, traceability, and a clean block at the cost of a third store — contained by sharing the substrate (§7).

**Synthetic `needs-human:<id>` blocker in `blocked_by` — the originally-drafted block mechanism, REJECTED after challenger F5/F6.** Proven structurally inert (`validate_task_runnable` ignores unresolvable blocker ids; `queue_candidates` dispatches anyway) and contradictory (rollup shows blocked, dispatch shows runnable). Replaced by the derive-from-store block (§4).

**Shared single `queue.json` with a `kind` discriminator.** Rejected (§7): disjoint schemas/producers/drainers/cadence; a union `Entry` couples the agy extraction contract to hand-raise. Shared substrate *library* yes; shared *file* no.

**Auto-answering / LLM resolves its own question.** Rejected: the point of a raised hand is the crew **couldn't** resolve it; auto-answering recreates the "confident garbage passes its own vague criteria" failure the definition-of-ready exists to prevent. Answering is a human-only gate (ADR-050).

**SQLite store.** Rejected for v1 (ADR-051 reasoning): runtime dependency, kills the jq-readability the dead-man check relies on, overkill for tens of entries.

## Open (deferred to build)

1. **Substrate extraction timing** — build `hands.rs` now as a third instance, or block on t-1995 generalizing first? Roadmap puts t-1995 after t-1994 (build now, generalize later), which defers the copy-paste-risk mitigation. Needs confirmation.
2. **`prune` of `answered`** — application-gated (prune only after the answer is confirmed applied / task re-dispatched, needs a sub-state) vs purely time-based at 30d. Time-based risks pruning an answered-but-not-yet-redispatched entry.
3. **Severity threshold ownership** — confirmed t-1981/t-1994's job; cross-reference the micro-vs-interface contract once t-1981 lands so the `severity` enum stays in sync.

## Challenger dispositions (2026-06-21, t-1993 AC)

Verdict: **RECONSIDER** (F5/F6 sev5 blockers). All findings addressed in this revision:

| # | Attack | Severity | Disposition |
|---|--------|----------|-------------|
| F1 | `brana queue` noun conflict confirmed; reasoning correct | sev2 | **Fixed** — `brana hands` noun, ADR-052 precedent cited (§1) |
| F2 | `queue.rs`/`remind.rs` exist; shared-substrate claim sound | sev1 | Proceed |
| F3 | `hands.rs` phantom present-tense framing misleads | sev3 | **Fixed** — reframed "to be created at `hands.rs`" (§1) |
| F4 | `brana remind write` + ADR-054 notify path confirmed | sev1 | Proceed |
| F5 | `needs-human:` sentinel inert: `validate_task_runnable` (tasks.rs:1159) ignores unresolvable ids; `queue_candidates` (tasks.rs:1280) dispatches anyway | sev5 | **Fixed (redesign)** — block DERIVED from the store; `queue_candidates` must exclude tasks with a pending hand (§4); required Rust change + test |
| F6 | write/display contradiction (rollup blocked, dispatch runnable) from the same root | sev5 | **Fixed** — rollup + dispatch both read `hands::has_pending` (§4) |
| F7 | dual-write crash recovery (`brana hands doctor`) phantom + unspecified; block could be lost | sev4 | **Fixed** — block is the entry's existence (single atomic write), not a third write; only the cosmetic `Q:` mirror is best-effort + doctor-healed (§6) |
| F8 | parallel-queue/shared-substrate sound; t-1995 a real task | sev2 | Proceed (§7) |
| F9 | same-beat race safety mirrors ADR-051/052 id-reversal | sev1 | Proceed |
| F10 | `micro` enum orphaned — schema admits it, raise contract forbids it, no gate | sev3 | **Fixed** — `brana hands raise --severity micro` rejected; store holds `interface` only (§2, §5) |
| F11 | session-start dead-man check promised but absent from live hook | sev3 | **Fixed** — named as explicit required implementation scope (§8) |
| F12 | `queue.rs:7` stale "via `brana queue`" doc comment | sev1 | Noted — cosmetic cleanup for the implementation |

> **Note:** the F5/F6/F7 resolution is a structural redesign (derive-block-from-store) of the block mechanism, not a patch. It directly answers the challenger's objection but was **not itself re-challenged** — verify the `queue_candidates`/`has_pending` exclusion and its race behavior at build (the §9 dispatch-exclusion test is the gate).
