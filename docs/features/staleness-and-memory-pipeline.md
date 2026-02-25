# Feature: Staleness Report + Output-to-Memory Pipeline

**Date:** 2026-02-19
**Status:** shipped
**Backlog:** #45, #51

## Goal

Create a staleness detection script for spec docs (#45) and extend the scheduler runner to capture job output into claude-flow memory (#51). Together, these make the weekly staleness check visible in `/morning` and session-start.

## Audience

The user — sees overnight staleness reports surfaced via claude-flow memory search.

## Constraints

- #45 lives in enter repo (`scripts/staleness-report.sh`) — bash + git, no Python
- #51 lives in thebrana repo (runner enhancement) — bash + claude-flow CLI
- Scheduler job config already exists (disabled, type: command, `./scripts/staleness-report.sh`)
- claude-flow memory uses `memory store -k key -v value --namespace ns --tags "tags"`
- Output must work headless (no interactive prompts)

## Scope (v1)

### #45 — staleness-report.sh
- Layer-aware age check: roadmap=30d, reflection=90d, dimension=180d (from doc 25)
- Git log last-modified per doc (zero dependencies beyond git)
- Dependency freshness: grep `doc NN` references, compare git dates
- Two-tier output: WARN (approaching threshold) and STALE (past threshold)
- Summary line for log capture: `N docs checked, X stale, Y warn`

### #51 — output-to-memory pipeline
- Post-run hook in runner: on success, extract summary from log
- Store in claude-flow memory: `namespace: scheduler-runs`, key: `sched:{job}:{date}`
- Tags: `job:{name}`, `status:{SUCCESS|FAILED}`, `type:scheduler-run`
- Graceful degradation: if claude-flow unavailable, skip silently

## Deferred

- Frontmatter `last_review_date` fields (git log is sufficient for now)
- CI/CD integration (scheduled job is enough)
- Version-pinned package tracking (separate concern)
- Rich structured output (JSON report file)

## Research findings

- No existing tool combines layer-aware thresholds + dependency freshness
- dbt warn_after/error_after pattern is transferable for two-tier alerting
- Giant Swarm frontmatter-validator is closest prior art
- `claude -p --output-format json | jq '.result'` for structured output capture
- claude-flow CLI: `memory store --upsert -k key -v value --namespace ns --tags "tags"`

## Design

### staleness-report.sh flow
```
for each *.md in enter/:
    days_since = git log last-modified date
    layer = classify(doc_number)  # roadmap/reflection/dimension
    threshold = layer_threshold[layer]
    if days_since > threshold: STALE
    elif days_since > threshold * 0.8: WARN
    else: OK

for each doc with references to other docs:
    ref_date = git log last-modified of referenced doc
    doc_date = git log last-modified of this doc
    if ref_date > doc_date: DEP_STALE (dependency updated more recently)

print summary
```

### output-to-memory pipeline flow
```
# In runner, after job completes successfully:
if claude-flow available and captureOutput enabled:
    summary = tail -20 logfile | head summary line
    claude-flow memory store \
      -k "sched:{job}:{date}" \
      -v "{status, summary, duration}" \
      --namespace scheduler-runs \
      --tags "job:{name},status:SUCCESS"
```
