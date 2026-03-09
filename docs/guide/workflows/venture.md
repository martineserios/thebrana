# Venture Management

Brana includes tools for managing business projects — stage-appropriate frameworks, metrics, reviews, and pipeline tracking.

## Getting started with a business project

```
/brana:onboard              — scan and diagnose (auto-detects venture clients)
/brana:align                — implement stage-appropriate structure
```

Brana detects venture clients by looking for `docs/sops/`, `docs/okrs/`, `docs/metrics/`, or business keywords in CLAUDE.md.

## Business stages

Every recommendation is stage-aware:

| Stage | Revenue | Team | Focus |
|-------|---------|------|-------|
| **Discovery** | None | 1-3 | Problem validation |
| **Validation** | Some | 2-10 | Product-market fit |
| **Growth** | Repeatable | 10-50 | Scaling processes |
| **Scale** | Established | 50+ | Sustaining growth |

## Periodic reviews

```
/brana:review                — weekly health check (default)
/brana:review monthly        — monthly close + forward plan
/brana:review check          — ad-hoc AARRR funnel audit
```

## Pipeline

```
/brana:pipeline              — manage leads, deals, follow-ups
```

## Business milestones

```
/brana:venture-phase launch     — product launch
/brana:venture-phase fundraise  — fundraise preparation
/brana:venture-phase expansion  — market expansion
```

## Key principle

Don't over-systematize. EOS for a pre-PMF startup is harmful. Wait until a process repeats 3+ times before writing an SOP.
