# User Journey Map & Gap Analysis

> t-497 deliverable. Maps the end-to-end brana experience for external users.
> Parent: t-496 (Brana Distribution & Contribution Pipeline)

## Journey Stages

### 1. Discovery

**Current state:** Users find brana via GitHub search or CC plugin marketplace.

| Touchpoint | Exists | Quality |
|-----------|--------|---------|
| README.md | Yes | Good — "What you get" section, install paths, feature highlights |
| marketplace.json | Yes | Metadata present (24 skills, 10 hooks, 11 agents) |
| GitHub topics/tags | Partial | Keywords in plugin.json but no GitHub repo topics set |
| Blog/social posts | No | LinkedIn content pipeline planned (t-163, t-165) but no posts live |
| CC marketplace search | Unknown | Depends on CC marketplace indexing — untested externally |

**Gaps:**
- **G1: No external validation of marketplace discoverability.** We've never searched for "brana" from a fresh CC install. Does it appear? What search terms surface it?
- **G2: No social proof.** Zero blog posts, zero community mentions, zero demo videos. README is the only pitch.
- **G3: GitHub repo topics not configured.** Missing `claude-code`, `ai-development`, `plugin`, `developer-tools` topics that drive organic search.

---

### 2. Install

**Current state:** Three paths documented in `docs/guide/getting-started.md`.

| Path | Target User | Time | Friction |
|------|------------|------|----------|
| Marketplace | End user | ~30s | `/plugin marketplace add` + `/plugin install` — two commands |
| Dev mode | Contributor | ~1min | `git clone` + `claude --plugin-dir ./system` every session |
| Bootstrap (identity) | Power user | ~2min | Requires `jq`. Deploys to `~/.claude/` |

**Gaps:**
- **G4: No single-command install.** Marketplace path requires two commands. No `curl \| sh` or `brew install`. (Addressed by t-501.)
- **G5: Dev mode requires `--plugin-dir` every session.** No `.clauderc` or project-level config to persist this. Contributors must remember the flag.
- **G6: Bootstrap prerequisites unclear upfront.** `jq` required but only discovered at runtime. Node.js needed for ruflo but optional — confusing.
- **G7: No install verification beyond manual checklist.** `getting-started.md` has a checklist but no `brana doctor` command to auto-verify.

---

### 3. Configure

**Current state:** Optional but important for full experience.

| Config Area | Mechanism | Docs |
|-------------|-----------|------|
| Display theme | `/brana:backlog theme` | configuration.md |
| Task portfolio | Edit `~/.claude/tasks-portfolio.json` | configuration.md |
| Scheduler | `brana-scheduler enable/deploy` | scheduler.md |
| MCP servers | Edit `.mcp.json` | — |
| GitHub sync | Edit `~/.claude/tasks-config.json` | — |

**Gaps:**
- **G8: No guided setup wizard.** After install, users must read docs to know what to configure. A `/brana:setup` or interactive first-run could walk through: theme, portfolio, scheduler, GitHub sync.
- **G9: MCP server setup undocumented for new users.** `.mcp.json` exists but no guide explains which MCP servers brana benefits from or how to add them.
- **G10: GitHub sync config is manual JSON editing.** No CLI command to enable/configure it.

---

### 4. Use

**Current state:** Strong — 33 skills, 11 agents, 10 hooks. Well-documented.

| Learning Path | Resource | Quality |
|---------------|----------|---------|
| Tab-complete `/brana:` | Built-in | Good — immediate discovery |
| Command index | `docs/guide/commands/index.md` | Good — 25 commands listed |
| Workflow guides | `docs/guide/workflows/*.md` | Good — 9 guides covering all major flows |
| First session walkthrough | `getting-started.md` lines 77-98 | Good — step-by-step |
| Concepts glossary | `docs/guide/concepts.md` | Exists |

**Gaps:**
- **G11: No progressive disclosure.** New users see all 33 skills at once. No "start here" subset or difficulty levels. Overwhelming for someone who just wants to try it.
- **G12: No interactive tutorial.** No `/brana:tutorial` that walks through a sample build-test-close cycle on a demo project.
- **G13: No usage telemetry or feedback mechanism.** We don't know which skills users actually use, which ones confuse them, or where they drop off.

---

### 5. Update

**Current state:** Two paths documented in `docs/guide/upgrading.md`.

| Path | Mechanism | Post-upgrade |
|------|-----------|-------------|
| Marketplace | `/plugin update brana` | Re-run `bootstrap.sh` |
| Dev mode | `git pull` | Next session picks up changes |

**Gaps:**
- **G14: No changelog surfacing.** After update, users don't see what changed. No `brana --changelog` or post-update notification.
- **G15: Bootstrap re-run not automatic after plugin update.** Users must remember to re-run `./bootstrap.sh` — easy to forget, leading to identity/plugin version skew.
- **G16: No version pinning.** Users can't pin to a specific version or roll back via marketplace. Only dev mode supports `git checkout <tag>`.

---

### 6. Report Bugs

**Current state:** GitHub Issues + SECURITY.md for vulnerabilities.

| Channel | Exists | Quality |
|---------|--------|---------|
| GitHub Issues | Yes | No issue templates |
| SECURITY.md | Yes | Minimal — "open issue marked security" |
| Troubleshooting guide | Yes | Good — symptom-to-fix format |

**Gaps:**
- **G17: No issue templates.** No bug report template, feature request template, or question template. Users must write from scratch.
- **G18: No `brana report` command.** No way to auto-collect environment info (CC version, brana version, OS, active hooks, plugin status) for bug reports.
- **G19: No community channel.** No Discord, Slack, or GitHub Discussions for questions that aren't bugs.

---

### 7. Contribute

**Current state:** CONTRIBUTING.md exists and is comprehensive.

| Aspect | Documented | Quality |
|--------|-----------|---------|
| Dev setup | Yes | Clear 3-step process |
| Branch naming | Yes | Table with prefixes |
| Commit conventions | Yes | Conventional Commits with examples |
| PR process | Yes | 7-step flow |
| Testing | Yes | Manual + `validate.sh` |
| Release automation | Yes | semantic-release, fully automated |
| Extending guides | Yes | Skills, hooks, agents each have their own doc |

**Gaps:**
- **G20: No "good first issue" pipeline.** Label exists but no process to regularly tag approachable issues.
- **G21: No contributor recognition.** No AUTHORS file, no changelog credits, no "contributors" section in README.
- **G22: Testing is mostly manual.** No automated test suite for skills/hooks. `validate.sh` checks frontmatter and budgets but doesn't exercise behavior. Contributors can't run `npm test` or equivalent.
- **G23: No development environment parity check.** A contributor's `--plugin-dir` setup may diverge from the published plugin. No `brana dev check` to verify.

---

## Gap Priority Matrix

| Gap | Stage | Impact | Effort | Priority |
|-----|-------|--------|--------|----------|
| **G1** Marketplace discoverability | Discovery | High | S | P1 — validate before any promotion |
| **G2** No social proof | Discovery | High | M | P1 — content pipeline (t-163, t-165) |
| **G3** GitHub topics | Discovery | Medium | XS | P0 — 2 minutes to set |
| **G4** No single-command install | Install | High | M | P1 — t-501 covers this |
| **G5** Dev mode flag every session | Install | Medium | S | P2 — CC limitation |
| **G6** Prerequisites unclear | Install | Medium | S | P1 — update getting-started |
| **G7** No install verification cmd | Install | Medium | M | P2 — `brana doctor` |
| **G8** No setup wizard | Configure | Medium | M | P2 |
| **G9** MCP setup undocumented | Configure | Low | S | P2 |
| **G10** GitHub sync manual config | Configure | Low | S | P3 |
| **G11** No progressive disclosure | Use | High | M | P1 — "start here" subset |
| **G12** No interactive tutorial | Use | Medium | L | P3 |
| **G13** No usage telemetry | Use | Low | L | P3 |
| **G14** No changelog surfacing | Update | Medium | S | P2 |
| **G15** Bootstrap not auto after update | Update | Medium | M | P2 — t-501 may solve |
| **G16** No version pinning | Update | Low | M | P3 |
| **G17** No issue templates | Bug Report | Medium | S | P1 — 15 min to create |
| **G18** No `brana report` cmd | Bug Report | Low | M | P3 |
| **G19** No community channel | Bug Report | Medium | S | P2 |
| **G20** No good-first-issue pipeline | Contribute | Medium | S | P2 |
| **G21** No contributor recognition | Contribute | Low | S | P3 |
| **G22** Testing mostly manual | Contribute | High | L | P1 — blocks confidence in PRs |
| **G23** No dev parity check | Contribute | Low | M | P3 |

## Quick Wins (P0 — do now)

1. **G3:** Set GitHub repo topics (`claude-code`, `ai-development`, `plugin`, `developer-tools`, `claude-code-plugin`)

## High-Impact Next (P1 — this milestone)

2. **G1:** Test marketplace discoverability from a fresh CC install
3. **G2:** Ship first 2-3 LinkedIn posts (t-163, t-165)
4. **G4:** Single-command installer (t-501)
5. **G6:** Add prerequisites section with versions to getting-started.md
6. **G11:** Create "Essential 5 commands" section in getting-started.md
7. **G17:** Add GitHub issue templates (bug, feature, question)
8. **G22:** Automated test framework for skills/hooks (prerequisite for contributor confidence)

## Journey Diagram

```
DISCOVERY          INSTALL           CONFIGURE         USE
─────────────────────────────────────────────────────────────
GitHub/Marketplace → /plugin install → [optional setup] → /brana:build
       │                  │                │                  │
       │ G1,G2,G3         │ G4,G5,G6,G7   │ G8,G9,G10       │ G11,G12,G13
       ▼                  ▼                ▼                  ▼
  "How do I          "Two commands?     "What do I        "33 commands,
   find this?"        jq? ruflo?"        configure?"       where start?"


UPDATE             REPORT BUGS        CONTRIBUTE
─────────────────────────────────────────────────
/plugin update → GitHub Issues → Fork → PR → Release
       │                │                │
       │ G14,G15,G16    │ G17,G18,G19   │ G20,G21,G22,G23
       ▼                ▼                ▼
  "What changed?     "No template,     "How do I test?
   Re-run bootstrap?" no env info"      Manual only?"
```

## Recommendations for t-496 Sibling Tasks

| Task | Gaps Addressed | Recommendation |
|------|---------------|----------------|
| t-498 (Plugin registry) | G1, G5 | Validate discoverability first. Consider `.claude/config` for persistent plugin-dir. |
| t-499 (Versioning & release) | G14, G16 | Add post-update changelog display. Consider `brana --version --changelog`. |
| t-500 (Contributor onboarding) | G20, G21, G22, G23 | CONTRIBUTING.md exists — focus on test infra (G22) and issue templates (G17). |
| t-501 (Installer) | G4, G6, G7, G15 | `curl \| sh` that handles prerequisites check, plugin install, bootstrap, and verification. |
