# Session Handoff — 2026-06-03

---

## 2026-06-03 — H5-H8 goal-completion heuristics + AC criteria (t-1828, t-1830)

**Mode:** FULL · 6 commits · 14 files · 3 tasks completed (t-1821, t-1822, t-1823)

### Accomplished
- **H5-H8 heuristics** in `system/hooks/goal-completion.sh`: file-contains, jq-query, command-exits-0 (allowlisted), git-log. Coverage: ~41% (H1-H4) → ~88% (H1-H8). Tests: 15/15 pass.
- **`docs/conventions/ac-criteria.md`** — new reference doc, all 9 AC: parseable forms with sandbox rules and H7 allowlist.
- **`system/procedures/build.md`** — AC: syntax block added in DECOMPOSE step.
- **`docs/architecture/hooks.md`** — inventory row updated: 8 heuristics, session binding, stale guard.
- **Correction**: MCP "task not found" is a CWD resolution issue in worktrees (not in-memory state) — debrief-analyst corrected the session summary's diagnosis.

### Next
1. **t-1826** (S, backlog-git-alignment) — `backlog add` should always assign epic — NOT completed (interrupted during LOAD)
2. **t-1824** (S, harness) — Research `/workflows` command and dynamic workflows in CC
3. **t-1825** (M, harness) — Research: skills as orchestrators of agent teams
4. **maintenance** — `/brana:reconcile --scope consistency,propagation` (system/hooks/ changed + errata E2026-06-03-1/2 pending)
5. **stash review** — `stash@{0}` on t-1827 branch has tasks.json + spec-graph.json changes (91 lines) — pop or drop before next t-1827 resumption

---

## North star
Exponential leverage: foundational platform tasks first, then maximize results from them.

---

## 2026-06-02 — docs maintenance (hooks.md inventory)

**Mode:** NANO · 1 commit · 1 file

### Accomplished
- `docs/architecture/hooks.md`: added `Stop` event to events table; added `goal-completion.sh` to Plugin hooks inventory; updated `session-end.sh` row to mention Phase 4 (`session-end-pattern-promotion.sh`).

### Next
1. **t-1713** (M, knowledge-pipeline, P1) — Scheduled memory consolidation (Auto Dream)
2. **t-1781** (M, knowledge-pipeline, P1) — `brana knowledge process-url` via ruflo browser
3. **maintenance** — `/brana:reconcile --scope propagation` (E2026-06-02-3)

---

## 2026-06-02 — harness-core foundational run (t-1702, t-1779, t-203)

**Mode:** FULL · 15 commits · 23 files · 3 tasks completed

### Accomplished

- **t-1702** (refactor): Model field audit — all 33 skills + 13 agents correctly assigned, no downgrades. One agy gap fixed: `build.md` LOAD step 2b now uses `agy_delegate` for graph-neighbor docs >100 lines. `brainstorm.md` ToolSearch updated.

- **t-1779** (feat): Full `/goal` auto-loop per ADR-047. `build.md` Step 0 reads `acceptance_criteria` + `AC:` lines, writes `~/.claude/run-state/active-goal.json`, calls `/goal`. New `goal-completion.sh` Stop hook: 4-heuristic criteria validation, auto-completes tasks on full pass. `Stop` event wired in `hooks.json`. 6 tests pass.

- **t-203** (feat): Pattern promotion pipeline. `session-start.sh` now writes recalled pattern KEYS to JSONL. New `session-end-pattern-promotion.sh` Phase 4: promote/demote ±0.1 conf based on correction_rate thresholds (<0.05 / >0.25). Audit log at `~/.claude/logs/pattern-promotion.jsonl`. 6 tests pass.

- **Errata:** E2026-06-02-3 — stale task context claiming build.md already uses agy (false; fixed).
- **Patterns:** audit-no-changes-valid-outcome, promotion-pipeline-needs-keys-not-text, commit-state-files-before-branch

### Next

1. **t-1713** (M, knowledge-pipeline, P1) — Scheduled memory consolidation (Auto Dream)
2. **t-1781** (M, knowledge-pipeline, P1) — `brana knowledge process-url` via ruflo browser
3. **maintenance** — Update `docs/architecture/hooks.md`: add goal-completion.sh + session-end-pattern-promotion.sh
4. **maintenance** — `/brana:reconcile --scope propagation` (E2026-06-02-3)
5. **t-1778** (in-progress) — acceptance_criteria Rust impl; unblocks t-1779 full field support

### Watch

- `goal-completion.sh` Stop hook is live — first real test next session with `AC:` lines in context.
- Pattern promotion log: `~/.claude/logs/pattern-promotion.jsonl` — check after a few sessions.
- Auto-state files (spec-graph.json, tasks-config.json) get dirty from backlog ops → **commit before branching** or worktree-gate blocks.

## What was done

| Task | Status | Summary |
|------|--------|---------|
| triage | done | Opus reprioritized 245 pending tasks → 5 P0, 15 P1 (leverage-first north star) |
| t-1771 | done | MCP_CONNECTION_NONBLOCKING=1 in settings.json + bootstrap.sh Step 4c2 |
| t-1773 | done | ToolSearch baseline spike → confirmed CC alwaysLoad (server boolean, not tool array) |
| t-1777 | done | alwaysLoad: true on brana server + ruflo instructions field (848B) + bootstrap.sh sync |
| t-1772 | done | hard_deny manifest (8 rules) wired to settings.json + bootstrap.sh Step 4c3 |
| t-1776 | done | ADR-047 acceptance_criteria schema — gates self-validating build loop |
| t-1778 | in-progress | TDD commit 1 done (3 failing tests); branch: cli-backlog-schema/feat/t-1778-acceptance-criteria |

## Key commits
- 0629c23 chore(triage): reprioritize pending tasks — exponential leverage north star
- 72f744a feat(harness): MCP_CONNECTION_NONBLOCKING=1
- 758747f research(harness): MCP Tool Search baseline
- 7f4afce feat(harness): alwaysLoad brana + ruflo instructions
- 5c584d1 feat(harness): hard_deny manifest
- 94d73df docs(adr): ADR-047 acceptance_criteria schema
- 4924955 test(t-1778): acceptance_criteria — 3 failing tests (TDD commit 1)

## Next session — pick up here

**t-1778 in-progress** (TDD commit 2): implement `acceptance_criteria` in `set_field` in `brana-core/src/tasks.rs`, add `--acceptance-criteria` flag to CLI `backlog add`, expose in brana-mcp `backlog_add`. Tests are written and waiting. Branch: `cli-backlog-schema/feat/t-1778-acceptance-criteria`.

**After t-1778:** t-1779 (build wiring) and t-645 (post-build evaluator — unblock from t-649 first: remove stale blocker since redesign uses CC subagents not Agent SDK).

**Wave B P0 remaining:** t-645 (post-build evaluator, L-effort — verify/remove t-649 blocker first).

## Learnings
- CC `alwaysLoad` is **server-level boolean** in .mcp.json, not a per-tool array as originally assumed
- `paths:` frontmatter in system/rules/*.md excludes file from 28KB context budget — use for manifest/reference files
- worktree-gate hook fires on compound `git stash && git checkout -b` — must commit dirty files first
- Doc gate checks staged files, not just edited files — always `git add` docs before attempting commit

## Open items
- `.mcp.json` and settings.local.json both set MCP_CONNECTION_NONBLOCKING per-server; global settings.json env may be redundant (low priority)
- t-645 blocker: remove t-649 from blocked_by (parked, API key constraint, redesign = CC subagents)

---

# Session Handoff — 2026-05-08 (late)

## What was done

| Task | Status | Summary |
|------|--------|---------|
| t-1367 | done | Archived docs/architecture/posttooluse-workaround.md → docs/archive/ with RESOLVED tombstone |
| t-1366 | done | Bootstrap restart sentinel: bootstrap.sh → /tmp sentinel → session-start.sh banner in additionalContext |
| t-054 | done | sync-notebooklm.py — hash-based dimension doc staging; tests (17/17); docs/reference/scripts.md; notebooklm-source pointer |

## Key commits
- 0f27dda chore(t-1367): archive posttooluse-workaround.md
- e35df36 feat(t-1366): bootstrap restart sentinel
- a2ff727 feat(t-054): sync-notebooklm.py
- a83d345 merge(feat/t-054-notebooklm-doc)

## State to be aware of
- **Orphaned stash**: `stash@{0}` from 0c41a64 (before cherry-pick). Contains superseded notebooklm-source.md + tasks.json change. Drop with `git stash drop stash@{0}` after confirming.
- **tasks.json dirty**: modified but not committed — CC Tasks from this close session. Will auto-commit in STASH-CLEANUP.
- **t-1379 filed**: triage pre-existing Venture project test failure in test-session-start.sh (1/29 failing).

## Next unblocked (thebrana)
- t-1379: triage test-session-start.sh Venture project case (XS)
- t-055: Test Audio Overview from dimension docs (web UI) — run sync-notebooklm.py first, upload, then test

## Next session
1. Drop stash: `git stash drop stash@{0}`
2. Run `uv run python system/scripts/sync-notebooklm.py` to stage dim docs for NotebookLM
3. Upload staged files and test t-055
