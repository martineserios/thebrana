---
title: Structured-field usage audit — tasks.json
status: research
task: t-3164
created: 2026-08-29
---

# Structured-field usage audit — tasks.json

Read-only audit of field fill rates across the brana backlog (ADR-086 T6). Data source:
`.claude/tasks.json` read directly (3111 tasks). Note: `brana backlog query --output json`
returns only 2861 tasks — it silently drops legacy statuses (`next`: 55, `active`: 4,
`archived`: 1) plus ~190 others; the file is ground truth for this audit.

**Root-caused and fixed 2026-08-30 (t-3233).** Not a status-parsing defect: `query`'s
default `--type` scope is `task,subtask` only, unconditionally excluding every
`phase`/`milestone`/`epic`/`initiative` node — 250 of the file's 3114 tasks at fix
time (50 phase + 139 milestone + 61 epic), which happen to be exactly where the legacy
`next`/`active`/`archived` vocabulary lives (only epic nodes use it, ADR-065). Re-verified:
`--output json` (default scope) returns 2864 with a new stderr note reporting the 250
excluded; `--type task,subtask,phase,milestone,epic,initiative` returns all 3114. Changing
the default scope was judged too risky (every existing consumer assumes it); the fix makes
the exclusion explicit instead (CLI: stderr note; MCP `backlog_query`: `excluded_by_default_type`
field) and, as a directly-adjacent fix, validates `--type`/`task_type` tokens so a typo
errors loudly instead of silently returning zero results — the same failure class, triggered
a different way, that this task exists to close.

**Total: 3111 tasks** — 1881 completed, 917 pending, 241 cancelled, 55 next (legacy),
12 in_progress, 4 active (legacy), 1 archived (legacy).

"Filled" = key present AND non-null AND non-empty (empty string/array counts as unfilled).
Excluded from any diet recommendation by construction: `context`, `notes`, `description`,
`acceptance_criteria`. Report only — no schema changes proposed.

## Summary table

| field | overall fill | pending fill | producer exists | reading |
|---|---|---|---|---|
| id / status / created | 3111/3111 (100%) | 100% | yes | core, mechanical |
| subject | 3110/3111 (100%) | 100% | yes | core |
| type | 3072/3111 (98.7%) | 97.5% | yes | core |
| priority | 2889/3111 (92.9%) | 93.9% | yes | healthy |
| tags | 2782/3111 (89.4%) | 92.5% | yes | healthy |
| effort | 2621/3111 (84.2%) | 87.7% | yes | healthy |
| parent | 2603/3111 (83.7%) | 79.5% | yes | healthy |
| kind | 2395/3111 (77.0%) | 78.3% | yes | healthy (v2 field, back-filled) |
| work_type | 2353/3111 (75.6%) | 74.9% | yes | healthy; overlaps `kind` (branch-prefix fallback) |
| context | 2101/3111 (67.5%) | 79.0% | yes | excluded from diet |
| description | 1721/3111 (55.3%) | 52.3% | yes | excluded from diet |
| execution | 1704/3111 (54.8%) | 68.2% | yes | healthy, rising on newer tasks |
| order | 1285/3111 (41.3%) | 43.4% | yes (add writes 0) | mechanical default |
| notes | 1037/3111 (33.3%) | 2.1% | yes | excluded from diet; completion-time field |
| completed | 1030/3111 (33.1%) | 0% | yes | lifecycle-mechanical |
| ac_state | 942/3111 (30.3%) | 41.9% | yes (validated; approve verb) | new (ADR-079); see below |
| started | 690/3111 (22.2%) | 0% | yes | lifecycle-mechanical |
| blocked_by | 613/3111 (19.7%) | 20.7% | yes | healthy for a dependency field |
| branch | 491/3111 (15.8%) | 0% | yes (backlog start) | lifecycle-mechanical |
| strategy | 297/3111 (9.5%) | 0% | yes (settable; build auto-classifies) | only written at build time |
| github_issue | 256/3111 (8.2%) | 6.4% | yes (settable) | producer exists, mostly unused |
| acceptance_criteria | 254/3111 (8.2%) | 8.6% | yes | excluded from diet |
| task_type | 40/3111 (1.3%) | 0.7% | no (legacy residue) | MCP `task_type` param maps to `type`; stray key |
| build_step | 32/3111 (1.0%) | 0% | yes (/brana:build) | transient by design |
| spawn | 16/3111 (0.5%) | 0.1% | yes (settable, validated) | producer exists, ~unused |
| proposed_acceptance_criteria | 10/3111 (0.3%) | 0.4% | yes (propose→approve flow, ADR-079/080) | new, barely started |
| isc | 8/3111 (0.3%) | 0% | yes (set_field +/- verbs) | producer exists, ~unused |
| linear_issue_id | 7/3111 (0.2%) | 0.1% | yes (`sync_linear.rs`) | scoped to ms-* sync |
| linear_milestone_id | 3/3111 (0.1%) | 0.2% | yes (`sync_linear.rs`) | scoped to ph-* sync |
| lease | 2/3111 (0.1%) | 0% | yes (wave-pull drain) | transient by design, auto-cleared |
| spec | 0/3111 (0%) | 0% | **no** (t-3007 to build) | unwired — absence of evidence |
| log | 0/3111 (0%) | 0% | **no** (t-3008 to build) | unwired — absence of evidence |

## ac_state coverage — the standing wave's frontier

Of **917 pending** tasks:

| ac_state | count | share |
|---|---|---|
| key absent entirely (legacy, pre-ADR-079) | 533 | 58.1% |
| `none` | 375 | 40.9% |
| `proposed` | 6 | 0.7% |
| `approved` | 3 | 0.3% |

**Callout:** only 3 pending tasks are `approved` and 6 more are `proposed` — 99.0% of the
pending backlog (908/917) has no AC motion at all. Any wave whose drain frontier is gated
on `ac_state: approved` is starved by coverage, not by approval throughput: the 58.1% with
the key absent don't even match an `ac_state` filter (legacy tasks never match, per the
query tool contract), so they are invisible to the frontier rather than merely unapproved.

## Methodology

Parsed `.claude/tasks.json` (read-only) with python3; for every key appearing on any task,
counted tasks where the value is present, non-null, and non-empty (empty strings and empty
arrays count as unfilled), overall and per status. Producer existence was determined by
grepping `system/cli/rust/crates/` (the `set_field` allowlist at
`brana-core/src/tasks/validation.rs:433-436`, `backlog_add.rs`, `sync_linear.rs`, wave/lease
code in `tasks/mod.rs`), `system/skills/`, and `system/scripts/` — excluding test code.
Essence: `filled = lambda v: v not in (None, '', [], {})`, then
`sum(filled(t.get(f)) for t in tasks)` per field per status bucket.

Lens applied (per feedback_backlog-field-usage-vs-feed-mechanism): a low fill rate means
"unwired" unless a producer exists; only "producer exists AND still unused" hints unwanted.

## Diet candidates (producer exists, still ~unused, low capability argument)

- **spawn** — settable and enum-validated since ~t-459; 16/3111 (0.5%) ever used, 1 pending.
- **isc** — full +/- set_field verbs exist; 8/3111 (0.3%), all on completed tasks.
- **github_issue** — settable; 256/3111 (8.2%) and skewed toward cancelled tasks (29.0%);
  weakest capability argument of the three above given `gh` CLI covers the linkage.
- **task_type** (stray key, not the MCP param) — no active producer writes a key named
  `task_type` (the add tool's param lands in `type`); the 40 occurrences are legacy residue.
  Cleanup candidate rather than schema diet.

Not diet candidates despite low fill: `lease`, `build_step`, `branch`, `started`,
`completed`, `strategy` (transient/lifecycle fields — low fill is by design);
`linear_issue_id` / `linear_milestone_id` (scoped by design to ph-*/ms-* sync);
`proposed_acceptance_criteria` / `ac_state` (new ADR-079 flow, adoption just starting).

## Unwired fields (no producer — absence of evidence, not evidence of absence)

- **spec** — 0/3111; zero write-path references in the Rust crates. t-3007 exists to build
  the producer. Fill rate says nothing about the field's worth.
- **log** — 0/3111; the only `"log"` hits in the crates are `git log` args and the feed
  command's unrelated `"log"` action. t-3008 exists to build the producer.
