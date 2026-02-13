---
name: morning
description: Daily operational check — stage-aware focus card with priorities, blockers, key metric, and optional calendar review
allowed-tools:
  - Read
  - Glob
  - Grep
  - Bash
---

# Morning — Daily Operational Check

Stage-aware daily review that produces a focus card. Pulls the last health snapshot, surfaces blockers, and shows what matters today. Read-only — nothing is written or modified.

## When to use

At session start on a venture project, or anytime you need to re-center on priorities. The daily-ops agent will eventually trigger this automatically via the session-start-venture hook.

---

## Step 1: Detect Stage

Check project docs for the current venture stage:

```bash
# Check CLAUDE.md for stage
[ -f ".claude/CLAUDE.md" ] && grep -i "stage" ".claude/CLAUDE.md"

# Check for venture-align output
ls docs/venture/ 2>/dev/null || ls docs/ 2>/dev/null

# Check for metrics docs (Growth+ indicator)
[ -d "docs/metrics" ] && ls docs/metrics/

# Check for OKRs (Growth+ indicator)
[ -d "docs/okrs" ] && ls docs/okrs/
```

If stage is unclear, ask: "What stage is this venture at? (Discovery / Validation / Growth / Scale)"

---

## Step 2: Pull Last Health Snapshot

Look for the most recent `/growth-check` output:

```bash
# Check docs/metrics/ for health snapshots
ls -t docs/metrics/health-*.md 2>/dev/null | head -1

# Search ReasoningBank for stored snapshots
CF=""
for candidate in "$HOME"/.nvm/versions/node/*/bin/claude-flow; do
    [ -x "$candidate" ] && CF="$candidate" && break
done
[ -z "$CF" ] && command -v claude-flow &>/dev/null && CF="claude-flow"

if [ -n "$CF" ]; then
    cd "$HOME" && $CF memory search --query "growth-check:$(basename $OLDPWD)" --limit 1 2>/dev/null || true
fi
```

Read the most recent snapshot found. Extract: key metric values, bottleneck, red/yellow items.

If no snapshot exists, note "No previous /growth-check found" and skip to Step 3.

---

## Step 3: Show Blockers

Scan for blockers and blocked items:

```bash
# Check GitHub Issues for blockers
gh issue list --label "blocker" --state open 2>/dev/null || true

# Check task files
grep -ri "block" docs/tasks/ 2>/dev/null || true
grep -ri "block" TODO.md 2>/dev/null || true

# Check for stale PRs
gh pr list --state open 2>/dev/null || true
```

Also check MEMORY.md for any flagged blockers from previous sessions.

---

## Step 4: Surface Now Priorities

Read the portfolio file and task list for current priorities:

```bash
# Portfolio file (cross-venture view)
[ -f "$HOME/.claude/memory/portfolio.md" ] && cat "$HOME/.claude/memory/portfolio.md"

# Project-specific Now/Next/Later
grep -i "now\|priority\|current" docs/tasks/ 2>/dev/null || true
grep -i "now\|priority\|current" TODO.md 2>/dev/null || true

# Check project MEMORY.md for recent context
ls "$HOME/.claude/projects/"*"/memory/MEMORY.md" 2>/dev/null
```

Extract the top 3 items from the Now list. If no structured task list exists, surface the most recent commitments from MEMORY.md or issue tracker.

---

## Step 5: Check Calendar (Optional)

If Google Workspace MCP is configured, check today's calendar:

```
# Only if Google Workspace MCP is available in .mcp.json
# Pull today's events: meetings, deadlines, external commitments
# Flag time-sensitive items that affect priority ordering
```

If not configured, skip this step. Do not prompt for setup — just omit the calendar section from output.

---

## Step 6: Output Focus Card

Output depends on the detected stage.

### Discovery Stage (light)

```
TODAY'S FOCUS — {Project Name}
Stage: Discovery | {date}

1. {Priority 1 — usually a customer conversation or research task}
2. {Priority 2}
3. {Priority 3}

Blocker: {top blocker, or "None"}
```

### Validation Stage

```
TODAY'S FOCUS — {Project Name}
Stage: Validation | {date}

1. {Priority 1}
2. {Priority 2}
3. {Priority 3}

Blocker: {top blocker, or "None"}
Watch:   {key metric from last /growth-check — e.g., "Activation rate: 18% (yellow)"}
```

### Growth Stage (full dashboard)

```
TODAY'S FOCUS — {Project Name}
Stage: Growth | {date}

PRIORITIES
1. {Priority 1}
2. {Priority 2}
3. {Priority 3}

BLOCKER: {top blocker, or "None"}

METRICS SNAPSHOT (from last /growth-check on {snapshot date})
| Metric | Value | Status |
|--------|-------|--------|
| {key metric 1} | {value} | {green/yellow/red} |
| {key metric 2} | {value} | {green/yellow/red} |
| {bottleneck metric} | {value} | {status} |

Bottleneck: {AARRR stage} — {one-line why}

CALENDAR: {today's meetings/deadlines, or "No calendar configured"}
```

### Scale Stage (comprehensive)

```
TODAY'S FOCUS — {Project Name}
Stage: Scale | {date}

PRIORITIES
1. {Priority 1}
2. {Priority 2}
3. {Priority 3}

BLOCKER: {top blocker, or "None"}

METRICS SNAPSHOT (from last /growth-check on {snapshot date})
| Metric | Value | Status | Trend |
|--------|-------|--------|-------|
| {key metric 1} | {value} | {status} | {up/down/flat vs previous} |
| {key metric 2} | {value} | {status} | {trend} |
| {key metric 3} | {value} | {status} | {trend} |
| {bottleneck metric} | {value} | {status} | {trend} |

Bottleneck: {AARRR stage} — {one-line why}

TEAM ITEMS
- {delegated item or pending review, if any}
- {hiring/contractor action, if any}

CALENDAR: {today's meetings/deadlines, or "No calendar configured"}
```

---

## Rules

- **Read-only.** This skill does not write files, update tasks, or store data. It only reads and presents.
- **Fast over thorough.** The morning check should take seconds, not minutes. If data is missing, show what you have and move on.
- **3 priorities max.** Never list more than 3 priorities. If there are more, pick the top 3 — the rest belong on a task list, not a focus card.
- **1 blocker max.** Show only the top blocker. Multiple blockers means the first one needs solving before worrying about the rest.
- **Stage-appropriate detail.** Discovery gets 3 lines. Scale gets a dashboard. Do not overwhelm early-stage ventures with metrics they do not track yet.
- **No data, no metrics section.** If no `/growth-check` snapshot exists, omit the metrics section entirely. Do not show empty tables.
- **Suggest /growth-check if stale.** If the last snapshot is older than 30 days, add a note: "Last health check was {N} days ago. Consider running /growth-check."
