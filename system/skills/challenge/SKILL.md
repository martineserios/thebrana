---
name: challenge
description: "Spawn an Opus subagent to stress-test the current plan or approach. One-pass adversarial review. Use when a significant decision, plan, or architecture needs adversarial review."
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

This skill spawns an Opus subagent to adversarially review a plan, approach, or decision.

1. **Gather context** about what to challenge:
   - If `$ARGUMENTS` provided, use it as the description of what to challenge.
   - If no arguments: **self-challenge mode** — challenge your own most recent substantive answer. Scan the conversation for your last analysis, recommendation, plan, or decision. That becomes the target. Frame it as: "Let me stress-test what I just said."

2. **Choose challenge flavor** based on context:
   - Architecture/design decisions → **Pre-mortem**: "Imagine this solution failed in production 3 months from now. What went wrong?"
   - Implementation plans → **Simplicity challenger**: "Can you achieve the same outcome with half the complexity?"
   - Migration/performance/estimates → **Assumption buster**: "What are you assuming that might not be true?"
   - Code/security review → **Adversarial reviewer**: Find concrete problems, security issues, performance concerns.

3. **Query NotebookLM for doc-grounded context** (auto, skip silently if unavailable):
   - Call `mcp__notebooklm__get_health` — if not authenticated, skip this step
   - Call `mcp__notebooklm__search_notebooks` with keywords from the challenge target
   - If a relevant notebook exists, call `mcp__notebooklm__ask_question`:
     ```
     "What documented constraints, decisions, best practices, or past failures
      are relevant to: [challenge target summary]?
      Cite specific sources."
     ```
   - Feed the response to the Opus subagent as **"Prior knowledge (Gemini, grounded in dimension docs)"**
   - The subagent should compare the plan against this documented knowledge and flag contradictions

4. **Spawn Opus subagent** using the Task tool:
   - `model: "opus"`
   - `subagent_type: "general-purpose"`
   - Provide: the plan/approach being challenged + relevant code/files
   - Key instruction: "Be specific and actionable. Don't nitpick — focus on things that would actually cause problems or wasted effort. Suggest concrete alternatives for each concern."

5. **Present findings** alongside the original plan. If NotebookLM context was used, note which concerns are backed by documented knowledge vs pure reasoning.

6. **Let the user decide** which concerns to address. Do not auto-apply changes.

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
     --tags "project:PROJECT,type:challenge,outcome:accepted|rejected|partial,confidence:quarantine"
   ```

   If claude-flow is unavailable, append to `~/.claude/projects/{project-hash}/memory/MEMORY.md`.

## Rules

- **No arguments = self-challenge.** Empty `/challenge` targets your own last answer. Never ask "what should I challenge?" — either use the provided arguments or self-challenge.
- **Ask for clarification on scope**, not on target. If you know WHAT to challenge but not HOW DEEP, ask. If the conversation has no substantive prior answer to self-challenge (e.g., session just started), then ask what to target.
