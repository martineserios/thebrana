---
title: Adopt Pocock's implementation discipline, v1.3 round — tdd, pr, two invariants, retro held
status: draft
created: 2026-10-07
tasks: [t-3263, t-2981, t-3013, t-3477]
relates-to:
  - "[ADR-097](../architecture/decisions/ADR-097-upstream-band-standing-v1-3.md) — the decision this idea proposes (proposed 2026-10-07)"
  - "[ADR-084](../architecture/decisions/ADR-084-upstream-skill-band-vendored-pocock-skills.md) — the band mechanism; §7a left materialization to 'a separate follow-up ADR'"
  - "[2026-10-07-pocock-recheck.md](../research/2026-10-07-pocock-recheck.md) — evidence: skills v1.3, ring-fit, follow-ups F1–F6"
  - "[2026-08-22-pocock-alignment-decision-matrix.md](../research/2026-08-22-pocock-alignment-decision-matrix.md) — §0 ring-fit filter, KEEP/ADOPT rows"
  - "[tdd-organ-build-loop.md](../architecture/features/tdd-organ-build-loop.md) · [pr-body-organ.md](../architecture/features/pr-body-organ.md) · [upstream-band-pin-bump.md](../architecture/features/upstream-band-pin-bump.md) — the specs"
---
# Adopt Pocock's implementation discipline, v1.3 round

> Shaped 2026-10-07 from the quarterly recheck (t-3263). Status: decided — ADR-097 accepted
> with changes 2026-10-07 after a 3-worker pre-mortem + deep verification (see its Challenge
> record). The plan below is the post-challenge cut; the original P1–P10 is kept for the record.

## Seed

Operator, 2026-10-07: "can we adopt something from him? he is very good implementing." Then:
"start applying changes in the same way you build, starting from idea and ADR and specs —
pure docs. Then we move it into the implementation."

The standing premise has not changed since 2026-08-18: *his ergonomics on top, our substrate
underneath, the ticket is the joint.* What changed is the evidence. Skills v1.3 (2026-10-04)
graduated three skills, his band is at v1.3.1 while brana's three vendored organs are pinned at
v1.2.3, and ADR-084's pilot already read **EXPAND** on 2026-08-30 without the band ever being
declared standing. This round closes that gap and adds the two organs that most directly carry
*how he implements*.

## What "very good at implementing" actually names

Not a vibe. Four concrete mechanisms, each already read off his repo at `main` 2026-10-07:

| Mechanism | Where it lives upstream | What brana has today |
|---|---|---|
| **Red that is proven red.** One failing test; if the red was forced by a mutation, `diff` against a pristine copy before trusting it (PR #1209); smallest green; refactor after. | `tdd` | Discipline spread across `sdd-tdd.md`, `build-loop.md`, `red-verification.sh`; enforced as "a spec or test file exists," not "a red ran" |
| **Evidence at the merge valve.** PR body = smallest visual + before/after evidence + one-way/two-way door + blast radius. "Without asking for hard evidence it's very easy for agents to say 'yeah that probably works.'" | `pr` | `/brana:ship` PR body is `git log --oneline`; feature PRs have no body shape; `pr-reviewer` never sees a danger call |
| **Implementers never explore; merges always fast-forward.** One exploration subagent writes notes outside the repo once; each implementer merges the integration tip into its branch before reporting done. | `implement-spec` | Runner/build have no stated "sync before you say done" invariant; CLOSE presents a merge command the human may find conflicted |
| **Environment retrospective from real logs.** Seven categories (navigation, unwired checks, mechanical→deterministic check, AGENTS.md weight, tool economy, no-ops, information access). Human applies; "you don't want to automate this." | `retro` | `/brana:retrospective` classifies a learning the operator already has; `/brana:close` extracts from the model's memory of the session; nothing reads logs or treats the environment as the subject |

## Ring-fit before anything else (matrix §0)

| Mechanism | Ring | Feeds a valve or removes one? | His side persists it? | Verdict |
|---|---|---|---|---|
| `tdd` | micro | feeds the Beat valve (red→green inside the `/goal` span) | n/a (stateless by design) | **vendor** — t-2981, already AC-approved |
| `pr` | beat, at the human-merge valve | feeds it (gives the valve its brief) | n/a | **vendor** — new organ |
| `implement-spec` invariants | beat | feeds the merge valve (conflict-free merges) | no — orchestrator dies with the session | **take the two invariants, not the skill**; brana's runner *is* his "deterministic loop" |
| `retro` | knowledge | neither; emits proposals | no | **hold** — decide the home first (close EXTRACT vs quarterly run), carry his do-not-automate rule |
| `chief-of-staff`, `loop-me` | epic-shaped, in-context | would remove the wave/epic persistence | no — in-progress, one session | **watch** until graduated |

Nothing here removes a valve. Everything adoptable feeds one. No KEEP row in the 2026-08-22
matrix flips.

## Proposed shape (what ADR-097 decides)

1. **The band is standing, not pilot.** ADR-084 §7a authorized unparking t-2835/t-2836 and
   deferred "materializing the standing band" to a follow-up. This is that follow-up. Standing
   means: a pin policy (one version for the whole band), a manual bump procedure (the pump,
   still run by hand), and the §7 proxies re-used as the band's kill criteria.
2. **Pin moves to v1.3.1 for all three existing organs** (`diagnosing-bugs`, `code-review`,
   `wizard`). First measured drift on the pilot band; two of the three changed upstream
   (`diagnosing-bugs` #1209 + GLOSSARY read; `code-review` standards-file search, foreground
   sub-agents, tracker doc). Spec: `upstream-band-pin-bump.md`.
3. **Admit `tdd` (organ 4) and `pr` (organ 5).** `tdd` is t-2981 as already approved, with
   the ADR-061 invariants re-asserted in the adapter. `pr` is new: thin adapter, GLOSSARY.md
   remapped to `docs/domain/`, three headings mandatory, `pr-reviewer` reads Merge Danger.
   Specs: `tdd-organ-build-loop.md`, `pr-body-organ.md`.
4. **Two invariants into the Beat contract, no vendoring:** (a) exploration once, pointers
   after; (b) sync the integration tip before reporting done so the human merge is
   fast-forward. Home: `/brana:close`'s merge-command step and the runner's close-out.
5. **`retro` is not vendored this round.** A decision task picks its home; the constraint
   travels with it: human-in-the-loop, sampled sessions, never a loop.
6. **GLOSSARY remap.** Every adapter that upstream points at `GLOSSARY.md` maps to
   `docs/domain/` (today `MODEL-001-brana-core.md`; a `glossary.md` does not exist yet —
   t-3013's discipline is where it would come from). ADR-084 §3's CONTEXT.md sentence is
   superseded.

## Proposed backlog plan (penciled, not created — ADR acceptance first)

| # | Task | Kind | Effort | Blocked by | Spec |
|---|---|---|---|---|---|
| P1 | Bump the three vendored organs to v1.3.1; re-verify each adapter's `redirect-check.md`; recompute hashes via `skills-lock-hash.sh` | chore | S | ADR-097 | upstream-band-pin-bump.md |
| P2 | t-2981 as approved — vendor `tdd`, adapter ≤15 lines, build-loop + fix call it, ADR-061 invariants preserved | feature | M | P1 | tdd-organ-build-loop.md |
| P3 | Vendor `pr`; adapter `system/skills/pr-body/`; `/brana:ship` and feature-branch close-out use it; `pr-reviewer` reads Merge Danger | feature | S | P1 | pr-body-organ.md |
| P4 | CLOSE merge-command step: sync integration tip (`dev`) into the branch before presenting the command; runner close-out states the same | fix | XS | — | ADR-097 D4 |
| P5 | Decide `retro`'s home (close EXTRACT step vs quarterly run vs out); write the spec if in | research | S | — | — |
| P6 | Reword t-3013 + ADR-084 §3 from CONTEXT.md to GLOSSARY.md; decide whether `docs/domain/glossary.md` is bootstrapped there | docs | XS | — | — |

P1 → P2/P3 is the only hard order: bump the pin before adding organs at the new pin, so the
whole band carries one `pinnedRef`.

### Added by the same-day deeper sweep (research §6, ADR-097 D8)

| # | Task | Kind | Effort | Blocked by | Source |
|---|---|---|---|---|---|
| P7 | Rules → hooks audit: test every always-load rule line with "could a `PreToolUse` hook exit 2 with this?"; convert, delete the line, re-measure headroom | refactor | S | — | §6 S1 |
| P8 | Triage repro gate: reproduce-or-record + existing-task check before any role flips to `ready-for-agent`; brief names contracts, never paths | feature | S | — | §6 S2 |
| P9 | QA-plan brief at wave ship: `kind: review` task from the wave's commits, tagged human, linked from the digest, completed when walked | feature | S | — | §6 S3 |
| P10 | File-size gate: pre-commit lint, no file crosses 1,000 lines without an override tag | chore | XS | — | §6 S4 |

Folded into existing tasks (context appends, no new task): fidelity routing + prototype
round-trip → t-3012, t-2984 (§6 S5); slice lower bound → decompose phase note (§6 S6);
tautology question, seam gate, one-test-at-a-time → `tdd-organ-build-loop.md` and t-2981
(§6 S8). Rule proposal for the human to place in `delegation-routing.md`: smartest model for
the interview and the challenge, cheaper models for build, runner and any read-and-extract
fan-out (§6 S7, operator direction 2026-10-07).

### Convergence evidence, not adoption (research §6c)

Lauren Tan's pstack reached brana's runner-manifest + human-merge-valve design independently.
The one open item on that side — revert-and-tighten for whatever rung may merge alone — is
now named as the consumer of the `pr` organ's Merge Danger call (ADR-097 D3).

## Plan after the challenge (ADR-097 §Plan — the one that is filed)

| # | Task | Kind | Effort | Blocked by | Why it survived |
|---|---|---|---|---|---|
| P0 | Fix the band's call path: drop `disable-model-invocation` from the two live adapters, add call-site records to all adapters, one resolution test per organ, re-read ADR-084 §7a against real records | fix | S | — | CRITICAL 1: the flag blocks the Skill tool; the pilot was never reachable |
| P1 | Pin bump v1.2.3 → v1.3.1 with dated per-organ hold; `vendored_from:` updated; heading-presence + pin-equality tests created | chore | S | P0 | first measured drift; tests the specs assumed do not exist |
| P2 | t-2981 corrected: `tdd` organ covers red + green only, callers keep 3d1/3d2, inline fallback, delegation checklist path named | feature | M | P1 | CRITICAL 2: no refactor step exists; registration commit must stay caller-owned |
| P3 | PR-body template + `--body-file` in ship + runner body + `gh pr create` headings hook | feature | S | — | WARNING 4: both real PR paths are scripted; a template + hook covers them, an organ cannot |
| P4 | Read-only merge-readiness probe at close.md step 10; one sentence in epic-drain §Merge; "explore once, point after" for the runner's exploration step | fix | XS | — | WARNING 6: no-ff merge, runner denies merge, close window must not widen |
| P7 | One-shot rules → hooks audit, proposal-only, must-fire test per conversion, scoped by `rules-over-hooks-for-gates.md` | refactor | S | — | observed failure: CI headroom floor broke twice |

**Parked, with the trigger that un-parks each** (Pocock's own `SCOPE.md` bar: an observed
failure, not a hypothetical improvement):

| # | Parked item | Trigger |
|---|---|---|
| P5 | `retro`'s home (close EXTRACT step vs quarterly run vs out) | a session whose environment defect a log-reading pass would have caught |
| P6 | GLOSSARY wording in t-3013 | t-3013 starts (ADR-084 §3 is already superseded by ADR-097 D7) |
| P8 | Triage repro gate before `ready-for-agent` | a task that reached ready-for-agent and was not reproducible or already built |
| P9 | QA-plan brief at wave ship | a wave whose close-out the human could not check from branches alone |
| P10 | File-size gate | a review miss attributable to an oversized file; and a rule for files already over the limit |

Twins to cite when P2 starts: t-3010 (consolidate the diffused TDD discipline into one
reference) and t-3018 (spike: refactor split out of red-green into review). P2 does not
pre-decide t-3018.

## Open questions for the ADR challenge

- Does `pr` need its own adapter, or is a 20-line template inside `/brana:ship` cheaper and
  equally faithful? The ADR argues adapter: the organ is model-invoked and must fire on
  feature-branch PRs too, not only the dev→main ship.
- `tdd` on the `/goal` seam: his skill has no termination engine; the adapter re-asserts
  ADR-061 invariants 2 and 3. Is "red→green only, refactor outside the predicate" compatible
  with his refactor step, or does the adapter cut his loop at green? (Spec answers: cut at
  green; refactor runs in brana's existing post-green step.)
- Three organs bumped at once vs one at a time: the §7 proxies were pre-registered per organ.
  The ADR bumps together but records proxies per organ.
