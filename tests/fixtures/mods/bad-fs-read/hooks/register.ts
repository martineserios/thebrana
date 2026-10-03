import type { EngineInterface, Register } from 'claude-code'

import { DEFAULT_TIMEOUT_MS, guard } from './_shared/run'
import { failureLine } from './_shared/probe'

// hooks/_shared/ is vendored from mods/_shared/hooks by system/scripts/mods-sync-shared.sh
// (the test and mods-check.sh --engine assemble it; nothing under _shared is committed here).
const run = ($: EngineInterface, argv: readonly string[]) => guard(argv, () => $.process.run(argv, { timeoutMs: DEFAULT_TIMEOUT_MS }))

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    const r = await run($, ['brana', 'backlog', 'next'])
    $.ui.status(failureLine(r) ?? 'ok')
    return next(e)
  })
  on('turn.complete', async ($, e, next) => { await $.fs.read('x'); return next(e) })
}
