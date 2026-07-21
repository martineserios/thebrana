# Skills-as-Loops — First-Pass Primitive Audit (preview)

Source: /home/martineserios/enter_thebrana/thebrana/system/skills/ (frontmatter + intro read; bodies read for challenge/reconcile/verify-docs/close/decide/review).
Palette: skill · workflow · loop · goal · agent · (compose / retire).

## Scope note
34 first-party brana skills in system/skills/*. A separate `acquired/` dir holds ~25 third-party
packs (first-principles, inversion, six-hats, decision-matrix, ddd, fastapi, supabase, vitest, web-design…).
Those are **reference/knowledge skills** — human-invoked, judgment-led, no queue. They ALL stay skills
and are not really part of the behavior-refactor surface. I classify only the 34 first-party skills.

## Classification table (34 first-party skills)

| skill | what it does | current form | proposed | rationale |
|---|---|---|---|---|
| acquire-skills | find+install skills for a gap | recipe (search→install) | skill | human-invoked once per gap; judgment (which to install) |
| align | align a project to brana practices | procedure assess→plan→impl→verify | skill (loop-lean) | judgment-heavy; the impl-over-gaps middle is loop-shaped but run once per project |
| backlog | task CRUD, roadmap, planning | recipe/CRUD | skill | the queue *substrate*, not a drainer; human plans against it |
| bash-defensive-patterns | shell hardening reference | reference | skill (ref) | knowledge pack, quarantined acquired |
| brainstorm | idea maturation, rounds+exit gate | human-stop loop | skill | seed says keep — human stop condition IS the design; gets exit-router |
| build | unified dev command (one task→AC+validate) | already task-loop | compose (loop-shaped skill) | seed: "build = task loop"; drain-wrapper (wave) is the new loop, don't rebuild the driver |
| cargo-machete | remove unused Rust deps | tool wrapper | loop | mechanical + verifiable (compiles); the Dependency-Sweeper loop in the seed table |
| challenge | adversarial review, N lenses | **already fans out→verify→synthesize** | workflow | textbook workflow; deep mode already calls verify-findings |
| claudemd | audit/generate CLAUDE.md | recipe | skill | human-invoked, judgment |
| client-retire | archive a client's patterns | one-shot procedure | skill | run once per retire; judgment |
| close | session end: extract→handoff→patterns→drift | phased skill that enqueues nightly extraction | compose (skill→loop) | orchestration=skill; extraction=LEARN loop producer (already spawns) |
| decide | one-sentence-in, one-rec-out; routes to frameworks | router recipe | skill | NO fan-out in core path; human judgment — refutes "shared workflow with challenge" |
| discover | list installed skills/agents/hooks | read-only inventory | skill | trivial; could fold into a `catalog` util |
| do | alias for `backlog start` | router | **retire→backlog** | its own description says use backlog start directly |
| docs | generate/update living docs; "composable building block" | building block | compose (loop-lean) | invoked BY close/others; changelog-drafter drain candidate |
| domain-driven-design | DDD pattern reference | reference | skill (ref) | acquired knowledge pack |
| export-pdf | md→pdf | tool wrapper | skill (util) | trivial utility |
| fix | repro(test)→diagnose→fix→verify→commit | already task-loop w/ repro verifier | compose (loop-body) | seed: fix=task loop; becomes body of the bug-drain wave |
| gemini | delegate to agy (Gemini worker) | delegation wrapper | agent (compose) | this IS the agent primitive wrapped as a skill |
| gsheets | Google Sheets MCP ops | utility | skill (util) | CRUD over an external service |
| log | append-only event capture, bulk mode | capture utility | skill | feeds inbox/triage loop but itself is capture |
| mcp-builder | how to build MCP servers | reference | skill (ref) | knowledge pack |
| memory | recall / pollinate / audit-docs | mixed | compose | recall=retrieval; audit=drain-over-docs (loop-lean) |
| meta-templates | WhatsApp template mgmt | client utility | skill (util) | external-service CRUD |
| onboard | scan/diagnose or scaffold a project | recipe | skill | human-invoked, judgment |
| plugin | CC plugin registry mgmt | utility | skill (util) | CRUD |
| reconcile | drift/security/propagation/knowledge maintenance | batch scanner, human-invoked | **loop** | prime drain-until-done; findings queue + verifiers already conceptual |
| research | research topic: fan-out sources→verify→findings | fork context, fan-out | workflow | parallels deep-research; fan-out+verify+synthesize shape |
| retrospective | store one learning, classify+route | single-item classify | compose (loop-body) | the per-item body of the LEARN loop |
| review | business health, weekly/monthly cadence | phased skill, spawns metrics agent | skill (cadence/scheduled) | cadence-driven; different domain from challenge — collides on name only |
| rust-skills | 179 Rust rules reference | reference | skill (ref) | knowledge pack |
| scheduler | manage cron/remote agent jobs | infra mgmt | skill | this is the *loop scheduling infrastructure*, meta to the palette |
| ship | preflight→deploy→verify→monitor | pipeline | skill (goal-lean) | verifiable end-state (shipped+green) = a goal, but human-gated release; stays skill |
| sitrep | situational awareness / context recovery | read-only orientation | skill | trivial recovery recipe |
| verify-docs | no-LLM structural drift-evidence collector | sensor | **merge→reconcile** | explicitly feeds reconcile propagation/knowledge; it's reconcile's sensor/verifier |

## Merge candidates (hypotheses TESTED)

**A. reconcile / verify-docs / repo-cleanup → one drain loop — PARTIAL.**
- verify-docs → **merge into reconcile** as its sensor phase (no-LLM structural check feeding propagation/knowledge scopes). Clean merge, −1.
- repo-cleanup → **stays a distinct loop**; it drains the *git working tree* (uncommitted spec changes), a different queue than reconcile's *spec-vs-impl drift*. Shares the drain-core, does not merge.
- Verdict: one merge (verify-docs), two sibling drain loops sharing machinery.

**B. challenge / review / decide → shared workflow core — REFUTED (mostly).**
- challenge = the workflow (already fans out→verify→synthesize). It IS the shared core, but there's nothing to share it with.
- decide = lightweight human-judgment router (no parallel agents in core path) → stays skill.
- review = cadence business-health skill, unrelated domain → stays skill / scheduled.
- Verdict: name collision, not primitive overlap. No 3-way merge.

**C. Extra merge/retire found:** `do` → retire into `backlog start` (self-declared alias). `discover`/`sitrep`/`export-pdf`/`plugin`/`gsheets`/`meta-templates` are thin utilities that could collapse into fewer "util" surfaces but each serves a real distinct job — low-value churn, leave them.

## Counts (34 first-party)
- stay skill: 22 (incl. 3 reference packs, 6 utilities, ship goal-lean, review cadence)
- → workflow: 2 (challenge, research)
- → loop (standalone): 2 (reconcile, cargo-machete)
- compose (loop-shaped skill / loop-body / agent-wrapper): 6 (build, fix, close, docs, memory, retrospective) + gemini(agent) = 7
- retire/merge: 2 (do→backlog, verify-docs→reconcile)

Net top-level surface: 34 → ~32 (−2 hard). Loops don't reduce count (reconcile stays one entry, just autonomous).

## Verdict
Net-reduction hypothesis holds only **weakly**: ~2 hard retires, not a dramatic shrink. The real
payoff is *conceptual* (fewer primitive-types to reason about, drain-machinery reused) not fewer
menu entries. **Genuinely 2 skills want to BE standalone loops (reconcile, cargo-machete/dep-sweep);
~4 more are loop-BODIES that feed new drain waves (fix→bug-drain, close-extraction→LEARN,
docs→changelog, backlog→AC-backfill).** Most skills correctly stay skills — human-judgment,
reference, and utility work has no queue to drain. Honest read: this is a re-derivation that
reclassifies ~10 behaviors and retires ~2, not a surface-halving refactor. The seed's own
challenge/review/decide merge was wrong; test hypotheses against shape, not shared vocabulary.
