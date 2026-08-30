# Redirect check — diagnosing-bugs (v1.2.3)

Every upstream slash-reference (`/name`) found in `.agents/skills/diagnosing-bugs/`'s text, and where it redirects. ADR-084 §1's pump re-greps this list on every upstream bump; an unmapped ref found by that grep is a reported drift, not a silent break.

Regenerate the "found" column with (run from repo root):
```bash
grep -noE '/[a-z][a-z-]+' .agents/skills/diagnosing-bugs/SKILL.md .agents/skills/diagnosing-bugs/agents/*.yaml .agents/skills/diagnosing-bugs/scripts/*.sh \
  | grep -vE '/(bin|env|usr|localhost|fail|failing|slow|throwing|console|network|hitl-loop)$'
```
(the excluded suffixes are path fragments and prose, not slash-commands — re-review the exclude list by hand on every bump, don't just widen it mechanically)

| Found in upstream text | Redirect |
|---|---|
| `/improve-codebase-architecture` (`SKILL.md:140`, Phase 6 handoff) | Not vendored (ADR-084 §4: SKIP for this wave, no stated pain point). Redirect: recommend filing a `kind:refactor` task describing the architectural gap found, don't reference the Pocock skill by name. |

## Also intercepted (not a slash-ref, but the same "breaks silently on upstream drift" class)

| Assumption | Redirect |
|---|---|
| `CONTEXT.md` (`SKILL.md:10`, "read `CONTEXT.md` if it exists") | brana has no repo-root glossary file. Adapter substitutes: pull the 2-3 most relevant `docs/architecture/*.md` files + the task's own context inline, per [SKILL.md](SKILL.md)'s remap section. |
| `/setup-matt-pocock-skills` | Not present in this skill's text (confirmed by the grep above) — no redirect needed for `diagnosing-bugs` specifically. Listed here because ADR-084 §3 names it as a general Pocock cross-reference class; it appears in `code-review` (t-2835, not yet vendored), not here. |
