---
name: build-phase
description: Plan and implement the next roadmap phase with built-in learning loops — debrief after each work item, maintain-specs after each phase.
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Glob
  - Grep
  - Task
---

# Build Phase

Implement the next phase of the brana roadmap with learning loops baked into the process. After each work item you debrief. After each phase you propagate learnings through the specs. The system learns while it builds itself.

## When to use

When you're ready to implement the next phase of the roadmap.

**Invocation:**
- `/build-phase` — auto-detect roadmap and phase
- `/build-phase 2` — build Phase 2 (auto-detect roadmap)
- `/build-phase lean` — use doc 18 (lean roadmap), auto-detect phase
- `/build-phase full` — use doc 17 (full roadmap), auto-detect phase
- `/build-phase lean 2` — use doc 18, build Phase 2
- `/build-phase full 3` — use doc 17, build Phase 3

## Process

### Step 0: Orient — where are we, which roadmap?

#### 0a: Choose the roadmap

Parse `$ARGUMENTS` for roadmap selection:

- If `$ARGUMENTS` contains `lean` → use **doc 18** (`~/enter_thebrana/enter/18-lean-roadmap.md`)
- If `$ARGUMENTS` contains `full` → use **doc 17** (`~/enter_thebrana/enter/17-implementation-roadmap.md`)
- If neither specified → **always ask the user**. Present the comparison so they can choose fresh each time:

```markdown
**Which roadmap should we follow for this phase?**

| | Doc 18 — Lean | Doc 17 — Full |
|---|---|---|
| **Phases** | 3 + pain-driven menu | 6 (0-5) |
| **Philosophy** | Build minimum, add when it hurts | Build the full vision upfront |
| **Deploy** | `cp -r` + git | Symlinks + rollback.sh |
| **Immune system** | Quarantine only + manual review | 5 automated layers |
| **SONA** | Not planned (activate when tags fail) | Phase 3 milestone |
| **Best for** | Getting to a working brain fast | Enjoying systems infrastructure |

Both roadmaps are compatible — lean is the on-ramp to full. Nothing you build under lean needs redoing if you switch to full later.
```

**Do not remember the choice across sessions.** The user picks each time.

#### 0b: Detect current phase

1. **Check current state:**
   - Run `cd ~/enter_thebrana/thebrana && git tag --list 'v*' --sort=-v:refname | head -5` to see what's tagged.
   - Run `cd ~/enter_thebrana/thebrana && git log --oneline -10` for recent work.
2. **Determine current phase** from the tag:

   **If using lean roadmap (doc 18):**
   - No tag or `v0.0.x` → Phase 1 (Working Skeleton)
   - `v0.1.x` → Phase 2 (Learning Loop)
   - `v0.2.x` → Phase 3 (Refinement)
   - `v0.3.x` → Pain-driven additions (switch to doc 17 as menu)

   **If using full roadmap (doc 17):**
   - No tag → Phase 0 (Skeleton)
   - `v0.1.x` → Phase 1 (Foundation Skills + Plugins)
   - `v0.2.x` → Phase 2 (Learning Loop)
   - `v0.3.x` → Phase 3 (SONA + Vector Intelligence)
   - `v0.4.x` → Phase 4 (Immune System)
   - `v0.5.x` → Phase 5 (Self-Improvement)

3. **If `$ARGUMENTS` specifies a phase number** — override the auto-detection.

#### 0c: Read context

1. **Read the selected roadmap doc** — find the section for the target phase.
2. **Also read the other roadmap** for supplementary detail (doc 17 has more implementation specifics even when using doc 18's structure).
3. **Read doc 24** (`~/enter_thebrana/enter/24-roadmap-corrections.md`) for known errata affecting this phase.
4. **Read doc 00** (`~/enter_thebrana/enter/00-user-practices.md`) for field observations that should inform this phase.

### Step 1: Plan the phase

Read the phase section from the selected roadmap (and the other roadmap for supplementary detail). Extract:

1. **Goal** — one sentence stating what "done" looks like.
2. **Work items** — break the phase into discrete, committable units. Each should be:
   - Small enough to complete in one session
   - Testable — has a verification step
   - Independent where possible (parallelizable)
3. **Exit criteria** — the checklist from the roadmap doc.
4. **Known risks** — from doc 24 errata, from doc 05 alpha caveats, from lessons learned.

Present the plan to the user:

```markdown
## Phase N: [Title]

**Goal:** [one sentence]

### Work Items

| # | Item | Depends On | Est. Complexity | Verification |
|---|------|-----------|----------------|-------------|
| 1 | ... | — | Low/Med/High | ... |
| 2 | ... | #1 | ... | ... |

### Exit Criteria (from roadmap)
- [ ] ...

### Known Risks
- [from doc 24, doc 05, lessons learned]

### Learning Checkpoints
- Mini-debrief after each work item (errata + learnings → doc 24 + memory)
- Full debrief + maintain-specs after all items complete
```

**Wait for user approval before proceeding.** The plan is a proposal, not a commitment.

### Step 2: Recall before building

Before touching code, query for relevant patterns:

```bash
CF=""
for candidate in "$HOME"/.nvm/versions/node/*/bin/claude-flow; do
    [ -x "$candidate" ] && CF="$candidate" && break
done
[ -z "$CF" ] && command -v claude-flow &>/dev/null && CF="claude-flow"
[ -z "$CF" ] && command -v npx &>/dev/null && CF="npx claude-flow"

cd "$HOME" && $CF memory search -q "project:brana phase:N" --format json 2>/dev/null || true
```

Also check auto memory at `~/.claude/projects/*/memory/MEMORY.md` for relevant notes.

Summarize what past sessions learned that's relevant to this phase. If nothing found, say so — start fresh.

### Step 3: Execute work items (the build loop)

#### 3a: Create the phase branch

**Before any edits**, create a branch for this phase's work:

```bash
# In thebrana (implementation)
cd ~/enter_thebrana/thebrana && git checkout -b feat/phase-N-title

# In enter (specs) — if spec updates are expected
cd ~/enter_thebrana/enter && git checkout -b docs/phase-N-errata
```

All work for this phase happens on these branches. Main stays clean until the phase is complete and verified.

#### 3b: The build loop

For each work item, follow this cycle:

```
┌─────────────────────────────────────────┐
│            FOR EACH WORK ITEM           │
│                                         │
│  1. State what you're building          │
│  2. Implement it (on the phase branch)  │
│  3. Verify it (run tests, manual check) │
│  4. Commit (conventional commits)       │
│  5. Mini-debrief (see below)            │
│  6. Store learning in memory            │
│                                         │
│  → Next work item (informed by what     │
│    you just learned)                    │
└─────────────────────────────────────────┘
```

#### Mini-debrief (after each work item)

This is NOT a full `/debrief`. It's a quick extraction:

1. **Did anything surprise you?** An API that didn't work as expected, a file in the wrong place, a command that needed flags not documented.
2. **Did you hit a spec mismatch?** If yes — note it. You'll write it up properly in the full debrief.
3. **Did you discover something reusable?** A pattern, a shortcut, a gotcha.

For each finding, store immediately:

```bash
cd "$HOME" && $CF memory store \
  -k "build:brana:phase-N:item-M:{short-id}" \
  -v '{"type": "build-learning", "phase": N, "item": "...", "finding": "...", "severity": "..."}' \
  --namespace patterns \
  --tags "project:brana,type:build-learning,phase:N"
```

If claude-flow is unavailable, append to `~/.claude/projects/*/memory/MEMORY.md`.

**Do not stop to write full errata entries yet** — collect them and batch-write in the full debrief. The goal is to keep building momentum while not losing learnings.

### Step 4: Validate exit criteria

After all work items are complete, check each exit criterion from the roadmap:

```markdown
### Exit Criteria Check

- [x] criterion 1 — verified by [how]
- [x] criterion 2 — verified by [how]
- [ ] criterion 3 — NOT MET: [what's missing]
```

If any criteria are not met, create additional work items and loop back to Step 3 for those items only.

### Step 5: Full debrief

Run the equivalent of `/debrief` but focused on the entire phase:

1. **Gather evidence** — `git log` from phase start to now, all mini-debrief findings, conversation context.
2. **Classify** into errata / learnings / issues.
3. **Write errata entries** to doc 24 following existing format.
4. **Write process learnings** to doc 24's Lessons Learned section.
5. **Store all findings** in claude-flow memory with phase tags.

### Step 6: Maintain specs

Run the equivalent of `/maintain-specs`:

1. **Re-evaluate reflections** — do docs 08 and 14 still hold after what was learned building this phase?
2. **Apply any new errata** — layer by layer (dimension → reflection → roadmap).
3. **Check doc 25** — does the self-documentation doc need updating?

This is where the system self-corrects. Building Phase N reveals things about the specs that inform Phase N+1. The specs update, and the next phase starts from corrected ground.

### Step 7: Close the phase

This step wraps up the phase: bookmark the code, snapshot the knowledge, commit the specs, and produce a report that tells you (and future sessions) exactly where things stand.

#### 7a: Commit, merge, clean up branches

All phase work happened on branches (created in Step 3a). Now merge them into main.

**1. Commit any remaining work on the branch:**

```bash
cd ~/enter_thebrana/thebrana && git status
# If uncommitted changes, stage and commit them
```

**2. Merge the phase branch into main:**

```bash
# thebrana repo
cd ~/enter_thebrana/thebrana
git checkout main
git merge --no-ff feat/phase-N-title -m "feat: complete Phase N — [title]"
git branch -d feat/phase-N-title

# enter repo (spec updates)
cd ~/enter_thebrana/enter
git checkout main
git merge --no-ff docs/phase-N-errata -m "docs: update specs after Phase N build"
git branch -d docs/phase-N-errata
```

`--no-ff` creates a merge commit even if fast-forward is possible. This preserves the branch in history — `git log --graph` will show the phase as a clear group of commits branching off and merging back.

**3. Verify clean state:**

```bash
cd ~/enter_thebrana/thebrana && git status && git log --oneline --graph -10
cd ~/enter_thebrana/enter && git status && git log --oneline --graph -10
```

Both repos should be on `main`, clean, with the merge commit visible.

#### 7b: Tag the phase in thebrana

A git tag is a named bookmark on a commit — it marks "Phase N was complete at this point." It costs nothing and gives you a rollback point.

```bash
cd ~/enter_thebrana/thebrana && git tag -a vX.Y.0 -m "Phase N complete: [one-line summary]"
```

**Version mapping:**

| Roadmap | Phase | Tag |
|---------|-------|-----|
| Lean | Phase 1 (Working Skeleton) | `v0.1.0` |
| Lean | Phase 2 (Learning Loop) | `v0.2.0` |
| Lean | Phase 3 (Refinement) | `v0.3.0` |
| Full | Phase 0 (Skeleton) | `v0.1.0` |
| Full | Phase 1 (Skills + Plugins) | `v0.2.0` |
| Full | Phase 2 (Learning Loop) | `v0.3.0` |
| Full | Phase 3 (SONA) | `v0.4.0` |
| Full | Phase 4 (Immune System) | `v0.5.0` |
| Full | Phase 5 (Self-Improvement) | `v1.0.0` |

**What this enables:**
- `git log v0.1.0..v0.2.0` — see everything that happened during Phase 2
- `git checkout v0.1.0` — go back to Phase 1 state if Phase 2 breaks something
- `git diff v0.1.0..HEAD` — compare current state to the end of a previous phase

**Optional:** also tag the enter repo if the spec changes from this phase are significant:
```bash
cd ~/enter_thebrana/enter && git tag -a specs-after-phase-N -m "Specs updated after Phase N build"
```

#### 7c: Snapshot knowledge

Run `export-knowledge.sh` to create a portable snapshot of the brain's state at the end of this phase. This is insurance — if the DB corrupts or claude-flow breaks, you have a JSON + markdown dump of everything learned.

```bash
cd ~/enter_thebrana/thebrana && bash export-knowledge.sh "./knowledge-export-phase-N-$(date +%Y%m%d)"
```

This produces a directory with:
- `reasoning-bank.json` — all patterns from ReasoningBank
- `auto-memory/` — cross-project memory files
- `project-memory-*/` — per-project memory

**Don't commit the export** — it's a local backup, not a tracked artifact. It lives alongside the repo, not inside it.

#### 7d: Store phase completion in memory

Record the phase completion so future `/build-phase` invocations and `/pattern-recall` queries know what was done:

```bash
cd "$HOME" && $CF memory store \
  -k "build:brana:phase-N:complete" \
  -v '{"phase": N, "roadmap": "lean|full", "tag": "vX.Y.0", "date": "YYYY-MM-DD", "work_items": N, "errata_found": N, "learnings": N}' \
  --namespace patterns \
  --tags "project:brana,type:phase-complete,phase:N"
```

#### 7e: Report

Produce a summary the user can scan. This is also what future sessions will see if they query for phase history.

```markdown
## Phase N Complete: [Title]

**Roadmap:** [lean (doc 18) | full (doc 17)]
**Tag:** `vX.Y.0`
**Date:** YYYY-MM-DD

### What was built
| # | Work Item | Commit | Verified |
|---|-----------|--------|----------|
| 1 | [description] | `abc1234` | [how] |
| 2 | [description] | `def5678` | [how] |

### What was learned
- **Errata found:** N new entries in doc 24 (errors #X-#Y)
- **Process learnings:** N entries added to doc 24 Lessons Learned
- **Patterns stored:** N entries in ReasoningBank
- **Key insight:** [the single most important thing learned this phase, in one sentence]

### Specs updated (from maintain-specs)
| Doc | What changed |
|-----|-------------|
| 08 | [change summary] |
| 14 | [change summary] |

### Exit criteria
- [x] criterion 1
- [x] criterion 2
- [x] all criteria met / [ ] N criteria not met (see below)

### Phase transition: what comes next

**Next phase:** Phase [N+1]: [Title]
**Goal:** [one sentence from roadmap]

**What this phase taught us that affects the next one:**
- [specific lessons, gotchas, or errata that change how N+1 should be approached]
- [any exit criteria from N+1 that need adjusting based on what was learned]

**Prerequisites before starting Phase [N+1]:**
- [Does it need real-world usage first? How many sessions? Across how many projects?]
- [Are there open errata that should be fixed before moving on?]
- [Does the user need to make a decision (e.g., which roadmap for the next phase)?]

**Suggested actions:**
1. Use the system in real projects — Phase [N+1] should be informed by real usage, not just test sessions
2. Run `/debrief` after real sessions to accumulate learnings
3. When ready: `/build-phase [N+1]`
```

#### 7f: Ask about next steps

Don't assume the user wants to immediately continue. Present the options:

1. **Use the system in real projects** — some phases (especially Phase 2→3) need real-world data before the next phase makes sense
2. **Start the next phase now** — if the current phase was quick and the next one doesn't need usage data
3. **Review and adjust** — look at the errata, reconsider the roadmap choice, or take a different direction

The user decides.

## Phase-Specific Guidance

### Phase 1: Working Skeleton

Focus: get files in place, deploy working, skills invokable. The most common trap is over-polishing — Phase 1 is scaffolding.

Key work items:
- Fix `deploy.sh` settings merge (doc 24 error #1)
- Wire disabled hooks in `settings.json` (placeholder for Phase 2)
- Install recommended plugins
- Verify all 6 skills work end-to-end
- Run `export-knowledge.sh` and confirm output
- Context budget validation under 15KB
- Use in 2+ real sessions before tagging

### Phase 2: The Learning Loop

Focus: hooks that actually fire, store, and recall. The most common trap is silent failures (lesson from doc 24).

Key work items:
- Enable SessionStart hook in `settings.json`
- Enable SessionEnd hook in `settings.json`
- Enable PostToolUse + PostToolUseFailure hooks
- Implement quarantine (confidence: 0.5, transferable: false)
- Test full recall→learn→recall cycle
- Test graceful degradation (what happens when claude-flow is down?)
- Test Layer 0 fallback (pending-learnings.md)
- Verify no infinite hook loops
- Use in 10+ sessions across 2+ projects before tagging

### Phase 3: Refinement

Focus: respond to real pain from Phase 2. Don't pre-plan — read your own debrief notes and doc 00 (user practices) to decide what to fix.

Key inputs:
- Mini-debrief findings from Phase 2 sessions
- Doc 00 user practices (what keeps hurting?)
- ReasoningBank query: recalled patterns that were useless (precision problems)
- ReasoningBank query: patterns you stored but never recalled (recall problems)

### Post-v0.3.0: Pain-Driven

Use doc 17 as a menu. For each pain point, read the corresponding doc 17 section, plan the addition as a single work item, build it, debrief it.

## Rules

- **Never skip the mini-debrief.** It takes 30 seconds and prevents losing learnings. The whole point of this command is that building and learning happen together.
- **Exit criteria are non-negotiable.** Don't tag a phase as complete if criteria aren't met. Incomplete phases compound — Phase 2 on a shaky Phase 1 is worse than finishing Phase 1 properly.
- **Maintain-specs is not optional.** The spec-reality gap is the #1 source of wasted work (see doc 24 errors #2 and #9). Every phase that touches reality must feed back into specs.
- **One phase per invocation.** Don't try to build multiple phases in a single session. Each phase needs real-world usage between build sessions.
- **Commit early, commit often.** Each work item gets its own commit. If something breaks, you can revert one item without losing the phase.
- **Ask before proceeding past the plan.** The plan in Step 1 is a proposal. The user decides whether to proceed, reorder, or skip items.
- **Ask for clarification whenever you need it.** If something is unclear, ambiguous, or you're unsure how the user wants to proceed — ask. Don't guess. A quick question saves more time than a wrong assumption.
