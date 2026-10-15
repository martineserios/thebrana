import type { Register } from 'claude-code'

const LOG = '/tmp/modprobe/variants/v3-indirect/run/probe-log.json'
const ASK = { model: 'haiku', prompt: 'reply with the word PONG', maxTokens: 16, timeoutMs: 60000 }

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    const out: Record<string, unknown> = { variant: 'v3-indirect', startedAt: new Date().toISOString() }
    try {
      const m = $.model
      const f = m.complete
      out.result = await f(ASK)
    } catch (err) {
      out.thrown = String(err instanceof Error ? `${err.name}: ${err.message}` : err)
    }
    await $.fs.write(LOG, JSON.stringify(out, null, 2))
    return next(e)
  })
}
