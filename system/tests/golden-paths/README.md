# Golden-Path Snapshots

Reference recordings of successful skill executions. Format: `golden-path-snapshot-v1` — schema at `docs/architecture/features/golden-path-snapshot-schema.json`.

## Files

| File | Skill | Origin | Notes |
|---|---|---|---|
| `build-feature-small.json` | `/brana:build` | Authored 2026-05-04 | Small feature build with single subtask. Approximates the t-927 hyphen-keyword fix path. |
| `close-typical.json` | `/brana:close` | Authored 2026-05-04 | Typical session close with retrospective + handoff write. |
| `backlog-add.json` | `/brana:backlog` add | Authored 2026-05-04 | Single-task add via shorthand flags. |

## How these were captured

**v1 baseline:** authored by reading `system/procedures/{build,close,backlog}.md` and instantiating the schema with the canonical happy-path step sequence + tool calls + AskUserQuestion patterns. **Not** recorded from a live runtime — no capture harness exists yet (t-1208 / future tooling).

**v2 (planned):** real runtime captures via a recorder hook that emits the snapshot at session-end. Replaces these baseline files when shipped.

## Diffing

Use `t-755` (when shipped) for structured diff: tool sequence changes, step rename detection, AskUserQuestion option drift. Until then, `jq -S 'walk' a.json b.json | diff` is enough for visual inspection.

## Maintenance

When a procedure changes:
1. Regenerate or hand-update the affected snapshot.
2. Run `t-755` diff against the prior version (when shipped).
3. Commit the new snapshot in the same change as the procedure edit.
