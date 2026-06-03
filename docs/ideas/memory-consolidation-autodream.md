# Memory Consolidation — Auto Dream Integration

> Brainstormed 2026-06-02. Challenger review 2026-06-03 (5 findings addressed). Status: idea.
> Backlog task: t-1713
> Related: [`memory-consolidation-kairos.md`](./memory-consolidation-kairos.md) (Lint+Heal methodology, L0–L4 depth layers)
> Related: [`dated-memory-files.md`](./dated-memory-files.md) (memory write gateway)

## Problem

Brana accumulates memory files across sessions but never compacts them. `/brana:close` adds
patterns; nothing ever goes back over the corpus to merge duplicates, resolve contradictions,
or normalize dates across months of accumulation. The result: redundancy, drift, growing
MEMORY.md index.

`lint-heal.sh` already implements L1/L2 deterministic cleanup (dedup, grep-contradiction,
frontmatter imputation, concept surfacing) and is **already running weekly** (enabled:true,
Sun 15:00) — not threshold-triggered, not session-aware. It manages its own state in
`~/.swarm/lint-heal-state.json` including a `session_count_since_run` counter.

CC's autoDream triggers after 24h + ≥5 sessions and produces 5–15% denser memory. Brana
has no equivalent.

## Proposed Solution

A threshold-triggered consolidation job that runs asynchronously when enough sessions
have accumulated, operating on the full `~/.claude/projects/*/memory/` corpus.

Three distinct jobs in the memory maintenance layer (none of these replaces the others):
- **`/brana:close` + debrief-analyst** — session extraction layer (modified: adds counter increment + flag write)
- **`lint-heal.sh`** — weekly deterministic L2 sweep (already running Sun 15:00)
- **`memory-consolidation.sh`** — threshold-triggered layer for what lint-heal doesn't do: debrief-flag consumption, date normalization, consolidation log (new)

## Architecture

```
~/.swarm/lint-heal-state.json  (EXISTING — extended, not replaced)
  {
    "last_run_ts": 1780409488,
    "session_count_since_run": 12,
    "last_run_date": "2026-06-02",
    "last_consolidation_ts": 0    ← NEW field added by memory-consolidation.sh
  }

~/.swarm/debrief-flags.jsonl   (NEW)
  { "timestamp": "...", "type": "contradiction", "file": "feedback_X.md",
    "action": "archive", "acted_on": false, "confidence": "high", "session": "..." }

/brana:close (modified — two additions):
  1. Increment session_count_since_run in lint-heal-state.json (+1 via atomic read-modify-write)
  2. After user approves an errata: extract memory file refs via regex
     → pattern: /\b(feedback|project|user|field-note)_[\w-]+\.md\b/g
     → for each matched file: append structured flag to ~/.swarm/debrief-flags.jsonl

Scheduler job: memory-consolidation (daily check, Mon–Sat 15:30 to avoid Sunday lint-heal overlap)
  1. Read lint-heal-state.json
  2. elapsed = now - last_consolidation_ts
     If NOT (elapsed > 24h OR session_count_since_run >= 5): exit 0 (fast no-op)
  3. If threshold met:
     a. Read debrief-flags.jsonl → for each entry where acted_on=false:
        - Check file exists in ~/.claude/projects/*/memory/
        - If exists: archive to ~/.claude/memory/archive/YYYY-MM-DD/
        - Mark acted_on=true in-place
     b. Date normalization: scan frontmatter created:/updated: fields across memory files,
        normalize to ISO 8601 (YYYY-MM-DD) via regex + date math, no LLM
     c. Write consolidation log → ~/.claude/memory/consolidation-log.md (append)
     d. Update lint-heal-state.json: set last_consolidation_ts=now
        (do NOT reset session_count_since_run — lint-heal.sh owns that reset)
```

**Note:** consolidation job does NOT call lint-heal.sh. Scope is explicitly limited to what
lint-heal doesn't do. This avoids lock collision and double-archiving. lint-heal continues
running independently on its weekly schedule.

## Trigger model

**OR logic:** fire when `(now - last_consolidation_ts > 24h) OR (session_count_since_run >= 5)`

Both values read from `~/.swarm/lint-heal-state.json`.

Rationale:
- AND logic (CC's model) fails silently if `/brana:close` is skipped (ctrl+C exits)
- OR logic ensures the time-based fallback always covers drift
- Sessions-based arm catches burst periods (8 sessions in one day) faster than weekly
- `session_count_since_run` is reset to 0 by lint-heal.sh on its weekly Sunday run; after
  that reset the time-based arm (24h) becomes the primary trigger until sessions accumulate

**W3 known caveat (accepted in v1):** The 24h arm can fire during a first session after
multi-day machine absence. Impact is low (archive-not-delete), so no mitigation in v1.
Future: add a `session_start_ts` guard — if a session started < 15 minutes ago, defer 30m.

## Debrief Integration

The debrief-analyst agent is **unchanged** — it returns human-readable markdown to the
main context. Integration happens in `/brana:close` via prose-to-flag extraction:

**Extraction mechanism in `/brana:close`:**
When the user approves an errata finding, `/brana:close` runs a regex pass over the approved
errata text before writing it to memory:

```
regex: /\b(feedback|project|user|field-note)_[\w-]+\.md\b/g
```

Any matched filename that exists in `~/.claude/projects/*/memory/` is treated as a superseded
file. For each match, close appends a structured flag entry:

```json
{
  "timestamp": "2026-06-02T10:00:00Z",
  "type": "contradiction",
  "file": "feedback_X.md",
  "action": "archive",
  "acted_on": false,
  "confidence": "high",
  "session": "main",
  "source": "debrief-analyst"
}
```

The consolidation job's flag-consumption step (step 3a) reads `debrief-flags.jsonl`, filters
`acted_on=false`, archives each matched file if it still exists, then marks it `acted_on=true`
in-place. Idempotent: if the file was already archived by lint-heal.sh between flag write and
consumption, the existence check skips it cleanly.

**Limitation:** Debrief errata must name the specific memory file to be flagged. Errata that
describe a general behavioral contradiction without citing a filename produce no flag. This is
a v1 constraint — the debrief-analyst can be extended in a later task to emit structured
`## Supersedes` metadata in its output when the contradiction is file-specific.

## Date Normalization

Scope: **frontmatter `created:` / `updated:` fields only** — deterministic regex + date math.
No LLM needed. Most memory files already use ISO dates; this is minor cleanup.

Forward enforcement: the `brana memory write` gateway (t-1731 / dated-memory-files.md) will
enforce ISO dates on all new writes, making normalization a one-time cleanup, not ongoing work.

## Risks and Mitigations

| Risk | Mitigation |
|------|------------|
| lint-heal.sh and consolidation job archive the same file (double-archive) | Consolidation job does NOT call lint-heal.sh; debrief-flag consumption checks file existence before archiving (idempotent) |
| Counter drift if close is skipped | OR trigger: 24h fallback fires regardless of session count |
| 24h arm fires during first session after multi-day absence (W3) | Accepted in v1 — archive-not-delete makes this recoverable; future: session_start_ts guard |
| Errata with no memory filename produces no flag | V1 constraint — future: extend debrief-analyst to emit `## Supersedes` metadata |
| NANO sessions inflate counter | Future enhancement: skip run if <N memory files modified since last consolidation |
| lint-heal.sh resets session_count_since_run on Sunday, erasing consolidation signal | Expected and correct — consolidation's last_consolidation_ts is the primary state; count is a secondary accelerator |
| Regex false-positive (matches a memory filename in a code block or comment) | `/brana:close` only regex-scans the errata section of debrief output, not the full session text |

## Engineering Disciplines

- **DDD:** ADR documenting trigger model (OR logic, global state file location, flag file format)
- **TDD:** Unit tests for threshold check logic (state file reads, OR condition, counter reset) + dry-run fixture test for lint-heal.sh
- **SDD:** Update `scheduler.template.json` lint-heal comment + update `memory-consolidation-kairos.md` status → "implementing L2 + threshold trigger + debrief integration"
- **Docs:** `docs/architecture/features/memory-consolidation-autodream.md` (this file becomes the feature doc after implementation)

## Next Steps

1. Extend `lint-heal-state.json` schema — add `last_consolidation_ts: 0` field; document in a companion schema file
2. Add to `/brana:close`: (a) increment `session_count_since_run` in lint-heal-state.json; (b) regex-scan approved errata for memory filenames; (c) append to `~/.swarm/debrief-flags.jsonl`
3. Write `system/scripts/memory-consolidation.sh` — threshold check + debrief-flag consumption + date normalization + consolidation log + update `last_consolidation_ts`
4. Register `memory-consolidation` in `scheduler.template.json` (Mon–Sat 15:30, enabled: true)
5. Write ADR — trigger model, state file extension, flag schema, scope split vs lint-heal
6. Write tests — threshold OR logic unit, flag-consumption idempotency (file already archived), regex false-positive guard, date normalization edge cases
