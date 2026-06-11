# Test spec: /brana:close — weight-adaptive NANO/LIGHT/INSTANT/FULL classification (t-1623, updated t-1973)

## Behaviour under test

Step 1 weight classification routes the close. Since Track 1 (ADR-052 §5):
auto-classified heavy sessions are **INSTANT** (snapshot + `brana close-queue append`
+ handoff; extraction deferred to the nightly cron). **FULL** (in-session
debrief-analyst) fires only on explicit `--full`. NANO and LIGHT are unchanged —
those assertions are the Track 1 regression net (t-1970 challenger C3).
Classification uses `git diff --name-only`, not `--stat`.

## Acceptance criteria (summary — assertions live in the .sh)

- Behavioral changes (.sh, code extensions, behavioral JSON, ≥2 commits) → INSTANT
- tasks.json-only / ≤5 non-code files at 1 commit → NANO (unchanged)
- 6+ non-code files or 0-commit spread → LIGHT (unchanged)
- `--full` is the ONLY route to FULL; `--light`/`--nano` override autos
- Invariant sweep: no auto path reaches FULL
