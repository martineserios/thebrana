---
status: specifying
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
  - validate.sh
  - .github/workflows/ci.yml
  - bootstrap.sh
  - .claude-plugin/marketplace.json
---
# Feature: Cockpit — tier 1 band + tier 2a Board pane

**Date:** 2026-10-03
**Status:** specifying
**Task:** t-3425 · epic t-3422 `cockpit`
**ADR:** [ADR-096](../decisions/ADR-096-cockpit-surface-claude-code-mods.md) — the six laws this spec implements. The laws are not restated here; every section names the law it serves.
**Implements:** t-3427 (CI harness) · t-3428 (snapshot verb) · t-3429 (band) · t-3387 (pane shell + Board) · t-3432 (instrumentation + day-14 rule)
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

**In:** `mods/_shared` (allowlist, run, state, probe, log) · `mods/cockpit-band` · `mods/cockpit-pane` with the Board tab only · `brana cockpit snapshot --json` and `brana cockpit log-event` · `bootstrap.sh` install step + `--check` assertion · validate.sh Check 77 · ci.yml pinned-CLI step + scheduled drift job · `brana ops cockpit` read-out of the open/close log · the day-14 reminder.
**Out (2b, after the signal):** Wave/Orbit, Ops, Build, Valves tabs; any valve action; any pane spec beyond Board.

## Research

- **Deploy route (spike t-3426):** a `plugins[]` entry with `"source": "./mods/<name>"` installs via `claude plugin install <name>@brana --scope user` and populates `enabledPlugins` + the plugin cache; hooks then run in every session kind including `claude -p`. `bootstrap.sh` Step 7a/7b already registers the `brana` marketplace in `known_marketplaces.json` and symlinks `~/.claude/plugins/marketplaces/brana` → this repo, so a mod install resolves against the live checkout.
- **Engine data (spike):** `session.measure` pushes `{ context: { tokens, window, percent }, rateLimits: [{ kind, percentUsed, resetsAt }], cost: { usd }, changed[] }`; `$.session.usage()` returns the same; `session.start` knows only `window`. `AbovePrompt` gives `hasSurvey`, `isWorking`, `maxRows`, `bodyColumns`. A pane docks only under `/tui fullscreen`; `$.ui.open` returns `{ isPlaced, reason }`.
- **Prototype (`backlog-pane`):** pure logic in `board.ts` (parse, format, args, stale label, shape guard), adapter in `register.tsx`, 16 tests under `claude plugin test`; `claude plugin validate` prints `hooks:` / `calls:` lines. Lessons: a stale `$.state` shape threw inside `ui.render` and drew nothing; hotkeys need focus, so subcommands mirror them; `claude plugin test` needs `hooks/hooks.json` even for pure-module tests.
- **validate.sh:** checks are numbered blocks with `--fast` and narrow-mode skips; Check 70 delegates a sweep to a script so new suites need no edit — Check 77 copies that shape. **ci.yml:** `validate` job builds the Rust CLI then runs `./validate.sh`; `tests` and `macos` jobs exist; the uv incident (ci.yml ~line 96) is the exit-127 class.
- **Ecosystem:** `linear-mod` (board → item → prompt buttons), ruv's `ruflo-console` (palette shows the exact command, then confirms; hotkeys mirrored as subcommands), Anthropic's `blast-radius` (hold + Proceed/Cancel) — memory `reference_claude-code-mods-ecosystem`.

## Assumptions (need confirmation)

1. **CI installs the CLI from npm:** chose `npm install -g @anthropic-ai/claude-code@<pinned>` on ubuntu because it is the documented install path and gives an exact pin — **needs confirmation** (t-3427 verifies on the first run; ADR-096 Q3 asks whether `plugin validate|test` need auth/network).
2. **Install against the symlinked marketplace:** chose to reuse bootstrap 7b's symlink (`marketplaces/brana` → repo) rather than a second directory-source marketplace, because the spike proved a directory source and the symlink *is* a directory — **needs confirmation** on first bootstrap run.
3. **Quota display:** chose percent + reset time only (no token counts) because `rateLimits` carries `percentUsed` and `resetsAt`, nothing finer — confirm the band should not try to show more.
4. **Keymap:** chose `ctrl+x tab` (engine focus chord) + `1/2/3/r/s/a/x/Esc` as in the prototype; nothing else bound — confirm.
5. **Dev loop:** chose `claude --plugin-dir mods/<name>` as the documented loop (hot-load of a *new* folder into dev-mods was not observed in the spike) — confirm, or spike hot-load separately.

## Behavior

- **Band (tier 1):** every turn the band shows context fill, 5h/7d quota and the guard state. Past the context-budget thresholds (55 / 70 / 85 %) the gauge changes colour and offers the rule's action as a button that fills the prompt (`/compact`, `/brana:close --continue`). With no snapshot (brana unreachable, timeout, unknown CC version) the band shows one short degraded line or nothing — never stale numbers.
- **Pane (tier 2a):** `/brana` (alias `/board`) opens the Board pane: In progress · Next · Blocked columns (stacked under 96 cells), rows pressable, a detail panel underneath, Start / Ask / Close buttons that only fill the prompt. Every open and close writes one line through `brana cockpit log-event`.
- **Success is confirmed** by: the band's number equals the statusline's; `brana ops cockpit` lists opens per session; `./validate.sh --check 77` and CI are green; `bootstrap.sh --check` reports both mods installed.

## Edge cases

- `session.measure` not yet fired (first turn): band shows `ctx —` dims, no colour.
- `rateLimits` empty (API-key session): quota cells show `—`; nothing is inferred.
- Pane opened on the main screen (not fullscreen): seats inline above the prompt; the command's text reply says `inline — /tui fullscreen docks it right`.
- `$.ui.open` → `{ isPlaced: false, reason }`: reply with the reason; no retry loop.
- `$.state` holds an older `schema`: discarded, reloaded, one dim line `cockpit-pane: state v1 discarded`.
- `brana` exits non-zero / times out (15 s): board shows the error line in red with the age of the last good snapshot; band shows `cockpit: brana unreachable` for one turn, then nothing.
- Untested CC version: band shows `cockpit: untested CC <ver> — statusline only`; pane command replies the same; no other draw.
- `ruflo-mods` enabled: `bootstrap.sh --check` fails naming the entry; the probe's degrade line says `ruflo-mods trust gate`.
- Two sessions open the pane at once: each logs its own session id; the snapshot cache is shared read-only (last writer wins on refresh; no lock, counts only).

## Design

### Layout (Law 6)

```
mods/
├── _shared/                     pure, tested, imported by both mods
│   ├── allowlist.ts             READ + WRITE argv lists (the only place verbs are named)
│   ├── run.ts                   run($, argv, init) → checks allowlist, calls $.process.run
│   ├── state.ts                 atom schema:N + readValid($, atom, guard, reload)
│   ├── probe.ts                 engine-version probe → 'ok' | 'untested' | 'ruflo-gate'
│   ├── snapshot.ts              parse + age/stale for `brana cockpit snapshot --json`
│   └── *.test.ts
├── cockpit-band/
│   ├── .claude-plugin/plugin.json    name cockpit-band · types ./types/index.d.ts
│   ├── hooks/hooks.json              { "modules": ["./register.tsx"] }
│   ├── hooks/register.tsx            ≤ ~100 lines: hooks + draw only
│   ├── hooks/band.ts                 pure: thresholds, labels, templates
│   ├── hooks/band.test.ts
│   └── types/index.d.ts              PluginState['cockpit-band']
└── cockpit-pane/                     the prototype, moved; same shape as cockpit-band
```

Each mod is a complete plugin; `_shared` is imported by relative path (`../../_shared/run`) — no package manager, no `node_modules`. `.claude-plugin/types/` (engine-written) and `tsconfig.json` are gitignored.

### Components

```
┌──────────────────────── Claude Code session ────────────────────────┐
│  cockpit-band (AbovePrompt)          cockpit-pane (/brana, Pane)     │
│  session.measure ──▶ gauge + quota   command.run ──▶ open + load     │
│  session.start   ──▶ probe + load    ui.render   ──▶ Board + detail  │
│  turn.complete   ──▶ load            ui.close    ──▶ log-event close │
│        │                                   │                          │
│        └──────── _shared/run (allowlist) ──┘                          │
└───────────────────────────────┬──────────────────────────────────────┘
                                │ $.process.run (no shell, argv only)
                ┌───────────────┴────────────────┐
                ▼                                ▼
  brana cockpit snapshot --json         brana cockpit log-event --kind open|close
  (read; TTL cache; counts only)        (write allowlist; appends one JSONL line)
                │                                │
                ▼                                ▼
  $GIT_COMMON_DIR/brana/tasks.json      $GIT_COMMON_DIR/brana/cockpit/events.jsonl
  (read-only, load_tasks, never lock)   (read by `brana ops cockpit`)
```

### `_shared/allowlist.ts` (Law 3)

```ts
export const READ: readonly string[][] = [
  ['brana','cockpit','snapshot','--json'],
  ['brana','backlog','get'], ['brana','backlog','query'], ['brana','backlog','next'],
  ['brana','backlog','search'], ['brana','backlog','blocked'],
]                                   // prefix match on argv; extra args allowed only after a listed prefix
export const WRITE: readonly string[][] = [
  ['brana','cockpit','log-event'],  // each write verb: confirm button OR automatic-and-logged (log-event only)
]
```

`run()` denies anything whose argv does not start with a READ or WRITE prefix (`{ denied: true, reason }`), and the deny path has a must-fire test. Not on any list: `git`, `gh`, `brana recall|memory|agy`, `curl`, `claude`, `sh`. The valves verb is added to READ by t-3021's landing commit, nowhere else.

### `_shared/state.ts` (Law 2)

Every atom's value is `{ schema: N, ...data }`. `readValid($, atom, guard)` returns the data when `guard(value)` holds and `value.schema === SCHEMA`, else returns `null` after `update(atom, () => null)`. Tests: a v(N-1) fixture is discarded; a malformed value is discarded; a valid value passes through. Rule in code comment: *state is a cache — the CLI is the source of truth; never persist a decision or an in-flight action.*

### `_shared/probe.ts` (Law 6)

At `session.start`: read the engine version (from `$.plugin`/engine info as the types expose it — t-3429 pins the field); compare against `SUPPORTED: readonly string[]` in the file; detect `ruflo-mods` in the loaded plugin set if the engine lists it; return `'ok' | 'untested' | 'ruflo-gate'`. Anything but `'ok'` → both mods draw one line (band) / reply one line (pane) and otherwise return `next(e)`.

### `brana cockpit snapshot --json` (Law 2, t-3428)

Read-only Rust verb in `brana-cli/src/commands/cockpit.rs`, mirroring wave board's pattern (`load_tasks`, never `lock_tasks`/`save_tasks`; a byte-identical-tasks.json test). Output:

```json
{ "at": "2026-10-03T15:00:00Z", "ttl_s": 20,
  "backlog": { "in_progress": 8, "next": 15, "blocked": 23 },
  "valves": { "waiting": 0, "source": "none" },        // "none" until t-3021; then "hands"
  "ops": { "health": "ok|warn|fail", "failing_jobs": [] },
  "orbit": { "armed": false, "kill_switch": false },
  "reminders_due": 2,
  "worktrees": 3,
  "guard": { "checkout_deny": "installed|missing" } }    // presence of t-3333's hook file, nothing more
```

Cache: `$GIT_COMMON_DIR/brana/cockpit/snapshot.json`, rewritten when older than `ttl_s` (20 s), read otherwise; concurrent sessions share it. Warm call ≤ 100 ms. **Field list is this spec's; adding a field is a spec change, not an ADR change.**

### `brana cockpit log-event` (Laws 1/3, t-3428/t-3432)

`brana cockpit log-event --kind open|close --session <id> [--surface pane]` appends `{"at","kind","session","surface"}` to `$GIT_COMMON_DIR/brana/cockpit/events.jsonl` (append-only, locked like ADR-051 stores). `brana ops cockpit [--since 14d]` prints sessions seen, sessions with ≥ 1 open, the ratio, and the day-8–14 window ratio the ADR-096 rule reads. t-3432 creates the `brana remind` entry (due day 14, dedup key `cockpit:day14`) in the same commit that ships the log.

### bootstrap.sh (Law 6)

New step **7c — Mods**: for each entry in `.claude-plugin/marketplace.json` whose `source` starts with `./mods/`: `claude plugin install <name>@brana --scope user` when not in `enabledPlugins`, else `=` line; `--check` reports `+ would install` / `=`. Step 7d — **ruflo mods guard**: if `enabledPlugins` or `.claude/settings.json` lists `ruflo-mods|ruflo-swarm|ruflo-console`, `--check` **fails** with the entry named. `CACHE_RSYNC_EXCLUDES` is untouched because `mods/` is outside `system/`.

### validate.sh — Check 77 (Laws 2/3/6)

Shape of Check 70: skipped under `--fast`/narrow modes with a `warn`; otherwise delegates to `system/scripts/mods-check.sh`, which for every `mods/*/` with a `.claude-plugin/plugin.json`: (a) static greps — fail on `$.model`, `$.http`, `['model']`, `['http']`, destructured `{ model` / `{ http` from `$`, `fetch(`, `child_process`, `tasks.json`, `git-common-dir`, and `process.run(` outside `mods/_shared/run.ts`; (b) `claude plugin validate <mod>` must pass; (c) `claude plugin test <mod>` must pass; (d) if `claude` is absent: **FAIL** (not skip) with `claude CLI not on PATH — install it or run with --fast`. Must-fire fixtures live in `tests/fixtures/mods/bad-*` and the script's own test proves each grep fires.

### ci.yml (Law 6)

`validate` job gains, before "Run validation": `Install pinned Claude Code CLI` (`npm install -g @anthropic-ai/claude-code@${{ env.CC_VERSION }}`, `claude --version` must print the pin) — ubuntu only; the macOS job keeps asserting a stock environment and Check 77 there reports FAIL→ the macOS job runs `./validate.sh --fast`, which skips 77 (document this in the job comment). New workflow `mods-drift.yml`: weekly schedule, installs *latest* `claude`, runs `system/scripts/mods-check.sh`, opens nothing — a red run is the signal to bump `CC_VERSION`.

### Instrumentation + rule (Law 1, t-3432)

`cockpit-pane` calls `log-event open` after a successful `$.ui.open` and `log-event close` from its `ui.close` hook; both via `run()` (WRITE list). `brana ops cockpit` is the read-out; the `brana remind` entry is the owner; the rule text is quoted verbatim from ADR-096 Law 1 in the remind body.

### Dev loop

`claude --plugin-dir mods/cockpit-band --plugin-dir mods/cockpit-pane` (Assumption 5). Tests: `claude plugin test mods/<name>` and `mods/_shared`; `tsc -p mods/<name>` once the engine has laid `.claude-plugin/types/` (pinned `typescript` dev dep in `mods/package.json`, used by nothing else).

## UI design

Conventions: one accent colour per meaning only — **green** in-progress / ok, **cyan** next, **red** blocked / error / ≥ 85 %, **yellow** warn / stale / 70–85 %, **dim** metadata; P0 red bold, P1 yellow, P3 dim. Never animate; never redraw on a timer. Every hotkey has a slash-subcommand twin.

### Band — states (tier 1, AbovePrompt, 1 row; 2 rows only when an action is offered)

```
normal      ctx ▓▓░░░░░░░░ 23%   5h 23% ↻18:10   7d 20% ↻Oct 9   guard ✓
orange      ctx ▓▓▓▓▓▓▓░░░ 62% ⚠ prefer summaries, delegate next step        5h 41%  7d 22%  guard ✓
            [ /brana:close --continue ]   [ /compact ]
red         ctx ▓▓▓▓▓▓▓▓▓░ 88% ⛔ delegate to a fresh subagent               5h 67%  7d 25%  guard ✓
            [ /brana:close --continue ]
quota warn  ctx ▓▓▓░░░░░░░ 31%   5h ▓▓▓▓▓▓▓▓▓░ 91% ↻18:10 ⚠                  7d 44%  guard ✓
first turn  ctx —           5h —   7d —   guard ✓                            (session.measure not yet fired)
stale       ctx 62% · 7m ago · stale   (snapshot unavailable; last good shown dim, labelled)
unreachable cockpit: brana unreachable — statusline only                     (one turn, then nothing)
degraded    cockpit: untested CC 2.1.301 — statusline only
            cockpit: ruflo-mods trust gate — statusline only
guard ✗     … guard ✗ hook missing   (t-3333 hook file absent: shown, never enforced)
survey      (nothing — hasSurvey yields the band)
```

Rules: the bar is 10 cells, filled proportionally from `percent`; thresholds 55/70/85 colour the bar and switch the message to the context-budget rule's text; the quota cell only expands to a bar at ≥ 80 %; buttons appear only in orange/red and each **fills** the prompt (never submits); `isWorking` dims the whole row.

### Pane — Board (tier 2a), docked right under fullscreen, ≥ 96 cells → columns

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

Narrow (< 96 cells) or inline: tabs replace columns —

```
│ [1 In progress 8] [2 Next 15] [3 Blocked 23]           12s ago  r   │
│ P1 S t-3305 Fix worktree-toplevel-relative tasks.json resolution…    │
│ …                                                                    │
```

Row grammar: `PRI EFF id ⎇? subject…` — priority coloured, `⎇` when a branch exists, subject truncated to width. Header: counts with glyphs `▶ ○ ⛔`, age with `· stale` after 5 min in yellow. Detail panel border takes the task's priority colour. Empty column shows `—`. Error: a red line under the search field, the last good snapshot stays with its age.

### Keymap (pane focused via `ctrl+x tab` or click; `Esc` returns to the prompt)

| Key | Action | Slash twin |
|---|---|---|
| `Tab` / arrows | move between rows and buttons | — |
| `Enter` on a row | open detail | `/brana t-NNN` |
| `1` `2` `3` | column / tab | `/brana progress` `next` `blocked` |
| `r` | refresh (snapshot + lists) | `/brana r` |
| `/` + text + Enter | search (empty → back to Next) | `/brana search <q>` |
| `s` | fill `/brana:backlog start t-NNN` | — (detail only) |
| `a` | fill the fixed "next step" prompt for t-NNN | — (detail only) |
| `x` | close detail | — |
| — | plain text dump (headless) | `/brana dump [column]` |

### Command replies (what the transcript shows)

`/brana` → `Backlog opened (docked)` or `Backlog opened (inline — /tui fullscreen docks it right)`; refused → `Backlog pane not shown: <engine reason>`; degraded → the probe line. Replies are one line; usage on bad args.

## Boundaries

| Always | Ask first | Never |
|---|---|---|
| Read via `run()` + allowlist; draw from the snapshot or an event; log open/close | Any new verb on either allowlist (spec change); any button that writes (confirm) | Call `$.model`/`$.http`; read `tasks.json`; run `git`; enforce anything; auto-submit a prompt; persist a decision in `$.state`; enable ruflo mods |

## Testing strategy

- **Unit (≈ 70 %):** `_shared` — allowlist deny/allow incl. prefix abuse (`brana backlog set` denied, `brana backlog get` allowed); `state` schema discard; `probe` three outcomes; `snapshot` parse + age/stale. `band.ts` — threshold → colour/message/buttons at 54/55/69/70/84/85; empty `rateLimits`; first-turn; template fill rejects a non-`t-NNN` id. `board.ts` — the prototype's 16 tests, kept.
- **Integration (≈ 25 %):** `claude plugin test` on each mod: band draws nothing with `hasSurvey`; band shows the unreachable line when `run()` returns an error; pane open → `log-event open` argv observed; `ui.close` → `log-event close`; stale-state fixture → one dim line, reload. Rust: `cockpit snapshot` byte-identical tasks.json; TTL cache hit; `log-event` appends under lock; `ops cockpit` ratio on a fixture log.
- **E2E (≈ 5 %):** `mods-check.sh` on the `bad-*` fixtures (each grep must fire); `bootstrap.sh --check` in a temp HOME reports the two installs; one CI run green with the pinned CLI.
- **Mock policy:** real engine via the test kit; mock only the clock and `run()`'s process boundary.

## Enforcement matrix (AC1 — one line per law)

| Law | Where enforced | Must-fire proof |
|---|---|---|
| 1 | `log-event` on open/close; `brana ops cockpit`; `brana remind cockpit:day14` | pane test observes both argv; remind exists after t-3432 |
| 2 | Check 77 greps `tasks.json`/`git-common-dir`/non-adapter `process.run`; `readValid` tests; snapshot is the only aggregate | `bad-reads-ledger` fixture fails Check 77 |
| 3 | Check 77 greps model/http/fetch/child_process; `run()` allowlist deny test; template id test | `bad-calls-model` + `bad-destructured-http` fixtures fail; `brana backlog set` denied in test |
| 4 | Band renders `guard` from the snapshot only; no `tool.call` hook registered (Check 77 greps `on('tool.call'` in cockpit mods → fail) | `bad-tool-call-hook` fixture fails |
| 5 | `valves.source = "none"` until t-3021; no valve argv on READ until then | snapshot test asserts `source` ∈ {none, hands} |
| 6 | bootstrap 7c/7d; Check 77 (d) FAIL on absent CLI; ci pinned install; `mods-drift.yml`; probe degrade | `--check` temp-HOME test; CI run; probe unit tests |

## Task map

| Section | Task |
|---|---|
| `_shared`, Check 77, `mods-check.sh`, ci steps, drift workflow, `tsc` dev dep | t-3427 |
| `cockpit snapshot`, `cockpit log-event`, `ops cockpit`, cache | t-3428 |
| `cockpit-band` | t-3429 |
| `cockpit-pane` (prototype → `mods/`, `/brana` + `/board` alias, log-event calls) | t-3387 |
| remind entry, day-14 review, week-6 re-eval | t-3432 |
| bootstrap 7c/7d | t-3427 (infra) — or t-3387 if sequencing prefers; decide at DECOMPOSE of t-3427 |

## Documentation plan

- [ ] **Tech doc** — this file → `shipped` at the end of t-3387; Changelog per task.
- [ ] **User guide** — `docs/guide/features/cockpit.md` (t-3434): open, keys, subcommands, fullscreen note, what shows where.
- [ ] **Existing docs** — `the-brana.md` §Gate surface line (t-3433); `docs/README.md` row (this task); `plugin-structure.md` "Plugin vs Bootstrap" table gains a **Mods (`mods/`)** row (this task).

## Challenger findings

_(pending — context-isolated pass before user review)_

## Changelog

- 2026-10-03: spec drafted (t-3425) from ADR-096 + spike t-3426 + prototype.
