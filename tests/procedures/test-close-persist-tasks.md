# Test spec: /brana:close — persist next[] task IDs (t-1319)

## Behaviour under test

Before writing session state, `/brana:close` Step 9 must ensure every non-null
`task_id` in the `next[]` array exists in the backlog. Any ID that doesn't exist
must be created via `brana backlog add` before `brana session write` is called.

## Acceptance criteria

1. If `next[].task_id` is `"t-9999"` and `backlog_get("t-9999")` returns not-found,
   the procedure calls `backlog_add` with the matching `text` as subject before writing.

2. If `next[].task_id` is `null`, no check or creation is performed for that entry.

3. If `next[].task_id` is non-null and the task already exists, no duplicate is created.

4. `brana session write` is always called after the persistence step, not skipped.

## Verification

Run `/brana:close` in a session that emits next[] items with new task IDs and
confirm those IDs appear in `brana backlog get {id}` afterwards.
