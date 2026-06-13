---
always-load: true
---
# Work Start — Ordered Entry Protocol

When starting any task (implementation, design, research) follow these steps **in order**. First match wins; later steps refine the earlier ones.

## Precedence (numbered — no two steps claim first position)

**1. Read tasks.json first.**
Find the task, state what you found. Task exists → use its branch convention, set `in_progress`. No task → propose one before branching. See `task-convention.md` for full field/branch contract.

**2. Backlog start gate.**
If the user accepted a "continue with t-XXX?" or "start t-XXX?" suggestion, invoke `/brana:backlog start <id>` via the Skill tool **before any implementation**. Exception: user says "skip the workflow" or "just do it".

**3. Assess lifecycle gates.**
State which disciplines apply — even for S-effort fixes:
- **DDD**: `docs/domain/` exists AND task introduces/refines a domain entity → apply
- **SDD**: behavioral decision with architectural trade-offs (ADR needed) → apply
- **TDD**: code that can be tested → apply

One line per discipline: `DDD: skip — <reason>` / `SDD: apply — <reason>` / `TDD: apply`.

**4. Ask about skills.**
Present the detected workflow skill + domain skill via AskUserQuestion before loading either. Never silently invoke. Options: workflow only / domain only / both (default) / skip. Skip the ask if the skill was already loaded this session for this task.

Workflow skill map: implementation → `build` · research → `research` · architecture → `align` · spec/doc maintenance → `reconcile` · drift/security/sync → `reconcile`.

Domain skills: `brana skills suggest --query "<domain>"`. No match → offer `acquire-skills`.

**5. Route delegation.**
After skills are confirmed, apply the compute routing from `delegation-routing.md` §Compute Routing to decide who runs the work (Claude / Gemini / ruflo agent).
