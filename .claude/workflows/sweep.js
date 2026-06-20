// sweep — unbounded DISCOVERY across a target (the third reusable native block,
// alongside hive-mind and verify-findings).
//
// hive-mind answers ONE question; sweep finds ALL of something whose count is unknown
// (all bugs, all doc drift, all dead refs, all hollow calls). The risk it manages is
// MISSING things, not getting one answer wrong — so it fans out across distinct search
// ANGLES (not lenses), clusters what they surface (cross-finder agreement = corroboration,
// per pattern_no-dedup-overlap-as-signal), then delegates verification to verify-findings.
//
//   1. Sweep    — N read-only finders, each a distinct search angle, blind to each other
//   2. Cluster  — group near-duplicate findings; agreement = distinct angles that hit it
//   3. Verify   — workflow('verify-findings') judges each cluster; sweep layers an
//                 agreement-aware confidence label on the result
//
// Finders run as Explore agents: READ-ONLY by construction. A discovery tool must be
// structurally incapable of mutating its target (ADR-059 security stance).
//
// Runs on your Claude subscription via the native Workflow tool. No API key, no ruflo.
//
// USAGE (user must name the workflow — satisfies the Workflow opt-in rule):
//   Workflow({ name: "sweep", args: { target: "the auth module for security bugs" } })
//   Workflow({ name: "sweep", args: { target: "...", angles: ["by-content","by-time"], voters: 3 } })
//
// args:
//   target   (required) — what to search and for what
//   angles   (optional) — search modes; defaults to the diverse general set below
//   finders  (optional) — fan-out count, default = angles.length, capped at angles available
//   voters   (optional) — skeptics per cluster in verify, default 2, capped 4
//   model    (optional) — model alias for every sweep/cluster agent; omit to inherit session model
//
// NOTE: a loop-until-dry "exhaustive" mode was intentionally NOT shipped in v1 — doing it
// right requires feeding prior-round findings back into later finders, which is its own
// design. Add it behind an opt-in flag when a real task needs it (ADR-059).

export const meta = {
  name: 'sweep',
  description: 'Unbounded discovery over a target: read-only finders each search a distinct angle, near-duplicate findings cluster (agreement = corroboration), then verify-findings judges each cluster. Reusable native discovery block.',
  phases: [
    { title: 'Sweep', detail: 'N angle-diverse read-only finders surface candidate findings' },
    { title: 'Cluster', detail: 'group near-duplicates; count cross-finder agreement' },
    { title: 'Verify', detail: 'delegate to verify-findings; drop false positives, calibrate severity' },
  ],
}

// Robust to args as a JSON-encoded string, a real object, or a bare target string.
let input = args
if (typeof input === 'string' && input.trim().startsWith('{')) {
  try { input = JSON.parse(input) } catch (_e) { /* leave as string -> treated as the target */ }
}
const opts = (input && typeof input === 'object') ? input : {}
const target = opts.target || (typeof input === 'string' ? input : null)

if (!target) {
  log('sweep: no target provided. Pass args:{target:"..."} or a bare string. Aborting.')
  return { error: 'no target provided' }
}

// Search ANGLES — distinct ways to LOOK, so finders miss different things and overlap is meaningful.
const DEFAULT_ANGLES = [
  'BY-CONTAINER: walk the structure — files, modules, directories, layers. Find issues that live in how things are organized or where a concern is (mis)placed.',
  'BY-CONTENT: search by keyword, string, pattern, and idiom across the code/text. Find issues you catch by reading what is literally written.',
  'BY-ENTITY: follow named symbols — functions, types, configs, endpoints, callers. Find issues in how specific entities are defined, used, or wired together.',
  'BY-TIME: focus on what changed recently and what churns — recent edits, TODO/FIXME, half-done migrations, version skew. Find issues introduced or left behind over time.',
]

const angles = (Array.isArray(opts.angles) && opts.angles.length) ? opts.angles : DEFAULT_ANGLES
const finders = Math.max(1, Math.min(opts.finders || angles.length, angles.length))
const activeAngles = angles.slice(0, finders)
const voters = Math.max(1, Math.min(opts.voters || 3, 4)) // default 3 = odd => verify ties impossible
const model = opts.model // undefined => inherit session model

const FINDINGS_SCHEMA = {
  type: 'object',
  required: ['findings'],
  properties: {
    findings: {
      type: 'array',
      description: 'Concrete findings. Empty array if your angle surfaces nothing — do not invent.',
      items: {
        type: 'object',
        required: ['location', 'text', 'severity'],
        properties: {
          location: { type: 'string', description: 'Exact place: file:line, symbol, section — specific enough to verify.' },
          text: { type: 'string', description: 'What is wrong, in one or two concrete sentences.' },
          severity: { type: 'string', enum: ['CRITICAL', 'WARNING', 'OBSERVATION'] },
        },
      },
    },
  },
}

const CLUSTERS_SCHEMA = {
  type: 'object',
  required: ['clusters'],
  properties: {
    clusters: {
      type: 'array',
      description: 'Each distinct underlying issue, once. Findings describing the same root issue belong to one cluster even if worded differently.',
      items: {
        type: 'object',
        required: ['canonical', 'member_indices', 'severity'],
        properties: {
          canonical: { type: 'string', description: 'One clear description of the underlying issue.' },
          member_indices: { type: 'array', items: { type: 'number' }, description: '1-based indices of the raw findings that belong to this cluster.' },
          locations: { type: 'array', items: { type: 'string' }, description: 'Distinct locations across members.' },
          severity: { type: 'string', enum: ['CRITICAL', 'WARNING', 'OBSERVATION'], description: 'Highest claimed severity among members.' },
        },
      },
    },
  },
}

// duplicated by necessity from verify-findings.js — Workflow scripts are sandboxed (no shared imports).
const ORDER = { CRITICAL: 3, WARNING: 2, OBSERVATION: 1, FALSE_POSITIVE: 0 }

// ---- Phase 1: Sweep ---------------------------------------------------------
// All active angles in parallel (a barrier — clustering needs them all). Finders are
// Explore agents: read-only, so the sweep cannot mutate what it inspects.
phase('Sweep')
log(`sweep: ${activeAngles.length} read-only finders on "${target.slice(0, 70)}${target.length > 70 ? '…' : ''}"`)

const finderResults = await parallel(activeAngles.map((angle, a) => () =>
  agent(
    `You are finder ${a + 1} sweeping a target for ALL issues visible through ONE search angle. Other finders use other angles — do not try to be comprehensive, own your angle and go deep on it.\n\nTARGET (what to search, and for what):\n${target}\n\nYOUR SEARCH ANGLE (commit to it):\n${angle}\n\nUse your tools to actually look. Report only concrete findings with an exact location. If your angle surfaces nothing real, return an empty findings array — do not pad.`,
    { label: `find:${a + 1}`, phase: 'Sweep', schema: FINDINGS_SCHEMA, model, agentType: 'Explore' },
  ),
))

const finderFailed = finderResults.filter((r) => !r).length
if (finderFailed) log(`⚠ ${finderFailed}/${activeAngles.length} finders failed — sweep coverage is partial`)

const rawFindings = []
finderResults.forEach((r, a) => {
  if (!r || !Array.isArray(r.findings)) return
  r.findings.forEach((f) => rawFindings.push({ ...f, angle: activeAngles[a] }))
})

if (!rawFindings.length) {
  log('sweep: no findings surfaced.')
  return { target, raw_count: 0, cluster_count: 0, confirmed: [], false_positives: 0, by_severity: {}, finders_failed: finderFailed }
}

// ---- Phase 2: Cluster -------------------------------------------------------
// One agent groups near-duplicates. Agreement (distinct angles per cluster) is corroboration,
// NOT noise to discard — kept as a confidence multiplier in verify.
phase('Cluster')
const numbered = rawFindings.map((f, i) => `${i + 1}. [${f.severity}] (${f.location}) ${f.text}`).join('\n')
const clusterResult = await agent(
  `You are de-duplicating discovery findings. ${rawFindings.length} raw findings were surfaced by independent finders. Group findings that describe the SAME underlying issue into one cluster, even when worded differently or located slightly differently. Keep genuinely distinct issues separate. Every raw finding must belong to exactly one cluster.\n\nRAW FINDINGS:\n${numbered}\n\nReturn the clusters with 1-based member_indices into the list above.`,
  { label: 'cluster', phase: 'Cluster', schema: CLUSTERS_SCHEMA, model },
)

let clusters = (clusterResult && Array.isArray(clusterResult.clusters)) ? clusterResult.clusters : []
if (!clusters.length) {
  // Clustering failed entirely — degrade to one cluster per raw finding rather than losing data.
  log('⚠ clustering returned nothing — treating every finding as its own cluster')
  clusters = rawFindings.map((f, i) => ({ canonical: f.text, member_indices: [i + 1], locations: [f.location], severity: f.severity }))
}

// COVERAGE GUARD: every raw finding must end up in some cluster. Any index the cluster agent
// failed to assign becomes its own singleton cluster — a discovery tool must not silently
// drop discoveries.
const assigned = new Set()
clusters.forEach((c) => (c.member_indices || []).forEach((idx) => assigned.add(idx)))
const orphans = []
for (let i = 1; i <= rawFindings.length; i++) {
  if (!assigned.has(i)) orphans.push(i)
}
if (orphans.length) {
  log(`⚠ ${orphans.length} finding(s) left unclustered — re-added as singletons (no data lost)`)
  orphans.forEach((idx) => {
    const f = rawFindings[idx - 1]
    clusters.push({ canonical: f.text, member_indices: [idx], locations: [f.location], severity: f.severity })
  })
}

// Attach agreement = count of DISTINCT finder angles among a cluster's members.
clusters = clusters.map((c) => {
  const members = (c.member_indices || []).map((idx) => rawFindings[idx - 1]).filter(Boolean)
  const distinctAngles = new Set(members.map((m) => m.angle))
  return { ...c, member_count: members.length, agreement: distinctAngles.size }
})
log(`clustered ${rawFindings.length} findings → ${clusters.length} distinct issues`)

// ---- Phase 3: Verify (delegated to the canonical verifier) -------------------
// sweep does NOT re-implement the judge-panel — it calls verify-findings, then layers an
// agreement-aware confidence label on the verdicts it gets back.
phase('Verify')
const vfFindings = clusters.map((c, i) => ({
  id: i,
  text: c.canonical,
  severity: c.severity,
  source: `${c.agreement} angle(s): ${(c.locations || []).join(', ') || 'see finding'}`,
}))

let verifiedById = new Map()
let verifyFailed = false
try {
  const vf = await workflow('verify-findings', { target, findings: vfFindings, voters })
  verifiedById = new Map(((vf && vf.verified) || []).map((v) => [v.id, v]))
} catch (e) {
  verifyFailed = true
  log(`⚠ verify-findings failed (${e && e.message ? e.message : 'unknown'}) — returning UNVERIFIED candidates`)
}

const out = clusters.map((c, i) => {
  const v = verifiedById.get(i)
  if (!v) {
    // Verification unavailable for this cluster — surface as unverified, do not silently confirm or drop.
    return {
      issue: c.canonical,
      locations: c.locations || [],
      holds: !verifyFailed ? false : null, // null = unknown (verify down); false = verifier dropped it
      severity: c.severity,
      confidence: 'UNVERIFIED',
      agreement: c.agreement,
      votes: 'n/a',
      reason: verifyFailed ? 'verifier unavailable' : 'no verdict returned for this cluster',
    }
  }
  const holds = v.holds
  const severity = v.adjusted_severity
  const allHeld = /^(\d+)\/\1 held$/.test(v.votes) // e.g. "2/2 held"
  const confidence = holds && c.agreement >= 2 && allHeld ? 'HIGH'
    : holds && (c.agreement >= 2 || allHeld) ? 'MEDIUM'
      : holds ? 'LOW' : 'NONE'
  return {
    issue: c.canonical,
    locations: c.locations || [],
    holds,
    severity,
    confidence,
    agreement: c.agreement,
    votes: v.votes,
    reason: v.reason,
  }
})

const confirmed = out.filter((f) => f.holds === true)
  .sort((a, b) => (ORDER[b.severity] - ORDER[a.severity]) || (b.agreement - a.agreement))
const unverified = out.filter((f) => f.holds === null)
const falsePositives = out.length - confirmed.length - unverified.length
const by_severity = confirmed.reduce((m, f) => { m[f.severity] = (m[f.severity] || 0) + 1; return m }, {})
log(`${confirmed.length}/${out.length} clusters confirmed (${falsePositives} false positives${unverified.length ? `, ${unverified.length} unverified` : ''})`)

return {
  target,
  raw_count: rawFindings.length,
  cluster_count: clusters.length,
  confirmed,
  unverified: unverified.length ? unverified : undefined,
  false_positives: falsePositives,
  by_severity,
  finders_failed: finderFailed,
}
