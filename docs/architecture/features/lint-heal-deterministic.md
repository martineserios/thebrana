---
depends_on:
  - docs/ideas/memory-consolidation-kairos.md
  - docs/research/2026-04-08-cc-alignment-findings.md
informs:
  - docs/ideas/inbox-to-dimensions-pipeline.md
---
# Feature: Lint+Heal L2 — Deterministic Memory Consolidation

**Date:** 2026-04-10
**Status:** specced
**Task:** t-1075
**Depth:** L2 (deterministic — zero LLM, zero token cost)

## Problem

Brana accumulates Layer 2 knowledge across sessions but never consolidates it.
`/brana:close` appends, `/brana:retrospective` is user-triggered, MEMORY.md grows
unbounded (already at 206-line limit in thebrana). Three concrete failure modes today:

1. **Duplicate memory files** — same logical project has memory dirs under both
   `~/.claude/projects/clients/nexeye` and `~/.claude/projects/projects/nexeye`
   (the latter is a stale path after the portfolio reorganisation).
2. **Undocumented concepts** — high-frequency terms referenced across MEMORY.md
   files with no dedicated `feedback_*.md` or dimension doc.
3. **Frontmatter drift** — feedback/project files that pre-date the frontmatter
   convention may lack `name:`, `description:`, or `type:` fields, making them
   unroutable by `/brana:memory` and ruflo pattern search.

## Scope

**Layer 2 only.** This job never modifies Layer 1 (brana OS) artifacts:
`CLAUDE.md`, `rules/`, `hooks.json`, ADRs, skill frontmatter, CLI source,
or the "User Preferences — CRITICAL" section of `MEMORY.md`.
The implementation enforces this with a path allow-list; any write outside the
list aborts with a non-zero exit and an explicit error message.

**Writable paths (allow-list):**
```
~/.claude/projects/*/memory/feedback_*.md     ← imputation only
~/.claude/projects/*/memory/project_*.md      ← imputation only
~/.claude/memory/archive/YYYY-MM-DD/          ← dedup targets
~/.claude/memory/pre-lint-heal-YYYY-MM-DD/    ← rollback snapshot
~/.claude/lint-heal-report.md                 ← report output
~/.swarm/lint-heal-state.json                 ← gate state
~/.swarm/lint-heal.lock                       ← PID lock
```

## Capabilities (L2 — all deterministic)

### Pass 1 — Dedup

Scan all `feedback_*.md` and `project_*.md` under `~/.claude/projects/*/memory/`.
Group by `name:` frontmatter value.

**Stale-path rule:** when the same `name:` appears under a `projects/` dir AND a
`clients/` dir, archive the `projects/` copy. The `projects/` path is the stale
path after the 2026-04-06 portfolio reorganisation (`clients/` is canonical).

**Tiebreak (no stale path involved):** archive the less-recently-modified file.

**Never delete.** All archived files move to `~/.claude/memory/archive/YYYY-MM-DD/`
with their relative path flattened into the filename
(`projects__nexeye__memory__feedback_foo.md`). Recovery is a `cp` back.

### Pass 2 — Grep contradiction detection

Scan `feedback_*.md` and `project_*.md` only. **MEMORY.md is explicitly excluded**
(it deliberately documents both "prefer X" and "avoid X" for context; scanning it
would produce structural noise indistinguishable from real contradictions).

Detection heuristic: extract directional keyword + following tokens from each file.
Positive keywords: `prefer`, `always use`. Negative keywords: `avoid`, `never use`.

**Concept slug derivation:** take all tokens after the keyword (up to 4), lowercase,
hyphen-join. Example: `always use uv run python` → concept slug `uv-run-python`.
Strip trailing punctuation. Minimum 2 characters.

**Flagging threshold:** a concept is flagged only when it appears in ≥2 distinct
files with positive framing AND ≥2 distinct files with negative framing. A single
file pair is too noisy (one positive + one negative is common in brana's own memory).

**Surface only.** Findings go into the weekly report. No auto-fix. The user reviews
and marks resolved by adding `contradiction: resolved` to one file's frontmatter.

### Pass 3 — Frontmatter imputation

For each `feedback_*.md` / `project_*.md` with a complete `---` frontmatter block
but missing one or more required fields, fill in via deterministic heuristics:

| Field | Heuristic |
|-------|-----------|
| `name:` | Filename slug, stripping the `feedback_`/`project_` prefix |
| `type:` | `feedback` if filename starts with `feedback_`, else `project` |
| `description:` | First non-empty, non-markup content line after closing `---` (≤120 chars) |

Files without a frontmatter block (`---` delimiters) are skipped — creating
frontmatter from scratch is out of L2 scope.

### Pass 4 — Concept-reference surfacing

Scan all `MEMORY.md` files under `~/.claude/projects/*/memory/`.
Count word occurrences (≥8 characters, after stripping a stopword list).
Flag phrases with ≥10 occurrences that have no matching:
- `feedback_*.md` or `project_*.md` slug, or
- `brana-knowledge/dimensions/*.md` filename slug.

Surface in report only. The user decides whether to create a new pattern file.
Threshold is 10 (not 5) to avoid flagging structural boilerplate.

**Slug matching rule:** strip `feedback_`/`project_`/`reference_` prefix from
filenames and the path prefix from dimension doc paths; normalize hyphens and
underscores to `-`; compare against the counted word after the same normalization.
Example: concept word `session_memory` → normalized `session-memory`; matches
`feedback_session-memory.md` (after stripping prefix → `session-memory`) ✓.

## Non-negotiables

1. **Layer 2 only.** Hard path allow-list; exits non-zero if any write target is
   outside the list. Auditable in CI.
2. **Never delete, only archive.** Full path preserved (flattened) in archive dir.
   Recovery = `cp`.
3. **Lock file.** `~/.swarm/lint-heal.lock` stores the running PID. On acquire:
   check if stored PID is alive (`kill -0`). If dead, remove stale lock and
   continue. If alive, exit 1.
4. **`--dry-run` mode.** Shows every planned action without writing. Usable from
   terminal at any time — the "scheduler-only entry point" restriction applies to
   automated (non-human) invocation only.
5. **Rollback snapshot.** Before the first write, copy `~/.claude/projects/*/memory/`
   to `~/.claude/memory/pre-lint-heal-YYYY-MM-DD/`. One snapshot per day.
   Retained 7 days (cleanup on each run).
6. **Gate state.** `~/.swarm/lint-heal-state.json`:
   ```json
   {"last_run_ts": 1712345678, "session_count_since_run": 0, "last_run_date": "2026-04-10"}
   ```
   Updated at end of each successful (non-dry) run. `session_count_since_run` is
   reset to 0 on run; incremented by `session-start.sh` on each session start.
7. **Scheduler entry disabled on first deploy.** Enable manually after validating
   a dry-run.

## Scheduler gate (session-start.sh integration)

`session-start.sh` reads `~/.swarm/lint-heal-state.json` during Phase 2 (fast
local checks). Logic:

```
now - last_run_ts > 7 days  AND  session_count_since_run >= 5
  → surface in additionalContext: "[Lint+Heal due] Run: brana memory lint-heal --dry-run"
```

`session_count_since_run` is incremented on every session start across **any
project** (global, not project-scoped). This is intentional: lint-heal scans all
`~/.claude/projects/*/memory/`, so any session consuming memory contributes to
the consolidation need. After 5 sessions anywhere in the portfolio, the gate fires
on the next session where `SESSION_ID` and `CWD` are available.

## Report format

Written to `~/.claude/lint-heal-report.md` after each run.

```
# Lint+Heal Report — YYYY-MM-DD

## Summary
- Dedup: N files archived
- Contradiction candidates: N (surface only)
- Frontmatter imputed: N files
- Undocumented concepts: N

## Contradiction Candidates
- concept 'foo': positive in [feedback_use-foo.md], negative in [feedback_avoid-foo.md]

## Undocumented Concepts (≥10 refs, no dedicated doc)
- **session-memory** (14 refs) — no dedicated doc
- ...

---
Next action: `brana memory audit` to review candidates.
```

Surfaced at session start if report is ≤7 days old (one-line summary, not full
content).

## `/brana:memory audit` subcommand

Added to `system/procedures/memory.md`. Routes when argument is `audit`.

1. Read `~/.claude/lint-heal-report.md` (error if >7 days old or absent).
2. Show report summary inline.
3. Offer via AskUserQuestion:
   - "Review contradiction candidates" → walk through each, offer to mark resolved
   - "Review undocumented concepts" → offer to create a stub `feedback_*.md`
   - "Done"

## Files

| File | Change |
|------|--------|
| `system/scripts/lint-heal.sh` | New — all 4 passes, dry-run, lock, snapshot |
| `system/hooks/session-start.sh` | +gate check in Phase 2 + counter increment |
| `system/scheduler/scheduler.template.json` | +`lint-heal` job at `Sun *-*-* 15:00:00`, `enabled: false` |
| `system/state/scheduler.json` | Same addition |
| `system/procedures/memory.md` | +`audit` subcommand routing + procedure |

## Subtasks

| ID | Subject | Effort |
|----|---------|--------|
| t-1115 | Write `lint-heal.sh` | M | done 2026-04-10 |
| t-1116 | Inject gate into `session-start.sh` | S | done 2026-04-10 |
| t-1117 | Add scheduler entry (Sun 15:00, enabled after dry-run) | XS | done 2026-04-10 |
| t-1118 | Add `audit` subcommand to `procedures/memory.md` | XS | done 2026-04-10 |

All subtasks complete. Dry-run passed clean (0 dedup, 0 contradictions, 0 frontmatter gaps) on 2026-04-10 — scheduler job enabled.

## Implementation notes

- **Use `$HOME`, never `~`** in the allow-list and all path variables. `realpath -m`
  does not expand `~` when the path is quoted — `$HOME` is expanded by the shell.
- **`mkdir -p ~/.swarm`** in the lock-acquire block. Do not assume `~/.swarm/`
  exists; ruflo's CWD-mismatch fix means ruflo only creates it when launched from
  `$HOME`.
- **Archive filename flattening** uses `__` (double-underscore) as path separator.
  Current portfolio paths use single underscores — no collision today. Add a comment
  in the script noting the limitation for future path changes.
- **Mtime comparison** uses `stat -c %Y` (Linux). The host is Linux; no macOS
  portability needed for this script (it's a server-side scheduler job).

## Out of scope (L2)

- LLM contradiction adjudication → L3
- LLM content imputation → L3
- Draft article suggestion → L3
- Web search to fill gaps → L4
- `brana-knowledge/drafts/` staging directory → L3 (shared with D10 pipeline)
- MEMORY.md "User Preferences — CRITICAL" section → never
