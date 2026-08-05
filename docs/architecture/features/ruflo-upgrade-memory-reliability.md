# Feature: Upgrade ruflo v3.10.39 → v3.34.0 and re-verify memory reliability

**Date:** 2026-08-05
**Status:** decomposing
**Task:** t-2627

## Problem

thebrana is pinned to ruflo v3.10.39 (released 2026-06-08) with no deliberate reason —
just staleness. Latest is v3.34.0 (2026-07-31), ~24 minor versions and 2 months behind.

**Correction (found during SPECIFY, 2026-08-05 — supersedes the original framing):**
`project_ruflo-agentdb-status.md` (the memory surfaced during LOAD) undersold this.
A more recent and more specific memory, `project_ruflo-memory-corruption-recurring.md`
(2026-07-16, t-2261), root-caused our actual corruption history to a defect still
**inside our pinned version's `node_modules`**: `hybrid-backend.js` hardcodes
`dualWrite: true` with no `db.transaction(...)` wrapping, and neither SQLite init path
sets `PRAGMA busy_timeout` (default 0ms) — so concurrent writers collide and can produce
B-tree (page-level) corruption. Independently corroborated upstream by ruvnet/ruflo#1257
(closed) and #2512.

**Verified live during SPECIFY: #2512 (the busy_timeout fix) is still OPEN, unmerged into
`ruvnet/ruflo` main** — the fix commit (`3b768bbc5`) exists only on a contributor's
non-fork branch (`Stricttype/ruflo`), never landed. `gh search commits --repo ruvnet/ruflo`
for `busy_timeout` and `dualWrite` returns zero hits in the actual upgrade range
(v3.10.39→v3.34.0). **The upgrade does NOT fix our corruption root cause.**

What the upgrade range DOES contain, relevant to memory reliability:
- **v3.32.34** ("Reliable Memory Writes on Existing Installations") — a *different* bug:
  a migration gap (missing `provenance_type` column, ADR-323) that could block
  `memory_store` writes on pre-ADR-323 DBs. Unrelated to the busy_timeout/dualWrite race.
- **PR #2749** (merged 2026-07-20, "refuse unsafe sql.js whole-image writes under a live
  native WAL writer") — also *adjacent, not the same bug*. It guards the sql.js
  whole-image-write fallback path (used when the native better-sqlite3 bridge is
  unavailable) by refusing to write when `-wal`/`-shm` sidecars indicate a live native
  connection. Structurally similar in spirit to our own wrapper's WAL-sidecar awareness,
  but it does not touch `hybrid-backend.js`'s `dualWrite` or set `busy_timeout` — the
  actual mechanism behind our historical corruption.
- **v3.33.0** ("AgentDB Retrieval Security Layer", ADR-377) — memory-poisoning defenses
  (retrieval pattern scan, write-anomaly detection) on the `memory_entries`/HNSW path
  `mcp__brana__recall` depends on. Off by default even upstream. Unrelated to corruption.

`system/scripts/ruflo-mcp.sh` carries a hand-built defense (checkpoint-a-copy integrity
check, t-2085/t-2260) built specifically because of this still-unfixed upstream defect.
**Given the root cause remains present in v3.34.0, this task's AC3 answer is expected to
be "keep, not simplify" — evaluation during BUILD should try to falsify that, not assume
the opposite.**

## Decision Record (frozen 2026-08-05)
**Context:** No upstream blocker exists (ruvnet/ruflo#1492, referenced in project memory
as an "Upstream-Blocked" tracker, is closed). No deliberate version pin exists in
tasks.json, scripts, or settings. Staleness is accidental.
**Decision:** Upgrade to the latest stable ruflo release across both install surfaces
(global npm + whatever the MCP wrapper resolves via nvm), then re-verify memory
reliability empirically rather than trusting the release notes alone. The upgrade is
justified by v3.32.34 (unrelated migration-gap fix) and v3.33.0/ADR-377 (retrieval
security, opt-in) — **not** by any claim that it resolves our corruption history, since
the actual root cause (missing `busy_timeout`, hardcoded `dualWrite`) remains unfixed
upstream as of v3.34.0 (verified: #2512 open/unmerged, zero relevant commits in range).
**Consequences:** Requires touching `system/scripts/ruflo-mcp.sh` (test-covered) and
possibly `docs/architecture/features/ruflo-integration-map.md` / the ruflo-agentdb
dimension doc. Does not require an ADR — we're adopting existing upstream mechanisms
(ADR-323, ADR-377), not designing new architecture. The AC4 decision on enabling the
ADR-377 retrieval guard gets recorded via `brana decisions log`, not a new ADR.

## Constraints
- Two install surfaces must move together: global npm (`npm install -g ruflo`, resolved
  via nvm) and whatever `system/scripts/ruflo-mcp.sh`'s version-detection walk picks up
  — a version skew between them reproduces the exact CWD/version-drift bug class already
  logged in `project_ruflo-agentdb-status.md`.
- `~/.swarm/memory.db` is live, used by every session across every project in
  `~/enter_thebrana/` — not just thebrana. The upgrade must not corrupt or lock out
  concurrent sessions during the DB migration.
- WAL mode itself is not the risk (t-2085 finding: three prior corruption events were
  root-caused to the flock+orphan-sweep pattern, which was removed — not to concurrent
  WAL writes). The custom checkpoint-copy check in `ruflo-mcp.sh` is a *read-only*
  diagnostic, not a mutating guard like the old orphan sweep — re-evaluating it is about
  redundancy, not about reverting to something known-unsafe.
- ADR-377's guards (`CLAUDE_FLOW_RETRIEVAL_GUARD`, `CLAUDE_FLOW_POISON_FORENSICS`) are
  off by default even in v3.33.0+ — enabling them is a separate, explicit choice from
  the upgrade itself.

## Scope (v1)
- Upgrade global ruflo install and confirm **both** wrappers resolve the new version:
  `system/scripts/ruflo-mcp.sh` (MCP server entry) AND `system/scripts/ruflo-cli.sh`
  (t-1936, "the single sanctioned CLI entry for ruflo" — feeds `session-start.sh` recall
  and both `cf-env.sh` variants). **Correction (sprint-contract review, 2026-08-05):**
  the two wrappers implement nvm resolution differently — `ruflo-mcp.sh` does an explicit
  `sort -rV` newest-first walk with a stale-shadow WARN; `ruflo-cli.sh` uses a plain glob
  (`for candidate in "$HOME"/.nvm/versions/node/*/bin/$name`, no version sort) and is
  objectively more shadowing-prone. Both must be verified independently, not just the one
  the original draft named.
- Verify `memory store` / MCP `memory_store` round-trips against the live
  `~/.swarm/memory.db`, per v3.32.34's own verification steps.
- Directly invoke `ruflo_mcp_db_is_healthy()` (the t-2085/t-2260 checkpoint-copy function)
  against a WAL-present DB copy post-upgrade and confirm it still returns healthy — not
  just "the test suite passes," which doesn't call this function at all (sprint-contract
  finding: `test-ruflo-mcp-single-instance.sh` only asserts absence of the old
  flock/orphan-sweep code and presence of the string "WAL"; it never exercises the
  function whose keep/simplify/remove decision is this task's actual AC3).
- Prove cross-project invocation still resolves post-upgrade: run `ruflo-mcp.sh` with an
  external `CLAUDE_PROJECT_DIR` (simulating one of the 21 other consumer projects) before
  merging to `dev` — the blast-radius mitigation this task commits to is only real if
  tested from outside thebrana's own checkout, not asserted in prose.
- Decide — and record — whether to enable `CLAUDE_FLOW_RETRIEVAL_GUARD` /
  `CLAUDE_FLOW_POISON_FORENSICS` (**ruflo's own ADR-377** — distinct numbering space from
  this repo's `docs/architecture/decisions/ADR-NNN`, no local collision, but easy to
  misread; always write "ruflo ADR-377" in task notes/decision-log text) given
  `mcp__brana__recall`'s dependency on this path.
- Update the ruflo-agentdb dimension doc's Version History table with a row spanning the
  full jump (**v3.10.39→v3.34.0**, not just the destination version — the table's existing
  rows already show this convention, e.g. "v3.6.30→v3.10.3").

## Research
- ruflo release changelog (v3.10.39 → v3.34.0) reviewed via `gh release view` /
  `gh search commits/prs --repo ruvnet/ruflo` — see t-2627 context for the full list.
- `field-note_ruflo-agentic-layer-subscription-theater.md`: confirms the memory/embedding
  store (what this task touches) is the *real*, working part of ruflo — distinct from
  the API-key-gated agentic MCP surface (agent_execute/hive-mind/swarm/neural), which
  stays out of scope for this task regardless of version.
- `project_ruflo-agentdb-status.md`: DB path (`~/.swarm/memory.db`), WAL corruption
  root cause (t-2085), `memory_store` vs `agentdb_batch` table split (`memory_entries`
  vs `episodes` — v3.32.34's migration only touches the table this task cares about).
- ruvnet/ruflo#1492 (referenced as the upstream-blocked tracker): confirmed **closed** —
  no live blocker to upgrading.

## Assumptions
- **Upgrade mechanism: `npm install -g ruflo@latest` is sufficient** to move both the
  npx-resolved CLI and whatever `ruflo-mcp.sh`'s nvm-walk picks up — needs confirmation
  during BUILD (the wrapper's version-detection logic walks multiple nvm-installed node
  versions, so a stray older install could still shadow the new one).
- **"Latest stable" means v3.34.0 at time of writing**, not a specific alpha/pre-release
  tag — chose this because v3.34.0 is the `latest` npm dist-tag as of 2026-07-31 — needs
  confirmation if a newer stable has shipped by the time this task executes.
- **The corruption-check logic in `ruflo-mcp.sh` should default to "keep unless proven
  redundant"** rather than "remove unless proven necessary" — chose this because
  weakening a safety check on a shared, multi-session DB is a higher-cost mistake than
  keeping a possibly-redundant one. **Strengthened by SPECIFY evidence:** the specific
  defect the check exists for (missing `busy_timeout`, hardcoded `dualWrite` in
  `hybrid-backend.js`) is confirmed still present upstream in v3.34.0 (#2512 open,
  unmerged) — this is no longer just a cautious default, it's the evidence-backed
  expectation. AC3's evaluation should look for reasons to *keep* it, not reasons to
  remove it — needs confirmation with the user only if BUILD finds contradicting
  evidence.

## Behavior
- Running `ruflo --version` (both the plain CLI and via `ruflo-mcp.sh`'s resolution
  path) reports the new version.
- `ruflo memory store` / MCP `memory_store` against `~/.swarm/memory.db` succeeds and
  the entry is retrievable via `memory_search`, confirming the v3.32.34 migration ran
  cleanly on our existing (pre-ADR-323) database.
- A decision on the ADR-377 env vars is recorded in task notes / decision log, not left
  implicit.

## Edge Cases
- **Live sessions during upgrade:** other projects under `~/enter_thebrana/` share
  `~/.swarm/memory.db` via their own ruflo MCP instances. If a concurrent session is
  mid-write during the npm upgrade, the running MCP process keeps using its already-loaded
  code until restarted — the risk window is the *next* MCP restart per project, not the
  npm install itself. Note this in BUILD; no code change needed to handle it.
- **Migration failure on our schema:** v3.32.34 is supposed to fail closed if the
  `provenance_type` migration can't run (read-only/locked/damaged DB) rather than
  presenting a misleading WAL-fallback message. Verify this is actually what happens
  rather than trusting the release note.
- **Wrapper resolves a stale nvm-installed version:** `ruflo-mcp.sh` walks
  `$HOME/.nvm/versions/node/*/bin/node` newest-first looking for `ruflo` — if an old
  version exists under a *newer* node install than the one just upgraded, the wrapper
  could pick the newer node/older ruflo pairing. **Concrete check (sprint-contract
  finding — the original draft left this eyeball-passable):** grep `ruflo-mcp.sh`'s
  stderr for its own WARN string (`ruflo found in nvm ... but nvm default is ...`) after
  invocation and assert absence, rather than trusting "no shadowing" as an unverified
  claim.
- **`ruflo-cli.sh` shadowing is a separate, higher-risk instance of the same class:** its
  plain-glob resolution (no version sort) makes it more likely than `ruflo-mcp.sh` to
  pick a stale install if multiple nvm node versions carry a `ruflo` binary. Must be
  checked independently — passing `ruflo-mcp.sh`'s check says nothing about
  `ruflo-cli.sh`.

## Design
Primarily an operational change, not a code design:
- `npm install -g ruflo@latest` (or equivalent pinned version) via the nvm default node.
- No changes anticipated to `system/scripts/ruflo-mcp.sh`'s core logic unless AC3's
  evaluation concludes the checkpoint-copy check should be simplified/removed — in which
  case it's a targeted edit to `ruflo_mcp_db_is_healthy()`, test-first.
- Env var decision (AC4) is a config choice, not a code change — set (or explicitly not
  set) `CLAUDE_FLOW_RETRIEVAL_GUARD` / `CLAUDE_FLOW_POISON_FORENSICS` in whatever
  environment ruflo-mcp.sh's MCP invocation reads from.

## Boundaries
| Always | Ask First | Never |
|--------|-----------|-------|
| Verify memory round-trip against the live DB before declaring success | Removing/weakening the t-2085/t-2260 checkpoint-copy check | Run the DB migration against a copy — must run against the real `~/.swarm/memory.db`, or the fail-closed behavior can't be genuinely verified |
| Update the ruflo-agentdb dimension doc's Version History | Enabling ADR-377 guards without checking their perf/false-positive cost on `mcp__brana__recall`'s hot path | Touch the API-key-gated agentic MCP surface (agent_execute/hive-mind/etc.) — explicitly out of scope, confirmed theater under subscription |
| Test any `ruflo-mcp.sh` edit thoroughly before merging to `dev` — 21 other projects (several active client engagements) run whatever is checked out at the main thebrana path the moment their MCP restarts, with zero deploy gate | Merging any `ruflo-mcp.sh` change without running its full test suite first | Treat a `dev`-branch merge of `ruflo-mcp.sh` as low-stakes because "dev isn't shipped yet" — that safety model doesn't hold for this file |

## Testing Strategy
- **Unit:** one new permanent test — invoke `ruflo_mcp_db_is_healthy()` against a fixture
  WAL-copy, added regardless of AC3's keep/simplify/remove outcome (2nd-review Warning 2:
  the neither-suite-calls-it gap this task exists to close would otherwise reopen for the
  *next* upgrade, since the spec's own predicted AC3 outcome is "keep" — no code change,
  no test triggered by the conditional rule alone). `ruflo-mcp.sh` ends in an unconditional
  `exec "$RUFLO" "$@"` with no test-mode hatch (unlike `ruflo-cli.sh`'s
  `RUFLO_CLI_DRYRUN=1`) — extract the function body for testing (e.g. `sed`-isolate it)
  rather than sourcing the live script, to avoid adding a new env-var branch to a file
  with 21 external consumers just for testability.
- **Integration:** re-run `tests/scripts/test-ruflo-mcp-single-instance.sh` and
  `tests/scripts/test-ruflo-cli-wrapper.sh` against the upgraded binary (existing
  coverage, target 90%+ of the test budget for this task). If AC3 concludes a code
  change to the checkpoint-copy logic, write a failing test for the new behavior first.
- **E2E:** manual `ruflo memory store` / `memory_search` round-trip against
  `~/.swarm/memory.db` (the AC2 verification step) — can't meaningfully be captured as
  an automated test since it depends on the live, shared DB state. Run it once under
  `CLAUDE_PROJECT_DIR=/tmp/fake-project` too, in addition to the plain environment
  (2nd-review Warning 3: the external-CWD check and the round-trip check otherwise don't
  overlap, so neither alone proves read/write correctness from an external project's
  CWD — the actual named blast-radius risk). `mkdir -p /tmp/fake-project` first — the
  wrapper silently falls back to `cd "$HOME"` if the directory doesn't pre-exist (line
  19's `-d` test), so an unprepared directory would make the check pass without
  exercising anything (2nd-review Warning 4).
- **Mock policy:** N/A — no new collaborators introduced.

## Documentation Plan
- [ ] **Tech doc** — this file, updated to `Status: implemented` at CLOSE.
- [ ] **Existing docs to update** — `brana-knowledge/dimensions/56-ruflo-agentdb-architecture.md`
      Version History table (new row for v3.10.39→v3.34.0, plus ADR-377/v3.32.34 notes).
- [ ] **User guide** — not applicable; this is an internal ops change with no
      user-facing behavior.

## Challenger findings

1. **Stale corruption premise (RECONSIDER, self-corrected during SPECIFY before this
   review completed)** — an earlier draft of this spec cited `project_ruflo-agentdb-status.md`
   (2026-06-03) for "WAL isn't the risk" without checking whether a more recent memory on
   the same incident class superseded it. It did:
   `project_ruflo-memory-corruption-recurring.md` (t-2261, 2026-07-16) root-caused a
   still-active defect (missing `busy_timeout`, hardcoded `dualWrite`) independently of
   t-2085's flock/orphan-sweep finding. Already corrected in this spec's Problem/Decision
   Record/Assumptions sections above — verified live that #2512 remains unmerged.

2. **Blast radius: `system/scripts/ruflo-mcp.sh` bypasses the normal dev/ship safety
   model (CONFIRMED, not yet mitigated in this spec).** thebrana's stated model is "dev
   is an integration buffer, nothing here is live; deploy happens only at ship" (merge to
   `main` + `bootstrap.sh`). That model assumes consumers read from `~/.claude/` (the
   `bootstrap.sh` deploy target). **It does not hold for `ruflo-mcp.sh`**: 21 `.mcp.json`
   files across `~/enter_thebrana/{clients,ventures,personal}/` and other thebrana
   worktrees hardcode the literal path
   `/home/martineserios/enter_thebrana/thebrana/system/scripts/ruflo-mcp.sh` — the live
   main checkout, not a `~/.claude/`-deployed copy. Several are active client engagements.
   **Any edit to this file that merges to `dev` is live for all 21 the moment their MCP
   next restarts — no `bootstrap.sh`, no ship step, no gate.** Verified: `grep -rl
   "thebrana/system/scripts/ruflo-mcp.sh" ~/enter_thebrana/*/.mcp.json
   ~/enter_thebrana/*/*/.mcp.json` → 21 files.

   **Mitigation adopted:** treat any edit to `ruflo-mcp.sh` in this task (AC3) with
   ship-level caution even though it merges to `dev`, not `main` — test thoroughly before
   merging, not after; prefer no change over a speculative "simplify" if evidence doesn't
   clearly support it (consistent with the "keep unless proven redundant" bias above, now
   reinforced by blast radius, not just caution). The global `npm install -g ruflo` upgrade
   itself is lower-risk by comparison — it's a single shared binary already, not a
   thebrana-specific artifact other repos reference by path.
