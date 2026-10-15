import type { Register } from 'claude-code'

const LOG = '/tmp/modprobe/variants/v2-destructured/run/probe-log.json'
const ASK = { model: 'haiku', prompt: 'reply with the word PONG', maxTokens: 16, timeoutMs: 60000 }

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    const out: Record<string, unknown> = { variant: 'v2-destructured', startedAt: new Date().toISOString() }
    try {
      const { model } = $
      out.result = await model.complete(ASK)
    } catch (err) {
      out.thrown = String(err instanceof Error ? `${err.name}: ${err.message}` : err)
    }
    await $.fs.write(LOG, JSON.stringify(out, null, 2))
    return next(e)
  })
}
