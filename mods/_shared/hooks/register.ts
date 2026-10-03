import type { EngineInterface, Register } from 'claude-code'

import { DEFAULT_TIMEOUT_MS, guard } from './run'

// cockpit-shared is never installed. It exists so `claude plugin test mods/_shared` runs
// the *.test.ts beside it (the engine skips a folder with no hooks module: exit 0, no tests
// run — t-3446) and so the canonical adapter line below is exercised through the real
// engine. The files here are the source of truth, vendored into mods/<mod>/hooks/_shared/.
//
// The adapter line, byte-for-byte what every mod carries at its top level (run.ts explains
// why it cannot live in a shared file; Check 77a allows `$.process.run(` nowhere else):
const run = ($: EngineInterface, argv: readonly string[]) => guard(argv, () => $.process.run(argv, { timeoutMs: DEFAULT_TIMEOUT_MS }))

const COMMAND = 'cockpit-shared-run'

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    // Dev aid when loaded with --plugin-dir mods/_shared: `/cockpit-shared-run brana backlog get t-1`
    // prints the guard's verdict and result as JSON. In tests it is the handle that drives run().
    await $.command.register({ name: COMMAND, description: 'cockpit-shared dev aid: run an argv through the allowlist guard; prints the RunResult as JSON' })
    return next(e)
  })

  on('command.run', { command: COMMAND }, async ($, e) => {
    const argv = (e.args ?? '').split(/\s+/).filter(Boolean)
    return { text: JSON.stringify(await run($, argv)) }
  })
}
