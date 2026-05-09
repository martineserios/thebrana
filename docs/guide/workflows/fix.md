# Fixing Bugs

`/brana:fix` is a focused bug-fix flow: REPRODUCE → DIAGNOSE → FIX → VERIFY → COMMIT. Use it when you know something is broken and you want a tighter loop than `/brana:build`.

## Quick start

```
/brana:fix "JWT refresh returns 401 after 1h — token issued at login, refresh fails"
/brana:fix t-88           -- start from a task (loads description automatically)
/brana:fix                -- describe the bug interactively
```

## The 5 steps

### 1. REPRODUCE — prove it with a test

Before touching any source code, write a failing test that captures the bug. The test IS the spec — it defines what "fixed" looks like.

```
Test fails as expected: test_jwt_refresh_after_expiry — got 401, expected 200
```

If no test framework exists, write reproduction steps as a numbered list. Never change source code until a failing test (or reproduction case) exists.

### 2. DIAGNOSE — state a hypothesis

Trace the failing test back to root cause. A root cause is specific:

> "The nil check is missing in `parse_config()` — when the optional key is absent, it returns nil instead of the default value."

A symptom is not a hypothesis: "Something is wrong with config parsing" doesn't tell you where to look.

If uncertain, run one targeted experiment (add a log, write a second test). Revise once, then commit to the hypothesis.

### 3. FIX — minimal change

Make only what the hypothesis requires. Rules:
- Touch the minimum number of files (>3 files → the hypothesis may be too broad)
- No refactoring adjacent code while fixing
- No new features discovered during the fix — file a separate task

Run the failing test after each edit. Stop when it goes green.

### 4. VERIFY — no regressions

Run the full test suite. State the result:

```
N/N tests pass. Original symptom confirmed resolved.
```

Check 1-2 boundary cases adjacent to the fix. If tests that were passing now fail, go back to DIAGNOSE with the new failure.

### 5. COMMIT

```
fix({scope}): {what was wrong and what changed}
```

Examples:
- `fix(parse-config): nil check missing when optional key absent`
- `fix(session-end): cd /tmp invalidates git root for subsequent brana calls`

If this fix has a task ID, brana marks it completed automatically at this step.

## The 3-strike rule

If 3 or more previous fix attempts have already failed for this bug, **stop before DIAGNOSE** and run `/brana:challenge` on your diagnosis. Shape beats brute force — the problem is usually a wrong hypothesis, not a wrong fix.

## Fix vs Build

| Use `/brana:fix` | Use `/brana:build "fix..."` |
|-----------------|---------------------------|
| You know it's a bug | You're not sure if it's a bug or a missing feature |
| You want the tight 5-step loop | You want full SPECIFY → DECOMPOSE → BUILD → CLOSE |
| Single, well-scoped defect | Bug that requires understanding a larger system |

## Key rules

- **Test before source.** The failing test is the requirement — if you can't write a failing test, you don't understand the bug yet.
- **Hypothesis must be specific.** "Something in X is wrong" is not a hypothesis. Name the component, the condition, and the bad output.
- **3 failed attempts → challenge first.** Don't patch forward — reassess the shape of the problem.
- **Minimal change.** The smallest fix that makes the test pass is the right fix. Don't clean up while fixing.
