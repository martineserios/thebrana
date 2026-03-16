# 15 - Self-Development Workflow: The System That Maintains Itself

How to treat the mastermind system as software — version it, test it, deploy it, rollback it — while preserving the knowledge it accumulates. Brain surgery on a running brain.

---

## The Fundamental Separation: Genome vs Connectome

Two fundamentally different things live in the same space and must be managed differently:

```
THE GENOME (system code)                THE CONNECTOME (learned knowledge)
─────────────────────────               ─────────────────────────────────
How the brain works                     What the brain knows

~/.claude/CLAUDE.md                     ~/.swarm/memory.db (ruflo)
~/.claude/skills/*.md                   ~/.claude/memory/MEMORY.md
~/.claude/agents/*.md                   ~/.claude/memory/portfolio.md
~/.claude/commands/*.md                 ~/.claude/memory/retired/
~/.claude/rules/*.md                    Per-project auto memory
~/.claude/settings.json (hooks)         SONA trajectories

Changes intentionally, by you          Changes organically, by experience
Versioned in git                        Backed up, never rolled back
Has bugs, needs testing                 Has no "bugs" — only knowledge
Can be branched and merged              Linear accumulation, append-mostly
Deployed deliberately                   Grows continuously
```

**The cardinal rule: a system rollback must NEVER touch the knowledge store.** If you revert a broken skill to yesterday's version, the patterns learned yesterday must survive. Genome changes. Connectome persists.

---

## The Brana System as Its Own Project

The mastermind system is software. Give it its own project, its own repo, its own backlog, its own feature lifecycle — managed by the very system it defines.

```
~/projects/
├── brana/                                THE SYSTEM PROJECT
│   ├── .claude/                          ← Context for developing brana itself
│   │   ├── CLAUDE.md                     ← "You are developing the mastermind system.
│   │   │                                    Be careful — you're editing your own brain."
│   │   ├── rules/
│   │   │   └── self-edit-safety.md       ← "Always validate before deploying"
│   │   └── skills/
│   │       └── self-test/SKILL.md        ← Project-specific skill for testing the system
│   │
│   ├── system/                           ← THE GENOME (what gets deployed to ~/.claude/)
│   │   ├── CLAUDE.md                     ← Mastermind identity
│   │   ├── skills/
│   │   │   ├── memory/SKILL.md
│   │   │   │   │   │   ├── retrospective/SKILL.md
│   │   │   ├── project-onboard/SKILL.md
│   │   │   └── client-retire/SKILL.md
│   │   ├── agents/
│   │   │   ├── architect.md
│   │   │   ├── reviewer.md
│   │   │   └── scout.md
│   │   ├── commands/
│   │   │   ├── what-do-i-know.md
│   │   │   ├── teach-me.md
│   │   │   └── portfolio.md
│   │   ├── rules/
│   │   │   ├── universal-quality.md
│   │   │   ├── git-discipline.md
│   │   │   ├── sdd-tdd.md
│   │   │   ├── context-budget.md
│   │   │   ├── delegation-routing.md
│   │   │   ├── memory-framework.md
│   │   │   ├── task-convention.md
│   │   │   ├── pm-awareness.md
│   │   │   ├── research-discipline.md
│   │   │   └── work-preferences.md
│   │   ├── skill-catalog.yaml             ← Vetted external skills (version-pinned, checksum-verified)
│   │   └── settings.json                 ← Hooks configuration
│   │
│   ├── tests/                            ← VALIDATION
│   │   ├── validate-syntax.sh            ← All SKILL.md frontmatter is valid YAML
│   │   ├── validate-hooks.sh             ← All hooks reference existing scripts
│   │   ├── validate-context-budget.sh    ← Total context stays under budget
│   │   ├── validate-imports.sh           ← No broken @imports, no circular refs
│   │   └── smoke-test.sh                 ← Launch claude with --plugin-dir, run basic commands
│   │
│   ├── deploy.sh                         ← Deploy system/ → ~/.claude/ (with safety checks)
│   ├── rollback.sh                       ← Revert ~/.claude/ to last tagged version
│   ├── backup-knowledge.sh               ← Snapshot ruflo memory + auto memory
│   │
│   ├── BACKLOG.md                        ← Features, bugs, experiments for the system itself
│   ├── CHANGELOG.md                      ← History of system changes
│   └── README.md
│
├── alpha/                                ← A normal project
├── beta/                                 ← A normal project
└── gamma/                                ← A normal project
```

The `brana/` project lives alongside your other clients. The mastermind manages it just like any other client — same SPARC phases, same code review, same patterns. But with extra safety rails because the stakes are higher.

---

## The Deploy Pipeline

All changes flow through the system project. Never edit `~/.claude/` directly.

```
┌─────────────────────────────────────────────────────────┐
│                    THE SURGERY PROTOCOL                  │
│                                                         │
│  1. SNAPSHOT     backup-knowledge.sh                    │
│     └─ cp memory.db → backups/memory_YYYYMMDD.db        │
│     └─ cp memory/ → backups/memory_YYYYMMDD/            │
│                                                         │
│  2. BRANCH       git checkout -b feature/new-skill      │
│     └─ Work in brana/system/                             │
│                                                         │
│  3. CHANGE       Edit skills, hooks, agents, rules      │
│     └─ Claude Code edits files in brana/system/          │
│     └─ NOT in ~/.claude/ — that's production             │
│                                                         │
│  4. VALIDATE     tests/validate-*.sh                    │
│     └─ Syntax checks, budget checks, import checks      │
│                                                         │
│  5. STAGE        claude --plugin-dir ./system            │
│     └─ Test the changes in an isolated session           │
│     └─ Use a throwaway project directory                 │
│                                                         │
│  6. COMMIT       git commit (in brana repo)              │
│     └─ Conventional commit: "feat(skills): add ..."      │
│                                                         │
│  7. DEPLOY       deploy.sh                              │
│     └─ Symlink brana/system/* → ~/.claude/*              │
│     └─ Tag the commit: v0.3.1                            │
│                                                         │
│  8. MONITOR      Next 2-3 real sessions                 │
│     └─ Watch for issues, broken hooks, context bloat     │
│                                                         │
│  9. ROLLBACK     (if needed) rollback.sh                │
│     └─ git checkout last-good-tag                        │
│     └─ Re-deploy. Knowledge store UNTOUCHED.             │
└─────────────────────────────────────────────────────────┘
```

---

## Why Symlinks for Deploy

If `~/.claude/skills/memory/SKILL.md` is a symlink to `~/projects/brana/system/skills/memory/SKILL.md`, then:

- Git controls the source of truth (the brana repo)
- `~/.claude/` is always just a mirror
- Rollback = checkout different tag + re-symlink
- You can see exactly what's deployed with `ls -la ~/.claude/skills/`
- No copy drift — the symlink always points to whatever's in the repo

```bash
# deploy.sh (simplified concept)
#!/bin/bash
SYSTEM_DIR="$(dirname $0)/system"
TARGET="$HOME/.claude"

# Validate first
./tests/validate-syntax.sh || exit 1
./tests/validate-context-budget.sh || exit 1

# Symlink each component
ln -sfn "$SYSTEM_DIR/CLAUDE.md" "$TARGET/CLAUDE.md"
ln -sfn "$SYSTEM_DIR/skills" "$TARGET/skills"
ln -sfn "$SYSTEM_DIR/agents" "$TARGET/agents"
ln -sfn "$SYSTEM_DIR/commands" "$TARGET/commands"
ln -sfn "$SYSTEM_DIR/rules" "$TARGET/rules"
# settings.json needs merge, not overwrite (preserves user-specific settings)

echo "Deployed $(git describe --tags) to ~/.claude/"
```

---

## The Knowledge Backup Strategy

ruflo memory is SQLite — simple, reliable, easy to backup:

```bash
# backup-knowledge.sh
#!/bin/bash
BACKUP_DIR="$HOME/.swarm/backups"
DATE=$(date +%Y%m%d_%H%M%S)

# Backup ruflo memory
mkdir -p "$BACKUP_DIR"
sqlite3 ~/.swarm/memory.db ".backup '$BACKUP_DIR/memory_$DATE.db'"

# Backup auto memory
cp -r ~/.claude/memory/ "$BACKUP_DIR/memory_files_$DATE/"

# Keep last 30 backups
ls -t "$BACKUP_DIR"/memory_*.db | tail -n +31 | xargs rm -f

echo "Knowledge backed up: $BACKUP_DIR/memory_$DATE.db"
```

**When to backup:**
- Before every deploy (automatic, called by deploy.sh)
- Daily via cron (cheap insurance)
- Before `/brana:client-retire` (you're about to transform data)

**What about git for knowledge?**

Auto memory files (`.md`) can live in a separate knowledge repo or just be backed up. ruflo memory (`memory.db`) is a binary — git won't handle it well. SQLite backups + a retention policy is simpler and more reliable.

---

## Experimenting Safely

### Level 1: Syntax Validation (Cheap, Always Run)

```bash
# validate-syntax.sh
# Check all SKILL.md files have valid YAML frontmatter
for skill in system/skills/*/SKILL.md; do
  # Extract frontmatter between --- markers, validate as YAML
  sed -n '/^---$/,/^---$/p' "$skill" | yq . > /dev/null 2>&1
  if [ $? -ne 0 ]; then
    echo "FAIL: Invalid frontmatter in $skill"
    exit 1
  fi
done

# Check all agent .md files exist and aren't empty
for agent in system/agents/*.md; do
  [ -s "$agent" ] || { echo "FAIL: Empty agent $agent"; exit 1; }
done

# Check hooks reference existing scripts
# Check @imports resolve
# Check no file exceeds reasonable size
```

### Level 2: Context Budget Check (Prevents Bloat)

```bash
# validate-context-budget.sh
# Calculate total always-loaded context
TOTAL=0
TOTAL=$((TOTAL + $(wc -c < system/CLAUDE.md)))
for rule in system/rules/*.md; do
  TOTAL=$((TOTAL + $(wc -c < "$rule")))
done
# Add skill descriptions (just frontmatter, not full content)
for skill in system/skills/*/SKILL.md; do
  DESC_SIZE=$(sed -n '/^---$/,/^---$/p' "$skill" | wc -c)
  TOTAL=$((TOTAL + DESC_SIZE))
done

echo "Total always-loaded context: ${TOTAL} bytes"
if [ $TOTAL -gt 15360 ]; then  # 15KB budget
  echo "FAIL: Context budget exceeded (${TOTAL} > 15360)"
  exit 1
fi
```

### Level 3: Isolated Session Testing (The Real Test)

```bash
# Use --plugin-dir to test system changes without deploying
cd /tmp/test-project
git init
claude --plugin-dir ~/projects/brana/system

# In the session:
# - Try /brana:memory recall "test query"
# - Check that hooks fire
# - Verify context is reasonable
# - Look for errors
```

This launches Claude Code with your modified system but against a throwaway project. ruflo memory is read but not written (unless you explicitly test learning). Production `~/.claude/` is untouched.

### Level 4: A/B Testing (For Bigger Changes)

For significant changes — like a new learning hook or a redesigned skill — run both versions:

```
Week 1: Deploy version A (current). Note quality of pattern recall, session flow.
Week 2: Deploy version B (candidate). Note same metrics.
Compare: Did pattern recall improve? Did sessions feel smoother? Any regressions?
```

The mastermind itself can track this — store observations about its own performance in ruflo memory tagged `domain: brana-system`.

---

## The Self-Development CLAUDE.md

The brana project has its own `.claude/CLAUDE.md` that gives Claude special awareness when working on the system:

```markdown
# Brana System Development

You are editing the mastermind system — the skills, hooks, agents, and rules
that control YOUR OWN behavior across all clients.

## Safety Rules

1. **Never edit ~/.claude/ directly.** All changes go through brana/system/.
2. **Always run validation before suggesting deploy.** Use tests/validate-*.sh.
3. **Hooks must fail gracefully.** A broken hook should exit 0 and skip,
   not exit 2 and block. The system must degrade, never crash.
4. **Context budget is sacred.** Always-loaded content must stay under 15KB.
   Check with tests/validate-context-budget.sh after any change.
5. **Knowledge store is read-only during system development.**
   Don't modify ruflo memory while changing the system that writes to it.

## Before Any Change

- Read the current version of the file you're changing
- Check CHANGELOG.md for recent changes (avoid conflicting modifications)
- Run backup-knowledge.sh if the change touches hooks or learning logic

## After Any Change

- Run all validation scripts
- Test in isolated session (claude --plugin-dir ./system)
- Update CHANGELOG.md
- If the change is significant, note it in BACKLOG.md

## What You're Working With

system/CLAUDE.md        → The mastermind identity (edit carefully)
system/skills/          → Skills invoked across all clients
system/agents/          → Subagents available everywhere
system/commands/        → Slash commands available everywhere
system/rules/           → Always-loaded rules
system/settings.json    → Hook configurations
```

This is the recursive magic: when you `cd ~/projects/brana && claude`, the mastermind loads its own global identity AND the project-specific context for developing itself. It knows it's doing brain surgery.

---

## Feature Lifecycle for System Changes

Use the same SPARC phases from [doc 03](dimensions/03-pm-framework.md), adapted for self-modification.

### Example: Adding a `/pattern-confidence` command

**Specification:**
```markdown
## Feature: /pattern-confidence
Show confidence distribution of patterns in ruflo memory.
Helps identify which knowledge areas are strong (high confidence,
many uses) vs weak (low confidence, single use).

Acceptance criteria:
- Shows histogram of confidence scores
- Groups by project and by technology tag
- Flags patterns with declining confidence (used but failing)
```

**Pseudocode:**
```markdown
1. Query ruflo memory for all patterns
2. Group by confidence brackets: 0-0.3 (weak), 0.3-0.7 (moderate), 0.7-1.0 (strong)
3. Cross-reference with usage_count and success rate
4. Format as readable report
5. Highlight patterns that are frequently recalled but have low success (might be wrong)
```

**Architecture:**
- New file: `system/commands/pattern-confidence.md`
- Depends on: `npx ruflo@alpha hooks stats`
- Context cost: ~200 bytes for command description (within budget)
- No hook changes needed

**Refinement:**
- Test with current ruflo memory in isolated session
- Adjust output format based on real data
- Add to CHANGELOG.md

**Completion:**
- Validate, deploy, monitor
- The command itself becomes a tool for monitoring system health

---

## The BACKLOG.md

```markdown
# Brana System Backlog

## In Progress
- [ ] P1: Graceful hook failure mode — hooks should degrade, not crash

## Planned
- [ ] P2: /pattern-confidence command — visibility into knowledge quality
- [ ] P2: Context budget dashboard — real-time tracking of always-loaded size
- [ ] P3: Automated A/B testing framework for skill changes
- [ ] P3: Knowledge pruning — archive low-confidence, unused patterns

## Experiments
- [ ] E1: Try making SessionStart hook inject only top-5 patterns (less noise?)
- [ ] E2: Try confidence decay — patterns lose 5% confidence per month unused
- [ ] E3: Try "apprentice mode" for new projects — aggressive recall first week

## Done
- [x] v0.1.0: Initial system — CLAUDE.md, 5 skills, 3 agents, 3 rules
- [x] v0.2.0: Added deploy.sh and validation scripts
- [x] v0.2.1: Fixed: SessionStart hook was crashing on empty ruflo memory
```

---

## Danger Zones and Safety Mechanisms

### The Five Ways the System Can Break Itself

| Failure Mode | What Happens | Prevention | Recovery |
|---|---|---|---|
| **Broken SessionStart hook** | Every session starts broken. Can't query ruflo memory. | Hook must `exit 0` on error — degrade, don't block. Try/catch wrapper. | Rollback settings.json to last good version. Knowledge untouched. |
| **Corrupted CLAUDE.md** | Identity is garbled or empty. Claude behaves erratically. | Validation script checks CLAUDE.md isn't empty, has required sections. | Rollback symlink to last tagged commit. |
| **Context explosion** | Too much always-loaded content. Eats token budget. Slow, expensive. | Budget validation script blocks deploy if >15KB. | Remove newest rule/skill, re-deploy. |
| **ruflo memory corruption** | All cross-client memory lost. | Daily backups. Backup before every deploy. | Restore from latest backup. Gap is at most 1 day. |
| **Infinite hook loop** | Hook triggers action that triggers hook again. | Environment variable guard: `BRANA_HOOK_RUNNING=1`. Check before executing. | Kill session. Remove hook. Deploy without it. |

### The Self-Healing Hook

A lightweight check that runs at SessionStart BEFORE any ruflo memory queries:

```
SessionStart hook (first in chain):
  1. Does ~/.claude/CLAUDE.md exist and have content?
     → No? Restore from brana repo symlink.
  2. Does ~/.swarm/memory.db exist?
     → No? Log warning, skip ruflo memory queries, continue without memory.
  3. Are all skill files valid?
     → No? Log which ones are broken, disable them for this session.
  4. Is context budget within limits?
     → No? Log warning. System works but is degraded.

  Exit 0 always. Never block session start.
```

The system detects its own damage and either self-repairs or degrades gracefully. It never prevents you from starting a session — the worst case is "works like vanilla Claude Code" until you fix the issue.

---

## The Recursive Payoff

The system learns how to maintain itself:

```
Month 1: You manually edit skills, manually test, manually deploy.
  └─ It works but it's tedious.
  └─ ruflo memory stores: "When I changed the hook config, I forgot to
     validate first. Tests caught a syntax error."

Month 2: You develop a /self-test skill.
  └─ Pattern recalled: "Always validate before deploy."
  └─ The skill automates what you were doing manually.
  └─ ruflo memory stores: "The self-test skill caught 3 issues that
     would have broken production."

Month 3: You add a pre-deploy hook that runs validation automatically.
  └─ Pattern recalled: "Self-test is useful but I keep forgetting to run it."
  └─ Now it's impossible to deploy without validation.
  └─ ruflo memory stores: "Automated validation prevented a deployment
     of a skill with broken YAML frontmatter."

Month 6: The system suggests improvements to itself.
  └─ Cross-pollination: "In project-alpha, you solved a similar problem
     with a pre-commit hook. Your deploy.sh could use the same pattern."
  └─ The mastermind is now genuinely helping you develop... itself.
```

Each iteration makes the development process smoother because the system remembers what went wrong before and has patterns for avoiding it.

---

## The Version Strategy

### Semantic Versioning for the Brain

```
v0.1.0  — Initial system: CLAUDE.md, skills, agents, rules
v0.2.0  — Deploy pipeline + validation
v0.3.0  — Self-healing SessionStart hook
v0.3.1  — Fix: hook was too aggressive, injecting too many patterns
v0.4.0  — New skill: /pattern-confidence
v1.0.0  — Stable: all hooks reliable, deploy pipeline proven, 30 days without rollback
```

Major = new capabilities or breaking changes to skill interfaces.
Minor = new skills, commands, agents.
Patches = fixes to existing components.

### Tagging for Rollback

```bash
# Every deploy tags the commit
git tag -a v0.3.1 -m "Fix: SessionStart hook pattern injection limit"
./deploy.sh

# Rollback is just:
git checkout v0.3.0
./deploy.sh
# Knowledge store: untouched. Patterns from v0.3.1 era are still there.
```

---

## The Two Repos, Two Rhythms

```
brana.git                               FAST RHYTHM
├── system/                             Changes weekly. Intentional edits.
├── tests/                              Deploy pipeline protects production.
├── BACKLOG.md                          Feature lifecycle. SPARC phases.
└── CHANGELOG.md                        Explicit version history.

~/.swarm/memory.db                      SLOW RHYTHM
└── ruflo memory                       Changes every session. Organic growth.
    Backed up daily.                    Never rolled back. Only appended.
    Pruned occasionally.                Survives all system changes.

~/.claude/memory/                       MEDIUM RHYTHM
├── MEMORY.md                           Updated by Claude during sessions.
├── portfolio.md                        Updated when projects change.
└── retired/                            Updated when projects are archived.
    Also backed up.                     Can be in a separate knowledge repo
    Semi-structured.                    if you want version history.
```

The genome evolves deliberately through engineering. The connectome evolves organically through experience. Different lifecycles, different backup strategies, different rollback policies.

---

## Change Weight Classification

The real axis is **blast radius** — how many projects break if this change is wrong — not what type of file you're editing. And ceremony should decrease over time as the validation suite earns trust.

```
                        BLAST RADIUS
                            │
  Typo in a rule            │  ● Almost zero. One project, one session, recoverable instantly.
  New command               │  ● Low. Wrong output is annoying, not damaging.
  New skill                 │  ● Medium. Could confuse the model, but lazy-loaded — only on invoke.
  Agent capability change   │  ● Medium-high. Subagents run with autonomy.
  Hook modification         │  ● High. Hooks run on EVERY session, EVERY tool call.
  CLAUDE.md identity change │  ● Critical. Changes behavior everywhere, every project, every turn.
  Learning loop change      │  ● Nuclear. Corrupts future knowledge. See doc 16.
```

| Blast Radius | Protocol (Early) | Protocol (Tests Mature) |
|---|---|---|
| Almost zero | Edit, deploy, done | Same |
| Low | Validate + deploy | Same |
| Medium | Branch + validate + isolated test + deploy | Validate + deploy |
| High | Branch + validate + isolated test + 2-day bake + deploy | Branch + validate + isolated test + deploy |
| Critical | Full SPARC + staged rollout over 1 week | Branch + validate + A/B test + deploy |
| Nuclear | Full SPARC + knowledge backup + staged rollout + manual verification of first 3 sessions | Full SPARC + backup + staged rollout |

**Exception: learning loop changes are ALWAYS heavyweight.** The damage they cause is invisible — bad patterns entering ruflo memory look normal until they surface as wrong advice weeks later. You can't test for "will this produce subtly wrong learnings over 50 sessions." That requires slow rollout and observation. See [16-knowledge-health.md](dimensions/16-knowledge-health.md) for the full analysis of knowledge poisoning and the immune system design.

---

## System Change Review

The mastermind reviewing its own changes sounds circular, but it works — the same way developers review their own PRs before requesting peer review. The author-reviewer switch works because wearing the "reviewer hat" changes focus.

### The System Reviewer Agent

A dedicated adversarial agent in `system/agents/system-reviewer.md`:

```markdown
You are reviewing a proposed change to the mastermind system.
Your job is to find problems. Be adversarial. Assume every change
will break something until proven otherwise.

For every proposed change, answer:
1. What's the blast radius if this is wrong?
2. Can it fail silently? (Worst kind of failure.)
3. Does it increase always-loaded context? By how much?
4. Could it interfere with existing skills/hooks/rules?
5. Is there a simpler way to achieve the same thing?
6. What's the rollback plan?
```

This isn't the same agent reviewing itself — it's the same model with different instructions, different focus, different incentives. The reviewer agent has no investment in the change succeeding.

### Layered Review Model

| Change Weight | Review |
|---|---|
| Lightweight | Validation scripts only. No AI review. |
| Standard | Reviewer agent. Takes 30 seconds, catches "did you think about X?" |
| Heavyweight | Reviewer agent + you read the diff. Human eyes on hooks and identity. |
| Nuclear | Reviewer agent + you + let it bake for a week before trusting it. |

Reviews get stored in ruflo memory tagged `domain: brana-system`. Over time, the reviewer gets better because it recalls "last time someone changed a hook, the issue was X."

---

## Knowledge Migrations

ruflo memory patterns are unstructured JSON blobs with tags — not a rigid schema. So "migrations" are really **data transformations**: bulk operations on the pattern store.

Typical migrations:
- Rename tags: `"auth"` → `"authentication"` across all patterns
- Add fields: set `"transferable: true"` on all patterns with confidence > 0.8
- Split tags: `"backend"` → `"api"` + `"database"` based on content analysis
- Prune: archive patterns with confidence < 0.2 and unused for 6 months
- Re-score: recalculate confidence based on updated formula
- Merge: combine duplicate patterns (same problem, same solution, different sessions)

### Migration Scripts

```
brana/
├── migrations/
│   ├── 001-rename-auth-tags.sql
│   ├── 002-add-transferable-field.sql
│   ├── 003-prune-low-confidence.sql
│   └── applied.log                   ← Tracks which migrations ran
```

### Three Rules

1. **Idempotent.** Running the same migration twice produces the same result. If it partially fails, re-run safely. Use `UPDATE ... WHERE tag = 'auth'` not `UPDATE ALL`.

2. **Backup first.** Every migration script starts with `sqlite3 memory.db ".backup migration_backup.db"`. Non-negotiable.

3. **Tied to system versions.** Migration 002 runs when deploying system v0.4.0 because that version expects the `transferable` field. The deploy script checks `applied.log` and runs pending migrations automatically.

In practice, migrations happen rarely — maybe 2-3 per year. Don't build a framework upfront. A shell script running SQL queries is enough. Formalize only if you find yourself migrating often.

---

## Multi-Machine Sync

The system repo syncs via git — solved. The question is only about the knowledge store.

Options ranked by complexity:

### Option A: Don't Sync — Pick a Primary Machine

One machine is the brain. Laptop sessions don't contribute to or benefit from ruflo memory.

**Works when:** 90%+ of your work happens on one machine.
**Breaks when:** You travel for a week and a week of learnings is lost.

### Option B: Manual Periodic Export/Import

```bash
# Primary machine (export)
sqlite3 ~/.swarm/memory.db ".dump" > knowledge-export.sql
# Other machine (import)
sqlite3 ~/.swarm/memory.db < knowledge-export.sql
```

Merge strategy: append-only. If both machines have the same pattern, keep the higher confidence one.

**Works when:** Occasional machine switches, tolerable 1-day staleness.

### Option C: Shared Storage (Syncthing/NAS)

Put `memory.db` on Syncthing (peer-to-peer, no cloud dependency). One machine as "send only," the other as "receive only" to avoid concurrent writes.

**Danger:** SQLite doesn't handle concurrent writes from two machines. Use a lockfile:
```bash
if [ -f ~/.swarm/memory.lock ]; then
  echo "Another machine is using the brain. Wait or override."
  exit 1
fi
```

**Works when:** Never running Claude on both machines simultaneously.

### Option D: Turso/libSQL Remote Database

Replace local SQLite with Turso (hosted, multi-region, SQLite-compatible). Both machines connect to the same remote DB.

**Works when:** 3+ machines, need zero-thought sync.
**Breaks when:** Offline. Adds network dependency to every pattern query.

### Recommendation

**Start with Option A. Graduate to Option C when it hurts. Skip to D only if you're on 3+ machines regularly.** Don't build sync infrastructure until you've actually lost knowledge by not having it.

---

## When to Rewrite

### Detection: System Health Metrics

Track monthly:

| Metric | Healthy | Warning | Rewrite Signal |
|---|---|---|---|
| Rollbacks per month | 0-1 | 2-3 | 5+ |
| Workarounds in backlog | 0-2 | 3-5 | Most of backlog is working around limitations |
| Context budget utilization | <70% | 70-90% | Perpetually maxed, dropping things to fit |
| Time to deploy a simple change | <5 min | 5-15 min | Deploy is harder than the change itself |
| Skills that conflict | 0 | 1-2 | Can't add X without breaking Y |
| Hook chain complexity | Linear, 2-3 | Some branching | Need a flowchart to understand own hooks |
| How often you bypass the system | Never | Rarely | Skipping deploy pipeline because it's too slow |

The meta-signal: **when you're fighting the system more than using it, it's time.**

### Survival: Knowledge-First Migration

The knowledge is the asset, not the system. If genome/connectome are separated from day one, a rewrite is survivable:

1. **Export** — Dump ruflo memory to JSON. Copy all auto memory files, portfolio, retired projects.
2. **Build v3** — New CLAUDE.md, new skills, new hooks. Start from first principles.
3. **Import** — Load patterns into v3's knowledge store. The brain loses its wiring but keeps its memories.
4. **Validate** — Query patterns for known problems. Verify cross-pollination still works.
5. **Archive v2** — Tag final version. Its patterns about "how to maintain v2" become v3 patterns about "what went wrong with the previous version."

**Key design decision:** Keep the knowledge store system-agnostic. Tagged JSON blobs in SQLite can be read by ANY future system. The knowledge outlives the system.

### The Anti-Rewrite: Continuous Simplification

The best strategy is to never need a rewrite:

- **Prune regularly.** Remove unused skills. Delete rules that don't earn their context budget. Archive agents nobody invokes.
- **Resist accretion.** Every new component must justify its context cost. "Nice to have" isn't enough.
- **Refactor before adding.** Check if an existing component can be modified before creating a new one.
- **Track complexity.** The context budget check is a proxy for system complexity. If you're always near the limit, you're accumulating cruft.

### The Escape Hatch

Build a `/system-export` command from day one that dumps the entire knowledge store into a portable format (JSON + markdown). If you ever migrate to a different tool entirely, your knowledge comes with you.

---

## What Makes This Approach Unique

Most people using Claude Code treat it as a static tool — configure once, use forever. This approach treats it as a **living system under continuous development**:

- The system has its own backlog, changelog, and version tags
- Changes flow through a pipeline: branch → validate → stage → deploy → monitor
- Knowledge is separated from code — you can change the brain's wiring without losing its memories
- The system helps develop itself — patterns about self-maintenance compound over time
- Rollback is always safe — the worst case is "temporarily dumber," never "lost everything"
- Experiments are first-class — the backlog has an Experiments section for things to try
- Graceful degradation — broken components are skipped, not fatal

The end state: a system that gets better at two things simultaneously — solving your project problems AND maintaining itself.

---

## Resolved Questions

Questions from the initial brainstorm, now answered:

1. **How much ceremony per change?** → Resolved in Change Weight Classification above. Ceremony matches blast radius, and decreases as test coverage matures. Learning loop changes are always heavyweight.

2. **Who reviews system changes?** → Resolved in System Change Review above. Layered model: scripts for lightweight, adversarial reviewer agent for standard, human eyes for heavyweight/nuclear.

3. **Knowledge migrations?** → Resolved in Knowledge Migrations above. Idempotent SQL scripts, backup-first, tied to system versions. Expect 2-3 per year.

4. **Multi-machine sync?** → Resolved in Multi-Machine Sync above. Start with one primary machine. Graduate to Syncthing when it hurts. Don't over-engineer upfront.

5. **When to rewrite?** → Resolved in When to Rewrite above. Track 7 health metrics monthly. Knowledge-first migration when the signals are clear. Prefer continuous simplification to avoid needing a rewrite.

6. **Knowledge poisoning and health?** → Resolved in [16-knowledge-health.md](dimensions/16-knowledge-health.md). Comprehensive immune system: quarantine, dual-track confidence, transferability gates, decay, contradiction detection, failure attribution, anti-patterns.

---

## Remaining Open Questions

### Process
1. **Where are the exact blast-radius boundaries?** The classification above is a starting point. Experience will reveal whether "new skill" is truly medium or sometimes high. Tune the thresholds based on actual incidents.

2. **How to measure system quality over time?** Candidates: rollbacks/month, time-to-first-useful-output on new projects, pattern recall precision (how often recalled patterns actually help). Need to pick 3-4 metrics and track them.

### Knowledge
3. **What counts as "success" for a recalled pattern?** Tests passing? User explicitly approving? Session completing without errors? The definition shapes what the system optimizes for. See [doc 16](dimensions/16-knowledge-health.md) for deeper analysis.

4. **How to handle partially correct patterns?** A pattern that's 80% right and 20% wrong. Can't delete (80% is valuable) or keep as-is (20% causes damage). Need a refinement mechanism, not just accept/reject.

### Meta
5. **Should the system track its own metrics automatically?** A ruflo memory domain `brana-system` storing patterns about system maintenance. Over time, a "how to maintain me" knowledge base. The cost is extra patterns; the benefit is the system learning from its own maintenance history.

---

## Refresh Targets

**Versions:**
| Package | Pinned | Source |
|---------|--------|--------|
| ruflo | v3.1.0-alpha.34 | https://www.npmjs.com/package/claude-flow |
| Syncthing | — | https://github.com/syncthing/syncthing |

**Tools:**
- Claude Code CLI — new plugin/skill management features, deploy workflow changes
- ruflo — CLI updates, hook system changes, ruflo memory API changes
- Syncthing — version updates, conflict resolution improvements (multi-machine sync)
- BATS — test framework updates for bash hook testing

**Creators:**
- Anthropic — Claude Code plugin/skill system changes, new deployment patterns
- ruvnet — ruflo updates that affect brana system architecture

**Searches:**
- "Claude Code plugin deployment best practices 2026"
- "ruflo hook system updates 2026"
- "Syncthing conflict resolution dotfiles 2026"
- "Claude Code self-modifying agent systems"

**URLs:**
- https://code.claude.com/docs/en/skills
- https://code.claude.com/docs/en/plugins
- https://code.claude.com/docs/en/hooks
- https://github.com/ruvnet/claude-flow
