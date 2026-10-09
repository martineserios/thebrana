# modprobe — ADR-096 open question 1: does a mod's `$.model.complete` bill the subscription?

Date: 2026-10-07. Engine: `claude 2.1.293 (Claude Code)`, built 2026-10-07T06:36:42Z.
Auth: `claude auth status` → `loggedIn: true, authMethod: claude.ai, apiProvider: firstParty, subscriptionType: max`.
Env: `ANTHROPIC_API_KEY` and `ANTHROPIC_AUTH_TOKEN` unset (and explicitly `env -u` on every run). Run header reports `"apiKeySource":"none"`.

## VERDICT: BILLS-SUBSCRIPTION

`$.model.complete` succeeded keyless, twice per run, on two runs, with no API key anywhere in the environment. The only credential present was the claude.ai OAuth login. The debug log shows the call as an ordinary `/v1/messages` request on the session's own client (`source=side_query`) carrying the same `x-anthropic-billing-header` (`cc_entrypoint=sdk-cli`) the main turn sends. The API docs for the noun say it outright: "Completions through the session's own client and credentials."

Two caveats on what "bills the subscription" is measurable as:
1. The 5h/7d windows did not visibly move (39 % / 67 % before and after). A 16-in/5-out haiku call cannot move a whole percentage point, so this is not evidence either way; it is below the gauge's resolution.
2. The mod's call is **invisible to the session's own ledger**: `$.session.usage().cost.usd` is identical before and after each call (0 and 0.6348…), the final `modelUsage` lists only `claude-fable-5-1`, and the session-start call did not populate `rateLimits` (still `[]` after it answered). So `/cost`, the `-p` result JSON and the status line's quota reading will not show a mod's model spend. The only record is the `usage` on the call's own result and the debug-log line `$.model.complete (<plugin>): <model> answered in <ms>`.

Severity implication for Law 3: a leak of `$.model.complete` into a mod spends the person's subscription quota silently, with no trace in the session's cost/usage surfaces. Model resolves through the `--model` allowlist (`haiku` → `claude-haiku-5-5`).

## Mod source (final, run 2)

`mod/.claude-plugin/plugin.json`
```json
{ "name": "modprobe", "version": "0.1.0", "description": "ADR-096 OQ1 probe: does $.model.complete work keyless on a subscription session?", "author": { "name": "brana" } }
```
`mod/hooks/hooks.json`
```json
{ "modules": ["./register.ts"] }
```
`mod/hooks/register.ts`
```ts
import type { EngineInterface, Register } from 'claude-code'

// Scratch probe for ADR-096 open question 1. Twice per session (session.start, before any
// main-thread request; turn.complete, after the main thread's first API response so
// rateLimits has a reading): snapshot usage, make one keyless model call through the
// engine's own client, snapshot usage again, write JSON to <DIR>/probe-log-<phase>.json.
const DIR = '/tmp/claude-1000/-home-martineserios-enter-thebrana-thebrana/1e8af577-1266-4cc3-9fb1-0cca113c8d15/scratchpad/modprobe/run'

async function probe($: EngineInterface, phase: string): Promise<void> {
  const out: Record<string, unknown> = { phase, startedAt: new Date().toISOString() }
  try {
    out.version = await $.session.version()
    out.usageBefore = await $.session.usage()
    const t0 = Date.now()
    out.result = await $.model.complete({ model: 'haiku', prompt: 'reply with the word PONG', maxTokens: 16, timeoutMs: 60000 })
    out.elapsedMs = Date.now() - t0
    out.usageAfter = await $.session.usage()
  } catch (err) {
    out.thrown = String(err instanceof Error ? `${err.name}: ${err.message}` : err)
  }
  await $.fs.write(`${DIR}/probe-log-${phase}.json`, JSON.stringify(out, null, 2))
  $.ui.log(`modprobe: wrote probe-log-${phase}.json`)
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => { await probe($, 'session-start'); return next(e) })
  on('turn.complete', async ($, e, next) => { await probe($, 'turn-complete'); return next(e) })
}
```
Run 1 used the same module with only the `session.start` hook and a single log path (`run/probe-log.json`); its result was identical (`PONG`, usage 16/5, cost and rateLimits unchanged).

## Commands run (exact)

```sh
claude plugin validate $S/mod            # $S = this folder
# → ✔ Validation passed; hooks: session.start, turn.complete;
#   calls: $.fs.write, $.model.complete, $.session.usage, $.session.version, $.ui.log (via probe)

cd $S/run && env -u ANTHROPIC_API_KEY -u ANTHROPIC_AUTH_TOKEN -u CLAUDE_CODE_CHILD_SESSION \
  -u CLAUDE_CODE_MESSAGING_SOCKET -u CLAUDE_CODE_MESSAGING_TOKEN -u CLAUDE_CODE_BRIDGE_SESSION_ID \
  -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CODE_SESSION_ATTENDED -u CLAUDE_CODE_ENTRYPOINT \
  timeout 120 claude -p "say ok" --max-turns 1 --plugin-dir $S/mod --output-format json \
  --debug-file $S/run/debug.log > $S/run/stdout2.json 2> $S/run/stderr2.txt
# exit 0; stderr only the "no stdin data received in 3s" warning
```
No `--dangerously-skip-permissions`. Nothing installed under `~/.claude`; no repo or settings changes. `claude plugin test` was not used: the test kit mocks `$`, so it cannot answer a billing question.

## Outputs (exact, trimmed to the relevant fields)

Run header (`stdout2.json`, `system/init`): `"apiKeySource":"none"`, `"claude_code_version":"2.1.293"`, plugin `modprobe@inline` loaded from `$S/mod`.

`run/probe-log-session-start.json` (before any main-thread request):
```json
{
  "phase": "session-start",
  "startedAt": "2026-10-07T20:47:23.718Z",
  "version": {
    "version": "2.1.293",
    "base": "2.1.293",
    "builtAt": "2026-10-07T06:36:42Z"
  },
  "usageBefore": {
    "startedAt": 1791406036655,
    "context": {
      "window": 1000000
    },
    "rateLimits": [],
    "cost": {
      "usd": 0
    }
  },
  "result": {
    "isAnswered": true,
    "text": "PONG",
    "usage": {
      "input_tokens": 16,
      "output_tokens": 5,
      "cache_read_input_tokens": 0,
      "cache_creation_input_tokens": 0
    }
  },
  "elapsedMs": 618,
  "usageAfter": {
    "startedAt": 1791406036655,
    "context": {
      "window": 1000000
    },
    "rateLimits": [],
    "cost": {
      "usd": 0
    }
  }
}```

`run/probe-log-turn-complete.json` (after the main thread's first API response):
```json
{
  "phase": "turn-complete",
  "startedAt": "2026-10-07T20:47:28.087Z",
  "version": {
    "version": "2.1.293",
    "base": "2.1.293",
    "builtAt": "2026-10-07T06:36:42Z"
  },
  "usageBefore": {
    "startedAt": 1791406036655,
    "context": {
      "tokens": 53114,
      "window": 1000000,
      "percent": 5
    },
    "rateLimits": [
      {
        "kind": "five_hour",
        "percentUsed": 39,
        "resetsAt": "2026-10-07T22:10:00.000Z"
      },
      {
        "kind": "seven_day",
        "percentUsed": 67,
        "resetsAt": "2026-10-09T06:00:00.000Z"
      }
    ],
    "cost": {
      "usd": 0.6348527500000001
    }
  },
  "result": {
    "isAnswered": true,
    "text": "PONG",
    "usage": {
      "input_tokens": 16,
      "output_tokens": 5,
      "cache_read_input_tokens": 0,
      "cache_creation_input_tokens": 0
    }
  },
  "elapsedMs": 654,
  "usageAfter": {
    "startedAt": 1791406036655,
    "context": {
      "tokens": 53114,
      "window": 1000000,
      "percent": 5
    },
    "rateLimits": [
      {
        "kind": "five_hour",
        "percentUsed": 39,
        "resetsAt": "2026-10-07T22:10:00.000Z"
      },
      {
        "kind": "seven_day",
        "percentUsed": 67,
        "resetsAt": "2026-10-09T06:00:00.000Z"
      }
    ],
    "cost": {
      "usd": 0.6348527500000001
    }
  }
}```

Result record (`stdout2.json`, `type: result`): `is_error: false`, `result: "ok"`, `total_cost_usd: 0.63485…`, `api_error_status: null`; `modelUsage` has only `claude-fable-5-1` (no haiku entry). `rate_limit_event`: five_hour 0.39, seven_day 0.67.

Debug log (`run/debug.log`), the lines for the two calls:
```
2026-10-07T20:47:23.729Z [DEBUG] attribution header x-anthropic-billing-header: cc_version=2.1.293.064; cc_entrypoint=sdk-cli; cch=00000;
2026-10-07T20:47:23.729Z [DEBUG] [dispatch] sent anthropic-dispatch-id=v2d (side query)
2026-10-07T20:47:23.731Z [DEBUG] [API REQUEST] /v1/messages x-client-request-id=c88fce5e-db51-40ef-a50e-8cc99d2f8db6 source=side_query
2026-10-07T20:47:24.344Z [DEBUG] $.model.complete (modprobe): claude-haiku-5-5 answered in 617ms, 4 chars
2026-10-07T20:47:28.741Z [DEBUG] $.model.complete (modprobe): claude-haiku-5-5 answered in 653ms, 4 chars
```

Run 1 artifacts: `run/stdout.json`, `run/stderr.txt` (empty), `run/validate.txt`. Run 2: `run/stdout2.json`, `run/stderr2.txt`, `run/validate2.txt`, `run/debug.log`, the two probe logs above.

## API facts gathered on the way (2.1.293 types, `plugin-authoring` skill)

- `$.model.complete({ model, prompt, system?, maxTokens?, effort?, timeoutMs? })` → `ModelCompleteResult`: `{ isAnswered: true, text, usage }` or `{ isAnswered: false, reason: 'api-error' | 'empty-reply' | 'aborted', ... }`. `api-error` carries `status` and an `error` kind (`authentication_failed` is one of them) — that is the arm a NEEDS-KEY outcome would have shown. Only an engine-refused request (blocked model, bad cap) rejects.
- `$.model.fork({ prompt })` asks over the session's own transcript on the main model (prefix cache).
- `$.session.usage()` → `{ startedAt, context, rateLimits, cost }`; docs: "`rateLimits` is empty off a subscription". It reflects the main thread's last response, not a mod's side query.
- `plugin validate` lists every `$` call a module makes (`$.model.complete (via probe)`), so a source-level allowlist check (ADR-096 Law 3) can catch it.

## Bypass forms (follow-up, 2026-10-07, claude 2.1.293)

Question: is `claude plugin validate --json`'s call listing reliable against the bypass forms ADR-096 Law 3's static grep covers? Four sibling copies of the mod under `variants/<name>/`, each with a single `session.start` hook making the same `haiku` PONG call through a different spelling, all four validated with `--json` and then run once under `claude -p "say ok" --max-turns 1 --plugin-dir <variant> --output-format json --debug-file <variant>/run/debug.log` (same `env -u` scrubbing as above, `< /dev/null`).

| variant | spelling | validate lists the call? | call executed? |
| --- | --- | --- | --- |
| v1-bracket | `await $['model'].complete(ASK)` | no, **refused** (exit 1): "a computed or optional member access on $" | no: module did not load (`[ERROR] hooks module v1-bracket@inline failed to load`), no probe log, no `$.model.complete` debug line |
| v2-destructured | `const { model } = $; await model.complete(ASK)` | no, **refused** (exit 1): "$ itself is bound to a name (bound, passed, spread, returned or read)" | no: module did not load, same refusal text at load |
| v3-indirect | `const m = $.model; const f = m.complete; await f(ASK)` | no, **refused** (exit 1): "$.model is used as a value (a noun of $ bound, passed or read)" | no: module did not load, same refusal text at load |
| v4-dynamic-key | `const key = ['mo','del'].join(''); await ($ as any)[key].complete(ASK)` | no, **refused** (exit 1): "a computed or optional member access on $" | no: module did not load, same refusal text at load |

Reading: the engine does not *miss* these forms and list nothing; it refuses the whole module. Every refusal ends with the same rule: "$ is always spelled $.noun.event(...) at the call site, on is always on("<event>", hook), and next.to always next.to(e, "<tier>")". The same scanner runs at `plugin validate` and at load (the debug log carries the identical message, prefixed `hooks module <name>@inline failed to load`), so the call listing is reliable by construction: a `$` call reaches the engine only in the one spelling the listing reports, and the listing attributes a call made through a top-level helper as `(via <fn>)` (the baseline mod shows `$.model.complete (via probe)`). The one spelling a static grep must also accept is that helper form: `$.model.complete` still appears literally in source, so a `grep -E '\$\.model\.'` over `mods/**` catches it.

Headless-mode observations: the four runs all completed the main turn (`result: ok`, `is_error: false`) with no stderr, because under `--output-format json` a failed module load is written to the debug log only (as the reference says); and the `system/init` record's `plugins` array still lists the variant as loaded (`<name>@inline`) even though its hooks module was refused, so that array is not evidence that a mod's hooks are live.

Artifacts per variant: `variants/<name>/run/validate.json`, `stdout.json`, `stderr.txt` (empty), `debug.log`; no `probe-log.json` was written by any variant.
