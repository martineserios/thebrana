---
paths: ["system/**", ".claude/**", "docs/**"]
---

# Always Use Build Framework

Always start work via `/brana:backlog start <id>` → `/brana:build`. Never skip the framework to code directly.

**Why:** Skipping the framework bypasses spec-first gate, build_step tracking, and challenger review. Led to implementation cycles that were later scrapped.
**How to apply:** When the user says "start work on X" or "implement X", always run backlog start first. No exceptions for S-effort tasks.
