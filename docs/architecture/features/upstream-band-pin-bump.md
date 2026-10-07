# Feature: upstream band pin bump — the manual pump, v1.2.3 → v1.3.1

**Date:** 2026-10-07
**Status:** specced — ADR-097 accepted; implementation is P1 (S, chore), gated on P0 (adapter call-path fix)
**Task:** P1 (not yet created) · ADR-097 D1/D2 · ADR-084 §1 (pump), §7 (proxies), §7a (hash script)

## Problem

Three vendored organs (`diagnosing-bugs`, `code-review`, `wizard`) are pinned `v1.2.3`.
Upstream is `v1.3.1`. Two of the three changed. ADR-084 named a pump
(`reconcile --scope pocock-sync`) and a gauge but deliberately did not build them; §7a said
the bump is a human valve. There is no written procedure for running that valve, so the first
real bump would be improvised. This spec is the procedure, run by hand, and the same procedure
later admits new organs (`tdd`, `pr`) at the same pin.

## Decision Record (frozen 2026-10-07, pending ADR-097)

**Context:** ADR-084 §2 file-copy vendoring; `skills-lock.json` with `pinnedRef`,
`computedHash`, `files[]`; `skills-lock-hash.sh` is the only source of truth for the hash.
**Decision:** one procedure, one **default** band pin with a dated per-organ hold (ADR-097 D1,
amending ADR-084 §1), all organs bumped in one task; per-organ proxies recorded against the
pre-registered definition of "rework" (a change to the adapter's remap table or to a step
heading its `redirect-check.md` names, excluding `vendored_from:`/pin-text updates);
instruments stay unbuilt until the third bump.
**Precondition (P0):** the adapters are reachable. `disable-model-invocation: true` blocks the
Skill tool (ADR-076 verified finding #3); it is removed from `diagnose-hard-bug` and
`two-axis-review`, every adapter appends a call-site record to
`~/.claude/run-state/pocock-<organ>.jsonl`, and one resolution test per organ exists, before
this bump runs. Until those records exist the invocation proxy is unreadable, not zero.
**Consequences:** the bump is a reviewable diff per organ plus a lock-file change; nothing
auto-updates.

## Procedure (the pump, by hand)

```
for each organ in the band                         (today: 3; after P2/P3: 5)
  ┌─────────────────────────────────────────────────────────────────────┐
  │ 1  fetch upstream SKILL.md + shipped sub-files at the target tag    │
  │    gh api repos/mattpocock/skills/contents/<skillPath>?ref=v1.3.1   │
  │ 2  diff against .agents/skills/<organ>/  — read it, every line      │
  │ 3  re-verify the adapter's redirect-check.md:                       │
  │      every cross-skill reference in the new SKILL.md is listed;    │
  │      every step heading the adapter's remap names still exists     │
  │      (each organ's spec lists its load-bearing headings)           │
  │ 4  copy the new files in verbatim; point the adapter at the shared │
  │    GLOSSARY remap note if the diff introduced GLOSSARY.md (D7);    │
  │    update `vendored_from:` and any pin text in the adapter header  │
  │ 5  skills-lock.json: pinnedRef → v1.3.1;                             │
  │    computedHash + files[] ← system/scripts/skills-lock-hash.sh      │
  │ 6  run test-skills-lock-hash.sh, the organ's heading-presence +    │
  │    redirect test and the band pin-equality test (CREATED by this   │
  │    bump — none exists today, whatever earlier drafts said)         │
  │ 7  record the per-organ proxies (ADR-084 §7) in the task notes:     │
  │      adapter_churn since last pin · invocations since last pin ·    │
  │      upstream_delta (lines changed, headings renamed)               │
  └─────────────────────────────────────────────────────────────────────┘
then: one commit per organ ("chore(band): bump <organ> v1.2.3 → v1.3.1"),
      one PR, validate green, human merges.
```

Kill read (ADR-097 D1): an organ whose adapter needs rework at step 3/4 gets a **dated hold**
(`held_at: v1.2.3`, `hold_until`, reason) in its lock entry and the bump proceeds for the
rest; a hold that expires without a bump reverts that organ to port-and-own in its own task.

### Expected diffs at this bump (known from the 2026-10-07 recheck)

| Organ | Upstream change since v1.2.3 | Adapter impact |
|---|---|---|
| `diagnosing-bugs` | GLOSSARY.md read (d80fa0f4). PR #1209's "prove a forced mutation landed" step is **post-tag** (2026-10-07, on `main` only) and is NOT in v1.3.1 | remap line: CONTEXT.md → GLOSSARY.md → `docs/domain/`; note #1209 ↔ `red-verification.sh` for the next tag |
| `code-review` | searches for standards files; sub-agents foregrounded; tracker doc read (#1208) | `two-axis-review` already points Standards at `system/rules/*.md`; confirm the new search does not override that; tracker doc → `docs/agents/issue-tracker.md` |
| `wizard` | template.sh readline/.env quoting/symlink/EOF fixes (2026-10-06) | `wizard-scaffold.sh` regenerates from the template — re-run `test-wizard-scaffold.sh` |

## Tests

- `test-skills-lock-hash.sh` (existing, generic) — green after step 5 for every organ.
- Heading-presence + redirect test per organ and a band pin-equality test — **none exists
  today** (challenge finding 8); this bump creates them, red first against the v1.2.3 tree.
- `provisioning-wizard` has no `redirect-check.md` at all today; this bump writes it.
- `test-wizard-scaffold.sh` (existing, 12 cases).

## Acceptance criteria (penciled for P1)

1. All band organs carry `pinnedRef: v1.3.1` (or a dated hold); hashes regenerated by script;
   lock test and the new pin-equality test green; adapters' `vendored_from:` updated.
2. Each adapter's `redirect-check.md` re-verified and dated in its header.
3. Per-organ proxies recorded in the task notes.
4. The vendored `diagnosing-bugs` adapter's remap names `docs/domain/` where it named
   CONTEXT.md.
