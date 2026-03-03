---
name: venture-onboard
description: Discover and diagnose a business project — stage classification, framework recommendation, gap report. Use when taking over a business project or starting work on a new venture for the first time.
group: venture
allowed-tools:
  - Bash
  - Read
  - Glob
  - Grep
  - Write
  - AskUserQuestion
---

# Venture Onboard

Diagnostic entry point for business projects. Scans what exists, identifies the business stage, assesses current management systems, recalls relevant frameworks and patterns, and outputs a diagnostic report.

**Analog of:** `/project-onboard` (diagnostic, read-only)

## When to use

First session on a new business project, when taking over an existing venture, or as a periodic health check to reassess stage and gaps.

---

## Step 1: Discovery Interview

Ask the user — skip anything that's obvious from existing docs:

1. **What's the business?** — one-sentence description. Product, service, marketplace, consulting, SaaS?
2. **What stage are you at?** — idea / validated / growing / scaling? Revenue? Team size?
3. **Current tools and processes?** — CRM, project management, financial tracking, communication tools.
4. **Pain points?** — what's breaking? What takes too long? Where do things fall through cracks?
5. **What management frameworks are you using (if any)?** — EOS, OKRs, Scrum, Shape Up, ad hoc?

## Step 2: Detect Existing Structure

Scan the project directory for business artifacts:

```bash
# Look for business-related directories and files
for d in docs docs/decisions docs/sops docs/okrs docs/metrics docs/meetings; do
    [ -d "$d" ] && echo "Found directory: $d"
done

# Look for business documents
for pattern in "*.md" "*.pdf" "*.docx" "*.xlsx"; do
    count=$(find . -maxdepth 3 -name "$pattern" 2>/dev/null | wc -l)
    [ "$count" -gt 0 ] && echo "Found $count $pattern files"
done

# Check for CLAUDE.md
[ -f ".claude/CLAUDE.md" ] && echo "Found: .claude/CLAUDE.md"
```

Look for indicators: business plans, pitch decks, financial models, SOPs, OKR docs, meeting notes, decision logs, customer research, competitor analysis.

### Data Completeness Audit

If the business uses external data stores (Google Sheets, databases, CRMs), audit data completeness. Many ventures have the structure but not the data — empty tables are a common gap.

```bash
# Check for spreadsheet references
[ -f ".claude/CLAUDE.md" ] && grep -iE "spreadsheet|sheet_id|workbook" ".claude/CLAUDE.md"
```

If data sources are found, assess each table/sheet:

| Table | Rows | Key Gaps | Status |
|-------|------|----------|--------|
| {table_name} | {count} | {missing columns or empty fields} | Complete / Partial / Empty |

**Common data gaps in early-stage ventures:**
- Client acquisition channel not tracked (who referred them?)
- Cash flow not reconstructed from transactions
- COGS only captures external purchases, not internal production
- No referrer/partner attribution linking
- Stock/inventory not reconciled with sales

Present the data completeness matrix alongside the structural gap report. Empty tables with correct headers are "partial" — the schema exists but the data doesn't.

## Step 3: Stage Classification

Map the discovery answers to the four business stages from [28-startup-smb-management.md](~/enter_thebrana/brana-knowledge/dimensions/28-startup-smb-management.md):

### Discovery Stage
- **Signals:** No revenue or pre-revenue. Team of 1-3. Exploring problem space. No repeatable process yet.
- **Key question:** "Do we have a problem worth solving?"
- **Risk:** Building before validating. Premature scaling is the #1 startup killer (Startup Genome).

### Validation Stage
- **Signals:** Some revenue or strong engagement signals. < $1M ARR. Team of 2-10. Running experiments.
- **Key question:** "Do we have product-market fit?"
- **Risk:** Scaling what hasn't been validated. Hiring before PMF.

### Growth Stage
- **Signals:** Repeatable revenue. $1-10M ARR. Team of 10-50. Processes starting to break.
- **Key question:** "Can we scale this repeatably?"
- **Risk:** Process debt compounds. What worked at 10 people breaks at 30. Founder becomes bottleneck.

### Scale Stage
- **Signals:** Established revenue. $10M+ ARR. Team of 50+. Multiple product lines or markets.
- **Key question:** "Can we sustain growth without the founder in every decision?"
- **Risk:** Bureaucracy kills speed. Innovation stalls. Culture dilutes.

**Present the classification to the user and ask for confirmation.** Stage determines everything downstream.

## Step 4: Framework Recommendation

Based on stage, recommend stage-appropriate frameworks:

### Discovery Stage
- **Framework:** Lean Startup / Customer Development (Steve Blank)
- **Metrics:** Qualitative feedback, interview count, hypothesis validation rate
- **Meeting cadence:** Weekly founder sync (informal). No formal structure needed.
- **Books:** The Mom Test (Fitzpatrick), The Lean Startup (Ries)
- **What NOT to do:** Don't implement EOS. Don't set OKRs. Don't write SOPs. Focus on learning, not operating.

### Validation Stage
- **Framework:** Lean Startup + light OKRs (quarterly, 1-2 objectives max)
- **Metrics:** MRR/revenue, activation rate, retention/churn, burn rate, months of runway
- **Meeting cadence:** Weekly team sync, monthly metrics review
- **Books:** Traction (Weinberg & Mares), $100M Offers (Hormozi)
- **What NOT to do:** Don't hire ahead of demand. Don't build elaborate org charts. Keep processes informal until they repeat 3+ times.

### Growth Stage
- **Framework:** EOS (Entrepreneurial Operating System) or Scaling Up as operating system. OKRs for goal-setting. Shape Up for product cadence.
- **Metrics:** MRR, CAC, LTV, LTV:CAC ratio (target 3:1+), churn, gross margin
- **Meeting cadence:** Daily standup, weekly L10, monthly metrics review, quarterly planning
- **Books:** Traction (Wickman — EOS), Scaling Up (Harnish), 10x Is Easier Than 2x (Sullivan & Hardy)
- **SOPs needed:** Hiring, onboarding, sales process, customer support, financial reporting

### Scale Stage
- **Framework:** EOS or Scaling Up + department-level OKRs cascading from company OKRs
- **Metrics:** ARR, net revenue retention, burn multiple, Rule of 40, employee NPS
- **Meeting cadence:** Full cadence stack (daily, weekly, monthly, quarterly, annual)
- **Books:** Good to Great (Collins), The Hard Thing About Hard Things (Horowitz), An Elegant Puzzle (Larson)
- **SOPs needed:** Everything that repeats. Process automation (Zapier/n8n). Onboarding playbooks. Vendor management.

## Step 5: Pattern Recall

Search for relevant patterns from other business projects or transferable code project patterns:

```bash
source "$HOME/.claude/scripts/cf-env.sh"
```

If `$CF` is found:
```bash
# Search for stage-specific patterns
cd "$HOME" && $CF memory search --query "stage:{STAGE} business venture" --limit 10 2>/dev/null || true

# Search for domain-specific patterns
cd "$HOME" && $CF memory search --query "domain:{DOMAIN}" --limit 10 2>/dev/null || true

# Search for transferable code patterns
cd "$HOME" && $CF memory search --query "transferable:true type:process" --limit 10 2>/dev/null || true
```

Fallback: grep `~/.claude/projects/*/memory/MEMORY.md` and `~/.claude/memory/portfolio.md` for relevant terms.

Summarize what past sessions learned that's relevant. If nothing found, say so.

## Step 6: Gap Report

Based on stage and existing structure, identify what's missing. Prioritize by impact:

**Critical gaps** — things that will cause problems if not addressed soon:
- Missing decision log at any stage
- No metrics tracking at Validation+
- No SOPs at Growth+
- No meeting cadence at Growth+

**Important gaps** — things that should exist but aren't urgent:
- Missing CLAUDE.md / project description
- No OKRs at Growth+
- No hiring plan when planning to hire

**Nice-to-have** — things that help but can wait:
- Financial dashboard
- Process automation
- Onboarding playbook (until actually hiring)

## Step 7: Output Summary

Present a structured diagnostic:

```markdown
## Venture Onboard: {Business Name}

**Stage:** {Discovery | Validation | Growth | Scale}
**Domain:** {SaaS | Marketplace | Service | E-commerce | Consulting | ...}
**Team size:** {N}

### Recommended Framework
{Stage-appropriate recommendation from Step 4}

### Existing Structure
{What was found in Step 2}

### Gaps (prioritized)
**Critical:**
- [ ] ...
**Important:**
- [ ] ...
**Nice-to-have:**
- [ ] ...

### Relevant Patterns
{From Step 5, or "No patterns found — this is a fresh start"}

### Suggested Next Steps
1. {Most impactful action}
2. {Second priority}
3. {Third priority}
- Run `/venture-align` to implement the recommended structure
```

## Rules

- **This is diagnostic — don't create files.** Use `/venture-align` for active structure creation.
- **Stage classification drives everything.** Get it right. If unsure, discuss with the user.
- **Don't recommend frameworks above the stage.** EOS for a pre-PMF startup is harmful. Lean Startup for a scaling company is insufficient.
- **Ask for clarification whenever you need it.** If the business description is vague, the stage is ambiguous, or you need more context about pain points — ask. Don't guess.
