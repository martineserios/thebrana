---
name: respondio-prompts
description: "Respond.io AI agent prompt engineering — write instructions, actions, KB files, and multi-agent architectures within platform constraints. Use when writing or reviewing Respond.io agent prompts, designing multi-agent handoff flows, or creating knowledge bases."
effort: medium
argument-hint: "[write|review] [agent-name]"
group: utility
allowed-tools:
  - Read
  - Write
  - Edit
  - Glob
  - Grep
  - Task
  - WebSearch
  - WebFetch
  - AskUserQuestion
---

# Respond.io Prompt Engineering

Write, review, and architect AI agent prompt systems for Respond.io. Covers instructions, actions, knowledge bases, multi-agent handoffs, and platform constraints.

## When to use

When writing or reviewing Respond.io agent prompts, designing multi-agent flows, creating knowledge bases, or debugging agent behavior on the platform.

**Invocation:**
- `/brana:respondio-prompts` — interactive mode, ask what to build
- `/brana:respondio-prompts write agent instructions` — write instructions for an agent
- `/brana:respondio-prompts review` — review existing prompts against best practices
- `/brana:respondio-prompts design handoff flow` — design multi-agent routing

## Step Registry

On entry, create a CC Task step registry. Follow the [guided-execution protocol](../_shared/guided-execution.md).

Register these steps: ORIENT, AUDIT, WRITE, VALIDATE.

### Resume After Compression

If context was compressed:
1. Call `TaskList` — find CC Tasks matching `/brana:respondio-prompts — {STEP}`
2. The `in_progress` task is your current step — resume from there

## Process

```
Phase 1: Orient     — what agent, what goal, what existing system?
Phase 2: Audit      — check against platform constraints + best practices
Phase 3: Write/Fix  — produce or rewrite prompts
Phase 4: Validate   — character limits, field names, action chains, handoff safety
```

---

## Phase 1: Orient

### 1a: Parse arguments

Read `$ARGUMENTS`:
- If provided, use as starting context
- If empty, ask: "What do you need? (write new agent, review existing, design handoff, etc.)"

### 1b: Detect project context

Look for existing Respond.io prompt files:
- `agent-prompts*/` directories — existing agent systems
- `docs/prompt-system-best-practices.md` — platform research (read if found)
- `**/instructions.md`, `**/actions.md`, `**/kb-*.md` — agent files
- `**/VARIABLE_VALIDATION.md` — contact field registry

If `docs/prompt-system-best-practices.md` exists, read it — it contains project-specific platform research that supplements the constraints in this skill.

### 1c: Classify task

| Task | What to do |
|------|-----------|
| Write new agent | Full Phase 2-4 cycle |
| Review existing | Phase 2 audit + Phase 3 fixes |
| Design handoff | Focus on multi-agent routing patterns |
| Write KB files | Focus on template design + keyword anchors |
| Debug behavior | Diagnose against known platform constraints |

---

## Phase 2: Audit

Check existing prompts (or design requirements) against platform constraints. Flag violations.

### Audit checklist

1. **Character limits**: instructions ≤10,000 chars, action prompts ≤1,000 chars, comments ≤2,000 chars
2. **4-part framework**: CONTEXT → ROLE & COMMUNICATION STYLE → FLOW → BOUNDARIES
3. **KB references**: use semantic anchors ("search for 'TEMPLATE: X'"), never section-based ("Ver KB C") or filename-based. Retrieval is vector/semantic search — TEMPLATE: anchors work as unique semantic targets.
4. **Dual-mention rule**: every action referenced in BOTH instructions AND action settings
5. **Silent handoffs**: explicit "Do not respond to the Contact when assigning to [AI agent]"
6. **System Override Protection**: lifecycle updated BEFORE close action
7. **Contact field names**: exact match required (silent failures on typos)
8. **Anti-loop**: bot-message check at flow start, never-route-back rules
9. **Single source of truth**: no duplicated prices, doctor names, addresses across agents
10. **Action independence**: distinguish chained (output→input) from independent (different triggers) — only chains have the 2-3 limit
11. **Follow-up chain**: last follow-up routes to a closing action, not a dead-end
12. **Variable prefix consistency**: `@` for users/teams/AI agents, `$contact.` for fields, `%` for tags, `!` for workflows
13. **Null-check guards**: data collection steps check `$contact.field` before asking (skip if populated)
14. **Spam handling**: entry-point agent has explicit spam detection + silent close pattern
15. **Fallback section exists**: separate from BOUNDARIES — recovery paths when intent unclear or KB misses

---

## Phase 3: Write/Fix

### Writing instructions

Follow the 4-part framework strictly:

```markdown
# CONTEXT
Who the agent is, goal, audience, lifecycle scope, KB files attached.

# ROLE & COMMUNICATION STYLE
Persona, tone, language (e.g., argentino "vos"), emoji policy, formatting.
WhatsApp bold: *texto*. Progressive messaging: message → WAIT → next.

# FLOW
Step-by-step sequence with decision tables.
Step 0: anti-loop check (bot-message → WAIT).
Step 0.1: read handoff context from contact fields.
Each step ends with WAIT or STOP.
Keyword search guidance: "search for 'TEMPLATE: FAQ-DOLOR'"

# BOUNDARIES
Scope limits, valid assignment targets, escalation triggers.
"Do not respond to the Contact when assigning to another AI agent."
```

### Writing principles

| Principle | Do | Don't |
|-----------|-----|-------|
| Positive framing | "Respond with empathy first" | "NEVER skip empathy" |
| Normal language | "Use this when..." | "CRITICAL: You MUST..." |
| Motivate rules | "Leave OPEN because humans need the conversation" | "NEVER close" (no reason) |
| Explicit conditions | "When pain reported, assign to @Team Euge" | "Escalate if serious" |
| Keyword guidance | "Search for 'TEMPLATE: OBJECION-CARO'" | "Ver KB Sección B" |

### Instruction patterns (beyond the core 4)

Production instructions benefit from dedicated sections beyond CONTEXT/ROLE/FLOW/BOUNDARIES:

| Section | Purpose | When to include |
|---------|---------|-----------------|
| `# FOLLOW UP HANDLING` | Instruction-driven inactivity logic with timing and messages | When follow-up needs precise scripting beyond UI config |
| `# FALLBACK HANDLING` | Recovery when intent is unclear or KB returns nothing | Always — separate from BOUNDARIES (prohibitions ≠ recovery) |
| `# SPAM HANDLING` | Detect spam/promotional messages, close without engaging | Entry-point agents receiving unfiltered inbound |
| `# CHECK MISSING DATA` | Guard: only ask if `$contact.field` is null/undefined | Agents collecting data contacts may already have |
| `# COLLECT INFORMATION` | Sequence: ask one → save immediately → ask next | Data collection agents — prevents loss on drop |
| `# BUSINESS HOURS` | Hours in instructions for self-serve "we're closed" replies | When agents must distinguish hours without a workflow |

**Key patterns:**
- **Null-check before asking**: `Only ask for [field] if $contact.[field] is missing, null, or undefined`
- **Save before next ask**: persist each field immediately, before requesting the next
- **Redundancy for critical rules**: repeat safety-critical behaviors 2-3 times across FLOW, BOUNDARIES, and FALLBACK
- **Fallback ≠ Boundaries**: boundaries are prohibitions ("never invent"), fallbacks are recovery actions ("if unclear, escalate")

### Writing action prompts

Each action ≤1,000 chars. Format: `When [condition], [action verb] to [exact target name].`

**Action execution order**: actions fire BEFORE the reply message. For silent handoffs the agent must be told NOT to respond. For announced handoffs the transition message IS the reply.

**8 action types — syntax + primary gotcha:**

| # | Action | Canonical syntax | Primary gotcha |
|---|--------|-----------------|----------------|
| 1 | Close | `Close with category "[Name]", note "[text]"` | Categories must pre-exist. Update lifecycle BEFORE close. Summary + close only after user is informed of next steps. |
| 2 | Assign | `Assign to @[Team/User/Agent]` | Agent continues responding unless told to stop. Two load-balancing modes: round robin, least open conversations. 2-attempt clarification threshold before fallback assign. |
| 3 | Lifecycle | `Update Lifecycle stage to "[Stage]"` | Exact names, case-sensitive. Must execute BEFORE close. Bidirectional (advance or regress). Triggered by intent signals, often paired with Assign. |
| 4 | Contact Fields | `Update $contact.[field] to [value]` | Silent failures on typos — names must match Settings. Reactive capture: update when shared, not when asked. Action prompts use natural language field names; `$contact.` prefix is for instructions. |
| 5 | Comments | `Add comment: "[text]"` | ≤2,000 chars. Write-only — agents cannot read comments. Always paired with Assign (handoff artifact). Two archetypes: handoff summary (summary + next action) and escalation brief (issue + done + reason). |
| 6 | Tags | `Add tag %[TagName]` / `Remove tag %[TagName]` | Cannot read/check tags. One-way signals to Workflows. Bidirectional: intent-based add, resolution-based remove. Tags are boolean state signals, not data. |
| 7 | Workflow | `Trigger workflow ![name]` | No variable passing. Must be published. Set fields first. |
| 8 | Handle Calls | `Handle inbound calls` | Inbound only. 3-min cap. No mid-call transfer. Uses different instruction architecture: CALL CONTEXT / ROLE / COMMUNICATION STYLE / MUST DO / MUST NOT DO / FALLBACK / ERROR HANDLING. No FLOW section — voice is conversational, not sequential. No action chaining. |

**Variable prefixes** (Respond.io platform standard): `@` users/teams/AI agents, `$` fields/variables, `%` tags, `!` workflows. `{{ }}` in examples is human-readability markup only — not parsed by agents in prompts.

### Writing KB files

**Retrieval**: vector/semantic search over content — not keyword matching or filename search. Agents cannot prioritize or choose between sources; all enabled sources are searched equally.

**Supported formats**: PDF, TXT, MD, CSV, DOCX, PPTX, PPSX, images (JPEG, PNG, BMP, WEBP, TIFF). Snippets NOT supported for AI Agents.

**Limits**: 20MB per file (paid), 100 files per workspace, 20MB total, 50 daily add/edit actions, 3 sources processed in parallel per response.

**Content rules**:
- Every template: `TEMPLATE: UNIQUE-ID` header (semantic anchor for retrieval)
- Descriptive section headers (agents find via semantic search, not filename)
- Verbatim copy-paste content (prevents hallucination)
- FAQ format: full question + full answer (not minimal "Yes/No")
- Topic-specific files over monoliths (higher signal-to-noise)
- Shared data in a single file attached to all agents (prices, doctors, scope)
- Clear headings, bold key points, full sentences, clean tables
- Multilingual: auto-detects and responds in contact's language

### Multi-agent handoff patterns

**AI → AI (silent)**:
1. Update contact fields (handoff_source, handoff_context)
2. Assign to AI agent
3. Do NOT respond (explicit stop required)
4. Receiving agent reads contact fields (not comments — AI agents can't read comments)

**AI → Human (announced)**:
1. Update contact fields
2. Add Comment (audit trail for humans)
3. Assign to @Team
4. Send transition message to user
5. Leave OPEN — never close

**The 20-message problem**: critical context from early messages may be invisible to later agents. Mitigate with contact fields (primary), short flows, front-loaded data collection.

### Follow-up configuration

Follow-ups are configured in Respond.io UI, but instructions handle post-follow-up routing.

| Constraint | Limit |
|-----------|-------|
| Max follow-ups | 5 |
| Max interval | 24h after last message |
| Testing | Live sessions only (not Preview Mode) |
| Last follow-up | Must chain to closing action (e.g., route to Cierre) |

Design rules:
- UI configures follow-up messages and timing
- Instructions handle routing when follow-ups exhaust ("after follow-up with no response → route to Cierre")
- Never rely on follow-ups for core flow — they're a safety net for inactivity

---

## Phase 4: Validate

Run these checks on every output:

### Character counts

```bash
wc -c instructions.md  # Must be ≤ 10,000
```

For action prompts, each individual prompt block must be ≤1,000 chars.

### Field name validation

Cross-reference all `$contact.fieldName` references against `VARIABLE_VALIDATION.md` or Settings. Flag any that might be misspelled.

### Variable prefix validation

Cross-reference all variable references for correct prefix usage:
- [ ] `@Team`/`@Agent` targets match Respond.io workspace names
- [ ] `$contact.fieldName` uses correct prefix and exact field name
- [ ] `%TagName` tags exist in Settings → Tags
- [ ] `!workflow_name` workflows are published (not draft)

### Handoff safety

For every `[Assign]` in instructions:
- [ ] Is the target a valid name? (exact match)
- [ ] Is `handoff_source` + `handoff_context` set before assign?
- [ ] Is "do not respond" included for AI-to-AI?
- [ ] Is lifecycle updated BEFORE close (if closing)?
- [ ] Is conversation left OPEN for @Team assignments?

### Anti-loop check

- [ ] Step 0 checks if last message is from BOT
- [ ] No circular routing (e.g., Cierre never routes to Clasificador)
- [ ] Template dedup: if already sent → SHORT reminder

### KB coverage

For every "search for 'TEMPLATE: X'" in instructions:
- [ ] That template ID exists in an attached KB file
- [ ] The KB file is attached to this agent in Respond.io

---

## Platform Constraints

Essential limits that affect every decision. For full details, check `docs/prompt-system-best-practices.md` if available in the project.

| Resource | Limit |
|----------|-------|
| Instructions | 10,000 chars |
| Action prompts | 1,000 chars each |
| Internal comments | 2,000 chars |
| Conversation visibility | Last 20 messages |
| KB files per workspace | 100 files, 20MB total, 20MB per file (paid), 50 daily changes |
| Response time | 10-15s typical, 20s+ with KB |

**What agents CANNOT do**: see beyond 20 messages, see assignment history, distinguish AI from human messages, search KB by filename or title, prioritize between KB sources, send files/images/video, read internal comments, read/check tags, detect field update failures, create new lifecycle stages/fields/categories, pass variables to workflows, detect agent online status.

---

## Rules

1. **Always validate character counts** before presenting final output. Platform silently truncates.
2. **Always check field names** against VARIABLE_VALIDATION.md or Settings.
3. **Never use section references** ("Ver KB C"). Always use keyword search guidance.
4. **Every assign needs handoff fields** — handoff_source + handoff_context set before every assignment.
5. **Silent handoffs need explicit stop** — "Do not respond to the Contact when assigning."
6. **Lifecycle before close** — always. No exceptions.
7. **KB templates are verbatim** — never paraphrase. Prevents hallucination.
8. **One message, then WAIT** — progressive messaging is non-negotiable for WhatsApp/IG.
9. **When in doubt, escalate to human** — better to over-escalate than hallucinate medical info.
10. **Test one block at a time** — modify one prompt section, test, then modify the next.
