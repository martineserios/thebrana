# Knowledge Backup Invocation (shared)

`backup-knowledge.sh` triggers `brana-knowledge/backup.sh`, which correctly
`exit 1`s and prints `WARNING: Backup integrity check failed: ...` when
`PRAGMA integrity_check` finds a corrupt page (t-2796). Every documented call
site in this repo used to invoke it as:

```bash
"$HOME/.claude/scripts/backup-knowledge.sh" 2>/dev/null || true
```

`2>/dev/null` discards the WARNING text and `|| true` forces exit 0
regardless of outcome — a real SQLite corruption event was silently
invisible unless someone happened to read raw transcript output
(confirmed live 2026-08-12: a proyecto_anita `/brana:close` hit
`btreeInitPage() returns error code 11` across 3 btrees and still reported
success). Any procedure invoking `backup-knowledge.sh` must instead call
`run_knowledge_backup()` below, which surfaces a failure without blocking
the caller — a knowledge-backup failure should warn, not halt a session
close.

Used by: `system/skills/close/phases/metadata-and-memory.md` (Step 10),
`system/skills/retrospective/SKILL.md`, `system/skills/client-retire/SKILL.md`,
`system/skills/memory/SKILL.md`.

<!-- BACKUP-KNOWLEDGE-INVOKE-BLOCK -->
```bash
# BACKUP_KNOWLEDGE_SCRIPT override exists for testability
# (tests/procedures/test-backup-knowledge-invoke.sh) — real callers should
# never set it and get the real deployed script.
run_knowledge_backup() {
  local script="${BACKUP_KNOWLEDGE_SCRIPT:-$HOME/.claude/scripts/backup-knowledge.sh}"
  local out
  if ! out=$("$script" 2>&1); then
    echo "⚠ backup-knowledge.sh failed — knowledge backup did NOT complete cleanly:" >&2
    echo "$out" >&2
    return 1
  fi
  return 0
}
```
<!-- /BACKUP-KNOWLEDGE-INVOKE-BLOCK -->

> The `BACKUP-KNOWLEDGE-INVOKE-BLOCK` markers above are load-bearing:
> `tests/procedures/test-backup-knowledge-invoke.sh` extracts exactly that
> span and sources it, so the test always exercises the shipped function.
> Do not remove or rename them, and keep the fences inside the markers.

**Callers**: source this block (or inline `run_knowledge_backup`), then call
it in place of the raw script invocation:

```bash
run_knowledge_backup
```

A non-zero return means the backup failed — warn the user inline (the
function already writes the diagnostic to stderr) rather than swallowing it.
This is advisory, not a hard gate: don't abort the enclosing close/retro/
retire flow over it, just make sure the failure is visible.

Covered by `tests/procedures/test-backup-knowledge-invoke.sh`, which extracts
this very code block so the test cannot drift from the shipped source.
