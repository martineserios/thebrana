import { expect, test } from 'claude-code/testing'

import { STALE_MS, ageText, isStale, parseSnapshot } from './snapshot'

// The field list is the spec's (cockpit.md §Rust verbs): adding a field is a spec change.
const SPEC_EXAMPLE = `{ "at": "2026-10-03T15:00:00Z", "ttl_s": 20, "age_s": 3,
  "backlog": { "in_progress": 8, "next": 15, "blocked": 23 },
  "valves": { "waiting": 0, "source": "none" },
  "ops": { "health": "ok", "failing_jobs": [] },
  "orbit": { "armed": false, "kill_switch": false },
  "reminders_due": 2,
  "worktrees": 3,
  "guard": { "checkout_deny_file": "present" } }`

test('parses the spec example byte for byte into the typed snapshot', () => {
  const s = parseSnapshot(SPEC_EXAMPLE)
  expect(s).toEqual({
    at: '2026-10-03T15:00:00Z', ttl_s: 20, age_s: 3,
    backlog: { in_progress: 8, next: 15, blocked: 23 },
    valves: { waiting: 0, source: 'none' },
    ops: { health: 'ok', failing_jobs: [] },
    orbit: { armed: false, kill_switch: false },
    reminders_due: 2, worktrees: 3,
    guard: { checkout_deny_file: 'present' },
  })
})

test('tolerates a note line brana prints before the JSON', () => {
  expect(parseSnapshot('note: cache refreshed\n' + SPEC_EXAMPLE)?.backlog.next).toBe(15)
})

test('garbage, empty output and a bare array are null, never a throw', () => {
  for (const t of ['', 'not json', '[]', 'null', '{"a":1}']) expect(parseSnapshot(t)).toBe(null)
})

test('a missing required field is null (a partial snapshot would draw lies)', () => {
  const o = JSON.parse(SPEC_EXAMPLE)
  delete o.guard
  expect(parseSnapshot(JSON.stringify(o))).toBe(null)
  const p = JSON.parse(SPEC_EXAMPLE)
  delete p.backlog.blocked
  expect(parseSnapshot(JSON.stringify(p))).toBe(null)
})

test('an enum outside the spec is null: ops.health and guard.checkout_deny_file', () => {
  const o = JSON.parse(SPEC_EXAMPLE)
  o.ops.health = 'green'
  expect(parseSnapshot(JSON.stringify(o))).toBe(null)
  const p = JSON.parse(SPEC_EXAMPLE)
  p.guard.checkout_deny_file = 'yes'
  expect(parseSnapshot(JSON.stringify(p))).toBe(null)
})

test('a wrong type is null: a count as a string', () => {
  const o = JSON.parse(SPEC_EXAMPLE)
  o.worktrees = '3'
  expect(parseSnapshot(JSON.stringify(o))).toBe(null)
})

test('the valves source accepts none now and hands later (t-3021) — nothing else', () => {
  const o = JSON.parse(SPEC_EXAMPLE)
  o.valves.source = 'hands'
  expect(parseSnapshot(JSON.stringify(o))?.valves.source).toBe('hands')
  o.valves.source = 'github'
  expect(parseSnapshot(JSON.stringify(o))).toBe(null)
})

test('ageText is short and human: seconds, minutes, hours', () => {
  expect(ageText(3)).toBe('3s')
  expect(ageText(59)).toBe('59s')
  expect(ageText(60)).toBe('1m')
  expect(ageText(3599)).toBe('59m')
  expect(ageText(3600)).toBe('1h')
  expect(ageText(-5)).toBe('0s')
})

test('isStale flips after 5 minutes since the read, not before', () => {
  expect(STALE_MS).toBe(5 * 60 * 1000)
  expect(isStale(1000, 1000 + STALE_MS)).toBe(false)
  expect(isStale(1000, 1000 + STALE_MS + 1)).toBe(true)
  expect(isStale(null, 5000)).toBe(true)
})
