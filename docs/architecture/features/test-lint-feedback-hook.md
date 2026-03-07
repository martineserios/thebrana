# Feature: Test/Lint Feedback Hook

**Task:** [t-043](../../.claude/tasks.json)
**Status:** implemented (2026-03-03), design doc post-hoc
**Challenger review:** 2026-03-03 — 2 critical bugs, 5 warnings

---

## Problem

Brana is blind to its own effectiveness. Claude runs tests, they fail, it edits code, runs again — but nobody records whether that cycle is improving or spinning. The flywheel metrics doc 14 promises are never computed without structured test/lint signals.

## Solution

Three hooks form an append-only event stream. At session end, 7 flywheel metrics are computed and stored.

## Architecture

```
DURING SESSION

  Claude runs a tool
        |
        |-- Success --> post-tool-use.sh --> classify + log
        |
        +-- Failure --> post-tool-use-failure.sh --> classify + cascade detect + log
                                                          |
                                                          v
                                                  /tmp/brana-session-{id}.jsonl
                                                          |
SESSION END                                               v
                                              session-end.sh
                                              |-- Count outcomes
                                              |-- Compute 7 flywheel rates
                                              |-- Store to claude-flow (Layer 1)
                                              |-- Write to sessions.md (Layer 0)
                                              +-- Detect system file drift

NEXT SESSION
                                              session-start.sh
                                              |-- Recall patterns
                                              |-- Surface correction patterns (Wave 3)
                                              +-- Check drift flags
```

## Outcome Classification

### Success path (post-tool-use.sh)

| Condition | Outcome |
|-----------|---------|
| Bash + test runner regex | `test-pass` |
| Bash + linter regex | `lint-pass` |
| Edit/Write + same file as previous | `correction` |
| Edit/Write + test file pattern | `test-write` |
| Everything else | `success` |

### Failure path (post-tool-use-failure.sh)

| Condition | Outcome | Extra |
|-----------|---------|-------|
| Bash + test runner regex | `test-fail` | error_cat: test-fail |
| Bash + linter regex | `lint-fail` | error_cat: lint-fail |
| Edit | `failure` | error_cat: edit-mismatch |
| WebFetch/WebSearch | `failure` | error_cat: network-fail |
| 3+ consecutive same target | any | cascade: true |

## Detection Patterns

| Pattern | Regex matches | Examples |
|---------|--------------|---------|
| Test runners | `npm test`, `npx jest/vitest/mocha`, `bun test`, `pytest`, `cargo test`, `go test`, `make test`, `./validate.sh` | `npx jest --coverage` |
| Linters | `eslint`, `flake8`, `ruff check`, `pylint`, `cargo clippy`, `golangci-lint`, `shellcheck`, `biome check`, `npm run lint` | `eslint src/` |
| Test files | `.test.`, `.spec.`, `/tests/`, `/test/`, `test_`, `_test.` | `auth.test.ts` |

## 7 Flywheel Metrics

| Metric | Formula | Healthy |
|--------|---------|---------|
| correction_rate | corrections / edits | lower = better |
| auto_fix_rate | fail→success pairs / failures | higher = better |
| test_write_rate | test-write / edits | higher = better |
| cascade_rate | cascades / failures | lower = better |
| test_pass_rate | pass / (pass + fail) | higher = better |
| lint_pass_rate | pass / (pass + fail) | higher = better |
| delegation_count | Task tool invocations | context-dependent |

## Auto-Fix State Machine

```
failure  "npm test"  --> prev_fail["npm test"] = 1
success  "auth.ts"   --> not in prev_fail, skip
test-pass "npm test" --> in prev_fail! fixes++, delete

Result: 1 fix / 1 failure = auto_fix_rate 1.00
```

## Two-Layer Storage

- **Layer 1:** claude-flow SQLite + HNSW. Keys: `session:{project}:{id}` (patterns), `flywheel:{project}:{id}` (metrics)
- **Layer 0:** `sessions.md` (always written), `pending-learnings.md` (L1 fallback)

## Known Issues (Challenger 2026-03-03)

### Critical

1. **awk field splitting** (session-end.sh:78): `@tsv` produces tabs, awk splits on whitespace. Fix: `-F'\t'`
2. **ruff regex** (post-tool-use.sh:38): `ruff(\s+check)?` matches `ruff format`. Fix: `ruff\s+check`

### Warnings

3. Missing: `yarn test`, `pnpm test`, `npm run test`, `mypy`, `tsc --noEmit`, `prettier --check`
4. Compound commands classified by first match only
5. Cascade requires 3 consecutive failures — edit interleaving breaks detection
6. `validate.sh` only matches `./validate.sh`
7. `grep -c` on compact JSON fragile to format changes

## Implementation Files

| File | Role |
|------|------|
| `system/hooks/post-tool-use.sh` | Success classification |
| `system/hooks/post-tool-use-failure.sh` | Failure classification + cascade |
| `system/hooks/session-end.sh` | Metric computation + storage |
| `system/hooks/session-start.sh` | Recall + drift detection |
