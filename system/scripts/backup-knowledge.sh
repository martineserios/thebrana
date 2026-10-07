#!/usr/bin/env bash
# Trigger the brana-knowledge backup if the clone exists.
# No clone on this machine -> skip silently (exit 0).
# Clone present but backup.sh missing or not executable -> warn and exit 1, so /brana:close
# shows it: a commit that dropped the exec bit (6c102b37, 2026-10-05) would otherwise switch
# every backup off without a word (t-3468). Silence keys on the CLONE, not on the file.
# Tested by tests/scripts/test-backup-knowledge-wrapper.sh.

REPO="$HOME/enter_thebrana/brana-knowledge"
BACKUP_SCRIPT="$REPO/backup.sh"
[ -d "$REPO" ] || exit 0
if [ ! -e "$BACKUP_SCRIPT" ]; then
    echo "WARNING: $BACKUP_SCRIPT is missing — knowledge backup NOT run. Check 'git -C $REPO log -1 -- backup.sh'." >&2
    exit 1
fi
if [ ! -x "$BACKUP_SCRIPT" ]; then
    echo "WARNING: $BACKUP_SCRIPT is not executable — knowledge backup NOT run. On a company-managed Mac this is intentional (it never exports): DO NOT chmod it and do not run it. On the owner's Linux machine: chmod +x it and check 'git -C $REPO log -1 -- backup.sh' for a mode change." >&2
    exit 1
fi
exec "$BACKUP_SCRIPT"
