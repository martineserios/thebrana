import { expect, test } from 'claude-code/testing'

import { run } from './run'

const ok = { exitCode: 0, stdout: '[]', stderr: '' }

test('a denied argv never reaches the host', async ($, on) => {
  let calls = 0
  on('process.run', () => {
    calls += 1
    return ok
  })
  const r = await run($, ['brana', 'backlog', 'set', 't-1', 'status', 'completed'])
  expect(r.denied).toBe(true)
  if (r.denied) expect(r.reason).toContain('brana backlog set')
  expect(calls).toBe(0)
})

test('a listed argv is passed through unchanged, with the default 15 s timeout, and its result returned', async ($, on) => {
  let seen: { argv: readonly string[]; timeoutMs?: number } | null = null
  on('process.run', (_$, e) => {
    seen = { argv: e.argv, timeoutMs: e.init?.timeoutMs }
    return ok
  })
  const r = await run($, ['brana', 'backlog', 'get', 't-3427'])
  expect(r).toEqual({ denied: false, failed: false, exitCode: 0, stdout: '[]', stderr: '' })
  expect(seen).toEqual({ argv: ['brana', 'backlog', 'get', 't-3427'], timeoutMs: 15000 })
})

test('a non-zero exit is a result, not a failure', async ($, on) => {
  on('process.run', () => ({ exitCode: 2, stdout: '', stderr: 'no such task' }))
  const r = await run($, ['brana', 'backlog', 'get', 't-0'])
  expect(r).toEqual({ denied: false, failed: false, exitCode: 2, stdout: '', stderr: 'no such task' })
})

test('a process.run that cannot start (brana not on PATH) is reported, never thrown', async ($, on) => {
  on('process.run', () => {
    throw new Error('spawn brana ENOENT')
  })
  const r = await run($, ['brana', 'cockpit', 'snapshot', '--json'])
  expect(r.denied).toBe(false)
  if (!r.denied) {
    expect(r.failed).toBe(true)
    expect(r.stderr).toContain('ENOENT')
  }
})

test('a WRITE verb runs like a read (the confirm button is the caller\'s job, the log is the CLI\'s)', async ($, on) => {
  let seen: readonly string[] = []
  on('process.run', (_$, e) => {
    seen = e.argv
    return { exitCode: 0, stdout: '', stderr: '' }
  })
  const r = await run($, ['brana', 'cockpit', 'log-event', '--kind', 'open'])
  expect(r.denied).toBe(false)
  expect(seen).toEqual(['brana', 'cockpit', 'log-event', '--kind', 'open'])
})
