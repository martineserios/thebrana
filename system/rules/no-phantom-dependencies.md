---
paths: ["system/skills/**", "system/procedures/**"]
---

# Never Reference Non-Existent Docs in Skill LOAD Steps

Never build a skill whose LOAD step references a doc that doesn't exist yet.

**Why:** Phantom references cause skill failures at runtime when the LOAD step tries to read a missing file. Skeleton-first prevents this.
**How to apply:** Before wiring a LOAD path in a SKILL.md, verify the target file exists: `ls path/to/doc.md`. If it doesn't exist, create a stub first, then wire it.
