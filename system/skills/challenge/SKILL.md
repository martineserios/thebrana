---
name: challenge
description: "Dual-model adversarial review. Opus subagent stress-tests reasoning; Gemini stress-tests against documented knowledge. Use when a significant decision, plan, or architecture needs adversarial review."
group: learning
allowed-tools:
  - Task
  - Read
  - Glob
  - Grep
  - mcp__notebooklm__ask_question
  - mcp__notebooklm__search_notebooks
  - mcp__notebooklm__get_health
disable-model-invocation: true
context: fork
---

# Challenge

Dual-model adversarial review. Opus stress-tests reasoning and finds logical flaws. Gemini stress-tests against documented knowledge and finds contradictions with existing docs. Both run independently, findings are merged.

1. **Gather context** about what to challenge:
   - If `$ARGUMENTS` provided, use it as the description of what to challenge.
   - If no arguments: **self-challenge mode** — challenge your own most recent substantive answer. Scan the conversation for your last analysis, recommendation, plan, or decision. That becomes the target. Frame it as: "Let me stress-test what I just said."

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

   **3b. Gemini challenger** — Query NotebookLM (skip silently if unavailable):
   - Call `mcp__notebooklm__get_health` — if not authenticated, skip 3b entirely
   - Call `mcp__notebooklm__search_notebooks` with keywords from the challenge target
   - If a relevant notebook exists, call `mcp__notebooklm__ask_question` with:
     ```
     "I need you to adversarially review this plan/decision:

     [challenge target summary]

     Your job: find problems. Specifically:
     1. What documented constraints, decisions, or best practices does this contradict or ignore?
     2. What past failures or known pitfalls in the sources apply here?
     3. What assumptions does this make that the documented knowledge doesn't support?
     4. What's missing — what do the docs say is important for this kind of work that the plan doesn't address?

     Be specific. Cite sources. Rate each finding: CRITICAL, WARNING, or OBSERVATION."
     ```
   - If the response is thin (no real findings), run a second query focused on related topics:
     ```
     "What are the most common mistakes or overlooked requirements when doing [topic area]?
      What do the sources warn about?"
     ```

4. **Merge and present findings.** Combine both challengers' output into a single report:

   ```
   ## Challenge Report

   **Target:** [what was challenged]
   **Flavor:** [pre-mortem / simplicity / assumption / adversarial]

   ### Critical Findings (would block success)
   - [Finding] — Source: Opus / Gemini ([source doc])

   ### Warnings (risk but manageable)
   - [Finding] — Source: Opus / Gemini ([source doc])

   ### Observations (minor, for consideration)
   - [Finding] — Source: Opus / Gemini ([source doc])

   ### Agreement
   - [Where both challengers raised the same concern — these are highest confidence]

   ### Verdict
   PROCEED / PROCEED WITH CHANGES / RECONSIDER
   ```

   When both Opus and Gemini flag the same concern independently, mark it as **high-confidence** — two models from different companies with different training data agree something is a problem.

5. **Let the user decide** which concerns to address. Do not auto-apply changes.

6. **Store challenge outcome** in ReasoningBank after the user decides:

   ```bash
source "$HOME/.claude/scripts/cf-env.sh"
```

   Store the outcome:
   ```bash
   cd $HOME && $CF memory store \
     -k "challenge:{PROJECT}:{short-topic}" \
     -v '{"flavor": "pre-mortem|simplicity|assumption|adversarial", "target": "what was challenged", "findings": "key concerns raised", "decision": "accepted|rejected|partial", "confidence": 0.5, "transferable": false, "recall_count": 0}' \
     --namespace patterns \
     --tags "project:PROJECT,type:challenge,outcome:accepted|rejected|partial,confidence:quarantine"
   ```

   If claude-flow is unavailable, append to `~/.claude/projects/{project-hash}/memory/MEMORY.md`.

## Rules

- **No arguments = self-challenge.** Empty `/challenge` targets your own last answer. Never ask "what should I challenge?" — either use the provided arguments or self-challenge.
- **Ask for clarification on scope**, not on target. If you know WHAT to challenge but not HOW DEEP, ask. If the conversation has no substantive prior answer to self-challenge (e.g., session just started), then ask what to target.
- **Both challengers run in parallel.** Don't wait for one to finish before starting the other. Launch Opus subagent and Gemini query at the same time.
- **Gemini is optional.** If NotebookLM is unavailable, the challenge runs as Opus-only. Never fail the skill because Gemini is missing.
- **Agreement = high confidence.** When both models independently flag the same issue, highlight it. Two different AI architectures agreeing on a problem is a strong signal.
