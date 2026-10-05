// Parse + age for `brana cockpit snapshot --json` (cockpit.md §Rust verbs, t-3428).
// The field list is the spec's: adding a field is a spec change. The parser is strict on
// purpose — a partial or mistyped snapshot returns null and the band shows its failure
// line rather than drawing a number that is not there.
export type Health = 'ok' | 'warn' | 'fail'
export type ValveSource = 'none' | 'hands'
export type Presence = 'present' | 'missing'

export type Snapshot = {
  at: string
  ttl_s: number
  age_s: number
  backlog: { in_progress: number; next: number; blocked: number }
  valves: { waiting: number; source: ValveSource }
  ops: { health: Health; failing_jobs: string[] }
  orbit: { armed: boolean; kill_switch: boolean }
  reminders_due: number
  worktrees: number
  guard: { checkout_deny_file: Presence }
}

const isObj = (v: unknown): v is Record<string, unknown> => typeof v === 'object' && v !== null && !Array.isArray(v)
const isNum = (v: unknown): v is number => typeof v === 'number' && Number.isFinite(v)
const isBool = (v: unknown): v is boolean => typeof v === 'boolean'
const isStr = (v: unknown): v is string => typeof v === 'string'
const oneOf = <T extends string>(v: unknown, set: readonly T[]): v is T => isStr(v) && (set as readonly string[]).includes(v)

export function isSnapshot(v: unknown): v is Snapshot {
  if (!isObj(v)) return false
  const { backlog, valves, ops, orbit, guard } = v
  return (
    isStr(v.at) && isNum(v.ttl_s) && isNum(v.age_s) &&
    isObj(backlog) && isNum(backlog.in_progress) && isNum(backlog.next) && isNum(backlog.blocked) &&
    isObj(valves) && isNum(valves.waiting) && oneOf(valves.source, ['none', 'hands'] as const) &&
    isObj(ops) && oneOf(ops.health, ['ok', 'warn', 'fail'] as const) && Array.isArray(ops.failing_jobs) && ops.failing_jobs.every(isStr) &&
    isObj(orbit) && isBool(orbit.armed) && isBool(orbit.kill_switch) &&
    isNum(v.reminders_due) && isNum(v.worktrees) &&
    isObj(guard) && oneOf(guard.checkout_deny_file, ['present', 'missing'] as const)
  )
}

// brana may print a note line before the JSON object (the prototype saw "note: N task(s)
// excluded" before an array); parse from the first `{`.
export function parseSnapshot(text: string): Snapshot | null {
  const start = text.indexOf('{')
  if (start < 0) return null
  try {
    const v: unknown = JSON.parse(text.slice(start))
    return isSnapshot(v) ? v : null
  } catch {
    return null
  }
}

export const STALE_MS = 5 * 60 * 1000

// readAtMs: when the mod last got a snapshot (null = never). Stale after five minutes —
// the prototype's lesson: say so rather than draw old numbers as current.
export const isStale = (readAtMs: number | null, nowMs: number): boolean => readAtMs === null || nowMs - readAtMs > STALE_MS

export function ageText(seconds: number): string {
  const s = Math.max(0, Math.floor(seconds))
  if (s < 60) return `${s}s`
  if (s < 3600) return `${Math.floor(s / 60)}m`
  return `${Math.floor(s / 3600)}h`
}
