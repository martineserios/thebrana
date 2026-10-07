# Feature: PR-body template + `gh pr create` hook — evidence-first PR bodies at the merge valve

**Date:** 2026-10-07 (revised same day after the ADR-097 challenge: template + hook, not a vendored organ)
**Status:** specced — ADR-097 accepted; implementation is P3 (S)
**Task:** P3 · ADR-097 D3 · research 2026-10-07 §2.2

## Problem

PRs are the human merge valve, and the valve receives no brief. `/brana:ship` opens the
dev→main PR with `--body "$(git log --oneline main..dev | head -40)"`
(`system/skills/ship/SKILL.md`, Part A). The autonomous runner opens PRs with a canned
one-line body (`system/scripts/autonomous-runner.sh:439`) from an executor whose allowed tools
exclude Skill. `pr-reviewer` reviews the diff with no statement of what the author claims, what
evidence backs it, or how reversible the merge is. The result is the failure Pocock names:
"without asking for hard evidence it's very easy for agents to say 'yeah that probably works
cuz I've read the code.'"

Pocock's `pr` skill is a template with three mandatory sections and a short guide for each.

## Decision Record (frozen 2026-10-07, ADR-097 D3)

**Context:** both real PR paths in brana are scripted bash blocks a skill cannot run inside; a
verbatim model-invoked upstream skill symlinked into `.claude/skills/` would carry its full
description and outrank any thin adapter, skipping the never-invent-evidence guard.
**Decision:** adopt the *shape* as a template file plus a deterministic hook: a template under
`system/skills/ship/`, `--body-file` in ship Part A, the same template rendered by the runner,
and a `PreToolUse` hook on `gh pr create` that checks the three headings. Upstream's `pr`
SKILL.md is kept as a pinned reference copy (provenance: Dex Horthy's `show-me` via Pocock),
not symlinked as a skill.
**Consequences:** every PR body on every path carries evidence and a reversibility call, or
the hook stops the create. No new model-invoked skill, so no description-byte cost against
`context-budget.sh`. Merge Danger informs the human and can only tighten (ADR-097 D3); it is
not an input to any autonomy rung.

## Design

### The shape (from upstream, unchanged)

```
## Summary        the smallest visual that makes the key point clear:
                  pseudocode · call tree · component tree · shallow file
                  tree · Mermaid · or a diff of one of those
## Evidence       Before: <output / failing run / screenshot>
                  After:  <output / passing run / screenshot>
                  screenshots S-tier · execution output A-tier
                  "Evidence: none — not run" is allowed; invented runs are not
## Merge Danger   Door: one-way | two-way | unknown
                  Blast radius: <one word> + ramifications
                  unknown or one-way → human reads before merge
```

### Files

```
system/skills/ship/pr-body-template.md       the template, with the per-section guidance
                                              condensed to one line each
system/hooks/pr-body-shape.sh                 PreToolUse on Bash matching `gh pr create`:
                                              resolves --body / --body-file, asserts the
                                              three headings in order, a Door value in
                                              {one-way, two-way, unknown}, non-empty radius;
                                              exit 2 with the missing heading named
.agents/reference/pr-SKILL.md                 pinned verbatim copy of upstream pr/SKILL.md
                                              at the band pin, for provenance only (not a
                                              skill, not symlinked, listed in skills-lock.json
                                              as sourceType reference)
```

### Callers

| Path | Change |
|---|---|
| `/brana:ship` Part A | before the scripted block, the session fills the template from `main..dev` (git log goes *under* Summary as the visual when nothing better fits) into a temp file; the block uses `--body-file`; on a re-run after red CI the body is regenerated and the open PR is edited with `gh pr edit --body-file` so no stale body survives |
| runner `gh pr create` (autonomous-runner.sh:439) | renders the same template from the task packet: Summary = task subject + files changed, Evidence = the gate's inspection output, Door/radius = `unknown` (the executor never rates its own diff) |
| `build/phases/close.md` step 10 | when the human chooses a PR instead of the local merge, the same template fills from the branch; the local `--no-ff` path is unchanged |
| `pr-reviewer` | reads `## Merge Danger` as input; disagreement with the door or radius is reported under its own heading, never silently re-rated; `unknown` is a review flag, not a defect |

### Attribution hook interaction

`no-attribution-commit.sh` inspects `gh pr create` command text. A `--body-file` body is not
in the command text, so the shape hook reads the file and re-runs the attribution check on its
contents, keeping the trailer ban enforced on file-passed bodies.

## Tests (write first)

- `system/hooks/tests/test-pr-body-shape.sh` — fixtures: valid body passes; missing heading,
  bad Door value, empty radius each exit 2 naming the defect; `--body` and `--body-file` both
  resolved; attribution trailer inside a body file is caught. Red first against today's
  `git log` body.
- Ship dry run against a throwaway branch pair produces a body that passes the hook (recorded
  in the task notes).
- Runner: a fixture task packet renders a template body that passes the hook.

## Acceptance criteria (P3)

1. Template file exists; ship Part A uses `--body-file`; re-runs edit the open PR's body.
2. Runner PRs render the template with `Door: unknown`.
3. `pr-body-shape.sh` wired as PreToolUse; its test suite is green; attribution check holds
   for body files.
4. `pr-reviewer.md` states it reads Merge Danger and how it reports disagreement.
5. Docs: `docs/guide/workflows/branching.md` or the ship guide gains the three-section shape;
   this spec's status flips to implemented.
