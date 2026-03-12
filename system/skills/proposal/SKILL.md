---
name: proposal
description: "Generate a client proposal — interview-driven, structured markdown with cost breakdown and timeline. Use when preparing a service proposal for a client."
group: venture
allowed-tools:
  - Bash
  - Read
  - Write
  - Glob
  - Grep
---

# Proposal — Client Proposal Generator

Generate a professional client proposal in markdown. Interview the user, scan project context, produce a structured document ready for PDF export.

## Process

### 1. Parse arguments

If `$ARGUMENTS` is empty, ask for the project/client name. If provided, use it directly (e.g., `/brana:proposal mandawa`).

### 2. Locate project root

Try to find the project directory:

```bash
# Check common locations
project_root=$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")
```

Also check `~/projects/{name}` if the current directory doesn't match the project name.

### 3. Scan existing context

Silently scan the project for context that informs the proposal:

- `CLAUDE.md` or `.claude/CLAUDE.md` — project conventions, tech stack
- `features/` or `docs/features/` — feature briefs
- `propuesta-*.md` — previous proposals (reuse rate, style)
- `docs/decisions/` — architectural decisions that affect scope

Summarize what you found to the user: "I found X, Y, Z — I'll use this as context."

### 4. Interview

Ask the user about the proposal. Skip questions where the answer is already clear from context or conversation. Use AskUserQuestion for structured choices where appropriate.

**Required:**

1. **The problem** — What problem does the client have? What's the current situation?
2. **What was found** — What did you discover during diagnosis/research? Technical findings, current state.
3. **Options** — What are the possible approaches? (Can be one or multiple)
   - For each option: description, pros, cons, effort estimate in hours
4. **Phases** — Break the work into phases. Each phase must be a **clear deliverable** (see Phase Deliverable Test below).
5. **Recommendation** — If multiple options, which one and why? (Skip if single option)
6. **Rate** — Hourly rate in USD? (Default: $65/hr — confirm with user)
7. **Timeline** — Expected delivery timeline per phase
8. **Outcome** — What does the client get at the end?

**Optional (ask if relevant):**

9. **Aclaraciones** — Any clarifications about billing, scope boundaries, what's excluded?
10. **Recurring costs** — Hosting, subscriptions, maintenance?

### Phase Deliverable Test

Every phase in the proposal must pass this test before writing. If a phase fails, merge it with an adjacent phase or restructure.

**The 3 questions (all must be YES):**

1. **Can we demo it?** — After this phase, can we show the client something tangible? A working feature, a report, a document, a system they can interact with?
2. **Does it add value standalone?** — If the client stops here, did they get something useful? Not just infrastructure or setup — actual value they can use.
3. **Is there a clear decision point?** — Can the client say "yes, continue" or "no, stop here" based on what they received?

**Anti-patterns (phases that fail the test):**

- "Database setup" — infrastructure, not a deliverable. Merge into the first phase that produces user-facing output using that database.
- "Learning/auto-improvement" — a feature enhancement, not a standalone deliverable. Merge into the phase that delivers the core system.
- "Testing" — quality assurance is part of each phase, not a separate deliverable.
- "Integration" — wiring things together is part of building, not a separate deliverable.
- "Configuration" — setup is invisible to the client. Merge into the first visible phase.

**Good phases (pass the test):**

- "Prueba de concepto" — client sees a precision report, decides go/no-go
- "Extracción y códigos" — client uploads files, gets a sheet with data extracted. Immediate value.
- "Validación completa" — the sheet now includes calculations, alerts, and self-improvement. Full value.
- "Ajuste fino" — system calibrated with real data, ready for autonomous daily use.

**Apply the test:** After the user provides phases, validate each one against the 3 questions. If any phase fails, propose a restructured phase list and explain why. Get approval before proceeding.

### 5. Generate proposal

Write `propuesta-{slug}.md` at the project root. Slugify the proposal topic (e.g., "integracion payway" → `propuesta-integracion-payway.md`).

Use this template — adapt sections based on whether there are multiple options or just one:

```markdown
# Propuesta: {Title} — {Client/Project Name}

> **Preparada por:** Martin Rios
>
> **Fecha:** {today, format: D de MMMM de YYYY, in Spanish}
>
> **Validez:** 30 dias a partir de la fecha

---

## El problema

{Problem description. Written in third person, professional tone. Spanish.}

---

## Que se encontro

{Technical findings, current state diagnosis. Include subsections if needed.}

---
```

**If multiple options:**

```markdown
## Opciones

{Brief intro to the options.}

### Opcion A — {Name}

{Description of the approach, step-by-step flow if applicable.}

**Ventajas:**
- {Pro 1}
- {Pro 2}

**Desventajas:**
- {Con 1}
- {Con 2}

| | |
|---|---|
| **Esfuerzo** | ~{hours} horas |
| **Costo recurrente** | {recurring or "Ninguno"} |
| **Experiencia del cliente** | {one-line UX summary} |

---

### Opcion B — {Name}

{Same structure as Option A}

---

## Que se recomienda

{Recommendation with reasoning. When to prefer the alternative.}

---
```

**If single option, replace "Opciones" with:**

```markdown
## Que se hara

{Brief overview of the approach — 1-2 paragraphs.}

{Then describe each phase as a subsection. Each phase MUST pass the Phase Deliverable Test.}

### Etapa N — {Name}: {one-line value statement}

{What gets built in this phase. Concrete, not abstract.}

**Entregable:** {What the client receives — be specific. Show examples (tables, screenshots, workflows).}

**Lo que {user} deja de hacer después de esta etapa:**
- {Concrete pain point eliminated}

**Lo que {user} todavía hace:**
- {What remains manual — be honest}

**Por qué importa:** {Why this phase exists as standalone value.}

**Decisión al final:** {Go/no-go or continue/stop decision point.}

---
```

**Cost and timeline sections (always present):**

```markdown
## Que incluye

{If multiple options, one subsection per option. Tasks grouped by phase.}

| Etapa | Tarea | Horas |
|-------|-------|-------|
| **N — {Phase name}** | | |
| | {Task 1} | {hours} |
| | {Task 2} | {hours} |
| | *Subtotal* | *{subtotal}* |
| **N — {Phase name}** | | |
| | {Task 1} | {hours} |
| | *Subtotal* | *{subtotal}* |
| **Total** | | **{total}** |

---

## Inversion

| | |
|---|---|
| **Tarifa** | USD ${rate}/hora |
| **Horas** | {total hours} |
| **Total** | **USD ${rate * hours}** |

Se puede pagar por etapa a medida que se avanza:

| Etapa | Horas | Costo |
|-------|-------|-------|
| N — {Phase name} | {hours} | USD ${cost} |
| N — {Phase name} | {hours} | USD ${cost} |
| **Total** | **{total hours}** | **USD ${total cost}** |

{If applicable:}

### Costos operativos del sistema (post-implementación)

| Concepto | Detalle | Costo mensual |
|----------|---------|--------------|
| {Item} | {Detail} | {cost} |
| **Total** | | **{total}** |

**Aclaraciones:**
- Las horas son de trabajo activo. Tiempos de espera no se facturan.
- Cada etapa se paga al entregar. No se avanza sin aprobación de la etapa anterior.
- {Additional billing clarifications}
- {Scope boundaries — what's excluded}

---

## Cronograma

{Timeline with clear deliverable per phase:}

    Semana(s) N    Etapa N — {Phase name}
                   {Any client dependency}
                   → Entrega: {specific deliverable, not vague}

Tiempo total estimado: {weeks} semanas.

---

## Resultado

{What the client gets at the end. Paint the picture of the improved state. Include:}
- What the user stops doing (concrete pain points eliminated)
- What the organization gains (time, accuracy, independence)
- Quantified impact where possible (hours saved, error reduction)
```

### 6. Page breaks

Insert `<div style="page-break-before: always;"></div>` before these sections to ensure clean PDF pagination:

- Before "Opciones" or "Que se hara"
- Before "Que se recomienda" (if present)
- Before "Inversion"
- Before "Cronograma"

### 7. Write and report

Write the file. Show the user:
- File path
- Section summary
- Recommend: "Run `/brana:export-pdf propuesta-{slug}.md` to generate the PDF."

## Rules

- **All proposal content in Spanish.** The template, section headers, and content are in Spanish. Technical terms can stay in English where natural (API, webhook, deploy).
- **Professional but direct tone.** No filler, no jargon inflation. Write like you're explaining to a smart non-technical person.
- **Hours must be specific.** Never "TBD" — estimate even if approximate. Use ranges (8-12) if uncertain.
- **Hours must be realistic.** Challenge optimistic estimates. Account for: prompt/AI iteration, API integration surprises, testing, edge cases discovered during fine-tuning that require rework in earlier stages. If in doubt, add 30-50% to the "happy path" estimate.
- **Every phase must pass the Phase Deliverable Test.** No infrastructure-only phases, no feature-only phases. If a proposed phase fails the 3 questions, restructure before writing.
- **Rate defaults to $65/hr** but always confirm with the user before generating.
- **Author is always "Martin Rios"** unless the user specifies otherwise.
- **Validity is always 30 days** unless the user specifies otherwise.
- **Don't invent technical details.** If the interview didn't cover something, ask — don't fill in plausible-sounding technical specifics.
- **Reuse previous proposal style.** If you found existing `propuesta-*.md` files, match their tone and structure.
