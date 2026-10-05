// The only place verbs are named (ADR-096 Law 3; cockpit.md §_shared/allowlist.ts).
// Prefix match on argv: every token of a listed prefix must equal the argv token at the
// same position; extra args are allowed only after a listed prefix. No shell is ever
// involved ($.process.run takes argv), so a metacharacter inside one token is just text.
//
// READ changes only by spec: the valves verb joins in t-3021's landing commit, nowhere
// else. allowlist.test.ts asserts both lists by exact equality.
export const READ: readonly (readonly string[])[] = [
  ['brana', 'cockpit', 'snapshot', '--json'],
  ['brana', 'backlog', 'get'],
  ['brana', 'backlog', 'query'],
  ['brana', 'backlog', 'next'],
  ['brana', 'backlog', 'search'],
  ['brana', 'backlog', 'blocked'],
]

// Automatic-and-logged; the only write without a confirm button (cockpit.md).
export const WRITE: readonly (readonly string[])[] = [['brana', 'cockpit', 'log-event']]

export type Verdict = { allowed: true; kind: 'read' | 'write' } | { allowed: false; reason: string }

const startsWith = (argv: readonly string[], prefix: readonly string[]): boolean =>
  argv.length >= prefix.length && prefix.every((tok, i) => argv[i] === tok)

export function check(argv: readonly string[]): Verdict {
  if (READ.some(p => startsWith(argv, p))) return { allowed: true, kind: 'read' }
  if (WRITE.some(p => startsWith(argv, p))) return { allowed: true, kind: 'write' }
  return { allowed: false, reason: `argv not on the READ or WRITE allowlist: ${argv.join(' ')}` }
}
