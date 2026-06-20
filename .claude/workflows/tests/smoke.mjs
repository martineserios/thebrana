#!/usr/bin/env node
// Deterministic smoke tests for the native workflow blocks (ADR-059).
//
// These workflows are LLM-orchestrated and non-deterministic at runtime, so we cannot assert
// their *content*. What we CAN — and must — protect against rot is the deterministic glue:
// arg parsing, clustering + coverage guard, confidence math, cross-workflow delegation, and
// the return shape. We mock the injected runtime globals (agent/parallel/pipeline/workflow/…),
// run each workflow's real body, and assert structure + invariants.
//
// Run:  node .claude/workflows/tests/smoke.mjs
// Exit: 0 all passed, 1 any failure. No network, no real agents.

import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, resolve } from 'node:path'

const HERE = dirname(fileURLToPath(import.meta.url))
const WF = resolve(HERE, '..')
const AsyncFunction = Object.getPrototypeOf(async () => {}).constructor

let pass = 0
let fail = 0
const ok = (cond, msg) => { if (cond) { pass++ } else { fail++; console.error(`  ✗ ${msg}`) } }

// --- Synthesize a schema-valid stub object the way a compliant agent would --------------
// holdMode: 'hold' => verdicts hold at full severity; 'refute' => everything is a FALSE_POSITIVE.
function stubFromSchema(schema, holdMode, prompt) {
  if (!schema) return 'stub'
  if (schema.properties && schema.properties.clusters) {
    // Cluster agent: one cluster covering every numbered finding in the prompt (exercises
    // the agreement path and leaves no orphans on the happy path).
    const n = (String(prompt).match(/^\d+\. /gm) || []).length || 1
    return { clusters: [{ canonical: 'merged issue', member_indices: Array.from({ length: n }, (_, i) => i + 1), locations: ['a.js:1'], severity: 'WARNING' }] }
  }
  if (schema.type === 'object') {
    const o = {}
    const req = schema.required && schema.required.length ? schema.required : Object.keys(schema.properties || {})
    for (const k of req) {
      const ps = (schema.properties || {})[k] || { type: 'string' }
      if (k === 'holds' || k === 'holds_up') o[k] = holdMode !== 'refute'
      else if (k === 'severity' || k === 'adjusted_severity') o[k] = holdMode === 'refute' ? 'FALSE_POSITIVE' : 'WARNING'
      else o[k] = stubFromSchema(ps, holdMode, prompt)
    }
    return o
  }
  if (schema.type === 'array') return [stubFromSchema(schema.items, holdMode, prompt)]
  if (schema.enum) return schema.enum[0]
  if (schema.type === 'number') return 0.8
  if (schema.type === 'boolean') return true
  return 'stub-text'
}

// --- Mock runtime ----------------------------------------------------------------------
function makeRuntime({ holdMode = 'hold', findingsPerFinder = 1, throwOn = null } = {}) {
  const noop = () => {}
  let verdictN = 0 // for holdMode 'split': alternate verdicts to simulate a divided panel
  const agent = async (prompt, opts = {}) => {
    const s = opts.schema
    // Simulate a subagent that completes WITHOUT calling StructuredOutput (the recurring failure):
    // agent({schema}) throws. Used to prove graceful degradation (t-2149).
    if (throwOn === 'clusters' && s && s.properties && s.properties.clusters) {
      throw new Error('simulated StructuredOutput skip (cluster agent)')
    }
    if (s && s.properties && s.properties.findings) {
      const findings = Array.from({ length: findingsPerFinder }, (_, j) => ({ location: `a.js:${j + 1}`, text: 'something is off', severity: 'WARNING' }))
      return { findings }
    }
    // Verdict schema (has a `holds`/`holds_up` boolean): control the vote precisely so we can
    // test the strict-majority tie rule, not just unanimous panels.
    if (s && s.properties && (s.properties.holds || s.properties.holds_up)) {
      const key = s.properties.holds ? 'holds' : 'holds_up'
      const truth = holdMode === 'split' ? (verdictN++ % 2 === 0) : holdMode !== 'refute'
      const o = {}
      for (const k of (s.required && s.required.length ? s.required : Object.keys(s.properties))) {
        if (k === key) o[k] = truth
        else if (k === 'severity' || k === 'adjusted_severity') o[k] = truth ? 'WARNING' : 'FALSE_POSITIVE'
        else o[k] = stubFromSchema(s.properties[k], holdMode === 'split' ? 'hold' : holdMode, prompt)
      }
      return o
    }
    if (s) return stubFromSchema(s, holdMode === 'split' ? 'hold' : holdMode, prompt)
    return 'free-form synthesis text'
  }
  const parallel = async (thunks) => Promise.all(thunks.map((t) => Promise.resolve().then(t).catch(() => null)))
  const pipeline = async (items, ...stages) => Promise.all(items.map(async (it, i) => {
    let v = it
    for (const s of stages) { try { v = await s(v, it, i) } catch { v = null; break } }
    return v
  }))
  // Nested workflow() runs the named workflow with the SAME runtime — exercises real delegation.
  const workflow = async (name, childArgs) => runWorkflow(`${name}.js`, childArgs, { holdMode, findingsPerFinder, throwOn })
  return { agent, parallel, pipeline, phase: noop, log: noop, workflow, budget: { total: null, spent: () => 0, remaining: () => Infinity } }
}

async function runWorkflow(file, wfArgs, runtimeOpts) {
  const src = readFileSync(resolve(WF, file), 'utf8').replace(/\bexport const meta\b/, 'const meta')
  const rt = makeRuntime(runtimeOpts)
  const fn = new AsyncFunction('agent', 'parallel', 'pipeline', 'phase', 'log', 'args', 'workflow', 'budget', src)
  return fn(rt.agent, rt.parallel, rt.pipeline, rt.phase, rt.log, wfArgs, rt.workflow, rt.budget)
}

// --- Static meta validation ------------------------------------------------------------
function checkMeta(file) {
  const src = readFileSync(resolve(WF, file), 'utf8')
  ok(/export const meta\s*=/.test(src), `${file}: has 'export const meta ='`)
  ok(/name:\s*['"][\w-]+['"]/.test(src), `${file}: meta.name present`)
  ok(/description:\s*['"]/.test(src), `${file}: meta.description present`)
}

// --- Tests -----------------------------------------------------------------------------
async function main() {
  console.log('workflow smoke tests\n')

  for (const f of ['hive-mind.js', 'verify-findings.js', 'sweep.js']) checkMeta(f)

  // verify-findings: contract — one entry per input, ids echoed, order preserved.
  {
    const r = await runWorkflow('verify-findings.js', { target: 't', findings: [
      { id: 'a', text: 'x', severity: 'CRITICAL' }, { text: 'y', severity: 'WARNING' },
    ] }, { holdMode: 'hold' })
    ok(r.total === 2, 'verify-findings: total === input count')
    ok(r.verified.length === 2, 'verify-findings: one verdict per finding (no drops)')
    ok(r.verified[0].id === 'a' && r.verified[1].id === 1, 'verify-findings: ids echoed (given id, then index)')
    ok(r.survived === 2 && r.refuted === 0, 'verify-findings: hold mode => all survive')
  }
  {
    const r = await runWorkflow('verify-findings.js', { target: 't', findings: [{ text: 'x' }] }, { holdMode: 'refute' })
    ok(r.survived === 0 && r.refuted === 1, 'verify-findings: refute mode => all refuted')
    ok(r.verified[0].adjusted_severity === 'FALSE_POSITIVE', 'verify-findings: refuted => FALSE_POSITIVE')
  }
  {
    const r = await runWorkflow('verify-findings.js', { target: 't', findings: [] })
    ok(r.total === 0 && r.verified.length === 0, 'verify-findings: empty findings => empty result')
  }
  {
    // Default voters must be ODD (3) so ties cannot occur. Locks ADR-059 verdict-rule decision.
    const r = await runWorkflow('verify-findings.js', { target: 't', findings: [{ text: 'x' }] }, { holdMode: 'hold' })
    ok(/\/3 held$/.test(r.verified[0].votes), 'verify-findings: default voters === 3 (odd, tie-proof)')
  }
  {
    // Strict majority: an even-voter SPLIT (1 of 2) must REFUTE — no tie survives.
    const r = await runWorkflow('verify-findings.js', { target: 't', voters: 2, findings: [{ text: 'x' }] }, { holdMode: 'split' })
    ok(r.verified[0].holds === false, 'verify-findings: 1-of-2 split => refuted (strict majority, ties drop)')
    ok(r.survived === 0, 'verify-findings: even-voter split => nothing survives')
  }

  // sweep: full pipeline incl. nested verify-findings delegation.
  {
    const r = await runWorkflow('sweep.js', { target: 'the codebase for bugs' }, { holdMode: 'hold', findingsPerFinder: 1 })
    ok(r.raw_count === 4, 'sweep: 4 angles × 1 finding => raw_count 4')
    ok(r.cluster_count >= 1, 'sweep: produced at least one cluster')
    ok(Array.isArray(r.confirmed), 'sweep: confirmed is an array')
    ok(r.confirmed.length >= 1, 'sweep: hold mode => at least one confirmed cluster')
    ok(r.confirmed[0].confidence === 'HIGH', 'sweep: all-angles cluster + all-held => HIGH confidence')
    ok(r.false_positives === 0, 'sweep: hold mode => no false positives')
    ok(r.confirmed.length + r.false_positives === r.cluster_count, 'sweep: counts reconcile (confirmed + FP === clusters)')
  }
  {
    const r = await runWorkflow('sweep.js', { target: 'x' }, { holdMode: 'refute', findingsPerFinder: 1 })
    ok(r.confirmed.length === 0, 'sweep: refute mode => nothing confirmed')
    ok(r.false_positives === r.cluster_count, 'sweep: refute mode => all clusters are false positives')
  }
  // sweep: a throwing cluster agent (StructuredOutput skip) must DEGRADE, not abort (t-2149).
  {
    const r = await runWorkflow('sweep.js', { target: 'x' }, { holdMode: 'hold', findingsPerFinder: 1, throwOn: 'clusters' })
    ok(r.raw_count === 4, 'sweep degrade: still surfaced 4 raw findings despite cluster throw')
    ok(r.cluster_count === 4, 'sweep degrade: cluster throw => one cluster per finding (no data lost)')
  }
  {
    const r = await runWorkflow('sweep.js', 'a bare string target', { holdMode: 'hold' })
    ok(!r.error, 'sweep: bare-string args accepted')
  }
  {
    const r = await runWorkflow('sweep.js', {}, { holdMode: 'hold' })
    ok(r.error === 'no target provided', 'sweep: missing target => clean error')
  }

  // hive-mind: smoke — runs, returns an answer.
  {
    const r = await runWorkflow('hive-mind.js', { question: 'X or Y?' }, { holdMode: 'hold' })
    ok(r.workers === 3, 'hive-mind: default 3 workers')
    ok(typeof r.answer === 'string' && r.answer.length > 0, 'hive-mind: returns a synthesized answer')
    ok(r.survived === 3, 'hive-mind: hold mode => all answers survive')
  }
  {
    const r = await runWorkflow('hive-mind.js', {}, { holdMode: 'hold' })
    ok(r.error === 'no question provided', 'hive-mind: missing question => clean error')
  }

  console.log(`\n${pass} passed, ${fail} failed`)
  process.exit(fail ? 1 : 0)
}

main().catch((e) => { console.error('harness crashed:', e); process.exit(1) })
