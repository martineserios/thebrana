# Context Budget Guard

## Before expensive operations

Before launching operations that consume significant context, estimate the cost:

- **5+ file reads** → ~10K+ tokens
- **3+ WebFetch calls** → ~50K+ tokens
- **5+ scout spawns** → coordination overhead ~5K+ tokens in main context

## Thresholds

- **Below 70% context used:** proceed normally
- **70-85% context used:** run `/compact` before the operation
- **Above 85% context used:** delegate the entire operation to a fresh subagent with a targeted prompt. Do not attempt it in main context.

## Bulk file edits (5+ files)

When editing 5+ files with similar changes, write a Python script instead of individual Read+Edit calls. This avoids loading all files into context.

Pattern:
1. Write a Python script that reads, modifies, and writes the files
2. Run the script once with Bash
3. Review the diff with `git diff`
4. Delete the script

## Scout and agent spawning

- Scouts MUST write findings to temp files (`/tmp/{task}-{N}.md`)
- Scouts return ONLY a 2-line summary, never full findings
- Main context reads temp files one at a time, summarizing each before reading the next
- Never read all scout outputs in a single turn

## WebFetch discipline

WebFetch injects 50-100K tokens per call. Treat it as expensive:
- Prefer WebSearch (returns snippets, ~1K tokens) over WebFetch (returns full page)
- In multi-source research, classify from metadata first, WebFetch only HIGH-priority items
- Max 2 WebFetch calls per scout, max 6 total per research session
