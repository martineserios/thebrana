# Parallel Bash Resilience

Claude Code cancels all sibling Bash tool calls when one exits non-zero. Guard independent parallel commands:

- **Independent checks** (validate, test, lint): append `|| true` so one failure doesn't cancel siblings. Check exit codes in a follow-up message.
- **Dependent commands** (build then test): run sequentially in one call with `&&`.
- **Non-critical background work** (metrics, logging): always `|| true`.

```bash
# WRONG — cargo test failure cancels the validate call
Bash("cargo test")          # parallel
Bash("./validate.sh")       # parallel — cancelled if cargo test fails

# RIGHT — both complete, check results after
Bash("cargo test; echo EXIT:$?")       # parallel
Bash("./validate.sh; echo EXIT:$?")    # parallel — runs regardless
```

When writing skill instructions that say "run in parallel", add the guard pattern explicitly.
