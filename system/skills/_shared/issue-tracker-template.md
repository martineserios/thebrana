<!-- issue-tracker-template.md (t-3163, ADR-086 §8) — the template /brana:align
     copies to a target repo's docs/agents/issue-tracker.md. Grain file, single
     owner: edit HERE, never fork per-repo wording. thebrana's own copy
     (docs/agents/issue-tracker.md) is the hand-verified reference instance.
     ALIGN MUST: (1) replace {{PROJECT}}; (2) run/verify every verb in the
     target repo before committing — a row that doesn't verify gets corrected
     or dropped, never shipped unverified; (3) drop the wave/runner rows when
     the target repo has no wave machinery. -->
---
title: Issue tracker — how agents use the {{PROJECT}} backlog
status: live
generated_by: "/brana:align from system/skills/_shared/issue-tracker-template.md — regenerate there, do not fork wording"
---

# Issue tracker — how agents use the {{PROJECT}} backlog

> Tracker vocabulary map: when a skill or agent says a generic tracker word
> (create, comment, label, claim…), this table says which real `brana` verb
> that is here. Never read or write `.claude/tasks.json` directly — CLI/MCP only.

## Operations table

| Tracker operation | brana verb (CLI) | MCP tool | Notes |
|---|---|---|---|
| create an issue | `brana backlog add --subject "..." --kind <k> --effort <e>` | `backlog_add` | JSON form: `add --json '{...}'` |
| read an issue | `brana backlog get <t-NNN>` | `backlog_get` | `--field <name>` for one field |
| list / frontier | `brana backlog query --status pending ...` · `brana backlog next` | `backlog_query` | Frontier = `pending ∧ ac_state:approved ∧ ¬tag:parked ∧ blocked_by resolved` |
| comment | `brana backlog set <id> context --append "YYYY-MM-DD: ..."` | `backlog_set(append: true)` | Dated appends; pointer-not-paste (see home-of-record) |
| label | `brana backlog set <id> tags +<tag>` / `tags -<tag>` | `backlog_set` | Namespaced tags allowed (`epic:<slug>`) |
| approve for agents | `brana backlog ac <id> approve` | `backlog_ac_approve` | Human-only valve (ADR-079 §1) |
| close | `brana backlog set <id> status completed` | `backlog_set` | Completion is graded, not asserted |
| wontfix | `brana backlog set <id> status cancelled` + context note | `backlog_set` | Cancelled blockers don't auto-resolve `blocked_by` — remove the edge |
| block on | `brana backlog set <id> blocked_by +t-NNN` | `backlog_set` | `-t-NNN` removes |
| claim (atomic) | `brana backlog wave pull <wave-id>` | — | Leased pull; drop this row if no wave machinery here |
| grouping map | epic node via `--type epic`; children via `parent`; `brana backlog tree <id>` | `backlog_add` | Membership = parent chain (ADR-065) |
| decision ticket | `brana backlog add --kind research --parent <id>` | `backlog_add` | Findings live in `docs/research/<date>-<topic>.md` |
| stale sweep | `brana backlog stale --days N` | `backlog_stale` | Park via `tags +parked`, never a bespoke status |

## Home-of-record table (pointer, not paste)

A `context` append names the home of record and a one-line gist; it never
restates the content:

| Content | Home (pointer target) | Inline in `context` |
|---|---|---|
| decision + rationale | ADR §n | one line + pointer |
| requirements / design | feature spec doc | "spec: … §n" |
| evidence / findings | `docs/research/<date>-<topic>.md` | gist |
| shaping in flux | `docs/ideas/<topic>.md` | pointer to section |
| learning / gotcha | auto-memory pattern / field note | gist |
| code state | commit / branch / PR / `file:line` | ref only |
| sibling task history | `t-NNN` | "see t-NNN context <date>" |
| task-local tactics | nowhere else — this is what `context` is for | inline, in full, short |
