# Agent Delegation TDD Checklist

Include this checklist in every agent delegation prompt that expects code output.

---

## Acceptance Criteria

Your output is only complete when ALL of the following are true:

- [ ] Tests written BEFORE implementation (failing tests first)
- [ ] Tests cover the happy path AND at least 2 boundary cases
- [ ] Implementation makes the tests pass
- [ ] All pre-existing tests still pass (no regressions)
- [ ] Behavior documented in the relevant `.md` file (procedure, ADR, or reference doc)
- [ ] No placeholder comments like `// TODO implement` in submitted code

If any criterion is unmet, continue working — do not mark the task done.
