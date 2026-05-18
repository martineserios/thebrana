# Test spec: /brana:close — Step 5 pattern routing + Step 11 memory recall (t-1263)

## Behaviour under test

After t-1263 ships, `/brana:close` Step 5 and Step 11 route through the
classify-then-route taxonomy from t-1241. Patterns go to `patterns.md`;
knowledge findings go to `knowledge-staging.md`. Rules require human
review via AskUserQuestion — never auto-written.

## Step 5: Pattern storage

### Acceptance criteria

1. When a session produces a learning classified as **pattern**, Step 5b
   writes it to `~/.claude/memory/patterns.md` as a new `## {slug}` entry
   with `Confidence: quarantine` and `Added: {date}`.

2. When a session produces a learning classified as **rule**, Step 5 fires
   `AskUserQuestion` with a draft preview. It does NOT auto-write to
   `system/rules/` or `patterns.md`.

3. If a slug derived from the learning already exists in `patterns.md`
   (i.e. `grep -q "^## {slug}" patterns.md`), Step 5b updates the existing
   entry via `Edit` — it does NOT create a duplicate `## {slug}` section.

4. `brana session write` is called after all Step 5/5b writes complete,
   not before.

## Step 11: Memory review routing

### Acceptance criteria

5. When the user selects "Recall patterns" in Step 11, `/brana:memory`
   queries `patterns.md` (local) and ruflo `pattern` namespace, then
   returns merged, deduplicated results.

6. When the user selects "Recall knowledge", `/brana:memory` queries
   `knowledge-staging.md` (local) and ruflo `knowledge` namespace.

7. Results from local files and ruflo are deduplicated by slug before
   presentation — no entry appears twice.

## Verification

Run `/brana:close` in a session that produced at least one pattern
learning and one rule candidate. Confirm:
- `~/.claude/memory/patterns.md` has a new `## {slug}` section
- An `AskUserQuestion` was fired for the rule candidate (not auto-written)
- Re-running close with the same pattern does not create a duplicate entry
- Step 11 memory recall returns the newly-written pattern
