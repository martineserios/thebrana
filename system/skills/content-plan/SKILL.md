---
name: content-plan
description: "Marketing content planning — themes, calendar, distribution checklist, performance tracking. Quarterly content strategy aligned to growth goals. Use when planning quarterly content strategy or launching a new content channel."
group: venture
allowed-tools:
  - Read
  - Write
  - Glob
  - Grep
  - Bash
---

# Content Plan — Quarterly Content Strategy

Build a quarterly content plan: themes, calendar, distribution checklist, and performance tracking. Aligns content output to the current growth bottleneck and stage.

## When to use

- Quarterly content planning cycle
- Launching a new content channel
- When `/growth-check` shows acquisition as the bottleneck
- After a pivot that changes messaging or audience

---

## Step 1: Context

Gather inputs from existing project data before planning.

### 1a: Read growth data

```bash
# Check for /growth-check snapshots
ls docs/metrics/health-*.md 2>/dev/null | tail -3
```

Read the most recent `/growth-check` report. Extract:
- **Current stage** (Discovery / Validation / Growth / Scale)
- **AARRR bottleneck** (especially Acquisition)
- **Key metrics** — traffic, signups, conversion rates

### 1b: Read experiment results

```bash
# Check for content experiments
ls docs/experiments/ 2>/dev/null
```

If content experiments exist, read them. Extract:
- Which content types performed best
- Which channels drove results
- Conversion data per content piece

### 1c: Detect stage

If no `/growth-check` exists, check `.claude/CLAUDE.md` for stage indicators. If unclear, ask the user.

---

## Step 2: Content Themes

Interview the user. Skip questions already answered by context.

1. **Target audience** — Who are you creating content for? (Be specific: role, pain points, where they hang out)
2. **Key messages** — What 1-3 things should every piece of content reinforce?
3. **Content pillars** — 3-5 recurring themes that map to your positioning. Examples:
   - Product education (how-to, tutorials)
   - Thought leadership (opinions, trends)
   - Social proof (case studies, testimonials)
   - Community (behind-the-scenes, culture)
   - SEO plays (search-driven educational content)
4. **Competitive positioning** — What angle differentiates your content from competitors?

Document the themes. These become the strategic foundation for the calendar.

---

## Step 3: Channel Selection

Recommend channels appropriate to the current stage. Present to the user for confirmation.

### Discovery

| Channel | Effort | Why |
|---------|--------|-----|
| Founder's blog / personal site | Low | Establishes voice, tests messaging |
| Social media (1-2 platforms) | Low | Where your audience already is |
| Community engagement | Low | Comments, forums, relevant Slack/Discord groups |

### Validation

All of Discovery, plus:

| Channel | Effort | Why |
|---------|--------|-----|
| Email newsletter | Medium | Owned audience, direct relationship |
| Guest posts / collaborations | Medium | Borrow someone else's audience |
| Partnership content | Medium | Co-marketing with complementary products |

### Growth

All of Validation, plus:

| Channel | Effort | Why |
|---------|--------|-----|
| Paid content promotion | Medium-High | Amplify what's already working organically |
| SEO strategy | High | Compounding long-term traffic |
| Video content | High | Higher engagement, broader reach |

### Scale

All of Growth, plus:

| Channel | Effort | Why |
|---------|--------|-----|
| PR / media outreach | High | Brand authority at scale |
| Analyst relations | High | Enterprise credibility |
| Thought leadership program | High | Conference talks, whitepapers, research |

Ask the user which channels they want to activate this quarter. Recommend no more than 2-3 for Discovery/Validation, 3-5 for Growth/Scale.

---

## Step 4: Calendar

Build a quarterly calendar with weekly cadence. Each week maps to a content pillar.

### Template

```markdown
## Q{N} {YYYY} Content Calendar

**Pillars:** {pillar 1}, {pillar 2}, {pillar 3}
**Channels:** {channel 1}, {channel 2}
**Cadence:** {N pieces/week}

| Week | Dates | Pillar | Topic | Format | Channel | Owner | Status |
|------|-------|--------|-------|--------|---------|-------|--------|
| 1 | {dates} | {pillar} | {topic} | {blog/video/newsletter/social} | {where} | {who} | Planned |
| 2 | {dates} | {pillar} | {topic} | {format} | {where} | {who} | Planned |
| ... | | | | | | | |
| 13 | {dates} | {pillar} | {topic} | {format} | {where} | {who} | Planned |
```

### Guidelines

- **Rotate pillars** — don't stack 4 weeks of the same theme
- **Front-load high-value pieces** — best content in weeks 1-4 while motivation is fresh
- **Leave buffer weeks** — mark 1-2 weeks as "flex" for timely/reactive content
- **Match format to channel** — long-form for blog/SEO, short-form for social, narrative for newsletter

Ask the user to fill in specific topics or suggest topics based on themes and audience.

---

## Step 5: Distribution Checklist

Create a per-content distribution checklist. Every piece of content should follow the same distribution steps.

```markdown
## Distribution Checklist (per content piece)

### Pre-publish
- [ ] Headline tested / reviewed
- [ ] CTA defined (what should the reader do next?)
- [ ] SEO metadata set (if applicable)
- [ ] Visual assets ready (images, thumbnails)

### Publish day
- [ ] Published on primary channel
- [ ] Shared on social media (platform 1)
- [ ] Shared on social media (platform 2)
- [ ] Sent to email list (if newsletter-worthy)
- [ ] Posted in relevant communities (with value-add, not spam)

### Post-publish (within 48h)
- [ ] Respond to comments / engagement
- [ ] Share with partners / collaborators for amplification
- [ ] Cross-post or repurpose (e.g., blog → thread → newsletter snippet)

### Post-publish (within 7 days)
- [ ] Check initial metrics (views, engagement, clicks)
- [ ] Note what worked / didn't in experiment log
```

Adapt the checklist to the channels selected in Step 3. Remove irrelevant items, add channel-specific ones.

---

## Step 6: Performance Tracking

Define metrics for each content piece and aggregate quarterly metrics.

### Per-piece metrics

| Metric | How to Measure | Target |
|--------|---------------|--------|
| Views / impressions | Analytics platform | {set based on channel} |
| Engagement (likes, comments, shares) | Platform native | {set based on baseline} |
| Click-through rate | UTM links / analytics | >2% |
| Conversions (signup, trial, purchase) | Attribution tracking | {set based on funnel} |
| Time on page | Analytics | >2 min for long-form |

### Quarterly aggregate metrics

| Metric | Q target | How to Measure |
|--------|----------|---------------|
| Total content pieces published | {N} | Count from calendar |
| Total reach / impressions | {N} | Sum across channels |
| Email list growth | {N} new subscribers | Newsletter platform |
| Content-attributed signups | {N} | UTM / attribution |
| Top-performing piece | — | Highest engagement or conversion |
| Cost per content piece | ${N} | Total spend / pieces published |

Ask the user what metrics they can actually track. Don't require tooling they don't have. Start with what's measurable and add tracking as infrastructure matures.

---

## Step 7: Output

Write the plan to `docs/content/plan-{YYYY}-Q{N}.md`:

```bash
mkdir -p docs/content
```

### File structure

```markdown
# Content Plan: Q{N} {YYYY}

**Created:** {today}
**Stage:** {Discovery | Validation | Growth | Scale}
**Growth bottleneck:** {from /growth-check, or "N/A"}

## Audience
{target audience from Step 2}

## Key Messages
{1-3 messages from Step 2}

## Content Pillars
1. {pillar} — {one-line description}
2. {pillar} — {one-line description}
3. {pillar} — {one-line description}

## Channels
{selected channels from Step 3, with rationale}

## Calendar
{full calendar table from Step 4}

## Distribution Checklist
{checklist from Step 5}

## Performance Targets
{metrics tables from Step 6}

## Review
- **Mid-quarter check:** Week 7 — review metrics, adjust calendar if needed
- **End-of-quarter review:** Feed results into next /content-plan and /growth-check
```

---

## Optional: Google Workspace MCP

If the Google Workspace MCP server is configured, offer to create calendar entries:

```
For each calendar row, create a Google Calendar event:
- Title: "[Content] {topic}"
- Date: {publish date}
- Description: Pillar: {pillar} | Format: {format} | Channel: {channel}
```

Check for MCP availability:
```bash
# Look for Google Workspace MCP in project config
grep -l "google" .mcp.json 2>/dev/null || grep -l "google" ~/.claude/settings.json 2>/dev/null
```

If not configured, skip — the markdown calendar is the primary artifact.

---

## Rules

- **Don't plan more than the team can execute.** A solo founder publishing 1 quality piece per week beats 5 rushed ones. Ask about capacity before building the calendar.
- **Themes before tactics.** Get the pillars and audience right in Step 2 before jumping to the calendar. Bad strategy executed consistently is still bad strategy.
- **Distribution > creation.** Most content fails from under-distribution, not under-creation. The checklist in Step 5 is as important as the calendar in Step 4.
- **Measure what you can.** Don't require Mixpanel if they only have Google Analytics. Start with available tools and recommend upgrades as the content program matures.
- **Feed the loop.** Content performance data should flow into `/experiment` (as content experiments) and `/growth-check` (as acquisition metrics). Isolated content plans decay fast.
- **Ask for clarification whenever you need it.** If the audience is vague, topics are unclear, or you need the user to make a channel decision — ask.
