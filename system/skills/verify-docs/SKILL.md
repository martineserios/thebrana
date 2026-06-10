---
name: verify-docs
description: "Periodic doc verification — runs validate.sh structural check, samples assumption rows for semantic review. Run quarterly to collect drift evidence."
effort: low
keywords: [verify, docs, assumptions, drift, semantic, freshness, quarterly]
task_strategies: [investigation]
stream_affinity: [docs, tech-debt]
argument-hint: "[--sample N] [--json] [--seed N]"
group: brana
model: haiku
allowed-tools:
  - Bash
  - Read
  - AskUserQuestion
status: stable
growth_stage: prototype
---
# Verify-Docs — Periodic Doc Verification

Run a structural assumption-freshness check + surface a random sample of assumption rows for manual semantic review. **No LLM.** This is the trigger-evidence collector for t-441 (LLM-assisted drift detection).

## When to use

- **Quarterly** — primary cadence. Run both `--scope docs` and `--scope claudemd`.
- **Before a major architecture change** — sanity-check assumption claims in the docs you're about to revise.
- **After a tier backfill** — confirm structural staleness clears with the new tiers.
- **After a CLAUDE.md edit** — run `--scope claudemd` to confirm no volatile content was introduced.
- **On demand** — when you suspect a doc says X but code does Y.

## Process

### 1a. Run the structural + sampling check (scope: docs)

```
Bash: bash system/scripts/verify-docs.sh --sample 5
```

If you want reproducibility, pass `--seed N`. For automation/scripting:

```
Bash: bash system/scripts/verify-docs.sh --json --sample 5 > /tmp/verify-docs-$(date -I).json
```

### 1b. Run the CLAUDE.md portfolio scan (scope: claudemd)

```
Bash: bash system/scripts/verify-docs.sh --scope claudemd
```

Detects three violation types across all portfolio `CLAUDE.md` files (excluding worktrees):
- **DATED_STATUS** — status lines with embedded 202X-MM-DD dates
- **PRICING** — service cost lines (`ARS N/mes`, `$N/mes`)
- **TRACKER_TABLE** — work-tracker tables (Status + Priority/Effort/Sprint/Assigned)

For JSON output: `bash system/scripts/verify-docs.sh --scope claudemd --json`

### 2. Read the sample

Each sample entry shows:
- `doc` — the file
- `tier` — effective tier (architecture / methodology / tech) and source (per-row, doc, or default)
- `verified` — the row's last_verified date
- `claim` — the assumption text (truncated to 100 chars; read the full row in the source doc)

For each sample row:
1. Read the claim. Open the doc. Read the full row context.
2. Check the implementation: does the code/system still behave as the claim says?
3. Mark drift: `y` (drifted — claim is wrong) or `n` (still true).

Record results — a checklist works:

```
[N] verify-docs run on YYYY-MM-DD
- doc#1 — claim: "..." — drift: n
- doc#2 — claim: "..." — drift: y (now does Z, not Y)
- doc#3 — ...
- doc#4 — ...
- doc#5 — ...

Drift rate: 1/5 = 20%
```

### 3. Decide

- **Drift rate ≤ 20%** — structural checks are sufficient. File errata/fix tasks for any drifted claims. Done.
- **Drift rate > 20%** — escalate. Update `t-441` notes with the rate and unblock it. Build the LLM-assisted check; the manual sample alone is too lossy.

### 4. Persist the result

Append a one-line entry to the field log so quarterly trends are visible:

```
Bash: echo "$(date -I) verify-docs N/5 drift" >> docs/field-notes/verify-docs-log.md
```

(File is created on first run; no scaffolding needed.)

## Outputs

- Console output (or JSON) with structural + sample.
- Optional: append to `docs/field-notes/verify-docs-log.md`.
- For each drifted claim: a backlog task to fix the doc or the code.

## Out of scope

- LLM semantic check — that's t-441. Build it only after this skill collects evidence the manual approach is insufficient.
- Continuous monitoring — verify-docs is a periodic surface, not a hook.
- Cross-repo verification — only scans `docs/` in the current repo.

## Reference

- Spec: `system/scripts/verify-docs.spec.md`
- Backing script: `system/scripts/verify-docs.sh`
- Tests: `tests/scripts/test-verify-docs.sh`
- Frontmatter spec: `docs/architecture/features/doc-frontmatter-spec.md`
- Trigger-gated next step: `t-441` (LLM-assisted drift detection)
