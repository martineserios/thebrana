# Knowledge Retrieval Tax — Positioning Frame

> **Spike output for t-1111.** Not a spec — a positioning doc and content plan.
> Source research: `docs/research/2026-04-08-url-batch-findings.md` §Cluster B

---

## What Is the Knowledge Retrieval Tax?

Every AI coding session starts with invisible work: the model re-infers the domain constraints it already knew from the last session. Your stack. Your naming conventions. Your past decisions. The ADRs you wrote. The patterns that were painful to learn.

This is the **knowledge retrieval tax** — the per-session cost of restating what was already true.

**Coined by:** Francisco Marques da Silva (`franciscomarquessilva`, LinkedIn)
**Amplified by:** Alindnbrg Lindenberg (`alindnbrg`, LinkedIn)

The tax is invisible because it's denominated in attention and time, not dollars. But it compounds:
- 5 minutes of re-orientation per session × 20 sessions/week = 100 minutes/week of tax
- Context window consumed by re-stating context → less room for reasoning
- Decisions re-litigated session-to-session because prior decisions weren't loaded

---

## Why This Maps Precisely to Brana

Brana doesn't add features to Claude. Brana **eliminates the retrieval tax** by making domain knowledge persistent, structured, and pre-loaded.

| Tax source | Brana answer |
|------------|-------------|
| Re-explaining the tech stack | `CLAUDE.md` loaded at session start |
| Re-inferring past decisions | ADRs in `docs/architecture/decisions/` + LOAD step |
| Re-discovering patterns | `ruflo memory_search` at task start |
| Re-orienting after context reset | `/brana:sitrep` + session state |
| Contradicting earlier guidance | Lint+Heal (scheduled consolidation) |
| Re-stating task context per session | `brana backlog get <id>` — full context field |

Every brana design decision passes a single test: **does this reduce the retrieval tax?**

This is a sharper compass than "harness with opinions" or "cross-client memory" — those describe what brana is. "Eliminate the knowledge retrieval tax" describes **what brana does**.

---

## Relationship to the Harness Engineering Frame

These frames are complementary, not competing:

- **Harness Engineering** = what brana IS (skills=tools, hooks=feedback loops, rules=constraints)
- **Knowledge Retrieval Tax** = what brana SOLVES (per-session re-inference cost)

Lead with the tax in content — it's the felt problem. Follow with the harness as the mechanism.

---

## Design Compass Application

Use KRT as a filter for any new brana feature decision:

| Feature | Reduces tax? | Verdict |
|---------|-------------|---------|
| LOAD step (pull context before build) | Yes — pre-loads ADRs + patterns | KEEP |
| Lint+Heal (consolidate contradictions) | Yes — contradictions increase confusion cost | BUILD |
| Dimensions (structured knowledge docs) | Yes — reusable, pre-indexed | KEEP |
| Session memory schema alignment | Yes — handoffs stop cold | KEEP |
| Skill telemetry | Yes — prunes dead overhead | KEEP |
| Buddy persona | No | CEDE |
| Voice mode | No | CEDE |

---

## LinkedIn Content Angles

### Post 1 — Definition (educational, primary)

**Hook:** "Every AI session, your model pays a hidden tax."

**Body:**
- Define the knowledge retrieval tax (credit Marques da Silva, Lindenberg)
- 3 concrete examples: "what stack are you using?", "what patterns matter here?", "remind me of past decisions?"
- Point: the tax isn't the model's fault — it's a tooling gap
- The fix: pre-load structured context before reasoning begins
- Brana does this: LOAD step, CLAUDE.md, ruflo search

**CTA:** Tag `@franciscomarquessilva` `@alindnbrg` — "you coined the problem, here's what solving it looks like in practice"

**Format:** Short-form (700-900 chars). No bullet lists — prose hook → definition → example → CTA.

---

### Post 2 — Design compass (practitioner, intermediate)

**Hook:** "Every tool decision I make for brana passes one test."

**Body:**
- The test: "does this reduce the knowledge retrieval tax?"
- Walk through 3 decisions that passed: LOAD step, Lint+Heal, structured dimensions
- Walk through 2 that failed the test: features that add overhead without reducing tax
- The insight: KRT gives a principled rejection criterion for feature requests
- Broader: any team can apply this to their AI tooling — not brana-specific

**CTA:** "What's your costliest retrieval tax source?"

**Format:** 1200-1500 chars. Conversational. 1 table or structured list mid-post.

---

### Post 3 — Before/after contrast (concrete, broadest reach)

**Hook:** "Two sessions. Same code. Same model. 17 minutes apart in first-commit time."

**Body:**
- Session A (stateless): 20 min explaining context before first useful output
- Session B (brana-loaded): first commit in 3 min, zero re-orientation
- The difference isn't Claude — it's the retrieval tax
- KRT makes this gap concrete and measurable (vs "Claude is inconsistent")
- Specific numbers if possible (estimate from your own sessions)

**CTA:** "Track your tax for one week. You'll find your sessions have a pattern."

**Format:** 900-1100 chars. Simple split-screen narrative. No jargon.

---

## Publication Notes

- **Tag strategy:** Both posts 1 and 2 should tag `@franciscomarquessilva` and `@alindnbrg`. Post 3 is broader — optional tags.
- **Sequence:** Post 1 first (define the concept). Post 2 one week later (apply the compass). Post 3 two weeks later (proof of concept).
- **LinkedIn slugs:** `franciscomarquessilva`, `alindnbrg`
- **Hashtags:** `#AIengineering`, `#ClaudeCode`, `#contextengineering`, `#agentarchitecture`

---

## Next Steps (not in this spike)

- [ ] Write the three posts to drafts (venturing to `ventures/linkedin/`)
- [ ] Update brana README to lead with KRT frame (t-560 area)
- [ ] Cross-pollinate to `brana-knowledge/dimensions/` as a dimension doc (if adopted as primary frame)
- [ ] Add Marques da Silva + Lindenberg to `docs/research/research-sources.yaml` (noted in Cluster B findings)
