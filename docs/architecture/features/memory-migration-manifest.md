# Memory Migration Manifest — Phase A

**Task:** t-1248/t-1249/t-1250  
**Date:** 2026-04-14  
**Status:** Awaiting human review before any migration  
**Total feedback_*.md files:** 119  

---

## Summary

| Category | Count | Action |
|----------|-------|--------|
| Already indexed in MEMORY.md | 93 | Keep — no action needed |
| Not indexed — proposed migration | 26 | See below — human approves per row |

---

## Already Indexed (93 files) — No Action

These files are referenced by MEMORY.md and serve as topic files. No migration needed.
They will be archived passively via `sweep-feedback-files.sh` when atime > 90 days.

---

## Not Indexed (26 files) — Proposed Actions

Legend: ✅ approve | ❌ reject (keep as-is) | 🔄 override (write desired type)

### Rules — propose drafting into system/rules/ (human gate)

| File | Proposed Rule | Approve? |
|------|--------------|---------|
| `feedback_always-use-build-framework.md` | "Always start work via `/brana:backlog start` → `/brana:build`. Never skip the framework." | |
| `feedback_rules-over-hooks-for-gates.md` | "Prefer rules over hooks for behavioral constraints — rules are lighter (no per-event overhead, no context pollution)." | |
| `feedback_ddd-sdd-tdd-gate-assessment.md` | "Always assess which DDD/SDD/TDD lifecycle steps apply before starting a task — even S-effort fixes." | |
| `feedback_phantom-dependency-gate.md` | "Never build a skill that references a non-existent doc in its LOAD step — create the skeleton first." | |
| `feedback_specify-check-ids.md` | "SPECIFY phase must read tasks.json for the next available ID before proposing task trees." | |

### Patterns — propose appending to ~/.claude/memory/patterns.md

| File | Proposed Pattern Title | Approve? |
|------|----------------------|---------|
| `feedback_awk-field-access-functions.md` | `awk-field-access-functions` | |
| `feedback_bash-stderr-separation.md` | `bash-stderr-separation` | |
| `feedback_batch-cleanup-pattern.md` | `batch-cleanup-pattern` | |
| `feedback_challenge-before-build.md` | `challenge-before-build` — run /brana:challenge before coding; avoids stale-premise rework | |
| `feedback_challenger-before-code.md` | `challenger-before-code` — run /brana:challenge before any new behavioral mechanism | |
| `feedback_challenger-double-review.md` | `challenger-double-review` — challenge at plan AND feature brief level | |
| `feedback_large-skill-edits.md` | `large-skill-write-not-edit` — use Write (not Edit) for structural SKILL.md changes >200 lines | |
| `feedback_mermaid-pdf-pipeline.md` | `mermaid-pdf-two-step` — mmdc then md-to-pdf from same directory | |
| `feedback_persist-signals-at-tier-transition.md` | `tier-transition-signal-persistence` | |
| `feedback_procedure-edits-flow-fast.md` | `procedure-edits-flow-fast` — markdown changes 5-6x faster than code; plan session scope accordingly | |
| `feedback_scope-before-effort.md` | `scope-before-effort` — stale-ref tasks may be partially resolved; scope first | |
| `feedback_set-u-optional-deps.md` | `set-u-optional-deps` | |
| `feedback_shell-json-via-python.md` | `shell-json-via-python` | |
| `feedback_subagent-worktree-sandbox.md` | `subagent-worktree-sandbox` | |
| `feedback_worktree-agent-bootstrap.md` | `worktree-agent-bootstrap` | |
| `feedback_worktree-isolation-filesystem.md` | `worktree-isolation-filesystem` | |

### Knowledge — propose appending to ~/.claude/memory/knowledge-staging.md

| File | Proposed Claim | Approve? |
|------|--------------|---------|
| `feedback_cli-memory-list-broken.md` | CC CLI `memory list` broken — use grep on MEMORY.md instead | |
| `feedback_cli-migration-invalidates-hooks.md` | CLI migration (Rust rename) invalidates hook paths — grep sibling hooks after each CLI rename | |
| `feedback_deferred-not-solved.md` | "Deferred" ≠ "solved" — unconfigured MCP bridges must not count as coverage in gap analysis | |
| `feedback_ruflo-cwd-root-cause.md` | Ruflo MCP reads `.swarm/` from `process.cwd()` — global config without cwd causes wrong DB path | |
| `feedback_timeout-kills-mcp-handshake.md` | MCP handshake timeout kills server before session established — increase timeout or use wrapper | |

---

## Instructions for Human Review

1. Mark each row ✅ / ❌ / 🔄
2. For Rules: you place the file in `system/rules/` — Claude will display the draft, not write it
3. For Patterns/Knowledge: Claude will append to the destination file after approval
4. Reject (❌) any classification you disagree with — Claude will re-classify
5. After approval, run `/brana:backlog start t-1254` through `t-1258` for each type's migration

---

## Changelog

- 2026-04-14: Initial manifest produced by Phase A agent pass (t-1249/t-1250)
