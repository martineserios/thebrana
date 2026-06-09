---
status: research
task: t-648
date: 2026-06-09
produced_by: t-648
---

# Feature: Build Cost Tracking

## Problem

We lack per-build token cost data. Without it we can't answer: "Was adding the challenger gate worth the 20x cost?" or "Which tasks are outliers?"

Anthropic benchmark context: solo run = $9/20min, full harness = $200/6hr (~22x cost). We need our own baselines to know when harness overhead is justified.

## Key Finding: Data Already Exists

CC writes per-turn usage to `~/.claude/projects/{project_hash}/{session_uuid}.jsonl`.

Every `assistant` type entry has `message.usage`:

```json
{
  "input_tokens": 2,
  "cache_creation_input_tokens": 22269,
  "cache_read_input_tokens": 22693,
  "output_tokens": 654,
  "service_tier": "standard",
  "speed": "standard"
}
```

**This session** (2026-06-09, 83 turns, multi-task): $4.37 total.
- Input: 96 tokens (all cache hits)
- Cache creation: 329,681 tokens
- Cache read: 7,330,302 tokens
- Output: 62,356 tokens

## Pricing Reference (Sonnet 4.6, 2026-06)

| Token type | Price |
|-----------|-------|
| Input (non-cached) | $3 / MTok |
| Cache creation | $3.75 / MTok |
| Cache read | $0.30 / MTok |
| Output | $15 / MTok |

## Anchoring Mechanism

A build run spans _part_ of a session. To isolate build cost from total session cost:

1. **At build start** (LOAD step or skill sentinel): write to `~/.claude/run-state/{task_id}.jsonl`:
   ```json
   {"step": "BUILD_START", "session_uuid": "<from BRANA_SESSION_ID>", "ts": "ISO_TS", "transcript_path": "~/.claude/projects/.../session.jsonl"}
   ```
2. **At build end** (CLOSE step): read transcript from start timestamp forward, sum `message.usage` for all `assistant` entries after that timestamp.

`BRANA_SESSION_ID` is written by `session-start.sh` to `$CLAUDE_ENV_FILE`. Session transcript lives at `~/.claude/projects/{hash}/{session_id}.jsonl` — can reconstruct path from session ID + project hash.

## Log Format

```json
{
  "task_id": "t-648",
  "session_id": "abf85182",
  "strategy": "feature",
  "build_start": "2026-06-09T15:00:00Z",
  "build_end": "2026-06-09T17:00:00Z",
  "duration_min": 120,
  "tokens": {
    "input": 50000,
    "cache_creation": 120000,
    "cache_read": 3500000,
    "output": 25000
  },
  "model": "sonnet-4-6",
  "harness": "full|solo",
  "agent_spawns": 3,
  "estimated_cost_usd": 2.10
}
```

Written to: `~/.claude/run-state/build-costs.jsonl` (append-only).

## Implementation Plan

### Step 1 — Capture start marker (S)

In `build.md` LOAD step, after reading task metadata, write a start marker:
```bash
mkdir -p ~/.claude/run-state
SESSION_UUID=$(echo $BRANA_SESSION_ID)
TRANSCRIPT="$HOME/.claude/projects/$(echo -n $(pwd) | md5sum | cut -d' ' -f1)/${SESSION_UUID}.jsonl"
printf '{"step":"BUILD_START","task_id":"%s","ts":"%s","transcript":"%s","strategy":"%s"}\n' \
  "{task_id}" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$TRANSCRIPT" "{strategy}" \
  >> ~/.claude/run-state/{task_id}.jsonl
```

### Step 2 — Aggregate at CLOSE (S)

In `build.md` CLOSE step, before committing:
```bash
python3 ~/.claude/scripts/build-cost-calc.py {task_id}
```

Script reads start marker from run-state, scans transcript from that timestamp, sums usage, appends to `build-costs.jsonl`.

### Step 3 — Report command (S)

`brana build costs` CLI or `brana backlog get t-NNN --field cost` to surface per-task cost.

Or: grep build-costs.jsonl for the task_id.

## Complexity

- Step 1 + 2: S-effort (bash + 50-line Python script)
- Step 3 (CLI): depends on CLI work already in progress

## Constraints

- Transcript path requires reconstructing project hash from CWD — `echo -n $(git rev-parse --show-toplevel) | md5sum` gives it
- `BRANA_SESSION_ID` must be set before LOAD runs — it is (set at session start)
- Agent spawn cost: subagent turns appear in the SAME transcript (they're subagent entries under the session), so the aggregate will naturally include agent spawns without extra work

## Open Questions

1. How to capture `harness: solo|full` mode? Need a flag at build start.
2. Should compare `isc` pass rate alongside cost? (quality proxy)
3. Rollup by epic/strategy useful for the "20x question"
