# Knowledge Pipeline — Research Session Digest

> Brainstormed 2026-04-13. Status: idea. Challenger review: passed (scope reduced from full insights command to lightweight digest).

## Problem

After processing a batch of URLs through the knowledge pipeline (tier1 → tier2 → tier3 → promote), there is no human-readable summary of what came through or what looks interesting for brana. The cluster report (`--report`) is structured data, not a digest. The user loses the connection between "I just processed 40 URLs" and "what should I pay attention to."

## Proposed solution

`brana knowledge insights [--session] [--brana]` — a thin wrapper around `call_claude_text` that reads the tier2 cluster report and produces a markdown digest.

### Flags
- `--session` — digest all today's clusters (default)
- `--brana` *(optional)* — adds to the prompt: "Which of these suggest an area where brana could improve, refactor, or add a feature?" Brana-scoped without architecture injection overhead.

### Prompt design (single pass)
> "Here are the research clusters processed today [cluster list + dimension targets]. Give a 1-2 sentence overview of each. Flag the top 3 as most interesting. Note: based on metadata-only summaries — treat as rough signal."
> With `--brana`: append the brana-scoped question above.

### Output
- `brana-knowledge/insights/YYYY-MM-DD.md` — browsable session log
- stdout — readable in the terminal immediately
- No ruflo storage. No auto-tasks.

## What was ruled out (challenger findings)

- **Full CLI + ruflo storage + auto-backlog** — ruled out because tier3 drafts are synthesized from metadata only (LinkedIn locked). Storing AI-on-AI confabulations in ruflo as `inspiration` entries would degrade memory_search quality system-wide.
- **`--add-tasks` with LLM specificity scores** — ruled out because scores would be uncalibrated. Task creation stays manual.
- **Two-pass prompting** — ruled out as premature. One pass is sufficient for a rough-signal digest.
- **HNSW dedup at write time** — ruled out due to staleness in batch mode (same-session entries not searchable until ruflo restarts).

**Revisit when:** t-1144 (full content fetch for tier1) ships. At that point the input quality supports a richer insights command with ruflo storage.

## Engineering disciplines
- **DDD:** No ADR needed — this extends the pipeline output, not its contract.
- **TDD:** Unit test for the digest prompt builder and file path generation.
- **SDD:** Update `inbox-to-dimensions-pipeline.md` (new optional step 6). Update CLI help.

## Command architecture

`insights` is a sibling subcommand under `brana knowledge`, not a flag on `process`:

```
brana knowledge process --tier1     # relevance filter
brana knowledge process --tier2     # cluster assignment
brana knowledge process --draft X   # synthesize cluster → draft
brana knowledge promote <path>      # append to dim doc, archive draft
brana knowledge insights            # ← digest what was just promoted
```

`insights` reads the output of `promote` (promoted dimension content), not of `process` (URL pipeline state). Keeping them separate maintains single-responsibility per subcommand.

After `brana knowledge promote` succeeds, CLI prints one nudge line:
```
  Tip: run 'brana knowledge insights' to get a digest of today's promotions
```

No auto-run. Just a reminder.

## Open questions (continue discussion)

- Should `insights` read the tier2 cluster report (what was clustered) or the promoted dim doc sections (what was written)? The cluster report is thinner but always available; the dim doc sections are richer but require reading N files.
- Should `--brana` inject a compact brana architecture summary or rely on the model's existing knowledge of brana? Injecting context improves specificity but adds tokens and requires maintaining the summary file.
- Lifecycle for `brana-knowledge/insights/` files — surface count in `/brana:review` weekly? Cap? Archive after N days?
- When t-1144 (full content fetch) ships, what does the upgrade path look like? Add `--store` flag that enables ruflo persistence once input quality is validated?

## Next steps
1. Add `insights_digest()` function to `knowledge_pipeline.rs` (reads pipeline state JSON + cluster report)
2. Add `insights` subcommand to `brana knowledge` CLI
3. Add `--brana` flag (optional brana-scoped question in prompt)
4. Wire output to `brana-knowledge/insights/YYYY-MM-DD.md` + stdout
5. Add nudge line to `brana knowledge promote` output
6. Unit tests for prompt builder and file path generation
