# Research: Matt Pocock's Skill System vs brana's

**Date:** 2026-08-13 | **Task:** t-2830 | **Strategy:** research (comparison + improvement mining)
**Sources:** [github.com/mattpocock/skills](https://github.com/mattpocock/skills) (35 `SKILL.md` files read in full, `main` branch, 2026-08-13) · [aihero.dev/skills](https://www.aihero.dev/skills) · brana internal: `docs/reference/skills.md`, `docs/reference/skill-validation-checklist.md`, `system/skills/_shared/smart-router.md`, `system/skills/challenge/SKILL.md`, `docs/ideas/drained/gentle-ai-adoption-ladder.md`, `docs/ideas/drained/enforced-delegation.md`

## Method

Internal-first per `research-discipline.md`: read brana's own skill-authoring docs and a sample of brana skill frontmatter before touching the external repo. The external repo's actual layout differs from the `aihero.dev/skills` marketing page — it is organized as `skills/{engineering,productivity,in-progress,misc}/<name>/SKILL.md`, 35 skills total, not the ~18 the first-pass estimate suggested (engineering: 18, productivity: 7, in-progress: 6, misc: 4). Every one was read; `SKILL-MECHANICS.md` and `PHASE-BOUNDARIES.md` (referenced sub-files) were pulled too.

---

## 1. Comparison Table — every mattpocock/skills skill mapped

Legend: **✅ counterpart** (brana has an equivalent doing the same job) · **◐ partial** (brana covers part of the job, different shape or narrower) · **✗ no counterpart** (brana has nothing).

### Engineering tier (18)

| Pocock skill | Invocation | Job | brana counterpart | Match |
|---|---|---|---|---|
| `ask-matt` | user | Router — names the main flow, on-ramps, standalone skills, vocabulary layer, in one ordered doc | `/brana:do` (thin alias to `backlog start`) + `docs/reference/skills.md` 6-Jobs table (unordered, generated) | ◐ — router exists, but nothing plays `ask-matt`'s role of an ordered, walkable idea→ship narrative |
| `grill-with-docs` | user | Stateful interview that also builds `CONTEXT.md`/ADRs | `/brana:brainstorm` (interview-ish, no CONTEXT.md glossary discipline) | ◐ |
| `grill-with-docs`'s primitive → `grilling` | model | Interview primitive: rounds, "frontier" of unblocked questions, recommended answers | none | ✗ |
| `implement` | user | 12-line wrapper: drive `/tdd` at seams, then `/code-review`, commit | `/brana:build` (BUILD/TDD-loop phase) | ✅ — brana's version is far larger in scope (full SPECIFY→CLOSE pipeline vs. a thin wrapper) |
| `tdd` | model | Red-green-refactor reference: seams, anti-patterns (implementation-coupled, tautological, horizontal-slicing), loop rules | embedded in `/brana:build`'s TDD step + global `sdd-tdd.md` rule | ◐ — no standalone `/tdd` skill; discipline is diffused across a rule + a build phase |
| `code-review` | model | Two-axis review (Standards vs Spec) via **parallel, non-reranked** sub-agents | `pr-reviewer` agent + `challenger` agent | ◐ — neither separates the two axes; findings get blended |
| `triage` | user | 5-role issue state machine (`needs-triage`/`needs-info`/`ready-for-agent`/`ready-for-human`/`wontfix`), redundancy + prior-rejection checks | `/brana:backlog triage` subcommand | ✗ — **corrected 2026-08-22, was a false cognate, not just vocabulary drift**: `/brana:backlog triage` (`system/skills/backlog/phases/triage-sync.md`) does *priority* reassessment (P0–P3 urgency tiers) — a genuinely different job from Pocock's *readiness routing* (is this ticket ready for an agent yet, or does it need more info first). No brana equivalent to his readiness state exists; see the-brana-guide.md L2.2b/L3 for the live gap this reopens. |
| `improve-codebase-architecture` | user | Scans for "deepening opportunities," renders a self-contained HTML/Mermaid report with before/after diagrams and recommendation-strength badges | none | ✗ |
| `setup-matt-pocock-skills` | user | One-time per-repo config: issue tracker, triage labels, `CONTEXT.md` layout | `/brana:align` + `/brana:onboard` (broader scope — general alignment, not skill-system config) | ◐ |
| `to-spec` | user | Synthesize the current conversation into a spec — explicitly **no interview** | `/brana:build` SPECIFY phase | ✅ |
| `to-tickets` | user | Spec → tracer-bullet tickets with explicit **blocking edges**; names the **expand–contract** pattern for wide, un-sliceable refactors | `/brana:build` DECOMPOSE phase + `backlog_add`'s `blocked_by` field | ◐ — blocking-edge mechanics exist; brana has no named expand–contract pattern for wide refactors |
| `wayfinder` | user | Huge foggy effort → a **map** of **decision tickets** (not deliverables) on the tracker; **frontier** = unblocked+unclaimed children; **fog of war** = named-but-not-yet-ticketable work; **out of scope** ≠ fog | brana's wave-pipeline / drain-loop (ADR-079) | ◐ — structurally close in spirit (frontier, claim-before-work, decisions recorded then closed) but brana's waves drain **execution** tasks, not **decision** tickets; the fog-of-war / out-of-scope distinction has no brana equivalent |
| `diagnosing-bugs` | model | 6-phase debug discipline: build a **tight, red-capable feedback loop** first (explicit completion criteria) → reproduce+minimize → **3–5 ranked, falsifiable hypotheses shown to the user before testing** → tagged instrumentation → fix+regression test → cleanup+post-mortem | `/brana:fix` (reproduce→diagnose→fix→verify→commit) | ◐ — same shape, much less granular: no explicit tight-loop completion criteria, no hypothesis-ranking step, no tagged-debug-log discipline |
| `research` | model | Background agent reads primary sources, writes one cited Markdown file | `/brana:research` | ✅ — brana's is a strict superset (registry, 3-phase scout budget, agy cross-check) |
| `resolving-merge-conflicts` | model | Hunk-by-hunk conflict resolution traced to each side's primary source (commit/PR/issue); **never `--abort`** | none | ✗ |
| `prototype` | model | Throwaway code that answers one design question (state-model vs UI branch); captured afterward as a **primary source** on a `prototype/<name>` branch | `strategy: spike` field exists on brana tasks (seen live on t-2830 itself) but no skill/discipline around it | ◐ |
| `wizard` | model | Generates an interactive bash script that walks a *human* through manual-only steps (credentials, dashboards, migrations) — opens URLs, captures values, writes `.env`/GitHub secrets, shows progress | none | ✗ |
| `codebase-design` | model | Shared vocabulary for deep modules: module/interface/depth/seam/adapter/leverage/locality; "one adapter = hypothetical seam, two = real"; the deletion test | none | ✗ |

### Productivity tier (7)

| Pocock skill | Invocation | Job | brana counterpart | Match |
|---|---|---|---|---|
| `grill-me` | user | Stateless version of `grill-with-docs` (no repo) | `/brana:brainstorm` | ◐ |
| `grilling` | model | (see above) | none | ✗ |
| `handoff` | user | Compact conversation → portable handoff doc; "suggested skills" section; redacts secrets | `/brana:close --continue` | ✅ — brana's is richer (also does pattern extraction, doc-drift detection) |
| `teach` | user | Multi-session stateful teaching workspace: `MISSION.md`, `lessons/*.html`, `learning-records/*.md` (ADR-shaped), fluency-vs-storage-strength design | none | ✗ |
| `to-questionnaire` | user | Turns an unanswerable decision into an async questionnaire for a third party; "grills the send, not the subject" | none | ✗ |
| `wait-what` | user | Re-pitches the agent's last message in plain English using `CONTEXT.md` vocabulary | none (`/brana:sitrep` is a different job — session reorientation, not message re-explanation) | ✗ |
| `writing-for-agents` | model | Prose-craft reference for any agent-consumed doc: **context pointers**, **information hierarchy** (step/reference/disclosed-reference), **completion criteria** (clarity × demand), **leading words**, pruning (single-source-of-truth, no-op test) | `docs/reference/skill-validation-checklist.md` (12-Factor-derived, pass/fail) | ◐ — different lens, not a conflict: Pocock's is *why good prose works*, brana's is *a compliance gate*. See §3. |

### In-progress tier (6) — Pocock's own words, not yet promoted to `engineering`/`productivity`

| Skill | Job | brana counterpart |
|---|---|---|
| `claude-handoff` | Same as `handoff` but launches a **background** `claude --bg` agent instead of writing a file | `/brana:close --continue` writes a file; no background-agent launch equivalent — ✗ |
| `loop-me` | Grills personal-life **workflows** into `workflows/*.md` specs (trigger/checkpoint/"push right"/brief vocabulary) | `/brana:scheduler` + native `/loop` cover recurring *execution*, not workflow *spec-authoring* — ✗ |
| `setup-ts-deep-modules` | Wires `dependency-cruiser` to enforce entry-point/subfolder module boundaries in TS repos | N/A — brana is Rust/shell, not TS; not portable |
| `writing-beats` / `writing-fragments` / `writing-shape` | Explore→exploit content-authoring pipeline (fragments → beats/shape → article) | `/brana:docs` generates docs, no fragment-authoring discipline — ✗, low priority (personal-writing tooling, not skill-system) |

### Misc tier (4) — Pocock's own "misc," narrow/course-specific

| Skill | Job | brana counterpart |
|---|---|---|
| `git-guardrails-claude-code` | PreToolUse hook blocking `push`/`reset --hard`/`clean -f`/`branch -D` | **brana already exceeds this**: `git-discipline.md` (hard rule) + `no-attribution-commit.sh` cover force-push, `--no-verify`, attribution, worktree discipline | ✅ brana wins |
| `migrate-to-shoehorn`, `scaffold-exercises`, `setup-pre-commit` | TS-testing / course-scaffolding / Husky setup utilities | Not portable — course/tech-specific, no brana gap | N/A |

**AC check:** all 35 skills read and mapped above (18 engineering + 7 productivity + 6 in-progress + 4 misc). ✅

---

## 2. What each side is actually good at (confirmed, refined from first pass)

- **Pocock's edge is legibility**, concretely: (a) `ask-matt` is a literal ordered walkthrough of the main flow with named on-ramps and a "standalone" bucket — brana has the *ingredients* (6 Jobs table, `/brana:do`) but not the *assembled walk*; (b) the user-invoked/model-invoked split is a **native Claude Code frontmatter mechanism** (`disable-model-invocation`), not a Pocock invention — Pocock just uses it everywhere and brana uses it almost nowhere (see §3); (c) thin composition — `implement`, `grill-me`, `grill-with-docs` are 5–15 line skills that call a shared primitive (`grilling`, `tdd`), keeping each skill single-responsibility.
- **Brana's edge is enforcement + a real execution substrate**, confirmed: `validate.sh`, `spec-gate.sh`, the challenger/evaluator agents, and the backlog v3 schema (waves, AC approve, drain loop, `blocked_by` graph) have no equivalent anywhere in Pocock's repo — his tracker integration is "GitHub issues or local markdown," no gates, no evaluators, no wave/drain mechanics. This is out of scope to adopt (per the task brief) and confirmed correctly out of scope after reading the source.
- **Genuine new finding**: `wayfinder` and brana's wave-pipeline/drain-loop are closer structural cousins than the first pass suggested — both use a claim-before-work frontier over blocking-edge graphs — but they optimize for different outputs (wayfinder: *decisions*; brana waves: *shipped code*). This is worth a explicit note in brana's wave docs so nobody conflates them, not an adoption target.

---

## 3. Cross-reference against brana's own conventions — conflicts named, not papered over

**`disable-model-invocation` is not a Pocock mechanism — it's native Claude Code frontmatter, already live in brana, and already once nearly overloaded.**

- `SKILL-MECHANICS.md` (Pocock) documents it as the whole basis of his user-invoked/model-invoked split: omit it → model-invoked (agent can fire it autonomously, description stays loaded every turn); set it `true` → user-invoked-only (zero context load, only reachable by typed name).
- Brana's `docs/reference/skills.md` "Legal values" table (generated from `docs/architecture/testing-validation.md`) **does not list `disable-model-invocation` as a field at all** — it documents `status`, `growth_stage`, `group`, but not this one, despite it being live.
- **Live usage audit**: grepping all 40 `system/skills/*/SKILL.md` for `disable-model-invocation` finds exactly **one** hit — `challenge/SKILL.md`. `docs/ideas/drained/gentle-ai-adoption-ladder.md` (line 111–113) claims *two* live uses ("`challenge/SKILL.md`, `domain-driven-design/SKILL.md`") — that claim is **stale**; `domain-driven-design/SKILL.md` currently carries no such field. Flagging this as a small doc-drift finding in its own right, not something this task fixes.
- **The conflict to name explicitly**: `gentle-ai-adoption-ladder.md` §Rung 3 proposed a **new, distinct** key `mode: execute-only` specifically *to avoid overloading* `disable-model-invocation`, reasoning that the existing field already means "deliberate-invocation-only" and a second, unrelated meaning (executor-vs-orchestrator role) needed its own key. **That ladder's Rungs 2–5 (including Rung 3, where `mode: execute-only` lives) were killed** by its own Phase 0 measurement (t-2591, `churn_share=0.342` against a 0.35 kill threshold, 2026-08-01). So `mode: execute-only` is dead — good, because Proposal P2 below (§4) is about systematizing `disable-model-invocation` itself for the *invocation-mode* axis, which is a **different axis** than the killed executor-role idea and does not resurrect it. This distinction must survive into P2's implementation or it will re-litigate a decision that already has a documented kill signal.

**`writing-for-agents` vs `skill-validation-checklist.md` — complementary, not competing.** The 12-factor checklist is a compliance gate (does the skill pass 12 binary-ish checks). `writing-for-agents` is about *why* prose choices work (context load vs cognitive load, progressive disclosure, leading words, the no-op test). Neither supersedes the other; §4 P3 proposes citing the latter as the craft reference the former's item 3 ("context loading is bounded") and item 4 ("control flow is explicit") already gesture at but don't explain the mechanism for.

**No conflict found in scope**: Pocock's `research` skill and `/brana:research` do the same job at different depths — no naming or mechanism collision, brana's is a superset.

---

## 4. Improvement Proposals — scored, adopt/reject

Effort/Impact are relative within this batch, not calibrated against the wider backlog. Every ADOPT proposal became a backlog task (see §5) tagged `wave:drain-3` (existing waves 1–2 are `shipped`; a `wave-3` object with selector `tag:wave:drain-3` is not yet created — do that when ready to drain this batch). M-effort tasks will pick up DDD/TDD/SDD/Docs gates naturally through `/brana:build`'s own spec-gate and TDD-loop machinery when built — this research task is not itself a build plan, so per `m-plus-discipline-enforcement.md` no discipline stub tasks were fabricated here.

| # | Proposal | Impact | Effort | Recommendation |
|---|---|---|---|---|
| P1 | Ordered idea→ship **spine doc**, mirroring `ask-matt`'s structure (main flow, on-ramps, standalone, vocabulary-underneath) | High — fixes a real, named legibility gap; the 6 Jobs table is close but unordered | S | **ADOPT** |
| P2 | Systematize `disable-model-invocation` as an explicit, documented, audited taxonomy across all 40 skills | Medium–High — real context-load savings (every currently-model-invoked skill's description loads every turn); also closes an undocumented-field gap | M | **ADOPT** (scoped away from the killed `mode: execute-only` axis — see §3) |
| P3 | Adopt `writing-for-agents`'s prose-craft levers as a companion reference to `skill-validation-checklist.md` | Medium — quality-of-authoring lever, not urgent | S | **ADOPT** |
| P4 | Promote `/brana:do` into a full router matching `ask-matt`'s richness | Would duplicate P1's spine content in a second location | — | **REJECT** — fold into P1; `/brana:do` should point at the spine doc, not re-author it |
| P5 | Port `diagnosing-bugs`' rigor into `/brana:fix`: explicit tight-loop completion criteria, ranked-hypotheses-before-instrumentation, tagged debug-log discipline | High — bug-fix reliability is a recurring pain point class | M | **ADOPT** |
| P6 | Two-axis (Standards vs Spec) parallel-subagent code review, reported unmerged | Medium — reduces "one axis masks the other" blending in current `pr-reviewer`/`challenger` | M | **ADOPT** |
| P7 | `wizard`-style interactive-bash generator for human-only provisioning steps (credentials, dashboards, migrations) | Medium — recurring need across client/venture onboarding | M | **ADOPT** |
| P8 | `codebase-design` vocabulary + `improve-codebase-architecture` visual HTML scanner | Medium value, but needs an ADR (new shared vocabulary) and a two-skill system — real cost | L | **REJECT for this wave** — log as a P2 idea, revisit if brana's own Rust CLI architecture-health becomes a stated pain point |
| P9 | `resolving-merge-conflicts` standalone skill | Low-frequency pain (brana's worktree discipline already reduces conflict surface) | S | **REJECT** — log as idea, not worth a wave slot until conflict pain is actually observed |
| P10 | `teach` / `to-questionnaire` / `wait-what` / `grilling` primitive | Real gaps, but personal-workspace or interview-mechanic features, not skill-*system* improvements per the task's scope | — | **REJECT for this task** — future-research leads, not wave candidates |

---

## 5. Backlog tasks created (wave-3 candidates)

Six tasks created via `backlog_add`, parented to `t-2830`, tagged `skills,wave:drain-3,mattpocock-mining`. `ac_state` is `proposed` on all six — run `backlog_ac_approve` per task once reviewed, don't bulk-approve blind. No `wave-3` process object exists yet (waves 1–2 are `shipped`); create one with `selector: tag:wave:drain-3` when ready to drain this batch.

| Task | Subject | Effort | Priority | Maps to |
|---|---|---|---|---|
| t-2831 | Ordered idea→ship spine doc | S | P2 | P1 |
| t-2832 | Systematize `disable-model-invocation` taxonomy | M | P2 | P2 |
| t-2833 | Adopt `writing-for-agents` prose-craft levers | S | P3 | P3 |
| t-2834 | Port `diagnosing-bugs` rigor into `/brana:fix` | M | P2 | P5 |
| t-2835 | Two-axis (Standards vs Spec) parallel code review | M | P3 | P6 |
| t-2836 | Interactive-bash wizard generator | M | P3 | P7 |

---

## 6. Registry / follow-up notes

- No `research-sources.yaml` entry exists for `mattpocock/skills` or `aihero.dev` — not proposing one; this is a one-off skill-system comparison, not a recurring-cadence source (no ongoing "check for updates" value the way a framework doc would have).
- Doc-drift finding (§3): `docs/ideas/drained/gentle-ai-adoption-ladder.md` line ~111 misstates that `domain-driven-design/SKILL.md` carries `disable-model-invocation: true` — it does not, as of 2026-08-13. Worth a small correction pass next time that doc is touched; not fixed here (out of this task's scope — it's an ideas doc, not authoritative).

---

## 7. Integration model — depend, don't fork (added 2026-08-14)

Decision direction from the follow-up studio session (feeds t-2838; supersedes any read of §4 as "copy his content"):

**Three modes, per skill:**

1. **DEPEND** — install his plugin verbatim, **pinned**, wrapped by ~10-line brana adapter skills that map inputs (tasks.json/context vocab → his expectations) and route output artifacts to brana homes. Applies to the artifact-shaped organs: `grilling`, `tdd`, `diagnosing-bugs`, `writing-for-agents`, `wizard`, `resolving-merge-conflicts`, `prototype`. This is his own thin-composition pattern with the organ upstream — we inherit his updates and versioning instead of maintaining drifted copies.
2. **ADAPT** — his *idea* applied to our machinery, nothing to import: spine doc (t-2831), `disable-model-invocation` taxonomy (t-2832), two-axis review in our reviewer agents (t-2835).
3. **SKIP** — ours is a superset (`research`, `handoff`, git-guardrails) or his is stack-coupled (TS/Husky misc tier).

**Update discipline (non-negotiable):** upstream skills are prompt-code executing inside our agent — an unpinned dependency lets upstream change our organs' behavior unreviewed. So: pin the version · a release-watch gauge surfaces new versions with diffs in the cockpit digest · a human valve approves the bump. Updates are queue items through a valve, never auto-pulls.

**Open gate:** verify the repo's license permits this usage before shipping any wrapper.
