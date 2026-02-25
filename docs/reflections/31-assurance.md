# 31 - Assurance: Does It Work?

How to verify that the mastermind system delivers on its claims. The brain says it learns, recalls, cross-pollinates, and improves over time — this reflection defines how to test those claims. R3 in the reflection DAG: validates what [R2 (Architecture)](./14-mastermind-architecture.md) specifies.

---

## The Core Question

The mastermind's value claim is "knowledge compounds over time." Without measurement, this is a feeling, not a fact. Assurance turns it into a testable proposition.

Three levels of assurance, from cheapest to most revealing:

| Level | Question | Method | Cost |
|-------|----------|--------|------|
| **Structural** | Is the system correctly assembled? | Static validation, schema checks, link verification | $0, seconds |
| **Behavioral** | Does the system do what it claims? | Deterministic tests, round-trip verification, regression suites | $0, seconds |
| **Outcome** | Does the system produce good results? | RAG metrics, LLM-as-judge, user feedback, longitudinal tracking | $1-50/run |

Most of what matters is in the first two levels. Outcome evaluation is important but expensive — run it periodically, not continuously.

---

## Structural Assurance

The cheapest checks. Run on every commit, block deployment if they fail.

### Configuration Validity

From [22-testing.md](../../../brana-knowledge/dimensions/22-testing.md) Layer 0 (Static Validation):

- **YAML frontmatter** — every skill, rule, and agent definition has valid frontmatter with required fields (`name`, `description`, `allowed-tools`)
- **Context budget** — total always-loaded context (CLAUDE.md + rules + skill descriptions + agent descriptions) stays under the ~24KB ceiling. Every KB competes with working context ([21-anthropic-engineering-deep-dive.md](../../../brana-knowledge/dimensions/21-anthropic-engineering-deep-dive.md))
- **Hook configuration** — `settings.json` references scripts that exist, event names are valid, async constraints are respected
- **Link integrity** — all markdown cross-references (`[doc NN](./NN-filename.md)`) resolve to real files
- **Pre-commit validation** — `.git/hooks/pre-commit` in thebrana validates spec consistency before commit: YAML frontmatter, JSON syntax, secrets, context budget. Shift-left complement to deploy-time validation. See [35-context-engineering-principles.md](../../brana-knowledge/dimensions/35-context-engineering-principles.md) for budget failure modes

### Knowledge Store Integrity

- **ReasoningBank accessible** — `memory search --query "test"` returns without error (catches sql.js missing, schema drift, DB corruption)
- **Round-trip verification** — store a test entry, retrieve it, verify content matches. This is the minimum viable health check for the intelligence layer
- **Namespace isolation** — patterns stored in namespace `patterns` don't leak into namespace `decisions`

### Enforcement Gate Verification

The PreToolUse hook claims to enforce spec-before-code discipline. Verify structurally:

- Hook exists in `settings.json` under `PreToolUse`
- Script is executable and passes `bash -n` syntax check
- On a `feat/*` branch in an opted-in project (has `docs/decisions/`), the hook blocks `Write|Edit` when no spec/test activity exists
- On non-feat branches or non-opted-in projects, the hook passes through

### Adversarial Input Validation

Hooks process JSON input from tool calls and sessions. They must resist adversarial payloads — not just valid input:

- **Shell metacharacters** — payloads with `;`, `|`, `$()`, backticks that could escape JSON parsing and inject bash code
- **Deeply nested structures** — JSON with extreme nesting or oversized strings designed to cause parser hangs or buffer overflows
- **Event spoofing** — input claiming to be from SessionStart but arriving via PostToolUseFailure, or vice versa
- **Escape sequences** — strings designed to break out of quoted contexts in shell scripts

Test: replay recorded hook input fixtures with adversarial variants. Hooks should exit non-zero or sanitize safely — never execute injected commands. Tool: Promptfoo red team plugins ([22-testing.md](../../../brana-knowledge/dimensions/22-testing.md)). Doc 22 identifies "Instruction poisoning incidents: 0 promoted" as a critical safety metric.

---

## Behavioral Assurance

Does the learning loop actually learn? Does recall actually recall? These are deterministic tests — the system either does the thing or doesn't.

### Learning Loop Round-Trip

The strongest behavioral test. From [22-testing.md](../../../brana-knowledge/dimensions/22-testing.md) record/playback pattern:

1. **Store** a pattern via SessionEnd hook (or manual `memory store`)
2. **Recall** it via SessionStart hook (or manual `memory search`)
3. **Verify** the recalled pattern matches what was stored — correct tags, correct namespace, correct content

If this round-trip fails, nothing else matters. The brain isn't learning.

### Quarantine Behavior

From [16-knowledge-health.md](../../../brana-knowledge/dimensions/16-knowledge-health.md) immune system design:

- New patterns enter at `confidence: 0.5`, `status: quarantined`, `transferable: false`
- Patterns are NOT cross-pollinated during quarantine
- After 3 successful recalls from different sessions, promotion to `status: trusted`
- Failed patterns are demoted to `status: suspect` immediately

Test each transition. The quarantine is the immune system's first layer — if it doesn't work, bad patterns spread freely.

### Skill Instruction Quarantine

From [16-knowledge-health.md](../../../brana-knowledge/dimensions/16-knowledge-health.md) Vector 8 — external skills can poison the instruction set. When a skill is installed from an external source (skills.sh, community repos), its SKILL.md content becomes part of Claude's instructions. Assurance must verify:

- **Source integrity** — new skills from external sources enter a review quarantine before deployment to `~/.claude/skills/`
- **Instruction override prevention** — skill SKILL.md content is validated to not override CLAUDE.md rules or safety directives
- **Conflict detection** — skill instructions conflicting with established rules are flagged for human review
- **Trust tier compliance** — quarantined skills are NOT loaded into context until promoted to trusted tier

Test: install an external skill, verify it enters quarantine. Run a task — the quarantined skill should NOT activate until explicitly promoted. Reference: [12-skill-selector.md](../../../brana-knowledge/dimensions/12-skill-selector.md) for the three-tier trust model (local core / curated catalog / discovery).

### Skill Activation

From [23-evaluation.md](../../../brana-knowledge/dimensions/23-evaluation.md) and Vercel's eval findings:

- Skills activate at only ~20% rate with simple instructions (Vercel data)
- Scott Spence demonstrated 84% with forced eval hooks
- CLAUDE.md achieves 100% pass rate vs 53% for skill invocation

**What to test:** When a user invokes `/memory recall topic`, does the skill execute? When SessionStart fires, does it actually query ReasoningBank? These are activation checks, not quality checks.

### Hook Lifecycle

Every hook in the system must be tested with realistic inputs:

- **SessionStart** — receives session context JSON on stdin, queries ReasoningBank, returns patterns as `additionalContext`
- **SessionEnd** — receives session summary, extracts patterns, stores in ReasoningBank
- **PostToolUse** — receives tool result, notices learning-worthy moments
- **PreToolUse** — receives tool request, enforces discipline gate

From lesson #6 (doc 24): `bash -n` catches syntax but not logic. Test hooks by piping real JSON and verifying side effects.

---

## Outcome Assurance

Does the system produce *good* results? This requires judgment — human or model-based.

### RAG Metrics for ReasoningBank Recall

The ReasoningBank is fundamentally a retrieval system — same evaluation framework as RAG applies:

| Metric | What It Measures | Target |
|--------|-----------------|--------|
| **precision@k** | Of k patterns recalled, how many were actually relevant? | >60% at k=5 |
| **recall@k** | Of all relevant patterns, how many were recalled? | >40% at k=10 |
| **faithfulness** | Does the session summary accurately reflect stored patterns? | >80% |
| **staleness rate** | How many recalled patterns are outdated? | <15% |

Measure with real sessions: after SessionStart injects patterns, have a reviewer (LLM-as-judge or human) grade whether each recalled pattern was useful for the actual work done.

### Testing the Learning Loop End-to-End

The behavioral test checks that store→recall works mechanically. The outcome test checks that it works *meaningfully*:

1. **Record** a session where a problem is solved
2. **SessionEnd fires** — capture what patterns are stored
3. **Start a new session** with a similar problem
4. **SessionStart fires** — check if relevant patterns are recalled
5. **Grade the outcome**: Did recalled patterns improve time-to-solution or prevent repeated mistakes?

This converts non-deterministic learning behavior into a deterministic regression test (Block Engineering's record/playback pattern from [22-testing.md](../../../brana-knowledge/dimensions/22-testing.md)).

### Grade Outcomes Not Paths

From [23-evaluation.md](../../../brana-knowledge/dimensions/23-evaluation.md) — Anthropic's core eval principle:

Don't measure HOW the brain works internally. Measure WHAT it produces:

- **New project onboarding time** — decreases as the portfolio grows?
- **Repeated mistakes** — does the brain prevent the same error in project B that happened in project A?
- **Cross-pollination hits** — when patterns from project A are recalled in project B, do they actually help?
- **Confidence calibration** — are high-confidence patterns actually more reliable than low-confidence ones?

Start with 20-50 eval tasks drawn from real sessions (Anthropic methodology). Use `pass@k` during development (capability), `pass^k` before trusting in production (reliability).

### The Anti-Pattern: Bad Evals Mask Real Capability

CORE-Bench showed performance jumping from 42% to 95% just by fixing broken eval harnesses. Before concluding the brain doesn't work, verify the eval infrastructure:
- Is the query reaching ReasoningBank correctly?
- Is the recall format what the SessionStart hook expects?
- Are you grading the right thing (outcome, not process)?

Infrastructure noise can account for up to 6 percentage points of score difference (Anthropic), so single-digit improvements may be noise.

---

## Knowledge Health as Ongoing Assurance

From [16-knowledge-health.md](../../../brana-knowledge/dimensions/16-knowledge-health.md) — the immune system IS the ongoing assurance layer. The quarantine, decay, and contradiction detection mechanisms don't just prevent bad patterns — they continuously validate that the knowledge store is healthy.

### Key Health Indicators

| Indicator | Healthy | Warning | Critical |
|-----------|---------|---------|----------|
| Quarantine promotion rate | 30-60% of quarantined patterns eventually promote | <10% (nothing surviving) or >80% (quarantine too lax) | 0% (quarantine broken) or 100% (no filtering) |
| Staleness rate | <15% of recalled patterns are outdated | 15-30% | >30% |
| Contradiction count | 0 active contradictions | 1-2 flagged | >2 unflagged |
| Confidence calibration | High-confidence patterns succeed more than low-confidence | No correlation | Inverted correlation |
| Cross-pollination accuracy | >50% of cross-project recalls are useful | 25-50% | <25% (noise) |

### The `/memory review` Skill as Health Check

Monthly execution of `/memory review` produces the health report. It's the equivalent of running a test suite on the knowledge store — not testing code, but testing the quality of accumulated knowledge.

What it checks:
- Pattern count by namespace and confidence tier
- Staleness distribution (last-used dates vs current date)
- Promotion/demotion velocity (is the system actively curating?)
- Contradiction candidates (patterns with overlapping tags but conflicting content)

---

## Calibration: User Feedback Closes the Loop

The system can self-test structural and behavioral properties. It cannot self-test whether the user finds it useful. That calibration comes from [00-user-practices.md](../00-user-practices.md):

- **"The patterns recalled today were actually useful"** vs **"mostly noise"** — qualitative signal that complements precision@k
- **Practices the user keeps documenting manually** — signals for missing automation (a practice repeated 3+ times should graduate to a hook or check)
- **Anti-patterns discovered in use** — when the user notices something consistently doesn't work, that's a stronger signal than any automated metric

The living brain isn't just hooks and memory stores. It includes the human who uses it and feeds back what works.

---

## What R3 Validates from R2

The architecture reflection ([14-mastermind-architecture.md](./14-mastermind-architecture.md)) makes structural claims. This reflection provides the verification framework:

| R2 Claim | R3 Verification |
|----------|-----------------|
| Three-layer architecture (Identity, Intelligence, Context) composes correctly | Structural: context budget check, hook config validation |
| ReasoningBank enables cross-project learning | Behavioral: round-trip test. Outcome: cross-pollination accuracy |
| Quarantine prevents bad pattern spread | Behavioral: quarantine transition tests |
| Hooks drive the learning loop | Behavioral: hook lifecycle tests with realistic inputs |
| Skills provide the workflow | Behavioral: skill activation rate. Outcome: skill usefulness (LLM-as-judge) |
| Enforcement hierarchy (convention → workflow → hooks → linters) works | Structural: gate verification. Outcome: compliance rate measurement |
| Token budget is the primary constraint | Structural: budget validation. Outcome: does staying under budget improve performance? |

---

## Cross-References

- [14-mastermind-architecture.md](./14-mastermind-architecture.md) — R2: what this reflection validates
- [22-testing.md](../../../brana-knowledge/dimensions/22-testing.md) — testing methodology: 7-layer pyramid, record/playback, headless mode
- [23-evaluation.md](../../../brana-knowledge/dimensions/23-evaluation.md) — eval methodology: pass@k/pass^k, RAG metrics, LLM-as-judge, fixture evals
- [16-knowledge-health.md](../../../brana-knowledge/dimensions/16-knowledge-health.md) — immune system design: quarantine, decay, contradiction detection
- [00-user-practices.md](../00-user-practices.md) — user feedback loop: calibration signal for outcome quality
- [08-diagnosis.md](./08-diagnosis.md) — R1: triage decisions that R3 validates were correct
- [32-lifecycle.md](./32-lifecycle.md) — R4: lifecycle stages where assurance applies (test before merge, validate before deploy)
