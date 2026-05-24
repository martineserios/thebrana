---
paths: ["system/**", ".claude/**", "docs/**"]
alwaysApply: true
---

# CWD Discipline

Always start Claude Code from the project root (e.g., ~/enter_thebrana/thebrana/),
never from a parent workspace directory like ~/enter_thebrana/.

Write permission blast radius = CWD + all subdirectories. Starting from a parent
directory expands write access to the entire portfolio.

## Gemini (agy) CWD isolation

`agy` is a subprocess with its own working directory — it is NOT subject to this rule
because it cannot write to the repo at all. Its output workspace is `/tmp/` only.
Claude reads from `/tmp/` and applies writes from the correct project CWD.

Do not pass project CWD to `agy` as a writable path. `/tmp/` is the only handoff zone.
