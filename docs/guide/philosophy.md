# Philosophy

## Software development is a learning system

Most tools treat development as a sequence of tasks: pick a ticket, write the code, ship it. Brana treats it differently. Software development is a learning system — every session teaches something, every failure contains a pattern, and every problem solved in one project can shorten the next one.

This is the thesis behind brana. Not a smarter AI, not a better autocomplete. A system that learns continuously and retains what it learns.

## The problem with prompts

Most people who use AI for development rely on prompts. They write careful instructions, paste context, guide the model through each step. It works — until the next session, when they start over.

The problem is that prompts are stateless. Nothing carries forward. The AI doesn't remember that you prefer TypeScript strict mode, that the staging environment behaves differently than production, or that the third approach to the auth bug finally worked. Every session is day one.

Brana's answer is not better prompts. It is better infrastructure.

## How the system works

Three components do the real work:

**Rules** are behavioral directives loaded every session. Not suggestions — enforced defaults. `git-discipline.md` says every change starts on a branch, without exception. `sdd-tdd.md` says write the spec before the code, write the test before the implementation. These conventions exist in most engineering teams but drift over time. In brana, they don't drift because the AI reads them fresh on every session start.

**Hooks** are the event-driven enforcement layer. The PreToolUse hook fires before every file edit. On a feature branch in a project with ADRs, it blocks implementation files until a spec or test exists on that branch — not as a reminder, as a gate. The SessionStart hook recalls stored patterns from memory before any work begins. The SessionEnd hook extracts learnings when the session closes and stores them for next time. Hooks turn conventions into infrastructure.

**The spec graph** connects specs to code. Dimension docs (deep research) feed into reflection docs (cross-cutting synthesis), which feed into roadmap docs (implementation plans). When a dimension doc changes, `/brana:maintain-specs` cascades the change forward. When implementation diverges from specs, `/brana:reconcile` detects it. The system knows when things are out of sync and flags it — rather than letting drift accumulate silently.

## What the system produces

Over time, these components compound.

An AI that only prompts might catch that you prefer a specific pattern for error handling — in this session. Brana stores that preference as a rule or a learned pattern, and it applies it in the next session without being reminded. After a month of working across three projects, the memory holds hundreds of patterns: what worked, what failed, which approach to avoid on which stack.

The cross-client memory is the part that surprises people. A solution discovered while debugging a Supabase auth issue on one project gets stored with tags. Six weeks later on a different project, when a similar pattern emerges, the SessionStart hook surfaces the earlier solution before any work begins. The compound effect is real: new projects bootstrap faster because solved problems stay solved.

The cascade throttle is a concrete example of how failure translates to structure. After three consecutive failures editing the same file, the hook injects a warning: "This file has failed repeatedly. Stop and reassess." Not a block — a signal to step back instead of patching forward. The `self-improvement` rule says the same thing: on failure, stop and reassess from scratch. The hook enforces it mechanically even when the model might otherwise push forward.

## Why infrastructure over prompts

The gap between a good AI session and a consistently good AI system is enforcement. Rules help — but rules in markdown files get ignored when the model is in flow or under pressure. Hooks don't get ignored. They fire on every relevant event, deterministically, regardless of what else is happening in the session.

This is the core design choice: move discipline from convention (AI might follow it) to enforcement (AI cannot bypass it).

The enforcement hierarchy reflects this explicitly. Rules achieve roughly 80% compliance. Skills structured workflows get 85-95%. PreToolUse hooks approach 100% — the AI cannot write to an implementation file before the spec exists if the hook blocks it.

The goal is not to constrain the AI. The goal is to make good practices the path of least resistance, so the human doesn't have to remember to enforce them.

## What this is not

Brana is not an attempt to replace engineering judgment. The challenger agent adversarially reviews plans, but it presents findings — not decisions. The memory system surfaces patterns, but the developer chooses what to apply. The hooks enforce discipline, but they operate on clearly defined structural conditions, not on the substance of the code.

The system acts as a partner that remembers, transfers knowledge, and protects its own quality. The engineering decisions remain with the engineer.

---

**Next steps:**
- [Getting Started](getting-started.md) — install and run your first session
- [Concepts](concepts.md) — vocabulary for rules, hooks, agents, and skills
- [Architecture](../reflections/ARCHITECTURE.md) — how the three layers compose
