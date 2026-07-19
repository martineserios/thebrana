# Gap Analysis: Agentic Engineering Feb–Jul 2026 vs brana

> **Date:** 2026-07-19 · **Sources:** Anthropic engineering blog 2026, Claude Code changelog Feb–Jul 2026, community practice sweep. Companion to [gentle-ai extraction](gentle-ai-productization-extraction.md).
> **Method:** 3-scout sweep (official blog / changelog / community) cross-checked against grep of `system/` for actual native-feature usage.

## Headline

The gap is not a missing practice — it's that **brana's homegrown infrastructure predates native equivalents that shipped Feb–Jul 2026**. Brana pays maintenance cost (dead crons, broken agent-memory reads, 16K-line bash hooks) for capabilities Claude Code now provides natively. Brana already wires Workflow, `/loop`, ScheduleWakeup, forks, and model routing into skills; the misses cluster in four areas below.

## Confirmed gaps (zero usage in system/, direct evidence of pain)

### 1. Native persistent subagent memory — replaces broken hand-rolled agent memory
`memory: user|project|local` in agent frontmatter gives subagents cross-session learning, natively. Brana hand-rolls this (`~/.claude/agent-memory/brana-challenger/CALIBRATION.md`) and it is **failing right now** — session-start recurring errors show 31 failed reads of that file. Migrate challenger/build-evaluator/debrief-analyst to native memory frontmatter.

### 2. Cloud Routines — replaces the fragile local cron layer
Routines run Claude Code sessions on Anthropic infra on schedule, API trigger, or GitHub events; MCP connectors; no local machine needed. Brana's `brana ops` local scheduler is the current equivalent and its close-extraction cron is **dead right now** (session-start warning: queue unprocessed >3 days). Candidates to move: close-extraction, daily summary, overnight learning extraction, reminder sweeps. Local scheduler stays for machine-local jobs only.

### 3. Agent Teams / SendMessage — unused coordination primitive
Teammates with shared task list + direct messaging (experimental flag). Community consensus on fit: competing-hypotheses debugging and cross-layer changes where agents must **challenge each other** — exactly brana's challenger pattern, currently one-shot. Also: teams can spawn from existing `.claude/agents/` definitions. Not urgent (higher token cost, experimental), but the challenger-as-persistent-teammate experiment is worth one session.

### 4. Loop-engineering verifier gate — small model decides "done"
2026 community pattern ("loop engineering"): a separate small-model verifier (Haiku) checks completion after each iteration — the worker never grades itself; prevents infinite loops and premature completion claims. Brana's `goal-completion.sh` (16K bash) approximates this in-process. Restructure: build-loop's completion check becomes a Haiku verifier call against `/goal` + AC lines.

## Partially covered — align, don't rebuild

- **Long-running harness patterns** (Anthropic, Mar 24): two-phase init/coder split, feature-JSON with explicit "failing" states, `claude-progress.txt`, session onboarding ritual (directory verify → progress review → smoke test), one-feature-at-a-time. Brana's close/handoff + sitrep covers session continuity; the **structured feature-state file** and onboarding ritual should fold into the ADR-059/060 autonomous runner.
- **`isolation: worktree` on subagents** — native, auto-cleaned. Doesn't replace worktree-discipline for main-session work, but lifts the old "in-session Task agents can't write to worktrees" constraint (rule + ADR-060 note now stale — update both).
- **Subagent background-by-default, hotloading, `Agent(model:...)` permission rules** — free wins; check settings assumptions.
- **Agent SDK separate credit pool** (Jun 15: $100/mo on Max 5x) — potentially materially relevant given extra-usage is org-disabled: SDK-driven runner work draws from a separate pool, not the session subscription.

## Where brana violates new official guidance

1. **Minimal viable toolset**: "if engineers can't pick the right tool, neither can the agent." ruflo MCP exposes ~300 tools (deferred loading mitigates context cost, not selection confusion) — and its agentic layer is already documented theater. Prune the server surface to memory/recall + the handful actually routed.
2. **Decompose by shared context, not problem type**: Anthropic explicitly calls plan→build→test-type splits an anti-pattern ("telephone game" degradation). Brana's fan-outs are mostly dimension-based (good) but some skill pipelines split by phase — audit challenge/research fan-outs.
3. **15× token honesty**: multi-agent costs ~15× single-agent; only rational for high-value outputs. Add an economic gate to adversarial-hive-mind/sweep triggers (skip fan-out for S-effort).
4. **Zero-trust shared resources**: "cooperate" prompts don't prevent write conflicts — queues/merge layers do. Brana learned this the hard way (t-2216/t-2206 races); native worktree isolation is the sanctioned fix.
5. **Redundant custom agents vs Plan Mode** (community anti-pattern): audit the 14 brana agents for overlap with native Plan/Explore agents (scout ≈ Explore?).

## Explicitly fine as-is

Workflows usage (challenge, adversarial-hive-mind), `/loop` + ScheduleWakeup in build-loop, fork usage in research/challenge/claudemd, `_shared/model-routing.md`, context-budget rule (matches official JIT-retrieval + compaction guidance), reconcile/validate drift gates (ahead of community norm).

## Recommended order of attack

1. **Subagent memory migration** (S, fixes an active failure x31)
2. **Routines migration for dead/critical crons** (M, fixes an active outage)
3. **Haiku verifier gate in build-loop** (S–M, replaces 16K bash with the 2026 canonical pattern)
4. **Runner alignment with long-running harness patterns** (M, feature-state JSON + onboarding ritual)
5. **ruflo tool-surface prune + agent redundancy audit** (M)
6. **Teams experiment: persistent challenger teammate** (S spike, experimental flag)
