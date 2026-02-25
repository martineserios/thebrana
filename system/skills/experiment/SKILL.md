---
name: experiment
description: "Growth experiment loop — hypothesis, test design, success criteria, results, learning. Structured experimentation with auto-incrementing records. Use when testing a growth hypothesis or after /growth-check identifies a bottleneck."
group: venture
allowed-tools:
  - Read
  - Write
  - Glob
  - Grep
  - Bash
---

# Experiment — Growth Experiment Loop

Structured growth experimentation: hypothesis, test design, success criteria, results, learning. Every growth initiative follows this loop. Produces auto-incrementing experiment records in `docs/experiments/` and stores learnings in ReasoningBank for cross-project recall.

## When to use

- Testing a growth hypothesis (new channel, pricing change, feature bet, messaging variant)
- After `/growth-check` identifies a bottleneck — design an experiment to address it
- Trying a new channel, feature, or pricing model and want structured tracking
- Returning to measure results of a running experiment

**Invocation:**
- `/experiment` — start a new experiment (interview mode)
- `/experiment measure EXP-NNN` — return to measure results of a running experiment

---

## Step 1: Context

### 1a: Locate project root

Run `git rev-parse --show-toplevel` in the current directory. Fall back to `$PWD` if not a git repo.

### 1b: Read last /growth-check

Search for the most recent growth-check output:

```bash
# Check docs/metrics/ for recent health reports
ls docs/metrics/health-*.md 2>/dev/null | sort | tail -1
```

Also search ReasoningBank:

```bash
source "$HOME/.claude/scripts/cf-env.sh"
```

If `$CF` is found:
```bash
cd "$HOME" && $CF memory search --query "growth-check:{PROJECT}" --limit 3 2>/dev/null || true
```

Extract: current bottleneck, red/yellow metrics, stage. If no growth-check exists, note it and proceed — the user may have their own data.

### 1c: Detect stage

Check `.claude/CLAUDE.md`, `docs/metrics/`, `docs/okrs/` for stage indicators (Discovery / Validation / Growth / Scale). If unclear, ask the user.

### 1d: Route — new or measure?

If `$ARGUMENTS` contains `measure` and an `EXP-NNN` identifier, skip to **Step 8: Measure Results**. Otherwise, proceed with new experiment creation.

### 1e: Explore the problem space

Before jumping to a single hypothesis, broaden the search:

1. **Reframe the bottleneck** (from Steps 1b-1c) as 2-3 "How might we..." questions:
   - "How might we [desired outcome] for [audience] given [constraint]?"

2. **Generate 3+ hypothesis candidates** from the HMW questions, each in format:
   - "We believe that [action] will [outcome] for [audience]."

3. **Quick-rank** each candidate:

   | # | Hypothesis | Impact (H/M/L) | Testability (easy/hard) |
   |---|-----------|:--------------:|:----------------------:|
   | 1 | ... | | |
   | 2 | ... | | |
   | 3 | ... | | |

4. **Pick the most promising** for full development in Step 2.

**Skip clause:** If the user arrives with a specific hypothesis already formed, present it alongside 1-2 alternatives and let them confirm or switch. Don't force exploration when conviction exists.

---

## Step 2: Hypothesis

Interview the user (skip what is already clear from `$ARGUMENTS` or conversation context):

1. **What do you believe?** State the hypothesis in one sentence. Format: "We believe that [action] will [outcome] for [audience]."
2. **What evidence suggests this?** Data, customer feedback, competitive observation, gut feeling (be honest about source quality).
3. **What would disprove it?** The kill criteria — if we see X, the hypothesis is wrong.

---

## Step 3: Test Design

Define the test with the user:

| Element | Question |
|---------|----------|
| **Action** | What exactly will you do? (Be specific — "run Facebook ads" is vague; "run 3 Facebook ad variants targeting {audience} with {budget}" is testable.) |
| **Audience** | Who is this targeting? Segment, persona, geography. |
| **Duration** | How long will the test run? (Minimum viable: enough time for statistical significance.) |
| **Channel** | Where does this happen? (Paid ads, email, product, partnerships, content, outbound.) |
| **Budget** | What resources are required? (Money, time, tools.) |
| **Control** | What's the baseline or control group? (Current state, A/B split, before/after.) |

---

## Step 4: Success Criteria + ICE Score

### Success Criteria

Define measurable criteria BEFORE running. No post-hoc rationalization.

| Criterion | Metric | Target | Timeframe |
|-----------|--------|--------|-----------|
| Primary | {the one metric that matters} | {specific number} | {duration} |
| Secondary | {supporting metric} | {specific number} | {duration} |
| Kill | {what would kill the experiment} | {threshold} | {when to check} |

### ICE Score

Score the experiment for prioritization (especially when multiple experiments compete):

| Dimension | Score (1-10) | Rationale |
|-----------|:---:|-----------|
| **Impact** — if this works, how big is the effect? | {N} | {why} |
| **Confidence** — how sure are we it will work? | {N} | {why} |
| **Ease** — how easy is it to run? | {N} | {why} |
| **ICE Total** | {I x C x E} | |

ICE score helps rank experiments. Run the highest-ICE experiment first. If the user has multiple hypotheses, score all of them and recommend order.

---

## Step 5: Auto-increment experiment number

Ensure `docs/experiments/` exists. If not, ask the user: "This project doesn't have `docs/experiments/` yet. Create it?" If yes, `mkdir -p docs/experiments/`. If no, abort.

Scan for the highest existing experiment number:

```bash
highest=$(ls docs/experiments/EXP-*.md 2>/dev/null | sed 's/.*EXP-\([0-9]*\).*/\1/' | sort -n | tail -1)
next=$(printf "%03d" $(( ${highest:-0} + 1 )))
echo "Next experiment number: EXP-$next"
```

---

## Step 6: Create Experiment Record

Slugify the hypothesis into a short slug (lowercase, hyphens, max 50 chars). Write to `docs/experiments/EXP-NNN-slug.md`:

```markdown
# EXP-NNN: {Short Title}

**Status:** Running
**Created:** {today}
**Owner:** {user or role}
**Stage:** {Discovery | Validation | Growth | Scale}
**ICE Score:** {total} (I:{n} C:{n} E:{n})

## Hypothesis

We believe that {action} will {outcome} for {audience}.

**Evidence:** {what suggests this}
**Kill criteria:** {what would disprove it}

## Test Design

| Element | Detail |
|---------|--------|
| Action | {specific action} |
| Audience | {target segment} |
| Duration | {timeframe} |
| Channel | {where} |
| Budget | {resources required} |
| Control | {baseline} |

## Success Criteria

| Criterion | Metric | Target | Timeframe |
|-----------|--------|--------|-----------|
| Primary | {metric} | {target} | {duration} |
| Secondary | {metric} | {target} | {duration} |
| Kill | {metric} | {threshold} | {when} |

## Results

*Pending — run `/experiment measure EXP-NNN` when the test period ends.*

| Criterion | Target | Actual | Met? |
|-----------|--------|--------|------|
| Primary | {target} | — | — |
| Secondary | {target} | — | — |
| Kill | {threshold} | — | — |

## Decision

*Pending measurement.*

- [ ] Scale — worked, double down
- [ ] Kill — failed, document why
- [ ] Iterate — promising, modify and retest

## Learnings

*To be filled after measurement.*

---

*Bottleneck addressed: {from /growth-check, or "N/A"}*
*Related experiments: {EXP-NNN if iterating, or "none"}*
```

---

## Step 7: Update Index

If `docs/experiments/README.md` exists, add the new experiment to the table. If not, create:

```markdown
# Experiments

| # | Title | Status | ICE | Channel | Created |
|---|-------|--------|:---:|---------|---------|
| EXP-NNN | {title} | Running | {score} | {channel} | {today} |
```

### Step 7b: GitHub Issue (Optional)

If `gh` CLI is available, create a tracking issue for the new experiment.

```bash
if command -v gh &>/dev/null && gh repo view &>/dev/null 2>&1; then
    # Create labels (idempotent)
    for label in "source:experiment" "type:experiment" "status:running"; do
        gh label create "$label" --force 2>/dev/null || true
    done

    # Create issue for the experiment
    gh issue create \
      --title "EXP-{NNN}: {short title}" \
      --label "source:experiment,type:experiment,status:running" \
      --body "**Hypothesis:** {hypothesis}
**ICE Score:** {total} (I:{n} C:{n} E:{n})
**Channel:** {channel}
**Duration:** {duration}
**Success criteria:** {primary criterion}
**Kill criteria:** {kill criterion}

Experiment record: docs/experiments/EXP-{NNN}-{slug}.md" \
      2>/dev/null || true
fi
```

Skip silently if `gh` is not installed or the project has no GitHub remote.

---

## Step 8: Measure Results (returning to a running experiment)

When the user returns to measure (via `/experiment measure EXP-NNN` or by asking to check an experiment):

### 8a: Read the experiment record

Read `docs/experiments/EXP-NNN-*.md`. Extract the success criteria and test design.

### 8b: Collect actuals

Ask the user for actual results for each criterion. If metrics are in `docs/metrics/` or available via data sources, read them.

### 8c: Compare to criteria

Fill in the Results table:

| Criterion | Target | Actual | Met? |
|-----------|--------|--------|------|
| Primary | {target} | {actual} | Yes/No |
| Secondary | {target} | {actual} | Yes/No |
| Kill | {threshold} | {actual} | Triggered/Clear |

---

## Step 9: Decision

Based on results, recommend one of three outcomes and discuss with the user:

| Outcome | When | Action |
|---------|------|--------|
| **Scale** | Primary criterion met, kill criteria clear | Double down — increase budget, expand audience, make permanent |
| **Kill** | Kill criteria triggered, or primary far from target | Stop the experiment. Document why it failed. Extract the learning. |
| **Iterate** | Promising but not conclusive — close to target, or secondary met but primary missed | Modify the hypothesis or test design. Create a follow-up experiment (EXP-NNN+1) referencing this one. |

Update the experiment record: check the appropriate decision box, change status to `Completed` (scale/kill) or `Iterating` (iterate), fill in the Learnings section.

---

## Step 10: Store Learning

### 10a: ReasoningBank

```bash
source "$HOME/.claude/scripts/cf-env.sh"
```

If `$CF` is found:
```bash
cd "$HOME" && $CF memory store \
  -k "experiment:{PROJECT}:EXP-{NNN}" \
  -v '{"type": "experiment", "title": "...", "hypothesis": "...", "channel": "...", "ice_score": N, "status": "...", "outcome": "scale|kill|iterate", "primary_met": true|false, "key_learning": "...", "confidence": 0.5, "transferable": true}' \
  --namespace business \
  --tags "project:{PROJECT},type:experiment,channel:{CHANNEL},outcome:{OUTCOME},stage:{STAGE}"
```

Set `transferable: true` — experiment learnings about channels and tactics often apply across projects.

### 10b: Fallback (claude-flow unavailable)

Append to `~/.claude/projects/{project-hash}/memory/MEMORY.md`:
```
## Experiment: EXP-NNN {title}
- Hypothesis: {one line}
- Channel: {channel}
- Outcome: {scale/kill/iterate}
- Key learning: {one line}
- Date: {today}
```

### 10c: Update index

Update the experiment's row in `docs/experiments/README.md` with final status and outcome.

### 10d: Close GitHub Issue (Optional)

If `gh` CLI is available and an issue exists for this experiment, close it with the outcome.

```bash
if command -v gh &>/dev/null && gh repo view &>/dev/null 2>&1; then
    # Find the issue by title prefix
    ISSUE_NUM=$(gh issue list --search "EXP-{NNN}" --json number --jq '.[0].number' 2>/dev/null)
    if [ -n "$ISSUE_NUM" ]; then
        gh issue close "$ISSUE_NUM" \
          --comment "**Outcome:** {Scale/Kill/Iterate}
**Primary criterion met:** {Yes/No}
**Key learning:** {one-line learning}

Full results: docs/experiments/EXP-{NNN}-{slug}.md" \
          2>/dev/null || true

        # Update label to reflect outcome
        gh issue edit "$ISSUE_NUM" \
          --remove-label "status:running" \
          --add-label "status:{outcome}" \
          2>/dev/null || true
    fi
fi
```

---

## Rules

- **Define success criteria BEFORE running.** No post-hoc rationalization. If criteria weren't set upfront, set them now before looking at results.
- **Never skip the hypothesis.** "Let's try Facebook ads" is not an experiment. "We believe Facebook ads targeting {segment} will produce {N} signups at <${X} CAC" is.
- **ICE score is for prioritization, not gatekeeping.** Low-ICE experiments are fine if nothing better is available. The score helps choose between competing ideas.
- **Kill criteria are mandatory.** Every experiment must define what failure looks like. Without kill criteria, failed experiments drag on indefinitely.
- **One experiment tests one variable.** Don't change the channel AND the messaging AND the audience simultaneously. Isolate the variable.
- **Never overwrite a completed experiment.** If iterating, create a new EXP-NNN+1 that references the original.
- **Experiments decay.** A learning from 6 months ago in a different market may not apply. Note the context.
- **Store results in ReasoningBank when available, fall back to auto memory when not.**
- **Ask for clarification whenever you need it.** If the hypothesis is vague, success criteria are unmeasurable, or the test design has confounds — ask.
