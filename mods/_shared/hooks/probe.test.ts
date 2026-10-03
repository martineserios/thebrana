import { expect, test } from 'claude-code/testing'

import { SUPPORTED, UNTESTED_LINE, failureLine, probe } from './probe'

test('SUPPORTED lists release cores only and contains the CI pin', () => {
  expect(SUPPORTED).toContain('2.1.288')
  for (const v of SUPPORTED) expect(/^\d+\.\d+\.\d+$/.test(v)).toBe(true)
})

test('a supported release is ok', () => {
  expect(probe({ version: '2.1.288', base: '2.1.288', builtAt: '2026-10-01T00:00:00Z' })).toBe('ok')
})

test('a development build of a supported release is untested', () => {
  expect(probe({ version: '2.1.288-dev.20261003.t101500.sha1a2b3c4', base: '2.1.288-dev' })).toBe('untested')
})

test('a version with no release base is untested', () => {
  expect(probe({ version: 'local' })).toBe('untested')
})

test('a release outside SUPPORTED is untested, older and newer alike', () => {
  expect(probe({ version: '2.1.200', base: '2.1.200' })).toBe('untested')
  expect(probe({ version: '9.0.0', base: '9.0.0' })).toBe('untested')
})

test('the one visible line names the engine version and what is supported', () => {
  const line = UNTESTED_LINE({ version: '2.1.200', base: '2.1.200' })
  expect(line).toContain('2.1.200')
  expect(line).toContain('2.1.288')
  expect(line).toContain('statusline only')
})

test('failureLine: a denied run names the denial; an unreachable brana is named; a plain exit code is not a failure', () => {
  expect(failureLine({ denied: true, reason: 'argv not on the READ or WRITE allowlist: git status' })).toContain('denied')
  expect(failureLine({ denied: false, failed: true, exitCode: -1, stdout: '', stderr: 'spawn brana ENOENT' })).toBe('cockpit: brana unreachable (not on PATH)')
  expect(failureLine({ denied: false, failed: true, exitCode: -1, stdout: '', stderr: 'timed out after 15000 ms\nmore' })).toBe('cockpit: brana failed — timed out after 15000 ms')
  expect(failureLine({ denied: false, failed: false, exitCode: 2, stdout: '', stderr: 'no such task' })).toBe(null)
  expect(failureLine({ denied: false, failed: false, exitCode: 0, stdout: '{}', stderr: '' })).toBe(null)
})
