---
name: challenge
description: "Adversarial review — Fable 5 stress-tests reasoning, Gemini checks knowledge. Use before plan or architecture decisions."
model: sonnet
effort: high
keywords: [adversarial, review, stress-test, pre-mortem, simplicity, assumptions, council]
task_strategies: [feature, refactor, migration, greenfield]
stream_affinity: [roadmap, tech-debt]
argument-hint: "[target description] [--council] [--hats] [--deep]"
group: learning
allowed-tools:
  - Task
  - Workflow
  - Read
  - Glob
  - Grep
  - mcp__brana__agy_delegate
  - AskUserQuestion
  - ToolSearch
disable-model-invocation: true
context: fork
status: stable
growth_stage: evergreen
---
# Challenge

Adversarial review with two modes. **Standard:** three native challenger subagents (convergent · systems · critical) stress-test reasoning, Gemini retrieves documented constraints — all run independently, Claude merges and judges. **Council (`--council`):** Four parallel perspective agents (devil's advocate, optimist, pragmatist, operator) plus Gemini — Claude synthesizes across all five.

**Deep (`--deep`, or auto on high-stakes):** any mode, plus an adversarial **verification stage** — every merged finding is independently re-attacked by N skeptics (`verify-findings` workflow), so plausible-but-wrong findings are dropped to FALSE_POSITIVE and survivors get a calibrated severity before you see them. All agents are native subagents on the subscription — no ruflo, no API key.

1. **Gather context** about what to challenge:
   - If `$ARGUMENTS` provided, use it as the description of what to challenge.
   - If `$ARGUMENTS` contains `--council`: strip `--council` from the target description, activate **council mode** — step 4a spawns 4 parallel perspective agents instead of one Opus agent. All other steps unchanged.
   - If `$ARGUMENTS` contains `--hats`: strip `--hats` from the target description, activate **hats mode** — step 4a spawns 4 parallel hat agents (White/Black/Yellow/Green) instead of hive-mind workers. Mutually exclusive with `--council`; if both present, `--hats` wins.
   - If `$ARGUMENTS` contains `--deep`: strip `--deep` from the target description, activate **deep mode** — runs the adversarial verification stage (step 4d) over the merged findings before synthesis. Combinable with any mode (standard / `--council` / `--hats`).
   - **Auto-deep:** even without `--deep`, activate deep mode automatically when the target is high-stakes — an architectural or irreversible decision, cost-of-being-wrong rated expensive/catastrophic in step 2, or an M+ effort plan. When auto-triggering, tell the user one line: "High-stakes target — running deep verification."
   - If no arguments: **conversation-context inference** — scan recent conversation turns (both user and assistant) to identify the most significant unchalllenged decision, plan, or proposal. Priority order:
     1. A plan or architecture decision being actively discussed
     2. A proposal the user described or asked about
     3. Your own most recent substantive recommendation
     4. A trade-off or choice where alternatives weren't explored
   - Extract: the decision/plan itself, the key constraints mentioned, and any assumptions stated or implied.
   - Frame it naturally: "I see we're discussing [X]. Let me stress-test that." — not "Let me challenge my last answer."
   - If the conversation has no substantive decision context (e.g., session just started, only greetings), then ask what to target.

2. **Scope discovery** — before launching challengers, ask 2-4 targeted questions that could change the challenge outcome.

   First, think (silently): given what's being challenged, what dimensions are non-obvious but consequential? What does Claude not know yet that would change which findings matter?

   Then surface 2-4 questions via a single AskUserQuestion call. Choose from the dimensions below — pick the ones most relevant to the target. Skip generic process questions.

   | Dimension | When to ask | Example option set |
   |---|---|---|
   | Deadline pressure | Plan or implementation work | "this week" / "this month" / "no fixed date" |
   | Cost of being wrong | Architecture or migration | "cheap (refactor)" / "expensive (data migration)" / "catastrophic (prod incident)" |
   | What's been tried | Recurring problem or refactor | "first attempt" / "one prior approach" / "multiple stalled attempts" |
   | Stakeholder breadth | Anything visible externally | "just me" / "one other person" / "wider team" / "external users" |
   | Constraints already locked | Mid-project decisions | "nothing locked yet" / specific commitments listed |
   | Hard ceiling on scope | Sprawling proposals | "S" / "M" / "L" / "explicitly unbounded" |
   | Gemini grounding | Brana-domain decisions — user wants to skip | "run agy (Recommended)" / "skip — no Brana docs apply" |

   Use the answers to:
   - Calibrate severity (high deadline pressure → demote long-term observations to LOW)
   - Choose flavor in step 3 (e.g., "multiple stalled attempts" → assumption-buster, not pre-mortem)
   - Brief the Opus challenger ("user has these constraints already locked: …")
   - Decide whether to run Gemini (skip if user says "no Brana docs apply")

   Skip step 2 entirely if: the target is trivial, the user said "no scope ambiguity" / "just challenge it", or the conversation already established these dimensions naturally.

3. **Choose challenge flavor** based on context (and scope answers from step 2):
   - Architecture/design decisions → **Pre-mortem**: "Imagine this solution failed in production 3 months from now. What went wrong?"
   - Implementation plans → **Simplicity challenger**: "Can you achieve the same outcome with half the complexity?"
   - Migration/performance/estimates → **Assumption buster**: "What are you assuming that might not be true?"
   - Code/security review → **Adversarial reviewer**: Find concrete problems, security issues, performance concerns.
   - High-confidence plans / user seems anchored / "obviously good" decision → **Inversion**: "What would guarantee this fails completely?" Invert the goal, actively design failure, then check if any failure patterns are already present in the plan. Signal: user is very confident, plan has broad consensus, or multiple prior attempts stalled. For all flavors, a brief inversion pass can precede the hive-mind as a warm-up — brief the workers with the top 2 failure patterns found via inversion as additional context.

4. **Launch challengers in parallel:**

   **4a. Challenger(s)** — Two modes based on step 1 detection:

   **Standard mode** (default, no `--council` flag):
   Read `../_shared/adversarial-hive-mind.md` for the full pattern — three native `brana:challenger` subagents (convergent · systems · critical) spawned in parallel via the Agent tool, Claude merges. Caller-specific value: `prefix: "challenger"`.

   For all workers/fallback — provide: the plan/approach being challenged + relevant code/files + the chosen flavor.
   Key instruction: "Be specific and actionable. Don't nitpick — focus on things that would actually cause problems or wasted effort. Suggest concrete alternatives for each concern. Rate each finding: CRITICAL (would block success), WARNING (risk but manageable), OBSERVATION (minor, for consideration)."

   **Council mode** (`--council` flag set in step 1):
   Spawn 4 agents in parallel using the Agent tool. Each receives a distinct role; no agent sees another's output — synthesis is step 5's job. Use `subagent_type: "brana:challenger"` for each.

   | Role | Brief to include in agent prompt |
   |------|----------------------------------|
   | **Devil's advocate** | Find every way this could fail, backfire, or create hidden debt. Focus on worst-case scenarios and failure modes others would overlook. |
   | **Optimist** | Find what's undervalued. What hidden advantages exist? What assumptions are overly conservative? What could go better than the plan assumes? |
   | **Pragmatist** | Focus on what's actually buildable within the stated constraints. What scope traps exist? What will cost 10× more effort than estimated? What shortcuts are safe vs. risky? |
   | **Operator** | You will execute this plan as Claude in a future session. What is unclear, ambiguous, or underspecified? What will cause you to make a wrong judgment call at runtime? |

   For each: provide the plan/approach + chosen flavor + role brief. Key instruction: "Rate findings CRITICAL / WARNING / OBSERVATION. Be specific, no nitpicking. Suggest concrete alternatives for each concern."

   **Hats mode** (`--hats` flag set in step 1):
   Spawn 4 agents in parallel using the Agent tool. Each wears a single de Bono thinking hat — no agent sees another's output. Use `subagent_type: "brana:challenger"` for each. Blue (process/synthesis) is handled by Claude in step 5; Red (gut feeling) is brief and added inline by Claude after reading agent output.

   | Hat | Agent brief |
   |-----|------------|
   | **⬜ White — Facts** | Enumerate what is factually known, what data is missing, and what is uncertain or assumed. Do not evaluate or judge — report only. |
   | **⬛ Black — Caution** | Identify every risk, weakness, and way this could go wrong. What assumptions might be false? What has been overlooked? Rate each: CRITICAL / WARNING / OBSERVATION. |
   | **🟨 Yellow — Value** | Identify what is genuinely valuable, what the best realistic outcome looks like, and what hidden opportunities exist. Be specific — no generic praise. |
   | **🟩 Green — Alternatives** | Generate alternative approaches that haven't been considered. What if a key constraint were relaxed? What's the unconventional angle? What could be combined differently? |

   For each: provide the plan/approach + chosen flavor + hat brief. Key instruction: "Think only in your hat's mode. Do not mix perspectives. Be specific and concrete."

   **4b. Gemini detail retriever** — Query agy (Gemini Flash via brana compute). Runs by default; skip only if the user explicitly opted out in step 2 or if `mcp__brana__agy_delegate` returns an error.

   Run a **two-pass retrieval** in parallel with step 4a:

   **Pass 1 — Constraint extraction** (Gemini's strength: detail retrieval, not reasoning):
   - Extract specific technical nouns from the challenge target (hook names, tool names, thresholds, module names). Use these as query anchors — never "the brana system" or broad abstractions.
   - Call `mcp__brana__agy_delegate` with:
     ```
     prompt: "You are reviewing the brana system. List every specific constraint,
      threshold, requirement, and documented rule that relates to [specific technical
      noun from the plan]. For each, give the exact number or rule and note which
      context it comes from. If you cannot find something verbatim, say so explicitly
      rather than stating it as fact. Do not summarize — enumerate."
     ```
   - **Canned-response detection:** If the response is < 150 words, matches a generic system overview pattern, or doesn't contain any specific numbers/constraints, discard and retry once with a more specific anchor term from the plan. If retry also fails, note "Gemini returned no grounded constraints" and proceed without.

   **Pass 2 — Adjacent constraints** (if Pass 1 returned results):
   - Call `mcp__brana__agy_delegate`:
     ```
     prompt: "You are reviewing the brana system. What documented requirements,
      version constraints, and named dependencies are adjacent to [topic from Pass 1]?
      Include specific thresholds, tool names, and file paths. If inferring beyond
      documented knowledge, mark it [INFERENCE]."
     ```

   **On error:** If `mcp__brana__agy_delegate` fails for **any reason** — MCP tool-call failure (version mismatch, binary not found, JSON-RPC error), response starting with `"Error:"`, or empty/unusable output — skip 4b **completely and silently**. Do NOT add an "Unavailable" note or any Gemini reference to the report. Do NOT surface the error message. Proceed as if step 4b was never attempted.

   **4c. Compliance check** (Claude, main context — after both 4a and 4b complete):
   - Take the constraints retrieved by Gemini in 4b
   - Check the challenge target against each retrieved constraint
   - Flag violations as findings with source attribution
   - This is where the adversarial reasoning happens — Claude judges, Gemini retrieves

   **4d. Adversarial verification** (deep mode only — `--deep` flag or auto-deep from step 1):
   After 4a–4c produce the raw findings, before synthesizing, re-attack each finding to drop plausible-but-wrong ones. Collect the merged findings into a list (one entry per concern, with its provisional severity and source), then dispatch:
   ```
   Workflow({ scriptPath: ".claude/workflows/verify-findings.js", args: {
     target: "{what was challenged}",
     findings: [ { severity: "CRITICAL", text: "{finding}", source: "{agent/role}" }, ... ],
     voters: 2
   }})
   ```
   The workflow returns each finding with `holds` / `adjusted_severity` / `reason`. In step 5: drop `FALSE_POSITIVE` findings (list them in a short "Refuted in verification" note so the user sees what was filtered), and present survivors at their `adjusted_severity` rather than the raw one. Gemini compliance findings (4c) are HIGH-confidence by construction — pass them through verification too, but a refutation only downgrades, never deletes, a doc-grounded constraint.
   If the Workflow tool is unavailable, fall back: Claude re-attacks each CRITICAL/WARNING finding inline (one skeptical pass each) before synthesis.

5. **Merge and present findings with confidence tiers.** Await all agents (and Gemini if running) before synthesizing. Each finding gets a confidence tier based on its source:

   | Source | Confidence | Why |
   |--------|-----------|-----|
   | Agreement (Opus + Gemini) | **HIGH** | Two models, different architectures, same concern |
   | Council agreement (2+ of 4 agents) | **HIGH** `[COUNCIL-AGREEMENT: N/4]` | Independent perspectives, same root concern |
   | Opus-only / single council agent | **MEDIUM** | Strong reasoning, may lack doc grounding |
   | Gemini with source citation | **MEDIUM** `[AGY-UNVERIFIED]` | Good retrieval, but citation needs verification |
   | Gemini citing external tools/practices not in docs | **LOW** `[AGY-UNVERIFIED]` | Hallucination risk — Gemini invents plausible references |
   | Compliance check (4c) | **HIGH** | Claude reasoning on Gemini-retrieved constraints |
   | Survived deep verification (4d) | **+ `[VERIFIED]`** | Re-attacked by N independent skeptics and held; severity recalibrated. Tag added on top of the source tier. |

   **Standard mode report:**
   ```
   ## Challenge Report

   **Target:** [what was challenged]
   **Flavor:** [pre-mortem / simplicity / assumption / adversarial]

   ### Critical Findings (would block success)
   - [Finding] — Source: Opus / Compliance-check — Confidence: HIGH/MEDIUM

   ### Warnings (risk but manageable)
   - [Finding] — Source: Opus / Compliance-check — Confidence: HIGH/MEDIUM

   ### Observations (minor, for consideration)
   - [Finding] — Source: Gemini [AGY-UNVERIFIED] — Confidence: LOW/MEDIUM

   ### Agreement (highest confidence)
   - [Where both challengers raised the same concern]

   ### Gemini Constraint Retrieval
   - [Constraints retrieved by Gemini — available for manual verification]

   ### Verdict
   PROCEED / PROCEED WITH CHANGES / RECONSIDER
   ```

   **Council mode report** (when `--council` was set):

   Dedup first: for each finding raised by 2+ agents, collapse to one entry tagged `[COUNCIL-AGREEMENT: N/4]`. These are the highest-confidence signals regardless of severity.

   ```
   ## Challenge Report (Council)

   **Target:** [what was challenged]
   **Mode:** Council — devil's advocate · optimist · pragmatist · operator
   **Flavor:** [pre-mortem / simplicity / assumption / adversarial]

   ### Critical Findings (would block success)
   - [Finding] [COUNCIL-AGREEMENT: 3/4] — Confidence: HIGH
   - [Finding] — Source: Devil's advocate — Confidence: MEDIUM

   ### Warnings (risk but manageable)
   - [Finding] [COUNCIL-AGREEMENT: 2/4] — Confidence: HIGH
   - [Finding] — Source: Pragmatist — Confidence: MEDIUM

   ### Observations (minor, for consideration)
   - [Finding] — Source: Optimist — Confidence: MEDIUM

   ### Perspectives Summary
   **Devil's advocate:** [top 1-2 concerns]
   **Optimist:** [top 1-2 undervalued aspects]
   **Pragmatist:** [top 1-2 scope/effort risks]
   **Operator:** [top 1-2 runtime ambiguities]

   ### Cross-cutting Themes
   - [Concern raised across 3+ perspectives, even if differently framed]

   ### Gemini Constraint Retrieval
   - [Constraints retrieved by Gemini — available for manual verification]

   ### Verdict
   PROCEED / PROCEED WITH CHANGES / RECONSIDER
   ```

   **Hats mode report** (when `--hats` was set):

   ```
   ## Challenge Report (Six Hats)

   **Target:** [what was challenged]
   **Mode:** Six Hats — White · Black · Yellow · Green
   **Flavor:** [pre-mortem / simplicity / assumption / adversarial / inversion]

   ### ⬜ White — Facts & Data
   Known: [key established facts]
   Missing / uncertain: [gaps in current knowledge]

   ### ⬛ Black — Risks & Caution
   - [Risk] — Confidence: HIGH/MEDIUM (CRITICAL / WARNING / OBSERVATION)
   - [Risk] — Confidence: HIGH/MEDIUM

   ### 🟨 Yellow — Value & Opportunities
   - [Genuine upside or hidden opportunity]
   - [What the best realistic outcome looks like]

   ### 🟩 Green — Alternatives
   - [Alternative approach or option not yet considered]
   - [What changes if constraint X is relaxed?]

   ### 🟥 Red — Gut Signal (Claude inline)
   [One sentence: what feels most wrong or most right about this, beyond what the other hats surfaced]

   ### Cross-hat Themes
   - [Concern or pattern appearing across multiple hats]

   ### Gemini Constraint Retrieval
   - [Constraints retrieved by Gemini — available for manual verification]

   ### Verdict
   PROCEED / PROCEED WITH CHANGES / RECONSIDER
   ```

6. **Let the user decide** which concerns to address. Do not auto-apply changes.

7. **Log findings to decision log** (before storing to memory):

   ```bash
   brana decisions log --agent challenger --entry-type concern \
     --content "{target}: {key finding summary}" \
     --severity "{highest finding severity}" \
     --refs "{task-id if applicable}" 2>/dev/null || true
   ```

   Log one entry per CRITICAL or WARNING finding. OBSERVATION-level findings are not logged.

8. **Store challenge outcome** in ReasoningBank after the user decides:

   ```bash
source "$HOME/.claude/scripts/cf-env.sh"
```

   Store the outcome:
   ```bash
   cd $HOME && $CF memory store \
     -k "challenge:{PROJECT}:{short-topic}" \
     -v '{"flavor": "pre-mortem|simplicity|assumption|adversarial", "target": "what was challenged", "findings": "key concerns raised", "decision": "accepted|rejected|partial", "confidence": 0.5, "transferable": false, "recall_count": 0}' \
     --namespace pattern \
     --tags "client:PROJECT,type:challenge,outcome:accepted|rejected|partial,confidence:quarantine"
   ```

   If ruflo is unavailable, append to `~/.claude/projects/{project-hash}/memory/MEMORY.md`.

## Rules

- **Challengers are native subagents, not ruflo.** Standard/council/hats modes all spawn real `brana:challenger` subagents via the Agent tool (subscription, no API key). Never reintroduce the ruflo hive-mind MCP tools — those calls write metadata records and self-votes but never execute workers (verified theater, 2026-06-19; see `field-note_ruflo-agentic-layer-subscription-theater`).
- **`--deep` strips before use.** Strip the flag from `$ARGUMENTS` before using the remainder as the target. `--deep` adds step 4d (verify) on top of whatever mode is active; it does not change the find mode.
- **Auto-deep on high-stakes.** Trigger deep verification without the flag when the target is architectural/irreversible, cost-of-being-wrong is expensive/catastrophic, or effort is M+. Announce it in one line; don't ask permission.
- **Verification downgrades, never deletes, doc-grounded findings.** A compliance finding (4c) refuted in 4d drops a tier but is never removed — a documented constraint that a skeptic argues against still deserves the user's eyes.
- **Ask for clarification on scope**, not on target. If you know WHAT to challenge but not HOW DEEP, ask.
- **All challengers run in parallel.** Don't wait for one to finish before starting others. Launch all agents and Gemini simultaneously.
- **`--council` strips before use.** Strip the flag from `$ARGUMENTS` before using the remainder as the target description. Never include `--council` in the agent brief.
- **Council agents are isolated.** No agent in a council run sees another's output. Cross-agent synthesis is exclusively Claude's job in step 5.
- **Council dedup rule.** When 2+ council agents raise the same root concern (even if differently worded), collapse to a single finding tagged `[COUNCIL-AGREEMENT: N/4]`. Agreement is the signal, not the phrasing.
- **`--hats` strips before use.** Strip the flag from `$ARGUMENTS` before using the remainder as the target description. Never include `--hats` in the agent brief.
- **Hats agents are isolated.** No hat agent sees another's output — synthesis is Claude's job in step 5. Each agent thinks only in its designated mode; do not ask a White-hat agent to evaluate or a Black-hat agent to find upsides.
- **`--hats` vs `--council` choice signal.** Use `--hats` when the decision needs balanced perspective across facts/risks/value/alternatives (e.g., strategy calls, product trade-offs, "should we do X?"). Use `--council` when pure adversarial stress-testing is needed (e.g., production plans, security review, "what could go wrong?"). The two modes are mutually exclusive — if both flags present, `--hats` wins.
- **Inversion flavor as warm-up.** When inversion is the chosen flavor OR when the user seems anchored, run a brief inversion pass (invert the goal, list top 3 failure patterns) BEFORE briefing the hive-mind or hat agents. Include the top 2 inversion findings in the agent briefs as additional context.
- **Gemini runs by default.** Skip only if the user explicitly opted out in step 2 ("skip — no Brana docs apply") or if `mcp__brana__agy_delegate` fails for any reason (see step 4b "On error"). On any failure: skip silently — no mention of Gemini in the report. Proceed without Gemini (standard: Opus-only; council: 4 agents only). Never fail the skill because Gemini is unavailable.
- **Gemini flow is unchanged in council mode.** 4b runs in parallel with the 4 council agents. Step 5 synthesizes all results together.
- **Agreement = high confidence.** When multiple models independently flag the same issue, highlight it. Independent architectures agreeing on a problem is a strong signal.
- **Gemini retrieves, Claude reasons.** Never ask Gemini to "adversarially review" or "find problems" — it falls back to generic summaries. Ask it to enumerate specific constraints, then Claude checks compliance. Gemini is a detail-extraction engine, not a synthesis engine.
- **Anchor Gemini queries to technical nouns.** Use specific terms from the plan (hook names, tool names, thresholds) as query anchors. Never start a Gemini query with broad system names — this triggers canned overview responses.
- **Tag all Gemini-only claims.** Any finding sourced exclusively from Gemini must carry `[AGY-UNVERIFIED]`. The user decides whether to verify against source docs.
