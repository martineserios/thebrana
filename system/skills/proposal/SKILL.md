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

If `$ARGUMENTS` is empty, ask for the project/client name. If provided, use it directly (e.g., `/proposal mandawa`).

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
4. **Recommendation** — If multiple options, which one and why? (Skip if single option)
5. **Rate** — Hourly rate in USD? (Default: $65/hr — confirm with user)
6. **Timeline** — Expected delivery timeline per option
7. **Deliverables** — What does the client get at the end?

**Optional (ask if relevant):**

8. **Aclaraciones** — Any clarifications about billing, scope boundaries, what's excluded?
9. **Recurring costs** — Hosting, subscriptions, maintenance?

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

{Description of the approach.}

---
```

**Cost and timeline sections (always present):**

```markdown
## Que incluye

{If multiple options, one subsection per option.}

### {Option Name}

| Tarea | Horas |
|-------|-------|
| {Task 1} | {hours} |
| {Task 2} | {hours} |
| **Total** | **{total}** |

---

## Inversion

### {Option Name}

| | |
|---|---|
| **Tarifa** | USD ${rate}/hora |
| **Horas** | {total hours} |
| **Total** | **USD ${rate * hours}** |
| **Costo recurrente** | {if applicable} |

**Aclaraciones:**
- {Billing clarifications}
- {Scope boundaries}
- {What's excluded}

---

## Cronograma

### {Option Name}

{Timeline as a simple text block or table.}

---

## Resultado

{What the client gets at the end. Paint the picture of the improved state.}
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
- Recommend: "Run `/export-pdf propuesta-{slug}.md` to generate the PDF."

## Rules

- **All proposal content in Spanish.** The template, section headers, and content are in Spanish. Technical terms can stay in English where natural (API, webhook, deploy).
- **Professional but direct tone.** No filler, no jargon inflation. Write like you're explaining to a smart non-technical person.
- **Hours must be specific.** Never "TBD" — estimate even if approximate. Use ranges (8-12) if uncertain.
- **Rate defaults to $65/hr** but always confirm with the user before generating.
- **Author is always "Martin Rios"** unless the user specifies otherwise.
- **Validity is always 30 days** unless the user specifies otherwise.
- **Don't invent technical details.** If the interview didn't cover something, ask — don't fill in plausible-sounding technical specifics.
- **Reuse previous proposal style.** If you found existing `propuesta-*.md` files, match their tone and structure.
