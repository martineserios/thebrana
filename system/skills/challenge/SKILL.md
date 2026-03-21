---
name: challenge
description: "Dual-model adversarial review. Opus subagent stress-tests reasoning; Gemini stress-tests against documented knowledge. Use when a significant decision, plan, or architecture needs adversarial review."
effort: max
argument-hint: "[target description]"
group: learning
allowed-tools:
  - Task
  - Read
  - Glob
  - Grep
  - mcp__notebooklm__ask_question
  - mcp__notebooklm__search_notebooks
  - mcp__notebooklm__get_health
  - AskUserQuestion
disable-model-invocation: true
context: fork
---

# Challenge

Dual-model adversarial review. Opus stress-tests reasoning and finds logical flaws. Gemini retrieves specific documented constraints for compliance checking. Both run independently — Opus reasons, Gemini retrieves, Claude merges and judges.

1. **Gather context** about what to challenge:
   - If `$ARGUMENTS` provided, use it as the description of what to challenge.
   - If no arguments: **conversation-context inference** — scan recent conversation turns (both user and assistant) to identify the most significant unchalllenged decision, plan, or proposal. Priority order:
     1. A plan or architecture decision being actively discussed
     2. A proposal the user described or asked about
     3. Your own most recent substantive recommendation
     4. A trade-off or choice where alternatives weren't explored
   - Extract: the decision/plan itself, the key constraints mentioned, and any assumptions stated or implied.
   - Frame it naturally: "I see we're discussing [X]. Let me stress-test that." — not "Let me challenge my last answer."
   - If the conversation has no substantive decision context (e.g., session just started, only greetings), then ask what to target.

2. **Choose challenge flavor** based on context:
   - Architecture/design decisions → **Pre-mortem**: "Imagine this solution failed in production 3 months from now. What went wrong?"
   - Implementation plans → **Simplicity challenger**: "Can you achieve the same outcome with half the complexity?"
   - Migration/performance/estimates → **Assumption buster**: "What are you assuming that might not be true?"
   - Code/security review → **Adversarial reviewer**: Find concrete problems, security issues, performance concerns.

3. **Launch both challengers in parallel:**

   **3a. Opus challenger** — Spawn subagent using the Task tool:
   - `model: "opus"`
   - `subagent_type: "general-purpose"`
   - Provide: the plan/approach being challenged + relevant code/files + the chosen flavor
   - Key instruction: "Be specific and actionable. Don't nitpick — focus on things that would actually cause problems or wasted effort. Suggest concrete alternatives for each concern. Rate each finding: CRITICAL (would block success), WARNING (risk but manageable), OBSERVATION (minor, for consideration)."

   **3b. Gemini detail retriever** — Query NotebookLM (skip silently if unavailable):
   - Call `mcp__notebooklm__get_health` — if not authenticated, skip 3b entirely
   - Call `mcp__notebooklm__search_notebooks` with keywords from the challenge target
   - If a relevant notebook exists, run a **two-pass retrieval**:

   **Pass 1 — Constraint extraction** (Gemini's strength: detail retrieval, not reasoning):
   - Extract specific technical nouns from the challenge target (hook names, tool names, thresholds, module names). Use these as query anchors — never "the brana system" or broad abstractions.
   - Call `mcp__notebooklm__ask_question` with:
     ```
     "List every specific constraint, threshold, requirement, and documented rule
      from your sources that relates to [specific technical noun from the plan].
      For each, give the exact number or rule and cite which source document.
      If you cannot find something verbatim in your sources, say so explicitly
      rather than stating it as fact. Do not summarize — enumerate."
     ```
   - **Canned-response detection:** If the response is < 150 words, matches a generic system overview pattern, or doesn't contain any specific numbers/constraints, discard and retry once with a more specific anchor term from the plan. If retry also fails, note "Gemini returned no grounded constraints" and proceed without.

   **Pass 2 — Adjacent constraints** (if Pass 1 returned results):
   - Call `mcp__notebooklm__ask_question` in the same session:
     ```
     "What documented requirements, version constraints, and named dependencies
      are adjacent to [topic from Pass 1]? Include specific thresholds, tool names,
      and file paths. If inferring beyond your sources, mark it [INFERENCE]."
     ```

   **3c. Compliance check** (Claude, main context — after both 3a and 3b complete):
   - Take the constraints retrieved by Gemini in 3b
   - Check the challenge target against each retrieved constraint
   - Flag violations as findings with source attribution
   - This is where the adversarial reasoning happens — Claude judges, Gemini retrieves

4. **Merge and present findings with confidence tiers.** Combine all output into a single report. Each finding gets a confidence tier based on its source:

   | Source | Confidence | Why |
   |--------|-----------|-----|
   | Agreement (Opus + Gemini) | **HIGH** | Two models, different architectures, same concern |
   | Opus-only | **MEDIUM** | Strong reasoning, may lack doc grounding |
   | Gemini with source citation | **MEDIUM** `[NLM-UNVERIFIED]` | Good retrieval, but citation needs verification |
   | Gemini citing external tools/practices not in docs | **LOW** `[NLM-UNVERIFIED]` | Hallucination risk — Gemini invents plausible references |
   | Compliance check (3c) | **HIGH** | Claude reasoning on Gemini-retrieved constraints |

   ```
   ## Challenge Report

   **Target:** [what was challenged]
   **Flavor:** [pre-mortem / simplicity / assumption / adversarial]

   ### Critical Findings (would block success)
   - [Finding] — Source: Opus / Compliance-check — Confidence: HIGH/MEDIUM

   ### Warnings (risk but manageable)
   - [Finding] — Source: Opus / Compliance-check — Confidence: HIGH/MEDIUM

   ### Observations (minor, for consideration)
   - [Finding] — Source: Gemini `[NLM-UNVERIFIED]` — Confidence: LOW/MEDIUM

   ### Agreement (highest confidence)
   - [Where both challengers raised the same concern]

   ### Gemini Constraint Retrieval
   - [Constraints retrieved by Gemini — available for manual verification]

   ### Verdict
   PROCEED / PROCEED WITH CHANGES / RECONSIDER
   ```

5. **Let the user decide** which concerns to address. Do not auto-apply changes.

6. **Log findings to decision log** (before storing to memory):

   ```bash
   uv run python3 system/scripts/decisions.py log challenger concern "{target}: {key finding summary}" \
     --severity "{highest finding severity}" \
     --refs "{task-id if applicable}" 2>/dev/null || true
   ```

   Log one entry per CRITICAL or WARNING finding. OBSERVATION-level findings are not logged.

7. **Store challenge outcome** in ReasoningBank after the user decides:

   ```bash
source "$HOME/.claude/scripts/cf-env.sh"
```

   Store the outcome:
   ```bash
   cd $HOME && $CF memory store \
     -k "challenge:{PROJECT}:{short-topic}" \
     -v '{"flavor": "pre-mortem|simplicity|assumption|adversarial", "target": "what was challenged", "findings": "key concerns raised", "decision": "accepted|rejected|partial", "confidence": 0.5, "transferable": false, "recall_count": 0}' \
     --namespace patterns \
     --tags "client:PROJECT,type:challenge,outcome:accepted|rejected|partial,confidence:quarantine"
   ```

   If ruflo is unavailable, append to `~/.claude/projects/{project-hash}/memory/MEMORY.md`.

## Rules

- **No arguments = conversation inference.** Empty `/brana:challenge` scans the conversation for the most significant unchalllenged decision or plan — from either user or assistant. Never ask "what should I challenge?" unless the conversation truly has no decision context (session just started, only greetings).
- **Ask for clarification on scope**, not on target. If you know WHAT to challenge but not HOW DEEP, ask.
- **Both challengers run in parallel.** Don't wait for one to finish before starting the other. Launch Opus subagent and Gemini query at the same time.
- **Gemini is optional.** If NotebookLM is unavailable, the challenge runs as Opus-only. Never fail the skill because Gemini is missing.
- **Agreement = high confidence.** When both models independently flag the same issue, highlight it. Two different AI architectures agreeing on a problem is a strong signal.
- **Gemini retrieves, Claude reasons.** Never ask Gemini to "adversarially review" or "find problems" — it falls back to generic summaries. Ask it to enumerate specific constraints, then Claude checks compliance. Gemini is a detail-extraction engine, not a synthesis engine.
- **Anchor Gemini queries to technical nouns.** Use specific terms from the plan (hook names, tool names, thresholds) as query anchors. Never start a Gemini query with broad system names — this triggers canned overview responses.
- **Tag all Gemini-only claims.** Any finding sourced exclusively from Gemini must carry `[NLM-UNVERIFIED]`. The user decides whether to verify against source docs.
