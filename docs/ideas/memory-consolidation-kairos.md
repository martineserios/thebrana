# Memory Consolidation — Lint + Heal Shape

> Brainstormed 2026-04-08. **Reframed 2026-04-09** around Karpathy's Lint + Heal methodology, after user clarified the Layer 1 / Layer 2 distinction.
> Status: **shape / brainstorm only — no implementation.**
> Upstream findings: [`../research/2026-04-08-cc-alignment-findings.md`](../research/2026-04-08-cc-alignment-findings.md) §D2 + second addendum.
> Related prior work: [`resilient-pattern-store.md`](./resilient-pattern-store.md), [`ruflo-native-integration.md`](./ruflo-native-integration.md).
> Companion shape doc: [`inbox-to-dimensions-pipeline.md`](./inbox-to-dimensions-pipeline.md) — the pipeline that feeds the knowledge base that this job cleans.
> See also: [`feedback_layer1-vs-layer2.md`](~/.claude/projects/-home-martineserios-enter-thebrana-thebrana/memory/feedback_layer1-vs-layer2.md) — the distinction that motivated the reframe.

## Problem

Brana accumulates Layer 2 knowledge — patterns, dimensions, research notes, field notes, session snapshots — across sessions. Current consolidation is *manual* and *reactive*:
- `/brana:close` writes new patterns to MEMORY.md and pattern files, but never deduplicates, merges, or prunes existing entries
- `/brana:retrospective` is user-initiated, not scheduled
- `/brana:reconcile` and `/brana:maintain-specs` exist but are user-triggered, not ambient
- MEMORY.md growth is monitored by a line count rule, not a content rule
- Ruflo (the semantic memory layer) is fragile — see `feedback_complexity-audit.md`: *"accretion > architecture as the real problem"*

**Scope clarification (Layer 1 / Layer 2):** This job operates **only on Layer 2 content** — the LLM-authored work product. It does not touch Layer 1 (brana OS) artifacts: CLAUDE.md, rules, hooks.json, ADR decisions, skill frontmatter, CLI source, MEMORY.md "User Preferences — CRITICAL" section. Those stay pinned.

The user's chosen methodology for Layer 2 is Karpathy's **"Lint + Heal"** pattern — a scheduled, deterministic-to-LLM-augmented maintenance layer that finds inconsistencies, imputes missing info, suggests new articles, and uses web search to fill gaps. The question is not whether to build it (the user has chosen this methodology). The question is **at what depth** brana OS should enforce the Lint + Heal workflow.

The old framing of this doc — "should brana speculatively build toward CC's unreleased Kairos?" — is retired. Karpathy is a named primary source for the methodology; we're no longer guessing at Anthropic's flag-gated code.

## What the methodology actually tells us

### From Karpathy (primary — the chosen methodology)

Karpathy's infographic names **Lint + Heal** as a support-layer box in his Living Knowledge Base pipeline. Four capabilities, all described:

1. **Find inconsistent data** — surface contradictions between related notes
2. **Impute missing info** — fill in structural gaps (missing metadata, incomplete entries)
3. **Suggest new articles** — when a concept is referenced repeatedly but not documented, propose a new article
4. **Web search to fill gaps** — when the existing corpus can't answer a question, search and cite

Context: *"all connected to the wiki"* — Lint + Heal reads the whole wiki and writes back into it. It runs in the support layer, below the main pipeline, ambient and scheduled.

Karpathy's framing of the whole system: *"You never write the wiki. The LLM writes everything. You just steer — every answer compounds."* Under the Layer 1 / Layer 2 split, this applies to Layer 2 only — exactly what this job operates on.

### From CC (secondary — corroborating context)

The leak analysis [REPORTED] that Anthropic has built **Kairos** (an always-on background daemon) and **autoDream** (the consolidation logic inside it). autoDream's described goals: *"merge duplicate memories, eliminate contradictions, resolve speculations, prune memory to make stored data more suitable for action."*

**Not verified** — no one has quoted code for any of: trigger conditions, storage format, or algorithm. Both features are flag-gated off in the published build.

**Implication:** CC's Kairos is a *second source* pointing at the same methodology, not the *primary* source. If it ships in a future CC release and looks different from Karpathy's framing, brana's Lint + Heal job stays valid — it was built against Karpathy, not CC.

### From the Aum post (tertiary — pattern-level corroboration)

The Aum "12 Agentic Harness Patterns" post names **Pattern 4: Dream Consolidation** with the description *"background processes clean stale memory by deduplicating, pruning, and resolving contradictions automatically during idle periods."* Three independent community sources (Karpathy, Cathedral.ai, Aum) converge on the concept. Implementation details still vary. Concept is stable.

### What this means for the shape

The **direction** is well-supported (multiple independent sources, named primary source, clearly scoped to Layer 2). The **depth** is the open question: how much of Karpathy's four-capability list does brana OS enforce? That's what the options below resolve.

## The four sub-decisions inside Lint + Heal

Before comparing options, the four Karpathy capabilities each have an independent design choice. The options below are *combinations* of these sub-decisions.

### SD1 — Contradiction finding

**Question:** How does Lint + Heal know two Layer 2 entries contradict each other?

| Approach | What it looks like | Cost | False-positive profile |
|---|---|---|---|
| **Deterministic (grep-based)** | Look for opposite keyword pairs, identical `name:` frontmatter across files, conflicting numeric fields (e.g., different `confidence:` values for same pattern). No LLM. | Zero token cost, fast | Misses semantic contradictions ("prefer X" vs "avoid X" in different wording); low false-positive rate on matches |
| **LLM-semantic** | Feed clusters of related pattern files to the LLM, ask "do any of these contradict each other?" | Token cost per run, slower | Catches semantic contradictions; risk of hallucinated contradictions; non-deterministic |
| **Hybrid** | Grep finds candidates, LLM adjudicates only on candidates | Low-to-medium token cost | Best of both; more code to write |

### SD2 — Imputation

**Question:** When Lint + Heal finds a Layer 2 entry with missing data, does it fill in the gap?

| Scope | What it writes | Risk |
|---|---|---|
| **Nothing (read-only lint)** | Surface the gap in a report, human fills in | Very low |
| **Frontmatter only** | Fill in missing `name:` / `description:` / `type:` / `confidence:` fields from content heuristics (grep first line, count words, etc.) — no LLM | Low — deterministic rules, archivable |
| **Content** | LLM fills in missing paragraphs, examples, cross-references | Medium — LLM may invent; needs dry-run + rollback |

### SD3 — Web search to fill gaps

**Question:** When a Q&A over the wiki can't answer a question, does Lint + Heal search the web and add a citation-backed answer?

| Scope | Behavior | Cost |
|---|---|---|
| **None** | Q&A returns "don't know"; human decides whether to research | Zero |
| **Budgeted search** | Lint + Heal runs ≤N web searches per scheduled cycle, writes findings as `docs/research/auto-YYYY-MM-DD-*.md` draft files for review | Token + search API cost per run |

### SD4 — New article suggestion / promotion

**Question:** When Lint + Heal notices a concept referenced repeatedly but not documented, what does it do?

| Response | What it produces |
|---|---|
| **Nothing** | Ignores the pattern |
| **Surface only** | Reports "concept X is referenced in 7 places but has no dimension doc" in the weekly maintenance log |
| **Draft-only** | Generates a draft dimension doc with `status: draft` frontmatter, drops in `brana-knowledge/dimensions/` (or a staging directory) for human review at milestones |

---

## Proposed shape (four depth layers)

Each layer is a superset of the previous. L0 is the control (do nothing). L4 is Karpathy's full vision. Each layer turns on more of the sub-decisions above.

### L0 — Do nothing (control / reference point)

**Purpose:** Keep as comparison baseline. Not a real option the user picks — they've already chosen Karpathy's methodology. Included so the cost/benefit of each layer is measurable.

**What happens if we pick L0:** Layer 2 knowledge keeps growing manually. `/brana:close` and `/brana:retrospective` continue doing the work they do today. No scheduled maintenance.

**Cost:** 0 hours, 0 tokens. Status quo.

### L1 — Deterministic dedup (stepping stone)

**Sub-decisions:** SD1 = none, SD2 = none, SD3 = none, SD4 = none. Just dedup.

**What:** The original Option B from the previous version of this doc. Weekly scheduled job that lists all `feedback_*.md` and `project_*.md` files across auto-memory dirs, groups by name slug, archives exact duplicates.

**Algorithm:**
1. List all pattern files under `~/.claude/projects/*/memory/`
2. Group by name slug (`feedback_ruflo-cwd-root-cause` → one group)
3. For duplicates, keep the most recently modified, archive the rest to `~/.claude/memory/archive/YYYY-MM-DD/`
4. Surface entries with identical `name:` frontmatter but different slugs in a weekly report
5. Never delete — always archive

**Cost:** ~3 hours (script + scheduler registration + test). Ongoing: zero.

**Pros:** Boring, safe, deterministic. Zero token cost. Solves the verified duplication case. Independent of any methodology question.

**Cons:** Doesn't do contradiction-finding, imputation, web search, or article suggestion. *Not yet Karpathy's methodology.* It's just housekeeping.

**Risk:** Very low. Worst case: archived file needs un-archiving.

### L2 — Deterministic Lint + Heal

**Sub-decisions:** SD1 = grep, SD2 = frontmatter only, SD3 = none, SD4 = surface-only.

**What:** L1 plus three deterministic capabilities. Still no LLM, still no web search.

**Adds on top of L1:**
- **Grep-based contradiction detection:** look for opposite-keyword pairs, conflicting numeric fields, identical `name:` across files
- **Frontmatter imputation:** deterministic heuristics to fill missing `name:` (from H1 of content), `description:` (from first paragraph), `type:` (from filename prefix `feedback_`/`project_`)
- **Concept-reference surfacing:** grep for repeated concept names across the corpus; if a phrase appears ≥5 times and has no dedicated doc, add to the weekly report

**Cost:** L1's ~3 hours + ~3 hours for grep patterns + frontmatter imputation + reference counter. Total ~6 hours. Ongoing: zero.

**Pros:** All deterministic — no LLM, no tokens, no hallucination risk. Starts actually implementing Karpathy's methodology (SD1-grep and SD2-frontmatter and SD4-surface). Low-risk learning loop: we see what Lint + Heal surfaces before we let the LLM act on it.

**Cons:** Grep-based contradiction detection misses semantic contradictions. Frontmatter imputation can't fix content gaps. Still no web search.

**Risk:** Low. Deterministic + archive-don't-delete = safe rollback. Main risk: false positives in grep-based contradiction detection annoy the user and get the job ignored.

### L3 — LLM-augmented Lint + Heal

**Sub-decisions:** SD1 = hybrid (grep candidates + LLM adjudication), SD2 = content (LLM fills gaps), SD3 = none, SD4 = draft-only.

**What:** L2 plus LLM-adjudicated contradiction detection, LLM-drafted content imputation, and LLM-drafted article suggestions. Still no web search.

**Adds on top of L2:**
- **Hybrid contradiction detection:** grep finds candidate pairs; LLM is prompted per candidate cluster to confirm "yes these contradict" or "no they're compatible because X." Dry-run mode writes the LLM's verdicts to a report for human review.
- **LLM content imputation:** for entries with missing content sections (e.g., `feedback_*.md` files with no "How to apply" field), LLM drafts the missing section based on surrounding context. Drafts go to a staging file, not the original.
- **LLM article suggestion:** when the reference-counter finds an undocumented concept, LLM drafts a stub dimension doc with `status: draft` frontmatter. Drops in `brana-knowledge/drafts/` (new directory) for review at milestones (via `/brana:review`).

**Cost:** L2's ~6 hours + ~4 hours for LLM prompt engineering + staging directory + draft review flow. Total ~10 hours. Ongoing: token cost per scheduled run (TBD — depends on corpus size and cadence).

**Pros:** This is the first layer that's actually "Karpathy's methodology" in any meaningful sense. LLM writes Layer 2 content under brana OS's enforcement (draft-only + staging + milestone review). Catches contradictions the grep-only layer misses. Starts using the LLM-authoring capability the user explicitly chose.

**Cons:** LLM cost compounds. LLM content imputation can hallucinate. Draft staging directory forks the knowledge base until reviewed (discipline problem). Non-determinism — consecutive runs may yield different drafts.

**Risk:** Medium. Requires strong dry-run + rollback semantics. Draft staging must have hard rules about what can leave staging and how.

### L4 — Full Karpathy Lint + Heal

**Sub-decisions:** SD1 = hybrid, SD2 = content, SD3 = budgeted web search, SD4 = draft + auto-create.

**What:** L3 plus web search to fill gaps. Full Karpathy vision.

**Adds on top of L3:**
- **Budgeted web search:** during the Q&A phase of Lint + Heal, if an internal question has no answer in the corpus, LLM issues a bounded web search (≤N per cycle, configurable). Results go to `docs/research/auto-YYYY-MM-DD-*.md` draft files with citations.
- **Auto-create drafts from search results:** when search results contain enough signal to draft a new dimension doc, create it automatically (still `status: draft`, still reviewed at milestones).

**Cost:** L3's ~10 hours + ~4 hours for web search integration + budget enforcement + citation formatting. Total ~14 hours. Ongoing: token cost + search API cost.

**Pros:** Complete Karpathy pipeline. Lint + Heal becomes a full research-assistant backbone. Closes the loop: raw concept → web research → draft dimension doc → review → accepted spec.

**Cons:** Highest cost. Highest risk of drift (auto-created drafts compound if review cadence slips). Hardest to dry-run because web search is non-idempotent. Most complex rollback (if a bad search result poisons a draft chain, untangling takes work).

**Risk:** Medium-high — not from speculation (the methodology is Karpathy's), but from operational complexity. Needs serious discipline around review cadence and draft quality gates.

---

## Comparison matrix

| Dimension | L0 | L1 | L2 | L3 | L4 |
|---|---|---|---|---|---|
| Effort (hours) | 0 | ~3 | ~6 | ~10 | ~14 |
| Ongoing token cost | Zero | Zero | Zero | Per-run | Per-run + search API |
| LLM involvement | None | None | None | Adjudicate + draft | Adjudicate + draft + search |
| Deterministic rollback | N/A | Trivial | Trivial | Requires staging discipline | Requires staging + search result hygiene |
| Implements Karpathy | No | Partial (dedup only) | Partial (3 of 4 caps, deterministic) | Most (3 of 4 caps, LLM-augmented) | Full (all 4 caps) |
| Enforces user's chosen methodology | No | Barely | Partially | Mostly | Fully |
| Hallucination risk | None | None | None | Medium | Medium-high |
| Depends on `inbox-to-dimensions-pipeline.md` (D10) | No | No | Light (surfacing only) | **Yes** (draft staging overlap) | **Yes** (draft staging overlap) |
| Throw-away risk if Karpathy methodology changes | N/A | None | None | Low (primary source is stable) | Low |
| Blast radius if consolidation misbehaves | N/A | 1 archived file | 1 archived file + 1 wrong frontmatter | 1 bad draft (isolated in staging) | 1 bad draft + 1 bad search-backed doc |

## Key design decisions (non-negotiable regardless of depth)

1. **Layer 2 only.** This job never touches Layer 1 (brana OS). It never modifies `~/.claude/rules/`, `hooks.json`, `CLAUDE.md`, ADR decisions, skill SKILL.md frontmatter, the CLI source, or the `User Preferences — CRITICAL` section of MEMORY.md. If the implementation ever needs to touch Layer 1, that's a scope violation — stop and re-shape.
2. **Never delete, only archive.** Any removed entry moves to `~/.claude/memory/archive/YYYY-MM-DD/` with full path preserved. Recovery must be possible by `cp` back.
3. **Lock file before write.** Single-writer invariant. No two Lint + Heal jobs (or a Lint + Heal + a session close) ever write the same file concurrently. Lock path: `~/.swarm/lint-heal.lock` (not `kairos.lock` — rename away from Cathedral framing).
4. **Dry run mode required.** `brana memory lint-heal --dry-run` must show everything the job *would* write without writing anything. First run in any new deployment is always dry-run.
5. **Rollback snapshot.** Before any non-dry-run, snapshot `~/.claude/memory/` to `~/.claude/memory/pre-lint-heal-YYYY-MM-DD/`. Retained 7 days. For L3–L4, snapshot also includes `brana-knowledge/drafts/`.
6. **Scheduler is the only entry point.** No ad-hoc invocation from inside a session (avoids "lint fires mid-close" race). Manual trigger only via `brana memory lint-heal` CLI, never from a skill procedure.
7. **Build on the existing brana scheduler**, not a new daemon. Do not introduce a new process.
8. **Draft staging directory is shared (L3–L4 only).** `brana-knowledge/drafts/` is written by two producers: **D10 inbox-to-dimensions pipeline creates drafts** (source URLs → dimension additions); **Lint + Heal creates stub article suggestions** (undocumented concept → stub draft). Both producers are read by `/brana:review`. Promotion requires a human action (`brana knowledge promote <path>`). No auto-promotion from either producer. Hard cap: **10 drafts** across both producers (locked 2026-04-12, post-challenge); if cap hit, both producers halt until user acknowledges via `brana knowledge process --status`.
9. **Token budget cap (L3–L4).** Per-run cap in config. If cap hit mid-run, abort and log — do not partial-write.
10. **Idempotent scheduling.** Missing a run must be safe. The next run catches up without duplicate work.

## Risks (updated for Layer-2 scope)

| Risk | Applies to | Mitigation |
|---|---|---|
| Layer 2 job accidentally touches Layer 1 file | All layers | Hard path allow-list; CLI refuses to write outside allowed paths; unit test covers rejection of Layer 1 paths |
| Grep-based contradiction detection has false positives | L2+ | Dry-run first; surface-only mode for first N weeks; user can mark entries as "not a contradiction" in frontmatter |
| LLM content imputation hallucinates | L3+ | Staging directory + milestone review + archive-don't-delete + dry-run mandatory |
| LLM article-suggestion drafts accumulate faster than review cadence | L3+ | Hard cap: **10 drafts** across all producers (D10 pipeline + Lint+Heal); if cap hit, both halt with warning. Cap lowered from 20 (challenger finding: at 12-15 URLs/day, 3 missed reviews → 30-50 drafts, recreating the triage problem). |
| Web search returns low-quality or wrong info | L4 | Cite sources in drafts; require ≥2 source agreement for draft creation; per-run search budget cap |
| Ruflo concurrent writes corrupt DB | L3+ (if ruflo touched) | Lock file + better-sqlite3 WAL (per MEMORY.md); but *preferred*: Lint + Heal writes to files only, lets ruflo reindex pick up changes on its own schedule |
| Scheduler missed run (Oracle VM downtime) | All | Idempotent design; missing runs is safe |
| Token cost compounds | L3+ | Per-run budget cap; monthly spend report surfaced in `/brana:review` |
| User loses trust in Lint + Heal and ignores the reports | L2+ | First N weeks in surface-only mode before any writes; track report-action rate as a calibration metric |
| Draft staging forks the knowledge base | L3+ | Hard rule: drafts never influence `/brana:research` results until promoted; staging indexed separately from accepted dimensions |

## Open questions

**Resolved by the reframe:**
- ~~"Does the user want consolidation at all?"~~ → Yes (user chose Karpathy methodology)
- ~~"Build on speculation or wait for CC?"~~ → Build on Karpathy (primary source)
- ~~"First-mover positioning value?"~~ → Not the driver; user wants the behavior regardless
- ~~"Is the Cathedral pattern wrong?"~~ → Cathedral is out of scope; Karpathy is the primary reference

**Still open (these affect depth choice L1 → L4):**

1. **Does the user's current pain come from duplication (→ L1 is enough), contradiction (→ L2+), missing content (→ L3+), or research gap filling (→ L4)?** Only the audit answers this.
2. **How often are Layer 2 contradictions actually appearing?** Back-of-envelope audit can tell us.
3. **Has ruflo stabilized since AgentDB v3 + WAL?** If yes, L3+ is lower-risk than it was. If no, Lint + Heal should write to files only and let ruflo reindex catch up out-of-band.
4. **Does brana have a draft staging directory yet?** `brana-knowledge/drafts/` does not exist. L3–L4 require it. This depends on the D10 pipeline doc (`inbox-to-dimensions-pipeline.md`), which also wants a draft staging area. **The two shape docs overlap here — they should agree on one staging location and one promotion ritual.**
5. **Is `/brana:review` the right milestone for draft review, or does Lint + Heal need its own dedicated review skill?** If the corpus grows fast enough that `/brana:review`'s weekly cadence can't keep up, a `/brana:lint-heal review` might be warranted.
6. **What's the token budget tolerable per run?** Unknown without a real-corpus dry-run.
7. **Do any existing brana skills (`/brana:reconcile`, `/brana:maintain-specs`) already do some of this work?** Probably partial overlap — need to audit.

## Cheap audit (same as before, but now drives depth-choice not option-choice)

Before picking a depth layer, run this 15-minute audit:

```
# Count Layer 2 files by project
find ~/.claude/projects/*/memory/ -name '*.md' -type f | wc -l
find ~/enter_thebrana/brana-knowledge/dimensions/ -name '*.md' -type f | wc -l
find ~/enter_thebrana/thebrana/docs/research/ -name '*.md' -type f | wc -l
find ~/enter_thebrana/thebrana/docs/ideas/ -name '*.md' -type f | wc -l

# Duplicate frontmatter name: fields
grep -r "^name:" ~/.claude/projects/*/memory/ | sort -t: -k3 | uniq -f 2 -d

# MEMORY.md line counts
wc -l ~/.claude/projects/*/memory/MEMORY.md

# Missing frontmatter fields in pattern files
for f in ~/.claude/projects/*/memory/feedback_*.md ~/.claude/projects/*/memory/project_*.md; do
  head -10 "$f" | grep -q "^description:" || echo "NO_DESCRIPTION: $f"
  head -10 "$f" | grep -q "^type:" || echo "NO_TYPE: $f"
done | head -20

# References to concepts that have no dimension doc (heuristic: tag density)
grep -rh "^- \[.*\](.*\.md)" ~/enter_thebrana/brana-knowledge/dimensions/ | sort | uniq -c | sort -rn | head
```

**Reading the audit results:**
- **<5 duplicates, <50 files total, frontmatter mostly complete** → L1 is enough (or even L0 — the problem isn't real yet)
- **10–30 duplicates, 100+ files, some missing frontmatter, no contradiction signal** → L1 or L2
- **Contradictions visible in `/brana:reconcile` output, or multiple `feedback_*.md` files saying opposite things** → L2 or L3
- **Repeated concept references with no dimension doc (clear research gaps)** → L3 or L4
- **Active research workflow with recurring "I can't find this in the wiki" moments** → L4

Run the audit, then pick depth based on what the numbers show. **Do not pick a depth without the audit.**

## Recommendation

**None — this is still a shape doc, not a plan.** The methodology is chosen (Karpathy Lint + Heal). The depth is the open question, and the audit is the next cheap action.

If the user wants a directional hint: **L2 is the lowest-regret entry point.** It implements 3 of the 4 Karpathy capabilities in deterministic form, with zero token cost, archive-don't-delete safety, and no dependency on the D10 staging directory. It's a working instance of the user's chosen methodology without the LLM-drift risks of L3–L4. If the audit shows the problem is bigger than L2 can address, upgrade to L3 — the added sub-decisions (LLM adjudication, content imputation, draft suggestion) each have isolated rollback.

**Do not pick L4 without shipping L2 first.** Operational complexity compounds — validate the scheduling, lock semantics, archive rotation, and report format on L2 before adding LLM behavior.

## Dependency on D10 (inbox-to-dimensions-pipeline)

L3 and L4 share a draft staging directory with the D10 pipeline. Both shape docs need to agree on:

- **Staging location:** `brana-knowledge/drafts/` vs `~/.claude/memory/drafts/` vs per-project `drafts/` subdirs
- **Draft frontmatter convention:** what `status: draft` actually means, what other metadata is required
- **Promotion ritual:** how does a draft move from staging to accepted? A CLI command? A skill step? A hook?
- **Review cadence:** `/brana:review` weekly? On-demand? Batched?

These are addressed in `inbox-to-dimensions-pipeline.md`. **If that shape doc picks different answers, this one should update to match** — or both should raise the conflict before either is implemented.

## What is NOT in scope of this doc

- Session memory format (8-section schema) — see `session-memory-cc-alignment.md` for D1
- Ruflo infrastructure repair — see `ruflo-native-integration.md`
- Pattern store resilience — see `resilient-pattern-store.md`
- The `inbox → dimensions` drafting pipeline — see `inbox-to-dimensions-pipeline.md` (sibling D10 shape doc)
- MEMORY.md "User Preferences — CRITICAL" section (Layer 1)
- Any Layer 1 artifact — rules, hooks, ADRs, skill frontmatter, CLI source
- Any implementation, scheduler registration, or rollout plan

## Next concrete step (pending direction)

1. **Run the cheap audit** (15 min). This tells us what depth is justified.
2. **If user picks L1:** write `docs/architecture/features/memory-dedup-minimal.md` as a scoped feature brief with audit numbers baked in. Smallest path to value.
3. **If user picks L2:** write `docs/architecture/features/lint-heal-deterministic.md` with the three deterministic capabilities scoped + grep patterns + report format.
4. **If user picks L3:** write `docs/architecture/features/lint-heal-llm-augmented.md` AND coordinate with `inbox-to-dimensions-pipeline.md` on the draft staging convention. Must not ship L3 without D10's staging design locked.
5. **If user picks L4:** same as L3 plus scope the web-search budget + citation format. Do not attempt before L3 has run for ≥4 weeks in production.
6. **If user picks L0 (defer):** close this as "considered, deferred," flag t-1075 with "reshaped as Lint + Heal — awaiting depth pick," revisit when Layer 2 accretion pain is concrete.
