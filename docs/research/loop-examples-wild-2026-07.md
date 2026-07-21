# Production Agent-Loop Examples — Wild Catalog

## Examples Discovered

### 1. Boris Cherny Verification Loops (Anthropic/Claude Code)
- **Source**: karozieminski.substack.com - "Boris Cherny Claude Code Workflow"
- **What it does**: Gives Claude a way to verify its work by opening a browser, testing UI, iterating until it works
- **Trigger**: Manual (interactive, but can be wrapped in /loop)
- **Queue**: Not explicitly queued; interactive feedback
- **Stop condition**: Task verified (vibes-based, but with instrumental verification)
- **Verifier**: Browser/UI testing (external, human-visible)
- **Autonomy level**: L2+ (human-in-the-loop interactive)
- **Lesson**: Verification must be instrumental and observable — watching Claude test a UI gives confidence 2-3x better than code review alone

### 2. Ralph Wiggum Loop (Vercel + Community)
- **Source**: github.com/vercel-labs/ralph-loop-agent; tessl.io blog
- **What it does**: Outer loop that wraps LLM tool-use + verifies result + decides to retry
- **Trigger**: Manual invocation or scheduled
- **Queue**: Single task → verify → retry logic
- **Stop condition**: 
  - Iteration cap (N attempts)
  - Token budget (max $ spent)
  - Cost ceiling (explicit dollar cap)
  - Multiple stops (ANY trips halts)
- **Verifier**: `verifyCompletion()` function (external, returns completion status + reasoning for retry)
- **Autonomy level**: L3 (fully unattended, resource-bounded)
- **Lesson**: Nested loops (inner LLM iteration + outer verify/retry) with hard resource caps prevent runaway. Feedback from verifier guides next attempt.

### 3. Claude Code /loop & /schedule (Anthropic)
- **Source**: claude.com/blog/getting-started-with-loops; Medium articles
- **What it does**: Time-based automation of any Claude prompt/goal
- **Types**:
  - Turn-based: User triggers, runs until Claude judges done
  - Goal-based (/goal): Manual trigger, run until goal achieved or max turns
  - Time-based (/loop + /schedule): Recurring intervals (e.g., /loop 5m, /schedule cron)
- **Trigger**: Time (cron), manual (/goal), event
- **Queue**: Session-scoped; each run is fresh session (state doesn't persist)
- **Stop condition**:
  - Max turns
  - Goal achievement (verified externally)
  - Time limit
  - User cancellation
- **Verifier**: Encoded in /goal definition (e.g., "Lighthouse > 90")
- **Autonomy level**: L1 (report-only) → L3 (scheduled unattended)
- **Lesson**: Session isolation + fresh context per run prevents context bloat. Explicit success criteria are required for goal loops.

### 4. PR Babysitter (Claude Code Community)
- **Source**: solberg.is; GitHub gists; X/Boris Cherny
- **What it does**: Automatically monitors PR, fixes CI failures, addresses review comments, rebases
- **Trigger**: Manual `/babysit-pr` command; or `/loop 5m /babysit` (every 5 minutes)
- **Queue**: Single PR, polled in loop
- **Stop condition**: 
  - CI is green AND no unaddressed issues remain
  - Max 3 iterations (safety limit)
- **Verifier**: 
  - CI status (external: gh pr checks --watch)
  - Code review feedback (via Greptile MCP)
- **Autonomy level**: L2-L3 (structured decision-making; triage feedback into Fix/Dismiss/Escalate before acting)
- **Lesson**: **Triage step is critical** — agent doesn't blindly fix everything; it makes judgment calls (Fix/Dismiss/Escalate) and documents reasoning. Prevents over-automation.

### 5. Sweep AI Issue→PR Loop (GitHub App)
- **Source**: sweepai/sweep; multiple reviews; ycombinator thread
- **What it does**: End-to-end: GitHub issue → plan (posted as comment) → codebase search → multi-file edits → PR creation
- **Trigger**: Issue opened + label, or comment with trigger keyword
- **Queue**: GitHub issue queue; processes one at a time
- **Stop condition**: PR created + human review gate
- **Verifier**: 
  - Internal: Sweep validates branch compiles/tests before PR submission
  - External: Human review (required before merge)
- **Autonomy level**: L2 (PR creation autonomous; merge requires approval)
- **Lesson**: Plan-as-comment bridges transparency and autonomy. Humans see the plan before code is written; can course-correct.

### 6. Production Error Sweep Loop (Nightly, MindStudio Pattern)
- **Source**: mindstudio.ai/blog/production-error-sweep-loop-nightly-ai-bug-detection
- **What it does**: Nightly scan of production logs → identify errors → generate fixes → create PRs or issues
- **Trigger**: Scheduled (e.g., 11 PM local time)
- **Queue**: Error batch queue from log analysis
- **Stop condition**: All errors processed
- **Verifier**: 
  - Confidence scoring (high/medium/low)
  - needs_human_review boolean flag
- **Decision Logic**:
  - confidence=high + needs_human_review=false → auto-create PR
  - medium or flagged → create GitHub issue (for human triage)
- **Autonomy level**: L2 (high-confidence fixes auto-PR; escalates ambiguous)
- **Lesson**: Confidence + escalation gate prevents blind automation. Graduated autonomy by decision quality.

### 7. FlakyGuard Test Repair Loop (Uber, Industry Scale)
- **Source**: arxiv.org/html/2511.14002v1
- **What it does**: Autonomous flaky test diagnosis and repair
- **Trigger**: Flaky test report enters system (from CI/test framework)
- **Queue**: Ticketing system queue; processes daily batch
- **Stop condition**: 
  - Time limit: 2 hours per test case
  - All nested loops complete
  - Successful fix found
- **Nested Loop Architecture** (M=3, P=2, N=3; 18 total repair attempts per test):
  - Outer loop (M=3): Collect new execution contexts
  - Middle loop (P=2): Generate high-level reasoning
  - Inner loop (N=3): Produce, apply, validate fixes
- **Verifier**: 
  - Build validation (compile check)
  - Test validation: **1000 test reruns** (all must pass; ANY error → revert)
- **Autonomy level**: L3 (fully autonomous; auto-submit PR to developer)
- **Lesson**: Extreme validation rigor (1000 runs) for test fixtures. Nested loops with feedback at each level. Hard time cap prevents resource exhaustion.

### 8. Nx Self-Healing CI (Build Tool Integration)
- **Source**: nx.dev/blog/nx-self-healing-ci
- **What it does**: Detects CI task failures → spins AI agent → proposes fix → validates → commits to PR
- **Trigger**: CI task failure
- **Queue**: Nx Cloud failure queue
- **Stop condition**: Fix validated or human rejection
- **Fix Validation**: 
  - Re-run originally failed tasks with proposed changes
  - **Parallel validation** (not sequential)
- **Gate**: Human review + approval required before commit
- **Autonomy level**: L2 (fixes proposed autonomously; human approval required)
- **Lesson**: Parallel validation (re-run tests concurrently) is faster than sequential. Human gate is non-negotiable for code changes.

### 9. GitHub Issue Triage Loop (Agentic Workflows, 2026)
- **Source**: github.com/github/gh-aw; GitHub Docs
- **What it does**: New issue opened → analyze content → apply labels → post acknowledgment comment → detect duplicates
- **Trigger**: Issue opened or reopened
- **Queue**: GitHub issue event queue
- **Stop condition**: All new issues labeled + duplicate detection complete
- **Verifier**: 
  - Content analysis (manual rule-based or AI classification)
  - Duplicate detection (similarity + comment chain review)
- **Autonomy level**: L1-L2 (labeling + comments autonomous; maintainer reviews for edge cases)
- **Lesson**: "Hello world" of agent automation — low-risk (labels/comments vs. code changes), immediate impact, high volume. Good pilot pattern.

### 10. Dependabot Dependency Update Loop (GitHub)
- **Source**: GitHub Docs; Dependabot 2026 features
- **What it does**: Scheduled dependency scanning → version resolution → PR creation for upgrades
- **Trigger**: Scheduled (configurable interval; default weekly)
- **Queue**: Dependency manifest queue; batched/grouped
- **Stop condition**: PR created + CI passes (optional auto-merge for safe updates)
- **Verifier**:
  - CI pipeline (tests, linting)
  - Compatibility scoring (public CI data from other repos using same update)
- **Auto-merge criteria**: patch/minor updates + CI passing + low risk
- **Autonomy level**: L3 (auto-merge for patch; L2 for minor/major)
- **Lesson**: Compatibility scoring (leveraging public data) reduces false negatives. Graduated trust by semver.

### 11. Self-Healing CI Pipelines (Dagger Pattern)
- **Source**: dagger.io/blog/automate-your-ci-fixes-self-healing-pipelines
- **What it does**: CI failure → agent analyzes → applies fix → re-runs tests → submits as code suggestion
- **Trigger**: CI pipeline failure (linting or test stage)
- **Queue**: Failure event queue
- **Stop condition**: Fix validated (tests pass) or max iterations
- **Fix Loop**:
  1. Analyze failure output
  2. Use ReadFile/ListFiles to understand code
  3. Apply hypothetical fix (WriteFile)
  4. Validate (RunTests or RunLint)
  5. Repeat if failure persists
- **Verifier**: 
  - Compilation check
  - Test re-run (success = fix validated)
- **Autonomy level**: L2 (suggestions only; developer reviews before merge)
- **Lesson**: Iterative fix-validate loop tightly coupled. Developer review is final gate (prevents over-automation).

### 12. Memory Consolidation Loop (Nightly Autonomous)
- **Source**: Autobot pattern; Cloudflare Agent Memory
- **What it does**: Long-running agents periodically consolidate memory to prevent context bloat
- **Trigger**: Session age threshold or scheduled (nightly)
- **Queue**: Message buffer (100-capacity); queues burst traffic
- **Stop condition**: Consolidation complete; old messages summarized to long-term store
- **Mechanism**: 
  - Write-manage-read: new info enters memory → pruned/compressed → compressed memory retrieved on next run
  - FSRS spaced repetition + Hebbian learning patterns
- **Verifier**: Salience scoring (what's important to retain?)
- **Autonomy level**: L3 (fully autonomous)
- **Lesson**: Queue + state isolation prevents concurrent-write race. Consolidation happens **between** sessions, not during.

---

## Key Patterns Across Examples

| Pattern | Examples | Key Detail |
|---------|----------|-----------|
| **Event-driven trigger** | Sweep, GitHub triage, FlakyGuard, self-healing CI, Dependabot | Reacts to external signal (issue opened, test failed, dependency update) |
| **Time-based trigger** | Claude /loop, /schedule, Production sweep loop, Memory consolidation | Cron or interval (every 5m, nightly, weekly) |
| **Manual trigger** | Ralph loop, PR babysitter, Boris Cherny, /goal | Command or interactive invocation |
| **External verifier** | Ralph (verifyCompletion), FlakyGuard (1000 test runs), Nx (re-run tests), Dependabot (CI), Triage (classification rules) | Decoupled from execution; self-grading fails at scale |
| **Encoded stop condition** | Ralph (iteration cap, token budget, cost), FlakyGuard (2hr, nested loops), PR babysitter (max 3), Claude /goal (max turns) | Multiple stops (AND/OR logic); prevent runaway |
| **Triage/categorization step** | PR babysitter (Fix/Dismiss/Escalate), Production sweep (confidence + escalate), Nx (human approval), Sweep (plan review) | Decision logic before action; documents reasoning |
| **Autonomy levels** | All examples | L1 report → L2 human approval → L3 unattended (rare; usually stops at L2) |
| **Queue mechanism** | Autobot (100-capacity buffer), GitHub events, FlakyGuard queue, Sweep issue queue | Handles concurrent events; prevents blocking |
| **State tracking** | Claude sessions (session ID + turn count), Memory consolidation (long-term store), Sweep (branch state) | Persists across iterations for context |

---

## Stop-Condition Mechanics

### Encoded (Hard Resource Caps)
- Ralph loop: iteration N, token budget T, cost ceiling C
- FlakyGuard: 2-hour wall clock, nested loop max (3×2×3)
- PR babysitter: max 3 iterations
- Claude /goal: max turns

### Verifier-Based (External Success Criteria)
- Boris Cherny: browser UI verification
- Nx: test re-run success
- FlakyGuard: 1000 test runs all pass
- GitHub triage: classification complete, duplicates found
- Dependabot: CI passing, compatibility score OK

### Gate-Based (Human Approval)
- Sweep: plan comment → human reviews → merge approval
- Production sweep: high confidence auto-PR, medium/flagged → issue for review
- Nx: human review + approval before commit
- Self-healing CI: code suggestions, developer reviews

### Completion Signal
- PR babysitter: CI green + no unaddressed feedback
- Sweep: PR created
- Triage: all issues labeled

---

## Lessons Repeated Across Sources

### Lesson 1: Verifiers Must Be Independent & Encoded
**The problem**: Self-grading agents give themselves A+ every time. Runaway loops happen when stop conditions are vague.

**Production pattern**: Real systems separate verification from execution:
- **External test suite** (FlakyGuard: 1000 runs, Nx: re-run original tests)
- **Compilation/linting** (self-healing CI: build validation)
- **CI pipeline** (Dependabot, Sweep)
- **Separate evaluator** (Ralph: verifyCompletion function)
- **Human gate** (Sweep, Nx, production sweep)

**Encoded stops** prevent infinite spinning:
- Iteration caps (Ralph N, P, M values)
- Token/cost budgets (Ralph)
- Wall-clock time limits (FlakyGuard 2 hours)
- Turn limits (Claude /goal)

### Lesson 2: Queues + State + Autonomy Rungs
**The problem**: Concurrent events can corrupt shared state or block progress.

**Production pattern**:
1. **Message queue** (buffer burst traffic, FIFO processing)
   - Autobot: 100-capacity queue handles user + cron concurrency
   - GitHub events: natural FIFO for issue+PR events
   - Ticketing systems (FlakyGuard) batch errors daily

2. **Persistent state** (survives iterations + sessions)
   - Session ID + turn count (Claude)
   - Branch state (Sweep)
   - Long-term memory store (consolidation)
   - Confidence scores + context (production sweep)

3. **Explicit autonomy rungs** (not binary)
   - **L1**: Report-only (GitHub triage post comment, FlakyGuard submit suggestion)
   - **L2**: Human approves before action (Nx review+approve, Sweep merge gate, production sweep escalation)
   - **L3**: Unattended (rare; Ralph loop with resource caps, Claude /schedule with hard goal)

**The triage pattern** (PR babysitter most explicit):
> Don't blindly execute feedback. Categorize: Fix (valid) / Dismiss (invalid) / Escalate (ambiguous). Document each decision.

### Lesson 3: Triggers Are Layered; Stops Are Multiple
**The problem**: Single trigger = inflexible; single stop = runaway risk.

**Production pattern**: Combine trigger types:
- **Event triggers** (issue opened, test failed, CI stage finishes, dependency update)
- **Time triggers** (cron /loop 5m, /schedule, nightly)
- **Manual triggers** (command /babysit-pr, /goal, user initiates)

**Multiple stop conditions** (NOT single success criterion):
- Ralph loop: iteration OR token OR cost (any fires)
- FlakyGuard: time OR loops complete OR fix found (any fires)
- PR babysitter: CI green AND no issues remaining (all must be true)
- Production sweep: process all in batch, then escalate ambiguous

**Graduated autonomy by quality**:
- High confidence + low ambiguity → auto-create PR (production sweep)
- Medium confidence or flagged → escalate to issue (human reviews)
- Compile error → revert and retry (FlakyGuard)

---

## What's Missing in "Wild" Production Examples

- **Very few true L3 (fully autonomous) loops** in production. Most stop at L2 (human approval before merge/execution).
- **Limited queue-overflow handling** documented (e.g., what if FlakyGuard gets 1000 tests in one day?).
- **Cross-loop coordination** (e.g., PR babysitter + Sweep running on same repo — do they conflict?).
- **State recovery after crashes** (e.g., if loop crashes mid-fix, does it resume?).
- **Cost tracking at scale** (Ralph loop documents token budget; what about at 100 repos × daily?).

---

## Implementation Patterns to Steal

1. **Encode stop conditions, don't negotiate them in the agent**
2. **Triage before action** (Fix/Dismiss/Escalate)
3. **External verification** (test suite, CI, human gate) — never self-grade
4. **Queue + state + isolation** (per-session or per-message)
5. **Graduated autonomy** (L1 report → L2 approval → L3 unattended)
6. **Layered triggers** (event + time + manual)
7. **Multiple stops** (resource caps + external gate + completion signal)
8. **Plan-as-transparency** (post plan before executing — Sweep style)
9. **Confidence + escalation** (auto-act on high-confidence, escalate ambiguous)
10. **Nightly consolidation** (memory/state cleanup between sessions, not during)
