---
name: usage
description: "Token usage analytics — model distribution, activity trends, session efficiency. Use when checking usage patterns, evaluating model routing efficiency, or before rate-limit-sensitive work."
group: utility
---

# Usage Analytics

Read `~/.claude/stats-cache.json` and present a usage dashboard. This file is maintained by Claude Code and contains daily activity, model token counts, and session metadata.

## Process

### Step 1: Read stats cache

```bash
cat ~/.claude/stats-cache.json
```

If the file doesn't exist or is empty, report: "No usage data found. Stats are generated after your first Claude Code session."

### Step 2: Compute summaries

Parse the JSON and calculate:

**All-time totals:**
- Total sessions, messages, tool calls
- First session date → days active
- Messages per session (avg)
- Tool calls per message ratio

**Model distribution:**
From `modelUsage`, for each model:
- Output tokens (the work tokens — this is what the model produces)
- Input tokens
- Cache read tokens and cache creation tokens
- Model's share of total output tokens (%)

**Period activity (last 7 days, last 30 days):**
From `dailyActivity`, filter by date and sum:
- Messages, sessions, tool calls
- Average messages per day
- Most active day (highest message count)

**Model timeline:**
From `dailyModelTokens`, identify:
- When each model first appeared
- When the primary model switched (e.g., Sonnet → Opus on 2026-02-06)
- Current primary model (highest recent token share)

**Session patterns:**
From `hourCounts`:
- Peak hours (top 3 by session count)
- Active window (first to last hour with sessions)

### Step 3: Present dashboard

Format as a structured report:

```markdown
## Usage Dashboard — [date]

### Summary
| Metric | Value |
|--------|-------|
| Days active | N (since YYYY-MM-DD) |
| Total sessions | N |
| Total messages | N |
| Avg messages/session | N |
| Tool call ratio | N% of messages |

### Model Distribution
| Model | Output tokens | Share | Since |
|-------|--------------|-------|-------|
| [model] | N.NM | NN% | YYYY-MM-DD |

### Last 7 Days
| Metric | Value |
|--------|-------|
| Sessions | N |
| Messages | N |
| Avg msgs/day | N |
| Peak day | YYYY-MM-DD (N msgs) |

### Last 30 Days
[same format]

### Session Patterns
- Peak hours: HH:00, HH:00, HH:00 (UTC)
- Active window: HH:00 – HH:00

### Model Timeline
- YYYY-MM-DD: Started with [model]
- YYYY-MM-DD: Switched to [model]
```

### Step 4: Flag anomalies (optional)

If any day in the last 30 has > 3x the average daily messages, flag it:
```
Spike: YYYY-MM-DD had N messages (Nx average)
```

## Rules

- Read-only analysis — never modify stats-cache.json
- Present raw numbers, not dollar estimates (subscription pricing makes per-token costs meaningless)
- Use M/K suffixes for readability (1.2M tokens, 213K messages)
- Keep the output concise — one screen, not a report
