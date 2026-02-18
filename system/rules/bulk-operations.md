# Bulk Operations

## Multi-file edits (5+ files)

When applying similar changes to 5+ files, use a Python script instead of individual Edit tool calls.

**Why:** Each Read+Edit pair consumes ~3K tokens. Ten files = 30K tokens. A Python script does the same work in ~2K tokens total.

**Pattern:**
```
1. Write a Python script that processes all files
2. Run it once: python3 /tmp/bulk-edit.py
3. Review: git diff
4. Clean up: rm /tmp/bulk-edit.py
```

## Sequential reads before edits

Never batch N Edit calls without reading each file first. The Edit tool requires a prior Read. When editing multiple files:
- Read file A → Edit file A → Read file B → Edit file B (sequential)
- NOT: Read A, Read B, Read C → Edit A, Edit B, Edit C (risky — earlier reads may be evicted from context)

## Large search-and-replace

When renaming a variable, function, or pattern across many files:
- Use `grep -rl` to find affected files first
- Write a `sed` or Python script to apply all changes at once
- Review the diff before committing
