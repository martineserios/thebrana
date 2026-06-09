---
paths: [".claude/CLAUDE.md", ".claude/CLAUDE.local.md"]
---
# Run Reconcile After CLAUDE.md Convention Changes

After any change to naming conventions in `.claude/CLAUDE.md` (branch prefixes, slug formats, task ID patterns, etc.), run:

```bash
/brana:reconcile --scope propagation
```

**Why:** Procedure files (`system/procedures/*.md`, `system/skills/*/SKILL.md`) embed branch naming examples verbatim. When the convention changes in CLAUDE.md, those examples silently go stale. The `propagation` scope catches spec→impl drift across all procedure files.

**How to apply:** This fires when CLAUDE.md is in the working set. If you just updated a naming convention, run reconcile before closing the session. The issue that prompted this rule: `build.md` retained the old stream-based branch format (`feat/t-NNN-slug`) after CLAUDE.md was updated to the epic-scoped format (`{epic-slug}/{work-type}/t-{NNN}-{slug}`).
