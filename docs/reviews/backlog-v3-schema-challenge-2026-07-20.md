# Challenge Report — Backlog v3 Schema (Six Hats, Deep) — 2026-07-20

**Target:** [backlog-v3-schema.md](../architecture/features/backlog-v3-schema.md) + [ADR-065](../architecture/decisions/ADR-065-epic-as-hierarchy-top.md) (branch `docs/backlog-v3-schema`), paired with [brana-v3-redesign.md](../ideas/brana-v3-redesign.md)
**Mode:** Six Hats — White · Black · Yellow · Green — plus adversarial verification (2 skeptics × 10 findings, 20 verifier agents, ~1.2M tokens)
**Flavor:** Pre-mortem
**Verdict:** **PROCEED WITH CHANGES** — all changes applied to the docs in the same revision that added this report.
**Prior challenge:** [brana-v3-challenge-2026-07-19.md](brana-v3-challenge-2026-07-19.md) (parent redesign; its findings were excluded from re-litigation here).

## ⬜ White — Facts & Data

Verified exactly against live tasks.json (2,156 tasks) and the Rust CLI source: 2,156 total · 43 epics · `execution` 746 code / 3 autonomous · `type` task=1,825 vs `level` task=1,254 (total non-null 2,123 vs 1,442 — both favor `type`) · dx-tooling 492 tasks @ 89.2% · key:value tags genuinely net-new (1 colon-tag store-wide).

Mis-measured in the drafts (all corrected):

- **AC coverage:** "~13% (67 of ~500)" matched no computable measure. Real: **38 of 2,156 non-empty** (2 pending), ≈1.8%. The "233 tasks" figure counted null keys (84% null). Sibling docs disagreed with each other (11% vs 13%).
- **Pending:** 563, not 491. **Done-but-unmarked epics:** 11 fully resolved (17 at ≥80%), no threshold reproduces "~19". **Harness family:** 4 members, not 7.
- **`Option<Vec<String>>`:** exists only as the MCP/CLI input type — there is no typed Task struct; the store is untyped `serde_json::Value`.
- **Missed live consumers:** `stream` still on 72 tasks with `github_sync.labels.stream: true` actively emitting it; undocumented `active_initiative: "backlog-ui"` key in tasks-config.json.
- **Missing:** no named migration script / backup / dry-run story — despite `system/procedures/migrate.md` + 7 prior scripts in `system/scripts/migrate/` covering this exact class of change.

## ⬛ Black — Risks (post-verification severities)

| # | Severity (raw → verified) | Finding | Resolution applied |
|---|---|---|---|
| 1 | CRITICAL → **CRITICAL** [VERIFIED 2/2] | **Write-path sealing missing** — `set_field` (tasks.rs:787-790), CLI `cmd_add`, MCP `backlog_add` all accept `level`/`epic`; migration table named field fates but zero write surfaces; stale path silently resurrects retired fields (`inherit_epic` amplifies); precedent t-1344/t-1345 + in-code t-2263 drift comment | §Migration engineering item 2: 4-step sealing bundle as explicit task |
| 2 | CRITICAL → WARNING [VERIFIED] | `tags` type-polymorphic in production (2,071 array / 84 comma-joined string / 1 null) — D8's "flat string arrays today" premise factually wrong; string-typed tags already silently invisible to filters | Tags section: normalization precondition + validate.sh type check before key:value |
| 3 | CRITICAL → WARNING [VERIFIED] | Drift-cascade *trigger* doesn't exist (reconcile manual/interactive; nothing watches spec changes); query substrate was honestly scoped, wording over-promised | Reworded "queryable, not automatic"; trigger scoped as explicit wave task |
| 4 | CRITICAL → WARNING [VERIFIED] | `active_epic` promoted to load-bearing while **live-divergent at review time** (global copy named a non-thebrana epic; project-local copy absent → WIP cap would silently no-op; t-1883 guard is sync-time only) | Epic table: fail-loud resolution assertion on next/drainable/WIP paths |
| 5 | WARNING → WARNING [VERIFIED] | `log` appends = whole-file RMW on ~2.6MB store; correctness holds (blocking flock, t-2166) but wave-2/4 write volume is an unaddressed growth trajectory | Log section: wave-2 lock-contention test; shard-on-fail fallback |
| 6 | WARNING → WARNING [VERIFIED] | `shape` gates drainable/waves/L3 graduation with no owning function; the `claude -p`-over-tasks.json loop path is a live replication vector; divergence corrupts the graduation ledger | Shape row: single brana-core owner; loops must call CLI/MCP surface |
| 7 | WARNING → OBSERVATION | ∧-notation vs space-token grammar split is presentation-only (wave `--select` already defined as reusing `q`) | One-grammar statement + EBNF added |
| 8 | WARNING → WARNING [VERIFIED] | Store's `version: 1` exists but is never value-gated; stale binary writes `level` **and prefers it on read** (tasks.rs:148) | §Migration engineering item 3: version 2 stamp + value-gated load, wave-1 |
| 9 | OBSERVATION → **FALSE_POSITIVE** (1/2) | "Stacked advisory gates repeat the failure mode" — refuted: the unmarked-epic mess accreted under a *zero-signal* regime; advisory-with-computed-prompt is structurally different. Kernel kept: D4/D7 lacked promotion criteria | D4/D7: promotion criterion tied to spec-gate pilot review (2026-07-28), hard-block by default |
| 10 | OBSERVATION → OBSERVATION [VERIFIED] | "Deletes ≥ adds" holds for schema fields, not code surface (~8 net-new subsystems + 16-verb CLI in one ≤10-task wave) | Design-goals caveat: cost-baseline spike before wave commit; split waves |

## 🟨 Yellow — Value

- **The 20% that captures most of the win: `ac_state` + epic lifecycle (`status`/`wip_limit`)** — fixes both halves of the stated problem without spec/log/tags/waves.
- Undervalued: `spec:` as a free reverse-traceability matrix; `log` verdict rows doubling as a per-loop performance ledger; computed `shape` = zero-backfill rule changes; key:value tags as a future-selector escape hatch; `initiative:` tag preserving Linear sync at zero present cost.
- Overly conservative: D4/D7 one conditional from hard-block (→ promotion criteria added); D2 could silent-close when the contract is provably satisfied (left as-is — D2 stands).
- The schema is on the critical path for three of the parent plan's five waves; it *is* the outcome ledger wave 5 reads.

## 🟩 Green — Alternatives (12 generated; strongest)

1. **Lazy/on-touch migration** (compat shim `type = type ?? level`) — adopted as a named strategy option (§Migration engineering item 5, decided at plan time).
2. **Hygiene-first sequencing** — epic mark-done sweep + AC backfill + `ac_state` land week-1 value before any schema change — adopted as a plan-time variant in Next steps.
3. **3-verb CLI** (`q`/`act`/`log`) + LLM-composed queries — adopted as the intent-CLI starting shape in Next steps.
4. Waves as `waves.yaml` git-versioned config · `log` in git-notes · SQLite shim · `ac_state` derived from test state · budget-based WIP · nested waves — recorded, not adopted; revisit if the adopted shapes strain.

## 🟥 Red — Gut Signal

The three-axis design is right and survived the attack; what felt wrong was the spec standing on numbers that didn't survive measurement — and its most load-bearing input (AC content) being six times scarcer than believed.

## Cross-hat Themes

1. Re-measure before shipping claims — the decisions survived, the Problem-section numbers didn't.
2. Migration discipline already exists in-repo (migrate.md, 7 scripts, write-path pattern, version-guard pattern) — cite and apply, don't rediscover.
3. Single-source-of-computation for shape and the grammar before three consumers exist.
4. Sequencing consensus (Yellow ∩ Green): hygiene + `ac_state` + epic lifecycle first; heavier machinery after.

## Process notes

Gemini constraint-retrieval leg failed (headless permission denial) and was skipped per skill rule; the run used 4 native hat agents + 20 native verification skeptics. Findings logged to the decision log (1 CRITICAL, 5 WARNINGs).
