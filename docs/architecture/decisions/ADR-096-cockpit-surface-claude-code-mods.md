---
status: proposed
extends: docs/architecture/decisions/ADR-063-pending-questions-store.md
respects: docs/architecture/decisions/ADR-094-tasks-json-ledger-in-git-common-dir.md
informs: docs/architecture/the-brana.md
---

# ADR-096: The Brana's cockpit surface is Claude Code mods, under six laws

**Status:** Proposed (2026-10-03) — awaiting one context-isolated challenger pass, then the decider
**Date:** 2026-10-03
**Deciders:** Martín Rios
**Tags:** cockpit, mods, gate, gauge, harness, cc-alignment
**Tasks:** t-3424 (this ADR) · epic t-3422 `cockpit` · spec t-3425 · spike t-3426 (evidence) · band t-3429 · pane shell t-3387 · CI t-3427 · snapshot verb t-3428 · instrumentation t-3432
**Extends:** [ADR-063](ADR-063-pending-questions-store.md) (the one queue the Valves tab reads; `room ∈ cockpit | studio`)
**Respects:** [ADR-094](ADR-094-tasks-json-ledger-in-git-common-dir.md) (the shared main checkout stays on `dev`; safety mechanisms are not removed before their replacement lands)
**Informs:** [the-brana.md](../the-brana.md) §Gate (the cockpit room gains a surface)
**Evidence:** [ideas/brana-cockpit-mod.md](../../ideas/brana-cockpit-mod.md) — brainstorm, 3-lens challenger review, spike t-3426 findings

---

## Context

[the-brana.md](../the-brana.md) §Gate defines two rooms for the inhabitant: the **studio** (needs thinking → agenda) and the **cockpit** (rubber-stamps → digest). It names five human valves (AC approve · wave ship · merge → dev · ship → main · re-arm runner) and records that "all five are cockpit items and four are surfaced nowhere". Orientation today is a dozen CLI calls to remember (`sitrep`, `ops status`, `wave board`, `orbit status`, `remind due`); the context-budget and git-discipline rules exist only as prose; the statusline is the only always-on readout and it carries session-local numbers alone ([ideas/statusline-pipeline-awareness.md](../../ideas/statusline-pipeline-awareness.md) designed a two-tier successor that never shipped).

Three earlier answers to "give the cockpit a screen" are parked: t-531 (Ratatui TUI, gated on "only if CLI snapshots prove insufficient" — a gate that never fired in six months), t-532 (Axum web dashboard) and t-1423 (web UI + Kanban). All three stand *outside* the session the inhabitant is already in.

Claude Code ≥ 2.1.287 ships **mods**: plugins whose hooks module registers functions the engine calls on its own events — a tool call, a submitted prompt, a part of the interface being drawn — and which can draw a pane beside the transcript, a band above the prompt, buttons and text fields, inside the running session. Verified in this repo (spike t-3426, 2026-10-03):

- `session.measure` pushes `context: { tokens, window, percent }` after every main-thread turn — the same window the statusline uses — plus `rateLimits: [{ kind: five_hour | seven_day, percentUsed, resetsAt }]` and `cost: { usd }`; `$.session.usage()` returns the same shape on demand.
- A second `plugins[]` entry in the repo's `.claude-plugin/marketplace.json` (`source: "./mods/<name>"`) installs in a clean `HOME` via `claude plugin install <name>@brana --scope user`; a `claude -p` turn then runs the mod's hooks headless. Only *drawing* is limited to the terminal and the Desktop app.
- A pane docks beside the transcript only under the fullscreen layout (`/tui fullscreen`); on the main screen it seats inline above the prompt.
- Persisted `$.state` outlives hot-reloads and schema changes: a renderer that read a stale shape threw, and a thrown render hook draws nothing (one dim transcript line is the only trace).

A prototype (`backlog-pane`: `/board`, three columns, task detail, Start/Ask buttons that fill the prompt, 16 tests under `claude plugin test`) exists in the session's dev-mods folder. The brainstorm that shaped this decision ran a 3-lens challenger quorum (convergent · systems · critical); five findings had ≥ 2 lenses agreeing and all five are folded into the laws below. One premise of that review — "mods never load for `claude -p`" — was later disproved by the spike; the conclusions it supported survive on their other grounds and are restated accordingly.

### Forces

- **The room exists, the surface doesn't.** The valve inventory and the gauge/pump/valve vocabulary are decided; what is missing is a place the inhabitant *stands*. The surface must be the architecture's, not a parallel dashboard with its own notion of state.
- **One source of truth.** `tasks.json` is a ledger in `$GIT_COMMON_DIR/brana/` (ADR-094) read and written only through `brana`; any UI that reads it directly, or aggregates valve sources itself, becomes the shadow store ADR-002/065 forbid.
- **Subscription-only operation.** Every model call a mod makes bills the API key, not the plan. A cockpit that quietly spends is worse than none.
- **Mods are not a safety layer.** A hook that shells out can time out, fail to load, or be disabled; mods are off under `--safe-mode` and `disableAllHooks`; string-matching `git checkout` is bypassed by `git -C`, aliases, `switch`, `restore`. The ADR-094 harm class (clobbering the shared checkout) needs an enforcement point that none of those switches turn off.
- **The retention bet.** The print-first CLI never lost to a dashboard here. A pane that nobody opens is a weekly maintenance tax with no return; the decision must carry its own kill switch.
- **API churn.** The mods API is new (types regenerate per CC build); an auto-updated CC can break a live mod before CI notices.

## Decision

The Brana's cockpit room gets its surface as **Claude Code mods**, and every cockpit mod obeys six laws. The laws are the decision; tabs, layouts and keymaps are implementation detail owned by the feature spec (t-3425) and may change without amending this ADR.

### Law 1 — Three tiers, band first, the pane earns its keep

```
tier 0  statusline   ·  always on   ·  numbers only              (exists: statusline.sh)
tier 1  band         ·  always on   ·  one gauge + one action    (AbovePrompt — ship first, days)
tier 2  pane /brana  ·  on open     ·  lists, detail, valves     (Pane — ship second, weeks)
```

The band is the pane's doorbell (`⛔ 2 valves · [open]`): the pane's value rides on a signal the band keeps pointing at, not on habit. Tier 2 ships only after a **measured** decision: the pane appends one line per open/close to a log `brana ops` reads; at day 14 after the band and the Board tab ship, the inhabitant keeps or kills the pane tier on that number (t-3432). Killing the pane leaves tiers 0–1 intact. The pane's own spec is written *after* that signal; this ADR and the tier-1 spec do not design tabs beyond Board.

### Law 2 — Gauge law: mods read, never compute, never own state

A mod obtains every number it shows from exactly two sources: a `brana` CLI read verb, or an engine event payload (`session.measure`, `turn.complete`, …). It never reads `tasks.json`, never aggregates raw sources (orbit ledger, `gh pr`, close-queue) into a value of its own, and never recomputes a figure the engine already pushed — the context gauge draws `e.context.percent` as given, so it cannot drift from the statusline's number. `$.state` is a cache: every atom carries `schema: N`, one `readValid($, atom, guard)` helper discards anything else and reloads, and no decision or in-flight action is ever persisted there. Cross-session fan-out is bounded by one read verb, `brana cockpit snapshot --json` (t-3428), backed by a shared TTL cache; the band refreshes on `session.start` and an explicit `r` only, never on a timer.

### Law 3 — No API-billed calls, enforced at the source

A cockpit mod never calls `$.model` or `$.http`. Enforcement is static and needs no Claude Code binary: `validate.sh` greps every `mods/*` source for those nouns and fails on a hit, with a must-fire fixture (t-3427). Process execution goes through one `run()` wrapper with an argv allowlist of `brana` read verbs (plus `git` read-only forms), tested by a denied-argv case — so a mod cannot reach `agy`, `brana recall` embeddings, `curl` or `claude -p` by the back door. Buttons that involve the model only `$.prompt.fill` from fixed templates plus a task id — never free text from task fields, never auto-submit; the turn then runs on the subscription and the inhabitant presses Enter.

### Law 4 — Safety stays in shell hooks; mods render, never enforce

Anything that *prevents* harm — the ADR-094 checkout deny (t-3333), commits on `main`, force-push, `rm -rf` holds — is a PreToolUse shell hook, which runs for every Bash caller in every session kind and cannot be switched off by a mod setting. A mod may show that hook's state in the band and explain a denial; it never carries the deny itself. Rationale (corrected after the spike): not that mods are absent headless — they do run under `claude -p` — but that a mod hook can fail open (timeout, load failure, `--safe-mode`, `disableAllHooks`, a `plugin.register` trust gate from another mod), is bypassed by command forms a shell hook already handles, and does nothing for the inhabitant's own terminal. No fourth enforcement point (memory: `pattern_enforcement-systems-overbuild-then-revert`).

### Law 5 — Valves read one queue; the write path follows reversibility

The Valves tab renders ADR-063's `pending-questions.json` filtered to `room: cockpit`, through whatever verb t-3021 settles (`peek` in [the-brana.md](../the-brana.md) L4.1; `list/show/answer/cancel` in ADR-063 §5 — the tab names the verb once, when it exists). Until t-3021 lands the tab is a stub that says so; no mod ever assembles a valve list from raw sources (that is the shadow queue). Acting on a valve follows the three-tier rule: a **reversible** cockpit item (AC approve, re-arm) may call the store's answer verb directly behind a confirm button; an **irreversible** one (merge → dev, ship → main) only fills the prompt, so Claude Code's permission layer stays the gate. A pane click is the inhabitant's own act — never a peer message, never an approval on behalf of anyone (the permission-laundering rule).

### Law 6 — Operations: where mods live, how they ship, how they stay green

- **Layout:** top-level `mods/<name>/` in this repo — never under `system/`, which `bootstrap.sh --sync-plugin` rsyncs to the plugin cache with `--delete` (the t-2500 24 GB class). Each mod is a complete plugin (`.claude-plugin/plugin.json`, `hooks/hooks.json`, `hooks/register.ts(x)`, `types/index.d.ts`, tests).
- **Deploy:** one `plugins[]` entry per mod in `.claude-plugin/marketplace.json`; `bootstrap.sh` runs `claude plugin install <name>@brana --scope user` (idempotent) and `--check` asserts the install. The live marketplace is registered from GitHub, so a mod ships when `main` moves, exactly as the plugin does.
- **Green:** `validate.sh` runs `claude plugin validate` + `claude plugin test` for every `mods/*` (plus the Law-3 grep); `ci.yml` installs a pinned `claude` on ubuntu and fails loudly when the binary is absent (the exit-127 class recorded at ci.yml ~line 96) — skipped on macOS; a scheduled drift job re-runs the same on the installed CC version; a pinned `tsc` dev dependency gives local type checks. Each mod probes the engine version at `session.start` and, on an untested version, degrades to statusline-only with one visible line. `$`-touching code is a thin adapter (≈ 100 lines per mod); logic lives in pure modules under `claude plugin test`.
- **Ruflo mods stay off.** `ruflo init` ≥ 3.50 writes `ruflo-mods`/`-swarm`/`-console` into `.claude/settings.json`; `ruflo-mods` registers a `plugin.register` trust gate that blocks later mods using `process.run`. brana mods never depend on `$.ruflo`, and `bootstrap.sh --check` warns if those entries appear (ruflo's sanctioned surface is memory/recall only — `delegation-routing.md`).

## Consequences

- The cockpit room has a surface that is the architecture's own: valves, gauges and digest drawn where the inhabitant already is, read through `brana`, with no second state store. "Rules become UI": context budget and quota become a gauge with the action one keypress away; the checkout guard becomes visible without becoming weaker.
- Tier 1 ships in days and pays regardless of the pane's fate; tier 2 is a bet with an explicit, instrumented kill switch. t-531, t-532 and t-1423 are **not** retired — they are re-evaluated at the week-6 check on the same data, because a session-bound pane cannot serve the no-session (overnight orbit) or client-facing cases.
- Every Claude Code upgrade becomes a tracked event (CI pin bump + green run) instead of silent drift — a property the whole harness gains, not only mods.
- Costs: a per-CC-release maintenance slot; one Rust verb (`cockpit snapshot`); `bootstrap.sh` grows an install step; a second kind of plugin in the marketplace file. The "no API" and allowlist rules make some future conveniences (an in-pane summariser, live GitHub status via HTTP) deliberately harder — they must go through `brana` verbs or `gh` on the allowlist.
- Second-order: a visible valve count brings valves forward → the runner's human valve stops being the bottleneck → orbit can be armed more often (opportunity). The checkout guard routes Claude through `worktree add` → more concurrent worktrees → lane pins and time brackets (ADR-069/083) see more concurrency; the snapshot verb carries the live worktree count so this stays visible.

## Non-actions

- No mod enforces anything (Law 4). t-3333 ships as a shell hook first, independent of this epic.
- No valve aggregation outside ADR-063's store (Law 5); t-3021 keeps its own gating (blocked_by t-2834) and is linked, not absorbed.
- No pane spec, no tabs beyond Board, until the day-14 signal (Law 1).
- No retirement of t-531 / t-532 / t-1423 before week 6.
- No `$.ruflo` dependency; no ruflo mods enabled.
- Not decided here: the exact band layout, hotkeys, tab order, the snapshot verb's field list — t-3425 and the day-14 pane spec own those.

## Open questions

1. New-folder hot-load into the session's dev-mods folder was not observed during the spike (the same module ran under `--plugin-dir`). Development loop may need `--plugin-dir` rather than hot reload; t-3425 records which.
2. Whether subagent tool calls are visible to a mod's `tool.call` hook (`turn.step` carries `e.agentId`) — irrelevant to Law 4's conclusion, relevant to any future observability tab.
3. Whether `bodyColumns`-based column layout survives the Desktop app's Code tab unchanged — tier-2 concern, verify before the pane spec.

## Review record

- 2026-10-03 — brainstorm challenger quorum (3 lenses) on the idea doc: five HIGH findings accepted and encoded as Laws 1 (instrumented retention), 3 (source-level enforcement, allowlist), 4 (guard stays a hook), 5 (t-3021 linked not absorbed), 6 (CI install step, drift job, version probe). Six single-lens observations promoted into Laws 2 and 6 (deploy path, snapshot verb, state schema) and Law 5 (write path by reversibility).
- 2026-10-03 — spike t-3426: context % and 5h/7d quota readable; marketplace deploy route verified in a clean `HOME` including a headless run; **correction** — mods do run under `claude -p`; Law 4's rationale restated.
- Pending — one context-isolated challenger pass on this ADR before Accepted (t-3424).
