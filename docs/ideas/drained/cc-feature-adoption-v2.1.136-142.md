---
title: CC Feature Adoption — v2.1.136–v2.1.142
status: draft
created: 2026-05-15
---

# CC Feature Adoption — v2.1.136–v2.1.142

> Brainstormed 2026-05-15. Work in progress.

## Problem

Claude Code v2.1.136–v2.1.142 shipped 10+ features with direct brana impact. None are currently wired into the thebrana system. No systematic intake process exists — features go dormant unless manually discovered and adopted.

## Key design decisions from brainstorm

### TDD gate stays hard-stop

`continueOnBlock` is for advisory gates, not enforcement gates. The TDD gate's value is in blocking — auto-recovery would defeat the purpose by removing the human signal.

**Taxonomy:**
- Enforcement gates (TDD, main-guard, branch-verify, worktree-gate) → hard-stop, no `continueOnBlock`
- Advisory gates (feedback-gate, post-plan-challenge, post-tasks-validate) → `continueOnBlock` makes sense

This should be encoded in the hook architecture docs as a design principle.

### Auto-goal requires `acceptance_criteria` in backlog schema first

The marathon approach: add `acceptance_criteria` as a structured field to the backlog schema. `/brana:build` reads it and generates a deterministic `/goal`. Without structured criteria, `/goal` is just a prompt modifier — Claude might trivially self-terminate.

### MCP Tool Search — test before tuning

Empirical test first (1 session, 5 skill flows, measure ruflo invocation drop), then write server `instructions` informed by data, then `alwaysLoad: true` on the right server. Don't tune without a baseline.

> **2026-06-02 errata:** `alwaysLoad` is a **server-level boolean** (all tools or none) — not a per-tool array. Set `alwaysLoad: true` on the brana server (~16 tools, all session-relevant, low context cost). Do NOT set it on ruflo (200+ tools — would blow context budget). Spike t-1773 validated this. Implemented in t-1777.

### cc-changelog-check is dormant infrastructure

The script already works. session-start.sh already reads the report. The only missing piece: wire `cc-changelog-check.sh` as an async SessionStart hook. 1-line change, highest ROI in the list.

## Proposed solution

Tiered adoption plan across five clusters, ordered by effort and dependencies.

### Tier 0 — Activate dormant (< 1 hour each)

**E4: Wire cc-changelog-check as async SessionStart hook**
- Add to `hooks.json` SessionStart with `async: true`
- Every session: version check runs in background, report file created if new version
- session-start.sh already reads the report — no other changes needed
- Activates always-on CC feature tracking at zero ongoing cost

**A5: Wire ConfigChange hook for ANTHROPIC_BASE_URL guard**
- `config-change-guard.sh` already exists — move to `ConfigChange` event
- Wire in `~/.claude/settings.json` (user-level, not project)
- Closes CVE-2026-21852 properly

### Tier 1 — Config pass (< 2 hours total)

**A2: hard_deny manifest**
- Move all "never-ever" rules from sentinel workarounds to `autoMode.hard_deny`
- Create a canonical manifest file — auditable, diffable, reviewable
- Replace hook-based blocking for permanent denies

**A3: Exec-form args migration**
- Batch migrate all hook commands to `"args": ["bash", "script.sh"]` form
- No shell, no quoting bugs, reduced injection surface
- One commit, all hooks

**A4: `if` pre-filters on hot-path hooks**
- Add `"if": "Bash(git *)"` to branch-verify.sh and commit-msg-verify.sh entries
- Measurable latency reduction: hooks only spawn on matching commands

**D3: `MCP_CONNECTION_NONBLOCKING=1`**
- Set in session-start or `.mcp.json` env block
- Session startup no longer blocks on ruflo startup
- Tradeoff: ruflo tools unavailable for ~2s at session start (fine for most sessions)

### Tier 2 — Design + build (1 day each)

**A1 (revised): `continueOnBlock` on advisory gates**
- Audit advisory gates: feedback-gate, post-plan-challenge, post-tasks-validate
- Add `continueOnBlock: true` to these entries
- Write test assertions for the new behavior (wave transition audit required)
- Enforcement gates untouched

**C1+C2: terminalSequence ambient awareness**
- session-end hook emits window title: `brana: session saved ✓`
- Stop hook emits context window % and active task in terminal title
- Background build completion: `brana: t-XXXX done`
- No conversation pollution — pure ambient signal

**D1+D2: MCP Tool Search + server instructions**
- First: empirical test (1 hour — enable Tool Search, run 5 skill flows, measure)
- Then: write ruflo server `instructions` field (2KB) based on test data
- Then: `alwaysLoad: true` on the **brana server** (server-level boolean — all 16 tools or none; brana chosen because all its tools are session-relevant and schema is small; ruflo stays deferred — 200+ tools) ✓ done in t-1777
- Also: consume `CLAUDE_PROJECT_DIR` in brana-mcp and ruflo (1-line change each)

### Tier 3 — Foundation work (1+ week)

**B2 + E2: Auto-goal from acceptance criteria**
- Step 1: Add `acceptance_criteria` field to backlog schema (Rust CLI update)
- Step 2: `brana backlog add/set` supports the new field
- Step 3: `/brana:build` reads `acceptance_criteria` → generates `/goal` string
- Step 4: Stop hook validates completion against criteria
- Step 5: Task auto-marked done on successful /goal exit
- This closes the full loop: backlog → goal → build → validate → done

**E1: MCP Resources as spec anchors**
- brana-mcp exposes dimension docs as resources
- `@brana:dimension://55-vercel-platform` injects doc as attachment mid-conversation
- Replaces "grep the knowledge base" with direct spec injection

## Engineering disciplines

- **DDD:** ADR needed for `acceptance_criteria` schema addition (schema-level decision) and for `continueOnBlock` gate taxonomy (enforcement vs advisory)
- **TDD:** Hook behavior tests need audit before any wave transitions; backlog schema changes need enum validation tests across 3 write paths
- **SDD:** hooks.md needs gate taxonomy section; backlog schema docs need `acceptance_criteria` field; 09-native-features.md already updated with new primitives
- **Docs:** `docs/architecture/hooks.md` — enforcement vs advisory taxonomy; `docs/reference/hooks.md` — auto-generated, fix upstream

## Risks and mitigations

| Risk | Mitigation |
|------|-----------|
| `/goal` trivial self-termination | Requires structured `acceptance_criteria` — schema first, `/goal` after |
| MCP Tool Search degrades ruflo reliability | Empirical test before enabling; `alwaysLoad: true` on brana server as fallback (server-level, not per-tool) |
| `continueOnBlock` on wrong gates makes enforcement unpredictable | Strict taxonomy: enforcement=hard-stop, advisory=continueOnBlock |
| exec-form migration breaks hooks that need shell features | Audit each hook — only migrate those that don't use pipes/env expansion |

## Next steps

1. Wire `cc-changelog-check.sh` as async SessionStart hook (Tier 0, 30 min)
2. Wire ConfigChange for ANTHROPIC_BASE_URL guard (Tier 0, 30 min)
3. Build `hard_deny` manifest + exec-form migration (Tier 1, 2 hours)
4. MCP Tool Search empirical test (Tier 2 prerequisite, 1 hour)
5. ADR for `acceptance_criteria` schema + continueOnBlock gate taxonomy (Tier 3 prerequisite)
