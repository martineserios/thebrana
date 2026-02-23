---
name: meta-template
description: "Write Meta WhatsApp templates optimized for Utility classification — empirically validated formula, safe elements, kill lines, appeal texts. Use when creating or reviewing WhatsApp Business templates for any project."
allowed-tools:
  - Read
  - Write
  - Edit
  - Glob
  - Grep
  - Task
---

# Meta WhatsApp Template Writer

Write WhatsApp Business templates that hit the Utility sweet spot — maximum warmth that passes Meta classification without appeal friction. Based on empirically validated formula (tested 2026-02-20).

## When to use

When creating, reviewing, or rewriting WhatsApp Business templates for any project that sends messages via Meta's WhatsApp Business API.

**Invocation:**
- `/meta-template` — interactive mode, ask what template to build
- `/meta-template [template purpose]` — build a specific template (e.g., `/meta-template appointment confirmation`)
- `/meta-template review` — audit existing templates against the formula
- `/meta-template appeal [template name]` — generate appeal text for a template

---

## Process

```
Phase 1: Orient     — what project, what template, what tone?
Phase 2: Classify   — Utility or Marketing? Pick the right tier.
Phase 3: Write      — apply the formula
Phase 4: Validate   — check against kill lines, char limits, variable examples
Phase 5: Appeal     — generate appeal text if needed
```

---

## Phase 1: Orient

### 1a: Parse arguments

Read `$ARGUMENTS`:
- If provided, use as starting context (template purpose, project name)
- If empty, ask: "What template do you need? (appointment confirmation, follow-up, welcome, etc.)"

### 1b: Load cross-project formula

Read `~/.claude/memory/meta-whatsapp-templates.md` — this contains the empirically validated formula, safe elements, and kill lines.

### 1c: Detect project context

Look for project-specific tone and template files:
- `**/tone-reference.md` — client's natural voice and patterns
- `**/templates.md` — existing templates and their statuses
- `**/template-categories.md` — template audit/inventory
- `**/errors.md` — known Meta API errors for this account

If a tone reference exists, read it to calibrate warmth. The template should feel like the client's voice filtered through the Utility formula.

### 1d: Gather template requirements

Ask (skip what's already clear):
1. **What triggers this message?** — what event causes the template to be sent? (appointment booked, surgery scheduled, inquiry received, payment confirmed, etc.)
2. **What information does it contain?** — dates, times, locations, instructions, next steps?
3. **What action does the recipient need to take?** — confirm, send documents, reply, nothing (just awareness)?
4. **What variables are needed?** — patient/client name, dates, advisor name, etc.
5. **What language/dialect?** — Spanish (ARG with voseo), Spanish (neutral), English, Portuguese, etc.

---

## Phase 2: Classify

### Is this Utility or Marketing?

| Question | Utility | Marketing |
|----------|---------|-----------|
| Did the recipient initiate contact or a transaction? | Yes — they booked, messaged, purchased | No — cold outreach, re-engagement |
| Does it reference a specific event/transaction? | Yes — "tu turno del 15/03" | No — generic greeting or offer |
| Does it require the recipient to DO something? | Yes — confirm, send docs, take medication | No — just brand awareness |
| Could a hospital/bank send an equivalent message? | Yes — appointment reminders, statements | No — promotional content |

If 3+ answers are "Utility" → target Utility classification.

### Pick the tier

| Tier | When to use | Approval path |
|------|-------------|---------------|
| **Tier 1 (C-level)** | Template has a natural transactional anchor ("recibimos tu consulta", "tu turno está confirmado") | Direct Utility — no appeal needed |
| **Tier 2 (D-level)** | No natural anchor, but strong service/medical context | Appeal required — write appeal text |
| **Marketing** | No transaction, no user-initiated event | Submit as Marketing, don't appeal |

**Default to Tier 1.** Only use Tier 2 when the use case genuinely can't include an anchor phrase.

---

## Phase 3: Write

### The C-level formula (Tier 1 — default)

```
┌─────────────────────────────────────────────────────┐
│ HEADER (text): [Clinical/transactional label]       │
│   Max 60 chars, 1 variable max, no formatting       │
├─────────────────────────────────────────────────────┤
│ BODY:                                               │
│                                                     │
│   Hola {{nombre}}, [TRANSACTIONAL ANCHOR].          │
│   [Optional: Soy {{asesora}}, tu [role].]           │
│   [Optional: warm process language]                 │
│                                                     │
│   [Core information with *bold* labels]             │
│   - *Label:* value                                  │
│   - *Label:* value                                  │
│                                                     │
│   [Optional: direct question to recipient]          │
│   [Optional: business hours / next steps]           │
│                                                     │
│   Podés [responder/escribirnos] por esta vía        │
│   [+ functional close].                             │
├─────────────────────────────────────────────────────┤
│ BUTTONS (optional): functional only                 │
│   Quick Reply: CONFIRMO / REPROGRAMO                │
│   Never: "Shop Now", "Check Out", "Learn More"     │
└─────────────────────────────────────────────────────┘
```

### Transactional anchors by use case

| Use case | Anchor phrase |
|----------|---------------|
| Patient/client sent inquiry | "recibimos tu consulta" / "recibimos tu mensaje" |
| Appointment booked | "tu turno está confirmado para el..." |
| Surgery/procedure scheduled | "tu cirugía está programada para el..." |
| Post-op/post-service follow-up | "se cumplen N semanas de tu [procedimiento]" |
| Document/action required | "necesitamos recibir [docs] antes de..." |
| Payment received | "recibimos tu pago" / "tu pago fue confirmado" |
| Order placed | "recibimos tu pedido" / "tu pedido está en proceso" |
| Delivery update | "tu pedido está en camino" / "tu envío sale el..." |
| Account update | "tu cuenta fue actualizada" / "tu solicitud fue procesada" |

### Safe elements (use freely)

- Voseo: "podés", "contame", "respondé", "comunicáte", "escribinos"
- `*bold*` formatting on labels and key data
- Clinical/transactional text headers
- "Acompañar" / "orientar" / "queremos ayudarte"
- Direct questions framed as info-gathering ("¿Podés contarme sobre tu caso?")
- Business hours
- Personal advisor/contact name via variable
- "Podés escribirnos/responder por esta vía"
- Functional close: "te orientamos", "te ayudamos"

### Kill lines (never include)

| Element | Risk level | Notes |
|---------|-----------|-------|
| Emojis (any) | **HARD KILL** | Instant Marketing classification |
| "¿Cómo estás?" | **HARD KILL** | Social greeting = Marketing |
| Generic greeting without anchor | **HARD KILL** | "Hola, en qué te ayudo?" fails even on appeal |
| Gratitude ("gracias por elegirnos") | RISKY | Needs appeal to pass — avoid |
| Brand description ("somos un equipo de...") | RISKY | Needs appeal to pass — avoid |
| "Nos encantaría" | RISKY | Aspirational language — avoid |
| Team signature ("Equipo X") | AVOID | Branding signal |
| Exclamation greetings ("Hola!") | AVOID | Only passed in D-level (appeal needed) |
| Footer branding | AVOID | Contributes to Marketing signal |
| "Shop Now" / "Check Out" buttons | **HARD KILL** | Meta docs explicit |

### Adapting to project tone

If a `tone-reference.md` exists:
1. Read the client's natural patterns (greeting style, word choices, formality)
2. Map each pattern to the safe/kill classification above
3. Keep safe elements from their natural voice (voseo, word choices, sentence rhythm)
4. Replace kill elements with their closest safe equivalent:
   - Emojis → `*bold*` for emphasis
   - "Gracias por elegirnos" → (remove entirely)
   - Team signature → (remove)
   - "Nos encantaría" → "queremos ayudarte"
   - "Hola! Cómo estás?" → "Hola {{nombre}}, [anchor]"

---

## Phase 4: Validate

Run these checks on every template before presenting:

### Character limits

| Component | Limit |
|-----------|-------|
| Header (text) | 60 chars, 1 variable max |
| Body | 1024 chars |
| Footer | Not used (branding risk) |
| Buttons | 3 max, 25 chars each |

### Kill line scan

Go through the body word by word. Flag ANY of:
- [ ] Emojis present?
- [ ] "Cómo estás" or social greetings?
- [ ] "Gracias por" + anything?
- [ ] Brand description or team intro?
- [ ] "Nos encantaría" or aspirational language?
- [ ] Team signature or footer branding?
- [ ] Exclamation marks in greeting? ("Hola!")
- [ ] Promotional buttons?

### Anchor check

- [ ] Does the opening sentence contain a transactional anchor?
- [ ] Does the anchor tie to a specific event the recipient initiated?

### Variable examples

Prepare realistic example values for each variable — vague placeholders trigger misclassification at submission.

| Variable | Bad example | Good example |
|----------|-------------|--------------|
| {{1}} | "nombre" | "María Laura" |
| {{2}} | "fecha" | "15 de marzo de 2026" |
| {{3}} | "hora" | "10:30" |

---

## Phase 5: Appeal (if needed)

Generate appeal text only for Tier 2 templates or templates that get rejected.

### Appeal text formula

```
This template is [sent exclusively to / an automated response for] [recipients]
who [specific triggering event].

It [contains/confirms/requests] [specific content: dates, instructions, documents, etc.].

The [recipient] initiated this [transaction/interaction] by [specific action].

This is [equivalent real-world analogy] — equivalent to a [hospital appointment reminder /
pharmacy prescription notification / bank statement / shipping notification].

It meets Meta's Utility category definition: a message related to an existing transaction
that [requires user awareness / requires user action (specific action)].
```

### Appeal process

1. Submit template as Marketing (Meta ML will flag it regardless)
2. Wait for approval as Marketing
3. Appeal within 60 days via Business Support Home
4. Paste the appeal text — human reviewer evaluates content
5. Expected timeline: 24-72h per appeal
6. If rejected: revise wording, 1 re-appeal allowed

---

## Output Format

Present each template as:

```markdown
### `template_name` — [Purpose]

| Component | Content |
|-----------|---------|
| **Header (text)** | [header] |
| **Body** | see below |
| **Buttons** | [buttons or "none"] |

> [Full body text with formatting]

**Classification:** Utility (Tier 1/2) or Marketing
**Anchor:** [the anchor phrase used]
**Variables:** {{1}} = [example], {{2}} = [example]
**Char count:** [N] / 1024
**Appeal text:** [if Tier 2, include full appeal text]
```

---

## Rules

1. **Always load the formula first.** Read `~/.claude/memory/meta-whatsapp-templates.md` before writing any template.
2. **Default to Tier 1 (C-level).** Only drop to Tier 2 when the template genuinely can't include a transactional anchor.
3. **Never include emojis.** Not even one. This is a hard kill confirmed empirically.
4. **Always validate character counts.** Meta silently truncates.
5. **Always prepare variable examples.** Vague placeholders cause misclassification.
6. **Adapt to the project's voice.** Read tone-reference if available. The template should feel like the client wrote it — minus the kill elements.
7. **One template at a time.** Present, validate, confirm with user before writing the next.
8. **If reviewing existing templates:** flag every kill-line violation, propose specific rewrites, classify risk level.
