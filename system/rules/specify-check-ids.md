---
paths: [".claude/**", "system/skills/**"]
---

# SPECIFY Phase Must Check Existing Task IDs

Before proposing a task tree in the SPECIFY phase, read tasks.json to find the next available ID.

**Why:** Duplicate ID collisions cause silent overwrites or CLI errors. The SPECIFY phase is the only point where ID assignment can be validated before tasks are created.
**How to apply:** In /brana:build Step 2 (SPECIFY), run `brana backlog stats` or check the highest current ID before proposing new task IDs.
