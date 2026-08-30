---
title: Issue tracker — how agents use the brana backlog
status: live
task: t-3163
created: 2026-08-29
generated_by: "hand-written for thebrana (the reference instance); /brana:align emits this file for other repos from the shared template (system/skills/_shared/issue-tracker-template.md)"
---

# Issue tracker — how agents use the brana backlog

> This file is the tracker vocabulary map (ADR-086 §8; it *is* ADR-084 §3's
> "Other backend" mapping, so vendored upstream skills no longer carry their
> own). It answers one question: **when a skill or agent says a generic
> tracker word (create, comment, label, claim…), which real `brana` verb is
> that here?** Every verb below was run and verified 2026-08-29 (t-3163).
> Never read or write `.claude/tasks.json` directly — CLI/MCP only.

## Operations table

| Tracker operation | brana verb (CLI) | MCP tool | Notes |
|---|---|---|---|
| create an issue | `brana backlog add --subject "..." --kind <k> --effort <e>` | `backlog_add` | JSON form: `add --json '{...}'`. Context required for M+ effort |
| read an issue | `brana backlog get <t-NNN>` | `backlog_get` | `--field <name>` for one field |
| list / frontier | `brana backlog query --status pending ...` · `brana backlog next` | `backlog_query` | **`query --role ready-for-agent` lands with ADR-086 T1 (t-3160, pending)** — until then the frontier is `pending ∧ ac_state:approved ∧ ¬tag:parked ∧ blocked_by resolved` composed by the caller (or use `wave pull`, which applies it atomically) |
| comment | `brana backlog set <id> context --append "YYYY-MM-DD: ..."` | `backlog_set(append: true)` | Dated appends are the comment stream; pointer-not-paste discipline (§Home-of-record below) |
| label | `brana backlog set <id> tags +<tag>` / `tags -<tag>` | `backlog_set` | Namespaced tags allowed (`epic:<slug>`, `wave:<name>`) |
| approve for agents | `brana backlog ac <id> approve` | `backlog_ac_approve` | **Human-only valve** (ADR-079 §1). `set ac_state approved` is rejected by design; the loop may only `ac-propose` |
| close | `brana backlog set <id> status completed` | `backlog_set` | Outside build CLOSE this is runner-denied — completion is graded, not asserted |
| wontfix | `brana backlog set <id> status cancelled` + a context note saying why | `backlog_set` | A cancelled blocker does NOT auto-resolve `blocked_by` (ADR-079 amendment) — remove the edge explicitly |
| block on | `brana backlog set <id> blocked_by +t-NNN` | `backlog_set` | `-t-NNN` removes. Frontier respects unresolved blockers (t-3043) |
| claim (atomic) | `brana backlog wave pull <wave-id>` | — | Leased pull: sets in_progress atomically under lock; the sanctioned way a loop takes work |
| wayfinder map | an epic node: `brana backlog add --subject "<slug>" --type epic`, children via `parent` | `backlog_add` | Membership = parent chain (ADR-065); `brana backlog tree <id>` shows the subtree |
| decision ticket | `brana backlog add --kind research --parent <id> ...` | `backlog_add` | Findings land as a `docs/research/<date>-<topic>.md` doc the task points at |
| stale sweep | `brana backlog stale --days N` | `backlog_stale` | Park via `tags +parked` (ADR-078), never a bespoke status |

## Home-of-record table (pointer, not paste — ADR-086 §7)

A `context` append names the home of record and a one-line gist; it never
restates the content. If an inline append grows past a paragraph, that is
the signal it is really one of these documents:

| Content | Home (pointer target) | Inline in `context` |
|---|---|---|
| decision + rationale | ADR §n | one line + pointer |
| requirements / design | feature spec `docs/architecture/features/<slug>.md` | "spec: … §n" |
| evidence / findings | `docs/research/<date>-<topic>.md` | gist |
| shaping in flux | `docs/ideas/<topic>.md` | pointer to section |
| learning / gotcha | auto-memory pattern / field note | gist |
| code state | commit / branch / PR / `file:line` | ref only |
| sibling task history | `t-NNN` | "see t-NNN context <date>" |
| **task-local tactics** (next step, parking reason, "test with X not Y") | **nowhere else — this is what `context` is for** | inline, in full, short |

## Trust boundaries (the verbs an unattended loop must never run)

`ac approve` · `wave approve` (with confirm_ids) · `wave set status shipped` /
`wave ship` · `wave set gate|selector|contract` · `git merge`/`push` ·
`set status completed` outside build CLOSE. Mechanically enforced in
`BRANA_RUNNER=1` sessions by `system/hooks/runner-verb-guard.sh`; the
authoritative table lives in `docs/guide/workflows/drain-loop.md` §Denied verbs.
