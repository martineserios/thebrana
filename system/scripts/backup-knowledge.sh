#!/usr/bin/env bash
# Trigger the brana-knowledge backup if the repo exists.
# No clone on this machine -> skip silently (exit 0).
# Clone present but backup.sh not executable -> warn and exit 1, so /brana:close shows it:
# a commit that dropped the exec bit (6c102b37, 2026-10-05) would otherwise switch every
# backup off without a word (t-3468). Tested by tests/scripts/test-backup-knowledge-wrapper.sh.

BACKUP_SCRIPT="$HOME/enter_thebrana/brana-knowledge/backup.sh"
[ -e "$BACKUP_SCRIPT" ] || exit 0
if [ ! -x "$BACKUP_SCRIPT" ]; then
    echo "WARNING: $BACKUP_SCRIPT is not executable — knowledge backup NOT run. If this is the owner machine: chmod +x it and check 'git log -1 -- backup.sh' in brana-knowledge for a mode change. On a company-managed Mac this is expected (it never exports)." >&2
    exit 1
fi
exec "$BACKUP_SCRIPT"
