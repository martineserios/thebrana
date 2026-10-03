import type { SessionVersion } from 'claude-code'

import type { RunResult } from './run'

// Engine-version probe (ADR-096 Law 6). Pure: called once from session.start with
// `await $.session.version()`; the result lives in a module variable. Anything but 'ok'
// means the band draws UNTESTED_LINE, the pane command replies it, and every other hook
// returns next(e) untouched.
//
// SUPPORTED holds release cores only. It moves with ci.yml's CC_VERSION pin (a test in
// tests/scripts asserts the pin is listed) and with each green mods-drift.yml run.
export const SUPPORTED: readonly string[] = ['2.1.288']

export type Probe = 'ok' | 'untested'

export function probe(v: SessionVersion): Probe {
  const base = v.base
  if (!base || base.endsWith('-dev')) return 'untested'
  return SUPPORTED.includes(base) ? 'ok' : 'untested'
}

export const UNTESTED_LINE = (v: SessionVersion): string =>
  `cockpit: engine ${v.version} untested (supported: ${SUPPORTED.join(', ')}) — statusline only`

// The one line for a run() that did not produce a result. A non-zero exit is not a
// failure here: the CLI's own stderr is the message and the caller decides.
//
// Note (t-3450 probe B): the ruflo-mods trust gate refuses a mod at plugin.register,
// before it loads, so no run() ever sees that case; bootstrap 7g is the layer that
// prevents it. The engine prints, verbatim (tests/fixtures/mods/captures/probe-b-ruflo-trust-gate.txt):
//   <mod>: refused by ruflo-mods: ruflo mod trust (modTrust=refuse-risky): <mod> process.run (runs host commands); allow it by provenance (<mod>@<marketplace>) in modTrustAllow
// This classifier covers host-level failures only.
export function failureLine(r: RunResult): string | null {
  if (r.denied) return `cockpit: denied — ${r.reason}`
  if (!r.failed) return null
  if (r.stderr.includes('ENOENT')) return 'cockpit: brana unreachable (not on PATH)'
  const first = r.stderr.split('\n')[0] ?? ''
  return `cockpit: brana failed — ${first}`
}
