---
title: Build receipts — proof of done that doesn't rest on agent self-report
status: draft
created: 2026-08-01
---
# Build receipts

> Input spec for **t-2592** (ADR) and **t-2595** (feature spec). Consolidates research done
> 2026-08-01 against gentle-ai's Receipt-Driven Development, so the findings live somewhere
> discoverable rather than only in task context.
>
> Related: [enforced-delegation.md](enforced-delegation.md) (the design this outlived),
> [gentle-ai-adoption-ladder.md](gentle-ai-adoption-ladder.md).

## The problem we're actually solving

`pattern_task-notes-are-not-work-state`: task notes and git routinely disagree about whether
work is done. "Done" currently rests on an LLM's evaluation plus notes the same LLM wrote. We
want an artifact where **git and executed test output are the authority**, not assertion.

This is our own reason. It does not depend on gentle-ai being right.

## What gentle-ai actually does — and doesn't

Researched by reading the source, not the README. The headline correction:

**Their receipts hash a claim. They never execute verification.**

| | |
|---|---|
| The verdict | a CLI flag the *agent* supplies — `--outcome passed` (`internal/cli/review_artifact.go:44,78`) |
| The "evidence" | caller-supplied bytes, only SHA-256'd (`verification_evidence.go:90`) |
| State transition | reads that supplied enum directly (`compact.go:1512-1516`) |
| Subprocesses spawned by the review engine | **`git` only** — no test runner, ever (`snapshot.go:1468`) |

They are explicit and honest about this boundary — a documented design decision, not an
oversight:

> "Checksums only where useful for detecting accidental corruption; **they are not
> authentication**" — `docs/review-authority-threat-model.md:29`

And no test asserts a truthful-verification property, because the code claims none.

**So their receipt means:** *"an agent asserted outcome X over exactly these git trees, and the
trees are still these."* That is **scope-binding, not truth** — a narrower claim than
"structural proof replaces agent self-report" suggests.

## What to steal, what to deviate on

**Deviate — execute the check.** Our `mint` must run the test command itself and hash **its own
captured stdout + exit code**. This is the property gentle-ai explicitly declines to claim, and
the only thing that makes the artifact evidence rather than a signed assertion. (See
`pattern_hashed-claim-is-not-evidence`.)

**Steal — the git binding is the load-bearing half.** Everything that actually catches drift is
re-derivable from the repo at gate time: `base_tree` / `candidate_tree` (git tree OIDs from
frozen snapshots), `paths_digest` (domain-separated + length-prefixed, `snapshot.go:1313`), and
snapshot identity. The evidence hash alone catches nothing — it is only an equality token. A
receipt is worth building on the git binding **even without execution**.

**Steal — a three-valued gate result**, their single best design call:

| Result | Meaning |
|---|---|
| `allow` | proceed |
| `scope-changed` | your candidate moved — routes to *recovery*, not restart |
| `invalidated` | your approval is void |

Collapsing these into a boolean is what makes verification tools infuriating to use.

**Steal — the mechanical hygiene:**
- Split *pure shape validation* from *pure comparison*, both with zero I/O; all re-derivation
  lives in the caller (their `validateDerivedGate` has no repo handle, by design).
- Store under `git rev-parse --git-common-dir`, not `.git` — one authority shared across linked
  worktrees, invisible to `git status`, never pushed.
- Content-bound journal for idempotency, **not a lock** — digest the whole request, plan
  revisions before applying, mark `published`/`completed` separately. A differing retry becomes
  a hard error; the identical request resumes.
- **Re-check after deciding** — re-derive the snapshot and re-read authority on the allow path,
  or the gate is a TOCTOU.
- Canonical JSON, reject unknown fields and trailing values; domain-separate and length-prefix
  every hash input.

## The enforcement gap — the part they don't have

gentle-ai's five gates (`post-apply`, `pre-commit`, `pre-push`, `pre-pr`, `release`) are **CLI
subcommands, not git hooks** — grep for `.git/hooks` across their codebase returns nothing.
Compliance is procedural, carried by agent-facing skill text. **Nothing physically prevents
`git commit`;** an agent that skips `review validate` commits normally.

That is `pattern_gate-armed-by-the-party-it-constrains` sitting in the reference
implementation. A mature, carefully-built system landing on a voluntary gate by default is
evidence the failure is *structural*, not carelessness.

**Consequence for us:** t-2594 (pre-merge hook) is the part gentle-ai lacks, and the thing that
makes a receipt more than advisory. Anchor it to the **merge** — an involuntary event — never
to state the committing party opts into writing. ADR-060 records that `dev`→`main` has no
automated gate today, so without t-2594 the receipt is decorative.

## Evidence that any of this works

**There is none, publicly.** Stated plainly so nobody later cites gentle-ai as validation:

- ✅ An internal benchmark (`bench/`, 36 end-to-end journeys) measuring *friction of their own
  tool* — 6 out-of-band blocks initially, 0 dead ends after fixes. Honest enough to find its own
  biases.
- ✅ 18+ named community testers filing real bugs.
- ❌ No external adoption metrics, no testimonials, **no measured outcomes**. Nobody reporting
  faster or safer development.

Adopting receipts means adopting a **design hypothesis with a compelling rationale**, not a
proven practice.

## Failure modes their users actually hit

Worth designing against — these are consequences of the design, not bugs:

- **Deadlock (@decode2):** a corrected candidate passes verification and holds approval, but
  remediation needs a distinct successor, creating a successor needs an invalidated
  predecessor, and invalidation is refused for a healthy approved candidate. **Three
  individually defensible rules forming a closed loop.**
- **Forged authorization accepted and stored as genuine (@Blue-XL)** — "a wrong one lies,"
  worse than an absent field.
- **Kill switch off, but approved receipts still present** → `authority_corrupted` (@Andiveli).

The lesson: every additional state an enforcement system can be in is a state it can get stuck
in. Prefer fewer states.

## Their design constraint, worth adopting verbatim

> "It **must not get in the way**. A system that forces ceremony to change a comma gets
> uninstalled in three days." — `docs/architecture/the-organic-rdd-story.md`

## Task track

| Task | | |
|---|---|---|
| t-2592 | S | ADR — receipts as evidence, and why enforced delegation was deferred |
| t-2595 | S | Feature spec (gates t-2593) |
| t-2593 | M | `brana receipt mint\|validate` — mint executes the tests |
| t-2594 | S | Pre-merge hook — the part gentle-ai doesn't have |

Order: t-2592 + t-2595 → t-2593 → t-2594.
