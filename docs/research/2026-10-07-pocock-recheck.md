---
title: Pocock quarterly recheck — skills v1.3 (implement-spec, pr, retro), GLOSSARY rename, scope records
status: draft
created: 2026-10-07
related: docs/research/2026-09-02-pocock-sandcastle-video-findings.md, docs/research/2026-08-22-pocock-alignment-decision-matrix.md, docs/research/2026-08-18-pocock-methodology-synthesis.md, docs/architecture/decisions/ADR-084-upstream-skill-band-vendored-pocock-skills.md, docs/agents/issue-tracker.md, t-3263
---

# Pocock quarterly recheck — skills v1.3, GLOSSARY rename, scope records

**Date:** 2026-10-07 | **Scope:** everything Matt Pocock shipped on his live sources since the
2026-09-02 pass — the YouTube channel and the `mattpocock/skills` repo. Sandcastle was not
re-read (no signal it moved; his own v1.3 content supersedes it, see §2.1).

**Method:** first *systematic* channel pass. The 2026-09-02 doc was search-driven and
explicitly flagged "a systematic channel pass ... would be worth doing once." This pass
enumerated the channel's latest 40 uploads with `yt-dlp --flat-playlist`, dated the top 22,
and read the auto-generated transcript of the only upload newer than 2026-09-02. Repo state
came from `gh release list`, the commit log since 2026-09-02, and direct reads of the new
`SKILL.md` files, `SCOPE.md`, and `.out-of-scope/`. Every mechanism below was placed on a
brana ring (§0 of the decision matrix) before being compared.

---

## 1. Coverage — what moved, and what didn't

| Source | Since 2026-09-02 | Note |
|---|---|---|
| Channel | **1 upload**: "New Skills! v1.3 brings /pr, /implement-spec, and /retro" — `BsJGo1wFTvQ`, 2026-10-05, 14m34s | Transcript read in full |
| Repo releases | **v1.3.0 + v1.3.1**, both 2026-10-04 | v1.3.0 release was cut by an agent without asking; he reports this in the video as a `retro` finding |
| Repo commits | ~60 commits 2026-09-24 → 2026-10-07 | Graduations, GLOSSARY rename, SCOPE.md, issue-triage workflows, two experimental skills, a `diagnosing-bugs` change |

**Closed gap from the prior pass.** The channel's July–August uploads (v1.1 on 2026-07-08,
"complete workflow" 2026-07-16, `/prototype` 2026-07-23, `/wayfinder` 2026-07-30, v1.2 on
2026-08-05) predate 2026-09-02 and were never transcript-read, but the 2026-08-13 and
2026-08-18 docs covered the same content from the repo at those versions. Nothing there is
unaccounted for. Channel enumeration method is now recorded in memory
(`reference_pocock-live-sources`) so the next recheck is a five-minute job.

---

## 2. Findings

### 2.1 [NEW] `implement-spec` — his AFK orchestrator moved *inside* the harness — HIGH

**What it is.** User-invoked. Reads a spec plus its tickets as a **task graph** ("not a list of
steps ... there is always a **frontier** of tickets which are ready to be grabbed"), creates an
**integration branch**, runs **implementer subagents** each in its own worktree via `tdd`,
merges each finished one onto the integration branch with a **merger subagent**, re-scans the
frontier and fires more implementers, closes with `code-review` on the integration branch, and
only then opens (or marks ready) one PR. Communication to subagents is "sparse ... primarily
through **context pointers**." Optional exploration subagent writes notes *outside the repo* so
implementers never explore.

**His own ranking, verbatim from the video.** Three ways to run the ticket loop: the manual
loop ("you're acting like a for loop ... not really workable"), the **deterministic loop** (a
script that reads tickets and runs `implement` — "this is how I recommend most people do this
... reliable and cheap"), and `implement-spec` ("an agent does the babysitting instead of a
human ... worse than doing a deterministic loop ... but a good way to get started with AFK
workflows"). It became possible because "sub agents can themselves spawn sub agents."

**Ring placement (matrix §0).** Beat ring. This is Sandcastle's four-role pipeline
(planner/implementer/reviewer/merger, 2026-09-02 doc §3a) collapsed into one Claude Code
session with no external process. It still has **no Epic ring**: nothing is persisted between
invocations, there is no wave, no contract, no gate, no lease — the orchestrator holds every
claim in its own context. It *feeds* brana's human-merge valve (one PR at the end) and tries
to remove nothing.

**What it changes for the decision matrix.**

| Row | Prior verdict | Effect |
|---|---|---|
| 1 — Loop runtime | KEEP brana | **No flip.** He still ranks the deterministic script above `implement-spec` and positions the skill as the beginner on-ramp. brana's runner *is* his "deterministic loop," already built. |
| 2 — Wave-level parallelism | ADOPT | **Strengthened.** His orchestrator is frontier-driven concurrency with a merger step and an integration branch — the concrete shape t-2889-style work can cite. |
| 6 — Leases | KEEP brana | **Confirmed by absence.** He needs no lease because one orchestrator owns every claim in memory. brana's lease exists only because several sessions pull from one persisted queue — a difference to keep (matrix §0 question 3). |
| 10 — `blocked_by` in frontier | ADOPT | **Confirmed again.** "Task graph with blocking relationships" is now the skill's first stated premise. |

**Net-new detail worth copying, independent of ring:** each implementer "merges the
integration branch tip into its own branch before reporting done, so each merge is a
fast-forward." brana's epic-drain / runner merge step does not state this invariant.

### 2.2 [NEW] `pr` — a PR body shape, model-invoked — MEDIUM

**What it is.** Three sections: **Summary** as "the smallest visual that makes the key point
clear" (pseudocode, call tree, component tree, shallow file tree, Mermaid, or a *diff of one of
those*); **Evidence** as before/after ("screenshots are S-tier ... execution-based evidence is
A-tier"); **Merge Danger** as **one-way vs two-way door** plus **blast radius**. Credited to
Dex Horthy's `show-me` (HumanLayer). Reads `GLOSSARY.md` for vocabulary. He reports it as "one of
the most consistently invoked model-invoked skills ... at least on Opus 5.5" and "PRs are still
the main bottleneck for work getting to main."

**Why he built it:** "without asking for hard evidence it's very easy for agents to say 'yeah
that probably works cuz I've read the code' ... verification is something I'm beginning to be
really obsessed with."

**Ring placement.** Beat ring, at the human-merge valve. Feeds a valve brana already has.

**brana today.** `/brana:ship` opens the dev→main PR with `--body "$(git log --oneline
main..dev | head -40)"` (`system/skills/ship/SKILL.md:193-195`). Feature-branch PRs have no
body convention at all. `brana:pr-reviewer` reviews diffs but is not handed a merge-danger
call. This is the cheapest adoptable item in the batch: a body template is ~40 lines of prose
and touches no state.

### 2.3 [NEW] `retro` — environment retrospective from real session logs — MEDIUM

**What it is.** User-invoked. Reads "the primary sources for the session the user specifies ...
searching through session logs on this machine," then looks for improvements in seven
categories: **navigation** (would a navigation pointer have saved the search?), **automated
checks** (a check that exists but is unwired is the finding; "a repo with no guardrail ... is
itself a finding"), **coding standards** (classify first: a **mechanical** violation "gets a
deterministic check, full stop ... Default to building the check over writing the rule";
`CODING_STANDARDS.md` only for judgement calls), **global AGENTS.md** size, **tool economy**
(token-inefficient CLIs/MCPs), **no-ops** in steering files, **information access** (dev-server
logs, read-only third-party access). Presents candidates by severity; human decides.

**His operating rule, verbatim:** "Pretty much everyone when I show them this, they go 'ooo I'd
love to automate this.' No, you don't want to automate this. Automating this means the agent
will get itself into a loop where it continually finds false positives." Run it "on a sampling
of your agent sessions ... a session that has gone wrong." He placed it as the last step of his
main flow, after `code-review`.

**Ring placement.** Knowledge ring. It does not touch the Beat (no code changes) and persists
nothing itself — it emits proposals.

**brana today.** `/brana:retrospective` classifies a *learning the operator already has* and
routes it to a destination (rule / ADR / pattern / knowledge / reference). `/brana:close`'s
EXTRACT step reflects on the just-finished session from the model's own memory of it. Neither
reads session logs, and neither is pointed at the *environment* (hooks, rules, CLAUDE.md
weight, tool cost) as the subject. The seven categories are a lens brana lacks. His
mechanical-vs-judgement rule is the same split brana already codified in memory as
`pattern_split-enforcement-by-what-it-needs` — independent convergence, cite it.

### 2.4 [VERSION] `CONTEXT.md` → `GLOSSARY.md` everywhere — LOW impact, mechanical

Renamed in `domain-modeling`, `grill-with-docs`, `improve-codebase-architecture`,
`setup-matt-pocock-skills`, `triage`, `tdd`, `diagnosing-bugs`, `ask-matt`, `codebase-design`,
`wait-what`, `pr`. His reason (video): "Context.md just felt way too vague. It didn't trigger
the agent to pull it in at the right moment ... I also ended up reducing the amount of stuff
in context.md until it was literally just a glossary." `GLOSSARY-MAP.md` indexes multiple
bounded contexts. `domain-modeling` now also triggers on writing or editing an ADR directly.

**Affects:** t-3013's subject/AC wording ("CONTEXT.md-style glossary-building discipline");
ADR-084 §3's CONTEXT.md assumption; the 2026-08-13 doc's `grill-with-docs` row;
`docs/ideas/the-brana-guide.md` references. All textual. brana's own `docs/domain/glossary.md`
convention was already the glossary-shaped version of this.

### 2.5 [NEW] `SCOPE.md` + `.out-of-scope/` — his boundaries, now written down — MEDIUM

Added 2026-10-06. The bar: an issue stays open only with an **observed failure** in a real
session *and* fit with the philosophy; "config options, harness-specific branches, or a tweak
to suit one person's workflow" belong in your own `CLAUDE.md` or a fork. Three records matter
to brana:

- **`mainstream-issue-trackers-only.md`** — first-class backends are GitHub, GitLab, local
  markdown, *forever*: "Every other tracker goes through the **Other** option ... you describe
  your workflow in a paragraph and the skill records it as prose in `docs/agents/issue-tracker.md`.
  That file is yours." This is exactly brana's adapter (t-3163, live). It confirms the August
  session's Level 1 choice (idea #4/#6) and permanently closes Level 2 on *his* side — there
  will never be a tracker-agnostic backend to plug into, so brana's prose adapter is the
  sanctioned path, not a workaround.
- **`subagent-recursion.md`** — "The harness should be responsible for stopping infinite
  subagent loops, not skills ... A guard written into one skill's prose covers only that skill,
  costs tokens on every run, and still depends on the model choosing to obey it." Same
  position brana's hooks/manifests take (ADR-062 runner manifest, deny hooks). Cite when a
  skill PR proposes an in-prose guard.
- **`new-skills.md`** — proposals and contributions closed; "if you can compose the behaviour
  from existing skills, it doesn't get a new skill." Consequence for ADR-084: there is no
  upstream contribution path, so **vendoring is the only relationship**. The ADR already
  assumes this; now it is stated by him.

### 2.6 [VERSION] `diagnosing-bugs` drifted past the vendored pin — LOW now, compounding

brana's pilot adapter `system/skills/diagnose-hard-bug/SKILL.md` pins `vendored_from:
mattpocock/skills@v1.2.3`. Upstream is v1.3.1, and the skill changed twice since the pin:

1. 2026-08-15 — reads `GLOSSARY.md`, not `CONTEXT.md` (§2.4).
2. 2026-10-07, PR #1209 — step "Watch it fail" gains: "If you forced the red by mutating code
   or a fixture, `diff` against a pristine copy to prove the mutation landed before you trust
   it." Same class as brana's memory `pattern_detector-needs-a-must-fire-test`.

Neither is behavioural for the adapter yet, but this is the first measured drift on the pilot
band and the kind ADR-084 said the pin exists to make visible.

### 2.7 [WATCH] Two experimental skills in `in-progress/` — not graduated

- **`chief-of-staff`** (2026-10-05): "Pursue a long-running goal in a single session by
  co-ordinating subagents." Two simultaneous tracks — *tactical* (complete the task) and
  *strategic* ("modify the environment to improve the outcomes of the **next** task"). All work
  in background subagents; suggest recurring schedules "harness-permitting"; agents thrive in
  the **pit of success** (constrained APIs, lint rules that force correctness,
  `CODING_STANDARDS.md`); a **"no workarounds"** rule. Ring: this is his first object that
  *accrues* across tasks ("accruing tribal knowledge"), i.e. an Epic-ring intent — but it still
  lives in one session's context, so it is ephemeral by construction. brana's epic node + wave +
  memory already persist what this skill tries to hold in-context.
- **`loop-me`** (older, still in-progress): a `grilling` session whose only output is
  workflow specs. Vocabulary: **trigger** (event or schedule), **checkpoint** (human-in-the-loop
  point), **push right** ("defer the checkpoint as far as it will go ... so they are asked
  once, late, with everything prepared"), **brief** ("a tight, decision-ready summary ... never
  the raw output. The user reads a brief, not a draft"). "Mandate nothing structural." This
  overlaps brana's loop-first epic (t-2820) and `docs/ideas/skills-loops-graphs.md` (which
  already cites loop-me). "Push right" and "brief" are the two nameable concepts: brana's
  valve ≈ his checkpoint, brana's digest ≈ his brief. Worth citing in cockpit/valve docs; not
  worth building against until it graduates.

### 2.8 [CONFIRMS] Smaller items — LOW

- `resolving-merge-conflicts` removed: "the agent works through an in-progress merge or rebase
  conflict without a dedicated skill." Nothing in brana depended on it.
- Cross-skill invocation convention hardened: skills say `Call the Skill tool with "x"`
  (bare `/x` prose "does not reliably cause it to load"), and user-invoked skills may never be
  called by other skills — a one-way dependency rule. brana's skills already invoke via the
  Skill tool; the user-invoked-is-a-leaf rule is a useful lint idea for `validate.sh`.
- Issue-triage GitHub Actions and issue forms added; `needs-info` auto-closes after 14 days.
- His own `retro` run (video) found: the agent cut the v1.3.0 release without asking (an
  irreversible public action), the repo had a check script nothing ran, context loss across
  compactions, and two token-wasting custom CLIs. "Retro is merciless."

---

## 3. What this changes for brana

Applying the ring-fit filter (matrix §0) to the batch: everything he shipped is Beat-ring or
Knowledge-ring. Nothing new on the Epic ring; `chief-of-staff` gestures at it without
persistence. No KEEP verdict in the 2026-08-22 matrix flips. Two ADOPT rows (2, 10) gain
concrete upstream shapes to cite.

Follow-ups surfaced (none created here — see t-3263 notes for the decision):

| # | Follow-up | Size | Ring / valve | Why now |
|---|---|---|---|---|
| F1 | Bump `diagnose-hard-bug` pin to v1.3.1; verify the GLOSSARY read and #1209 step land through the adapter | S | Beat | First measured drift on the ADR-084 pilot band (§2.6) |
| F2 | PR-body template (summary visual · before/after evidence · door + blast radius) for `/brana:ship` and feature-branch PRs; hand Merge Danger to `pr-reviewer` | S | Beat / human-merge valve | Cheapest adopt; brana's PR body is a `git log` today (§2.2) |
| F3 | Decide whether `retro`'s seven-category environment lens becomes a step in `/brana:close` EXTRACT, a quarterly run like `verify-docs`, or stays out | S (decision) | Knowledge | brana has no session-log reader and no environment-as-subject retrospective (§2.3); his do-not-automate rule must travel with it |
| F4 | Reword t-3013 and the ADR-084 §3 assumption from CONTEXT.md to GLOSSARY.md | XS | — | Mechanical (§2.4) |
| F5 | Add "merge integration tip into own branch before reporting done → every merge fast-forwards" to the runner/epic-drain merge contract | XS | Beat | Named invariant brana's docs lack (§2.1) |
| F6 | Next quarterly instance of this recheck, due ~2027-01 | XS | — | Task's own cadence |

### 3a. Diagrams — his v1.3 harness, and where it sits on brana's rings

**His main flow, with the new skills in place.** One dev, one repo, one session. The ticket
loop in the middle is the only place he offers alternatives, and he ranks them himself.

```
Pocock skills v1.3 — main flow

  grill-* ──→ to-spec ──→ to-tickets ──→ [ticket loop] ──→ pr ──→ retro
  (shape)     (spec)      (task graph)        │          (body)   (env)
                                              │
     ┌────────────────────────────────────────┴───────────────────────┐
     │ three ways to run the ticket loop (his ranking, 2026-10-05)     │
     │                                                                 │
     │  1  deterministic script      "reliable and cheap" — recommended│
     │     read ticket → implement → next                              │
     │  2  implement-spec  (NEW)     "worse than 1, but the on-ramp    │
     │     an agent babysits the loop  to AFK workflows"               │
     │  3  manual                    "you are acting like a for loop"  │
     └─────────────────────────────────────────────────────────────────┘
```

**Inside `implement-spec`.** Everything lives in one orchestrator context; the parallelism is
real, the state is not.

```
implement-spec — one orchestrator session

  ┌──────────────── orchestrator agent ─────────────────────────────┐
  │ 1  read spec + tickets ──→ task graph (blocking edges)          │
  │ 2  (opt) exploration subagent ⇢ notes saved OUTSIDE the repo    │
  │ 3  create integration branch                                    │
  │                                                                 │
  │        frontier = tickets with no open blockers                 │
  │        ┌────────────┐ ┌────────────┐ ┌────────────┐             │
  │ 4      │ implementer│ │ implementer│ │ implementer│  own        │
  │        │  tdd       │ │  tdd       │ │  tdd       │  worktree,  │
  │        │  merge int.│ │  merge int.│ │  merge int.│  background │
  │        │  tip → ff  │ │  tip → ff  │ │  tip → ff  │             │
  │        └─────┬──────┘ └─────┬──────┘ └─────┬──────┘             │
  │              └──────────────┼──────────────┘                    │
  │ 5                    merger subagent → integration branch       │
  │ 6      frontier changed? ──yes──→ back to 4                     │
  │ 7      code-review on integration branch → fix in 1 implementer │
  │ 8      one PR (draft → ready)        9  clean up worktrees      │
  └─────────────────────────────────────────────────────────────────┘
     when the session ends nothing remains: no wave, no contract,
     no gate, no lease, no beat record — the next run starts cold
```

**Ring overlay.** Same four rings as the-brana guide §L3.1; his objects placed by what they
persist and who they answer to, not by step count.

```
ring        brana (persisted)                  Pocock v1.3                 fit
──────────  ─────────────────────────────────  ──────────────────────────  ─────
knowledge   memory · ADRs · /retrospective ·   retro — proposals only,     ◐ lens
            /close EXTRACT                     human applies, never auto     to add
epic        epic node · wave (contract, gate,  — none. chief-of-staff       ✗ no
            wip) · wave-ship valve             gestures at it, in-context     peer
beat        runner pull (lease) · build loop · implement-spec orchestrator  ◐ same
            merge valve · beat record          · integration branch · pr      shape,
                                                                              no state
micro       TDD red-green, no human            tdd · diagnosing-bugs        ✓ vendored

legend   ✓ fits as-is    ◐ fits after placement    ✗ no counterpart on his side
```

**The seams.** Matrix §0 question 2: does it feed one of our valves, or try to remove one?

```
                 FEEDS a brana valve               REMOVES / LACKS
                 (adopt near-automatically)        (keep ours; decide explicitly)
───────────────  ────────────────────────────────  ─────────────────────────────────
implement-spec   frontier = unblocked tickets      claims held in-context → no lease
                 worktree per ticket               no persisted wave / contract / gate
                 "merge int. tip → ff" invariant   orchestrator dies with the session
                 one PR → human merge valve        his own verdict: worse than a script
pr               human merge valve (the body)      —
retro            knowledge ring (proposals)        must stay human-in-the-loop
chief-of-staff   strategic track ≈ our epic node   one session, nothing persisted
```

Reading the two columns together: the left column is what brana's runner and build loop can
cite as upstream confirmation; the right column is the list of questions his scope never has
to answer, which is where brana's persisted substrate earns its weight.

---

## 4. Sources

- Video — [New Skills! v1.3 brings /pr, /implement-spec, and /retro](https://www.youtube.com/watch?v=BsJGo1wFTvQ) (2026-10-05, 14m34s; auto-transcript)
- Releases — [v1.3.0](https://github.com/mattpocock/skills/releases/tag/v1.3.0), [v1.3.1](https://github.com/mattpocock/skills/releases/tag/v1.3.1) (2026-10-04)
- Skills — `skills/engineering/{implement-spec,pr,retro}/SKILL.md`, `skills/in-progress/{chief-of-staff,loop-me}/SKILL.md` at `main` 2026-10-07
- Scope — `SCOPE.md`, `.out-of-scope/{mainstream-issue-trackers-only,subagent-recursion,new-skills}.md`
- `diagnosing-bugs` — PR #1209 (2026-10-07), rename commit d80fa0f4 (2026-08-15)
- Channel enumeration — `yt-dlp --flat-playlist --print "%(id)s|%(title)s" https://www.youtube.com/@mattpocockuk/videos`, then `--print "%(upload_date)s"` per id

---

## 5. Next recheck

Due ~2027-01-07 (quarterly, t-3263 cadence). Watch specifically: whether `chief-of-staff` or
`loop-me` graduate (first Epic-ring object on his side), whether `implement-spec` grows any
persistence between runs, and whether `retro` gets an automated mode despite his stated rule.
