# Extraction: What gentle-ai Does Well on the Public Path

> **Source:** https://github.com/Gentleman-Programming/gentle-ai (v2.1.8, 2026-07) · **Date:** 2026-07-19
> **Context:** Comparison session — brana's orchestration is more powerful but "scattered and discretionary"; gentle-ai's practices are productized. This doc extracts the productization mechanics relevant to the brana public path ([t-407 Brana OS framework](t-407-claude-systems-marketplace.md), distribution epic t-2090/t-2092/t-2093, [user journey gaps](../architecture/features/user-journey-gap-analysis.md)).

## Corrected core finding

gentle-ai's *runtime* is weaker than brana's. Its trigger rules are rendered markdown injected into agent config files — "nothing pauses the workflow." No hooks-level enforcement, no deterministic orchestration engine, no autonomous loops. Brana's hooks + native Workflow layer is strictly stronger at runtime.

What gentle-ai excels at is the **product pipeline**: one Go binary that renders opinionated practices into per-agent artifacts, with a full managed lifecycle around them. The lesson for the public path is not "adopt their practices" — it's "adopt their *packaging discipline* for practices brana already has."

## The eight extractable mechanisms

### 1. Render from a catalog; never hand-maintain agent config
Core catalog (`internal/catalog/`) + per-agent adapters (`internal/agents/`) render the same practice set into `.claude/CLAUDE.md`, `.cursor/rules/`, `.instructions.md`, etc. Skills/personas ship embedded in the binary (`internal/assets/`).
**Brana mapping:** this is t-407's framework thesis, implemented. The public brana should *generate* deployed rules/config from `system/` definitions rather than copying files — `bootstrap.sh` becomes a renderer with adapters, even if Claude Code is the only adapter at launch.

### 2. Lifecycle verbs are the product spine
`install --dry-run` → `sync` → `doctor` → `upgrade` → `uninstall`, all dry-runnable. Install *merges* configs non-destructively (never overwrites the user's existing setup); `--dry-run` previews detected OS/package-manager/plan before anything mutates.
**Brana gap:** `brana doctor` exists (t-520); installer exists (t-501). Missing: `sync` (re-render managed assets after upgrade), `--dry-run` on everything, `uninstall`.

### 3. Managed-state manifest
`~/.gentle-ai/state.json` records exactly what the tool manages: agent selections, created-vs-modified files. This is what makes uninstall safe ("removes managed config only") and rollback atomic (pre-install existence tracked; created files removed, modified files restored).
**Brana gap:** bootstrap.sh has no memory of what it deployed. A `~/.claude/.brana-manifest.json` would enable safe uninstall/rollback — a hard adoption blocker for strangers ("what if I want it out?").

### 4. Checksum-deduped backups with pinning
Every install/sync/upgrade backs up the target config; skipped if checksum-identical to the latest; 5 unpinned retained, pinned kept forever (TUI toggle).
**Brana gap:** none of this exists. Cheap to build, high trust signal.

### 5. TTY-aware headless mode
TTY → interactive prompts; non-TTY → auto-decline + explicit flags/env vars (`GENTLE_AI_INSTALL_SCOPE`), unknown options rejected, fail-fast on unsupported platforms. Reproducible CI installs by design.
**Brana mapping:** matters for the `claude -p` runner story (ADR-059/060) and for CI adopters.

### 6. Skill registry with deterministic precedence + path-passing injection
`skill-registry refresh` scans project roots then global roots (project wins on collision), writes one index file. The orchestrator matches task context against skill descriptions and passes **exact SKILL.md paths** to sub-agents — full files, not summaries, "preserving original skill intent."
**Brana mapping:** adopt path-passing when spawning agents (currently sub-agents rediscover context); the registry pattern maps to `brana skills` + a rendered index.

### 7. Content-bound review receipts (the trust kernel)
Receipts bind to git **tree hashes** (content-derived, immutable), not refs. Pre-commit/pre-push gates compare receipts against the live tree; release gate revalidates tree + config + manifest + provenance; validation fails closed; concurrent writers rejected via lock + revision guard. Explicit threat model doc: trusts filesystem atomicity + live git state; does **not** trust agent narration or a malicious local actor.
**Brana mapping:** closes the challenge→merge drift gap. Also note: *publishing the threat model is itself a product asset* — legibility as marketing.

### 8. Legible review triage: tiers, not thresholds
Three qualitative risk tiers (trivial / standard / hot-path) with exactly **one** number (>400 authored lines → full 4-lens review). Simple enough for a stranger to predict what the system will do.
**Brana mapping:** brana's 40 hooks are individually sensible but collectively unpredictable to a newcomer. A public brana needs a one-page "what fires when" tier model.

## Meta-patterns worth copying

- **Persona modes** (Gentleman / Neutral / Custom): Custom preserves the user's existing config. Respect-by-default onboarding — public brana must layer onto an existing `~/.claude/`, never clobber it.
- **Per-agent feature matrix in docs**: capability legibility ("what do I get on my agent") is the top of their funnel.
- **Release cadence as trust**: 244 releases; matches pending t-499 (release automation via release-plz + cargo-dist).
- **Positioning sentence**: "NOT an installer — an ecosystem configurator." One-line category definition that pre-empts the obvious objection. Brana needs its equivalent (t-407 draft: "framework for process-powered Claude systems").

## What NOT to copy

- Multi-agent adapter breadth (14+ agents) — massive surface area; brana's depth-on-one-agent is the differentiator, per the t-058 conclusion ("ship integrated system, don't decompose").
- Runtime softness — their rules are advisory text; keep brana's hook enforcement.
- No backlog/task layer — brana's process integration (build→backlog→close) is the moat t-407 identified.

## Candidate backlog items (distribution epic, pending confirmation)

1. `brana sync` + `--dry-run` on bootstrap/install/sync — re-render managed assets, preview plan.
2. Managed-state manifest + `brana uninstall` + backup/rollback (checksum-dedup, pin).
3. Skill-path injection: pass exact SKILL.md paths when spawning sub-agents (skills `_shared/` convention).
4. Review receipts spike: tree-hash-bound receipt at challenge time, validated by pre-push hook.
5. One-page hook tier model ("what fires when") for public docs.
6. Per-phase model/effort profiles in build/fix workflows (from earlier session finding — Workflow `agent()` already supports `model`/`effort`).
