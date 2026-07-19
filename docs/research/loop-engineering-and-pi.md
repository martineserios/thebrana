# Research: loop-engineering (Cobus Greyling) + Pi (pi.dev)

> **Date:** 2026-07-19 · Companion to [agentic-engineering gap analysis](agentic-engineering-2026-gap-analysis.md) and [gentle-ai extraction](gentle-ai-productization-extraction.md). Visual map: see the "Agentic Engineering 2026 — Research Map" artifact.

## loop-engineering — github.com/cobusgreyling/loop-engineering

Framework + npm CLI toolkit for production agent loops. Credibility: Boris Cherny (head of Claude Code) — *"I don't prompt Claude anymore. I have loops running that prompt Claude."*

### The framework
**Six components** (a control system, not a prompt): scheduling/automations · git worktrees · skills (persistent knowledge) · plugins/connectors (act, don't suggest) · sub-agent verifiers (maker/checker split) · durable memory/state (JSON, STATE.md). Inner cycle: Reason → Act → Observe → Repeat.

**Autonomy taxonomy:** L1 report-only → L2 assisted (human approves) → L3 unattended. Phased rollout, never start at L3.

**Stop conditions (all encoded, none optional):** goal achieved (human-verified) · iteration cap · non-recoverable error → escalate · cost threshold · state drift. Principle: *"done" is unverified until a human confirms.*

**Named failure modes:** infinite loops (no exit/cost guard) · **comprehension debt** (speed masks understanding; engineers lose judgment) · token economics (cadence × sub-agents multiplies cost; triage must stay cheap) · self-grading · state drift.

**CLI tools:** `loop-init` (scaffold + readiness score), `loop-audit`, `loop-cost` (pre-deploy token estimate), `loop-sync` (state-drift detection), `loop-context`, `loop-worktree`.

**7 production patterns:** Daily Triage, PR Babysitter, CI Sweeper, Dependency Sweeper, Changelog Drafter, Post-Merge Cleanup, Issue Triage.

### Brana mapping
- Validates existing choices: worktree discipline, skills-as-persistent-knowledge, tasks.json/session-state as durable state, challenger as checker. Brana independently converged on ~5 of 6 components.
- **L1→L2→L3 taxonomy** is cleaner than ADR-059's autonomy framing — adopt the labels; classify every brana cron/loop by level.
- **Missing in brana:** per-loop cost budgets + iteration caps as *encoded* stop conditions (goal-completion.sh checks goals, not cost/iterations); state-drift detection between runs (`loop-sync` equivalent); the maker/checker split in build-loop (worker still self-grades — same finding as the gap analysis' Haiku-verifier item).
- **Comprehension debt** is a genuinely new concept for brana's vocabulary — a risk register item for the autonomous runner.
- The 7 patterns are a menu for brana Routines migration (PR Babysitter ≈ post-pr-review hook, CI Sweeper, Issue Triage ≈ inbox/feed processing).

## Pi — pi.dev

Minimal open-source coding agent by Mario Zechner (badlogic/libGDX; Earendil Inc., co-founded by Armin Ronacher). MIT. **62K+ GitHub stars by June 2026.**

### The model
- **Primitives-over-features:** 4 built-in tools (read/bash/edit/write), ~1k-token system prompt. Deliberately *omits* sub-agents, plan mode, MCP, permission popups — users build these as extensions.
- **Package model:** extensions ship as npm/git packages — TypeScript extensions (in-process, full harness API), skills (progressive disclosure), prompt templates, themes. Semver via npm.
- Tree-structured branching sessions instead of persistent memory; 15+ providers with mid-session switching; TUI/JSON/RPC/SDK modes.
- **gentle-pi** (same author as gentle-ai) retrofits the full SDD/TDD/verification lifecycle *as a Pi package* — proof that opinionated harnesses can be distribution artifacts on a minimal core.

### Brana mapping — the strategic signal
Pi + gentle-pi + gentle-ai converge on one lesson: **the winning shape is platform + opinionated layers as packages.** This is exactly t-407's "process plugins on the Brana OS layer" — independently validated at 62K-star scale. Implications for the public path (t-2090):
1. Public brana should split **core** (CLI, lifecycle verbs, state manifest — the gentle-ai extraction items) from **process packs** (build/backlog/close, venture ops) shipped as installable layers.
2. Claude Code plugins are brana's "npm for harness packages" — the plugin packaging bet (t-232) was the right call; process packs = additional plugins, not a monolith.
3. Pi's radical minimalism is the counter-position to brana's depth; don't copy it — but its *packaging boundary* (core vs. opinion) is the industry-consensus line to cut on.
