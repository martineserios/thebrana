import type { ProcessRunResult } from 'claude-code'

import { check } from './allowlist'

// The one gate every host command passes through (ADR-096 Law 3).
//
// Why guard(argv, exec) and not run($, argv): the engine's scanner refuses a hooks module
// that passes `$` to a function it did not declare at its own top level ("$ is passed to
// "run", which is not a function declared at the top of this file"), so a shared
// $-taking run() is impossible by construction. Instead every mod's hooks module carries
// exactly this one adapter line at its top level — validate Check 77a allows
// `$.process.run(` nowhere else in mods/**:
//
//   const run = ($: EngineInterface, argv: readonly string[]) => guard(argv, () => $.process.run(argv, { timeoutMs: DEFAULT_TIMEOUT_MS }))
//
// `plugin validate` then reports the call as `$.process.run (via run)`, which Check 77b
// parses against the allowed set.
export type RunResult =
  | { denied: true; reason: string }
  | { denied: false; failed: boolean; exitCode: number; stdout: string; stderr: string }

export const DEFAULT_TIMEOUT_MS = 15000

export async function guard(argv: readonly string[], exec: () => Promise<ProcessRunResult>): Promise<RunResult> {
  const verdict = check(argv)
  if (!verdict.allowed) return { denied: true, reason: verdict.reason }
  try {
    const r = await exec()
    return { denied: false, failed: false, exitCode: r.exitCode, stdout: r.stdout, stderr: r.stderr }
  } catch (err) {
    // Cannot start (brana not on PATH), timed out, or the host refused: a result, never a
    // throw — a hook that throws is skipped and the band draws nothing.
    return { denied: false, failed: true, exitCode: -1, stdout: '', stderr: String(err instanceof Error ? err.message : err) }
  }
}
