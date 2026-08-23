# Skill tier mapping — 41 first-party skills against ADR-085 D3's atom/wrapper split

**Date:** 2026-08-23 · **Task:** t-2490 (closes AC1: "each existing skill classified composite vs atomic, with the granularity floor stated and justified") · **Triggered by:** `/brana:challenge --deep` finding M4 (ADR-085 claimed this re-verification without an artifact).

**Method.** Measured, not read: for each `system/skills/*/SKILL.md` — `disable-model-invocation` frontmatter (invocation reach), count of `AskUserQuestion` mentions across the skill directory (interactivity proxy), presence of `phases/` (composite procedure). Cross-referenced with t-2278's audit ([drained/skills-as-loops.md](../ideas/drained/skills-as-loops.md) §Audit preview, 34 skills, 2026-07-20). Note the two axes are **orthogonal**: t-2278 classified by *runtime shape* (stay / workflow / loop / compose / retire); D3 classifies by *invocation surface* (atom vs wrapper). Neither reclassifies the other — this doc is the missing bridge.

**Tiers (D3):**
- **W — wrapper-shaped**: user-invoked (`disable-model-invocation: true`), owns orchestration + gates. May ask.
- **A — atom-shaped**: model-invoked, one job, no `AskUserQuestion` on its main path.
- **A? — atom candidate**: model-invoked, one job, exactly one `AskUserQuestion` mention — likely an exit-router or fallback, not verified to be off the main path. (t-3041's lint resolves these.)
- **C — supervised composite**: model-invocable (field unset) *and* ask-heavy (≥2) or phase-structured. Neither atom nor thin wrapper. **Exempt under D3** ("no existing monolith is rewritten"); extraction only via D4's floor.

| skill | dmi | asks | phases | t-2278 class | D3 tier |
|---|---|---|---|---|---|
| challenge | true | 2 | – | → workflow | W |
| client-retire | true | 1 | – | stay | W |
| gsheets | true | 1 | – | stay | W |
| meta-templates | true | 0 | – | stay | W |
| onboard | true | 3 | – | stay | W |
| plugin | true | 4 | – | stay | W |
| scheduler | true | 1 | – | stay | W |
| ship | true | 7 | – | stay | W |
| cargo-machete | – | 0 | – | → standalone loop | A |
| discover | – | 0 | – | stay | A |
| domain-driven-design | – | 0 | – | stay (ref pack) | A |
| mcp-builder | – | 0 | – | stay (ref pack) | A |
| rust-skills | – | 0 | – | stay (ref pack) | A |
| terminal-diagrams | – | 0 | – | (post-audit) | A |
| web-design-guidelines | – | 0 | – | stay (ref pack) | A |
| align | – | 1 | – | stay | A? |
| bash-defensive-patterns | – | 1 | – | stay (ref pack) | A? |
| design-system | – | 1 | – | stay (ref pack) | A? |
| do | – | 1 | – | retire → backlog start | A? (still present) |
| export-pdf | – | 1 | – | stay | A? |
| gemini | – | 1 | – | compose (agent-wrapper) | A? |
| grad-mechanism-design | – | 1 | – | stay (ref pack) | A? |
| impeccable | – | 1 | – | stay (ref pack) | A? |
| product-brainstorming | – | 1 | – | stay | A? |
| sitrep | – | 1 | – | (post-audit) | A? |
| verify-docs | – | 1 | – | retire → reconcile sensor | A? (still present) |
| backlog | – | 18 | Y | stay | C |
| build | – | 21 | Y | compose (loop-body) | C |
| close | – | 29 | Y | compose (loop-body) | C |
| reconcile | – | 4 | Y | → standalone loop | C |
| brainstorm | – | 16 | – | stay | C |
| log | – | 7 | – | stay | C |
| fix | – | 4 | – | compose (loop-body) | C |
| acquire-skills | – | 4 | – | stay | C |
| claudemd | – | 3 | – | stay | C |
| decide | – | 3 | – | stay (human router) | C |
| docs | – | 3 | – | compose | C |
| review | – | 3 | – | stay (cadence) | C |
| memory | – | 2 | – | compose | C |
| research | – | 2 | – | → workflow | C |
| retrospective | – | 2 | – | compose | C |

**Counts:** W 8 · A 7 · A? 11 · C 15 · **total 41** (t-2278's 34 + 7 added since, e.g. terminal-diagrams, sitrep).

## Findings

1. **t-2278's verdicts stand — no reclassification on its axis.** Every compose/workflow/loop entry lands in C except `cargo-machete` (an ask-free loop → A) and `challenge` (user-invoked → W). The two retire candidates (`do`, `verify-docs`) are still present — t-2278 is unblocked, not done.
2. **The "22 stay-skills" are not one tier.** Reference packs → A/A?; conversational utilities (`backlog`, `brainstorm`, `log`, `decide`, `review`) → C. "Stay skill" in t-2278 meant *don't turn it into a loop*, which says nothing about atom-vs-wrapper.
3. **D3(b) is currently violated by 26 of 33 model-invoked skills** (≥1 `AskUserQuestion` mention). This is the M7 finding made concrete: `disable-model-invocation` does not deliver property (b) — only 8 skills set it, and interactivity is uncorrelated with it. Enforcement = t-3041's lint, advisory first.
4. **Granularity floor (D4) applied to C:** only the four phase-structured composites (`backlog`, `build`, `close`, `reconcile`) have phase files that *could* be extracted; the floor (≥2 callers or must run headless) selects exactly what ADR-085 D4 already names — the TDD loop body (build + fix, headless under a runner) and the judgment organs (t-3040). No other phase file has a second caller today. Floor holds; no extraction beyond D4's two.
5. **Pocock cross-check.** His user-invoked skills (`implement`, `to-tickets`) ≈ W; model-invoked (`diagnosing-bugs`, `tdd`) ≈ A — internally multi-step is fine for A (challenge finding M6, refuted: "node, never the graph" is about inter-skill composition, not internal steps). Brana's C tier has **no Pocock analogue** — it exists because brana carries enforcement gates inside skills (ADR-085 Context ¶4), which he doesn't.

## What this does NOT decide
Whether any C skill *should* become W+A (thin wrapper over atoms). That is t-2278's parked north-star and D6's evidence-gated path — this table is the baseline for that decision, not the decision.
