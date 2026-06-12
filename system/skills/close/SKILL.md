---
name: close
description: "End a session — extract learnings, write handoff, store patterns, detect doc drift. Use when ending a work session or when the user says done/bye/closing."
effort: high
model: sonnet
keywords: [session, handoff, debrief, learnings, errata, drift]
task_strategies: [feature, bug-fix, refactor]
stream_affinity: [roadmap, tech-debt]
argument-hint: "[--continue|--finish|--patterns|--abort|--full|--light|--nano] [focus-hint]"
group: session
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Glob
  - Grep
  - AskUserQuestion
  - Agent
  - Task
  - TaskList
  - Skill
  - mcp__ruflo__memory_store
  - mcp__ruflo__memory_search
  - mcp__ruflo__hive-mind_memory
  - mcp__ruflo__claims_release
  - mcp__ruflo__claims_list
  - ToolSearch
status: stable
growth_stage: evergreen
---

# Close — Session End

End a work session. Extracts what was learned, writes a handoff note for the next session, stores patterns, and detects doc drift. Replaces `/session-handoff` close mode and `/debrief`.

## When to use

- User says "done", "bye", "closing", "that's it", or similar
- End of a long implementation session
- Before switching to a different project
- **Mid-session, on demand** — context relief before `/compact`, switching tasks, capturing a discovery, abandoning an approach
- Explicitly: `/brana:close [--<orientation>]`

## Orientation modes (ADR-053)

WHY you're closing picks WHAT runs. Flag given → execute immediately, no questions. Bare `/brana:close` → the gate detects the scenario and asks (options labeled with their flags — the picker teaches them).

| Flag | Use when | What happens |
|---|---|---|
| `--continue` | pausing to resume — context relief, task switch | snapshot + queue + resumable handoff; task stays `in_progress`; no cleanup |
| `--finish` | work is done | snapshot + queue + handoff; task → `completed`; cleanup runs; extraction tonight |
| `--patterns` | a discovery is worth keeping, regardless of task state | inline extraction (Steps 4–5) NOW; no queue, no handoff, no task/git changes |
| `--abort` | approach proven wrong | reason required; branch archived as pushed `aborted/*` tag via close-abort.sh; task → `pending` |

Deferred (post-v1): `--block`, `--handoff`, `--eod` — see ADR-053.

## Phase Protocol — how to execute this skill

The procedure body lives in per-phase files under `phases/` (this skill's base directory). **Never execute a phase from memory.** Three rules:

1. **On skill entry:** Read `phases/gate-and-evidence.md` first — always. It classifies the close weight (NANO/LIGHT/FULL) and gathers evidence; everything downstream depends on it.
2. **At every step boundary:** when a phase completes and the next begins, Read the next phase file from the PHASES registry below BEFORE doing any of its work. A phase you have not Read this session does not exist — do not improvise its steps.
3. **On resume after compression:** identify your current step (CC TaskList `/brana:close — {STEP}` entries), then Read the phase file that owns that step before continuing. Previously loaded phase content did NOT survive compression. Re-read `../_shared/guided-execution.md` too.

<!-- PHASES -->
| Steps (registry names) | File | Load when |
|------|------|-----------|
| GATE, GATHER, EXTRACT, DOC-CHECK (Steps 0–3b) | phases/gate-and-evidence.md | Skill entry — always first |
| ERRATA, PATTERNS (Steps 4–5) | phases/errata-and-patterns.md | Entering the parallel findings block (`--full`, LIGHT, and LIGHT-INLINE closes) |
| FIELD-NOTES, IDEATE (Steps 6–7) | phases/notes-and-ideation.md | With the parallel findings block |
| DRIFT (Step 8) | phases/doc-drift.md | With the parallel findings block |
| HANDOFF, RUFLO-SYNC (Steps 9–9c) | phases/session-state.md | After findings block completes |
| METADATA, MEMORY-REVIEW (Steps 10–11) | phases/metadata-and-memory.md | After session state is written |
| WORKTREE-REAP, PENDING-RECONCILE, STASH-CLEANUP, REPORT (Steps 11b–12 + session close) | phases/cleanup.md | Final phase — always last |
<!-- /PHASES -->

Steps 4–8 run in parallel: when entering that block, Read all three of `errata-and-patterns.md`, `notes-and-ideation.md`, and `doc-drift.md` before dispatching the parallel work. NANO and INSTANT closes skip them entirely; LIGHT-INLINE (`--patterns`) reads only `errata-and-patterns.md` and runs Steps 4–5 (the gate phase says when). Since Track 1 (ADR-052), the default for code sessions is **INSTANT** — snapshot + `brana close-queue append` + handoff, extraction deferred to the nightly cron; Steps 4–8 run in-session only on explicit `--full` (plus the LIGHT inline scan and the `--patterns` inline extraction).

In the deployed-plugin layout the same relative paths apply: `{base-dir}/phases/{file}`. If a path doesn't resolve, use Glob: `**/skills/close/phases/{file}`.

## Step Registry

On entry, create a CC Task step registry. Follow the [guided-execution protocol](../_shared/guided-execution.md).

Register these steps: GATE, GATHER, EXTRACT, DOC-CHECK, ERRATA, PATTERNS, FIELD-NOTES, IDEATE, DRIFT, HANDOFF, RUFLO-SYNC, METADATA, MEMORY-REVIEW, WORKTREE-REAP, PENDING-RECONCILE, STASH-CLEANUP, REPORT.

<!-- ruflo preamble -->
ToolSearch("select:mcp__ruflo__memory_store,mcp__ruflo__memory_search,mcp__ruflo__hive-mind_memory,mcp__ruflo__claims_release,mcp__brana__memory_index")

## Rules

1. **Extract from evidence, don't invent.** Every finding traces to something that happened — a command that failed, a mismatch observed, a workaround applied.
2. **Learnings must be actionable.** Each contains a concrete rule someone can follow. If you can't state it as a rule, it's not a learning yet.
3. **Don't duplicate.** Read existing errata before adding. If already documented, skip or note confirmation.
4. **Gate on changes.** Read-only sessions get a one-line handoff and no debrief.
5. **Don't block on failures.** Agent fails → manual scan. Claude-flow fails → handoff note is the fallback. Backup fails → skip.
6. **Suggest, don't execute.** Doc drift → suggest updating specs or running `/brana:reconcile`. Let the user decide when.
7. **Be specific.** "The API was wrong" is useless. "Spec says `hooks recall`, actual is `memory search`" is useful.
8. **Ask for clarification when needed.** Ambiguous findings → ask. Don't guess classifications.
9. **Step registry.** Follow the [guided-execution protocol](../_shared/guided-execution.md). Register steps on entry, update as each completes.
10. **Phase files are the procedure.** Read the registered phase file at every step boundary (Phase Protocol above). Never run a step from this overview alone.

---

## Field Notes

### 2026-05-06: feedback-gate stops close mid-flow on Step 11 memory writes [→ t-1350]
Step 5b documents the sentinel (`touch /tmp/brana-close-active`) for feedback_*.md writes, but Step 11 memory-review writes hit the same gate without a wrapper. Every close that writes memory files in Step 11 stalls the agent loop. Sentinel touch/rm must wrap Step 11 memory writes too.
Source: close session 2026-05-06 / feedback-gate sentinel gap

### 2026-06-02: memory-write-gate uses a different sentinel than feedback-gate [→ t-1132]
`feedback-gate.sh` checks `/tmp/brana-close-active`. `memory-write-gate.sh` checks `/tmp/brana-memory-write-active`. Close Steps 5b and 11 only set `brana-close-active` — `memory-write-gate.sh` always fired and stopped every typed memory write. Fix: both sentinel touch/rm blocks in Steps 5b and 11 now set both sentinels. Any future gate that adds a new sentinel must also be added to these blocks.
Source: t-1132 2026-06-02

### 2026-05-19: Procedure decision points must never silently drop items
Any branch in a procedure that lets the user "skip" an action must still write a lower-priority `next[]` entry. "Skip" means "don't act now" — not "forget this forever." Four leakage points were found in close.md (Steps 3b, 4, 8, 12) where items were silently dropped. Rule: every decision branch preserves context in `next[]`; only the priority/category changes.
Source: close session 2026-05-19 / brainstorm session-continuity

### 2026-05-25: NANO mode + pre-errata dedup + MEMORY.md overflow guard
Three improvements from brainstorm session. (1) NANO mode: sessions with exactly 1 commit and ≤5 files that are all non-code skip Steps 3-8 entirely — the overhead cost exceeded the signal value for these tiny sessions. (2) Pre-errata dedup: `git show HEAD:errata-doc` before writing catches resume-after-compression duplicates (E2026-05-25-3 was committed in a prior session's close but the resumed session tried to write it again). (3) MEMORY.md overflow: if > 175 lines, auto-prune dead-link entries before the classification audit; report remaining count if still above cap.
Source: 2026-05-25 brainstorm + close procedure update

### 2026-05-19: brana session write is replace-not-merge — same-day parallel close loses data [→ t-1461]
`brana session write` always replaces `session-state.json` unconditionally. When two sessions close on the same project the same day, the second write erases the first's `accomplished`/`next`/`learnings`. The archive (`session-history.jsonl`) captures both, but nothing reads it for continuity. Fix: merge mode when `written_at` is today, replace mode for new days (t-1461).
Source: close session 2026-05-19 / brainstorm session-continuity

### 2026-06-03: `.claude/sessions/` handoff files must NOT be git-committed — they leak secrets
`handoff-2026-06-03.md` was committed in project `proyecto-anita` (commit `24d954a`) with `ANITA_ADMIN_SECRET` in plaintext. The same secret also leaked into `tasks.json` notes. Required: secret rotation + `git filter-repo` history scrub + force push.

**Rule — three parts:**

1. **Never `git add .claude/sessions/`** at session close. The project's `.gitignore` must include `.claude/sessions/`. If missing, add it before writing the handoff.
2. **Never write secret values into handoff files.** Reference where the secret lives (`.env.dev`, Secret Manager, Kapso dashboard) — never the value itself. If a secret value appears in conversation context, redact it before writing the handoff (`<redacted — see .env.dev>`).
3. **Check `.gitignore` before the close commit.** If `.claude/sessions/` is not in `.gitignore`, add it in a separate commit first, then write the handoff.

**Why this keeps happening:** The procedure says "Do NOT write to `session-handoff.md` (deprecated)" but said nothing about `.claude/sessions/handoff-*.md`. Gap closed by this field note. A future procedure update should add `.claude/sessions/` to the standard gitignore template for all projects.
Source: 2026-06-03 — proyecto-anita secret leak; history scrubbed same session

---

## Resume After Compression

If context was compressed and you've lost track of progress:

1. Call `TaskList` — find CC Tasks matching `/brana:close — {STEP}`
2. The `in_progress` task is your current step — resume from there
3. **Read the phase file that owns that step** (PHASES registry above) before executing anything — phase content loaded before compression is gone
4. Check git log and handoff file for what was already accomplished
