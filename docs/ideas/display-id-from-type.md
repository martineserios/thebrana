---
title: Display-layer task ID prefixes (derive from live type)
status: idea
created: 2026-06-18
relates_to: t-2133
---

# Display-layer task ID prefixes

> Brainstormed 2026-06-18. Status: idea.

> **⚠ Supersedes t-2133's current scope.** t-2133 is filed as "make `next_id()` type-aware"
> — the design this doc *rejects* (it encodes mutable `type` into an immutable ID). The
> task's stored context still describes that approach. When picked up, this doc is the
> source of truth: re-scope t-2133 to Direction A (`display_id` + prefix-agnostic resolver)
> and add an ADR recording why type-in-ID was rejected.

## Problem

The documented task-ID convention (`in-`/`ph-`/`ms-`/`t-`/`st-` per `task_type`) is not
honored by the ID generator. `brana-core::tasks::next_id()` hardcodes `t-` and ignores
`task_type` entirely; both the MCP `backlog_add` tool and the CLI call it the same way. So
milestones/phases created through either path get `t-NNNN` instead of `ms-`/`ph-`.

The naive fix — "make `next_id()` type-aware" — encodes a **mutable** field (`type`, which
changes on promotion/demotion/reparenting) into the **immutable** ID. Combined with the
hard constraint of never renumbering existing IDs, that guarantees the prefix will
eventually *lie*: `ms-001` could become a regular task and the prefix can't be corrected.
A lying convention is worse than none — it misleads anyone scanning the raw file.

## Proposed solution (Direction A — prefix as display concern)

Stop storing the prefix. IDs stay `t-NNNN` forever (immutable, type-free, zero migration).
Derive the prefix from the **live `type` field** wherever a task is rendered.

- Add `display_id(task) -> String` in `brana-core` that maps the current `type` to its
  prefix and combines it with the numeric suffix of the stored ID
  (`t-2134` + `type=milestone` → `ms-2134`).
- Call it from CLI render paths: `render_tree_node` (backlog.rs:779), `cmd_roadmap`,
  `cmd_tree`, and any list/get display.
- `next_id()` is **untouched** — the global-vs-per-type counter fork disappears entirely
  (it was an artifact of storing the prefix).
- The raw `tasks.json` truth is the adjacent `"type"` field, which is always correct
  because it is the single source the display derives from.

### Core requirement: prefix-agnostic lookup

Display IDs are decoupled from stored IDs, so **every ID-accepting code path must resolve
by numeric suffix and ignore the prefix**. `ms-2134`, `t-2134`, and bare `2134` all resolve
to the same task. This is not a mitigation — it is what keeps the decoupling safe:

- A user/commit/doc referencing the *displayed* `ms-2134` must find the *stored* `t-2134`.
- Resolution rule: strip any leading `<prefix>-`, match on the numeric suffix.
- Applies to `backlog get`, `set`, `start`, `tree <id>`, `parent`/`blocked_by` resolution,
  and the MCP equivalents — one shared resolver in `brana-core`.
- Existing hand-assigned prefixed IDs (`ph-004`, `ms-010`) continue to resolve unchanged.

### Why A over the alternatives

| Criterion | A — display | B — store prefix in ID | Hybrid |
|---|---|---|---|
| Never lies | ✅ single source (`type`) | ❌ prefix drifts | ⚠️ two signals disagree |
| No renumbering | ✅ | ✅ | ✅ |
| Single shared code path | ✅ `next_id()` trivial + 1 helper | ⚠️ `next_id()` + counter fork | ❌ both |
| Raw-file readability | ⚠️ prefix not on ID; `type` adjacent | ✅ prefix on ID | ✅ |
| Effort | ✅ low | ⚠️ medium | ❌ highest |
| Reversible | ✅ trivial | ❌ minted IDs permanent | ❌ |

## Research findings

- `next_id()` at `brana-core/src/tasks.rs:578`: `format!("t-{}", max+1)`, global counter,
  no `task_type` parameter. Test at line 2069 encodes the bug (`ph-001` + `t-10` → `t-11`).
- Both callers identical: MCP `backlog_add.rs:73`, CLI `backlog.rs:583`.
- Prefix is purely cosmetic today — filtering/tree/roadmap key off the `type` field and
  `parent` pointer, never the ID string. Existing `in-`/`ph-`/`ms-` IDs were hand-assigned.
- Render seam already exists: `render_tree_node` (backlog.rs:779).

## Risks

- **Raw-file scan loses the at-a-glance prefix** (pre-mortem top risk). Mitigation: rendered
  output (`tree`/`roadmap`/`ls`) always shows the correct prefix; a `jq` view can prepend it
  too. The "orient within hierarchy" job moves to rendered output, where it's always truthful.
- **Render seams missed** — a code path that prints a bare stored ID looks inconsistent.
  Mitigation: grep for ID-printing sites; route all through `display_id`.
- **Lookup seams missed** — a displayed `ms-2134` that some path can't resolve is a broken
  reference. Mitigation: the prefix-agnostic resolver above is a *core requirement*, not
  optional; sweep all ID-accepting call sites in the same change.

## Next steps

1. Write an ADR recording the decision: prefix is a display concern derived from live type
   (rejects type-in-ID for the immutability/lying reason).
2. Revise t-2133 scope from "fix next_id()" to "add display_id() + route render paths".
3. TDD: tests for `display_id` across all types incl. type-change (no stale prefix).
4. Implement helper + wire render paths; update the misleading `test_next_id` comment.
