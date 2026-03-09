---
name: pipeline
description: "Sales pipeline tracking — leads, deals, conversions, follow-ups. Stage-aware CRM that works with markdown or MCP integrations. Use when tracking leads, updating deals, or reviewing pipeline health."
group: venture
allowed-tools:
  - Read
  - Write
  - Glob
  - Grep
  - Bash
  - AskUserQuestion
---

# Pipeline — Sales Pipeline Tracker

Track leads, deals, conversions, and follow-ups. A stage-aware CRM that works with markdown files by default and upgrades to Airtable/HubSpot MCP when configured.

## When to use

- Tracking a new lead or contact
- Updating a deal (stage change, notes, next action)
- Logging an interaction (call, email, demo, meeting)
- Marking a deal as closed (won or lost)
- Reviewing pipeline health before a weekly review or monthly close

---

## Step 1: Detect Stage

Check existing docs for venture stage:

```bash
# Look for stage in CLAUDE.md
[ -f ".claude/CLAUDE.md" ] && grep -i "stage" ".claude/CLAUDE.md"

# Look for existing pipeline
[ -d "docs/pipeline" ] && ls docs/pipeline/

# Look for growth-check snapshots (Growth+ indicator)
[ -d "docs/metrics" ] && ls docs/metrics/
```

If stage unclear, ask the user: "What stage is this business at? (Discovery / Validation / Growth / Scale)"

The stage determines the pipeline template (see Step 3 and stage-dependent templates below).

---

## Step 2: Load Pipeline

### Check for docs/pipeline/README.md

```bash
if [ -f "docs/pipeline/README.md" ]; then
    cat docs/pipeline/README.md
else
    echo "No pipeline found"
fi
```

If `docs/pipeline/` does not exist, ask the user: "This project doesn't have `docs/pipeline/` yet. Create it?" If yes, create with `mkdir -p docs/pipeline/` and initialize with the stage-appropriate template (see below).

### Check for MCP integrations

Probe for Airtable or HubSpot MCP availability:

```bash
# Check .mcp.json for configured CRM servers
[ -f ".mcp.json" ] && grep -i -E "airtable|hubspot" .mcp.json
[ -f "$HOME/.claude/settings.json" ] && grep -i -E "airtable|hubspot" "$HOME/.claude/settings.json"
```

If Airtable MCP is configured, use `mcp__airtable__*` tools to read/write pipeline data. If HubSpot MCP is configured, use `mcp__hubspot__*` tools. If neither is available, use markdown files in `docs/pipeline/`.

**Markdown is always the source of truth.** MCP integrations sync to/from markdown, they don't replace it.

---

## Step 3: Pipeline Action

Ask the user what they need (skip if clear from `$ARGUMENTS` or conversation context):

### Add Lead

Create or append to `docs/pipeline/leads.md`:

```markdown
### {Lead Name}

- **Source:** {where they came from}
- **Date added:** {today}
- **Stage:** New
- **Contact:** {email/phone/channel}
- **Notes:** {context — what they need, how they found us}
- **Next action:** {what to do next}
- **Follow-up date:** {when}
```

### Update Deal

Find the lead in `docs/pipeline/leads.md` or `docs/pipeline/deals.md`. Update stage, add notes, set next action. Record the stage change with a timestamp:

```markdown
- **Stage:** {New Stage} (was: {Old Stage}, changed: {today})
```

### Log Interaction

Append to the lead/deal record:

```markdown
#### {today} — {type: call/email/demo/meeting}

{Summary of interaction. Key points discussed, commitments made, next steps agreed.}
```

### Mark Closed

Move the record from active pipeline to `docs/pipeline/closed.md`. Record outcome:

```markdown
### {Deal Name} — {Won / Lost}

- **Closed date:** {today}
- **Value:** {amount, if applicable}
- **Stage duration:** {days from first contact to close}
- **Win/loss reason:** {why they bought or why we lost}
- **Lessons:** {what to repeat or avoid}
```

---

## Step 4: Calculate Metrics

After any pipeline change, calculate current conversion rates:

```
Pipeline Conversions
====================

Lead → Qualified:     {N} / {N} = {X%}
Qualified → Proposal: {N} / {N} = {X%}
Proposal → Closed:    {N} / {N} = {X%}

Overall:              {N} / {N} = {X%}
Average deal cycle:   {N} days
```

For Discovery stage, use simplified funnel: Contact → Interested → Engaged.
For Validation stage, use: Lead → Trial → Paid.
For Growth+, use full pipeline: Lead → Qualified → Demo → Proposal → Negotiation → Closed.

Count only deals that have moved past each stage (not deals currently sitting at a stage). Use closed deals for historical rates, active deals for pipeline volume.

---

## Step 5: Pipeline Snapshot

Render the current pipeline state as a table:

```markdown
## Pipeline Snapshot — {today}

### Active Pipeline

| Lead/Deal | Stage | Value | Days in Stage | Next Action | Follow-up |
|-----------|-------|-------|---------------|-------------|-----------|
| {name} | {stage} | {$} | {N} | {action} | {date} |

### Summary

| Metric | Value |
|--------|-------|
| Total leads | {N} |
| Active deals | {N} |
| Pipeline value | {$total} |
| Avg deal cycle | {N days} |
| This month closed | {N won} / {N total} |
| Win rate (all time) | {X%} |

### Conversion Funnel

{Stage-appropriate funnel from Step 4}

### Follow-ups Due

| Lead/Deal | Action | Due |
|-----------|--------|-----|
| {name} | {what} | {date — highlight overdue in bold} |
```

Flag any follow-ups that are overdue. Deals stalled for more than 2x the average stage duration get flagged as at-risk.

---

## Step 6: Store

### Save to docs/pipeline/

Update `docs/pipeline/README.md` with the latest snapshot. Keep `leads.md`, `deals.md`, and `closed.md` as the working files.

If `docs/pipeline/README.md` doesn't exist yet, create it with:

```markdown
# Sales Pipeline

**Stage:** {Discovery | Validation | Growth | Scale}
**Last updated:** {today}

## Current Snapshot

{Paste snapshot from Step 5}

## Files

- `leads.md` — active leads and contacts
- `deals.md` — qualified deals in progress (Growth+ only)
- `closed.md` — closed deals (won and lost) with learnings
```

### Store in ReasoningBank

```bash
source "$HOME/.claude/scripts/cf-env.sh"
```

If `$CF` is found:
```bash
cd "$HOME" && $CF memory store \
  -k "pipeline:{PROJECT}:{date}" \
  -v '{"type": "pipeline-snapshot", "stage": "...", "total_leads": N, "active_deals": N, "pipeline_value": N, "win_rate": N, "follow_ups_due": N, "overdue": N}' \
  --namespace business \
  --tags "client:{PROJECT},type:pipeline,stage:{STAGE}"
```

Also search for previous snapshots to enable trend comparison:
```bash
cd "$HOME" && $CF memory search --query "pipeline:{PROJECT}" --limit 5 2>/dev/null || true
```

Fallback: append summary to `~/.claude/projects/{project-hash}/memory/MEMORY.md`.

---

## Stage-Dependent Templates

### Discovery — Simple Contact List

At Discovery stage, there is no sales process yet. Track people you're talking to.

**File:** `docs/pipeline/leads.md`

```markdown
# Contacts

| Name | Role | Channel | Last Contact | Notes | Next Step |
|------|------|---------|-------------|-------|-----------|
| {name} | {role/company} | {email/twitter/intro} | {date} | {what they said} | {follow up how/when} |
```

No deal stages, no values, no conversion math. Just: who are you talking to, what did you learn, what's next.

### Validation — Basic Funnel

At Validation stage, you have a product and some traction. Track the basic conversion funnel.

**Files:** `docs/pipeline/leads.md`, `docs/pipeline/closed.md`

```markdown
# Pipeline — Validation Stage

## Funnel

Lead → Trial → Paid

| Lead | Source | Date | Stage | Trial Started | Converted | Value | Notes |
|------|--------|------|-------|---------------|-----------|-------|-------|
| {name} | {source} | {date} | {Lead/Trial/Paid/Lost} | {date or —} | {yes/no/—} | {$} | {notes} |

## Metrics

- Leads this month: {N}
- Trial conversion: {X%}
- Trial → Paid: {X%}
- MRR added: {$}
```

### Growth+ — Full Pipeline

At Growth and Scale stages, use the full pipeline with qualified stages.

**Files:** `docs/pipeline/leads.md`, `docs/pipeline/deals.md`, `docs/pipeline/closed.md`

```markdown
# Pipeline — Growth Stage

## Stages

1. **Lead** — inbound or outbound, not yet qualified
2. **Qualified** — confirmed budget, authority, need, timeline (BANT)
3. **Demo** — product demonstrated, stakeholders engaged
4. **Proposal** — proposal or quote sent
5. **Negotiation** — terms under discussion
6. **Closed** — won or lost

## Active Deals (docs/pipeline/deals.md)

| Deal | Company | Value | Stage | Owner | Days in Stage | Next Action | Close Date (est) |
|------|---------|-------|-------|-------|---------------|-------------|-----------------|
| {deal} | {co} | {$} | {stage} | {who} | {N} | {action} | {date} |

## Weighted Pipeline

| Stage | Deals | Value | Weight | Weighted Value |
|-------|-------|-------|--------|----------------|
| Qualified | {N} | {$} | 20% | {$} |
| Demo | {N} | {$} | 40% | {$} |
| Proposal | {N} | {$} | 60% | {$} |
| Negotiation | {N} | {$} | 80% | {$} |
| **Total** | {N} | {$} | — | **{$}** |
```

---

## Rules

- **Markdown first.** MCP integrations are optional upgrades, not requirements. The pipeline must work with zero external tools.
- **Don't invent data.** If a field is unknown, leave it blank or mark it "TBD." Never guess deal values or conversion rates.
- **Follow-ups are the highest-value output.** A pipeline without follow-up dates is just a list. Always ask for or suggest a next action and follow-up date.
- **Flag stale deals.** Any deal sitting at the same stage for more than 2x the average duration for that stage gets flagged. Stale deals are the #1 pipeline killer.
- **Record win/loss reasons.** Closing a deal without recording why is losing the learning. This feeds `/growth-check` and cross-client patterns.
- **Stage-appropriate complexity.** Discovery gets a contact list, not a weighted pipeline. Don't over-tool early-stage sales.
- **Store results in ReasoningBank when available, fall back to auto memory when not.**
- **Ask for clarification whenever you need it.** If the deal stage is ambiguous, the value is unclear, or you're unsure about the pipeline structure, ask.
