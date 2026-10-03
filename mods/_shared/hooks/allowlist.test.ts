import { expect, test } from 'claude-code/testing'

import { READ, WRITE, check } from './allowlist'

// Exact equality on purpose (cockpit.md §_shared/allowlist.ts, ADR-096 Law 3/5): the valves
// verb joins READ in t-3021's landing commit and nowhere else, so any `hands`/valve argv
// appearing here before then fails this test.
test('READ is exactly the spec list', () => {
  expect(READ).toEqual([
    ['brana', 'cockpit', 'snapshot', '--json'],
    ['brana', 'backlog', 'get'],
    ['brana', 'backlog', 'query'],
    ['brana', 'backlog', 'next'],
    ['brana', 'backlog', 'search'],
    ['brana', 'backlog', 'blocked'],
  ])
})

test('WRITE is exactly log-event — the one automatic-and-logged write', () => {
  expect(WRITE).toEqual([['brana', 'cockpit', 'log-event']])
})

test('a listed READ prefix allows extra args after it', () => {
  expect(check(['brana', 'backlog', 'get', 't-3427'])).toEqual({ allowed: true, kind: 'read' })
  expect(check(['brana', 'cockpit', 'snapshot', '--json'])).toEqual({ allowed: true, kind: 'read' })
})

test('a WRITE prefix is allowed and labelled write', () => {
  expect(check(['brana', 'cockpit', 'log-event', '--kind', 'open'])).toEqual({ allowed: true, kind: 'write' })
})

test('brana backlog set is denied with a reason naming the argv', () => {
  const v = check(['brana', 'backlog', 'set', 't-1', 'status', 'completed'])
  expect(v.allowed).toBe(false)
  if (!v.allowed) expect(v.reason).toContain('brana backlog set')
})

test('prefix abuse: "get; rm" is one token and does not match "get"', () => {
  expect(check(['brana', 'backlog', 'get; rm', '-rf']).allowed).toBe(false)
})

test('prefix abuse: a token that merely starts with a listed word does not match', () => {
  expect(check(['brana', 'backlog', 'getx']).allowed).toBe(false)
  expect(check(['brana', 'backlogs', 'get']).allowed).toBe(false)
})

test('argv shorter than every prefix is denied, empty argv included', () => {
  expect(check(['brana', 'backlog']).allowed).toBe(false)
  expect(check(['brana']).allowed).toBe(false)
  expect(check([]).allowed).toBe(false)
})

test('nothing outside brana is ever allowed', () => {
  for (const argv of [['git', 'status'], ['gh', 'pr', 'list'], ['curl', 'x'], ['sh', '-c', 'brana backlog get'], ['claude', '-p', 'hi'], ['brana', 'recall', 'x'], ['brana', 'agy', 'x']]) {
    expect(check(argv).allowed).toBe(false)
  }
})

test('shell metacharacters after a listed prefix are plain argv (process.run has no shell)', () => {
  expect(check(['brana', 'backlog', 'search', 'a; rm -rf /']).allowed).toBe(true)
})
