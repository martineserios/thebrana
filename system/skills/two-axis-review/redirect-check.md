# Redirect check — code-review (v1.2.3)

Every upstream slash-reference (`/name`) found in `.agents/skills/code-review/`'s text, and
where it redirects. ADR-084 §1's pump re-greps this list on every upstream bump; an
unmapped ref found by that grep is a reported drift, not a silent break.

Regenerate the "found" column with (run from repo root):
```bash
grep -noE '/[a-z][a-z-]+' .agents/skills/code-review/SKILL.md .agents/skills/code-review/agents/*.yaml \
  | grep -vE '/(bin|env|usr|localhost)$'
```
(the excluded suffixes are path fragments, not slash-commands — re-review the exclude list
by hand on every bump, don't just widen it mechanically)

| Found in upstream text | Redirect |
|---|---|
| `/setup-matt-pocock-skills` (`SKILL.md:13`, "run `/setup-matt-pocock-skills` if `docs/agents/issue-tracker.md` is missing") | Not present — `docs/agents/issue-tracker.md` already exists in this repo (t-3163), and this adapter never routes the Spec axis through it anyway (see [SKILL.md](SKILL.md)'s Spec-source remap: the spec source is the task's own `acceptance_criteria`/`context`, not the tracker-verb doc). The adapter always pre-supplies the spec-lookup answer via `system/scripts/two-axis-spec-lookup.sh`, so this path never fires; no install, no prompt. |

## Also intercepted (not a slash-ref, but the same "breaks silently on upstream drift" class)

| Assumption | Redirect |
|---|---|
| Issue tracker (`SKILL.md:13`, "The issue tracker should have been provided to you") | brana has no separate issue-tracker hand-off step. The adapter supplies the spec brief itself (task `acceptance_criteria`/`context`, via `two-axis-spec-lookup.sh`) before the Spec sub-agent is ever spawned — the upstream skill's own "look for the issue tracker" step is satisfied before it's reached. |
| `CODING_STANDARDS.md` / `CONTRIBUTING.md` (`SKILL.md:36`, "such as...") | brana has neither file. The adapter substitutes `system/rules/*.md` (the closest brana equivalent — behavioural conventions that bind all work: `sdd-tdd.md`, `no-patches-root-cause.md`, `universal-quality.md`, `git-discipline.md`) plus any domain-specific skill docs relevant to the diff's language (e.g. `brana:rust-skills`, `brana:bash-defensive-patterns`), per [SKILL.md](SKILL.md)'s Standards-source remap. |
| Spec source, item 1: "Issue references in commit messages... fetch via the workflow in `docs/agents/issue-tracker.md`" (`SKILL.md:29`) | Redirected to the task's own fields directly (AC2 of t-2835 is explicit this must NOT route through `docs/agents/issue-tracker.md` — that file maps tracker *verbs*, e.g. `brana backlog get`, it is not itself a spec source). The adapter resolves the branch's `t-NNN` and calls `backlog_get`/`two-axis-spec-lookup.sh` on the result. |
