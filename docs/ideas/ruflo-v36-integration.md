# Ruflo v3.6 Integration — thebrana v1.20

> Brainstormed 2026-05-20. Status: partial — Track C (DONE), Track D (DONE), Track B (NO-GO), Track A (pending).

## Problem

Brana is running ruflo v3.6.30 but was designed against v3.5.1 assumptions. Several v3.6
capabilities — RRF/MMR diversity memory search, browser automation substrate, expanded
AgentDB controllers, new tool namespaces (daa_, hive-mind_, etc.) — are installed but not
wired into any brana skill, procedure, or hook.

Additionally, a stale memory file (`project_ruflo-agentdb-status.md`) claimed brana was
on v3.5.1 (a version with known prompt injection CVEs). The memory was wrong — brana is
on v3.6.30, already past the v3.5.40 security remediation.

## Key Discoveries from Session 2026-05-20

### Version State
- Installed: **ruflo v3.6.30** (not v3.5.1 — memory was stale)
- Security CVEs (prompt injection + preinstall, fixed in v3.5.40): **already remediated**
- Memory file `project_ruflo-agentdb-status.md`: corrected this session

### Confirmed Stubs (don't build on these)
- `ruflo security-scan` — returns hardcoded fake vulnerability counts
- `ruflo deploy` — no real implementation
- Memory quantization — hardcoded 3.92× multiplier

### Infrastructure Confidence
- `ruflo-mcp.sh`: well-built (exec, CLAUDE_PROJECT_DIR, nvm resolution)
- `bulk-index.mjs`: dynamic ruflo node_modules resolution — robust across upgrades
- Blast radius for further upgrades: **low**

## Opportunities (v3.6 features not yet wired)

### 1. RRF + MMR diversity in LOAD steps
- `ruflo-rag-memory` in v3.6 supports `smart: true` on `memory_search` calls
- Enables: RRF fusion, query expansion, MMR diversity, recency boost
- Currently: brana LOAD steps call `memory_search` without `smart: true`
- Impact: every brainstorm/build/research session gets better recall quality
- Integration cost: **low** — add `smart: true` to LOAD calls in 4 procedures

### 2. Browser automation substrate
- Ruflo v3.6 ships `mcp__ruflo__browser_*` tools (Playwright-backed, depth unknown)
- Concrete brana use case: **Meta template appeals** — currently documented as "UI-only"
  in `brana:meta-templates`. Browser automation could automate the Meta Business Manager
  appeal flow (affects somos_mirada, proyecto_anita, mya, brapsoclaw)
- Secondary: richer scout agent research (navigate docs, not just WebSearch snippets)
- Integration cost: **medium** — spike needed to validate depth, then wire into meta-templates

### 3. New tool namespace audit
- v3.6 adds: `mcp__ruflo__daa_*` (Dynamic Agent Adaptation), `mcp__ruflo__hive-mind_*`
  (already partially used), `mcp__ruflo__browser_*`, `mcp__ruflo__ruvllm_*`, expanded
  `mcp__ruflo__agentdb_*` (19 controllers vs 8 known)
- Some likely relevant, some likely stubs — unvalidated
- Integration cost: **medium** — structured spike to test each new namespace

### 4. Stub command hygiene
- Add lint rule or procedure note: never use `ruflo security-scan`, `ruflo deploy`,
  or memory quantization as authoritative output
- Integration cost: **low** — add to rules or skill procedure prose

## Shape Summary

**Problem:** Brana runs ruflo v3.6.30 but was designed against v3.5 assumptions. v3.6 capabilities are installed but unwired.

**Solution:** Three-track integration — smart memory, browser automation, tool audit.

**Audience:** Thebrana itself → all downstream clients and ventures using brana skills.

**Scale:** 1-2 weeks, significant effort (M+).

**Success metrics:**
- LOAD steps return measurably better results (before/after test)
- `brana:meta-templates` appeal no longer requires manual browser navigation
- New tool namespace map exists; stubs flagged in rules

## Risks

- `smart: true` adds latency per LOAD call → degrade to `smart: false` in hot-path hooks if needed
- Browser automation may be a shallow wrapper → spike first, feature plan after validation
- Tool audit may find mostly stubs → test before wiring; "not yet wired" is safe default

## Engineering Disciplines

- **DDD:** ADR for `smart: true` as LOAD default; ADR for browser automation adoption
- **TDD:** Before/after memory quality test; browser_check smoke test
- **SDD:** Update `56-ruflo-agentdb-architecture.md`; update LOAD step docs in 4 procedures
- **Docs:** Update `brana:meta-templates` skill; update hooks.md if browser wires into hooks

## Planned Tracks

### Track A — Smart Memory (quick win, same session or next)
1. Add `smart: true` to LOAD calls in brainstorm/build/research/review procedures
2. Validate with before/after test (compare top-3 results with and without)

### Track B — Browser Automation (spike → feature) — **NO-GO 2026-05-20**
1. ~~Run `mcp__ruflo__browser_check` to validate substrate is live~~ — `browser_check` is a checkbox interaction tool, not a health check (E2026-05-20-10)
2. Validated via t-1550: Chromium network fully blocked in CC environment (DNS + direct IP both fail)
3. **CANCELLED** pending environment fix — see `56-ruflo-agentdb-architecture.md` §Browser Substrate for fix path

### Track C — Tool Namespace Audit
1. Enumerate new namespaces: `daa_*`, `ruvllm_*`, extended `agentdb_*` (11 new controllers)
2. Test each with a sample call; produce "real vs. stub" classification table
3. Map confirmed-real tools to brana procedures that could use them

### Track D — Stub Command Guard (low cost)
1. Add lint rule or procedure note: never treat `ruflo security-scan` / `ruflo deploy` / quantization output as authoritative
