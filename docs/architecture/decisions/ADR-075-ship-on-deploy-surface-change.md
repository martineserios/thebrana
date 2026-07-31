# ADR-075: Ship on Deploy-Surface Change, Not on Batch Size or Schedule

- **Status:** Accepted
- **Date:** 2026-07-31
- **Evidence:** t-2547 (this decision), t-2546 (repo-vs-live drift), t-2214 (the deferral that started the loop, cancelled), t-2542 + t-2506 (two fixes measured inert while merged)
- **Related:** ADR-060 (two-tier dev/main integration model), ADR-069 (fail-open signals), [pattern: exit-code-is-not-evidence-of-work](../../../.claude/memory)

## Context

`main` is production — what `bootstrap.sh` deploys to `~/.claude/`. Feature branches merge to
`dev`, and nothing in `system/` is in force until `dev` is promoted to `main` and bootstrap runs
(ADR-060). Promotion has been repeatedly deferred, and the deferrals compound: t-2214 ("Ship
dev→main + bootstrap.sh") was filed 2026-06-21 and deferred the same day, its recorded reason
being that `dev` had grown to 83 commits. The batch grows precisely while promotion is deferred,
so each deferral makes the next one more likely.

The deferral was locally reasonable every time. A large undifferentiated batch *is* riskier to
promote than a small one — if batch size measures risk. **It does not, and that assumption was
never tested.**

### Measurement, 2026-07-31

`dev` was 68 commits ahead of `main` (55 three days earlier — +13 in 3 days), 48 files changed,
4534 insertions. Decomposed by deploy surface:

| Path | Files | Commits | Deploy channel |
|---|---|---|---|
| `system/hooks` | 3 | 3 | `bootstrap.sh` — **inert until deploy** |
| `system/rules` | 0 | — | `bootstrap.sh` — inert until deploy |
| `system/agents` | 0 | — | `bootstrap.sh` — inert until deploy |
| `system/skills` | 3 | — | plugin cache |
| `system/cli` | 10 | 16 | **separate** `cargo build` + install |
| `docs` | 26 | — | none — live in the repo on merge |
| `.claude` (tasks.json) | 1 | — | none |

Sixty-eight commits reduce to **six deploy-relevant files plus a binary rebuild.** The count that
triggered every deferral is dominated by documentation and task-record churn with no deployed
footprint whatsoever.

### Rollback cost, measured

The deferral instinct rests on a bad promotion being expensive. It is not:

- Promotion is `--ff-only`, so `main` simply moves. There is no merge commit to unwind.
- `bootstrap.sh` deploys hooks with `rsync -a --delete` (`bootstrap.sh:405`, `:417`) — a **mirror**,
  not an accumulation. Re-running it from an earlier checkout restores the earlier state exactly.
  Rollback is deterministic, not lossy.
- `bootstrap.sh:395` already runs `rsync --dry-run --itemize-changes` for the hooks surface. The
  tool for inspecting blast radius before deploying already exists and was never used as a
  decision input.
- **Exception:** `bootstrap.sh` does not rebuild the `brana` binary. That is a second, independent
  deploy channel with its own rollback step.

### What deferral actually cost

Measured the same day, unchanged across the preceding three days: `diff -rq` reported 3 differing
hook entries and 1 differing rule between `system/` and `~/.claude/`. The live binary was built
2026-07-27 against a newest-CLI-commit of 2026-07-29, and `strings ~/.local/bin/brana | grep -c
base_written_at` returned **0** — confirming t-2506's compare-and-swap fix was absent from the
running binary. Every session close was still silently dropping `next[]` handoff entries while
the fix sat merged, tested (1265 passing) and inert.

The second inert commit, `f6a736c6` (t-2542), fixes the branch-name guard's misparsing of quoted
shell arguments. During the authoring of this ADR that undeployed bug rejected the very
`git worktree add` command creating its branch — the guard read `2>&1` as the branch name. A fix
for a defect blocked the work of shipping itself.

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
commit). On 2026-07-31 that reads "13 deploy-relevant files, binary 4 days stale" rather than "68
commits" — a number that can be acted on.

## Consequences

- Promotion becomes frequent and small on the surface that matters, while documentation continues
  to accumulate on `dev` without triggering anything.
- The two deploy channels must both be honoured. A promotion that runs `bootstrap.sh` but skips
  the `cargo` install leaves the binary channel stale, which is how t-2506's fix stayed inert
  after its merge. Any implementation of this rule covers both, or it recreates the defect it
  exists to prevent.
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
