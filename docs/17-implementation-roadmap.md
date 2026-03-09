# 17 - Implementation Roadmap: Building the Mastermind on claude-flow

How to go from spec documents to a working system. claude-flow is the foundation — everything builds on it. Phased approach from skeleton to self-improving brain.

**Hard constraint:** claude-flow is the intelligence layer. Accept the alpha stability risk and plan around it.

---

## Design Context

Decisions that shape this roadmap:

| Constraint | Value | Implication |
|---|---|---|
| **Intelligence layer** | claude-flow (non-negotiable) | Accept alpha risk. Build safety nets. Never let instability block basic work. |
| **Subscription plan** | Max5 (1,000 msg/block) | Comfortable challenger budget. Can auto-challenge medium+ decisions, run debates on critical ones. |
| **Active projects** | 3-5 during build period | Good pattern accumulation rate. ~50 patterns in 4-6 weeks. Cross-pollination valuable early. |
| **Core value** | Cross-project intelligence | Phase 0-1 is scaffolding. Phase 2+ is where the system earns its existence. Invest quality engineering in the learning loop. |
| **PM framework** | Preserved from brana v1 | Code/PM repo separation continues. `/project-onboard` should bootstrap both `.claude/` and PM repo structure. |

---

## The Foundation Constraint: Why claude-flow

claude-flow provides what would take months to build from scratch:

| Capability | What claude-flow Gives You | Alternative Without It |
|---|---|---|
| **Cross-project memory** | ReasoningBank — SQLite-backed, tagged, queryable | Build your own or use flat files |
| **Self-learning** | SONA — trajectory tracking, MoE routing, anti-catastrophic-forgetting | Nothing. This doesn't exist natively. |
| **Vector intelligence** | RuVector — HNSW indexing, flash attention, pattern similarity | External vector DB or naive string matching |
| **Token routing** | WASM transforms (<1ms) → Haiku → Sonnet → Opus routing | Manual model selection or single-model everything |
| **Hook lifecycle** | Pre/post task hooks, recall/learn lifecycle | Custom bash scripts wired to settings.json |
| **Agent orchestration** | 60+ specialized agents, swarm coordination, consensus | Claude Code's native subagents (limited) |

**The tradeoff:** alpha stability, documentation gaps, potential breaking changes.
**The bet:** claude-flow is powerful and will keep improving. Building on it compounds with every upstream release.

---

## Risk Mitigation: Living on Alpha

### Pin Everything

```bash
# Pin to exact version, not range
npm install -g claude-flow@2.5.0-alpha.130

# In any script that calls claude-flow:
CLAUDE_FLOW_VERSION="2.5.0-alpha.130"
cd "$HOME" && npx claude-flow@$CLAUDE_FLOW_VERSION memory search --query "..."
```

Never `@latest` in production. Test new versions in staging before upgrading.

> **Updated (2026-02-12):** `npx claude-flow` is now an anti-pattern (see errata #25, lesson #17). npx creates a separate package cache missing sql.js. All scripts and `.mcp.json` must use the **global binary directly** instead:
> ```bash
> # Smart binary discovery (replaces npx in all examples below)
> CF=""
> for candidate in "$HOME"/.nvm/versions/node/*/bin/claude-flow; do
>     [ -x "$candidate" ] && CF="$candidate" && break
> done
> [ -z "$CF" ] && command -v claude-flow &>/dev/null && CF="claude-flow"
> cd "$HOME" && $CF memory search --query "test"
> ```
> `deploy.sh` auto-installs sql.js on every deploy. After manual `npm install -g claude-flow`, run: `npm install sql.js --prefix $(dirname $(which claude-flow))/..`

### Wrap Every Call

```bash
# Every claude-flow command wrapped in error handling
recall_patterns() {
  result=$(cd "$HOME" && npx claude-flow@$CLAUDE_FLOW_VERSION memory search --query "$1" 2>/dev/null)
  if [ $? -ne 0 ]; then
    echo "⚠ ReasoningBank unavailable. Working without memory."
    return 0  # Degrade, never crash
  fi
  echo "$result"
}
```

### Backup Before Upgrade

```bash
# upgrade-claude-flow.sh
#!/bin/bash
NEW_VERSION=$1

# 1. Backup knowledge store
sqlite3 ~/.swarm/memory.db ".backup upgrade_backup_$(date +%Y%m%d).db"

# 2. Install new version in parallel
npm install -g claude-flow@$NEW_VERSION

# 3. Run smoke tests
cd "$HOME" && npx claude-flow@$NEW_VERSION memory search --query "test" > /dev/null 2>&1
if [ $? -ne 0 ]; then
  echo "FAIL: New version can't query ReasoningBank. Keeping old version."
  npm install -g claude-flow@$CLAUDE_FLOW_VERSION
  exit 1
fi

# 4. Update pinned version
echo "Upgraded to claude-flow@$NEW_VERSION"
```

### Two-Layer Memory Architecture

Don't treat native auto memory as a "degraded fallback." Design it as **Layer 0** — the foundation that's always there. ReasoningBank is **Layer 1** — the intelligence enhancement on top.

```
Layer 0 — Native Auto Memory (always available, zero dependency)
  ~/.claude/memory/MEMORY.md          ← Cross-project facts (200 lines auto-loaded)
  ~/.claude/memory/patterns.md        ← Manual pattern notes (read on demand)
  ~/.claude/memory/portfolio.md       ← Project portfolio (read on demand)
  ~/.claude/projects/<proj>/memory/   ← Per-project auto memory
  ~/.claude/agent-memory/<agent>/     ← Subagent persistent memory (memory: user)

Layer 1 — ReasoningBank (when claude-flow available)
  ~/.swarm/memory.db                  ← Vector-indexed, tagged, queryable
  HNSW similarity search              ← Find semantically related patterns
  Confidence scoring                  ← Track what works vs what doesn't
  Automated decay                     ← Stale patterns fade naturally
```

**Normal mode:** Layer 1 enriches Layer 0. SessionStart queries ReasoningBank AND reads auto memory. Both contribute context.

**Degraded mode (claude-flow unavailable):** Layer 0 carries the load alone. The system is less intelligent but has access to everything you explicitly wrote to auto memory files. Learnings go to `~/.claude/memory/pending-learnings.md` and flush to ReasoningBank when it's back.

**Key design rule:** Anything critical enough to survive claude-flow outage should ALSO be written to Layer 0. The SessionEnd hook writes to both layers. Universal high-confidence patterns get appended to MEMORY.md, not just stored in ReasoningBank.

### SONA Fallback Plan

SONA (Phase 3) is the most speculative dependency — trajectory tracking, MoE routing, and EWC++ are partially documented and unproven at scale. If SONA doesn't deliver:

```
Plan A (SONA works):
  Pattern recall = vector similarity + tag filtering via HNSW
  Smart routing via MoE experts
  Anti-catastrophic-forgetting via EWC++
  Phase 3 delivers full intelligence layer

Plan B (SONA doesn't work):
  Pattern recall = tag-based search + keyword relevance scoring
  Routing via simple heuristics (blast radius → model tier)
  No forgetting prevention needed (patterns are in SQLite, not weights)
  Phase 3 delivers quarantine + skill discovery without SONA magic

Plan B cost:
  - No semantic search (must rely on good tagging discipline)
  - No MoE routing (manual model selection continues)
  - Challenge suggestions based on rules, not learned data
  - Still functional. Still valuable. Just not as smart.
```

**Decision point:** At Phase 3 start, spend 1 week evaluating SONA. If it can't reliably find relevant patterns in a test set of 50+, go with Plan B and revisit SONA in 2-3 months.

---

## Phase 0: The Skeleton (Week 1-2)

**Goal:** A working project structure with claude-flow installed, ReasoningBank initialized, and a knowledge export escape hatch. No intelligence yet — just the bones and the safety net.

**Bootstrap note:** This phase builds the safety rails while having no safety rails. You're doing manual brain surgery. Every file you create here will later be managed by the system it defines. Accept this — there's no way around it. The validation scripts are the first safety you build, so build them first and use them on everything that follows.

### What You Build

```
~/projects/brana/                        THE SYSTEM PROJECT
├── .claude/
│   ├── CLAUDE.md                        ← "You are developing the mastermind system"
│   └── rules/
│       └── self-edit-safety.md          ← Safety rails for self-modification
│
├── system/                              ← THE GENOME (deploys to ~/.claude/)
│   ├── CLAUDE.md                        ← Mastermind identity (minimal v0.1)
│   ├── rules/
│   │   ├── universal-quality.md         ← "Test before ship, no secrets in code"
│   │   └── git-discipline.md            ← "Conventional commits, branch protection"
│   ├── skills/                          ← Empty, populated in Phase 1
│   ├── agents/                          ← Empty, populated in Phase 1
│   ├── scripts/                         ← Shared bash utilities (cf-env.sh, memory-store.sh)
│   ├── commands/                        ← Slash commands (session-handoff.md, init-project)
│   ├── skill-catalog.yaml               ← Curated external skills (populated in Phase 1)
│   └── settings.json                    ← Hooks (all disabled, wired in Phase 2)
│
├── tests/
│   ├── validate-syntax.sh              ← YAML frontmatter validation
│   ├── validate-context-budget.sh      ← 15KB budget enforcement
│   └── validate-hooks.sh               ← Hook integrity checks
│
├── deploy.sh                            ← Symlink-based deploy
├── rollback.sh                          ← Tag-based rollback
├── backup-knowledge.sh                  ← ReasoningBank + memory backup
├── export-knowledge.sh                  ← Portable JSON export (escape hatch)
├── BACKLOG.md
├── CHANGELOG.md
└── README.md
```

**Testing strategy:** The actual implementation uses a 3-layer test suite: `validate.sh` (static checks — YAML, JSON, syntax, secrets, context budget), `test-hooks.sh` (pipe fake JSON to deployed hooks, verify exit 0 + valid JSON), `test-memory.sh` (claude-flow store → search → verify round-trip). Wrapped by `test.sh` which runs all layers. The full 7-layer pyramid from [22-testing.md](dimensions/22-testing.md) is adopted pain-driven — add layers as failures motivate them, not upfront. Run `./test.sh` before merging to master.

### claude-flow Setup

```bash
# Install and pin
npm install -g claude-flow@2.5.0-alpha.130

# Initialize ReasoningBank
npx claude-flow init
# Creates ~/.swarm/memory.db (empty)
# Creates ~/.swarm/config.yaml

# Verify it works
cd "$HOME" && npx claude-flow memory search --query "test"
# Should return empty results, not an error
```

### Deploy Pipeline

Wire up the symlink deploy from [15-self-development-workflow.md](./15-self-development-workflow.md):
- `deploy.sh`: validate → symlink `system/*` → `~/.claude/*` → tag
- `rollback.sh`: checkout previous tag → re-deploy
- `backup-knowledge.sh`: snapshot `memory.db` + auto memory files

### The Escape Hatch (Day 1, Not Day 90)

```bash
# export-knowledge.sh — portable knowledge dump
#!/bin/bash
EXPORT_DIR="$1"
[ -z "$EXPORT_DIR" ] && EXPORT_DIR="./knowledge-export-$(date +%Y%m%d)"
mkdir -p "$EXPORT_DIR"

# Export ReasoningBank to JSON (if available)
if [ -f ~/.swarm/memory.db ]; then
  sqlite3 ~/.swarm/memory.db "SELECT json_object(
    'id', id, 'type', type, 'domain', domain,
    'pattern_data', pattern_data, 'confidence', confidence,
    'usage_count', usage_count, 'created_at', created_at
  ) FROM patterns;" > "$EXPORT_DIR/reasoning-bank.json" 2>/dev/null
fi

# Export auto memory (always available)
cp -r ~/.claude/memory/ "$EXPORT_DIR/auto-memory/" 2>/dev/null
cp -r ~/.claude/agent-memory/ "$EXPORT_DIR/agent-memory/" 2>/dev/null

# Export per-project memory
for proj_mem in ~/.claude/projects/*/memory/; do
  proj=$(basename $(dirname "$proj_mem"))
  cp -r "$proj_mem" "$EXPORT_DIR/project-memory-$proj/" 2>/dev/null
done

echo "Knowledge exported to $EXPORT_DIR"
echo "This is system-agnostic. Can be imported into any future system."
```

If claude-flow dies tomorrow, this JSON + markdown export preserves everything. Build it before you put a single pattern in.

### Context Budget

Start minimal:
- `CLAUDE.md`: ~2KB (identity + core principles)
- 2 rules: ~500 bytes each
- Total always-loaded: ~3KB (well under 15KB budget)

### Exit Criteria

**Functional:**
- [x] `cd ~/projects/brana && claude` loads the system identity
- [x] `deploy.sh` successfully symlinks to `~/.claude/`
- [x] `rollback.sh` restores previous version
- [x] `backup-knowledge.sh` creates ReasoningBank snapshot
- [x] `export-knowledge.sh` produces portable JSON + markdown
- [x] All validation scripts pass
- [x] claude-flow CLI responds to basic commands

**Value:** Phase 0 has no value metric — it's pure scaffolding. That's OK. The value starts in Phase 1.

- [x] Tag: `v0.1.0`

---

## Phase 1: Foundation Skills + Plugins (Weeks 2-4)

**Goal:** The six mastermind skills from [14-mastermind-architecture.md](reflections/14-mastermind-architecture.md), plus foundational plugins. The brain has its core capabilities but no automated learning yet. This is scaffolding — invest just enough polish to be usable, save quality engineering for Phase 2.

### Skills

Build in this order (each depends on the previous being conceptually proven):

| # | Skill | claude-flow Feature | Why This Order |
|---|-------|-------------------|---------------|
| 1 | `/brana:memory recall` | `memory search -q` | Most fundamental — query before working |
| 2 | `/brana:retrospective` | `memory store -k -v --namespace --tags` | Store learnings manually — test the write path |
| 3 | `/project-onboard` | `memory search -q` | Cross-project query — validates tagging |
| 4 | `/brana:memory pollinate` | `memory search -q` | Most nuanced — needs patterns to exist first |
| 5 | `/brana:project-retire` | `memory store` + bulk operations | Least urgent, most complex |
| 6 | `/brana:challenge` | Task tool with `model: "sonnet"` | Cross-model adversarial review — see [13-challenger-agent.md](dimensions/13-challenger-agent.md) |

### Plugins to Install

From the [11-ecosystem-skills-plugins.md](dimensions/11-ecosystem-skills-plugins.md) analysis:

| Plugin | Why | Scope |
|--------|-----|-------|
| **security-guidance** (Anthropic) | PreToolUse safety net — blocks dangerous commands | Global |
| **commit-commands** (Anthropic) | Consistent git workflow everywhere | Global |
| **claude-md-management** (Anthropic) | Keeps CLAUDE.md files healthy | Global |
| **Context7 MCP** | Real-time library docs — always-current knowledge | Global |

### Agents

| Agent | Role | Notes |
|-------|------|-------|
| `system-reviewer.md` | Adversarial review of system changes | From [15-self-development-workflow.md](./15-self-development-workflow.md) |
| `scout.md` | Haiku-powered fast research | Low-cost reconnaissance for memory recall |

### Commands

| Command | Purpose |
|---------|---------|
| `/what-do-i-know` | Query all memory for a topic |
| `/teach-me` | Manually inject a pattern into ReasoningBank |
| `/portfolio` | Show all projects + cross-project insights |

### Skill Catalog (Tier 2)

Create `system/skill-catalog.yaml` — a passive reference of vetted external skills. Not installed, zero context cost, but known-good. See [12-skill-selector.md](dimensions/12-skill-selector.md) for the full trust model.

As you manually install and evaluate skills during this phase, add the good ones to the catalog with version pin + checksum. This catalog grows organically through actual use, not upfront speculation.

### PM Framework Integration

The code/PM repo separation from brana v1 (doc 03) carries forward. Phase 1 ensures the mastermind is aware of it:

- **`/project-onboard`** should detect existing PM repos (via symlink at `.claude/context/pm`) and note their structure
- **`~/.claude/rules/pm-awareness.md`** (unconditional rule): "When starting a feature, check for a PM repo at .claude/context/pm. If it exists, read the BACKLOG.md and current sprint before planning."
- **`/project-onboard`** for new projects: "Suggest creating a PM repo and symlinking it per the brana convention. Offer to scaffold features/ planning/ architecture/ decisions/ structure."

This is lightweight — a rule + awareness in the onboard skill. The PM framework itself is organizational, not something claude-flow handles. But the mastermind should know about it.

### User Feedback Loop

Create [00-user-practices.md](./00-user-practices.md) (or its equivalent in the brana project) during Phase 1 setup. This is the user's field notebook — patterns discovered through real usage that feed back into system evolution. Categories: session workflow, memory, skills, hooks, deploy, cross-project, system evolution, anti-patterns.

The graduation pathway (manual practice → automated hook/check) becomes actionable in Phase 2 when hooks exist. But the document should exist from Phase 1 so observations start accumulating immediately. When multiple entries cluster around the same pain point, that's a signal to automate — a practice the user has to remember manually should eventually become a hook or validation check.

### Context Budget Check

After Phase 1:
- `CLAUDE.md`: ~2KB
- 2 rules: ~1KB
- 6 skill descriptions (frontmatter only): ~1.8KB
- 2 agent descriptions: ~500 bytes
- 3 command descriptions: ~500 bytes
- **Total: ~5.8KB** (within budget)

### Exit Criteria

**Functional:**
- [x] All 6 skills manually invokable and working
- [x] `/brana:memory recall` returns results from manually-inserted test patterns
- [x] `/brana:retrospective` successfully stores patterns in ReasoningBank
- [x] All plugins installed and functional
- [x] System reviewer agent catches at least one test issue
- [x] `/brana:challenge` skill spawns Sonnet subagent and returns actionable feedback
- [x] `skill-catalog.yaml` created with at least 5 vetted external skills
- [x] PM awareness rule in place
- [x] Context budget under 15KB
- [x] `./test.sh` passes all layers (validate + hooks + memory)

**Value:** Use skills in 3+ real sessions across different projects. After each session ask: "Did `/brana:memory recall` surface anything useful? Did `/brana:challenge` catch a real issue?" If not, adjust skill instructions before Phase 2. A skill that's invokable but unhelpful is worse than no skill (it wastes context).

- [x] Tag: `v0.2.0`

---

## Phase 2: The Learning Loop (Weeks 4-6)

**Goal:** Automated knowledge accumulation. Hooks fire on every session — recall on start, learn on stop, notice during work. The brain starts remembering on its own.

**This is where the system earns its existence.** Phase 0-1 was scaffolding. Phase 2 is the difference between "organized Claude Code" and "a brain that learns." Invest quality engineering here — test the hooks thoroughly, tune the learning extraction, validate that recalled patterns actually help.

### The Three Hooks

Wire these into `system/settings.json` per the design in [14-mastermind-architecture.md](reflections/14-mastermind-architecture.md). See [09-claude-code-native-features.md](dimensions/09-claude-code-native-features.md) for the hook JSON format, all 14 events, stdin/stdout contracts, and async constraints.

#### Hook 1: SessionStart — "Remember what you know"

```
Trigger: Every session start
Action:
  1. Detect current project (pwd, git remote)
  2. Query ReasoningBank for:
     a. Patterns tagged with this project
     b. Patterns from similar tech stacks
     c. Universal high-confidence patterns (>0.8)
  3. Inject brief context summary
Fallback: If claude-flow unavailable → skip, log warning
```

**claude-flow command:** `cd "$HOME" && npx claude-flow@$VERSION memory search --query "project:$(basename $PWD)"`

#### Hook 2: SessionEnd — "Remember what you learned"

```
Trigger: Session termination (fires once — NOT Stop, which fires every response)
Action:
  1. Analyze session: problems solved, approaches tried
  2. Extract patterns (problem→solution, failures, architecture decisions)
  3. Store in ReasoningBank with:
     - domain: project name
     - tags: technologies, problem types
     - confidence: 0.5 (quarantine — per doc 16)
     - transferable: false (per doc 16 quarantine rules)
  4. ALWAYS also write to Layer 0:
     - Universal patterns → append to ~/.claude/memory/MEMORY.md
     - Project patterns → append to project auto memory
     - This ensures critical knowledge survives claude-flow outages
Fallback: If claude-flow unavailable → write to ~/.claude/memory/pending-learnings.md
```

**claude-flow command:** `cd "$HOME" && npx claude-flow@$VERSION memory store -k "pattern:$PROJECT:{id}" -v '{...}' --namespace patterns --tags "project:$PROJECT"`

#### Hook 3: PostToolUse + PostToolUseFailure — "Notice important moments"

```
PostToolUse:
  Trigger: Write|Edit|Bash (filtered by matcher) — fires on SUCCESS
  Action:
    - If tests pass after a fix → record the fix pattern
    - If deployment succeeds → record the deployment approach
    Filter: Only fire on learning-worthy moments (not every file save)
  Fallback: Skip entirely if claude-flow unavailable

PostToolUseFailure (SEPARATE event — needs its own hook config):
  Trigger: Write|Edit|Bash — fires on FAILURE
  Action:
    - Record what didn't work (anti-patterns are often more valuable than successes)
    - Store as type: "failure" in ReasoningBank
  Fallback: Skip entirely if claude-flow unavailable
```

**Important:** Both hooks must be async (`"async": true`) and lightweight. Use environment variable guard (`BRANA_HOOK_RUNNING=1`) to prevent infinite loops. Async hooks cannot block or return decisions — they can only log and provide feedback on the next turn.

### Hook Capabilities to Leverage (from deep dive — see [20-anthropic-blog-findings.md](dimensions/20-anthropic-blog-findings.md))

Several hook capabilities discovered during the doc research that improve the learning loop:

**Async hooks (`"async": true`):** PostToolUse hooks can run in the background without blocking Claude's work. The learning extraction hook can be async — Claude continues working while the pattern is stored. Only `type: "command"` supports async. Cannot block or return decisions.

**`CLAUDE_ENV_FILE` in SessionStart:** Rather than injecting context via `additionalContext` JSON, SessionStart can write environment variables to `$CLAUDE_ENV_FILE` that persist for all subsequent Bash commands in the session. Useful for setting `BRANA_PROJECT=alpha`, `BRANA_HOOK_RUNNING=1`, etc.

**`PreToolUse` with `updatedInput`:** PreToolUse hooks can modify tool input before execution by returning `updatedInput` in the JSON output. A security hook could rewrite dangerous commands, or a PM hook could inject issue references into commit messages.

**`PostToolUseFailure` event:** Fires specifically when a tool fails (separate from PostToolUse which fires on success). The learning loop should capture failure patterns here — "what went wrong" is often more valuable than "what worked."

**Agent Teams hooks (`TeammateIdle`, `TaskCompleted`):** Quality gates for agent team work. TeammateIdle (exit 2 → teammate keeps working with stderr feedback). TaskCompleted (exit 2 → task stays incomplete with feedback). Relevant for Phase 5 when agent teams are used for parallel work.

### Testing the Loop

```
Test sequence:
  1. Start a session in a test project
  2. Verify SessionStart hook fires and queries ReasoningBank
  3. Solve a problem, make tests pass
  4. End session
  5. Verify SessionEnd hook extracted and stored patterns
  6. Start a NEW session in the same project
  7. Verify SessionStart recalls the pattern from step 3
  8. Start a session in a DIFFERENT project with same tech
  9. Verify pattern is NOT recalled (still in quarantine, not transferable)
```

**Testing methodology:** This sequence is the record/playback pattern from [22-testing.md](dimensions/22-testing.md) — capture hook inputs/outputs during a real session, then replay as a deterministic CI test. The manual sequence above should be converted to an automated replay test once the loop is stable.

**Measuring recall quality:** Use RAG metrics from [23-evaluation.md](dimensions/23-evaluation.md) and the eval framework in [14-mastermind-architecture.md](reflections/14-mastermind-architecture.md#evaluating-the-brain): precision@k (were recalled patterns relevant?), recall@k (were relevant patterns found?), staleness rate (<15%). The >50% value target in exit criteria maps to precision@5 > 0.5.

### Early Quarantine (Immune System Layer 1)

Don't wait for Phase 4 to quarantine patterns. Quarantine is the single most important immune mechanism (doc 16) and costs almost nothing to implement. Wire it into the SessionEnd hook from day 1:

```
Every new pattern stored via SessionEnd hook:
  confidence: 0.5 (regardless of in-session success)
  status: quarantined
  transferable: false (locked to source project)
  promotion: needs 3 successful recalls in different sessions
```

This alone prevents the worst failure mode — bad patterns cross-pollinating before they're proven. The remaining immune system layers (dual-track confidence, decay, contradiction detection) wait for Phase 4 when there's enough data to justify the complexity.

### The Markdown Fallback

When claude-flow is unavailable, learnings go to `~/.claude/memory/pending-learnings.md`:

```markdown
## Pending Learnings (will sync to ReasoningBank when available)

### 2026-02-10 — project-alpha
- **Problem:** Supabase RLS not applying to server routes
- **Solution:** Use service_role key through server client
- **Failed:** Tried disabling RLS, tried passing user JWT
- **Tags:** supabase, auth, rls, server-side
```

A daily cron or next-SessionStart can flush pending learnings to ReasoningBank.

### Exit Criteria

**Functional:**
- [x] SessionStart hook fires and injects relevant context
- [x] SessionEnd hook extracts patterns and stores them (ReasoningBank + Layer 0)
- [x] PostToolUse hook captures learning-worthy moments
- [x] All hooks degrade gracefully when claude-flow is unavailable
- [x] No infinite hook loops (environment guard works)
- [x] Full recall→learn→recall cycle verified end-to-end
- [x] Markdown fallback works when ReasoningBank is down
- [x] Quarantine operational: new patterns enter with 0.5 confidence, transferable: false
- [x] Challenge outcomes stored in ReasoningBank (type: "challenge", with flavor and outcome)

**Value (the real test):**
- [x] After 10+ sessions across 2+ projects, review recalled patterns. What percentage were actually useful? Target: >50% relevance. If below, the tagging strategy or recall query needs tuning before Phase 3.
- [x] At least one cross-project moment: a pattern from project A surfaced (via manual `/brana:memory pollinate`) and helped in project B.
- [x] At least one failure-memory moment: the system recalled a failed approach and the user avoided repeating it.

**Pattern accumulation check:** Track pattern count. You need ~50 for SONA activation in Phase 3. At 3-5 projects × 2-3 sessions/week × 5-10 patterns/session, expect 30-75 patterns over Phase 2's 2-3 weeks. If accumulation is slower, extend Phase 2 rather than rushing to Phase 3 with insufficient data.

- [x] Tag: `v0.3.0`

---

## Phase 3: Intelligence Layer + SONA (Weeks 6-10)

**Goal:** Activate the advanced claude-flow intelligence features — IF they work. SONA self-learning, token routing for cost optimization, and the quarantine promotion system. This phase has a built-in evaluation gate: if SONA doesn't deliver, fall to Plan B (see Risk Mitigation above) and still get quarantine, skill discovery, and challenge improvements.

### SONA Activation

From [06-claude-flow-internals.md](dimensions/06-claude-flow-internals.md): SONA (Self-Organizing Neural Architecture) provides trajectory tracking, MoE (Mixture of Experts) routing, and EWC++ catastrophic forgetting prevention.

**When to activate:** After ~50-100 patterns have accumulated in ReasoningBank. Before that, there isn't enough data for SONA to find meaningful trajectories.

```
Pre-SONA (Phase 0-2):
  Pattern recall = tag-based search (exact match on project, technology tags)
  Simple but works with small pattern counts

Post-SONA (Phase 3+):
  Pattern recall = vector similarity + tag filtering
  HNSW indexing finds semantically similar patterns, not just tag matches
  MoE routing selects which "expert" (pattern cluster) to consult
```

**Activation steps (with evaluation gate):**
1. Verify 50+ patterns exist in ReasoningBank
2. Enable SONA in `~/.swarm/config.yaml`
3. Run initial training: `npx claude-flow neural train`
4. **Evaluation gate (1 week):**
   a. Prepare 10 test queries (problems you've already solved, answers known)
   b. Run each query with SONA and with tag-only
   c. Compare: does SONA surface more relevant patterns?
   d. **If SONA wins on 7/10+:** proceed with Plan A
   e. **If SONA wins on <7/10:** fall to Plan B — keep tag-based recall, skip MoE routing, proceed with quarantine and skill discovery using keyword search
5. Monitor for 1 week before trusting SONA for daily use

### Evaluation Methodology (from Anthropic's Evals Research)

The SONA evaluation gate above follows Anthropic's proven eval methodology (see [21-anthropic-engineering-deep-dive.md](dimensions/21-anthropic-engineering-deep-dive.md), section 11 and [23-evaluation.md](dimensions/23-evaluation.md) for the full eval strategy). Key principles to apply:

**Start small:** Begin with 20-50 real queries, not comprehensive suites. These should represent actual problems you've solved — known answers that can be verified.

**Grade outcomes, not paths:** Evaluate whether SONA surfaces the *right* patterns, not whether it uses the expected search strategy. A creative path to the right answer is still correct.

**pass@k vs pass^k:** At 75% success per trial with 3 trials, pass@3 = ~97% (at least one succeeds) but pass^3 = ~42% (all must succeed). For pattern recall, pass@1 is what matters — does the first query return useful results?

**Capability vs regression:** The SONA gate is a capability eval (can it do better?). Once SONA is accepted, convert the test queries into a regression suite — run them after every claude-flow upgrade to verify nothing degraded.

**Infrastructure noise awareness:** Score differences below 3% should be treated with skepticism. SONA must show a *clear* improvement, not a marginal one within noise range.

### Token Routing

Route pattern processing through the optimal model tier:

```
WASM Transform (<1ms, $0)
  └─ Simple pattern matching, tag filtering, confidence checks
  └─ Handles 80% of recall queries

Haiku (~500ms, ~$0.0002)
  └─ Pattern relevance scoring, summarization
  └─ "Is this pattern relevant to the current task?"

Sonnet (1-3s, ~$0.003)
  └─ Cross-pollination analysis, pattern adaptation
  └─ "How does this pattern from project-alpha apply to project-beta?"

Opus (2-5s, ~$0.015+)
  └─ Complex architectural reasoning, contradiction resolution
  └─ Only for deep analysis tasks, not routine recall
```

**Implementation:** Configure in `~/.swarm/config.yaml` with routing rules per operation type.

### Pattern Promotion (building on Phase 2 quarantine)

Phase 2 established quarantine (patterns enter with 0.5 confidence, transferable: false). Now add the promotion path:

```
Layer 2 — Dual-Track Confidence:
  session_confidence: how well it worked when first stored
  validated_confidence: how well it's worked across recalls
  Only validated_confidence used for ranking and promotion decisions

Promotion path:
  3 successful recalls in different sessions → status: trusted
  Successful in 2+ different projects → transferable: true
```

### Skill Discovery and Install (from [doc 12](dimensions/12-skill-selector.md)/13)

With SONA active, build two new commands from the [12-skill-selector.md](dimensions/12-skill-selector.md) trust model:

**`/skill-discover`** — searches registries (skills.sh, etc.) using SONA semantic search. Shows results but **never auto-installs**. Human decides.

**`/skill-install`** — installs from the curated catalog only. Verifies checksum, installs to project scope (never global), applies skill quarantine.

**Skill quarantine:** extends the pattern quarantine model to external skills. New skills from Tier 2/3 enter probation — 3 successful uses + human review before promotion. No external skill ever auto-promotes to global Tier 1.

### Smart Challenge Suggestions (from [doc 13](dimensions/13-challenger-agent.md))

With SONA active and challenge outcomes accumulated from Phase 2, the system can suggest when to challenge. See [13-challenger-agent.md](dimensions/13-challenger-agent.md) for the full design.

```
SONA query: "How often were challenges on architecture changes accepted?"
  → "45% acceptance rate. Recommend running /brana:challenge."

Rate-limit aware: only suggest if quota > 50% remaining.
```

### Exit Criteria

**Functional:**
- [x] SONA evaluation gate completed (Plan A or Plan B decision documented)
- [x] If Plan A: vector similarity search returns better results than tag-only on 7/10+ test queries
- [x] If Plan B: tag-based recall refined with better tagging discipline
- [x] Token routing configured (or deferred if SONA is Plan B)
- [x] Dual-track confidence scoring in place
- [x] Pattern promotion path working: quarantined → trusted → transferable
- [x] `/skill-discover` returns relevant results from registries
- [x] `/skill-install` installs from catalog with checksum verification
- [x] Skill quarantine operational for external skills
- [x] System suggests `/brana:challenge` based on blast radius + historical acceptance rate

**Value:**
- [x] Pattern recall precision: >60% of recalled patterns rated useful by you in real sessions (up from Phase 2's >50% baseline — intelligence layer should improve this)
- [x] At least one quarantined pattern either promoted (proven useful) or demoted (caught a bad pattern early)
- [x] At least one external skill discovered, vetted, and added to catalog based on actual project need
- [x] Cost per session measurably lower with token routing (if Plan A) or documented baseline for future comparison (if Plan B)
- [x] Tag: `v0.4.0`

---

## Phase 4: Knowledge Health (Weeks 10-14)

**Goal:** Full immune system from [16-knowledge-health.md](dimensions/16-knowledge-health.md). The brain doesn't just learn — it monitors, detects, and heals its own knowledge.

### Remaining Immune System Layers

Phase 3 built quarantine + dual-track confidence. Now add:

#### Layer 3: Transferability Gates

```
Project-local (default)
  → 3+ successful sessions in same project
    → Promoted to project-trusted

Project-trusted
  → 2+ successes in DIFFERENT projects with same technology
    → Promoted to transferable

Transferable
  → Available for cross-pollination
```

#### Layer 4: Decay Function

```
Monthly decay:
  Recalled and succeeded:    no decay
  Recalled and failed:       -0.2 confidence
  Not recalled this month:   -0.05 confidence
  Not recalled in 3 months:  -0.1/month (accelerating)
  Below 0.2 confidence:      auto-archived
```

#### Layer 5: Contradiction Detection

On every new pattern storage, check for existing patterns with overlapping tags and conflicting solutions. Flag conflicts for review rather than silently storing.

### Detection Tools

Build the `/knowledge-audit` skill:

```
Monthly audit:
  1. All patterns with confidence > 0.7 (trusted set)
  2. Evaluate: still correct? truly universal? contradictions?
  3. Flag: stale, contradictory, context-specific, inflated
  4. Generate health report
```

Build the `/system-health` command:

```
Quick metrics:
  - Total patterns (trusted / quarantined / archived)
  - Anomalies (high confidence + low success rate)
  - Staleness distribution
  - Context budget utilization
  - Rollbacks this month
```

### Failure Attribution

Wire into the learning loop:

```
When a session has failures:
  1. Which patterns were recalled?
  2. Which were applied?
  3. Did they contribute to the failure?
  → Yes: downgrade validated_confidence by 0.15
  → If cross-pollinated: downgrade in ALL projects
```

### Healing: Anti-Patterns

Implement the conversion from bad patterns to anti-patterns (see [16-knowledge-health.md](dimensions/16-knowledge-health.md)):
- Never delete — convert to explicit warnings
- Cascading correction for cross-pollinated bad patterns
- Anti-pattern library grows into "things learned the hard way"

### Exit Criteria

**Functional:**
- [x] All 5 immune system layers operational (quarantine from Phase 2, dual-track from Phase 3, transferability gates + decay + contradiction detection from this phase)
- [x] Transferability gates preventing premature cross-pollination
- [x] Decay function running monthly (cron or manual)
- [x] Contradiction detection catching conflicting patterns
- [x] `/knowledge-audit` skill produces actionable health reports
- [x] `/system-health` command shows key metrics
- [x] Failure attribution connected to learning loop

**Value:**
- [x] At least one bad pattern caught by the immune system and converted to anti-pattern
- [x] At least one stale pattern decayed and archived (proving decay function works on real data)
- [x] Knowledge audit report shows >80% of trusted patterns are still correct
- [x] New project bootstrapping: `/project-onboard` on a new project delivers useful initial context from portfolio (time from `cd` to productive work measurably shorter)
- [x] Tag: `v0.5.0`

---

## Phase 5: Self-Improvement (Month 4+)

**Goal:** The system suggests improvements to itself, tests them, and evolves. The recursive payoff from [15-self-development-workflow.md](./15-self-development-workflow.md).

### A/B Testing Framework

For significant changes (new skills, hook modifications, identity changes):

```
Week 1: Deploy version A (current). Record metrics.
Week 2: Deploy version B (candidate). Record same metrics.
Compare:
  - Pattern recall precision (how often recalled patterns helped)
  - Time-to-first-useful-output on new sessions
  - Rollback frequency
  - User satisfaction signals (tests passing, session flow)
```

Store A/B results in ReasoningBank tagged `domain: brana-system`.

### System Health Dashboard

Track monthly (from [doc 15](15-self-development-workflow.md)'s "When to Rewrite" section):

| Metric | Target | Warning | Action |
|---|---|---|---|
| Rollbacks per month | 0-1 | 2-3 | Investigate root causes |
| Context budget utilization | <70% | 70-90% | Prune unused components |
| Time to deploy simple change | <5 min | 5-15 min | Simplify pipeline |
| Skills that conflict | 0 | 1-2 | Resolve or merge |
| Pattern recall precision | >70% | 50-70% | Improve tagging/SONA |
| Knowledge health (audit score) | >80% clean | 60-80% | Run healing pass |

### The System Suggesting Its Own Improvements

Once the system has enough self-referential patterns (`domain: brana-system`), it can:

1. **Notice recurring problems** — "The last 3 sessions started slow because SessionStart hook is querying too many patterns. Suggest: limit to top-10 by confidence."
2. **Cross-pollinate from other projects** — "In project-alpha, you solved a similar problem with caching. Your hooks could use the same pattern."
3. **Identify unused components** — "The `/brana:project-retire` skill hasn't been invoked in 3 months. Consider archiving it to save context budget."

This is the recursive payoff: the brain improving its own wiring based on what it's learned about maintaining itself.

### Auto-Challenge on Plan Mode (from [doc 13](dimensions/13-challenger-agent.md))

Hook on ExitPlanMode for high-blast-radius plans. Haiku pre-screens, Sonnet digs deep if warranted. Rate-limit-aware — self-regulates based on remaining quota. See [13-challenger-agent.md](dimensions/13-challenger-agent.md).

**Max5 budget calibration:** With 1,000 messages/block, the challenger has comfortable headroom. Default strategy:
- Auto-challenge on medium+ blast radius (Haiku pre-screen → Sonnet if warranted)
- Multi-round debates on critical/nuclear decisions (4-5 messages)
- Budget guard: skip auto-challenges below 40% remaining quota
- This consumes ~5-10% of the message budget — well within comfortable range

The system doesn't challenge everything — it challenges where the data says challenges are most likely to catch real issues.

### Smart Skill Suggestion on Onboard (from [doc 12](dimensions/12-skill-selector.md)/13)

`/project-onboard` now leverages the skill catalog and ReasoningBank effectiveness data:

```
/project-onboard
  → Detects: Django project, PostgreSQL, Redis
  → Catalog match: django-migrations (vetted, used 5 times, 90% success)
  → ReasoningBank: "django-migrations was effective in project-beta"
  → "This is a Django project. Recommended catalog skills:
     - django-migrations (proven in 2 projects)
     No Redis-specific skill in catalog — consider /skill-discover."
```

This is the earned automation — the system has enough data to make smart suggestions. Still requires human approval for install.

### System Reviewer Agent Evolution

The adversarial reviewer agent from Phase 1 now has accumulated review patterns:

```
ReasoningBank query: domain=brana-system, type=review
  → "Last time someone changed a hook, the issue was missing error handling"
  → "Identity changes tend to have subtle effects that show up 3-4 sessions later"
  → "Context budget violations correlate with adding rules, not skills"
```

The reviewer gets better at reviewing because it remembers what went wrong before.

### Evolving the Export Escape Hatch

`export-knowledge.sh` was built in Phase 0. By now it should be enriched to also export:

```bash
# Phase 5 additions to the export script:
# - Challenge outcomes and acceptance rates
# - Immune system metadata (quarantine states, confidence trajectories)
# - Self-referential patterns (domain: brana-system)
# - A/B test results and system health history
# - Skill catalog with effectiveness data
```

The escape hatch grows with the system. Every new data type stored gets an export path.

### Exit Criteria

**Functional:**
- [x] A/B testing framework operational for system changes
- [x] Monthly health dashboard tracking 6+ metrics
- [x] System generating improvement suggestions from self-referential patterns
- [x] Reviewer agent recalling past review insights
- [x] `/project-onboard` suggests catalog skills based on tech stack + effectiveness data
- [x] Auto-challenge hook operational on plan mode for high-blast-radius plans

**Value (the ultimate test — is this brain actually smarter?):**
- [x] At least one system improvement suggested AND implemented by the system itself
- [x] New project bootstrapping is measurably faster than month 1 (the portfolio effect is real)
- [x] Pattern recall precision >70% (up from Phase 2's >50% and Phase 3's >60%)
- [x] The challenger has caught at least 3 genuine issues that would have become code without it
- [x] You can point to a specific moment where cross-project knowledge transfer saved significant time
- [x] Tag: `v1.0.0` — the brain is self-maintaining

---

## Timeline Summary

```
Weeks 1-2       Phase 0: Skeleton
                ├─ Project structure, deploy pipeline, claude-flow init
                ├─ Export escape hatch (before putting any knowledge in)
                └─ Tag: v0.1.0

Weeks 2-4       Phase 1: Foundation (scaffolding — don't over-polish)
                ├─ 6 skills (5 mastermind + /brana:challenge), plugins, agents
                ├─ skill-catalog.yaml, PM awareness rule
                ├─ Use in 3+ real sessions to validate before Phase 2
                └─ Tag: v0.2.0

Weeks 4-6       Phase 2: Learning Loop (★ quality focus here)
                ├─ 3 hooks (SessionStart, SessionEnd, PostToolUse)
                ├─ Early quarantine (immune system Layer 1)
                ├─ Two-layer memory (Layer 0 native + Layer 1 ReasoningBank)
                ├─ Accumulation phase: target 50+ patterns
                └─ Tag: v0.3.0

Weeks 6-10      Phase 3: Intelligence (SONA evaluation gate)
                ├─ SONA: evaluate → Plan A or Plan B
                ├─ Pattern promotion path, dual-track confidence
                ├─ /skill-discover + /skill-install + skill quarantine
                ├─ Smart challenge suggestions
                └─ Tag: v0.4.0

Weeks 10-14     Phase 4: Knowledge Health
                ├─ Remaining immune system layers (transferability, decay, contradiction)
                ├─ /knowledge-audit, /system-health, failure attribution
                └─ Tag: v0.5.0

Month 4+        Phase 5: Self-Improvement (ongoing)
                ├─ A/B testing, health dashboard, recursive learning
                ├─ Smart skill suggestion on /project-onboard
                ├─ Auto-challenge hook on plan mode (Max5-calibrated)
                └─ Tag: v1.0.0
```

**Total to v0.5.0 (functional system):** ~14 weeks (was 12 — added buffer for alpha instability and accumulation time)
**Total to v1.0.0 (self-improving):** ~4 months + ongoing (was 3 — realistic given evaluation gates)

**Why the stretch:** The original timeline assumed everything works first try and patterns accumulate on schedule. Adding 2 weeks of buffer accounts for: claude-flow alpha issues requiring workarounds, SONA evaluation potentially going to Plan B, and the reality that pattern accumulation depends on how many sessions you run, not calendar time.

---

## Phase Dependencies

```
Phase 0 (skeleton + escape hatch)
    │
    ├──→ Phase 1 (skills + plugins — scaffolding, don't over-polish)
    │        │
    │        ├──→ Phase 2 (★ learning loop — quality focus)
    │        │        │
    │        │        ├─── [early quarantine starts HERE, not Phase 3]
    │        │        │
    │        │        ├─── [knowledge accumulation happens here]
    │        │        │     Need ~50 patterns before SONA evaluation gate
    │        │        │
    │        │        ├──→ Phase 3 (SONA evaluation → Plan A or Plan B)
    │        │        │        │
    │        │        │        └──→ Phase 4 (remaining immune system layers)
    │        │        │                 │
    │        │        │                 └──→ Phase 5 (self-improvement, ongoing)
    │        │        │
    │        │        └─── Value check: >50% recall precision before proceeding
    │        │
    │        └─── Skills can be used manually before hooks automate them
    │
    └─── Deploy pipeline + export used by ALL subsequent phases
```

Phases are sequential but overlap is fine — you can start building Phase 2 hooks while polishing Phase 1 skills. The main hard dependency is Phase 2→3: SONA needs accumulated patterns (~50). The evaluation gate at Phase 3 start is a genuine decision point that may redirect effort.

---

## What Each Phase Depends On From claude-flow

| Phase | claude-flow Features | Risk if Feature Breaks |
|---|---|---|
| **0** | CLI install, `init` | Can't start. Wait for fix or use older version. |
| **1** | `memory search`, `memory store` | Skills work manually, just slower. |
| **2** | Hook lifecycle integration, pre/post task hooks | Learning loop stops. Fall back to manual `/brana:retrospective`. |
| **3** | SONA, `neural train`, WASM transforms | **Evaluation gate catches this.** If SONA fails, Plan B: tag-based recall, no vector similarity, still functional. |
| **4** | ReasoningBank queries, stats, bulk operations | Immune system degrades. Manual audits still possible. |
| **5** | Full stack + self-referential patterns | Self-improvement pauses. System still functional. |

**The key insight:** each phase's dependency on claude-flow is additive. If a feature breaks, you lose the enhancement from that phase but everything below it still works. Phase 0 with no claude-flow = plain Claude Code with good organization. That's the floor, not a disaster.

---

## Getting Started: Day 1 Checklist

```
□ Create ~/projects/brana/ directory
□ git init
□ Create .claude/CLAUDE.md (self-development context)
□ Create system/CLAUDE.md (mastermind identity v0.1)
□ Create system/rules/universal-quality.md
□ Create system/rules/git-discipline.md
□ Create system/settings.json (empty hooks)
□ Create tests/validate-syntax.sh        ← build this FIRST (safety before code)
□ Create tests/validate-context-budget.sh
□ Create deploy.sh
□ Create rollback.sh
□ Create backup-knowledge.sh
□ Create export-knowledge.sh             ← the escape hatch (before any knowledge goes in)
□ npm install -g claude-flow@2.5.0-alpha.130
□ npx claude-flow init
□ Run export-knowledge.sh → verify it produces output (even if empty)
□ Run deploy.sh → verify symlinks
□ Start a claude session → verify identity loads
□ Create user practices doc (field notebook for usage observations — graduation to hooks in Phase 2+)
□ Tag v0.1.0
□ You're building the brain. The first safety rail is already in place.
```

---

## References

- [09-claude-code-native-features.md](dimensions/09-claude-code-native-features.md) — Hook JSON format, all 14 events, stdin/stdout contracts, async constraints
- [14-mastermind-architecture.md](reflections/14-mastermind-architecture.md) — The architecture this roadmap implements
- [15-self-development-workflow.md](./15-self-development-workflow.md) — Deploy pipeline, testing, versioning
- [16-knowledge-health.md](dimensions/16-knowledge-health.md) — Immune system implemented in Phase 4
- [24-roadmap-corrections.md](./24-roadmap-corrections.md) — Errata: deploy.sh merge bug, Stop→SessionEnd, hook format, PostToolUseFailure
- [05-claude-flow-v3-analysis.md](dimensions/05-claude-flow-v3-analysis.md) — claude-flow architecture
- [06-claude-flow-internals.md](dimensions/06-claude-flow-internals.md) — SONA, RuVector, WASM details
- [11-ecosystem-skills-plugins.md](dimensions/11-ecosystem-skills-plugins.md) — Plugin selections for Phase 1
- [12-skill-selector.md](dimensions/12-skill-selector.md) — Trust model, skill catalog, discovery, quarantine
- [13-challenger-agent.md](dimensions/13-challenger-agent.md) — Cross-model adversarial review, subscription-native
- [22-testing.md](dimensions/22-testing.md) — Testing strategy: 7-layer pyramid, record/playback, CI/CD, static validation
- [23-evaluation.md](dimensions/23-evaluation.md) — Evaluation strategy: pass@k, RAG metrics, LLM-as-judge, eval-driven development
- [00-user-practices.md](./00-user-practices.md) — User feedback loop: field notes from real usage, graduation pathway from manual practice to automated hook/check
- [25-self-documentation.md](./25-self-documentation.md) — Frontmatter convention, staleness detection, CI/CD for docs, growth stages for skills/configs
