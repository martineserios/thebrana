# Adversarial Review

`/brana:challenge` stress-tests a plan, architecture decision, or approach before you commit to it. Two AI models review independently — Opus reasons about problems, Gemini retrieves documented constraints — then findings are merged and tiered by confidence.

## Quick start

```
/brana:challenge                           -- challenges the most significant unreviewed decision in context
/brana:challenge "migrate auth to JWT"     -- challenge a specific plan
/brana:challenge t-88                      -- challenge the approach for a task
```

With no arguments, brana scans the conversation for the most significant unchalllenged decision or plan and challenges that.

## When to use

**Always use before:**
- Committing to an architecture decision (before writing the ADR)
- Starting effort L or XL work
- Any plan where being wrong is expensive or hard to reverse

**Also use when:**
- A fix has failed 3+ times (mandatory — see `/brana:fix` 3-strike rule)
- You're about to violate a recent ADR
- A stakeholder-visible decision needs a second opinion

## Challenge flavors

Brana picks the flavor automatically based on what you're challenging:

| Flavor | Best for | The question |
|--------|----------|-------------|
| **Pre-mortem** | Architecture, design | "It's 3 months from now and this failed in production. What went wrong?" |
| **Simplicity** | Implementation plans | "Can you achieve the same outcome with half the complexity?" |
| **Assumption buster** | Migrations, estimates | "What are you assuming that might not be true?" |
| **Adversarial review** | Code, security | Concrete problems, security issues, performance concerns |

## Scope questions

Before launching, brana asks 2-4 questions to calibrate the review:
- **Deadline pressure** — changes severity weighting (tight deadline → long-term concerns become LOW)
- **Cost of being wrong** — "cheap (refactor)" vs "catastrophic (prod incident)"
- **What's been tried** — "first attempt" vs "multiple stalled attempts"
- **Constraints already locked** — prevents challenging decisions that can't be changed

Answer briefly. The questions exist to focus the review, not to delay it.

## Reading the findings

Findings are tiered by confidence:

| Tier | Source | What it means |
|------|--------|--------------|
| **CRITICAL** | Either model | Would block success — address before proceeding |
| **WARNING** | Either model | Risk, but manageable — have a mitigation plan |
| **OBSERVATION** | Either model | Minor, for consideration |
| **Agreement** | Both models independently | Highest confidence — two architectures, same concern |
| `[NLM-UNVERIFIED]` | Gemini only | Verify against source docs before trusting |

A finding that Opus and Gemini both raise independently is the strongest signal the system can produce. Treat it as a blocker.

## After the challenge

The challenge report is a proposal, not a decision. You decide what to do:
- **Address the concern** — change the plan, add a mitigation
- **Accept the risk** — note it in the task context or ADR
- **Disagree with the finding** — that's valid; note why

CRITICAL and WARNING findings are automatically logged to the decision log. You don't need to capture them manually.

## Challenge and ADRs

If the challenge is about an architecture decision that should become an ADR, run the challenge **before** writing the ADR. The ADR's "Rejected alternatives" and "Risks" sections should reflect the challenge findings.

If a challenge finding contradicts a recent ADR, don't act on the finding without re-running the challenge with that constraint explicitly stated.

## Key rules

- **Empty `/brana:challenge` is smart.** It infers what to challenge from the conversation — you don't need to describe the plan again.
- **Gemini retrieves, Claude reasons.** Don't read Gemini findings as adversarial review — they're documented constraints. Claude's compliance check (combining both) is where the reasoning happens.
- **Agent results are inputs, not decisions.** The challenge report surfaces concerns; you decide what to do with them.
- **3 failed fixes = mandatory challenge.** Not a suggestion — stop, challenge, then resume.
