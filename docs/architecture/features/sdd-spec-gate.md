---
status: shipped
task: t-2117
date: 2026-06-15
depends_on:
  - docs/architecture/features/t-601-tdd-gate.md
  - docs/reflections/32-lifecycle.md
  - docs/ideas/ddd-sdd-lifecycle-artifacts.md
---

# Feature: SDD Spec Gate — Feature Spec Template + Advisory Gate for M+ Tasks

## Problem

`docs/domain/` has only MODEL-001 after months of work. The spec enforcement infrastructure
is underdeveloped: no quality bar on behavioral content, no gate requiring spec files for M+
tasks, and no extraction pipeline from feature specs to domain model docs.

The 61 existing `docs/architecture/features/*.md` files prove the convention works, but
only at the "file must exist" level. The gaps are:

1. No `## Behavior` or `## Edge Cases` sections in the template → thin specs pass gate
2. Gate passes on any `docs/` commit, not specifically a feature spec file → too broad
3. No extraction pipeline from spec content to `docs/domain/MODEL-NNN-*.md`

**The gap is enforcement quality and extraction — not a missing artifact type.**

## Decision Record (frozen 2026-06-15)

> Do not modify after acceptance.

**Context:** Three location options were evaluated:
- `docs/specs/t-NNN-slug.md` (new directory)
- `docs/architecture/features/{slug}.md` (existing convention, 61 files)
- Enforcement at a different location

**Decision:** Use `docs/architecture/features/{slug}.md` — extend the existing convention,
do not introduce a third competing directory alongside `docs/architecture/features/` and
`docs/architecture/decisions/`. Gate checks for file existence in this directory.

**Consequences:**
- All future feature specs land in `docs/architecture/features/`
- Existing 61 specs satisfy the gate via existing `## Scope` + `## Constraints` sections (no backfill required)
- New specs must include `## Behavior` (≥3 sentences) + `## Edge Cases` (≥2 items)

## Constraints

- Existing 61 specs must NOT be forced to add `## Behavior` + `## Edge Cases` — bridge solution required
- Gate starts advisory; hardens only after empirical compliance data (5 M+ tasks, 6-week deadline)
- S-effort tasks exempt from gate — cognitive overhead not justified at that scale
- Extraction pipeline (Phase 2) depends on Phase 1 shipping and stabilizing first

## Scope (v1 — Phase 1 only)

**In scope:**
1. Update `system/skills/build/phases/specify.md` template: add `## Behavior` + `## Edge Cases` sections
2. Advisory PreToolUse warn on M+ branches without a `docs/architecture/features/` spec file
3. Gate bridge: existing specs satisfy gate via `## Scope` or `## Constraints` (either is sufficient)
4. Pilot on 5 M+ tasks; apply hardening criteria at 6 weeks

**Out of scope (Phase 2+):**
- Nightly cron extraction to `docs/domain/.extraction-staging.json` (t-2119)
- Session-start hook surfacing candidate count (t-2120)
- Queue hygiene (t-2121)
- Domain index auto-generation (t-2122)
- Sitrep surface (t-2123)

## Design

### Template change (bridge strategy)

Two-track approach:
- **New specs** get full template: `## Behavior` (≥3 sentences) + `## Edge Cases` (≥2 items)
  placed between `## Problem` and `## Decision Record`
- **Existing specs** (61 files): satisfy gate via `## Scope` **or** `## Constraints` — already
  present in all specs written to the current template; no forced backfill

Gate check logic:
```
# Spec file exists?
spec_file = docs/architecture/features/{slug}.md
if not exists(spec_file): WARN (advisory)

# Content quality check (new spec only — skip if file predates this feature)
if new_file and not has_section("## Behavior"): WARN
if new_file and not has_section("## Edge Cases"): WARN
```

### Gate implementation

**Location:** `system/hooks/pre-tool-use/` (PreToolUse hook, same pattern as t-601-tdd-gate)

**Trigger:** First `Write|Edit` call on `system/`, `src/`, `tests/` paths on an M+ effort branch.
Gate fires **once per branch** via a sentinel file — no advisory fatigue (M4 resolution).

**Gate logic:**
```bash
# 0. Sentinel: only fire once per branch
sentinel=".git/brana-spec-gate-checked"
[[ -f "$sentinel" ]] && exit 0

# 1. Task ID — layered fallback (C1 resolution)
task_id=""
goal_file="$HOME/.claude/run-state/active-goal.json"
if [[ -f "$goal_file" ]]; then
    task_id=$(jq -r '.task_id // empty' "$goal_file" 2>/dev/null)
fi
if [[ -z "$task_id" ]]; then
    task_id=$(git branch --show-current 2>/dev/null | grep -oP 't-\d+' | head -1)
fi
if [[ -z "$task_id" ]]; then
    exit 0  # no task context (CI, detached HEAD, main) — silent skip
fi

# 2. Check effort — S/XS exempt
effort=$(brana backlog get "$task_id" --field effort 2>/dev/null | tr -d '"')
if [[ ! "$effort" =~ ^(M|L|XL)$ ]]; then
    touch "$sentinel" && exit 0
fi

# 3. Check for spec file added on this branch (C2 resolution: provenance-based, no frontmatter)
base=$(git merge-base HEAD main 2>/dev/null || git merge-base HEAD master 2>/dev/null)
if [[ -n "$base" ]]; then
    spec=$(git diff --name-only "$base" HEAD | grep "^docs/architecture/features/.*\.md$" | head -1)
    if [[ -z "$spec" ]]; then
        echo "⚠ Advisory: No spec file in docs/architecture/features/ for $task_id (M+ effort)."
        echo "  Consider creating: docs/architecture/features/{slug}.md"
    fi
fi

# Gate always exits 0 — advisory only, never blocks
touch "$sentinel"
exit 0
```

**Gate checks existence only — not content (M3 resolution).**
Quality (`## Behavior`, `## Edge Cases`) is enforced by the updated template and caught in
review/challenger — not by the hook. The 61 existing specs are not subject to content checks;
new specs follow the new template by convention.

**Hardening: manual, judgment-based (M5 resolution).**
After 5+ M+ tasks, review: "did this gate produce specs that mattered?" If yes → harden to
blocking via hook config. No automated threshold. Advisory → blocking is a judgment call.

### Spec file location in `/brana:build` SPECIFY step

Update `system/skills/build/phases/specify.md` line ~69:
- Current: `docs/features/{slug}.md` or `docs/architecture/features/{slug}.md`
- Change: canonicalize to `docs/architecture/features/{slug}.md` — remove the fork

## Boundaries

| Always | Ask First | Never |
|--------|-----------|-------|
| Checks `docs/architecture/features/` for spec file | Hardens gate to blocking (requires 6-week pilot data) | Backfills existing 61 specs |
| Warns advisory for M+ branches missing a spec | Creates spec file automatically | Blocks S-effort tasks |
| Updates specify.md template | Changes existing gate logic | Modifies docs/domain/ directly |

## Testing Strategy

- **Unit:** test gate script with M/S effort branches, with/without spec file present → exit code + message
- **Integration:** run PreToolUse hook against a real branch with a real task; verify advisory message appears
- **E2E:** pilot on 5 actual M+ tasks — track whether spec files are created
- **Mock policy:** real brana backlog CLI in tests (no mock); stub git branch output via env var

## Documentation Plan

- [x] **Feature spec** — this file (`docs/architecture/features/sdd-spec-gate.md`)
- [x] **Template update** — `system/skills/build/phases/specify.md`: add `## Behavior` + `## Edge Cases` to template
- [x] **Hook** — `system/hooks/spec-gate.sh`: advisory PreToolUse hook (registered in hooks.json)
- [x] **User-facing note** — one-liner addition to CLAUDE.md: "M+ tasks require a feature spec in `docs/architecture/features/`" (deferred: feedback-gate blocks close-time writes to CLAUDE.md — add via PR)

## Challenger findings

**CRITICAL (resolved):**
- C1: Silent bypass on non-standard branches → layered fallback: active-goal.json → branch regex → silent skip
- C2: grep-based spec matching fragile → provenance-based: `git merge-base` + `git diff --name-only`

**MAJOR (resolved):**
- M3: Bridge grandfathers forever → gate checks existence only, not content; template drives quality
- M4: Advisory fatigue from repeated firing → sentinel file (`.git/brana-spec-gate-checked`), fires once per branch
- M5: Automated hardening criteria unreliable at low volume → manual promotion, judgment-based

**MINOR (accepted):**
- Multi-feature tasks: one spec per task is sufficient
- Permission errors: `git diff` approach robust to missing dirs
- Template update is first build subtask — no ordering risk
