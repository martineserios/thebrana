---
status: accepted
---
# ADR-075: Ship on Deploy-Surface Change, Not on Batch Size or Schedule

- **Status:** Accepted
- **Date:** 2026-07-31
- **Evidence:** t-2547 (this decision), t-2546 (repo-vs-live drift), t-2506 (a fix measured inert on the binary channel while merged and tested)
- **Related:** ADR-060 (two-tier dev/main integration model), ADR-069 (fail-open signals), [pattern: exit-code-is-not-evidence-of-work](../../../.claude/memory)

> **Provenance note.** The first two drafts of this ADR argued from a deferral-loop narrative and
> from live-drift figures that went stale mid-session while four lanes were changing the same
> system. Both were withdrawn. What follows is argued from *structural* facts in `bootstrap.sh`
> and from a timestamped snapshot, because point-in-time drift readings in this repo do not
> survive the hour in which they are taken — which is itself worth knowing before citing one.

## Context

`main` is production — what `bootstrap.sh` deploys to `~/.claude/`. Feature branches merge to
`dev`, and nothing in `system/` is in force until `dev` is promoted and bootstrap runs (ADR-060).

**Promotion is not the problem.** Measured 2026-07-31T13:19: `main` advanced 117 commits over the
course of the day across several promotions, hooks deployed at 11:11, and by 13:19
`dev == main == c348482a` with **zero** deploy-surface divergence. An earlier framing of this
decision (t-2547, written 2026-07-28) described a compounding deferral loop; on the evidence of
2026-07-31 that loop did not hold, and this ADR does not rest on it.

### The real defect: deploy is two channels, and only one of them acts

`bootstrap.sh` mirrors `system/` into `~/.claude/` with `rsync -a --delete` (`:405`, `:417`) — a
true mirror, so that channel converges by construction. The `brana` binary is a **second,
independent channel that bootstrap does not execute.**

It is not that bootstrap is unaware of the binary. It checks (`bootstrap.sh:931-937`, and
`:946-953` for `brana-mcp`, added by t-2378), finds the source newer than the installed artefact,
and **prints a command for a human to run**:

```
! brana-cli binary may be stale (source changed since last build)
  Run: cd $RUST_SRC_DIR && CARGO_PROFILE_RELEASE_LTO=off cargo build --release -p brana-cli && ...
```

Every `cargo` occurrence in `bootstrap.sh` is inside a comment or an `echo`. **The deploy tool
detects the stale channel, reports it, and does nothing** — the same advisory-signal shape this
system keeps rediscovering elsewhere (ADR-065 D4's unenforced WIP cap; ADR-069's fail-open),
except here it sits inside the deploy path itself.

The consequence is *silent partiality*, not latency: a ship that promotes `main` and runs
bootstrap looks complete, exits clean, and can still leave the binary channel behind.

**Observed instance.** Earlier on 2026-07-31 the installed binary was built 2026-07-27T20:30 while
the newest `system/cli` commit was 2026-07-29T10:26, and `strings ~/.local/bin/brana | grep -c
base_written_at` returned `0` — t-2506's compare-and-swap fix, merged with 1265 tests passing, was
not in the running binary, so session closes were still silently dropping `next[]` handoff
entries. It was resolved at 11:46 when the printed command was run by hand. The fix worked; the
mechanism that was supposed to surface it only suggested it.

### Batch size does not measure risk

Separately, and independent of the above: at the snapshot where `dev` was 68 commits ahead of
`main`, that batch decomposed by deploy surface as:

| Path | Files | Commits | Deploy channel |
|---|---|---|---|
| `system/hooks` | 3 | 3 | `bootstrap.sh` — **inert until deploy** |
| `system/rules` | 0 | — | `bootstrap.sh` — inert until deploy |
| `system/agents` | 0 | — | `bootstrap.sh` — inert until deploy |
| `system/skills` | 3 | — | plugin cache |
| `system/cli` | 10 | 16 | **separate** `cargo build` + install |
| `docs` | 26 | — | none — live in the repo on merge |
| `.claude` (tasks.json) | 1 | — | none |

Sixty-eight commits reduce to **six deploy-relevant files plus a binary rebuild.** A commits-ahead
count is dominated by documentation and task-record churn with no deployed footprint whatsoever,
so it is the wrong input to any ship decision — whether that decision is to defer, or to size a
batch, or to raise an alarm.

### Rollback cost, measured

Reluctance to promote presumes a bad promotion is expensive. It is not:

- Promotion is `--ff-only`, so `main` simply moves. There is no merge commit to unwind.
- `bootstrap.sh` deploys hooks with `rsync -a --delete` (`bootstrap.sh:405`, `:417`) — a **mirror**,
  not an accumulation. Re-running it from an earlier checkout restores the earlier state exactly.
  Rollback is deterministic, not lossy.
- `bootstrap.sh:395` already runs `rsync --dry-run --itemize-changes` for the hooks surface. The
  tool for inspecting blast radius before deploying already exists and was never used as a
  decision input.
- **Exception:** `bootstrap.sh` does not rebuild the `brana` binary. That is a second, independent
  deploy channel with its own rollback step.

### Withdrawn claims

Two earlier drafts argued from live-drift readings. Both are withdrawn, and the reason is worth
recording because it generalises:

- **"3 differing hook entries and 1 differing rule, unchanged over three days."** The rule was
  `Only in system/rules: README.md` — a readme that does not deploy, counted as drift without
  being inspected. The hook count reached **0** during the writing of this ADR.
- **"An ad-hoc bootstrap deployed dev's tree while `main` was 68 commits behind."** False. `main`
  had been promoted to `0803ef52` at 11:10, one minute before the 11:11 hook deploy. That was a
  correct ship, not a bypass.
- **"t-2542's undeployed state caused the branch-name guard to reject this ADR's `git worktree
  add`."** Unverifiable — the rejection occurred (the guard read `2>&1` as a branch name), but it
  cannot be ordered against the 11:11 deploy. If the guard was already current, the
  quoted-argument case in t-2542 is not fully fixed. That is an open question, not evidence here.

**The generalisable lesson:** this repo is written by several concurrent sessions, so a drift
measurement is stale roughly as fast as it can be acted on. Structural facts (what `bootstrap.sh`
executes) hold; point-in-time deltas (`diff -rq` counts, commits-ahead) do not, and an ADR built
on the latter argues from a state that no longer exists by the time anyone reads it.

## Decision

**Ship is triggered by a change to the deploy surface, not by batch size and not on a schedule.**

> Any commit that touches `system/hooks`, `system/rules`, `system/agents`, or `system/cli` is
> promoted to `main` and deployed on merge to `dev`. Everything else rides along at no additional
> cost.

Rationale for rejecting the alternatives:

- **Size-triggered is disqualified.** It fires on a metric measured above to be uncorrelated with
  risk. It would fire constantly on documentation churn while a single inert hook fix waited.
- **Time-triggered treats unlike things alike.** A `docs/` commit is live the moment it merges. A
  hook, rule, agent or CLI commit is *dead* until deployed. A uniform interval applies the same
  urgency to both.
- **Event-triggered follows the actual failure mode**: the harm is a change that is merged, green,
  and not in force. That set is exactly the deploy surface.

"Everything else rides along" is not a concession — `--ff-only` promotion admits no partial
promotion, so unrelated commits are carried at zero marginal risk once the surface change
justifies the promotion.

### Deploy-pending indicator

Any deploy-pending signal is **derived at read time and counts the deploy surface, never commits.**
The historical written-down count was wrong at every observation (12, then 1, 10, 16, 55, 68)
because it counted commits, and a signal nobody can trust is worse than none — it is
indistinguishable from a verified one.

```sh
git diff --name-only main..dev -- system/hooks system/rules system/agents system/cli | wc -l
```

paired with a binary staleness check (live `~/.local/bin/brana` mtime vs. the newest `system/cli`
commit) — the check `bootstrap.sh:931` already performs.

Both readings must be taken at the moment of use and reported with their timestamp. At
2026-07-31T13:19 this reads "0 deploy-relevant files pending, binary current (built 11:46)". Two
hours earlier the same commands read "13 pending, binary 4 days stale". Neither is *the* state;
each is a state, and quoting one without its timestamp is how the two withdrawn claims above got
into this document.

## Consequences

- Promotion becomes frequent and small on the surface that matters, while documentation continues
  to accumulate on `dev` without triggering anything.
- **The binary rebuild must be executed, not printed.** `bootstrap.sh:934` and `:949` currently
  emit a copy-paste `cargo build` command and continue; a ship that runs bootstrap and stops there
  exits clean with one channel stale. That is how t-2506's fix stayed out of the running binary
  from 2026-07-29 until it was rebuilt by hand at 2026-07-31T11:46. Any implementation of this
  rule either runs the rebuild or fails loudly — printing a remedy and proceeding is the defect,
  not the mitigation.
- `bootstrap.sh`'s existing `--dry-run` becomes a pre-promotion check rather than dead
  functionality.
- ADR-060's two-tier model is preserved and made honest: `dev` is an integration buffer that
  actually drains, rather than a permanent third branch.

### Deliberately not decided here

**How the trigger is enforced** — hook, close step, or convention — is implementation and is left
to a separate task. This is called out rather than left implicit because an unenforced ship rule
is precisely the advisory-signal failure class this system keeps rediscovering: ADR-065 D4's
promotion review had a due date that passed unactioned, and the WIP cap it governs was breached
six times in a single session while being dutifully reported. A rule recorded here and enforced
nowhere would be the same artefact in a new file.
