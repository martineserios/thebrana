---
title: Full-power ruflo trial — v3.55 scratch install, every dormant feature on
status: setup-complete, runs-pending
task: t-3488
produced_by: /brana:build spike (2026-10-07)
depends_on: ADR-059, ADR-095 (d8), ADR-096
see_also: docs/architecture/features/ruflo-mcp-tool-classification.md, docs/research/substrate-leverage-audit.md
---

# Full-power ruflo trial (t-3488)

Every prior ruflo verdict (ADR-059, the ~150-tool classification, ADR-095 d8) tested ruflo **as
installed**: v3.34, 26/26 hooks disabled, 0 policy rules, guidance never compiled, daemon off,
0 loop-worker instances, no provider, no mods. "Unused" and "fake" probe identically. This trial
runs ruflo 3.55 at full power **in isolation** so the next decision rests on a run.

Owner: Martín · Kill rule (strict, pre-registered 2026-10-07): close as *no adoption* unless
**tokens/session drop ≥15 % vs baseline AND gate parity is 6/6**; decide by **2026-10-14**.
Ollama arm **skipped** by owner decision (no GPU, ~3 GB free RAM) — only no-model features are measured.

## Isolation (never touches the live install)

| What | Where | Why |
|---|---|---|
| ruflo + deps | `~/enter_thebrana/ruflo-trial/node_modules` (local `npm install`, exact pins, no `-g`, no `npx`) | ADR-033 |
| project | `~/enter_thebrana/ruflo-trial/proj` (own git repo on `dev`) | `ruflo init` rewrites `.claude/settings.json` in cwd |
| ruflo HOME | `HOME=~/enter_thebrana/ruflo-trial/home` for every `ruflo` command | `.swarm`, `.claude-flow` land in scratch |
| memory DB | `CLAUDE_FLOW_MEMORY_PATH=~/enter_thebrana/ruflo-trial/memory` | sole-copy rows in the live DB (ADR-095 d7/d8) |
| Claude Code config | `CLAUDE_CONFIG_DIR=~/enter_thebrana/ruflo-trial/home/.claude` for the parity/mods arm | marketplace clone + plugins stay out of `~/.claude` |
| real `~/.claude` | md5 of CLAUDE.md + settings.json + ~/.claude.json **unchanged** before/after init | verified 2026-10-07 |

Pins: see `PIN.txt` in the trial dir (ruflo 3.55.0 · @claude-flow/guidance 3.0.0 · marketplace
`ruvnet/ruflo@5693bf36` 2026-10-07T12:49-07:00 · claude 2.1.293 · node v22.22.3).

## What setup alone found (2026-10-07)

1. **The npm package is a shell.** `ruflo@3.55.0` ships 8 of the 37 `@claude-flow/*` packages its
   CLI imports and 9 of 17 `@ruvector/*` are absent. `@claude-flow/core` is imported but **not
   published on npm**. 12 core packages were installed explicitly (mcp, swarm, claims, embeddings,
   performance, testing, plugins, aidefence, integration, teammate-plugin, browser, codex); 15
   domain plugins (healthcare, legal, financial, quantum…) left out. "Full power" is not a flag — it
   is a dependency list nobody installs by default.
2. **Embeddings fall back to hash vectors "which carry no semantic meaning"** until
   `@claude-flow/embeddings` is installed. After install: Transformers.js MiniLM-L6-v2, 384-d,
   5.4 s cold generate.
3. **`guidance compile` extracted 55 rules from brana's 32 rule files** (auto-ids AUTO-001…055,
   Constitution: 0 — nothing marked always-active). `guidance retrieve` runs in ~4 ms but is
   **keyword/intent-based, not semantic**: for *"create a new branch for a bugfix and commit it"*
   it returned *verify-before-done*, *never save files to root*, *graphify query*, *type safety*,
   *do not poll* — none of the git-discipline/worktree rules — and the ranking was byte-identical
   before and after the real embedder was wired. Measurement (c) data point #1: 0/5 relevant.
4. **Built-in `guidance gates` fired on nothing**: `git checkout -b feature/x` → `[]`;
   content `SLACK_TOKEN=xoxb-EXAMPLE…` (Slack-token shape) → `null`. The secret detector did not catch it —
   while brana's `secret-scan.sh` **blocked the commit of this very file** until the token was marked EXAMPLE.
5. **`ruflo init` wrote `.mcp.json` as `npx -y ruflo@latest mcp start`** — an unpinned `@latest`
   inside the product's own init (ADR-033 violation class). Rewritten to the local binary.
6. **Mods are not in the npm package.** They load only from a GitHub marketplace clone
   (`git@github.com:ruvnet/ruflo.git`, 218 MB, HEAD at install time = unpinned). This is the
   "second code lane" from the challenge, live. Pinned here by recording the SHA.
7. **Mod engine-call audit at 5693bf3** (`claude plugin validate --json` + grep, no auth needed):
   - `ruflo-mods`: `$.tool.check` ×38, `$.fs.*` ×35, **`$.agent.spawn`/`offer` ×19**,
     `$.tool.call` ×13, `$.process.spawn` ×2, `$.ruflo.*` ×5 — **no `$.model`, no `$.http`**.
   - `ruflo-swarm`: `$.ui.render` ×36, `$.process.run` ×4, `$.agent.spawn` ×3, `$.agent.list` ×3.
   - `ruflo-console`: `$.ui.mount` ×68, **`$.http.fetch` ×4** — a mod making network calls (ADR-096 Law 3 class).
   So measurement (g): ruflo-mods makes no model call of its own, but it and ruflo-swarm **can spawn host
   subagents**, which bill the plan through the ordinary Task path. Settings written by init also set
   `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`.
8. **`policy init` refuses non-interactive terminals** ("policy administration requires an interactive
   local terminal") — a good property, and a manual step for the run session.
9. ruflo's own hook registry (`ruflo hooks list`) still shows **26/26 disabled** after `init --full`;
   the Claude Code side got 7 event types wired to `hook-handler.cjs`. The two registries are separate.
10. **`fixtures.sh gates` → built-in `guidance gates` fired on 0/4** command/content cases
    (`git checkout -b`, commit on main, `xoxb-` Slack token, `Co-Authored-By` trailer): every result `[]`/`null`.
    Measurement (b) path (1) = 0/6 before any live session. The compiled brana rules are *retrievable*
    (poorly) but **not enforced** by `gates`; only the live `tool.check`/policy path can still score.
    brana's own hook blocked the same trailer string live the moment it appeared in a Bash call.

## Measurements (pre-registered; fill from the run, never infer)

| # | Measure | Method | Baseline | Trial | Verdict |
|---|---|---|---|---|---|
| a | tokens / session, same 3–5 tasks | brana session-end records vs trial session `--output-format json` usage | | | |
| b | gate parity 6/6 | `fixtures.sh` cases against (1) `guidance gates`, (2) live trial session `tool.check`/policy | brana: 6/6 BLOCK (no-attribution case fired live on 2026-10-07 when the fixture string appeared in a Bash call from the thebrana checkout) | | |
| c | routing / guidance hit rate | `guidance retrieve -t` on each task description — relevant rules in top-5 | n/a | **#1: 0/5** | |
| d | latency: per tool call, session start | hook timings vs brana's 46 hooks | | | |
| e | Ollama worker correctness | **skipped** (owner decision) | — | — | — |
| f | does a mod's `$.model` bill the plan | **answered** by thebrana-a7 2026-10-07: **yes**, invisible to cost/usage/rateLimits | — | — | ADR-096 OQ1 → a7 |
| g | ruflo-mods `$.model`/`$.http` use + hidden spend | validate listing + grep at pinned SHA | — | **none; agent.spawn ×19; console http.fetch ×4** | |

## Run-session checklist (outside interactive hours)

1. `bash setup.sh` — idempotent; re-asserts pins and prints the manual steps.
2. **Manual, interactive terminal:** `cd ~/enter_thebrana/ruflo-trial/proj && HOME=~/enter_thebrana/ruflo-trial/home ../node_modules/.bin/ruflo policy init --mode enforce`, then add the 6 gate rules.
3. **Parity/mods arm auth:** `cp ~/.claude/.credentials.json ~/enter_thebrana/ruflo-trial/home/.claude/ && chmod 600 …` — **delete it when the run ends**. Then `CLAUDE_CONFIG_DIR=… claude plugin install ruflo-mods@ruflo --scope project` (and swarm/console only if measuring them).
4. `HOME=… ruflo daemon start` · `ruflo autopilot enable` (wire the Stop hook to `autopilot check`).
5. Run the fixtures (`fixtures.sh list`) through both paths; record (b).
6. Run the 3–5 tasks once in a plain brana session (baseline) and once in the trial session; record (a), (c), (d).
7. Never pass `--claude` without `--no-auto-permissions`; never run anything against the thebrana checkout.
8. Fill the table, apply the kill rule, write the per-feature verdict (adopt behind a brana seam / pattern only / closed).
9. Teardown: `ruflo daemon stop`; remove the copied credential; leave the trial dir for re-runs.

## Feature-class verdicts (fill after the run)

| Class | Verdict | Evidence |
|---|---|---|
| guidance control plane (compile/retrieve/gates) | | |
| policy engine (ADR-324) as gate host | | |
| mods: routeContext · tool.check · cost ladder · agentTrim · compactCarry | | |
| hooks / trajectory learning / route | | |
| memory: RaBitQ · KGE · graph store, fed | | |
| daemon + loop-workers | | |
| autopilot + Stop hook | | |
| metaharness_score / mcp_scan | | |
