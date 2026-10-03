---
title: The Brana cockpit as a Claude Code mod
status: draft
created: 2026-10-03
epic: t-3422
tasks: [t-3422, t-3424, t-3425, t-3426, t-3427, t-3428, t-3429, t-3387, t-3430, t-3431, t-3432, t-3433, t-3434]
relates-to:
  - "[the-brana.md](../architecture/the-brana.md) §Gate — cockpit room (rubber-stamps → digest) vs studio"
  - "[statusline-pipeline-awareness.md](statusline-pipeline-awareness.md) — predecessor: two-tier display in the statusline"
  - "[mission-control-cli.md](../architecture/features/mission-control-cli.md) — shipped print-first `brana run/agents/queue`"
  - "[wave-board.md](../architecture/features/wave-board.md) — shipped L0 gauge `brana backlog wave board`"
  - "t-531 (Ratatui TUI) · t-532 (Axum web) · t-1423 (web UI + Kanban) — candidates to retire into this"
---
# The Brana cockpit as a Claude Code mod

> Brainstormed 2026-10-03. Status: draft — shaped, ready for backlog planning (epic `cockpit`).

## Seed

Claude Code mods (function-hook plugins, CC ≥ 2.1.287) can draw panes, bands and guards
*inside* the terminal session. The idea: the cockpit room that `the-brana.md` §Gate
describes — valves, gauges, digest — becomes a `/brana` pane the inhabitant keeps open,
rather than a set of CLI commands they remember to run. A backlog-board prototype
(`backlog-pane`, 16 tests) exists in session dev-mods; task t-3387 holds its promotion.

## Job to be done

When I sit down at a session (or return after an AFK wave), I want to see the state of
The Brana and act on what is waiting for me — without remembering which commands to run —
so I can stay the inhabitant at the gate instead of the operator typing queries.

- Functional: orientation + valve actions in one place.
- Emotional: calm, in control, nothing forgotten.
- Social: the system looks finished — a cockpit, not a pile of scripts.

## Decisions so far (EXPAND)

- Scope: it **is** the cockpit room — valves + gauges + digest. Board is one tab.
- Scale: significant investment (weeks+); retire t-531/t-532/t-1423 into it on evidence.
- Success in 30 days: no manual sitrep/ops status; valves answered inside CC; context-budget
  and git-discipline rules become UI (t-3333 closes as a mod); the pane stays open after week 2.
- Constraints (recommended, pending confirmation): reads only via `brana` CLI (gauge law, no
  shadow state); ruflo mods stay off (trust-gate caveat, memory `reference_claude-code-mods-ecosystem`);
  terminal + Desktop only, text fallbacks elsewhere; no daemon, no network.

## Risks

- **Retention (accepted bet, 2026-10-03):** t-531's gate ("only if CLI snapshots prove
  insufficient") never fired in 6 months — print-first commands never lost. If the pane is
  closed in most sessions by week 3, that is the signal. Kill switch: "pane open after week 2"
  metric. Survivable: band, guards and `/brana dump` keep paying without the pane.

## Decisions (DISCUSS)

- **Three tiers, two tracks in parallel (2026-10-03):**
  `tier 0` statusline (exists) · `tier 1` band above the prompt — always on, gauge + one action
  (context budget, git-discipline guard, resume card) · `tier 2` pane `/brana` — on open, lists
  and valves (Board · Wave/Orbit · Ops · Build · Valves). Track A = band + guards (days);
  track B = pane shell + gauge tabs (weeks). The band is the pane's doorbell
  (`⛔ 2 valves waiting · [open]`), so the pane's retention bet rides on a signal, not habit.
- **Valves read one queue, never raw sources.** The Valves tab renders
  `brana hands peek --room cockpit --json` (ADR-063 store, t-3021 — Accepted, unbuilt) and is
  `blocked_by: t-3021`. Until then it shows "valve store not built — t-3021". Rationale: a pane
  that aggregates orbit ledger + PRs + close-queue is the shadow queue ADR-002/065 forbid; with
  the store, a new valve source is a feeder row, the UI never changes. Perf: one ~40 ms read,
  snapshot in `$.state`, refresh on events (`session.start`, `turn.complete`, `r`) — no timers.
- Devil's-advocate outcome: "band + guards only" was rejected because a valve is a list with
  per-item decisions — a band structurally cannot hold it; dropping the pane drops the
  "valves answered inside CC" success criterion.
- **Hard constraint — no API usage (2026-10-03):** mods never call `$.model` (API-key billing)
  nor `$.http`. All content comes from `brana` CLI output and engine events; "Ask Claude"
  buttons only `$.prompt.fill` so the turn runs on the subscription. Enforced: CI greps
  `claude plugin validate` `calls:` lines for `$.model` / `$.http.fetch` and fails.
- **Pre-mortem (2026-10-03):** top risks (A) t-3021 valve store never lands → half a cockpit;
  mitigation: t-3021 becomes track C inside this epic, started week 1. (B) mods API churn per CC
  release; mitigation: pure logic outside `$` (model.ts pattern), `claude plugin validate/test`
  in validate.sh + CI, CC version pinned in CI matrix.

## Challenger review (2026-10-03, 3-lens quorum: convergent · systems · critical)

HIGH (≥2 lenses agreed) — all five accepted:

1. **Guard stays a shell hook.** Mods never load in `claude -p`, subagents or the Task tool —
   the callers that wiped the ledger (ADR-094). t-3333 ships as the PreToolUse deny hook; the
   mod only renders the guard's state in the band. "t-3333 closes as a mod" is dropped.
2. **t-3021 is linked, not absorbed.** It is blocked_by t-2834 and carries its own ADR-063 schema
   amendment; verbs disagree (`peek/pull/ack` vs `list/show/answer/cancel`) — the tab spec names
   the verb once t-3021 fixes it. Valves tab = stub until `brana hands peek --room cockpit` exists.
   Success criterion split: band + guards + Board/Ops independent; Valves scored from t-3021's landing.
3. **Kill metric is instrumented.** The pane appends one line per open/close to a log `brana ops`
   reads; decision at day 14. t-531 / t-532 / t-1423 are *not* retired — "re-evaluate at week 6".
4. **No-API rule enforced at the source, not the manifest.** validate.sh greps mod sources for
   `$.model` / `$.http` (needs no CC); one `run()` wrapper with an argv allowlist of read verbs and a
   must-fire deny test; prompt fills from fixed templates + task id only; never auto-submit.
5. **CI/maintenance made explicit.** ci.yml installs a pinned `claude` and runs
   `claude plugin validate` + `test` on ubuntu, failing loudly when absent (the exit-127 class);
   a scheduled drift job; a startup version probe that degrades to statusline-only with a visible
   line; pinned `tsc` dev dep; `$`-touching adapters ≤ ~100 lines per mod.

OBSERVATIONS promoted to spec decisions: deploy path = top-level `mods/` + marketplace entry
(not under `system/`, which bootstrap rsyncs with `--delete`); one `brana cockpit snapshot --json`
read verb with a shared TTL cache (band refreshes on `session.start` + `r` only; pane does full
queries on open); valve write path per class (reversible → direct `brana hands ack` + confirm;
irreversible merge/ship → `$.prompt.fill`, the permission layer stays the gate); **ADR + spec
scoped to tier 1**, the pane spec written after the day-14 signal. Deferred: `schema: N` on every
state atom + one `readValid` helper (into the spec's state section); 1-hour spike "can a mod read
context % at all" gates the context band.

## Shape (2026-10-03)

**Problem.** `the-brana.md` §Gate defines a cockpit room (valves · gauges · digest) with no
surface. Orientation and decisions live in a dozen CLI calls to remember; the five valves are
surfaced nowhere; context-budget and git-discipline rules exist only as prose.

**Solution.** Claude Code mods draw the cockpit inside the session in three tiers:
statusline (exists) → always-on band (gauge + one action; guards) → `/brana` pane with tabs
Board · Wave/Orbit · Ops · Build · Valves. Reads only via `brana` CLI; writes only by filling
existing verbs with confirm; Valves reads the single ADR-063 store; no `$.model`/`$.http`.

**Audience.** The inhabitant (one operator, thebrana + clients). **Scale.** Weeks+, tracks
A (band + guards) · B (pane shell + gauge tabs) · C (t-3021 store → Valves tab) in parallel.
**Success (30 d).** No manual sitrep/ops status · band + guards + Board/Ops tabs live · pane open in
most sessions after week 2, measured (else the pane tier is killed, band stays). Valves criterion
scored from t-3021's landing date, not from day 0.

### Key insights
- "Cockpit" is an existing room; this is its missing surface, not a new concept.
- `linear-mod`, ruv's `ruflo-console` (palette shows the exact command, then confirms) and
  Anthropic's `blast-radius` (hold a tool call, show consequences, Proceed/Cancel) validate the
  board→item→prompt and guard shapes.
- A `tool.call` hook can deny `git checkout` in the main checkout *with a UI* — t-3333 as a mod.
- A band cannot hold a valve queue (list + per-item decision) → the pane tier is forced by the
  "valves answered inside CC" criterion.
- ruflo ≥3.50 ships its own mods whose trust gate would block ours; keep them off.

### Engineering disciplines
- **DDR/ADR:** "Claude Code mods are The Brana's cockpit surface" — three tiers, gauge law
  (reads via CLI), no API, valves via ADR-063 store, ruflo mods off, CC version pinned in CI.
  Supersedes the t-531/t-532 direction; amends the-brana.md §Gate.
- **TDD:** per mod, pure modules under `claude plugin test`; guard tests (deny in main checkout,
  allow in worktree); band threshold tests (55/70/85); shell tab-registration tests;
  `validate.sh` runs `claude plugin validate` + `test` for every `system/mods/*`.
- **SDD:** feature spec `docs/architecture/features/brana-mods.md` (layout `system/mods/<name>/`,
  bootstrap deploy via local marketplace, CI step, no-API rule); amend `the-brana.md` §Gate;
  mark `statusline-pipeline-awareness.md` absorbed as tier 1.
- **Docs:** tech doc (above) · user guide `docs/guide/features/cockpit.md` (keys, subcommands,
  fallbacks) · `docs/reference/skills.md` + `docs/README.md` entries · philosophy.md only if
  "rules become UI" is stated as a system-level pattern.

### Second-order effects
- Band shows `⛔ N valves` every turn → valves answered sooner → **the runner's human valve
  stops being the bottleneck → orbit can be armed more often** (opportunity).
- Git guard denies `checkout` in the main checkout → Claude routes via `worktree add` →
  **more concurrent worktrees → lane pins / time brackets (ADR-069/083) see more concurrency**
  (risk, partly covered).
- Mods validated in CI with a pinned CC version → **every CC upgrade becomes a tracked event**,
  not silent drift — for the whole harness (opportunity).

### Next steps
1. Epic `cockpit` under in-002 cc-alignment; ADR + feature spec; re-parent t-3387.
2. Track A: band (guard state · valve doorbell · context gauge if the spike says readable); t-3333 ships as the shell hook it already is.
3. Track B: `/brana` shell + Board (exists) + Wave/Orbit + Ops tabs. Valves tab stub, blocked_by t-3021 (linked, not absorbed).

## Spike t-3426 — findings (2026-10-03)

**Q2 — deploy route: YES.** A second `plugins[]` entry in the repo's `.claude-plugin/marketplace.json`
(`"source": "./mods/<name>"`) installs in a clean `HOME` with `claude plugin marketplace add <repo>`
+ `claude plugin install <name>@brana --scope user`; `enabledPlugins` and the plugin cache are
written by the CLI, and a `claude -p` turn ran the mod's `session.start` hook (marker file written).
Consequences for t-3425: (a) mods live at top-level `mods/<name>/`, never under `system/`
(bootstrap's `--sync-plugin` rsyncs `system/` only, with `--delete`); (b) bootstrap gains one
step per mod: `claude plugin install <name>@brana --scope user` (idempotent) — no rsync;
(c) the live brana marketplace is registered from GitHub (`extraKnownMarketplaces.brana.source
= github:martineserios/thebrana`), so a mod ships when `main` moves, same as the plugin.

**Correction to the challenger review:** mod hooks DO run under `claude -p` (verified: the
no-op mod's `session.start` fired headless; docs: hooks run in every session kind, only
drawing is terminal/Desktop). "Guard stays a shell hook" (t-3333) still stands — on fail-open
semantics, bypass forms (`git -C`, aliases, `switch`, `restore`), the user's own terminal and
"no fourth enforcement point" — but NOT on the premise that mods never load headless.
`e.agentId` on `turn.step` suggests subagent calls are visible to mods too (unverified).

**Q1 — context %: YES (live-verified).** `session.measure` fires after each main-thread turn
with `context: { tokens, window, percent }` (probe: `tokens 15884, window 1000000, percent 2` —
the same window the status line uses), plus `rateLimits: [{ kind: five_hour|seven_day,
percentUsed, resetsAt }]` and `cost: { usd }`; `changed[]` names which moved. `$.session.usage()`
returns the identical shape on demand (free; `"full"` adds the `/context` breakdown); at
`session.start` only `window` is known. **Decision: the context band is IN (t-3429).** Gauge law:
the band reads `e.context.percent` as pushed — never recomputes — so it cannot drift from the
status line's number. **Bonus:** the subscription 5-hour / 7-day windows are exposed — the band
should carry them (`5h 23% · 7d 20%`); for a subscription-only operator that is the scarcer
resource. Probe ran headless (`claude -p --plugin-dir ctx-probe`); the same module hot-loaded
into the interactive session wrote nothing and raised no error — new-folder hot-load in
dev-mods is unconfirmed; `--plugin-dir` and marketplace install are the proven routes.
