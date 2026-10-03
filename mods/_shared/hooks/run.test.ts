import { expect, test } from 'claude-code/testing'

import { DEFAULT_TIMEOUT_MS, guard } from './run'

const ok = { exitCode: 0, stdout: '[]', stderr: '' }
const never = async () => {
  throw new Error('exec must not run')
}

test('a denied argv never runs exec', async () => {
  let calls = 0
  const r = await guard(['brana', 'backlog', 'set', 't-1', 'status', 'completed'], async () => {
    calls += 1
    return ok
  })
  expect(r.denied).toBe(true)
  if (r.denied) expect(r.reason).toContain('brana backlog set')
  expect(calls).toBe(0)
})

test('empty argv is denied before exec', async () => {
  expect((await guard([], never)).denied).toBe(true)
})

test('a listed argv runs exec once and returns its result', async () => {
  let calls = 0
  const r = await guard(['brana', 'backlog', 'get', 't-3427'], async () => {
    calls += 1
    return ok
  })
  expect(r).toEqual({ denied: false, failed: false, exitCode: 0, stdout: '[]', stderr: '' })
  expect(calls).toBe(1)
})

test('a non-zero exit is a result, not a failure', async () => {
  const r = await guard(['brana', 'backlog', 'get', 't-0'], async () => ({ exitCode: 2, stdout: '', stderr: 'no such task' }))
  expect(r).toEqual({ denied: false, failed: false, exitCode: 2, stdout: '', stderr: 'no such task' })
})

test('an exec that rejects (brana not on PATH, timeout) is reported, never thrown', async () => {
  const r = await guard(['brana', 'cockpit', 'snapshot', '--json'], async () => {
    throw new Error('spawn brana ENOENT')
  })
  expect(r.denied).toBe(false)
  if (!r.denied) {
    expect(r.failed).toBe(true)
    expect(r.exitCode).toBe(-1)
    expect(r.stderr).toContain('ENOENT')
  }
})

test('a non-Error rejection is stringified, not swallowed', async () => {
  const r = await guard(['brana', 'backlog', 'next'], async () => {
    throw 'boom'
  })
  expect(!r.denied && r.failed && r.stderr === 'boom').toBe(true)
})

test("a WRITE verb runs like a read (the confirm button is the caller's job, the log is the CLI's)", async () => {
  const r = await guard(['brana', 'cockpit', 'log-event', '--kind', 'open'], async () => ({ exitCode: 0, stdout: '', stderr: '' }))
  expect(r.denied).toBe(false)
})

// The canonical adapter line lives in register.ts (an inline plugin compiled from this
// file cannot see a top-level function declared here — the engine's rule is per hooks
// module). Drive it through the real engine via the plugin's /cockpit-shared-run command.
const START = { surface: 'terminal', isInteractive: true, cwd: '/w' } as const
const drive = async ($: Parameters<Parameters<typeof test>[1] extends infer F ? (F extends (...a: infer A) => unknown ? (...a: A) => unknown : never) : never>[0], args: string) => {
  const r = await $.command.run({ command: 'cockpit-shared-run', args })
  return JSON.parse(r.text ?? 'null')
}

test('the canonical adapter line loads and reaches $.process.run with argv + 15 s timeout', async ($, on) => {
  let seen: { argv: readonly string[]; timeoutMs?: number } | null = null
  on('session.start', (_$, e) => ({ cwd: e.cwd }))
  on('command.register', (_$, e) => ({ value: { command: e.name } }))
  on('process.run', (_$, e) => {
    seen = { argv: e.argv, timeoutMs: e.init?.timeoutMs }
    return { value: ok }
  })
  await $.session.start(START)
  const out = await drive($, 'brana backlog get t-3427')
  expect(seen).toEqual({ argv: ['brana', 'backlog', 'get', 't-3427'], timeoutMs: DEFAULT_TIMEOUT_MS })
  expect(out).toEqual({ denied: false, failed: false, exitCode: 0, stdout: '[]', stderr: '' })
})

test('through the adapter, a denied argv never reaches the host', async ($, on) => {
  let calls = 0
  on('session.start', (_$, e) => ({ cwd: e.cwd }))
  on('command.register', (_$, e) => ({ value: { command: e.name } }))
  on('process.run', () => {
    calls += 1
    return { value: ok }
  })
  await $.session.start(START)
  const out = await drive($, 'git status')
  expect(out.denied).toBe(true)
  expect(calls).toBe(0)
})
