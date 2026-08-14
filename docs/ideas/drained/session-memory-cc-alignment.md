# Session Memory — CC Alignment Shape

> Brainstormed 2026-04-08. Status: **shape / brainstorm only — no implementation.**
> Upstream findings: [`../research/2026-04-08-cc-alignment-findings.md`](../research/2026-04-08-cc-alignment-findings.md) §D1.
> Related prior work: [`unified-session-state.md`](./unified-session-state.md) (implemented t-794, currently in production).

## Problem

Claude Code ships `session_memory` at `~/.claude/projects/<path>/.claude/session_memory` with a **fixed 8-section schema** (Current State / Files / Workflow / Errors / Codebase Documentation / Learnings / Results / Worklog), each ~2K tokens, total ~12K, auto-updated by a background extractor after model sampling. Init at 8K tokens into a session, refresh every 15K. **[VERIFIED]** from Zain Hasan blog quoting leaked source.

Brana already ships `session-state.json` at `~/.claude/projects/<path>/memory/session-state.json` with a different schema (`accomplished` / `learnings` / `next` / `backprop` / `doc_drift` / `state` / `metrics`). That schema was shaped in `unified-session-state.md` and implemented via t-794 (commits `928a598..679e28f`). It is the authoritative record for close / sitrep / session-start / session-end today.

The two schemas **overlap but do not line up**. CC's schema is organized around what you need to orient a new session (what are you working on? what files? what workflow? what errors?). Brana's is organized around what a human operator writes at session close (what got done, what was learned, what's next). They answer different questions — but they compete for the same job: continuity.

**Also note the path collision:** CC writes `~/.claude/projects/<path>/.claude/session_memory`; brana writes `~/.claude/projects/<path>/memory/session-state.json`. Two memory systems, two directories, one home. The naming accidentally tells a story — brana has `memory/` and CC has `.claude/`, and they're *siblings* under the same project dir.

## What the leak does and doesn't tell us

**Verified:**
- 8 section names (exactly)
- Token budgets per section (~2K) and total (~12K)
- Init trigger (8K tokens into session)
- Refresh cadence (every 15K tokens)
- Background extraction runs after model sampling

**Not verified (we're guessing):**
- **The file format itself.** Markdown with `##` headers? JSON? YAML frontmatter + sections? Nobody quoted the parser. Our options below assume markdown because that's what matches the closest convention (CLAUDE.md, MEMORY.md), but this is a guess.
- **Whether it's user-editable or read-only.** A background extractor writes it; can the user also write it?
- **Whether plugins can read it.** If yes, brana can consume it. If no, brana has to duplicate.
- **Whether it rolls forward between sessions or gets zeroed at session start.**

These unknowns matter because they change which of the three options below is even viable.

## Proposed shape (three options)

### Option A — Additive

**What:** Extend brana's existing `session-state.json` schema with a new top-level field called `session_memory` containing exactly CC's 8 sections. The existing fields (`accomplished`, `learnings`, `next`, etc.) stay untouched and continue to drive close / sitrep / session-start flows as they do today. The new field is a *secondary* representation generated from the primary fields.

**Mapping:**

| CC section | Derived from brana field(s) |
|---|---|
| `current_state` | `session_label` + active task (via `backlog_query status=in_progress`) + branch |
| `files` | `git diff --name-only HEAD~N..HEAD` for the session window |
| `workflow` | Active task's `build_step` + `strategy` + phase/milestone parents |
| `errors` | Errata findings from debrief Step 3 + anything classified `issue` |
| `codebase_docs` | `doc_drift.stale_docs` + changed files under `docs/` / `brana-knowledge/` |
| `learnings` | `learnings` array (1:1 mirror) |
| `results` | `accomplished` array (1:1 mirror) |
| `worklog` | `git log --oneline --since="<session start>"` + event-log entries matching session date |

**Budget enforcement:** Each section capped at ~1900 chars (≈500-token safety margin under CC's 2K) at close time. Truncation marker: ` … (truncated)`. Total payload capped at ~10K chars.

**Writer:** `/brana:close` Step 9 builds the `session_memory` block as part of the existing JSON payload before calling `brana session write`. Rust-side `SessionState` struct grows a new `session_memory: Option<SessionMemory>` field (serde optional, backward-compatible for old entries).

**Reader:** `/brana:sitrep` reads `session_memory.current_state` first (fastest orient), falls back to `accomplished`/`next` if empty.

**Cost:**
- ~1 hour rust struct extension + serialization tests
- ~1 hour close.md procedure update (Step 9 mapping logic)
- ~30 min sitrep.md procedure update
- Existing session history remains valid (new field is optional, old entries skip serialization)
- No migration needed

**Pros:**
- Minimum disruption to current flows.
- Backward compatible: old `session-state.json` files stay valid. Session history stays valid.
- If CC flips on a user-visible `session_memory`, brana can one-day *also* write to CC's path as a mirror.
- Tests required: just new-field round-tripping + mapping logic.

**Cons:**
- **Two sources of truth for the same data.** `learnings` appears in both the top-level field and `session_memory.learnings`. Rust serde duplication. Drift risk if one side updates and the other doesn't.
- **Budget enforcement is nominal** — we're capping chars but CC uses token counts. Close approximation (1 token ≈ 4 chars) is good enough until it isn't.
- Doesn't solve the path collision (still two separate files, still two memory directories under the project).

**Risk:** Low. Nothing pre-existing breaks. If CC's file format turns out not to be markdown, we can swap the rendering layer without touching the schema.

---

### Option B — Replace

**What:** Migrate brana's schema *to* CC's 8-section schema as the primary representation. Drop the `accomplished` / `learnings` / `next` top-level fields; keep `backprop`, `doc_drift`, `metrics`, `state` as metadata. Close / sitrep / session-start all rewrite around the 8 sections.

**Mapping:** Same as Option A, but one-way and permanent. No dual representation.

**Writer:** `/brana:close` builds the 8 sections directly (no intermediate `accomplished` array). The debrief-analyst agent's prompt changes: instead of "classify findings into errata / learning / issue," it becomes "populate these 8 sections from session evidence."

**Reader:** `/brana:sitrep` reads the 8 sections directly. Session-start displays `current_state` + `next` (next needs to be preserved as a separate field, since CC's schema doesn't have a next-actions slot — see risks below).

**Cost:**
- ~2–3 hours rust struct replacement (+ serde compatibility layer for old entries)
- ~3–4 hours close.md rewrite
- ~1 hour sitrep.md rewrite
- `session_history.jsonl` backward-read shim — old-format entries parse into a compat struct, displayed with a "legacy format" marker
- Migration script for any in-flight handoffs
- Debrief-analyst agent prompt rewrite
- **Rust binary rebuild needed before first post-migration close** (feedback_cli-binary-rebuild pattern)

**Pros:**
- **One schema to reason about.** Cleaner mental model. When CC ships its `session_memory` UI, brana's file is literally the same shape.
- Stop having two sets of sections covering the same ground.
- If we can read/write CC's actual file (assuming plugins can), brana becomes a front-end for CC's memory, not a separate layer.

**Cons:**
- **`next`-actions don't fit the 8-section schema.** CC's `session_memory` is retrospective — it has no "what to do next" slot. Brana's `next[]` is load-bearing (sitrep surfaces it, /brana:do keys off it). If we replace, we have to keep `next[]` as metadata alongside the 8 sections, which means Option B is actually "8 sections + some brana-specific metadata" — so it's not really a full replacement anyway.
- **Historical session state is now in the wrong shape.** `session_history.jsonl` has ~weeks of `accomplished` / `learnings` / `next` entries that now need compat rendering forever.
- The 8 sections are CC-shaped and don't describe some things brana tracks well: cross-project ADR references, venture-layer decisions, backlog rebalances.
- If CC changes its schema in a future version, brana is now stuck on the old one.
- High blast radius: all four tools (close, sitrep, session-start, session-end) need coordinated changes + rust binary rebuild + tests + old-format compat.

**Risk:** Medium-high. This touches t-794's shipped architecture directly.

---

### Option C — Mirror

**What:** Keep brana's existing `session-state.json` unchanged. Additionally write a **separate file** at `~/.claude/projects/<path>/.claude/session_memory` (CC's path) in CC's exact format, generated from brana's primary state at close time. Two files, one source of truth, one derived view.

**Writer:** `/brana:close` writes `session-state.json` as today, then *additionally* renders the 8-section file and writes it to CC's path. Rust CLI grows a `brana session render-cc` subcommand for the rendering.

**Reader:** brana never reads its own CC-mirror file (it's a one-way export). CC may read it (we don't know yet). `/brana:sitrep` continues reading `session-state.json`.

**Cost:**
- ~1 hour rendering function + CLI subcommand
- ~30 min close.md update
- ~30 min test coverage
- No schema change to existing `SessionState` struct
- No migration, no blast radius on existing tools

**Pros:**
- Safest option. Zero risk to current session-state flows.
- **One-way export** — if the rendered format is wrong, we just fix the renderer.
- If CC flips on a user-visible `session_memory` and it reads from that path, brana immediately integrates — no change required from the user.
- Rendered format can evolve independently as we learn more about CC's actual parser.

**Cons:**
- **Writes a file we can't read back.** If the background extractor writes to the same path, our close-time mirror clobbers CC's own updates (or vice versa). This is a data-loss risk that depends entirely on whether CC's background extractor is running on the same file.
- **Doubles disk I/O at close time** (minor).
- Doesn't actually align schemas — it's *coexistence*, not *alignment*. If the point is "handoffs become interchangeable with CC," this option only goes halfway.
- **Path collision risk is real.** The CC extractor is unreleased-but-compiled-in. If a future CC release enables it without a flag, brana's writer and CC's writer compete for the same file.

**Risk:** Medium. The write-without-reading pattern is brittle; if CC ever starts writing, we lose data.

---

### Option D — Do nothing (control)

**What:** Ignore the 8-section schema. Brana keeps its existing schema. Revisit when CC actually ships user-visible `session_memory`.

**Cost:** Zero.

**Pros:** Zero risk. Work that might be wasted isn't done. Consistent with "don't build on unverified community claims."

**Cons:**
- Brana's close artifact and CC's `session_memory` diverge in format forever.
- If CC ships a UI that reads its own format, brana's handoffs stay invisible to it.
- We lose the symbolic "brana is aligned with CC" positioning.

**Risk:** Zero, but opportunity cost if CC ships the feature.

---

## Comparison matrix

| Dimension | A Additive | B Replace | C Mirror | D Nothing |
|---|---|---|---|---|
| Effort (hours) | ~3 | ~8 | ~2 | 0 |
| Reversibility | High (drop field) | Low (historical schema) | High (delete file) | Trivial |
| Blast radius | Low | High | Low | Zero |
| Solves path collision | No | No | No | No |
| Aligned with CC on format | Yes (secondary) | Yes (primary) | Yes (via mirror file) | No |
| Works if CC never ships user-visible session_memory | Yes | Yes | Yes (wasted mirror) | Yes |
| Works if CC ships a *different* 8-section parser | Likely | Risky | Likely | N/A |
| Backward-compat with existing `session-history.jsonl` | Yes | Needs compat layer | Yes | Yes |

## Open questions (MUST be answered before picking)

1. **What is the actual file format of CC's `session_memory`?** Markdown, JSON, YAML, custom? We are guessing markdown. A single confirmed file quote kills this question.
2. **Is `session_memory` user-visible in any current CC release**, even behind a flag, or is it purely internal? If it's not user-visible, *any* alignment effort is premature.
3. **Can plugin hooks read/write CC's session_memory file**, or is the path owned by the core binary? This determines whether Option C is safe.
4. **Does brana's `next[]` field have a natural home in CC's schema**, or is it brana-only metadata forever? This shapes Option B's viability.
5. **Does CC's background extractor write the file during a session**, or only at session boundaries? This determines whether Option C is a race condition.
6. **Would CC ever *delete* the session_memory file between sessions?** If yes, Option C needs to re-write it on every session-start, not just session-end.

## Cheap experiments (to reduce the unknowns before committing)

Each is under 30 minutes and de-risks the decision:

- **E1.** Run a fresh CC session, let it hit 8K tokens, then inspect `~/.claude/projects/<path>/.claude/session_memory`. Does the file exist? What format? Is it readable?
- **E2.** Write a tiny PreToolUse hook that logs existence of `.claude/session_memory` every turn. Fire a session, see when it first appears, see how it grows.
- **E3.** From a plugin, attempt to read `.claude/session_memory`. If it succeeds and returns content, brana can consume CC's own memory as a reader (new option: **Option E — Consume, don't mirror**).
- **E4.** Check `settings.json` for a `sessionMemory.enabled` flag. If it's defaulted on, experiments E1–E3 produce real data. If it's defaulted off (which the leak suggests for Kairos — unclear for session_memory itself), nothing exists on disk to observe.

These experiments answer open questions 1, 2, 3, and 5 in under two hours of real work.

## Key design decisions (non-negotiable regardless of option)

1. **`unified-session-state.md` stays authoritative for brana's internal schema.** Whatever we pick, brana's *own* session state is still `session-state.json`. CC alignment is a representational concern, not an architectural replacement.
2. **The LLM never writes the file directly.** Same rule as t-794: build JSON, temp file, CLI validates. Adding 8-section content doesn't change that.
3. **Backward compatibility for session history.** `session-history.jsonl` entries from before the change must still parse.
4. **Budget enforcement is client-side.** Brana truncates at write time. We don't trust the LLM to respect the 2K-per-section cap.
5. **Whatever we pick, we document the open questions in the implementation doc** so the next session knows what was unverified at decision time.

## Risks (across all options)

| Risk | Applies to | Mitigation |
|---|---|---|
| CC file format is not markdown | A, B, C | Run E1 before writing any rendering code |
| CC background extractor overwrites brana's writes | C | Run E1–E3 to determine write ownership; skip Option C if contested |
| CC never ships user-visible session_memory | A, B, C | Low cost for A and C; B is harder to justify if this happens |
| 8-section schema changes in a future CC version | A, B, C | Keep rendering layer thin; isolate mapping logic |
| `next[]` has no home in the 8-section schema | B | Keep `next[]` as brana-specific metadata even after replacement (makes B partial) |
| We build the wrong thing because we didn't test first | All | E1–E4 before any schema changes |

## Recommendation

**None — this is a shape doc, not a plan.** The shape of the options is now on paper; the decision is the user's. The findings doc surfaces the tradeoffs but deliberately withholds a preferred option because the answer depends on E1–E4 results that do not exist yet.

If the user wants a direction to *explore*, the lowest-regret path is: **run E1–E4 first, then pick between A and C based on whether CC's file is plugin-readable.** But that's a meta-recommendation about process, not a pick between A / B / C / D.

## What is NOT in scope of this doc

- Memory consolidation / Kairos / autoDream — see `memory-consolidation-kairos.md` for D2
- Context budget documentation — see findings doc §D3
- PreQuery/PostQuery hook migration — see findings doc §D4
- Any implementation, migration, or CLI extension

## Next concrete step (pending direction)

- **If the user picks direction:** convert this shape doc into a feature brief under `docs/architecture/features/session-memory-cc-alignment.md` with chosen option marked, open questions closed, and scope tightened.
- **If the user asks for experiments first:** write a tiny spike doc scoping E1–E4 with expected outputs and rollback plan.
- **If the user picks D (do nothing):** close this shape doc as "considered, rejected," add a note to `cc-unreleased-features-tracker.md` (D7) to re-evaluate when CC 2.2+ ships.
