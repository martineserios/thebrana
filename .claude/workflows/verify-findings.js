// verify-findings — THE canonical adversarial verifier for brana's native multi-agent
// substrate (ADR-059). Single source of truth for FINDING verification:
//   - sweep.js calls it via workflow() after clustering
//   - /brana:challenge --deep calls it via Workflow after the native challenger fan-out
//
// NOT shared by hive-mind.js: that verifies a free-form ANSWER against its key_claims
// (holds_up / problems / adjusted_confidence) — a different primitive. Severity is
// meaningless for an answer; do not merge the two.
//
// Each finding is independently stress-tested by N skeptics, each with a distinct lens;
// majority-refute drops it to FALSE_POSITIVE, survivors get a calibrated severity. Kills
// the plain-but-wrong findings that single-pass challengers let through.
//
// Subscription-native (Workflow tool + native subagents). No API key, no ruflo.
//
// USAGE:
//   Workflow({ scriptPath: ".claude/workflows/verify-findings.js", args: {
//     target: "the plan/decision/code that was challenged",
//     findings: [
//       { id: "f1", severity: "CRITICAL", text: "...", source: "devil's advocate" },
//       { severity: "WARNING",  text: "..." }
//     ],
//     voters: 2   // optional, skeptics per finding (default 2, capped 4)
//   }})
//
// VERDICT RULE (unambiguous — resolves the prior "skepticism vs majority-refute" spec gap):
//   A finding HOLDS only with a STRICT MAJORITY of skeptics confirming. Ties and
//   majority-refute BOTH drop it to FALSE_POSITIVE. The burden of proof is on the finding
//   to survive, not on skeptics to kill it. `voters` defaults to 3 (ODD → ties are impossible);
//   the strict-majority test below also keeps even voter counts principled if a caller passes one.
//
// CONTRACT (sweep.js depends on these — do not weaken without updating callers):
//   - output.verified preserves INPUT ORDER and emits exactly one entry per input finding;
//     a finding whose skeptics all died is kept as holds:false / FALSE_POSITIVE, NEVER dropped.
//   - each entry echoes the input `id` (or its 0-based index when none was given) for correlation.
//   - returns: { target, total, verified: [{ id, text, claimed_severity, source, holds,
//                adjusted_severity, votes, verifiers_failed, reason }], survived, refuted }

export const meta = {
  name: 'verify-findings',
  description: 'Adversarially verify a list of findings — N diverse-lens skeptics per finding; a finding holds only with a strict majority confirming (ties and majority-refute both drop to FALSE_POSITIVE), survivors get a calibrated severity. The canonical finding-verifier; reusable judge-panel block.',
  phases: [
    { title: 'Verify', detail: 'N skeptics stress-test each finding in parallel' },
  ],
}

let input = args
if (typeof input === 'string' && input.trim().startsWith('{')) {
  try { input = JSON.parse(input) } catch (_e) { /* ignore */ }
}
const opts = (input && typeof input === 'object') ? input : {}
const target = opts.target || 'the proposal under review'
const findings = Array.isArray(opts.findings) ? opts.findings : []
const voters = Math.max(1, Math.min(opts.voters || 3, 4)) // default 3 = odd => ties impossible

if (!findings.length) {
  log('verify-findings: no findings provided (args.findings must be a non-empty array). Nothing to verify.')
  return { target, total: 0, verified: [], survived: 0, refuted: 0 }
}

const VERDICT_SCHEMA = {
  type: 'object',
  required: ['holds', 'severity', 'reason'],
  properties: {
    holds: { type: 'boolean', description: 'Is this a real, consequential finding (true) or a plausible-but-wrong / already-handled / nitpick one (false)?' },
    severity: { type: 'string', enum: ['CRITICAL', 'WARNING', 'OBSERVATION', 'FALSE_POSITIVE'], description: 'Calibrated severity. FALSE_POSITIVE if it does not hold.' },
    reason: { type: 'string', description: 'One or two sentences justifying the verdict — concrete, not generic.' },
  },
}

// Distinct skeptic lenses — diversity catches failure modes that redundant refuters miss.
// This is THE canonical lens set for finding verification; sweep reuses it via this workflow.
// NOTE: `voters` is capped at LENSES.length, so the `while (lenses.length < voters)` padding
// below is currently unreachable — kept as a deliberate guard for if the cap is ever raised.
const LENSES = [
  'REALITY: Is this a concrete problem you can point to an exact place/line/scenario for, or a plausible-sounding generality? Default to refuted if you cannot make it concrete.',
  'CALIBRATION: Suppose it is real — is the rated severity correct given the target and its constraints? Downgrade over-rated findings; flag if it is actually already handled.',
  'STEELMAN-THEN-BREAK: Build the strongest case the finding is RIGHT, then the strongest case it is WRONG or out of scope. Which wins on the evidence?',
  'COST: Even if real, would acting on it cost more than the risk it removes? A true-but-not-worth-it finding is an OBSERVATION at most.',
]

// duplicated by necessity in sweep.js — Workflow scripts are sandboxed (no shared imports).
const ORDER = { CRITICAL: 3, WARNING: 2, OBSERVATION: 1, FALSE_POSITIVE: 0 }

phase('Verify')
log(`verify-findings: ${findings.length} findings × ${voters} skeptics`)

const verified = await pipeline(
  findings,
  (finding, _again, i) => {
    const f = (finding && typeof finding === 'object') ? finding : {}
    const id = (f.id !== undefined && f.id !== null) ? f.id : i
    const text = f.text || f.finding || String(finding)
    const claimed = f.severity || 'UNRATED'
    const lenses = LENSES.slice(0, voters)
    while (lenses.length < voters) lenses.push(`INDEPENDENT: scrutinize from an angle the others would miss (#${lenses.length + 1}).`)
    return parallel(lenses.map((lens, k) => () =>
      agent(
        `You are an adversarial verifier for a challenge report. Default to skepticism — only confirm findings that genuinely hold.\n\nTARGET UNDER REVIEW:\n${target}\n\nFINDING (claimed severity: ${claimed}):\n${text}\n\nYOUR LENS:\n${lens}\n\nDecide whether this finding holds and what its severity really is.`,
        { label: `verify:${i + 1}.${k + 1}`, phase: 'Verify', schema: VERDICT_SCHEMA },
      ),
    )).then((verdicts) => {
      const vs = verdicts.filter(Boolean)  // throwing verifiers (e.g. StructuredOutput skip) → null → dropped
      const failed = lenses.length - vs.length
      const allFailed = vs.length === 0
      const holdsCount = vs.filter((v) => v.holds).length
      const holds = vs.length ? holdsCount * 2 > vs.length : false // strict majority; ties refute
      // Distinguish "verified false" from "couldn't verify": if EVERY verifier failed, do NOT
      // auto-dismiss as FALSE_POSITIVE (that silently drops possibly-real findings). Mark
      // UNVERIFIED so it surfaces for human attention (t-2149 graceful degradation).
      let adjusted = allFailed ? 'UNVERIFIED' : 'FALSE_POSITIVE'
      if (holds) {
        adjusted = vs.filter((v) => v.holds)
          .map((v) => v.severity)
          .reduce((best, s) => (ORDER[s] > ORDER[best] ? s : best), 'OBSERVATION')
      }
      return {
        id,
        text,
        claimed_severity: claimed,
        source: f.source || null,
        holds,
        adjusted_severity: adjusted,
        votes: allFailed ? '0/0 (all verifiers failed)' : `${holdsCount}/${vs.length} held`,
        verifiers_failed: failed,
        reason: allFailed
          ? `all ${failed} verifier(s) failed to return a verdict — left UNVERIFIED, not auto-dismissed`
          : (vs.map((v) => v.reason).filter(Boolean).join(' | ') || 'no verdicts returned'),
      }
    })
  },
)

// pipeline only yields null for a finding whose stage THREW (we don't throw — parallel
// returns nulls, not rejections). Guard anyway so a thrown stage never corrupts counts.
const dropped = verified.filter((v) => !v).length
if (dropped) log(`⚠ ${dropped} finding(s) errored during verification and were lost — investigate`)
const out = verified.filter(Boolean)
const failedAny = out.reduce((n, f) => n + (f.verifiers_failed > 0 ? 1 : 0), 0)
if (failedAny) log(`⚠ ${failedAny} finding(s) had at least one skeptic fail — verdicts ran short`)

const survived = out.filter((f) => f.holds).length
log(`${survived}/${out.length} findings survived adversarial verification`)

return { target, total: out.length, verified: out, survived, refuted: out.length - survived }
