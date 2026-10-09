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
