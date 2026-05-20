---
paths: ["system/procedures/**", "system/skills/**"]
---
# Ruflo Stub Guard

Never use these ruflo commands as authoritative signals. They return hardcoded
or unimplemented output regardless of input:

| Command / Tool | Stub behavior | Safe alternative |
|---|---|---|
| `ruflo security-scan` / `mcp__ruflo__aidefence_scan` | Returns hardcoded fake vulnerability counts | Manual code review; validate.sh |
| `ruflo deploy` | No real implementation; always "succeeds" | `git merge main`; Vercel/Cloud Run deploy |
| Memory quantization output | Reports hardcoded 3.92× compression factor | Treat as display-only; never use in capacity calculations |

**Why:** Confirmed stubs via source audit (issue #1482) and live testing (t-1549,
2026-05-20). Trusting these outputs has caused false security confidence and
incorrect capacity estimates in prior sessions.

**Scope:** This rule applies whenever writing or reviewing procedures and skills
that might reference these tools. For hooks that call ruflo, add a `# STUB — do not trust`
comment next to any of the three patterns above.
