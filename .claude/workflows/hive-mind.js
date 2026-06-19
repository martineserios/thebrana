// hive-mind — the real version of what ruflo's hive-mind/swarm/consensus MCP tools only mock.
//
// Collective intelligence over ONE question:
//   1. Convene   — N workers answer independently, each locked to a distinct lens
//   2. Verify    — each answer is adversarially stress-tested by a skeptic
//   3. Synthesize — survivors merged into one decisive, disagreement-aware answer
//
// Runs on your Claude subscription via the native Workflow tool. No API key, no ruflo.
//
// USAGE (user must name the workflow — that satisfies the Workflow opt-in rule):
//   Workflow({ name: "hive-mind", args: { question: "should we use X or Y?" } })
//   Workflow({ name: "hive-mind", args: { question: "...", workers: 5 } })
//   Workflow({ name: "hive-mind", args: { question: "...", lenses: ["cost", "security", "DX"], model: "haiku" } })
//   Workflow({ name: "hive-mind", args: "a bare question string also works" })
//
// args:
//   question (required) — what the hive answers
//   workers  (optional) — fan-out count, default 3, capped at lenses available
//   lenses   (optional) — custom perspectives; defaults to a diverse general set
//   model    (optional) — model alias for every agent; omit to inherit the session model

export const meta = {
  name: 'hive-mind',
  description: 'Collective intelligence over one question: diverse-lens workers answer independently, each answer is adversarially verified, then a synthesizer merges the survivors into one answer. Subscription-native replacement for ruflo hive-mind/swarm/consensus.',
  phases: [
    { title: 'Convene', detail: 'spawn N diverse-lens workers on the question' },
    { title: 'Verify', detail: 'adversarially stress-test each worker answer' },
    { title: 'Synthesize', detail: 'merge verified answers into one' },
  ],
}

// Be robust to args arriving as a JSON-encoded string (a common Workflow call mistake)
// as well as a real object or a bare question string.
let input = args
if (typeof input === 'string' && input.trim().startsWith('{')) {
  try { input = JSON.parse(input) } catch (_e) { /* leave as string -> treated as the question */ }
}
const opts = (input && typeof input === 'object') ? input : {}
const question = opts.question || (typeof input === 'string' ? input : null)

if (!question) {
  log('hive-mind: no question provided. Pass args:{question:"..."} or a bare string. Aborting.')
  return { error: 'no question provided' }
}

const DEFAULT_LENSES = [
  'First principles: decompose the problem to fundamental truths and reason up from them. Ignore "how it is usually done".',
  'Evidence: ground every claim in concrete sources, data, code, or docs. Cite specifics; flag anything you cannot support.',
  'Skeptic: argue the strongest counter-case. Where is the conventional answer wrong, risky, or incomplete?',
  'Practitioner: what actually works in practice — trade-offs, failure modes, and operational cost.',
  'Systems: second-order effects, interactions with the rest of the system, and what breaks at scale.',
]

const requested = Math.max(1, Math.min(opts.workers || 3, DEFAULT_LENSES.length + 3))
const base = (Array.isArray(opts.lenses) && opts.lenses.length) ? opts.lenses : DEFAULT_LENSES
const lenses = base.slice(0, requested)
while (lenses.length < requested) {
  lenses.push(`Independent angle #${lenses.length + 1}: investigate from a perspective the other workers would miss.`)
}
const model = opts.model // undefined => inherit session model

const ANSWER_SCHEMA = {
  type: 'object',
  required: ['answer', 'key_claims', 'confidence'],
  properties: {
    answer: { type: 'string', description: 'Your answer to the question, 1-3 paragraphs, committed to your lens.' },
    key_claims: { type: 'array', items: { type: 'string' }, description: 'The atomic factual claims your answer depends on.' },
    confidence: { type: 'number', description: 'Self-assessed confidence, 0..1.' },
  },
}

const VERDICT_SCHEMA = {
  type: 'object',
  required: ['holds_up', 'problems', 'adjusted_confidence'],
  properties: {
    holds_up: { type: 'boolean', description: 'Does the answer survive scrutiny overall?' },
    problems: { type: 'array', items: { type: 'string' }, description: 'Specific flaws, unsupported claims, or errors. Empty array if none found.' },
    adjusted_confidence: { type: 'number', description: 'Confidence after verification, 0..1.' },
  },
}

phase('Convene')
log(`hive-mind: ${lenses.length} workers on "${question.slice(0, 80)}${question.length > 80 ? '…' : ''}"`)

// find -> verify, per worker, no barrier: a worker's answer is verified the moment it lands.
const results = await pipeline(
  lenses,
  (lens, _lensAgain, i) => agent(
    `You are worker ${i + 1} in a hive-mind answering ONE question. Other workers cover other angles; do not try to be comprehensive — own your lens.\n\nQUESTION:\n${question}\n\nYOUR LENS (commit to it):\n${lens}\n\nAnswer through this lens only. Be specific and concrete. State the claims your answer rests on so they can be checked.`,
    { label: `worker:${i + 1}`, phase: 'Convene', schema: ANSWER_SCHEMA, model },
  ),
  (answer, lens, i) => {
    if (!answer) return null
    return agent(
      `You are an adversarial verifier in a hive-mind. Stress-test another worker's answer. Default to skepticism: only let claims pass if they genuinely hold.\n\nQUESTION:\n${question}\n\nWORKER ANSWER:\n${answer.answer}\n\nCLAIMS IT DEPENDS ON:\n${(answer.key_claims || []).map((c, k) => `${k + 1}. ${c}`).join('\n')}\n\nHunt for unsupported claims, factual errors, and logical gaps. Then judge whether the answer holds up overall.`,
      { label: `verify:${i + 1}`, phase: 'Verify', schema: VERDICT_SCHEMA, model },
    ).then((verdict) => ({ lens, answer, verdict }))
  },
)

phase('Synthesize')
const all = results.filter(Boolean)
const survivors = all.filter((r) => r.verdict && r.verdict.holds_up)
log(`${survivors.length}/${all.length} answers survived adversarial verification`)

if (!all.length) {
  return { question, workers: 0, survived: 0, answer: 'All workers failed to produce an answer.', detail: [] }
}

const dossier = all.map((r, i) => {
  const v = r.verdict || {}
  const status = v.holds_up ? 'VERIFIED' : 'REJECTED'
  const conf = typeof v.adjusted_confidence === 'number' ? v.adjusted_confidence : '?'
  const probs = (v.problems && v.problems.length) ? `\nProblems flagged: ${v.problems.join('; ')}` : ''
  return `### Worker ${i + 1} — ${status} (confidence ${conf})\nLens: ${r.lens}\nAnswer: ${r.answer.answer}${probs}`
}).join('\n\n')

const synthesis = await agent(
  `You are the synthesizer of a hive-mind. ${all.length} workers answered the question below from different lenses; each was adversarially verified.\n\nQUESTION:\n${question}\n\nWORKER DOSSIER:\n${dossier}\n\nProduce ONE consolidated answer. Lead with verified content; treat rejected answers as cautions, not facts. Surface genuine disagreement between workers instead of papering over it. Be decisive where the evidence supports it, hedged only where it must be.`,
  { label: 'synthesize', phase: 'Synthesize', model },
)

return {
  question,
  workers: all.length,
  survived: survivors.length,
  answer: synthesis,
  detail: all.map((r) => ({
    lens: r.lens,
    held_up: !!(r.verdict && r.verdict.holds_up),
    confidence: r.verdict && r.verdict.adjusted_confidence,
    problems: (r.verdict && r.verdict.problems) || [],
  })),
}
