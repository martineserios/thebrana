# Idea → Ship: The Skill Flow

> Companion to [The Brana](the-brana.md) (what it is — read that first) and [Skills Architecture](skills.md) (the parts) and the [6 Jobs table](../../.claude/CLAUDE.md#the-6-jobs) (the ingredients, unordered). This is the walk.

You don't remember all 40 skills, so here's the route. Most work travels one **main flow**; two **on-ramps** merge onto it. Codebase upkeep runs alongside it, not on it. Everything else is **standalone**, or a **vocabulary layer** underneath. Structure mirrors [mattpocock/skills](https://github.com/mattpocock/skills)' `ask-matt` — see [t-2830 research](../research/2026-08-13-matt-pocock-skill-system.md) §1, §4 P1 for the source comparison and why this doc adapts rather than imports it (§7: ADAPT, not DEPEND).

## The main flow: idea → ship

1. **[`/brana:brainstorm`](../../system/skills/brainstorm/SKILL.md)** — sharpen the idea through interactive exploration: research, discuss, shape into something actionable. Reach for **[`/brana:decide`](../../system/skills/decide/SKILL.md)** instead when the fork isn't "what is this" but "which of these."
2. **Branch — can you settle every question in conversation?** If a question needs a runnable answer, detour: **[`/brana:build`](../../system/skills/build/SKILL.md)** auto-detects `spike` strategy from language like "can we", "try", "prototype" (see its [phases/strategies.md](../../system/skills/build/phases/strategies.md) QUESTION → EXPERIMENT → ANSWER sequence). The spike's findings become the next `/brana:build`'s SPECIFY context when it graduates to a feature — see [build's Task Integration](../../system/skills/build/phases/classify.md#task-integration): "Strategy transitions create linked tasks."
3. **Branch — is this a multi-session build (Medium+ effort)?**
   - **Yes** → **[`/brana:backlog`](../../system/skills/backlog/SKILL.md)** `plan` turns the thread into an ordered task tree with `blocked_by` edges (the tracer-bullet-ticket equivalent), then `start <id>` per task — each one entering `/brana:build` in its own worktree, one TDD slice at a time. For a genuinely large, foggy effort, this is where the on-ramp below feeds in.
   - **No** → **[`/brana:build`](../../system/skills/build/SKILL.md)** directly, in the same context window: SPECIFY (light) → BUILD → CLOSE.

   Either way, `/brana:build`'s BUILD loop drives red-green-refactor per [sdd-tdd.md](../../system/rules/sdd-tdd.md), then runs whichever of its verification gates apply to the build's size and strategy (ISC, BUILD→CLOSE, Four Questions, evaluator, challenger — see [phases/verify-gates.md](../../system/skills/build/phases/verify-gates.md); most are size- or AC-gated, not unconditional), plus `/brana:docs` before CLOSE. Brana ships no standalone `/tdd` or `/code-review` skill of its own the way Pocock's flow has one — that discipline is folded into `/brana:build`'s BUILD and gates steps, not separately invocable (Claude Code's own built-in `/code-review` command is a different, harness-level thing).

   CLOSE merges to `dev` — the integration buffer, not live (ADR-060). **Shipping** — `dev`→`main` promotion plus deploy — is a separate, human-gated, periodic step: CLOSE's own step 14, or **[`/brana:ship`](../../system/skills/ship/SKILL.md)** for the richer pre-flight/verify path. That's the "ship" this doc's title promises; it's deliberately decoupled from any one build.

### Context hygiene

Keep the brainstorm → plan → first build in one unbroken context window where possible — the [context-budget](../../system/rules/context-budget.md) thresholds (55/70/85%) tell you when to `/compact` at a phase boundary instead of pushing on degraded. **[`/brana:close`](../../system/skills/close/SKILL.md)`--continue`** is brana's handoff: a portable state snapshot for a new session, a new worktree, or context recovery — reach for it at a genuine boundary, not mid-phase.

## On-ramps

Situations that generate work, then merge onto the main flow.

- **Bugs and requests piling up** → **[`/brana:backlog`](../../system/skills/backlog/SKILL.md)` triage`** — research-informed priority reassessment over raw incoming issues. Tasks that `/brana:backlog plan` already produced are agent-ready; don't re-triage them.
- **Something's broken** → **[`/brana:fix`](../../system/skills/fix/SKILL.md)** — reproduce (failing test) → diagnose → fix (minimal change) → verify → commit. Lighter-grained than Pocock's `diagnosing-bugs` (no explicit tight-loop completion criteria or ranked-hypothesis step yet — see [t-2830 research](../research/2026-08-13-matt-pocock-skill-system.md) P5, tracked as t-2834).
- **A huge, foggy effort** — bigger than one session's SPECIFY can hold → this is what main-flow step 3's "Yes" branch looks like for genuinely large, architectural work: the validated 8-step methodology in [ARCHITECTURE.md](../reflections/ARCHITECTURE.md)'s 2026-04-14 field note. (1) `/brana:brainstorm` deep — freeform investigation. (2) `/brana:challenge` round 1. (3) reshape. (4) `/brana:challenge` round 2 (premortem + simplicity). (5) address the findings. (6) `/brana:backlog plan` with the full task hierarchy. (7) wire DDD/SDD/test/docs lifecycle tasks *before* every implementation task. (8) integrate updates to every affected command or workflow. Steps 7 and 8 are the ones a shorter retelling drops first — and the source is explicit that dropping them is exactly how specs ship without tests and adjacent commands drift silently, so don't. For work that's already decomposed and draining as a batch, the wave/drain-loop ([ADR-079](decisions/ADR-079-backlog-drain-loop-handoff.md), [ADR-080](decisions/ADR-080-plan-time-wave-graphs-epic-runner.md)) is a structural cousin of Pocock's `wayfinder` — both run a claim-before-work frontier over a blocking-edge graph — but brana's waves drain **shipped code**, not **decision tickets**; don't conflate the two (see [t-2830 research](../research/2026-08-13-matt-pocock-skill-system.md) §2).

## Maintain

Not feature work — upkeep that runs alongside the main flow, not on it.

- **[`/brana:reconcile`](../../system/skills/reconcile/SKILL.md)** — drift detection, security checks, cascade spec propagation, knowledge hygiene, scoped via `--scope`.
- **[`/brana:verify-docs`](../../system/skills/verify-docs/SKILL.md)** — periodic doc verification: `validate.sh` structural check plus sampled semantic review. Run quarterly.

## Vocabulary underneath

Reach for these directly when the **words**, not the process, are the problem — or let the skills above pull them in.

- **[`/brana:domain-driven-design`](../../system/skills/domain-driven-design/SKILL.md)** — entities, value objects, aggregates, bounded contexts. `/brana:build`'s DDD gate (when `docs/domain/` exists) draws on this vocabulary.

Pocock's `codebase-design` (module/interface/depth/seam/adapter/leverage/locality — the shared vocabulary for a module's *shape*) has no brana counterpart yet. Logged as [t-2830 research](../research/2026-08-13-matt-pocock-skill-system.md) P8, rejected for this wave (needs its own ADR) — named here as an honest gap, not filled in.

## Standalone

Off the main flow entirely — reach for these on their own terms.

- **[`/brana:research`](../../system/skills/research/SKILL.md)** — background reading against primary sources, cited findings left as a Markdown file. Feeds `/brana:brainstorm`; doesn't replace it.
- **[`/brana:challenge`](../../system/skills/challenge/SKILL.md)** — adversarial review of a plan or decision. Callable at any point in the main flow, not just at SPECIFY.
- **[`/brana:decide`](../../system/skills/decide/SKILL.md)** — criteria, scenarios, patterns, recommendation for a standing choice.
- **[`/brana:sitrep`](../../system/skills/sitrep/SKILL.md)** — the corrective for "wait, what was I doing" — context recovery after compression or confusion.
- **[`/brana:retrospective`](../../system/skills/retrospective/SKILL.md)** — capture a learning and route it through the memory taxonomy (rule / decision / reference / pattern / knowledge / session).
- **[`/brana:memory`](../../system/skills/memory/SKILL.md)** — recall, cross-client pollination, and knowledge-base audits.
- **[`/brana:log`](../../system/skills/log/SKILL.md)** — append-only capture for events: links, calls, meetings, ideas.
- **[`/brana:claudemd`](../../system/skills/claudemd/SKILL.md)** — audit or generate a project's `CLAUDE.md`.
- **[`/brana:acquire-skills`](../../system/skills/acquire-skills/SKILL.md)** — find and install a skill for a tech or reasoning gap. `/brana:build`'s LOAD step reaches for this when it detects a tech stack (Rust, Python, TypeScript, Shell, Supabase, …) with no matching skill loaded — see its [phases/load.md](../../system/skills/build/phases/load.md) step 4a.

Domain-specific tech skills (`rust-skills`, `impeccable`, `design-system`, `web-design-guidelines`, …), utility skills (`gsheets`, `export-pdf`, `scheduler`, `meta-templates`), and venture skills (`review`, `client-retire` — the GROW job) sit outside this idea-to-ship code narrative entirely; the full catalog is [Skill Reference](../reference/skills.md).

## Precondition

**[`/brana:onboard`](../../system/skills/onboard/SKILL.md)** (existing project) or **[`/brana:align`](../../system/skills/align/SKILL.md)** (bring a project up to brana practices) — run before the first engineering flow in a new project or client.
