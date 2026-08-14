# Brana Distribution Strategy

> Brainstormed 2026-03-15. Status: idea.

## Problem

Brana is a mature, integrated development system with zero external users. No feedback loop, no validation, no adoption beyond the creator. Distribution is the missing piece — but the approach matters: wrong packaging loses the integration value, wrong audience wastes effort.

## Decision

**Ship the integrated system. Target power users. Solve every adoption barrier.**

- **Not** decomposing into composable layers (premature — CC already supports multi-plugin loading)
- **Not** shipping a "lite" version (the integration IS the value)
- **Not** waiting for CC to fix all blockers (workarounds exist)

Distribution channel: GitHub marketplace plugin (already functional). Bootstrap.sh remains for full experience until CC ships plugin-level rules/identity.

## Research findings

### CC Plugin Ecosystem (March 2026)
- 9K+ plugins in marketplace. Discoverability requires active promotion.
- CC supports multi-plugin loading + plugin dependencies — composability is built-in at the platform level
- skills.sh indexes 82K+ SKILL.md files from GitHub (auto-discovery)
- CC templates on npm (500K+ downloads) — alternative channel for individual components
- 5+ awesome-claude-code community lists exist for curation

### Brana's Current State
- Plugin packaging shipped (v1.0.0, t-232). Marketplace install works.
- Two-layer architecture: plugin (toolkit) + bootstrap (identity). Both required for full experience.
- CC bug #24529 blocks PostToolUse hooks from plugins — bootstrap.sh workaround in place.
- Missing CC features: plugin-level rules, plugin-level identity. Bootstrap remains as "shrinking shim."
- Semantic-release configured but minimal (GitHub releases only, no changelog surfacing).

### Key Insight
The value of /brana:build is the integration — TDD + spec-first enforcement + challenger review + memory + task tracking. Stripping components makes it worse. Users who invest in the full setup get outsized returns. Target those users.

## Adoption Funnel & Barriers

```
AWARE → INTERESTED → INSTALL → CONFIGURE → VALUE → HABIT → ADVOCATE
```

| # | Barrier | Current State | Required Fix |
|---|---------|--------------|--------------|
| B1 | **Awareness** | Zero content, zero community mentions | Harness engineering posts (t-163, t-165), awesome-list submissions |
| B2 | **Interest** | README lists features, doesn't show outcomes | README rewrite: outcomes-first, before/after demo |
| B3 | **Install** | Two steps (plugin + bootstrap), jq dependency | Single-command installer (t-501) |
| B4 | **First Value** | 33 skills, no "start here" path | "Essential 5" section, guided first session |
| B5 | **Trust** | Silent hook failures possible (CC #24529) | `brana doctor` command, clear workaround docs |
| B6 | **Maintenance signal** | No changelogs, no release cadence | Release automation (t-499): semantic-release + changelog surfacing |

## Risks

| Risk | Severity | Mitigation |
|------|----------|-----------|
| Small audience (CC power users only) | Medium | Quality feedback > quantity. 5 deep users > 500 bouncers. |
| CC bugs break first impression | High | Bootstrap workaround + `brana doctor` verification. Document clearly. |
| Maintenance burden on solo maintainer | Medium | Release automation reduces toil. Content is one-time investment. |
| Users bounce at bootstrap step | Medium | t-501 reduces to one command. Accept as power-user filter until ready. |
| Nobody cares about structured workflows | Low | Harness Engineering trend (Gundecha 2026) validates demand. Test with content first. |

## Execution Order

1. **B6: Release automation** (t-499) — establishes trust infrastructure. Tagged releases, changelogs, version badges.
2. **B2: README rewrite** — outcomes-first pitch ready before driving traffic.
3. **B1: Content** (t-163, t-165) — harness engineering posts, awesome-list submissions. Traffic driver.
4. **B3-B5 in parallel:**
   - B3: Single-command installer (t-501)
   - B4: Guided first session ("Essential 5" commands)
   - B5: `brana doctor` + hook verification docs

## Success Metric

5 external users who complete 3+ `/brana:build` cycles and provide feedback within 8 weeks of first content push.

## Composability Decision

**Deferred, not rejected.** If feedback from early adopters says "I want just X," that's the signal to decompose. Don't pre-optimize for hypothetical users. CC's multi-plugin loading means composability can be added later without architectural changes.

## LinkedIn Content Strategy Integration

Brana distribution and LinkedIn personal brand are the same funnel. Brana is the proof of expertise — every post about AI systems design, harness engineering, or build-in-public is simultaneously content marketing AND distribution awareness.

**The loop:**
```
LinkedIn post (t-165) → reader visits profile → profile links to brana repo (t-162)
→ repo README sells outcomes (t-518) → user installs → feedback loop closes
```

**Niche/perspective still being refined** (t-162 in progress, t-177 Mom Test pending), but the core angle is clear: brana demonstrates what you teach. Not "I wrote a blog post about TDD" — "I built a system that enforces TDD across 6 client projects."

**Sequencing:** Profile optimization (t-162) → README rewrite (t-518) → first posts (t-165) → awesome-list submissions (t-521). Each step makes the next more credible.

## Related Tasks

- t-496: Brana Distribution & Contribution Pipeline (parent milestone)
- t-497: User journey map (completed — 23 gaps identified)
- t-499: Versioning & release automation
- t-500: Contributor onboarding (completed)
- t-501: Bootstrap → proper installer
- t-058: Distribution channels research (scope absorbed into this strategy)
- t-163, t-165: LinkedIn content drafts
- t-162: LinkedIn profile optimization (links to brana repo)
- t-518: README rewrite — outcomes-first
- t-519: Guided first session — Essential 5
- t-520: brana doctor — install verification
- t-521: Submit to awesome-claude-code lists
