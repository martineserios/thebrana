---
status: accepted
---
# ADR-047: acceptance_criteria Schema — Gate for /goal Auto-Loop

**Status:** Accepted  
**Date:** 2026-06-02  
**Deciders:** Martín Rios  
**Tags:** backlog-schema, cc-features, goal, stop-hook, build

---

## Context

CC v2.1.139 introduced `/goal` — a completion condition that anchors multi-turn sessions and enables self-termination when the stated outcome is reached. Without structured criteria in the task definition, `/goal` strings are LLM-inferred prose that Claude might satisfy trivially or prematurely.

The design doc `docs/ideas/goal-adoption-brana-skills.md` identified the gap: structured `acceptance_criteria` in the backlog schema must come first. `/goal` becomes powerful only when it is generated deterministically from machine-readable assertions, not from free-text description.

This ADR locks the schema design and the wiring contract between backlog tasks, `/brana:build`, and the Stop hook. It gates t-1778 (Rust CLI impl) and t-1779 (/brana:build wiring).

---

## Decision

### 1. Schema — `acceptance_criteria` field

Add an optional `acceptance_criteria` field to the task schema. Type: array of strings. Each string is a **testable assertion** — a concrete, binary pass/fail statement about a system observable.

```json
{
  "id": "t-1778",
  "subject": "Add acceptance_criteria field to backlog schema",
  "acceptance_criteria": [
    "brana backlog get t-NNN returns acceptance_criteria array field (not null) when set",
    "backlog_set(field: acceptance_criteria, value: '[...]') persists valid JSON array",
    "backlog_set with non-array value returns validation error",
    "brana backlog add --json accepts acceptance_criteria key",
    "validate.sh Check 18 passes with acceptance_criteria present and absent"
  ]
}
```

**Rules for valid criteria items:**

- Must be falsifiable: "X does Y when Z" not "X works correctly"
- Must reference an observable: CLI output, file state, HTTP response, test pass/fail
- No implementation details: what, not how
- Max 10 items per task — scope signal; >10 means the task should be split

**What is NOT a criterion:**

- "Code is clean" — not observable
- "Tests pass" — too vague; name the test or behavior being tested
- "User can do X" — acceptable if X is specific and testable

---

### 2. /goal string — deterministic template, not LLM inference

When a task has `acceptance_criteria`, `/brana:build` generates the `/goal` string from a fixed template:

```
/goal "t-{id} done when: {criteria[0]} AND {criteria[1]} AND ... — verify all before marking complete"
```

For tasks with > 3 criteria, collapse to count reference:

```
/goal "t-{id} done when all {N} acceptance criteria pass — run /brana:build VERIFY to check"
```

**Rules:**

- Template is fixed — no LLM rewriting of criterion text
- `/goal` is set once at BUILD entry (after CLASSIFY), not re-set on each turn
- Tasks without `acceptance_criteria` use the existing prose `/goal` (description-derived anchor style)
- The goal string must not exceed 200 characters — truncate with count reference if needed

---

### 3. Stop hook behavior

The CC Stop hook fires when `/goal` self-terminates. At that point, `/brana:build` wires a validation step:

**On Stop event:**

1. Read the active task's `acceptance_criteria` from tasks.json
2. For each criterion, emit it as a check item to the user: `[ ] criterion text`
3. If all criteria are observable by the agent (CLI outputs, file existence, test results): run automated checks
4. If any criterion requires human judgment: surface the list and ask for sign-off
5. On full pass: auto-mark task `status: completed`, `completed: today`
6. On partial pass: report which criteria failed, leave task `in_progress`, do NOT auto-cancel

**Automated check heuristics** — the canonical, full grammar lives in
[`docs/architecture/ac-grammar.md`](../ac-grammar.md) (the single source of truth both
`/brana:backlog plan` lint and `goal-completion.sh` cite). The 8 patterns
`goal-completion.sh` actually implements:

| # | Criterion pattern | Automated check |
|---|-------------------|-----------------|
| 1 | `file ... exists` (path ends `.sh/.md/.json/.rs/.py/.ts/.js/.toml`) | `test -f path` under the work dir |
| 2 | `brana backlog get ... returns ...` | Run the CLI command, `grep -F` output |
| 3 | `validate.sh Check N passes` | Run `./validate.sh --check N` |
| 4 | `hook {name}.sh exists` | `test -f system/hooks/{name}.sh` |
| 5 | `file {path} contains "{string}"` | `grep -F` the file (rejects `/` and `..`) |
| 6 | `jq '{expr}' {file} returns "{value}"` | Run `jq`, string-equal (rejects `/` and `..`) |
| 7 | `"{command}" passes` | Run command (allowlist: cargo/pytest/bun/npm/yarn test, `bash tests/`, `./tests/`) |
| 8 | `changes to {path} committed` / `commit message contains "{s}"` | `git log` on path / `--grep` the message |
| — | Anything else | UNKNOWN → surface to user for manual sign-off |

> Drift note (t-2199): this table previously listed 4 patterns (including a
> `command exits 0` row the hook never implemented). Reconciled to the 8 the hook
> actually runs; future changes edit `ac-grammar.md` first.

---

### 4. Failure mode

**`/goal` exits without all criteria passing:**

- Do NOT auto-cancel the task
- Do NOT auto-mark complete
- Surface the failing criteria to the user as a checklist
- Leave task `in_progress` with a context note: `"goal exit: N/M criteria passed — manual review needed"`
- User decides: fix and re-run, or override-complete with `/brana:backlog done {id}`

**`/goal` fires prematurely (Claude self-terminates before real completion):**

- The Stop hook's criteria check catches this — if criteria fail, task stays open
- This is the primary defense against trivial self-termination

---

### 5. Backfill strategy

- `acceptance_criteria` is **optional** — existing tasks without it are unaffected
- Tasks without `acceptance_criteria` continue to use the current `/goal` anchor style (or no `/goal`)
- No migration script needed — the field is nullable; absence is valid
- When editing an existing task, criteria can be added via `backlog_set(field: "acceptance_criteria", value: "[...]")`
- `/brana:backlog plan` will prompt for criteria on new tasks with work_type `implement` (recommended, skippable)

---

## Rationale

**Why array of strings, not a schema with typed fields?**  
Typed fields (e.g. `{type: "cli", command: "...", expected: "..."}`) would enable fully automated validation but add authoring overhead and a parser. String assertions keep authoring fast while still being machine-parseable via heuristics. The heuristic checker covers the 80% case; human sign-off handles the rest.

**Why deterministic template, not LLM-generated /goal?**  
LLM-generated goal strings are non-reproducible and may be paraphrased in ways that make early termination easy. Fixed templates preserve the exact criterion wording, making it harder to satisfy trivially.

**Why optional backfill?**  
Mandatory backfill of 1,500+ tasks would be a high-friction migration with low ROI. The value comes from new tasks and in-flight P0/P1 tasks. Accept that legacy tasks lack criteria; add them opportunistically when a task is started.

---

## Consequences

- t-1778: Rust CLI adds `acceptance_criteria: Option<Vec<String>>` to task schema, MCP `backlog_set` accepts it, `backlog_get` returns it
- t-1779: `/brana:build` CLASSIFY reads criteria → sets `/goal`; Stop hook wires criteria validation
- `/brana:backlog plan` updated to prompt for criteria on implement tasks (non-blocking)
- validate.sh Check 18 extended: if `acceptance_criteria` present, assert it is a valid JSON array (not a string)
- No change to existing tasks — zero migration required

---

## References

- t-1778: Add acceptance_criteria field to backlog schema (Rust + MCP) — blocked by this ADR
- t-1779: /brana:build reads criteria → generates /goal + Stop hook validates — blocked by t-1778
- `docs/ideas/goal-adoption-brana-skills.md` — /goal adoption design and taxonomy
- `docs/ideas/cc-feature-adoption-v2.1.136-142.md` — acceptance_criteria prerequisite identified
- ADR-044: Initiative accumulator (related schema extension pattern)

---

## Amendment (t-2283, 2026-07-21): `ac_state` lifecycle field

The v3 forward-only slice (`docs/architecture/features/ac-state-forward-slice.md`) adds a
per-task lifecycle state to the acceptance criteria a task carries, without a migration of the
~2,100 legacy tasks.

**Field.** `ac_state` — one of `none` | `proposed` | `approved`. **Key presence is the
v3-management marker**, not the value:

- **Key absent** → legacy v2 task. Loops ignore it. No rewrite, no migration.
- **Key present** → task is under v3 AC management. `none` = managed, no AC proposed yet ·
  `proposed` = the ac-propose loop wrote a candidate AC (inert) · `approved` = human accepted (live).

Serde `Option::None` (absent) is deliberately distinct from `Some("none")` (present, valued
"none"); the two must not be collapsed. In the current Value-based store this distinction is the
raw JSON key's presence/absence.

**Write-path sealing (precondition).** CLI (`brana backlog set`) and MCP
(`mcp__brana__backlog_set`) both rewrite `tasks.json` through the shared
`load_raw` → `set_field` → `save_tasks` pipeline over a raw `serde_json::Value`, so unknown/new
fields already round-trip — sealing is structural for these two paths, guarded by a both-paths
regression test rather than new plumbing. `perform_rollup` writes tasks.json *outside* that
pipeline (its own read → partial mutation → save); it preserves untouched keys the same way and
carries its own `ac_state`-preservation regression test.

**Version gate.** `tasks.json` now carries a canonical **numeric** `version: 2`. Load
**auto-upgrades** (absent / `1` / the legacy JSON-**string** `"1"` the live file actually ships →
numeric `2` in memory; non-breaking, operator decision 2026-07-21 — not a hard reject that would
break the live backlog); save always stamps numeric `version: 2`, coercing legacy string stamps
to a number so integer checks stop silently missing them. Version reads route through
`version_as_int` (tolerates both number and string forms).

**Stamping.** `backlog add` (CLI + MCP) stamps `ac_state: none` on new tasks. Legacy tasks stay
key-less until explicitly opted in via `backlog set <id> ac_state none`.

**Consumer (out of scope here, unblocked by this slice).** The `ac-propose` loop drains
`ac_state == none` **minus** `work_type ∈ {research, review}` (research/audit tasks yield only
thin disjunctive ACs — route L2-only), writes `ac_state: proposed` + a candidate AC. **Proposed
ACs are inert** — they gate nothing until a human promotes them to `approved`. This keeps the
loop's mutation real but non-live. Exposed as `tasks::ac_propose_candidates`.

**Decoupled from `spec` for the MVP** — an AC can be approved without a spec (schema
open-question D7 deferred; revisit if D7 resolves otherwise).

- t-2283: v3 schema MVP — ac_state forward-only slice (this amendment)
- `docs/architecture/features/backlog-v3-schema.md` — full v3 schema (destination map)
- `docs/reviews/backlog-v3-schema-challenge-2026-07-20.md` — write-path sealing = surviving CRITICAL
