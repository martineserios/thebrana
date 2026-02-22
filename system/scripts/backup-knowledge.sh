#!/usr/bin/env bash
# Trigger brana-knowledge backup if repo exists. Skip silently otherwise.

BACKUP_SCRIPT="$HOME/enter_thebrana/brana-knowledge/backup.sh"
[ -x "$BACKUP_SCRIPT" ] && "$BACKUP_SCRIPT"
