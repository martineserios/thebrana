// $.state is a CACHE — the CLI is the source of truth; never persist a decision or an
// in-flight action here (ADR-096 Law 2; cockpit.md §_shared/state.ts).
//
// Every atom's value is `{ schema: N, ...data }`. A mod reads with
//   const v = valid(await read($, atom), isShape)
//   if (v === null) await update($, atom, () => null)   // discard what an older mod left
// (two engine calls in the hooks module — a shared $-taking readValid is refused by the
// engine's scanner, see run.ts). Bumping SCHEMA invalidates every atom at once; an atom that
// versions on its own passes its number explicitly.
export const SCHEMA = 1

export type Stamped<T extends object> = { schema: number } & T

export const stamp = <T extends object>(data: T): Stamped<T> => ({ schema: SCHEMA, ...data })

export function valid<T>(value: unknown, guard: (v: unknown) => v is T, schema: number = SCHEMA): T | null {
  if (typeof value !== 'object' || value === null || Array.isArray(value)) return null
  if ((value as { schema?: unknown }).schema !== schema) return null
  return guard(value) ? value : null
}
