---
name: challenge
description: Spawn a Sonnet subagent to stress-test the current plan or approach. One-pass adversarial review.
allowed-tools:
  - Task
  - Read
  - Glob
  - Grep
disable-model-invocation: true
context: fork
---

# Challenge

This skill spawns a Sonnet subagent to adversarially review a plan, approach, or decision.

1. **Gather context** about what to challenge:
   - If `$ARGUMENTS` provided, use it as the description of what to challenge.
   - Otherwise, look for the most recent plan, proposal, or significant decision in the conversation.

2. **Choose challenge flavor** based on context:
   - Architecture/design decisions → **Pre-mortem**: "Imagine this solution failed in production 3 months from now. What went wrong?"
   - Implementation plans → **Simplicity challenger**: "Can you achieve the same outcome with half the complexity?"
   - Migration/performance/estimates → **Assumption buster**: "What are you assuming that might not be true?"
   - Code/security review → **Adversarial reviewer**: Find concrete problems, security issues, performance concerns.

3. **Spawn Sonnet subagent** using the Task tool:
   - `model: "sonnet"`
   - `subagent_type: "general-purpose"`
   - Provide: the plan/approach being challenged + relevant code/files
   - Key instruction: "Be specific and actionable. Don't nitpick — focus on things that would actually cause problems or wasted effort. Suggest concrete alternatives for each concern."

4. **Present findings** alongside the original plan.

5. **Let the user decide** which concerns to address. Do not auto-apply changes.

## Rules

- **Ask for clarification whenever you need it.** If the scope of the challenge is unclear, you're unsure what to focus on, or you need more context — ask. Don't guess.
