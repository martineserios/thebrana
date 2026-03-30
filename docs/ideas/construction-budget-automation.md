# Construction Budget Automation

> Brainstormed 2026-03-26. Status: idea (paused — waiting for sample CAD/PDF files).

## Problem

Building construction budgets ("Planilla de Computo y Presupuesto de Mano de Obra") is a multi-hour manual process: extract quantities from CAD/PDF plans, assemble ~100+ line items across 9 rubros, apply unit prices, compute subtotals, format the client-facing document. Chicho (the engineer) does this manually each time.

## Context

- **Reference document:** `inbox/computo_chicho/NEWMAN JOVEN - PRESUPUESTO VARIOS RUBROS.pdf` (Sigma Construcciones, Arq. Schiavoni / Ing. Prado). 9 rubros, ~100 items, total $138.9M ARS mano de obra.
- **Inputs:** DWG (AutoCAD) files + PDFs. Layer naming varies by architect.
- **Constraints:** Must work with Argentine pricing (CAC index, pesos). Must integrate with Google Sheets/Excel. No SaaS budget.
- **User:** Chicho (engineer). Must be simple to operate.
- **Scale:** 1-2 week build for MVP.

## Proposed solution

End-to-end pipeline with 4 stages:

1. **Requirements mapping** — From plans, identify all needed items per rubro
2. **Quantity takeoff** — Parse CAD geometry (wall lengths, areas, room counts) to compute quantities in m2/ml/un/gl
3. **Pricing** — Collect/apply unit prices, compute subtotals, apply CAC multiplier
4. **Report generation** — Produce formatted budget document with manual supervision as final gate

## Research findings

### Market landscape
- **AI takeoff SaaS** (Beam AI, Togal.AI, Kreo): Read plans, extract quantities. 90%+ accuracy. Subscription, no public pricing, cloud-only. Not Argentine-market aware.
- **Argentina-specific**: Dataobra (presupuesto + Gantt), Nuqlea (material cost aggregation), Quercusoft (free 1000+ APU library). **None do AI plan reading + presupuesto end-to-end.**
- **Open-source**: OpenProject BIM, 4BIM (Python). No AI plan recognition.
- **Gap**: No tool bridges Argentine market needs (CAC, local rubros, pesos) with automated quantity takeoff.

### Technical feasibility
- DWG parsing: ezdxf (Python, open-source) can read DXF; ODA File Converter can batch DWG→DXF.
- PDF parsing: Requires OCR/vision — much harder than structured CAD.
- ~40-50% of budget items derive from CAD geometry (structure, flooring, walls, roofing). ~50% are design decisions (electrical, plumbing, fixtures, finishes) — not directly extractable from geometry.

### Approach options considered

| Option | Build time | Solves | Risk |
|--------|-----------|--------|------|
| A. Smart GSheets template | 2-3 days | Assembly + formatting. Manual quantities. | Low |
| B. Custom Python app | 1-2 weeks | Guided wizard + quantity estimation + PDF output | Medium |
| C. Hybrid (GSheets + Apps Script) | ~1 week | Familiar UI + automation guts | Low-Medium |
| D. CAD parser + GSheets | 1-2 weeks | Geometry quantities + assembly + formatting | Medium |

## Open questions (to resolve with sample files)

1. **CAD layer structure** — How consistent are layer names across projects? Can we build a mapping UI?
2. **Geometry → quantity mapping** — Which specific items can be auto-computed from CAD? Need to inspect actual DWG files.
3. **Spec items** — Do rules of thumb exist? (e.g., 1 toma per 4m2, 1 boca per ambiente). Could pre-populate estimates.
4. **PDF handling** — Is DWG always available, or are some projects PDF-only?
5. **Price database** — Does Chicho maintain a price list? How often do prices update?

## Risks

- **Layer inconsistency** across architects could make CAD parsing brittle → mitigation: interactive layer-mapping step
- **50% of items are spec decisions** not derivable from geometry → mitigation: accept hybrid (auto + manual), use rules of thumb where possible
- **Adoption** — Chicho may resist a new tool if it's more complex than his current process → mitigation: GSheets as the UI layer

## Next steps

1. **Get sample CAD files** (DWG) + corresponding PDFs from Chicho
2. Inspect layer structure and geometry to assess what's parseable
3. Build a proof-of-concept: DWG → quantity extraction for 1-2 rubros (e.g., structure, flooring)
4. Decide on output approach (GSheets template vs. custom app) based on findings
