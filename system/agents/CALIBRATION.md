---
name: challenger-calibration
description: Severity scoring guide with few-shot examples and hard thresholds for the challenger agent.
type: reference
---

# Challenger Calibration

Severity scoring guide with few-shot examples and hard thresholds. Referenced by `challenger.md` and the `/brana:challenge` skill.

## Scoring Rubric (1-5 Scale)

| Score | Severity | Definition | Verdict impact |
|-------|----------|-----------|----------------|
| **5** | Critical | Plan blocks success, causes data loss, or security breach | RECONSIDER |
| **4** | High | Known unmitigated risk affecting real workflows | RECONSIDER |
| **3** | Medium | Solid plan with minor gaps or workarounds needed | PROCEED WITH CHANGES |
| **2** | Low | Plan works, could be simpler or more robust | PROCEED WITH CHANGES |
| **1** | Clean | No findings; plan is solid as stated | PROCEED |

**Verdict rules:**
- ANY finding >= 4 --> verdict is **RECONSIDER**
- All findings <= 2 with clear mitigations --> **PROCEED WITH CHANGES**
- All findings <= 1 --> **PROCEED**

## Hard Thresholds

### CRITICAL (always score 5)

These conditions **always** trigger critical severity regardless of context:

1. **Service unavailability** -- Plan removes a critical feature with zero fallback
2. **Data loss risk** -- Migration plan has no backup strategy or rollback mechanism
3. **Workflow breakage** -- Change affects >50% of user operations without mitigation
4. **Security/secrets leak** -- Plan introduces unencrypted storage of credentials or auth
5. **Untested critical path** -- Core assumption (performance, availability) is stated but unvalidated
6. **Dependency conflict** -- Plan assumes a library version that conflicts with documented constraints

### WARNING (always score 4)

These conditions **always** trigger warning severity:

1. **Mitigable but unaddressed** -- Known workaround exists but isn't documented in the plan
2. **Edge case impact** -- Change affects <50% of workflows or specific user profiles
3. **Performance risk** -- Algorithm with known worst-case complexity on unbounded input
4. **Assumption unvalidated** -- Plausible but undocumented behavior from tool/library
5. **Partial coverage** -- Logic only applies to some platforms or environments

### OBSERVATION (score 1-3)

- Risk is too low to mitigate before shipping
- Mitigation can be added post-hoc
- Impact is theoretical or depends on rare conditions

## Few-Shot Examples

### Example 1: CRITICAL Finding

**Scenario:** Planning a migration of task persistence from tasks.json to SQLite without a backwards-compatibility layer.

**Flavor:** Pre-mortem

```
### Critical Findings
1. **No read-only fallback for tasks.json** -- All active CLI commands (brana backlog query,
   brana backlog next, brana backlog focus) assume SQLite availability. If SQL connection fails
   mid-batch, CLI becomes fully unavailable. The plan includes zero offline mode. This would
   cause production outages during migration.
   Mitigation: Add a git-based fallback reader that serves cached JSON when SQL is unavailable.

Confidence: HIGH
```

**Why CRITICAL:** Direct service unavailability (hard blocker). Zero mitigation in plan. Affects every user of `brana backlog` commands.

---

### Example 2: WARNING Finding

**Scenario:** Adding a new PreToolUse hook to validate commit messages without implementing a bypass for automated commits.

**Flavor:** Assumption Buster

```
### Warnings
1. **Automated commits will fail validation** -- The plan assumes all commits are user-initiated.
   However, bootstrap.sh and reconcile runs generate auto-commits. Hook will block these unless a
   bypass flag is added. This is manageable but requires a small scope expansion.
   Mitigation: Add `[skip-validate]` in commit body or `--allow-empty-message` bypass for
   tool-generated commits.

Confidence: MEDIUM
```

**Why WARNING (not critical):** Doesn't block success (has a clear workaround). Affects edge case (auto-commits), not primary workflow. Easy to mitigate (one flag addition).

---

### Example 3: OBSERVATION

**Scenario:** Adding a new agent that fetches GitHub issues without rate-limit caching.

**Flavor:** Simplicity Challenge

```
### Observations
1. **GitHub API rate limits will block concurrent queries** -- The agent spawns 3 subagents in
   parallel, each making ~5 gh api calls. GitHub's default is 5000 req/hour. On a heavy research
   task, this could consume 2-3% of hourly quota. Not a blocker because research tasks are
   infrequent, but worth noting for high-volume clients.

Confidence: MEDIUM
```

**Why OBSERVATION:** No hard block (quota recovers after 1 hour). Rare scenario (only on large research tasks). Still worth flagging for future caching work.

## Calibration Maintenance

- After each challenger review, check if findings match the rubric thresholds
- If the challenger consistently misclassifies severity, add a corrective few-shot example
- Monthly: review logged findings against hard thresholds -- refine if patterns emerge
- Source: Anthropic Bloom approach (calibration at extremes matters most), Anthropic harness design (evaluators need few-shot examples + hard thresholds)
