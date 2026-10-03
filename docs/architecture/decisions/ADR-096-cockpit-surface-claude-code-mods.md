---
status: accepted
extends: docs/architecture/decisions/ADR-063-pending-questions-store.md
respects: docs/architecture/decisions/ADR-094-tasks-json-ledger-in-git-common-dir.md
informs: docs/architecture/the-brana.md
---

# ADR-096: The Brana's cockpit surface is Claude Code mods, under six laws

**Status:** Accepted (2026-10-03 by Martín Rios) — brainstorm 3-lens quorum on the idea doc, spike t-3426 evidence, one context-isolated challenger pass on the ADR (PROCEED WITH CHANGES, 7 findings applied); kill threshold 50 % confirmed by the decider
**Date:** 2026-10-03
**Deciders:** Martín Rios
**Tags:** cockpit, mods, gate, gauge, harness, cc-alignment
**Tasks:** t-3424 (this ADR) · epic t-3422 `cockpit` · spec t-3425 · spike t-3426 (evidence) · band t-3429 · pane shell t-3387 · CI t-3427 · snapshot verb t-3428 · instrumentation t-3432
**Extends:** [ADR-063](ADR-063-pending-questions-store.md) (the one queue the Valves tab reads; `room ∈ cockpit | studio`)
**Respects:** [ADR-094](ADR-094-tasks-json-ledger-in-git-common-dir.md) (the shared main checkout stays on `dev`; safety mechanisms are not removed before their replacement lands)
**Informs:** [the-brana.md](../the-brana.md) §Gate (the cockpit room gains a surface; valve classes and verbs stay owned by L4.4)
**Evidence:** [ideas/brana-cockpit-mod.md](../../ideas/brana-cockpit-mod.md) — brainstorm, 3-lens challenger review, spike t-3426 findings · memory `reference_claude-code-mods-ecosystem` (Anthropic samples, ruv's field guide + ruflo/RuView mods, the ruflo-mods trust-gate caveat) · memory `pattern_cc-mods-authoring-gotchas`

---

## Context

[the-brana.md](../the-brana.md) §Gate defines two rooms for the inhabitant: the **studio** (needs thinking → agenda) and the **cockpit** (rubber-stamps → digest). It names five human valves (AC approve · wave ship · merge → dev · ship → main · re-arm runner), classifies each by reversibility (L4.4), and records that "all five are cockpit items and four are surfaced nowhere". Orientation today is a dozen CLI calls to remember (`sitrep`, `ops status`, `wave board`, `orbit status`, `remind due`); the context-budget and git-discipline rules exist only as prose; the statusline is the only always-on readout and it carries session-local numbers alone ([ideas/statusline-pipeline-awareness.md](../../ideas/statusline-pipeline-awareness.md) designed a two-tier successor that never shipped).

Three earlier answers to "give the cockpit a screen" are parked: t-531 (Ratatui TUI, gated on "only if CLI snapshots prove insufficient" — a gate with no threshold and no owner, which is why it never fired in six months), t-532 (Axum web dashboard) and t-1423 (web UI + Kanban). All three stand *outside* the session the inhabitant is already in.

Claude Code ≥ 2.1.287 ships **mods**: plugins whose hooks module registers functions the engine calls on its own events — a tool call, a submitted prompt, a part of the interface being drawn — and which can draw a pane beside the transcript, a band above the prompt, buttons and text fields, inside the running session. Verified in this repo (spike t-3426, 2026-10-03):

- `session.measure` pushes `context: { tokens, window, percent }` after every main-thread turn — the same window the statusline uses — plus `rateLimits: [{ kind: five_hour | seven_day, percentUsed, resetsAt }]` and `cost: { usd }`; `$.session.usage()` returns the same shape on demand.
- A second `plugins[]` entry in the repo's `.claude-plugin/marketplace.json` (`source: "./mods/<name>"`) installs in a clean `HOME` via `claude plugin install <name>@brana --scope user`; a `claude -p` turn then runs the mod's hooks headless. Only *drawing* is limited to the terminal and the Desktop app.
- A pane docks beside the transcript only under the fullscreen layout (`/tui fullscreen`); on the main screen it seats inline above the prompt.
- Persisted `$.state` outlives hot-reloads and schema changes: a renderer that read a stale shape threw, and a thrown render hook draws nothing (one dim transcript line is the only trace).

A prototype (`backlog-pane`: `/board`, three columns, task detail, Start/Ask buttons that fill the prompt, 16 tests under `claude plugin test`) exists in the session's dev-mods folder. The brainstorm that shaped this decision ran a 3-lens challenger quorum (convergent · systems · critical); five findings had ≥ 2 lenses agreeing and all five are folded into the laws below. One premise of that review — "mods never load for `claude -p`" — was later disproved by the spike; the conclusions it supported survive on other grounds and are restated accordingly.

### Forces

- **The room exists, the surface doesn't.** The valve inventory and the gauge/pump/valve vocabulary are decided; what is missing is a place the inhabitant *stands*. The surface must be the architecture's, not a parallel dashboard with its own notion of state.
- **One source of truth.** `tasks.json` is a ledger in `$GIT_COMMON_DIR/brana/` (ADR-094) read and written only through `brana`; any UI that reads it directly, or aggregates valve sources itself, becomes the shadow store ADR-002/065 forbid.
- **Subscription-only operation.** The brana compute model runs on the subscription; a mod's own model or HTTP calls are a second, unbudgeted spend channel (whether `$.model` bills the API key or the plan is an open question below — the law does not depend on the answer). A cockpit that quietly spends is worse than none.
- **Mods are not a safety layer.** A mod hook can time out, fail to load, be blocked by another mod's `plugin.register` trust gate, or break on a Claude Code upgrade; string-matching `git checkout` is sidestepped by `git -C`, aliases, `switch`, `restore`. The ADR-094 harm class (clobbering the shared checkout) needs the enforcement point with the fewest such failure modes.
- **The retention bet.** The print-first CLI never lost to a dashboard here, and the last gate on a dashboard (t-531) had no threshold and no owner. A pane that nobody opens is a weekly maintenance tax with no return; the decision must carry a pre-registered, owned kill switch.
- **API churn.** The mods API is new (types regenerate per CC build); an auto-updated CC can break a live mod before CI notices.

## Decision

The Brana's cockpit room gets its surface as **Claude Code mods**, and every cockpit mod obeys six laws. The laws are the decision; tabs, layouts, keymaps, cache design, file trees and helper names are implementation detail owned by the feature spec (t-3425) and may change without amending this ADR.

### Law 1 — Three tiers; tier 1 and a Board-only pane ship together; everything beyond is earned

```
tier 0   statusline        · always on · numbers only                      (exists: statusline.sh)
tier 1   band              · always on · context % · 5h/7d quota · guard state   (ships first, days)
tier 2a  pane /brana       · on open   · Board tab only, instrumented        (ships with tier 1)
tier 2b  further tabs      · on open   · Wave/Orbit · Ops · Build · Valves    (only after the signal)
```

Tier 1 draws what exists today — context fill and the 5-hour / 7-day quota from `session.measure`, and the state of the checkout guard (Law 4). A valve doorbell joins the band when, and only when, the Valves source exists (Law 5). Tier 2a exists to *measure*: the pane appends one line per open and close through the Law-3 write allowlist, and `brana ops` reads it. The keep/kill rule is pre-registered here, not decided later:

> **Keep tier 2b if the pane was opened in ≥ 50 % of sessions during days 8–14 after tier 1 + 2a ship; otherwise kill 2b and keep tiers 0–2a or 0–1.** Owner: a `brana remind` entry created by t-3432 together with the instrumentation, due on day 14, naming this rule. The week-6 re-evaluation of t-531 / t-532 / t-1423 reads the same log through the same owner mechanism. **Valves are scored separately: 14 days after t-3021 lands, on whether the Valves tab is used, not on day 14 of the pane.**

The pane's own spec (tabs beyond Board) is written *after* the day-14 signal; this ADR and the tier-1/2a spec (t-3425) do not design it.

### Law 2 — Gauge law: mods read and render; their only writes are Law 3's enumerated write verbs

A mod obtains every number it shows from exactly two sources: a `brana` read verb from the enumerated read allowlist, or an engine event payload (`session.measure`, `turn.complete`, …). It never reads `tasks.json` or any file under `$GIT_COMMON_DIR/brana/`, never aggregates raw sources (orbit ledger, `gh pr`, close-queue) into a value of its own, and never recomputes a figure the engine already pushed — the context gauge draws `e.context.percent` as given, so it cannot drift from the statusline's number. Git facts (branch, worktree count) arrive inside the snapshot verb, not from a mod running `git`. `$.state` is a cache only: versioned, validated on read, discarded and reloaded on any mismatch; no decision or in-flight action is ever persisted there (mechanics in t-3425). Cross-session fan-out is bounded by one read verb, `brana cockpit snapshot --json` (t-3428), served from a shared cache; the band refreshes on `session.start`, `turn.complete` and an explicit `r`, never on a timer, so a valve raised mid-session rings on the next turn. Enforcement: `validate.sh` greps `mods/*` sources for `tasks.json` and for any file read outside the adapter module, with a must-fire fixture.

### Law 3 — No API-billed calls; two allowlists, enforced at the source

A cockpit mod never calls `$.model` or `$.http`, and never reaches a model or the network by any other path. Enforcement is static and needs no Claude Code binary (`validate.sh`, t-3427): the grep covers the nouns, their destructured forms (`const { http } = $`, `$['model']`), global `fetch`, `child_process`, and any `process.run` outside the one adapter file — each with a must-fire fixture. All process execution goes through one `run()` wrapper that checks argv against **two enumerated lists kept in one file** (`mods/_shared/allowlist.ts`, owned by t-3425):

- **Read allowlist** — the `brana` read verbs the cockpit draws from (`cockpit snapshot`, `backlog get|query|next|search|blocked`, `ops status|health`, `orbit status`, `backlog wave board`, and the Valves verb once t-3021 names it). `brana recall`, `brana memory`, `agy`, `curl`, `claude` and `git` are **not** on it.
- **Write allowlist** — every verb that changes anything, each behind a confirm button, each logged: `brana cockpit log-event` (the Law-1 open/close line) and the valve verbs Law 5 permits. Anything not listed is denied, with a denied-argv test.

Buttons that involve the model only `$.prompt.fill` from fixed templates plus a task id matching `^t-\d+$` (unit-tested) — never free text from task fields, never auto-submit; the turn then runs on the subscription and the inhabitant presses Enter.

### Law 4 — Safety stays in shell hooks; mods render, never enforce

Anything that *prevents* harm — the ADR-094 checkout deny (t-3333), commits on `main`, force-push, `rm -rf` holds — lives in a PreToolUse shell hook. A mod may show that hook's state in the band and explain a denial; it never carries the deny itself.

Rationale, stated without overclaiming: a shell hook runs for every Bash caller in every session kind and is one thing to test; a mod hook is additionally exposed to the trust-gate and version-drift failure modes (Forces) and is the newer, less understood mechanism. Neither layer protects the inhabitant's own terminal, and no layer is claimed to survive `disableAllHooks` or `--safe-mode` — those stop settings hooks too (ADR-094 D5 already notes that humans in a terminal are covered only by D1 and D6). The three enforcement points that exist or are decided are: the PreToolUse deny (t-3333), the `post-checkout` / `post-merge` restore (ADR-094 D6) and the per-write ledger backups (ADR-094 D4); this ADR adds no fourth (memory: `pattern_enforcement-systems-overbuild-then-revert`). **Acceptance condition carried to t-3333:** its tests must cover the `git -C <path>`, `git switch` and `git restore` forms, since ADR-094 D5 denies on "cwd resolves to the main checkout" and `-C` sidesteps cwd.

### Law 5 — Valves read one queue; classification and verbs belong to L4.4

The Valves tab renders ADR-063's `pending-questions.json` filtered to `room: cockpit`, through whatever verb t-3021 settles (`peek` in [the-brana.md](../the-brana.md) L4.1; `list/show/answer/cancel` in ADR-063 §5 — the tab names the verb once, when it exists). The snapshot verb's valve count is read through that same verb, never re-derived, so `cockpit snapshot` is not a second surfacing point beside `peek`. Until t-3021 lands the tab is a stub that says so, and the band shows no valve count; no mod ever assembles a valve list from raw sources (that is the shadow queue).

Acting on a valve does **not** restate the classification: reversibility and the verb per valve are [the-brana.md](../the-brana.md) L4.4's (today: AC approve, merge → dev and re-arm reversible; wave ship mostly; ship → main irreversible). The rule here is only the mapping: a **reversible** valve with a CLI verb on the Law-3 write allowlist may be acted on behind a confirm button; **ship → main**, any valve whose L4.4 verb is a slash command rather than a CLI verb (re-arm = `/loop epic-drain`), and any valve not on the write allowlist fill the prompt only, so Claude Code's permission layer stays the gate. A valve appears in the tab only once the valve-feeder has raised it as a store entry (ADR-063 §6 keeps the store answer a separate step from the task action; the tab shows the entry, the verb does the work). A pane click is the inhabitant's own act — never a peer message, never an approval on behalf of anyone (the permission-laundering rule).

### Law 6 — Operations: where mods live, how they ship, how they stay green

- **Layout:** top-level `mods/<name>/` in this repo — never under `system/`, which `bootstrap.sh --sync-plugin` rsyncs to the plugin cache with `--delete` (the t-2500 24 GB class). Each mod is a complete, self-validating plugin with its own tests; internal file layout is t-3425's.
- **Deploy:** one `plugins[]` entry per mod in `.claude-plugin/marketplace.json`; `bootstrap.sh` runs `claude plugin install <name>@brana --scope user` (idempotent) and `--check` asserts the install. The live marketplace is registered from GitHub, so a mod ships when `main` moves, exactly as the plugin does.
- **Green:** `validate.sh` runs `claude plugin validate` + `claude plugin test` for every `mods/*` plus the Law-2/3 greps; `ci.yml` installs a pinned `claude` and fails loudly when the binary is absent (the exit-127 class recorded at ci.yml ~line 96); a scheduled drift job re-runs the same against the installed CC version. Each mod probes the engine version at `session.start` and, on an untested version, degrades to statusline-only with one visible line that names the cause. `$`-touching code is a thin adapter; logic lives in pure modules under `claude plugin test`.
- **Ruflo mods stay off, and it fails the check.** `ruflo init` ≥ 3.50 writes `ruflo-mods`/`-swarm`/`-console` into `.claude/settings.json`; `ruflo-mods` registers a `plugin.register` trust gate that blocks later mods using `process.run` — every cockpit read goes through `process.run`, so an enabled `ruflo-mods` kills the cockpit outright. brana mods never depend on `$.ruflo`; `bootstrap.sh --check` **fails** (not warns) if those entries appear, and the version probe's degrade line names "ruflo-mods trust gate" when that is the cause (ruflo's sanctioned surface is memory/recall only — `delegation-routing.md`).

## Consequences

- The cockpit room has a surface that is the architecture's own: valves, gauges and digest drawn where the inhabitant already is, read through `brana`, with no second state store and no second surfacing point. "Rules become UI": context budget and quota become a gauge with the action one keypress away; the checkout guard becomes visible without becoming weaker.
- Tier 1 + 2a ship in days and pay regardless of 2b's fate; 2b is a bet with a pre-registered threshold, an owner and a date. t-531, t-532 and t-1423 are **not** retired — they are re-evaluated at the week-6 check on the same log, because a session-bound pane cannot serve the no-session (overnight orbit) or client-facing cases.
- Every Claude Code upgrade becomes a tracked event (CI pin bump + green run) instead of silent drift — a property the whole harness gains, not only mods.
- Costs: a per-CC-release maintenance slot; one Rust verb (`cockpit snapshot`) and one write verb (`cockpit log-event`); `bootstrap.sh` grows an install step and a failing check; a second kind of plugin in the marketplace file. The two allowlists make some future conveniences (an in-pane summariser, live GitHub status) deliberately harder — they must arrive as `brana` verbs on a list.
- Second-order: a visible valve count brings valves forward → the runner's human valve stops being the bottleneck → orbit can be armed more often (opportunity). The checkout guard routes Claude through `worktree add` → more concurrent worktrees → lane pins and time brackets (ADR-069/083) see more concurrency; the snapshot verb carries the live worktree count so this stays visible.

## Non-actions

- No mod enforces anything (Law 4). t-3333 ships as a shell hook first, independent of this epic, with the `-C`/`switch`/`restore` test forms.
- No mod write verb outside the Law-3 write allowlist; no `git` execution by a mod.
- No valve aggregation outside ADR-063's store (Law 5); t-3021 keeps its own gating (blocked_by t-2834) and is linked, not absorbed. No valve classification is restated here — L4.4 owns it.
- No tabs beyond Board, no pane spec, until the day-14 signal (Law 1).
- No retirement of t-531 / t-532 / t-1423 before week 6.
- No `$.ruflo` dependency; no ruflo mods enabled.
- Not decided here (t-3425 owns them): band layout, hotkeys, tab order, the snapshot verb's field list, the `$.state` schema/validation mechanics, the cache's TTL and location, mod file trees, which TypeScript compiler, macOS CI handling.

## Open questions

1. **Billing of `$.model`** — assumed to bill the API key rather than the subscription; unverified. Law 3 forbids the call either way; the answer only changes the severity of a leak.
2. **`--safe-mode` / `disableAllHooks` scope** — the docs say they stop installed mods and settings hooks alike; unverified in this repo. Law 4 is written so as not to depend on it, and t-3333's spec should state what it does *not* survive.
3. **CI needs of `claude plugin validate|test`** — whether either needs auth or network. Law 6 assumes neither; t-3427 verifies on the first CI run.
4. **Dev loop** — new-folder hot-load into the session's dev-mods folder was not observed during the spike (the same module ran under `--plugin-dir`); t-3425 records which loop to use.
5. **Subagent visibility** — whether subagent tool calls reach a mod's `tool.call` hook (`turn.step` carries `e.agentId`); irrelevant to Law 4, relevant to a future observability tab.
6. **Desktop layout** — whether `bodyColumns`-based columns survive the Desktop app's Code tab; tier-2b concern.

## Review record

- 2026-10-03 — brainstorm challenger quorum (3 lenses) on the idea doc: five HIGH findings accepted and encoded as Laws 1 (instrumented retention), 3 (source-level enforcement, allowlists), 4 (guard stays a hook), 5 (t-3021 linked not absorbed), 6 (CI install step, drift job, version probe). Of the six single-lens observations, five are encoded (deploy path, snapshot verb, state-as-cache → Laws 2/6; write path by reversibility → Law 5; context-% spike → done, t-3426); the sixth — "ADR + spec scoped to tier 1 only" — is **superseded** by tier 2a: a Board-only pane ships with tier 1 because the retention signal cannot be measured without a pane.
- 2026-10-03 — spike t-3426: context % and 5h/7d quota readable; marketplace deploy route verified in a clean `HOME` including a headless run; **correction** — mods do run under `claude -p`; Law 4's rationale restated.
- 2026-10-03 — accepted by the decider; Law 1 threshold (≥ 50 % of sessions, days 8–14) confirmed.
- 2026-10-03 — context-isolated challenger pass on this ADR (PROCEED WITH CHANGES, 7 findings, all applied): Law 1 split into 2a/2b with a pre-registered threshold and owner; Law 3 gained the write allowlist and the bypass-form greps; `git` removed from mod reach; Law 4 rationale rewritten without the false premises and the three enforcement points named; Law 5 defers classification to L4.4 and adds the single-surfacing rule for the snapshot's valve count; band refresh includes `turn.complete`; spec-level mechanics moved to t-3425; Open questions 1–3 added; ruflo-mods check made failing.
