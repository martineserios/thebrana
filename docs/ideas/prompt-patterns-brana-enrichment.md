---
title: Prompt Patterns → brana Enrichment
status: draft
created: 2026-06-03
challenged: 2026-06-03
---

# Prompt Patterns → brana Enrichment

> Brainstormed 2026-06-03. Triggered by a viral Substack post ("20 secret Claude commands")
> that revealed user demand for structured AI behavior modifiers.
> Goal: extract genuinely valuable patterns; fold into brana without adding noise.

## Context

Charlie Hills' Substack post markets 20 "secret Claude commands" (/ultrathink, /devil,
/premortem, etc.). Research shows these are NOT real commands — they're informal prompt
conventions dressed in slash syntax. **Only `/ultrathink` had real machinery, and it was
deprecated on 2026-01-16** when Anthropic made extended thinking automatic for all Claude 4.x
models. The rest are conversational cues that work because Claude understands intent.

**The real insight:** the post went viral because users are hungry for structured,
predictable AI behavior. brana already solves this for workflows. This analysis asks:
which of these patterns fill genuine gaps in brana's skill system?

## Research Findings

### What is actually a Claude feature

| Feature | Status | brana action |
|---------|--------|-------------|
| Extended thinking | Auto-enabled on Claude 4.6 (sonnet-4-6) | Enable opt-in deep mode via `BRANA_DEEP_THINKING=1` → sets `MAX_THINKING_TOKENS=63999` |
| `alwaysThinkingEnabled` | In CC settings | Confirm brana's CC config has this on |
| Adaptive depth | Model decides automatically (no keyword needed) | Rely on it; don't fight it with manual hints |
| `/ultrathink` keyword | Deprecated Jan 16, 2026 | Audit + remove from all skill procedures that reference it |

**Actual CC slash commands** (built-in, not brana): `/clear`, `/compact`, `/init`,
`/memory`, `/model`, `/review`. The 20 "commands" from the post are none of these.

### Coverage audit: brana vs. the 20 patterns

| Pattern | Behavior | brana coverage |
|---------|----------|---------------|
| /ultrathink | Deep reasoning | Deprecated; thinking is auto |
| /godmode | Thorough all-angles | Implicit in `/brana:build` |
| /L99 | Expert level, no dumbing down | Opus model flag; not a skill |
| /devil | Argue against the idea | `/brana:challenge` ✓ |
| /steelman | Build the best opposing argument | `/brana:challenge` (partial) |
| /critique | Pull apart weak points | `/brana:challenge` + `/brana:review` ✓ |
| /UDA | Military-style structured analysis | `/brana:build` phases ✓ |
| /scout | Hidden risk scanning | `brana:scout` agent — not user-facing |
| /OODA | Observe / Orient / Decide / Act | Nothing |
| /persona | Lock into expert role for session | Nothing |
| /blindspots | Surface hidden assumptions | `/brana:challenge` (partial) |
| /brutal | Raw, unfiltered feedback | `/brana:challenge` tone variant (partial) |
| /ghost | Rewrite to sound human | Nothing — writing-only |
| /eli5 | Plain language explanation | Nothing |
| /skeptic | Challenge the question before answering | `/brana:challenge` ✓ |
| /10x | Rewrite 10x sharper | Nothing — writing-only |
| /noyap | Answer first, no preamble | Nothing — style-only |
| /punch | Cut text 40% | Nothing — style-only |
| /premortem | Assume failure, work backwards | Nothing — **clear gap** |
| /pitch | 30-sec investor pitch | Nothing — venture/writing |

**Coverage: ~35%** (7/20). The 7 covered cases map to challenge + build + review.

## Recommendations

### Tier 1 — High value, low effort: enrich existing skill procedures

These patterns don't need new skills — they need a line or two added to existing procedures:

**`/brana:challenge` enrichments:**
- Add `--deep` mode that activates three patterns in sequence: (1) **steelman** — build
  the strongest version of the opposing argument first; (2) **blindspots** — surface hidden
  assumptions after challenge rounds; (3) **brutal** — strip diplomatic softening from
  output. One flag, not three separate behaviors. Keeps the default flow lean.
- Add `--premortem` flag as a named challenge variant: "Assume this plan has already
  failed 12 months from now. What went wrong?" Distinct from `--deep` — runs a single
  focused failure analysis rather than a full adversarial round. This replaces the need
  for a separate `/brana:premortem` standalone skill (resolved below).

**`/brana:build` enrichments:**
- Add **optional premortem gate** at the SHAPE step: an AskUserQuestion offered for M+
  effort tasks, default "skip." User sees: "Run a quick premortem before committing to
  backlog?" No flag parsing, no auto-trigger — just a prompt at the right moment.
- Audit and remove any references to `/ultrathink` keyword — thinking is now auto-enabled.

**`/brana:research` enrichments:**
- Add `--eli5` flag: output as plain-language summary (no assumed domain knowledge).
  Useful when preparing explanations for non-technical stakeholders.

### Tier 2 — New skills worth building

**`/brana:premortem` → resolved: absorbed into `/brana:challenge --premortem`**
- Challenge verdict: building standalone creates duplicate maintenance surface with the
  `--premortem` variant added to challenge. Resolved as a flag, not a skill. If standalone
  becomes clearly necessary after the challenge enrichment ships, revisit.

**`/brana:persona`** (P3, effort S)
- Session-level role injection. Example: `/brana:persona CTO fintech startup`
- ~~Writes to CLAUDE.local.md~~ — **Challenge finding (CRITICAL):** CLAUDE.local.md write
  creates session bleed: persona persists silently into the next session if not reset;
  `/brana:close` has no knowledge of it.
- **Revised design:** persist persona as a field in the brana session state JSON
  (`session.persona`). The close skill already reads session state — it can offer to reset
  on session end. Source of truth is the session, not a gitignored file.
- Reset: `/brana:persona reset` → clears `session.persona` field.
- Useful for: client work (think from their CTO's POV), role-playing decision scenarios,
  preparing for stakeholder conversations.

**`/brana:scout` (user-facing)** (P3, effort XS)
- The `brana:scout` agent type already exists internally. Expose it as a direct skill.
- Usage: `/brana:scout "what are the risks of removing the TDD gate?"`
- Runs the scout agent on a question and surfaces hidden risks + blind spots.

### Tier 3 — Config change, not a skill

**Add `BRANA_DEEP_THINKING=1` opt-in env flag** (not a global default).
- When set: exports `MAX_THINKING_TOKENS=63999`, doubling the thinking budget for Claude 4.6
  64K-output models (Sonnet 4.x, Haiku 4.5).
- **Not global by default** — challenge finding (WARNING): setting globally on all sessions
  doubles thinking token cost even for trivial turns. Opt-in preserves cost control.
- Implementation: add to brana launch script as `[ "$BRANA_DEEP_THINKING" = "1" ] && export MAX_THINKING_TOKENS=63999`.
- User sets in shell profile or passes per-session: `BRANA_DEEP_THINKING=1 claude`.

### Tier 4 — Skip (style-only, not brana's job)

`/ghost`, `/punch`, `/10x`, `/noyap`, `/pitch` — these are content/writing modifiers.
Valid as one-off prompts in chat; not worth formalizing as skills. If writing assistance
becomes a core workflow, revisit as a dedicated `/brana:write` skill later.

## Risks and Mitigations

| Risk | Mitigation | Status |
|------|-----------|--------|
| Premortem gate adds friction to build flow | AskUserQuestion at SHAPE step, M+ only, default skip | Resolved in design |
| Persona leaks between sessions | Session-state JSON (not CLAUDE.local.md); close skill resets on session end | Resolved in design |
| MAX_THINKING_TOKENS increases cost globally | BRANA_DEEP_THINKING=1 opt-in flag, not a default | Resolved in design |
| `/brana:scout` duplicates `/brana:challenge` | Different purpose: scout = risk scan on a question, challenge = adversarial review of a plan | Open |
| `--deep` and `--premortem` flags diverge from challenge default flow | Document flags in challenge procedure header; test both code paths | Open |

## Engineering Disciplines

- **DDD:** Persona session-state design is novel (first skill to read/write session state
  as a behavior modifier) — lightweight ADR needed before implementation.
- **TDD:** For `/brana:persona` — test that `session.persona` writes/reads/resets via
  session MCP tools. For premortem gate in build — test that the AskUserQuestion fires for
  M+ and is absent for S/XS.
- **SDD:** Update `docs/reference/skills.md` after any new skill ships.
- **Docs:** No user guide needed for procedure enrichments; yes for `/brana:persona` and
  `/brana:scout` user-facing.

## Next Steps

Ordered by dependency — don't start an item until its prerequisites are done.

1. (XS) Audit skill procedures for `/ultrathink` references and remove them
2. (XS) Add `BRANA_DEEP_THINKING=1` opt-in flag to brana launch script
3. (S) Enrich `/brana:challenge` with `--deep` mode (steelman + blindspots + brutal)
   and `--premortem` flag (failure analysis variant) — these are one PR
4. (S) Add optional premortem gate to `/brana:build` SHAPE step (M+ only, default skip)
   — blocked by: step 3 (uses challenge --premortem under the hood)
5. (ADR, XS) Write ADR for persona-via-session-state pattern before building
6. (S) Build `/brana:persona` with session-state read/write/reset — blocked by: step 5
7. (XS) Expose `/brana:scout` as user-facing skill — independent, anytime
