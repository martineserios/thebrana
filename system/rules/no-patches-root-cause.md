---
always-load: true
---
# No Patches — Fix Root Causes

When a review, test failure, or finding surfaces a defect, do not stop at the fix that makes the symptom go away. Ask what *class* of problem produced it, and close that class.

- **A patch narrows who/what triggers the bug.** A root-cause fix removes the capability that made the bug possible in the first place.
- Before applying a fix, ask: "if I only did this, what's the next-worst thing that could still happen through the same mechanism?" If the answer is non-trivial, the fix is incomplete.
- Symptom-only fixes are acceptable ONLY when explicitly scoped as a stopgap, stated as such, with the real fix logged as a follow-up — never presented as done.

```
Example — a security review flags that an admin endpoint is gated by a secret
whose documented threat model doesn't cover the endpoint's actual blast radius.

PATCH:       swap in a better-scoped secret. Fixes "who can call this,"
             leaves "what a caller can do" untouched — the endpoint can still
             silently overwrite already-live production state forever.
ROOT CAUSE:  swap the secret AND remove the capability that made the finding
             dangerous in the first place (e.g. require an explicit
             confirmation to overwrite existing state, not just fresh writes).
             A leak of either secret now has a structurally smaller blast
             radius, not just a differently-named one.
```

Applies to bug fixes, challenger/evaluator findings, incident follow-ups, and refactors alike. When time pressure genuinely forces a patch, say so out loud and open the root-cause fix as its own tracked item — don't let a patch quietly stand in as the resolution.
