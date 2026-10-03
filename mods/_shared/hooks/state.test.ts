import { expect, test } from 'claude-code/testing'

import { SCHEMA, stamp, valid } from './state'

type Board = { schema: number; rows: string[] }
const isBoard = (v: unknown): v is Board => typeof v === 'object' && v !== null && Array.isArray((v as Board).rows)

test('stamp adds the current schema to the data', () => {
  expect(stamp({ rows: ['a'] })).toEqual({ schema: SCHEMA, rows: ['a'] })
})

test('a valid value of the current schema passes through as the same reference', () => {
  const v = { schema: SCHEMA, rows: ['a', 'b'] }
  expect(valid(v, isBoard)).toBe(v)
})

test('a value left by an older schema is discarded (null), even when its shape still fits', () => {
  expect(valid({ schema: SCHEMA - 1, rows: ['a'] }, isBoard)).toBe(null)
})

test('a newer schema (a downgrade) is discarded too — only an exact match is a cache hit', () => {
  expect(valid({ schema: SCHEMA + 1, rows: ['a'] }, isBoard)).toBe(null)
})

test('malformed values are discarded: null, undefined, a string, an array, an object without schema', () => {
  for (const v of [null, undefined, 'rows', ['a'], { rows: ['a'] }, { schema: 'x', rows: [] }, 42]) {
    expect(valid(v, isBoard)).toBe(null)
  }
})

test('the right schema with the wrong shape is discarded — the guard decides, the schema only gates', () => {
  expect(valid({ schema: SCHEMA, rows: 'not-an-array' }, isBoard)).toBe(null)
})

test('an explicit schema number can be passed for an atom that versions independently', () => {
  expect(valid({ schema: 7, rows: [] }, isBoard, 7)).toEqual({ schema: 7, rows: [] })
  expect(valid({ schema: SCHEMA, rows: [] }, isBoard, 7)).toBe(null)
})
