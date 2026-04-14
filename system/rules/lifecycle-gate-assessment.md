---
paths: ["system/**", ".claude/**", "docs/**"]
---

# Always Assess Lifecycle Gates Before Starting

Before starting any task, assess which DDD/SDD/TDD lifecycle steps apply — even S-effort fixes.

**Why:** The failure mode is skipping the assessment, not skipping the step. A 30-second check prevents building without a spec or spec without tests.
**How to apply:** At /brana:build Step 1, explicitly state: "This task requires: [DDD|SDD|TDD|none] because [reason]." Document the skip reason if skipping a step.
