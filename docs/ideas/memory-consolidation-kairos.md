# Memory Consolidation — Kairos/autoDream Shape

> Brainstormed 2026-04-08. Status: **shape / brainstorm only — no implementation.**
> Upstream findings: [`../research/2026-04-08-cc-alignment-findings.md`](../research/2026-04-08-cc-alignment-findings.md) §D2.
> Related prior work: [`resilient-pattern-store.md`](./resilient-pattern-store.md), [`ruflo-native-integration.md`](./ruflo-native-integration.md).

## Problem

Brana accumulates patterns, learnings, session snapshots, and field notes across sessions. Current consolidation is *manual* and *reactive*:
- `/brana:close` writes new patterns to MEMORY.md and ruflo, but never deduplicates, merges, or prunes existing entries
- `/brana:retrospective` is user-initiated, not scheduled
- MEMORY.md growth is monitored by a line count rule, not a content rule
- Ruflo (the semantic memory layer) is fragile — see `feedback_complexity-audit.md`: "accretion > architecture as the real problem"

The leak analysis (leak doc §1.3.2, §1.3.3) reports that Anthropic has built **Kairos** (an always-on background daemon) and **autoDream** (the consolidation logic inside Kairos) — both feature-flagged off in the published build. autoDream's described job is: *"merge duplicate memories, eliminate contradictions, resolve speculations, prune memory to make stored data more suitable for action."*

This is exactly brana's accretion problem. The question is whether to build brana's version *before* Anthropic flips the flag.

## What the leak actually tells us (and doesn't)

**[REPORTED]** — from DeepLearning.ai and Roger Wong, not from code:
- Kairos exists
- It's described as "always-on"
- autoDream is the consolidation layer inside it
- Both are flag-gated off in the published build
- autoDream's consolidation goals: dedup, contradiction resolution, speculation resolution, pruning

**NOT VERIFIED** — no one has quoted code for any of:
- Kairos trigger conditions (when does it run?)
- Kairos storage format (where does it write?)
- autoDream's actual consolidation algorithm (how does it dedup?)
- Whether Kairos runs as a separate process, a thread, or inline
- Whether it operates on the session_memory file, on a separate store, or on ruflo-equivalent memory

**[CONCEPTUAL]** — one community reimplementation exists (Mike W on DEV.to, Cathedral.ai). It uses:
- 3-gate trigger: 24h since last run / 5+ new sessions / lock file advisory
- 4 phases: Orient → Gather → Consolidate → Prune
- Hard cap: 200 lines / 25 KB

**Critical framing:** Cathedral's pattern is a *reconstruction*, explicitly described as "we believe this is what Kairos does." It is not the leaked code. If we build to Cathedral's spec and Anthropic ships something different, we throw work away. Everything in this shape doc that references the 3-gate / 4-phase pattern should be read as "one reasonable pattern from the community," not "what CC does."

## Proposed shape (four options)

### Option A — Cathedral clone (full reimplementation)

**What:** Implement the Cathedral 3-gate + 4-phase pattern as a scheduled brana job. Runs via the existing brana scheduler. Targets ruflo + MEMORY.md + pattern files in `~/.claude/projects/*/memory/`.

**Trigger:** 3-gate AND:
- Time: `last_consolidation + 24h < now()`
- Sessions: `count(sessions since last_consolidation) >= 5`
- Lock: no `~/.swarm/kairos.lock` file present

**Phases:**
1. **Orient** — read MEMORY.md, list all pattern files, query ruflo for top-500 recently-touched entries
2. **Gather** — group patterns by topic similarity (embedding cluster or ripgrep-based semantic buckets)
3. **Consolidate** — call LLM to merge duplicates, resolve contradictions, refine confidence scores
4. **Prune** — delete low-confidence unused patterns, archive old ones to `~/.claude/memory/archive/`

**Cost:**
- ~4 hours scheduler job + lock file + gate logic
- ~2 hours LLM consolidation prompt engineering
- ~2 hours testing against real memory state
- ~1 hour rollback / recovery (if consolidation breaks something, we need to restore)
- Ongoing: token cost for nightly LLM consolidation runs

**Pros:**
- **First-mover on the pattern.** If Anthropic's Kairos ships and looks like this, brana already has operational experience.
- Directly addresses the "accretion > architecture" pain already identified in brana's own audit.
- Publishable as a brana differentiator ("brana has Kairos-style consolidation *today*").
- Creates a natural event stream for `/brana:review` to surface ("consolidated 47 entries last week").

**Cons:**
- **Build on sand.** Cathedral's pattern is a guess. Anthropic's real Kairos might be file-level, not entry-level. Might not use 3 gates. Might not use 4 phases. We're shipping a community reconstruction as if it were a spec.
- **High risk of throw-away work.** If the real Kairos ships and is incompatible, we either keep running two consolidation systems or throw ours out.
- **LLM consolidation is not deterministic.** A bad merge destroys information. We need rollback semantics, which Cathedral's doc doesn't describe.
- **Ruflo is currently fragile.** Adding nightly writes to a DB that has already corrupted twice (see MEMORY.md "Ruflo AgentDB Status") is compounding risk on an unstable layer.
- Token cost of nightly LLM runs (TBD, but not free).

**Risk:** High. Every line of this option builds on unverified assumptions.

---

### Option B — Minimal dedup

**What:** A much smaller scheduled job that does exactly one thing: deduplicate pattern files with identical names or near-identical content. No LLM calls. Pure diff + merge.

**Trigger:** Weekly cron via existing brana scheduler. No 3-gate — just a simple time trigger.

**Algorithm:**
1. List all `feedback_*.md` and `project_*.md` files under `~/.claude/projects/*/memory/`
2. Group by name slug (`feedback_ruflo-cwd-root-cause` → single group)
3. For duplicates, keep the most recently modified, move others to `.claude/memory/archive/`
4. For entries with identical front-matter `name` but different slugs, surface in a weekly report for manual review
5. Never delete anything — always archive

**Cost:**
- ~2 hours shell/rust script
- ~1 hour scheduler registration + log wiring
- ~1 hour test against real memory dirs
- Ongoing: zero marginal cost (no LLM)

**Pros:**
- **Boring, safe, deterministic.** No LLM guessing. No consolidation "maybe it's the same idea." Just: identical = dedup.
- Catches the real problem (duplicate `feedback_*.md` files from repeated saves).
- Zero token cost.
- **Independent of whether Anthropic ships Kairos.** This is just good housekeeping.
- Can be rolled into `/brana:reconcile --scope knowledge` as a manual trigger for paranoid operators.

**Cons:**
- **Doesn't solve the consolidation problem.** "Merge contradictions" and "resolve speculations" are out of scope. Just handles the obvious duplication case.
- Does not provide the positioning angle ("brana has Kairos today").
- Still leaves MEMORY.md bloat untouched unless the rule also prunes stale index entries.

**Risk:** Very low. Worst case: an archived file needs to be un-archived.

---

### Option C — Wait and mirror

**What:** Do nothing until Anthropic flips a Kairos flag. When it does, inspect the behavior, decide whether to wrap it (if it's file-based and inspectable) or reimplement (if it's internal). Meanwhile, keep a one-page tracker doc updated.

**Cost:**
- ~30 min to create `docs/research/cc-unreleased-features-tracker.md` with Kairos row
- ~5 min/quarter to review
- Ongoing: zero

**Pros:**
- **Zero risk.** Zero wasted work.
- Stays consistent with "don't build on unverified community claims."
- Preserves capacity for other work (D1, D3, D4 are cheaper wins).
- If Anthropic never ships Kairos (flags stay off forever), we didn't invest.

**Cons:**
- **Doesn't solve brana's accretion problem today.** MEMORY.md keeps growing. Duplicate patterns keep accumulating. Ruflo keeps fragmenting.
- Loses the "first-mover" positioning angle.
- Reactive, not proactive — if the user's main pain is "my memory is getting messy," this option says "not our problem yet."

**Risk:** Low. Only risk is opportunity cost.

---

### Option D — Layered (B now, A-or-C later)

**What:** Ship Option B (minimal dedup) *this* cycle. Create the tracker doc from Option C in parallel. Revisit Option A only after (a) Anthropic's Kairos ships and we've seen its shape, OR (b) Option B's dedup has been running for 4+ weeks and we have operational data showing it's not enough.

**Cost:** B's cost (~4 hours) + C's cost (~30 min). No A upfront.

**Pros:**
- **Solves the boring, real problem (dedup) immediately with minimal risk.**
- Keeps us informed on the speculative problem (Kairos shape) with the tracker doc.
- Defers the high-risk build until either evidence comes in.
- Consistent with `feedback_research-to-shape-to-build.md` — we don't build on speculation.
- Gives a checkpoint: if after 4 weeks the dedup isn't enough, we have real data to motivate Option A.

**Cons:**
- Two-phase delivery means two sprints of attention on memory instead of one.
- Doesn't get the "brana has Kairos today" positioning win.
- Small risk: Option B consumes the appetite for Option A entirely (the team calls it done and never builds consolidation). If consolidation matters long-term, the minimal version can actually *delay* the real fix.

**Risk:** Low-medium. Same as B plus the risk of premature closure.

---

## Comparison matrix

| Dimension | A Cathedral | B Minimal | C Wait | D Layered |
|---|---|---|---|---|
| Effort (hours) | ~10 | ~4 | ~0.5 | ~4.5 |
| Risk | High | Very low | Zero | Low |
| Based on verified facts | No | Yes | N/A | Mostly (B is, A deferred) |
| Solves today's accretion pain | Yes | Partial (dedup only) | No | Partial (dedup now) |
| First-mover positioning | Yes | No | No | No (unless upgraded to A later) |
| Throw-away risk if CC ships incompatible Kairos | High | Near-zero | Zero | Near-zero |
| Addresses MEMORY.md bloat | Yes | Partial | No | Partial |
| Addresses ruflo fragility | Makes it worse | Neutral | Neutral | Neutral |
| Token cost | Ongoing | Zero | Zero | Zero |

## Key design decisions (non-negotiable regardless of option)

1. **Never delete, only archive.** Consolidation (in any form) moves entries to `~/.claude/memory/archive/YYYY/` rather than `rm`. Recovery must be possible.
2. **Lock file before write.** Single-writer invariant. No two consolidation jobs (or a consolidation + a session close) ever write the same file concurrently.
3. **Dry run mode required.** `brana memory consolidate --dry-run` must show what would change without writing anything.
4. **Rollback snapshot.** Before any consolidation run, snapshot the memory dir to `~/.claude/memory/pre-consolidate-YYYY-MM-DD/`. Retained 7 days.
5. **Scheduler is the only entry point.** No ad-hoc invocation from inside a session (avoids "consolidate fires mid-close" race).
6. **Build on the existing brana scheduler**, not a new daemon. Do not introduce a new process.

## Risks (across all options)

| Risk | Applies to | Mitigation |
|---|---|---|
| Cathedral pattern is wrong | A, D (if upgraded) | Don't build A without first verifying against an actual Kairos release |
| LLM consolidation destroys information | A | Dry-run + rollback snapshot + archive-don't-delete |
| Ruflo concurrent writes corrupt DB | A | Lock file + single-writer invariant + better-sqlite3 WAL (already configured per MEMORY.md) |
| Dedup misses semantically-equivalent-but-textually-different duplicates | B, D | Accept as out-of-scope; surface in weekly report for manual review |
| Scheduler missed run (Oracle VM downtime, etc.) | A, B, D | Consolidation is idempotent — missing a run is safe |
| Nightly LLM cost compounds | A | Cap spend via token budget; abort if quota hit |
| MEMORY.md bloat doesn't get solved | B, C, D | Separate line-count rule continues to warn; revisit if threshold hit |

## Open questions (would change the answer)

1. **Does the user's current memory pain come from duplication or from bloat?** If duplication: Option B solves it. If bloat: only A (or something like A) solves it.
2. **Has ruflo corruption stabilized since the AgentDB v3 migration?** MEMORY.md says WAL mode is configured. If it's stable, Option A's ruflo-write risk is lower than it was.
3. **Does Anthropic have a ship date for Kairos, or even a timeline?** If Kairos ships in CC 2.2, Option D's "wait 4 weeks" answer arrives naturally. If Kairos is a 2026-H2 thing, waiting is more expensive.
4. **Is brana's positioning story currently weak enough that "first-mover on Kairos" would move a needle?** If yes, the Option A tradeoff tilts toward "ship it, even speculative." If no, Options B/D are cleaner.
5. **Would a Cathedral-style system actually work on brana's memory shape, or is brana's memory too structured for entry-level merging?** Brana has per-topic files with frontmatter. Merging two `feedback_tdd-no-exceptions.md` files is one thing; merging two `project_*.md` files with different structures is another.
6. **How often do actual duplicates appear?** Back-of-envelope: we can grep for duplicate `name:` frontmatter right now as a quick audit.

## Cheap audit (to right-size the problem before deciding)

Before picking any option, run a 15-minute audit:

```
# Count memory files by project
find ~/.claude/projects/*/memory/ -name '*.md' -type f | wc -l

# Find duplicate name: frontmatter entries
grep -r "^name:" ~/.claude/projects/*/memory/ | sort -t: -k3 | uniq -f 2 -d

# Check MEMORY.md line counts
wc -l ~/.claude/projects/*/memory/MEMORY.md
```

If the audit shows <5 duplicates across <50 total files, Option B is overkill and Option C is correct. If it shows 20+ duplicates or 500+ files, Option B is necessary and Option D becomes a serious candidate.

This is the single cheapest thing we can do to de-risk the decision.

## Recommendation

**None — this is a shape doc, not a plan.** The option tree is on paper. The audit is the next cheap, low-regret action. The audit would tell us whether the pain is real enough to justify Option B, which in turn tells us whether Option D is worth planning.

If the user wants a directional hint: **Option D (minimal dedup now + tracker doc) is the lowest-regret path** — it solves the verified part of the problem, stays out of the speculation zone, and preserves optionality. But that's only defensible if the audit shows real duplication. If the audit comes up empty, Option C is correct.

## What is NOT in scope of this doc

- Session memory format (8-section schema) — see `session-memory-cc-alignment.md` for D1
- Ruflo infrastructure repair — see `ruflo-native-integration.md`
- Pattern store resilience — see `resilient-pattern-store.md` (there may be overlap; worth reading before implementing either A or B)
- MEMORY.md bloat controls — existing line-count rule handles this
- Any implementation, scheduler registration, or rollout plan

## Next concrete step (pending direction)

- **If user picks Option D:** run the cheap audit first. If audit justifies it, write `docs/architecture/features/memory-dedup-minimal.md` as a scoped feature brief with the audit numbers baked in.
- **If user picks Option A:** do NOT proceed without first verifying the Cathedral pattern against another primary source or waiting for Kairos release data. Mark the shape doc as "pending verification."
- **If user picks Option B alone:** same as D minus the tracker-doc work.
- **If user picks Option C:** create `docs/research/cc-unreleased-features-tracker.md` with Kairos/autoDream rows and a quarterly review trigger inside `/brana:review`.
- **If user picks no option:** close this as "considered, deferred," leave t-1075 pending, revisit when CC 2.2 ships.
