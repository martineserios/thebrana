---
status: approved
depends_on:
  - docs/architecture/decisions/ADR-096-cockpit-surface-claude-code-mods.md
  - docs/architecture/decisions/ADR-063-pending-questions-store.md
  - docs/architecture/plugin-structure.md
informs:
  - docs/architecture/the-brana.md
impl_files:
  - mods/cockpit-band/
  - mods/cockpit-pane/
  - mods/_shared/
  - system/cli/rust/crates/brana-cli/src/commands/cockpit.rs
  - system/scripts/mods-check.sh
  - system/scripts/mods-sync-shared.sh
  - system/scripts/marketplace-version-sync.sh
  - validate.sh
  - .github/workflows/ci.yml
  - .github/workflows/mods-drift.yml
  - bootstrap.sh
  - .claude-plugin/marketplace.json
---
# Feature: Cockpit — tier 1 band + tier 2a Board pane

**Date:** 2026-10-03
**Status:** approved (2026-10-03, operator) — implementation tasks t-3427/28/29/87/32; becomes `shipped` when t-3387 lands
**Task:** t-3425 · epic t-3422 `cockpit`
**ADR:** [ADR-096](../decisions/ADR-096-cockpit-surface-claude-code-mods.md) — the six laws this spec implements. The laws are not restated here; every section names the law it serves.
**Implements:** t-3427 (CI harness, `_shared`, bootstrap 7g/7h) · t-3428 (Rust verbs) · t-3429 (band) · t-3387 (pane shell + Board) · t-3432 (instrumentation + day-14 rule)
**Evidence:** [ideas/brana-cockpit-mod.md](../../ideas/brana-cockpit-mod.md) (brainstorm, challenger quorum, spike t-3426) · prototype `backlog-pane` (session dev-mods, 16 tests)

## Problem

The cockpit room ([the-brana.md](../the-brana.md) §Gate) has no surface. ADR-096 decided it is drawn by Claude Code mods under six laws and scoped the first delivery to **tier 1** (an always-on band) and **tier 2a** (a Board-only pane whose open/close log feeds a pre-registered keep/kill rule). This spec says exactly what gets built, where it lives, how it is enforced, and what it looks like — so that t-3427/28/29/87/32 can be built test-first from it without re-deciding anything.

## Decision Record

See ADR-096 (accepted 2026-10-03). This spec adds no decision; where it had to pick an implementation detail, the pick is listed under **Assumptions** with its reason, for confirmation.

## Constraints (from ADR-096)

| Law | Constraint on this spec |
|---|---|
| 1 | Tier 1 + 2a ship together; 2b not designed here; instrumentation + reminder are part of 2a |
| 2 | Reads only via `brana` read verbs or engine events; `$.state` is a versioned cache; snapshot verb bounds fan-out; refresh on `session.start`, `turn.complete`, `r` |
| 3 | No `$.model` / `$.http` / network; one `run()` wrapper; read + write allowlists in one file; prompt fills from fixed templates + `^t-\d+$` |
| 4 | Band shows guard state; never enforces |
| 5 | No valve data until t-3021; snapshot's valve count comes from that verb or is 0 |
| 6 | Top-level `mods/`; marketplace entry per mod; `bootstrap.sh` installs + `--check` asserts; validate.sh + CI + drift job; version probe; ruflo mods fail the check |

## Scope (v1 = tier 1 + 2a)

**In:** `mods/_shared` (allowlist, run, state, probe, snapshot) · `mods/cockpit-band` · `mods/cockpit-pane` with the Board tab only · `brana cockpit snapshot --json`, `brana cockpit log-event`, `brana cockpit mark-shipped`, `brana ops cockpit` · `bootstrap.sh` 7g (ruflo guard) + 7h (install) · validate.sh Check 77a/77b + `system/scripts/mods-check.sh` · ci.yml pinned-CLI step + `mods-drift.yml` · the day-14 reminder.
**Out (2b, after the signal):** Wave/Orbit, Ops, Build, Valves tabs; any valve action; any pane spec beyond Board.

## Research

- **Deploy route (spike t-3426):** a `plugins[]` entry with `"source": "./mods/<name>"` installs via `claude plugin install <name>@brana --scope user` and populates `enabledPlugins` + the plugin cache; hooks then run in every session kind including `claude -p`. `bootstrap.sh` Step 7a/7b registers the `brana` marketplace in `known_marketplaces.json` and **replaces the GitHub clone with a symlink** `~/.claude/plugins/marketplaces/brana` → this checkout — which is `dev` (ADR-094) — so an install from it takes `dev`'s mod code, and the install *copies* into the plugin cache (later edits do not propagate: the `plugin-cache-drift` class).
- **Engine data (spike + types):** `session.measure` pushes `{ context: { tokens, window, percent }, rateLimits: [{ kind, percentUsed, resetsAt }], cost: { usd }, changed[] }`; `$.session.usage()` returns the same; `session.start` knows only `window`. `$.session.version()` → `{ version, base?, builtAt? }` (the `claude --version` string; the type names the release field `base` — analytics rows call it `version_base`; a `-dev` build has `base` ending `-dev`). The `engine.create` hook's `e.plugins` lists the module names of the fold (managed first). `$.plugin` holds only `{ name, root }`. `AbovePrompt` gives `hasSurvey`, `isWorking`, `maxRows`, `bodyColumns` (the *transcript* width — narrower while a pane is docked). `Pane` gives its own `bodyColumns` and `placement: dock | inline`. `ui.close` carries `origin.kind ∈ plugin | person | unload`. A pane docks only under `/tui fullscreen`; `$.ui.open` returns `{ isPlaced, reason }`. A band Button with a `hotkey` is pressed by a bare digit in an empty composer (the survey mechanism); "two on one hotkey: later wins".
- **Prototype (`backlog-pane`):** pure logic in `board.ts` (parse, format, args, stale label, shape guard), adapter in `register.tsx`, 16 tests under `claude plugin test`; `claude plugin validate` prints `hooks:` and `calls:` lines. Lessons: a stale `$.state` shape threw inside `ui.render` and drew nothing; hotkeys need focus, so subcommands mirror them; the search box is an `Input` reached by Tab/click, not a `/` key; `claude plugin test` needs `hooks/hooks.json` even for pure-module tests.
- **validate.sh:** numbered blocks with `--fast` and narrow-mode skips; Check 70 delegates to a script so new suites need no edit; last check is 76. **ci.yml:** `validate` job builds the Rust CLI then runs `./validate.sh`; `macos` job asserts a stock environment and runs the test suites (it never calls `validate.sh` — corrected by t-3427); "Check version sync" reads `plugins[0]`; the uv incident (ci.yml ~line 96) is the exit-127 class. **bootstrap.sh** ~line 259 already tolerates a missing `claude` binary.
- **Ecosystem:** `linear-mod`, ruv's `ruflo-console`, Anthropic's `blast-radius` — memory `reference_claude-code-mods-ecosystem`.

## Assumptions

A1–A6 **confirmed by the operator 2026-10-03**; A7–A8 are verification items owned by t-3429 / t-3427.

1. **CI installs the CLI from npm:** `npm install -g @anthropic-ai/claude-code@<pinned>` on ubuntu, because it is the documented path and pins exactly. t-3427: the pin `2.1.288` is published on npm; the install step asserts the binary and its version. First CI run (37140367665): installed and asserted `2.1.288` in the validate job — **confirmed**.
2. **`claude plugin validate|test` run headless with no auth and no network** — the whole 77b proof rests on it (ADR-096 Q3). t-3427, locally: both ran in a fresh temp `HOME` with no credentials (probe A ran them against an installed cache copy; `claude -p` in the same HOME stopped at `Not logged in`, the plugin commands did not). First CI run (37140367665): 77b green with no credentials — **confirmed for auth**; network-free not proven (the runner has network).
3. **Install from the symlinked marketplace is acceptable for the operator's own machine**, with the caveat that it installs `dev`'s code into the cache; `--check` therefore compares *versions*, not presence (see bootstrap 7h). **Needs confirmation** that "installed from dev, bumped per change" is the intended operator model (the public ship path stays `main` → GitHub marketplace).
4. **Quota display:** percent + reset time only — `rateLimits` carries nothing finer. Confirm.
5. **Keymap:** engine focus chord + `1/2/3/r/s/a/x/Esc`; search via Tab to the field; nothing else bound. Confirm.
6. **Dev loop:** `claude --plugin-dir mods/<name>` (new-folder hot-load into dev-mods was not observed in the spike). Confirm, or spike hot-load separately.
7. **"Interactive session" is detectable at `session.start`** (a surface/draw-capability field on the payload) so the `session` event is logged only for sessions that *could* open a pane; t-3429 pins the field. If no such field exists, the fallback is "log `session` from the first `ui.render` of the band" (a band that drew is interactive by definition). **Needs verification.**
8. ~~**`engine.create` is hookable by an ordinary mod and its `e.plugins` includes managed/other plugin names**~~ — **moot (t-3427 probe B, 2026-10-03).** ruflo-mods' gate hooks `plugin.register` and, under `modTrust=refuse-risky`, refuses a later user-tier mod that calls `process.run` *at load*: `cockpit-probe: refused by ruflo-mods: ruflo mod trust (modTrust=refuse-risky): cockpit-probe process.run (runs host commands); allow it by provenance (cockpit-probe@claude-plugin-test) in modTrustAllow`. A refused mod never runs a hook, so no in-mod layer (neither `engine.create` nor a `run()` error) can ever see it; under the test kit `engine.create` of a later plugin was not observed either. Bootstrap 7g is the only layer. ruflo's default policy is `observe` (one transcript line, the mod loads). Capture: `tests/fixtures/mods/captures/probe-b-ruflo-trust-gate.txt`.

## Behavior

- **Band (tier 1):** every turn the band shows context fill, 5h/7d quota and the guard-file state. Past the context-budget thresholds (55 / 70 / 85 %) the gauge changes colour and offers the rule's action as a button that fills the prompt (`/compact`, `/brana:close --continue`). Gauge and quota come **from the engine event and never from the snapshot**, so they draw whenever `session.measure` has fired; a snapshot failure only dims the guard cell. On an untested engine version the band shows one line and nothing else.
- **Pane (tier 2a):** `/brana` (alias `/board`) opens the Board pane: In progress · Next · Blocked columns (tabs under the width threshold), rows pressable, a detail panel underneath, Start / Ask / Close buttons that only fill the prompt. Every open writes one event line; close is best-effort.
- **Success is confirmed** by: the band's percent equals the statusline's; `brana ops cockpit` prints the day-8–14 ratio with its denominator; `./validate.sh --check 77` and CI are green; `bootstrap.sh --check` reports both mods installed at the manifest version.

## Edge cases

- `session.measure` not yet fired (first turn): gauge and quota cells show `—`, dim; guard cell from the snapshot if available.
- `rateLimits` empty (API-key session): quota cells show `—`; nothing is inferred.
- Pane opened on the main screen (not fullscreen): seats inline above the prompt; the reply says `inline — /tui fullscreen docks it right`.
- `$.ui.open` → `{ isPlaced: false, reason }`: reply with the reason; no retry loop; no `open` event logged.
- `$.state` holds an older `schema`: discarded, reloaded, one dim line `cockpit-pane: state v1 discarded`.
- `brana` exits non-zero / times out (15 s): board shows the error line in red with the age of the last good snapshot; band shows `guard ?` and nothing else changes.
- ruflo-mods enabled with `modTrust=refuse-risky`: the engine refuses the mod at load and prints ruflo's refusal line in the transcript; the band and pane draw nothing because they never loaded (probe B). Bootstrap 7g prevents the state; there is no in-session layer. Under ruflo's default `observe` the mod loads and ruflo logs one line naming `process.run`.
- Untested engine version (`base` not in `SUPPORTED`, including any `-dev` build): band shows `cockpit: engine <ver> untested (supported: …) — statusline only` (`UNTESTED_LINE` in `probe.ts`); pane command replies the same; no other draw.
- Search results: replace the **Next** column (or tab) with `Search “q” N`; header gains `esc clears`; empty query restores Next.
- Zero tasks in a column: `—`. Zero tasks everywhere: `backlog empty — brana backlog add`.
- Selected task vanished after a refresh (completed/cancelled elsewhere): detail panel shows `t-NNN no longer listed · x` and nothing else.
- `r` pressed while the search `Input` has focus: it types into the field (engine behaviour) — the header's `refresh` Button is the way out; documented, not fought.
- Orange/red band needing 2 rows with `maxRows` of 1: the action buttons move onto the first row after the message, truncating the quota cells first.
- Two sessions open the pane at once: each logs its own session id; the snapshot cache is shared and refreshed under a non-blocking lock (loser serves the cached copy with its age).

## Design

### Layout (Law 6)

```
mods/
├── package.json                 one dev dependency: typescript (pinned); nothing runtime
├── _shared/                     plugin `cockpit-shared` (never installed): source of truth, VENDORED into each mod — SCANNED by 77a
│   ├── .claude-plugin/plugin.json
│   └── hooks/
│       ├── hooks.json, register.ts   carries the canonical run adapter + /cockpit-shared-run so tests drive it through the engine
│       ├── allowlist.ts             READ + WRITE argv lists (the only place verbs are named)
│       ├── run.ts                   guard(argv, exec): allowlist gate + never-throw result (the adapter line lives in each mod)
│       ├── state.ts                 atom schema:N + valid(value, guard)
│       ├── probe.ts                 engine-version probe → 'ok' | 'untested'; failureLine() for host-level run() failures
│       ├── snapshot.ts              parse + age for `brana cockpit snapshot --json`
│       └── *.test.ts                42 tests, `claude plugin test mods/_shared`
├── cockpit-band/
│   ├── .claude-plugin/plugin.json    name cockpit-band · version x.y.z · types ./types/index.d.ts
│   ├── hooks/hooks.json              { "modules": ["./register.tsx"] }
│   ├── hooks/register.tsx            thin adapter: hooks + draw only; the one canonical run adapter line
│   ├── hooks/_shared/*.ts            vendored by system/scripts/mods-sync-shared.sh — byte-identical (77a drift guard)
│   ├── hooks/band.ts                 pure: thresholds, labels, templates, layout at 60/80/120 cells
│   ├── hooks/band.test.ts
│   └── types/index.d.ts              PluginState['cockpit-band']
└── cockpit-pane/                     the prototype, moved; same shape as cockpit-band
```

Each mod is a complete plugin with its `_shared` files **vendored** into `hooks/_shared/` — no `node_modules`, no import outside the plugin's folder. *(Amended by t-3427: the first draft imported `../../_shared/run`; the engine refuses any import that leaves the plugin's folder, in the source tree and in the install cache alike — `tests/fixtures/mods/captures/probe-a-shared-import.txt`.)* `system/scripts/mods-sync-shared.sh` copies `mods/_shared/hooks/{allowlist,run,state,probe,snapshot}.ts` into every mod that imports `./_shared/`; Check 77a fails on a copy that differs from its source or has none. `.claude-plugin/types/` (engine-written) and `tsconfig.json` are gitignored. **Every change to a mod bumps its `plugin.json` version** — a refreshed vendored copy counts (validate 77a asserts the version differs from the base ref's when the mod's files differ — the cache-drift guard, see bootstrap 7h).

**The run adapter (amended by t-3427).** The engine's scanner refuses a hooks module that passes `$` to a function it did not declare at its own top level, so a shared `run($, argv)` cannot exist. `run.ts` exports the pure `guard(argv, exec)`; each mod's hooks module carries exactly this line, and Check 77a allows `$.process` nowhere else:

```ts
const run = ($: EngineInterface, argv: readonly string[]) => guard(argv, () => $.process.run(argv, { timeoutMs: DEFAULT_TIMEOUT_MS }))
```

`claude plugin validate` reports it as `$.process.run (via run)`, which Check 77b parses against the allowed set.

### Components

```
┌──────────────────────── Claude Code session (mods) ──────────────────────┐
│  cockpit-band (AbovePrompt)            cockpit-pane (/brana, Pane)        │
│  engine.create   ──▶ probe             command.run ──▶ open + load        │
│  session.start   ──▶ log session·load  ui.render   ──▶ Board + detail     │
│  session.measure ──▶ gauge + quota     ui.close    ──▶ log close (best-   │
│  turn.complete   ──▶ load                                effort, next(e)) │
│        │                                     │                            │
│        └────────── _shared/run (READ|WRITE allowlist) ──┘                 │
└────────────────────────────────┬─────────────────────────────────────────┘
                                 │ $.process.run — argv only, no shell, no git
   ──────────────────────────── CLI side (brana, Rust) ──────────────────────
                ┌────────────────┴──────────────────┐
                ▼                                   ▼
  brana cockpit snapshot --json              brana cockpit log-event
  read · TTL cache · counts only             --kind session|open|close
  resolves $GIT_COMMON_DIR itself            single O_APPEND line
                │                                   │
                ▼                                   ▼
  …/brana/tasks.json (load_tasks only)     …/brana/cockpit/events.jsonl
  …/brana/cockpit/snapshot.json            …/brana/cockpit/shipped_at
                                           (read by `brana ops cockpit`)
```

The mod never knows a path: the CLI resolves `$GIT_COMMON_DIR` from its own cwd (which may be a worktree — tested).

### `_shared/allowlist.ts` (Law 3)

```ts
export const READ: readonly string[][] = [
  ['brana','cockpit','snapshot','--json'],
  ['brana','backlog','get'], ['brana','backlog','query'], ['brana','backlog','next'],
  ['brana','backlog','search'], ['brana','backlog','blocked'],
]   // prefix match on argv; extra args allowed only after a listed prefix
export const WRITE: readonly string[][] = [
  ['brana','cockpit','log-event'],   // automatic-and-logged; the only write without a confirm button
]
```

`guard()` (and so every mod's `run()`) denies anything whose argv does not start with a READ or WRITE prefix (`{ denied: true, reason }`), never reaching the host; the deny path has a must-fire test (`brana backlog set` denied; `brana backlog get` allowed; `brana backlog get; rm` denied as one token mismatch). Not on any list: `git`, `gh`, `brana recall|memory|agy`, `curl`, `claude`, `sh`. The valves verb is added to READ by t-3021's landing commit, nowhere else — **the READ list is asserted by exact equality in a test** that fails if any `hands`/valve argv appears before then.

### `_shared/state.ts` (Law 2)

Every atom's value is `{ schema: N, ...data }` (`stamp(data)`). `valid(value, guard, schema = SCHEMA)` is pure: it returns the value when `value.schema === schema` and `guard(value)` holds, else `null`; the hooks module then clears the atom with `update($, atom, () => null)` — two engine calls in the module, since a shared `$`-taking `readValid` is refused by the scanner (amended by t-3427). Tests: a v(N−1) fixture is discarded; a malformed value is discarded; a valid value passes through. Rule in code comment: *state is a cache — the CLI is the source of truth; never persist a decision or an in-flight action.*

### `_shared/probe.ts` (Law 6)

`probe(version: SessionVersion): 'ok' | 'untested'` is pure: `SUPPORTED: readonly string[]` (release cores, e.g. `2.1.287`) in the file; `base` absent, ending `-dev`, or ∉ SUPPORTED → `'untested'`. `SUPPORTED = ['2.1.288']`, equal to ci.yml's `CC_VERSION` (asserted by `tests/scripts/test-ci-mods-harness.sh`). Called once from `session.start` with `await $.session.version()`; the result lives in a module variable; anything but `'ok'` → the band draws one line, the pane command replies it, every other hook returns `next(e)` untouched.

**ruflo trust gate — one layer (amended by t-3427 probe B).** The two in-mod layers first drawn here (an `engine.create` check and a `classifyRunError` keyed on the refusal text) cannot fire: the gate refuses the mod at `plugin.register`, before any of its hooks exist. Bootstrap 7g is the only layer. `probe.ts` keeps `failureLine(result)` for host-level failures only: denied argv, `brana` not on PATH (`cockpit: brana unreachable (not on PATH)`), timeouts.

### Rust verbs (Laws 1/2/3 — t-3428)

**`brana cockpit snapshot --json`** — read-only, `brana-cli/src/commands/cockpit.rs`, mirroring wave board (`load_tasks`, never `lock_tasks`/`save_tasks`; byte-identical-tasks.json test). Output:

```json
{ "at": "2026-10-03T15:00:00Z", "ttl_s": 20, "age_s": 3,
  "backlog": { "in_progress": 8, "next": 15, "blocked": 23 },
  "valves": { "waiting": 0, "source": "none" },          // "none" until t-3021; then "hands"
  "ops": { "health": "ok|warn|fail", "failing_jobs": [] },
  "orbit": { "armed": false, "kill_switch": false },
  "reminders_due": 2,
  "worktrees": 3,
  "guard": { "checkout_deny_file": "present|missing" } }  // file presence only — labelled so in the band
```

Cache `…/brana/cockpit/snapshot.json`: read when younger than `ttl_s` (20 s); otherwise refresh under a **non-blocking** `flock` — the winner recomputes with a cold-path budget of 5 s (ops health is the slow part) and writes **temp file + rename** in the same directory; a loser (lock held) serves the cached copy with its `age_s`. Warm ≤ 100 ms, cold ≤ 5 s, always under the mod's 15 s. **Field list is this spec's; adding a field is a spec change, not an ADR change.**

**`brana cockpit log-event --kind session|open|close --session <id> [--surface pane] [--origin person|plugin|unload]`** — appends one JSON line to `…/brana/cockpit/events.jsonl` with a single `O_APPEND` write (< PIPE_BUF, atomic; no lock, so a mod call can never hang on it). `--kind session` is idempotent per `(session, day)`.

**`brana cockpit mark-shipped`** — writes `…/brana/cockpit/shipped_at` once (refuses if present); run by t-3432 when tier 1 + 2a land. The day-8–14 window is anchored here, not on the first event.

**`brana ops cockpit [--window 8..14]`** — reads the two files and prints: interactive sessions seen (distinct ids with a `session` event), sessions with ≥ 1 `open`, the ratio, and the same three inside the window. **The ADR-096 rule reads `opens / sessions` within days 8–14 after `shipped_at`; closes are informational.** Fixture test: a synthetic log with known counts yields the known ratio; a log with no `session` events prints `denominator 0 — band not logging?` instead of a ratio.

### Instrumentation (Law 1 — t-3432)

- `cockpit-band` logs `--kind session` once per interactive session from `session.start` (Assumption 7 for the interactive test; fallback: from the band's first `ui.render`). Headless `claude -p` and runner sessions therefore never enter the denominator.
- `cockpit-pane` logs `open` after `isPlaced: true`, and `close` from `ui.close` with the origin — **best-effort: the hook always calls `next(e)`, never blocks the close, and the rule does not depend on it.**
- t-3432 ships, in one commit: `mark-shipped`, the `brana remind` entry (`cockpit:day14`, due `shipped_at + 14d`, body quoting ADR-096 Law 1 verbatim), and `ops cockpit`. The week-6 check reuses the same log and verb.

### bootstrap.sh (Law 6 — t-3427)

- **7h — Mods** (lettered 7g/7h because 7a–7f were taken; the draft said 7c/7d). For each entry in `.claude-plugin/marketplace.json` whose `source` starts with `./mods/`: compare the installed version (`plugins/installed_plugins.json`, key `<name>@brana`) with the repo's `plugin.json`; missing → `claude plugin install <name>@brana --scope user`; differing → `claude plugin update <name>@brana`, falling back to uninstall + install when the update fails; equal → `=`. **`--check` never runs `claude plugin …`**: it prints `+ would install` / `~ would update <old>→<new>` / `=` and counts a change. `claude` absent → the existing ~line-259 tolerance applies: `--check` prints `! claude missing — mods not verified` and counts a change; deploy prints the same and continues.
- **7g — ruflo mods guard** (runs before 7h). If `~/.claude/settings.json`, the project `.claude/settings.json` or `.claude/settings.local.json` (`ruflo mods install` writes the local file) enables `ruflo-mods|ruflo-swarm|ruflo-console` (any `@<marketplace>`, value `true`), `--check` **exits 3** at the summary naming file and key; deploy prints the same and skips 7h. Both steps are column-0 functions (`mods_ruflo_guard`, `mods_install_step`) so `tests/bootstrap/test-mods-step.sh` drives deploy mode without a real deploy (32 assertions: three names × user/project files, `false` is not a hit, all 7h outcomes, absent CLI).
- `CACHE_RSYNC_EXCLUDES` is untouched: `mods/` is outside `system/`.

### validate.sh — Check 77a / 77b (Laws 2/3/4/6 — t-3427)

Both delegate to `system/scripts/mods-check.sh`, which takes `--static` or `--engine`.

- **77a — static, always runs** (no `claude` needed; runs under `--fast` and on macOS). Scans every `.ts`/`.tsx` under `mods/` that git does not ignore (tracked or untracked — the engine writes types inside each mod; `*.test.ts(x)` never load in a session and are skipped), `_shared` included: FAIL on `$.model`, `$.http`, `['model']`, `['http']`, `Reflect.get(`, destructured `{ model` / `{ http` / `{ process` from `$`, `fetch(`, `child_process`, `tasks.json`, `git-common-dir`, `$.fs`, `readFile`, `Bun.file`, `on('tool.call'` and `on('tool.check'` (Law 4 — a permission verdict is enforcement), and any `$.process` other than the canonical adapter line (`spawn` included). Also: every vendored `hooks/_shared/*.ts` byte-identical to `mods/_shared/hooks/` (drift); and each mod's `plugin.json` version bumped when its files differ from the base ref (`MODS_BASE_REF`, else `origin/dev`, else `dev`; **none resolvable = FAIL**, so CI fetches `origin/dev` first). Must-fire fixtures `tests/fixtures/mods/bad-*` (20, one per rule) plus `good-minimal`; `tests/scripts/test-mods-check.sh` proves each fires (105 assertions, no `claude` needed).
- **77b — engine, skipped under `--fast` with a `warn`**, otherwise: `claude plugin validate <mod>` must pass; its `calls:` line is parsed and **every call must be in the allowed set** `{ process.run, prompt.fill, ui.open, ui.resolve, ui.status, ui.toast, state.get, state.set, session.usage, session.version, command.register, clock.now }` — structural, catches indirection the greps miss; a missing `calls:` line is a FAIL; then `claude plugin test <mod>` must exit 0 **and** report `Ran N tests` with N ≥ 1 (the engine exits 0 without running anything on a folder with no hooks module); `claude` absent → **FAIL** with `claude CLI not on PATH — install it or run with --fast`. Targets: every `mods/<mod>/` plus an isolated vendored copy of `tests/fixtures/mods/good-minimal`, so the pinned CLI meets a real mod in CI before any band or pane exists.

### ci.yml (Law 6 — t-3427)

`validate` job gains, before "Run validation": `Fetch origin/dev` (77a's base ref on a depth-1 checkout) and `Install pinned claude CLI` (`npm install -g "@anthropic-ai/claude-code@${CC_VERSION}"`, workflow-level `env.CC_VERSION`; the step itself fails when the binary is absent or `claude --version` is not the pin; ubuntu only). "Check version sync" runs `system/scripts/marketplace-version-sync.sh`: the `brana` entry **by name**, not `plugins[0]`, and each `./mods/*` entry against its `plugin.json`. The macOS job never calls `validate.sh` (corrected by t-3427): 77a's rules reach it through `tests/scripts/test-mods-check.sh`, 77b does not run there — the job comment says so. New workflow `mods-drift.yml`: weekly, installs *latest* `claude`, runs `mods-check.sh --engine`; a red run is the signal to bump `CC_VERSION` and `SUPPORTED`.

### Dev loop

`claude --plugin-dir mods/cockpit-band --plugin-dir mods/cockpit-pane` (Assumption 6). Tests: `claude plugin test mods/<name>` and `mods/_shared`; `tsc -p mods/<name>` once the engine has laid `.claude-plugin/types/` (pinned `typescript` dev dep in `mods/package.json`).

## UI design

Conventions: one accent colour per meaning — **green** in-progress / ok, **cyan** next, **red** blocked / error / ≥ 85 %, **yellow** warn / 70–85 %, **dim** metadata; P0 red bold, P1 yellow, P3 dim. Never animate; never redraw on a timer. Every pane hotkey has a slash-subcommand twin. **Band Buttons never set `hotkey`** (a bare digit in an empty composer would press them — the survey mechanism — and collide with the pane's `1/2/3`); asserted by a test.

### Band — states (tier 1, AbovePrompt; designed at 60 cells, tested at 60 / 80 / 120)

```
60 cells  ctx ▓▓░░░░░░░░ 23%  5h 23%↻18:10  7d 20%  guard file ✓
80 cells  ctx ▓▓░░░░░░░░ 23%   5h 23% ↻18:10   7d 20% ↻Oct 9   guard file ✓
orange    ctx ▓▓▓▓▓▓▓░░░ 62% ⚠ prefer summaries, delegate      5h 41%  7d 22%  guard file ✓
          [ /brana:close --continue ]   [ /compact ]
red       ctx ▓▓▓▓▓▓▓▓▓░ 88% ⛔ delegate to a fresh subagent     5h 67%  7d 25%  guard file ✓
          [ /brana:close --continue ]
maxRows 1 ctx ▓▓▓▓▓▓▓░░░ 62% ⚠ [ close --continue ] [ /compact ]  guard file ✓   (quota cells dropped first)
quota ⚠   ctx ▓▓▓░░░░░░░ 31%  5h ▓▓▓▓▓▓▓▓▓░ 91% ↻18:10 ⚠  7d 44%  guard file ✓
1st turn  ctx —   5h —   7d —   guard file ✓                       (session.measure not yet fired)
guard ?   ctx ▓▓░░░░░░░░ 23%  5h 23%  7d 20%  guard ?              (snapshot unavailable — gauge unaffected)
guard ✗   …  guard file ✗                                           (t-3333 hook file absent: shown, never enforced)
untested  cockpit: untested CC 2.1.301 — statusline only
gate      cockpit: ruflo-mods trust gate — statusline only
survey    (nothing — hasSurvey yields the band)
working   (whole row dim while isWorking)
```

Rules: the bar is 10 cells filled from `percent`; thresholds 55/70/85 colour the bar and switch the message to the context-budget rule's text; the quota cell expands to a bar only at ≥ 80 %; buttons appear only in orange/red, never carry `hotkey`, and each **fills** the prompt; at `bodyColumns < 60` the `7d` cell goes first, then the reset times, then the guard label shortens to `g ✓`. Gauge and quota never show "stale": they are the engine's own numbers for this turn.

### Pane — Board (tier 2a). Width = the **Pane's** `bodyColumns` (not the band's); columns at ≥ 96, tabs below

```
┌ Backlog ─────────────────────────────────────────────────────────────┐
│ ▶ 8  ○ 15  ⛔ 23                                        12s ago  r   │
│ / [search backlog (empty = back to Next)               ] ⏎ search    │
│ ╭ In progress 8 ─────╮ ╭ Next 15 ───────────╮ ╭ Blocked 23 ─────────╮│
│ │ P3 L t-1766 Analy… │ │ P1 M t-2164 Wave … │ │ P1 S t-498 ⎇ Plug… ││
│ │ P1 S t-3305 Fix w… │ │ P1 M t-2165 Wave … │ │ P1 S t-499 Versi… ││
│ │ …                  │ │ …                  │ │ …                   ││
│ │ +5 more            │ │ +12 more           │ │ +20 more            ││
│ ╰────────────────────╯ ╰────────────────────╯ ╰─────────────────────╯│
│ ╭ t-3305  Fix worktree-toplevel-relative tasks.json…  [s Start] [a Ask] [x] ╮
│ │ pending · fix · P1 · S   ⎇ —   #tasks-json #worktree #hooks              │
│ │ t-3286's Challenger Gate (second-variant finder, rung 1) found …         │
│ │ ☐ pre-tool-use.sh resolves tasks.json from the worktree toplevel          │
│ │ ☐ plan-mode-gate.sh … (+2 more AC)                                        │
│ ╰────────────────────────────────────────────────────────────────────────────╯
└──────────────────────────────────────────────────────────────────────┘
```

Search active (replaces the Next column/tab):

```
│ ╭ In progress 8 ─────╮ ╭ Search “worktree” 12 · esc clears ╮ ╭ Blocked 23 ╮│
```

Narrow (< 96 cells) or inline — tabs replace columns:

```
│ [1 In progress 8] [2 Next 15] [3 Blocked 23]           12s ago  r   │
│ P1 S t-3305 Fix worktree-toplevel-relative tasks.json resolution…    │
```

Row grammar: `PRI EFF id ⎇? subject…` — priority coloured, `⎇` when a branch exists, subject truncated to width. Header: counts with `▶ ○ ⛔`, snapshot age with `· stale` after 5 min in yellow (the pane's lists *are* snapshot data, so "stale" is honest here). Detail panel border takes the task's priority colour. Empty column `—`; empty board `backlog empty — brana backlog add`. Error: a red line under the search field; the last good lists stay with their age. Vanished selection: `t-NNN no longer listed · x`.

### Keymap (pane focused via the engine's focus chord or a click; `Esc` returns to the prompt)

| Key | Action | Slash twin |
|---|---|---|
| `Tab` / arrows | move between rows, buttons and the search field | — |
| `Enter` on a row | open detail | `/brana t-NNN` |
| `1` `2` `3` | column / tab | `/brana progress` `next` `blocked` |
| `r` | refresh (snapshot + lists); **types into the field if the search field has focus** | `/brana r` |
| `Tab` to the search field, type, `Enter` | search (empty → back to Next) | `/brana search <q>` |
| `s` | fill `/brana:backlog start t-NNN` | — (detail only) |
| `a` | fill the fixed "next step" prompt for t-NNN | — (detail only) |
| `x` | close detail | — |
| — | plain text dump (headless) | `/brana dump [column]` |

`/board` is registered as a second command name answering the same hook (command-registration test; if the engine rejects two names for one module, `/board` becomes a one-line reply pointing at `/brana` — t-3387 decides from the first run).

### Command replies

`/brana` → `Backlog opened (docked)` or `Backlog opened (inline — /tui fullscreen docks it right)`; refused → `Backlog pane not shown: <engine reason>`; untested / gate → the probe line. One line each; usage on bad args.

## Boundaries

| Always | Ask first | Never |
|---|---|---|
| Read via `run()` + allowlist; draw gauge/quota from the event; draw lists from the snapshot; log session/open | Any new verb on either allowlist (spec change); any button that writes (confirm) | Call `$.model`/`$.http`; read `tasks.json` or any file; run `git`; enforce anything; auto-submit a prompt; persist a decision in `$.state`; set `hotkey` on a band Button; enable ruflo mods |

## Testing strategy

- **Unit (≈ 70 %):** `_shared` — allowlist deny/allow incl. prefix abuse; exact-equality READ list; `state` schema discard; `probe` (`ok`, `untested`, `-dev`); `failureLine`; `snapshot` parse + age. `band.ts` — threshold → colour/message/buttons at 54/55/69/70/84/85; empty `rateLimits`; first turn; `guard ?`; layout at 60/80/120 and `maxRows` 1; no band Button has `hotkey`; template fill rejects a non-`t-NNN` id. `board.ts` — the prototype's 16 tests, kept, plus search-replaces-Next, vanished selection.
- **Integration (≈ 25 %):** `claude plugin test` on each mod: band draws nothing with `hasSurvey`; band shows `guard ?` when `run()` errors and the gauge still draws; band logs `session` once; pane open → `log-event open` argv observed; `ui.close` → `log-event close` *and* `next(e)` called; stale-state fixture → one dim line, reload; `/board` registration. Rust: `cockpit snapshot` byte-identical tasks.json; TTL hit; non-blocking refresh (loser serves cache); temp+rename; run from a worktree resolves the common dir; `log-event` single-line append; `mark-shipped` refuses twice; `ops cockpit` fixture ratio and the denominator-0 message.
- **E2E (≈ 5 %):** `mods-check.sh --static` on every `bad-*` fixture (each must fire); `bootstrap.sh --check` in a temp HOME reports installs and **exits non-zero** on a `ruflo-mods` entry; one CI run green with the pinned CLI; a temp-HOME spike with `ruflo-mods` enabled records the refusal text (Assumption 8).
- **Mock policy:** real engine via the test kit; mock only the clock and `run()`'s process boundary.

## Enforcement matrix (AC1 — one line per law)

| Law | Where enforced | Must-fire proof |
|---|---|---|
| 1 | `log-event session|open`; `mark-shipped`; `brana ops cockpit`; `brana remind cockpit:day14` | band test observes `session`; pane test observes `open`; `ops cockpit` fixture ratio; remind exists after t-3432 |
| 2 | 77a greps `tasks.json`/`git-common-dir`/`$.fs`/`readFile`/`Bun.file`/non-adapter `$.process` over `mods/**`; `valid` tests; snapshot is the only aggregate | `bad-reads-ledger`, `bad-fs-read` fixtures fail 77a |
| 3 | 77a greps model/http/bracket/Reflect/destructure/fetch/child_process; 77b `calls:` allowed-set parse; `run()` deny test; template id test | `bad-calls-model`, `bad-destructured-http`, `bad-reflect-get` fixtures fail 77a; a mod calling `$.http.fetch` via a template-built path fails 77b; `brana backlog set` denied in test |
| 4 | Band renders `guard` from the snapshot only; 77a greps `on('tool.call'` in `mods/**` | `bad-tool-call-hook` fixture fails 77a |
| 5 | `valves.source = "none"` until t-3021; READ list exact-equality test | the READ test fails on any `hands`/valve argv before t-3021 |
| 6 | bootstrap 7h (version compare, never installs under `--check`) / 7g (non-zero exit); 77b FAIL on absent CLI; ci pinned install + per-mod version sync; `mods-drift.yml`; probe degrade | temp-HOME `--check` tests (installs reported; ruflo entry → non-zero); CI run; probe unit tests |

## Task map

| Section | Task |
|---|---|
| `_shared` (allowlist, run, state, probe, snapshot), `mods/package.json`, Check 77a/77b + `mods-check.sh` + `mods-sync-shared.sh` + fixtures, ci steps, `mods-drift.yml`, **bootstrap 7g/7h**, the ruflo-mods temp-HOME spike | t-3427 |
| `cockpit snapshot`, `cockpit log-event`, `cockpit mark-shipped`, `ops cockpit`, cache + locks | t-3428 |
| `cockpit-band` (incl. `session` event, interactive detection) | t-3429 |
| `cockpit-pane` (prototype → `mods/`, `/brana` + `/board`, open/close events, search/vanished states) | t-3387 |
| remind entry, `mark-shipped` run, day-14 review, week-6 re-eval | t-3432 |

## Documentation plan

- [ ] **Tech doc** — this file → `shipped` at the end of t-3387; Changelog per task.
- [ ] **User guide** — `docs/guide/features/cockpit.md` (t-3434): open, keys, subcommands, fullscreen note, what shows where.
- [ ] **Existing docs** — `the-brana.md` §Gate surface line (t-3433); `docs/README.md` row (this task); `plugin-structure.md` "Plugin vs Bootstrap" table gains a **Mods (`mods/`)** row (this task).

## Challenger findings

2026-10-03 — context-isolated pass: PROCEED WITH CHANGES, 8 findings, all applied. **Critical:** (1) Check 77 would have skipped its greps under `--fast`/macOS/no-CLI and never scanned `_shared/` → split 77a (static, always, `mods/**`) / 77b (engine, `calls:` allowed-set parse); (2) the loaded-plugin set is not a `$` noun → probe is `ok|untested` from `$.session.version()`; ruflo-gate detection via `engine.create` `e.plugins` (Assumption 8) plus `classifyRunError`; bootstrap 7d is the guaranteed layer with a must-fire test; (3) the day-14 ratio had no denominator → band logs `session` for interactive sessions; `mark-shipped` anchors the window; close is best-effort and the rule reads opens. **Warnings:** gauge/quota draw from the engine event only (no "stale ctx"; `guard ?`; "guard file"); cache temp+rename + non-blocking refresh lock; `log-event` single `O_APPEND` line; CLI resolves the common dir (worktree test); bootstrap 7c compares versions, never installs under `--check`, tolerates a missing CLI; per-mod version bump asserted; ci version sync by name; macOS runs 77a only; keymap honesty (`Tab` to search, band Buttons never `hotkey`), band at 60 cells, five missing states added. **Observation:** 7c/7d assigned to t-3427; `/board` test; READ exact-equality test; diagram relabelled CLI-side; Assumption 2 (headless `plugin test`) added.

## Changelog

- 2026-10-03: spec drafted (t-3425) from ADR-096 + spike t-3426 + prototype; challenger pass applied; approved by the operator (A1–A6 confirmed).
- 2026-10-03: t-3427 built the harness and amended four engine-falsified premises, each with a committed capture or test: (1) `_shared` is vendored per mod, not imported by relative path (probe A); (2) `run($, argv)` became `guard(argv, exec)` plus one canonical adapter line per hooks module, and `readValid` became the pure `valid` (the scanner refuses passing `$` to a function not declared in the module); (3) the in-mod ruflo-gate layers are dropped — a refused mod never loads, bootstrap 7g is the only layer (probe B, Assumption 8 moot); (4) bootstrap steps are 7g/7h, the macOS CI job never ran `validate.sh`. Additions: `tool.check` joins the Law-4 greps; 77b requires `Ran N ≥ 1 tests` and a `calls:` line; an isolated `good-minimal` copy is always a 77b target; the version guard fails without a base ref.
