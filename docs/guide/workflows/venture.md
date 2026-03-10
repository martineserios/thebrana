# Venture Management

Brana includes tools for managing business projects -- stage-appropriate frameworks, metrics, reviews, pipeline tracking, financial modeling, and proposals.

## Getting started with a business project

```
/brana:onboard              -- scan and diagnose (auto-detects venture clients)
/brana:align                -- implement stage-appropriate structure
```

Brana detects venture clients by looking for `docs/sops/`, `docs/okrs/`, `docs/metrics/`, or business keywords in CLAUDE.md. The `session-start.sh` hook auto-detects venture projects and nudges the daily-ops agent.

## Business stages

Every recommendation is stage-aware. Never over-systematize for the current stage.

| Stage | Revenue | Team | Focus |
|-------|---------|------|-------|
| **Discovery** | None | 1-3 | Problem validation |
| **Validation** | Some | 2-10 | Product-market fit |
| **Growth** | Repeatable | 10-50 | Scaling processes |
| **Scale** | Established | 50+ | Sustaining growth |

## Periodic reviews

```
/brana:review                -- weekly health check (default)
/brana:review monthly        -- monthly close + forward plan (P&L, actuals vs projections)
/brana:review check          -- ad-hoc AARRR funnel audit with traffic-light metrics
```

The metrics-collector agent gathers data from `docs/metrics/`, `docs/experiments/`, `docs/pipeline/`, and `docs/financial/` before the review skill analyzes it.

## Pipeline

```
/brana:pipeline              -- manage leads, deals, follow-ups
```

Stage-dependent templates: Discovery uses a simple contact list, Validation adds a basic funnel (Lead -> Trial -> Paid), Growth+ gets a full weighted pipeline. The pipeline-tracker agent identifies overdue follow-ups and stage-stuck deals.

## Financial modeling

```
/brana:financial-model       -- revenue projections, P&L, unit economics, cash flow
```

Auto-detects business model type (SaaS, Marketplace, Service, E-commerce, Hybrid). Always produces three scenarios (base/upside/downside). Optional Google Sheets export via `/brana:gsheets`.

## Business milestones

```
/brana:venture-phase launch     -- product launch (with pre-launch gates)
/brana:venture-phase fundraise  -- fundraise preparation
/brana:venture-phase expansion  -- market expansion
/brana:venture-phase hiring     -- hiring round
```

Each milestone type has stage-appropriate exit criteria and learning loops.

## Client proposals

```
/brana:proposal "integration project for Acme"   -- generate a proposal
/brana:export-pdf propuesta-integracion-acme.md   -- convert to PDF
```

Interview-driven proposal generation in Spanish. Rate defaults to $65/hr.

## Key principle

Don't over-systematize. EOS for a pre-PMF startup is harmful. Wait until a process repeats 3+ times before writing an SOP.
