# Branch Prefix Resolution (shared)

Single authority for the `{work-type}` segment of a branch name
(`{epic-slug}/{work-type}/t-{NNN}-{slug}`, CLAUDE.md §Branch naming).

**`task.kind` is authoritative.** It names what the change *does*, which is exactly what
the prefix is for. `task.work_type` is a cognitive-mode label ("this is coding work") and
is deliberately orthogonal — `task-convention.md` states that `kind: refactor` tasks carry
`work_type: implement`, which confirms work_type was never meant to carry change class.

**`work_type` remains a real fallback, not a vestige.** 488 of 2158 tasks (22%) carry
`kind: null`. Demoting work_type entirely would leave a fifth of the backlog with no
prefix source at all, so the fallback runs constantly and is tested as a first-class path.

Used by: `system/skills/backlog/phases/start.md` (branch creation).
Human-readable statement of the same authority: `system/rules/task-convention.md` §Branch.

## Why this exists (t-2494)

Two sources disagreed for the same task: `task-convention.md` keyed on `kind`,
`start.md` keyed on `work_type`. Every `kind:fix` task carrying `work_type:implement`
resolved to `feat/` under one and `fix/` under the other. Three P1/P2 defect branches
(t-2487, t-2478, t-2491) were labelled `feat/` before anyone noticed, and the conflict
was resolved by hand twice. The prefix is the only signal in a branch name distinguishing
a bugfix from a feature, so the disagreement misreported change class to everything that
reads branch names.

<!-- BRANCH-PREFIX-BLOCK -->
```bash
# Resolve the branch work-type segment from a task's kind and work_type.
#
# Contract: always prints exactly one bare prefix — non-empty, no slash, no
# whitespace — and always exits 0. Callers build "{epic}/{prefix}/t-NNN-{slug}",
# so an empty return would silently produce a malformed branch name; unknown
# input degrades to `feat` rather than to "".
#
# Every prefix emitted here must appear in CLAUDE.md §Branch naming's work-type
# list. tests/procedures/test-branch-prefix.sh asserts that cross-file agreement.
resolve_branch_prefix() {
  local kind="${1:-}" work_type="${2:-}"

  # `--field` emits the JSON literal `null` for an absent value; treat it as absent.
  [ "$kind" = "null" ] && kind=""
  [ "$work_type" = "null" ] && work_type=""

  # AUTHORITY: kind first.
  case "$kind" in
    feature)  printf 'feat';     return 0 ;;
    fix)      printf 'fix';      return 0 ;;
    refactor) printf 'refactor'; return 0 ;;
    research) printf 'research'; return 0 ;;
    docs)     printf 'docs';     return 0 ;;
    design)   printf 'design';   return 0 ;;
    test)     printf 'test';     return 0 ;;
    ops)      printf 'chore';    return 0 ;;
  esac

  # FALLBACK: kind absent or unrecognised -> work_type.
  case "$work_type" in
    implement|feat)      printf 'feat'     ;;
    fix)                 printf 'fix'      ;;
    refactor)            printf 'refactor' ;;
    research)            printf 'research' ;;
    docs|document)       printf 'docs'     ;;
    design)              printf 'design'   ;;
    test)                printf 'test'     ;;
    review)              printf 'review'   ;;
    chore|ops|infra|dev) printf 'chore'    ;;
    *)                   printf 'feat'     ;;
  esac
  return 0
}
```
<!-- /BRANCH-PREFIX-BLOCK -->

> The `BRANCH-PREFIX-BLOCK` markers above are load-bearing:
> `tests/procedures/test-branch-prefix.sh` extracts exactly that span and sources it, so
> the test always exercises the shipped function. Do not remove or rename them, and keep
> the fences inside the markers.

## Adding a kind or work_type value

Add the case here, add the prefix to CLAUDE.md §Branch naming if it is new, and add an
assertion to `tests/procedures/test-branch-prefix.sh`. Do not add a mapping to
`task-convention.md` or `start.md` — they defer to this file by design, and restating a
mapping in either is what caused t-2494.
