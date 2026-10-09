---
status: accepted
supersedes: docs/architecture/decisions/ADR-097-upstream-band-standing-v1-3.md
amends: docs/architecture/decisions/ADR-084-upstream-skill-band-vendored-pocock-skills.md
respects: docs/architecture/decisions/ADR-061-goal-integration-three-primitive.md
---

# ADR-098: Retire the vendored upstream band; install Pocock's plugin as-is

**Status:** Accepted (2026-10-09 by Martín Rios, on "install his plugin as-is, retire the band" after the t-3489 gate). Docs only; deletion and install are separate tasks.
**Date:** 2026-10-09
**Deciders:** Martín Rios
**Tags:** skills, upstream-band, mattpocock-mining, tie-break-rule, harness-audit
**Supersedes:** [ADR-097](ADR-097-upstream-band-standing-v1-3.md) (band standing, pin v1.3.1, organs 4-5). **Amends** [ADR-084](ADR-084-upstream-skill-band-vendored-pocock-skills.md): §1 instruments, §2 vendoring mechanism, §3 name-remap contract, §7a EXPAND are withdrawn; the layer test and the swap table's KEEP-BRANA verdicts stand.
**Evidence:** t-3489 branch `brana-v3-redesign/fix/t-3489-band-call-path` (HEAD 9f17211a, unmerged) · [research/2026-10-07-pocock-recheck.md](../../research/2026-10-07-pocock-recheck.md) · memory `project_harness-audit-2026-10-07`

---

## Context

ADR-084 vendored three upstream skills behind thin adapters; ADR-097 made that band standing. Building P0 (t-3489) produced the evidence that the mechanism does not earn its keep:

- **Unreachable since shipped.** `disable-model-invocation: true` blocks the Skill tool (ADR-076 #3). Live probe, 2026-10-07: "Skill brana:diagnose-hard-bug cannot be used with Skill tool due to disable-model-invocation." Zero recorded invocations in six weeks.
- **Repo-local by construction.** Organs live under `.agents/skills`; `bootstrap.sh` syncs only `system/`. Client repos never receive them, so every call needs an inline fallback, which means the adapter is a second copy of the procedure.
- **Machinery outgrows the payload.** The fix needed a resolver, a recorder, a heading-presence test, a pin-equality test, a hold ledger, a validate check and a remedy entry to keep three ~20-line adapters alive. The panel found 14 defects in that machinery (call path, record shapes, CWD-relative paths, fallback exit codes).
- **The operator's tie-break rule (2026-10-07):** where brana and Pocock cover the same ground, choose his version and retire ours; do not merge. The harness audit (same day) found no band use and recommended trimming brana to about 8 skills.

## Decision

1. **Retire the band.** Delete the adapters `diagnose-hard-bug`, `two-axis-review`, `provisioning-wizard`; their lock entries and vendored copies under `.agents/skills/{diagnosing-bugs,code-review,wizard}`; `.claude/skills` symlinks; `redirect-check.md` files; the §1 pump/gauge/valve design. Nothing replaces them.
2. **Install his plugin as-is** (`claude plugins install mattpocock-skills`), the operator running it, since it changes global config. His updates then reach brana the way his other users get them; there is no pin, no sync, no adapter. The "managed bundle that updates automatically" property ADR-084 §2 rejected is accepted here on purpose: with no adapters there is nothing for an update to break except his own skills.
3. **Callers invoke his skills by their plugin names** (`mattpocock-skills:diagnosing-bugs`, `:code-review`, `:wizard`, `:tdd`). Where brana has a prose equivalent, the tie-break rule retires brana's: `/brana:fix`'s hard-bug branch calls his `diagnosing-bugs`; two-axis review becomes his `code-review`.
4. **What brana keeps because his scope lacks it** (ADR-084 swap table, ring-fit filter): the persisted ledger, atomic pull and leases, waves, portfolio, receipts, the `/goal` span and `red-verification.sh` registration (ADR-061). These are not "covering the same ground".
5. **Seam rule for `tdd` (supersedes ADR-097 D3).** Brana's build loop keeps the red commit (3d1) and the test gate (3d2) so registration and the `/goal` span (ADR-061 inv. 2-3) are untouched. His `tdd` is called for write-the-failing-test and smallest-green; the loop stops at green. There is no refactor step in brana's loop; t-3018 decides one. No resolver, no fallback text: if the plugin is absent the build loop's existing inline steps run, which is today's behaviour, not new code.
6. **`pr` (supersedes ADR-097 D3 on PR bodies).** Content: his `pr` skill's three sections are the body shape. Enforcement stays brana's, because two PR paths are scripts a skill cannot run inside (`/brana:ship` Part A, the runner's `gh pr create`, whose executor has no Skill tool): a `PreToolUse` hook on `gh pr create` checks the three headings and Door value, and `--body-file` carries the filled body. Merge Danger informs the human only (ADR-092). **Open, operator's call:** if you prefer no hook, ship uses his skill's text by hand and the runner path stays a one-liner.
7. **Cost of the install (measured 2026-10-09, corrects the earlier draft).** The operator installed `mattpocock-skills@claude-plugins-official`, scope user. It ships 38 skills with about 5.9 KB of description text, roughly 1.5k tokens of ambient context every turn. `system/scripts/context-budget.sh` and the pre-commit hook count only `system/`, so they do **not** see this cost and will not block; the 11-byte headroom is unaffected. The ambient cost is real but outside the gauge, so the audit's skill trim is the lever, not a budget gate. Brana does not use most of the 38; disabling the unused ones in plugin settings is a follow-up, not a precondition.
7a. **Version lag.** The official marketplace serves **1.2.3**, not his latest 1.3.1 (`claude plugins marketplace update` did not move it). Effect today: `pr` is in his in-progress bucket (still model-invocable), `retro` and `implement` are user-invoked-only, the `GLOSSARY.md` rename is absent. Nothing brana calls depends on 1.3.1, so staying on 1.2.3 is accepted. To track his repo directly instead: `claude plugin uninstall mattpocock-skills@claude-plugins-official`, `claude plugin marketplace add mattpocock/skills`, `claude plugin install mattpocock-skills@mattpocock`. Operator's call; revisit when something brana needs only exists in 1.3.x.
7b. **Call path verified.** `tdd`, `diagnosing-bugs`, `code-review`, `wizard` and `pr` carry no `disable-model-invocation`, so brana skills can reach them through the Skill tool as `mattpocock-skills:<name>`. `retro` and `implement` carry it and can never be called by another skill (upstream `.agents/invocation.md`).
8. **Keep from t-3489:** the class detector (any skill with `disable-model-invocation: true` still called through the Skill tool anywhere in `system/` fails validation) and the lesson, stored as pattern `quarantine-flag-severs-skill-from-its-callers`.
9. **Retained from ADR-097, unchanged:** D4 (read-only merge-readiness probe at build close step 10, never in the runner), D5 (`retro` held, human-in-the-loop, never a loop), D6 (watch `chief-of-staff`, `loop-me`), D8 item 1 (one-shot rules-to-hooks audit, proposal-only, must-fire tests; scoped by `rules-over-hooks-for-gates.md`). D1/D2/D7/D9 are withdrawn with the band.

## Plan

| Task | Change |
|---|---|
| t-3489, t-3495 | cancelled (done 2026-10-08) |
| t-2981 | rescoped: call his `tdd` from build-loop 3d/3e and `/brana:fix`; keep 3d1/3d2; AC rewritten, no vendoring |
| t-3490 | narrowed to the headings hook + `--body-file` (content from his `pr`); the template file is dropped |
| t-3491, t-3492 | unchanged |
| new: retire band | delete adapters, lock entries, `.agents/skills` organs, symlinks; remove skills.md rows; keep the class detector as validate Check |
| new: install plugin | operator runs the install after the budget gate (§7); then switch `/brana:fix` and build to plugin-prefixed names |

## Consequences

**Positive.** One fewer mechanism to keep alive; his updates arrive without a brana step; the tie-break rule is applied once, in writing, instead of per skill.
**Negative (accepted).** brana depends on a third party's skill names and behaviour with no pin; a breaking upstream rename breaks callers until fixed (SCOPE.md says he will not take brana's requests). Ambient context cost rises by his descriptions. Client repos get his plugin only if installed there.
**Reversal path.** The t-3489 branch holds the working resolver/recorder; vendoring can return per skill if his updates ever break a caller twice.

## Non-Actions

| Not doing | Why |
|---|---|
| Pin or vendor his plugin | the pin machinery is what failed |
| Write native 30-line equivalents | operator chose his version as-is |
| Merge t-3489 | its machinery is retired; only the detector and the lesson are kept |
| Install the plugin from this session | changes global config; operator action (done) |
