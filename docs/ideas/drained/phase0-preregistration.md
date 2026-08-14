---
title: Phase 0 pre-registration — build context measurement (t-2591)
status: pre-registered
created: 2026-08-01
---
# Phase 0 pre-registration

> **Written and committed BEFORE any data was aggregated.** The adversarial review of
> `enforced-delegation.md` found the original falsifier anchored and sunk-cost-biased. This
> file exists so the decision rule cannot be tuned after seeing the result. The commit
> timestamp is the proof.
>
> Only two things were inspected before writing this: the count of available session files
> (to set a feasible N) and the JSONL field names (instrument calibration). No token
> aggregation of any kind was run.

## The question

In a real `/brana:build` session, do **understanding** tokens or **iteration churn** tokens
dominate? Delegation to an executor exports churn but not understanding — the orchestrator
must load roughly the same files and conventions to write a self-contained brief. So if
understanding dominates, the delegation layer cannot pay for itself.

## Operational definitions (fixed — not revisable after seeing data)

**Build session:** a session JSONL whose `gitBranch` matches the task-branch convention
(contains `/t-`). Sessions on `main`/`dev` are excluded — they are not builds.

**Per-turn cost:** `input_tokens + cache_creation_input_tokens + cache_read_input_tokens +
output_tokens` from `message.usage`, attributed wholly to the turn's class.

**Turn classification** — by the tool calls the assistant turn makes:

| Class | Tools |
|---|---|
| **UNDERSTANDING** | `Read`, `Grep`, `Glob`, `Explore`/`Agent`, `WebFetch`, `WebSearch`, `Skill` |
| **CHURN** | `Bash`, `Edit`, `Write`, `NotebookEdit` |
| **ORCHESTRATION** | everything else (plain text, `AskUserQuestion`, `Task*`, backlog/MCP ops) |

A turn with tools from more than one class is attributed to the **highest-cost-to-export**
class present, in the order UNDERSTANDING > CHURN > ORCHESTRATION. This deliberately biases
*against* the delegation hypothesis: mixed turns count as understanding, which is the class
delegation cannot export. If delegation still passes under a biased-against rule, the result
is trustworthy.

**Cold-load cost:** tokens consumed from session start until the first `Edit`/`Write` call —
a proxy for what a fresh background executor must re-load before it can do anything.

## N

**N = 12** most recent build sessions matching the definition above. If fewer than 12 exist,
use all of them and report the actual N. No session is excluded after the fact for any
reason.

## Decision rule (pre-registered)

Let `churn_share = CHURN / (UNDERSTANDING + CHURN + ORCHESTRATION)`, computed over the pooled
N sessions.

| Outcome | Condition | Consequence |
|---|---|---|
| **PROCEED** | `churn_share >= 0.50` | Delegation exports the majority of build cost. Rungs 2–4 justified. |
| **INCONCLUSIVE** | `0.35 <= churn_share < 0.50` | Delegation exports a minority. Needs a different intervention; do not build the layer on this evidence. |
| **KILL** | `churn_share < 0.35` | Understanding dominates. Information conservation confirmed. The delegation layer dies; receipts continue independently. |

**Quota veto (independent, overrides PROCEED):** if median `cold_load_share` > 0.40, a
parallel executor re-pays more than 40% of a session's cost just to start. Parallelism then
multiplies quota rather than dividing wall-clock, and the layer is quota-negative regardless
of the churn split — the ADR-059 hollow-under-subscription failure recurring. In that case
the outcome is **KILL** even if `churn_share >= 0.50`.

## What this does NOT prove (honesty contract)

- It measures historical sessions under the *current* inline workflow. It cannot show what a
  delegated workflow would cost — only the size of the prize.
- Turn-level attribution is coarse: a turn that reads three files and runs one test is
  counted wholly as understanding.
- Cache-read tokens are counted at face value; they are cheaper in dollars than fresh input
  tokens, so raw token share overstates the dollar cost of re-loading context.
- It says nothing about whether delegation improves *correctness* — only cost.
