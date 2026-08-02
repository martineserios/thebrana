// Orphan-cleanup safety guard — shared by bulk-index.mjs and mcp-index.mjs (t-2613).
//
// A full reindex parses markdown docs, stores one entry per section, then treats
// every *other* active key in the namespace as an orphan and hard-deletes it.
// That set subtraction is only sound if the run's output is a complete census of
// what belongs in the namespace. It is not, in three distinct ways:
//
//   1. Other producers write here. `brana knowledge process-url` stores link
//      insights as knowledge:url:{slug} (knowledge.rs:23,35-54) and feed indexing
//      writes knowledge:feed:{slug}. Neither can ever appear in a doc parse, so
//      both were orphans by construction and were deleted on every full reindex.
//   2. A run can die part-way. The 2026-08-02 run was killed at 86% (2528/2929
//      sections) and the scheduler still logged SUCCESS. Had it reached cleanup,
//      the ~14% it never re-stored would have been deleted as orphans.
//   3. A run can cover only some doc types (a category directory missing or
//      unreadable). Absence of a type in this run means "not indexed", not
//      "no longer exists".
//
// The guard therefore narrows deletion to keys that this specific run is
// genuinely authoritative about. Deletes here are hard DELETEs with no tombstone,
// so the failure mode is unrecoverable and the guard errs toward keeping.
//
// Deliberately NOT exported as a prefix denylist: a denylist would have to be
// updated every time a new producer starts writing to the namespace, and the
// cost of forgetting is silent data loss. An allowlist of doc types fails safe —
// an unrecognised producer is simply never deleted.

/**
 * The 7 doc categories a full reindex regenerates.
 * Mirrors DOC_CATEGORIES in system/scripts/index-knowledge.sh:29-37 — keep in sync.
 * Keys are built as `knowledge:{docType}:{docSlug}:{sectionSlug}` (index-knowledge.sh:158).
 */
export const DOC_DERIVED_TYPES = Object.freeze([
  'dimension',
  'decision',
  'feature',
  'architecture',
  'reflection',
  'idea',
  'research',
]);

const DOC_TYPE_SET = new Set(DOC_DERIVED_TYPES);

/**
 * Extract the producer segment from a key: `knowledge:url:x` -> `url`.
 * Returns null for keys that do not have at least two colon-separated segments.
 */
export function keyType(key) {
  if (typeof key !== 'string') return null;
  const parts = key.split(':');
  if (parts.length < 2) return null;
  return parts[1];
}

/** True when the key is one a doc reindex is capable of regenerating. */
export function isDocDerived(key) {
  const t = keyType(key);
  return t !== null && DOC_TYPE_SET.has(t);
}

/**
 * Choose which existing keys may be deleted as orphans.
 *
 * @param {object}      opts
 * @param {Iterable<string>} opts.existingKeys Keys currently active in the namespace.
 * @param {Set<string>} opts.storedKeys        Keys this run wrote.
 * @param {Set<string>} [opts.protectedKeys]   Keys this run TRIED to write but
 *                                             failed on. They are absent from
 *                                             storedKeys through no fault of
 *                                             their own, so they must not be
 *                                             read as "no longer exists".
 * @param {string}      opts.namespace         Namespace being cleaned.
 * @param {boolean}     opts.runComplete       Whether the store loop ran to the
 *                                             end. False => prune nothing.
 * @returns {string[]} keys safe to delete.
 */
export function selectOrphans({
  existingKeys,
  storedKeys,
  protectedKeys,
  namespace = 'knowledge',
  runComplete,
}) {
  // Hazard 2: only a completed run is a valid census. Callers must pass this
  // explicitly — an undefined value is treated as "not complete" so that a
  // caller which forgets to thread the flag fails safe rather than deleting.
  if (runComplete !== true) return [];

  const stored = storedKeys instanceof Set ? storedKeys : new Set(storedKeys || []);
  const failed = protectedKeys instanceof Set ? protectedKeys : new Set(protectedKeys || []);
  const existing = [...(existingKeys || [])];

  // A key the run tried and failed to store is not evidence of deletion. Any
  // error rate above zero used to disable cleanup wholesale, which meant one
  // bad section out of thousands stranded every genuine orphan for a week.
  // Protecting exactly the failed keys lets the rest prune normally.
  const isProtected = (k) => stored.has(k) || failed.has(k);

  // Namespaces other than `knowledge` are populated solely from the indexer's
  // own JSONL, so their prior full-subtraction behaviour is correct and is
  // preserved. Guarding them would strand real orphans there permanently.
  if (namespace !== 'knowledge') {
    return existing.filter((k) => !isProtected(k));
  }

  // Hazard 3: a doc type absent from this run was not indexed, so this run
  // cannot speak to whether its existing entries are stale.
  const typesInRun = new Set();
  for (const k of stored) {
    const t = keyType(k);
    if (t !== null && DOC_TYPE_SET.has(t)) typesInRun.add(t);
  }

  return existing.filter((key) => {
    if (isProtected(key)) return false;
    // Hazard 1: never delete what this indexer does not produce.
    if (!isDocDerived(key)) return false;
    return typesInRun.has(keyType(key));
  });
}
