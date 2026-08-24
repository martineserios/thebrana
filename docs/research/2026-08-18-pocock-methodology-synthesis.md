# Pocock Methodology Synthesis — Public Content vs. brana's Core Five

**Date:** 2026-08-17 (research pass) / 2026-08-18 (promoted from scratch) | **Task:** t-2838 follow-up to t-2830 | **Scope:** Matt Pocock's public teaching content (search-only pass — X, aihero.dev, third-party analysis), cross-referenced against t-2830 (skill-file reading), t-2838 (5-pillar KEEP-SPINE map), wave-pipeline.md, and ADR-084.

**Method:** WebSearch (4 queries) + WebFetch (3 pages: aihero.dev/5-agent-skills-i-use-every-day, aihero.dev/skills, a third-party comparison piece). No YouTube transcript or LinkedIn content was directly fetchable within this pass's budget — search results surfaced enough X/aihero.dev quotes to ground every claim below in his own words or a close paraphrase.

---

## 1. What's genuinely new here (not in t-2830)

t-2830 read his skill files verbatim — the *mechanics*. This pass adds the *why*, from his own public statements:

- **His core framing for why any of this exists:** "You have access to a fleet of middling to good engineers that you can deploy at any time. But these engineers have a critical flaw: they have no memory." Skills exist to compensate for statelessness, not to add process for its own sake.
- **The daily sequence, in his own words:** `/grill-me` → `/write-a-prd`(`to-spec`) → `/prd-to-issues`(`to-tickets`) → `/tdd` → `/improve-my-codebase`(`improve-codebase-architecture`) — a chain where "each one's output is the next one's input, so the whole workflow gets better as you tune single steps." `improve-codebase-architecture` is used *daily*, not occasionally — t-2830 §4 P8 rejected it as one-off tooling; his own practice treats it as a standing habit. Worth noting, doesn't change the reject (still no observed brana pain point).
- **Explicit critique target, more precise than the README line already in t-2830:** he critiques frameworks that "own the process" — meaning frameworks that make the process *opaque*, taking control away from the developer and making bugs in the process itself hard to resolve. He names GSD, BMAD, Spec-Kit. This is a critique of **process opacity**, not of **verification depth**. Important distinction for §3 below.
- **A real, stated technical disagreement:** a third-party comparison piece reports Pocock argues *refactoring belongs in code review, not the red-green-refactor loop* — splitting TDD's third step out of the implementation loop entirely. This directly contradicts how both competing frameworks (and brana's own `sdd-tdd.md`) bundle red-green-refactor as one atomic cycle. Genuine, specific, actionable disagreement — flagged in §3.
- **"Agent context as a scarce budget"** is the stated reason for his user-invoked/model-invoked split — nearly verbatim brana's own `context-budget.md` framing. Independent convergence, not new information about brana, but useful confirmation the two systems are reasoning from the same constraint.
- **Economy of prose as a design principle, demonstrated not just asserted:** `/grill-me` is "only three sentences long, but... incredibly impactful" — "skills don't have to be long to be impactful, you just need to choose the right words at the right time." This is the same claim `writing-for-agents` makes structurally; here it's demonstrated with a real example, reinforcing (not changing) t-2833's already-shipped ADAPT verdict.
- **A third-party framing worth taking seriously:** one comparison piece places Pocock at the *lightest-weight, most composable* end of a spectrum running toward "opinionated" frameworks — explicitly lighter than even the "Superpowers" and "Agent Skills" alternatives it compares him against. This matters directly for §3's verdict on `challenge`.

---

## 2. Per-skill verdict: does his methodology change the circuit, or confirm KEEP-SPINE?

t-2838's 2026-08-14 studio map already classified `brainstorm, build, close, sitrep, challenge` as **KEEP-SPINE** — core, right position, refactor-don't-replace, grounded in 30-day telemetry (860 invocations, 67% concentrated in backlog+build). Testing each against what this pass found:

### brainstorm — **KEEP-SPINE confirmed, one specific internal discipline worth adopting**

Pocock's `grilling` is narrower than brainstorm (alignment-before-plan only, not full explore/research/shape), so it's not a circuit replacement — brana's brainstorm is already the superset in scope, as t-2830 found. But his specific critique is sharp and actionable: *"Claude Code tends to spit out a plan really early when in plan mode, creating a document before we've truly understood each other."* His `grill-me` exists specifically to hard-block artifact creation until shared understanding is confirmed. Worth checking honestly: does brana's brainstorm actually enforce that gate as strictly, or does it let the conversation drift into drafting before alignment is confirmed? This is a real, narrow, testable improvement — not a reason to swap circuits.

### build — **KEEP-SPINE confirmed, reinforces an already-known gap, surfaces one real disagreement to weigh**

The vertical-slice/tracer-bullet framing ("cutting through all integration layers... surfaces unknown unknowns early") is the same `expand-contract` gap t-2830 already named as unclaimed (no task filed). Nothing new here beyond reinforcement.

The TDD-refactor-in-code-review disagreement (§1) is new and genuinely worth debating: brana's `sdd-tdd.md` treats red-green-**refactor** as one inline loop; Pocock's stated practice splits refactor out to the review stage. This is a real methodological fork, not a naming difference — but it's a content change to the TDD discipline, not a circuit-level rewrite of `build`. Flagged as a scored candidate in §4, not adopted here.

### close — **KEEP-SPINE confirmed, no new evidence**

Nothing in this pass surfaces a close/handoff discipline richer than what t-2830 already found (`handoff` is narrower than brana's `close --continue`, which also does pattern extraction and doc-drift detection). No change.

### sitrep — **KEEP-SPINE confirmed, no upstream equivalent exists**

No skill in Pocock's public catalog does session-reorientation the way `sitrep` does; `wait-what` (re-explaining the last message) was already correctly identified as a different job. Nothing in the public content changes this.

### challenge — **KEEP-SPINE confirmed, and the public content argues *against* importing his model here specifically**

This is the clearest finding of the pass. The third-party comparison explicitly places Pocock at the lightest-weight end of the spectrum — thin, composable, developer-controls-everything, no dedicated adversarial-review substrate comparable to brana's evaluator+challenger system. His `code-review` skill (already the ADR-084 pilot-gated vendor target, `t-2835`) is the closest analog, and ADR-084 already drew the correct boundary: `code-review` is post-diff review, `challenge` is pre-commitment architecture stress-testing — different jobs, not overlapping.

Crucially, his stated critique target — frameworks that "own the process" and "take away control" — is about **opacity**, not about **verification depth**. Brana's heavier evaluator/challenger/wave substrate keeps the developer fully in the loop (visible findings, explicit approval gates, no black-box automation) — it doesn't fall under his own critique. If anything, this pass's evidence argues brana's heavier verification layer is a deliberate, defensible differentiator from his lighter-weight model, not overhead his own reasoning would tell us to strip.

---

## 3. Headline verdict

**Confirm KEEP-SPINE.** Nothing in Pocock's public philosophy — beyond what t-2830's skill-file reading and t-2838's telemetry-grounded map already captured — makes a case that brana's core five (`brainstorm, build, close, sitrep, challenge`) are structurally wrong in a way internal refactoring can't fix. His own stated critique target (opaque, process-owning frameworks) doesn't apply to brana's transparent, human-gated substrate. ADR-084's pilot-only, artifact-scoped vendoring stance (diagnosing-bugs → `/brana:fix`, gated) remains the right-sized response — this pass found no evidence for a bigger move.

The one place this pass surfaces a genuine, specific, *not-yet-settled* disagreement worth the user's attention is the TDD-refactor-placement split (§2 build, §4 below) — that's a real fork in practice, not a naming quirk, and deserves an explicit decision rather than silent inheritance of brana's current assumption.

---

## 4. Scored recommendations — new from this pass only (not re-listing t-2830's P1–P10)

| # | Proposal | Impact | Effort | Recommendation |
|---|---|---|---|---|
| N1 | Audit brainstorm's SPECIFY-gate: does it hard-block artifact creation until shared understanding is confirmed, the way `grill-me` does? If not, tighten it. | Medium — closes a real, specific process gap Pocock names explicitly (premature-plan-drafting) | S | **ADOPT** — narrow, testable, doesn't touch circuit shape |
| N2 | Decide explicitly whether brana's TDD discipline (`sdd-tdd.md`) should split "refactor" out of the inline red-green-refactor loop into the review/challenge stage, per Pocock's stated practice | Medium-High if right — changes where structural cleanup happens and who reviews it; also a real risk if wrong (refactor deferred = code review scope creep) | M (needs a trial, not a blind swap) | **INVESTIGATE, don't adopt blind** — genuine disagreement with current practice, worth a small spike/trial on 2-3 tasks before deciding, not silent inheritance either way |
| N3 | No action on `challenge` — public evidence argues brana's heavier substrate is a deliberate differentiator, not overhead | — | — | **CONFIRM AS-IS**, explicitly logged so this doesn't get re-litigated without new evidence |

---

## 5. Sources

- [aihero.dev/5-agent-skills-i-use-every-day](https://www.aihero.dev/5-agent-skills-i-use-every-day)
- [aihero.dev/skills](https://www.aihero.dev/skills)
- [dev.to — Superpowers vs Agent Skills vs Pocock](https://dev.to/jamilxt/superpowers-vs-agent-skills-vs-pocock-three-philosophies-of-ai-coding-workflows-e6n)
- [x.com/mattpocockuk — 5 skills he uses every day](https://x.com/mattpocockuk/status/2033647563627212953)
- [x.com/mattpocockuk — writing-for-agents used beyond skill-writing](https://x.com/mattpocockuk/status/2074218527884464523)
- [x.com/mattpocockuk — grill-me virality](https://x.com/mattpocockuk/status/2036076132924100760)
- [x.com/mattpocockuk — v1 release notes, model/user-invoked split](https://x.com/mattpocockuk/status/2067259590488510471)
- [github.com/mattpocock/skills](https://github.com/mattpocock/skills) (README, cross-checked against t-2830's direct file reads)


---

## 6. Addendum (2026-08-18) — loops and graphs in his public content

Correction to §1: the skill-file reading under-reported this. In his public content he explicitly:
- popularizes the **Ralph loop** — agent in a bash loop, autonomously pulling issues from the backlog and committing to branches ("come back to a stack of PRs"); the same RALPH lineage `brana-knowledge/dimensions/60-agent-loop-architecture.md` traces — an *independent* citation of the same ancestor, stronger convergence evidence than structural similarity;
- frames `to-tickets`/`prd-to-issues` output as a **parallelizable DAG** — tickets with blocking edges, two tasks with no shared dependency grabbable by separate agents;
- names a context "smart zone" ending ~140K tokens (independent confirmation of `context-budget.md`'s constraint).

Sources: talksintel.ai AIE-EU-2026 walkthrough · blog.alexrusin.com (main flow; agentic pipeline) · richsnapp.com "next iteration of Ralph" · explainx.ai loop-engineering.

## 7. Addendum (2026-08-18) — the tracker seam, read at v1.2.3

`to-tickets` publishes to "the configured tracker": `/setup-matt-pocock-skills` writes `docs/agents/issue-tracker.md` (GitHub via `gh` with native issue dependencies · GitLab via `glab` · local `.scratch/<feature>/issues/NN-<slug>.md` · **Other = freeform prose describing your workflow**). Ticket = title · what-to-build (end-to-end, no file paths) · AC checkboxes · Blocked by · Status. Readiness = one label `ready-for-agent`; five roles. Frontier = open ∧ **unblocked** ∧ unclaimed; claim = first write; resolve = answer + close + *gist+link* to the map. brana backlog fits the "Other" slot; concept map ticket→task, Blocked by→blocked_by, ready-for-agent→ac_state:approved∧¬parked∧wave, frontier→wave_pull_decision (which today ignores blocked_by — the one place his loop is stricter), comments→context dated appends, map→epic node.
