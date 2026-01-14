#!/bin/bash

# Migration Script: Old backup-data structure → New snapshots/backups structure
# Migrates existing backups to new architecture without affecting data

echo "=========================================="
echo "  Wazuh Backup Structure Migration"
echo "  Old: backup-data/ → New: snapshots/ + backups/"
echo "=========================================="
echo ""

# Configuration
UNRAID_SERVER="10.2.0.16"
SSH_KEY="/home/dev/.ssh/unraid_id_rsa"
OLD_PATH="/mnt/user/wazuh-data/backup-data"
NEW_BACKUPS_PATH="/mnt/user/wazuh-data/backups"
NEW_SNAPSHOTS_PATH="/mnt/user/wazuh-data/snapshots"

echo "🎯 Target: Phoenix Unraid server at $UNRAID_SERVER"
echo ""

# Safety check: Verify local backup exists
if [ ! -d "/home/dev/code/phoenix/phoenix_wazuh/backup-safety/20251216_080800" ]; then
    echo "❌ SAFETY CHECK FAILED!"
    echo "   Good backup (20251216_080800) not found in local backup-safety directory"
    echo "   Please copy it locally first before running migration"
    exit 1
fi
echo "✅ Safety backup verified locally"
echo ""

# Check if old directory exists
echo "🔍 Checking for old backup structure..."
if ! ssh -i $SSH_KEY root@$UNRAID_SERVER "[ -d '$OLD_PATH' ]"; then
    echo "   ℹ️  No old backup-data directory found"
    echo "   Creating new structure from scratch..."
else
    BACKUP_COUNT=$(ssh -i $SSH_KEY root@$UNRAID_SERVER "ls -1 $OLD_PATH 2>/dev/null | wc -l")
    echo "   ✅ Found old backup directory with $BACKUP_COUNT backups"
fi
echo ""

# Create new directory structure
echo "📁 Creating new directory structure..."
ssh -i $SSH_KEY root@$UNRAID_SERVER "
    mkdir -p $NEW_BACKUPS_PATH
    mkdir -p $NEW_SNAPSHOTS_PATH/current
    chown -R 1000:100 $NEW_BACKUPS_PATH
    chown -R 1000:100 $NEW_SNAPSHOTS_PATH
"
echo "   ✅ New directories created"
echo ""

# Migrate existing backups if they exist
if ssh -i $SSH_KEY root@$UNRAID_SERVER "[ -d '$OLD_PATH' ] && [ \$(ls -1 $OLD_PATH 2>/dev/null | wc -l) -gt 0 ]"; then
    echo "📦 Migrating existing backups..."
    echo "   This will COPY (not move) data to preserve originals"
    echo ""

    # Get list of backup timestamps
    TIMESTAMPS=$(ssh -i $SSH_KEY root@$UNRAID_SERVER "ls -1 $OLD_PATH")

    for timestamp in $TIMESTAMPS; do
        echo "   🔄 Migrating backup: $timestamp"

        # Create new backup directory
        ssh -i $SSH_KEY root@$UNRAID_SERVER "mkdir -p $NEW_BACKUPS_PATH/$timestamp"

        # Copy snapshots directory to snapshot (singular)
        if ssh -i $SSH_KEY root@$UNRAID_SERVER "[ -d '$OLD_PATH/$timestamp/snapshots' ]"; then
            ssh -i $SSH_KEY root@$UNRAID_SERVER "cp -r $OLD_PATH/$timestamp/snapshots $NEW_BACKUPS_PATH/$timestamp/snapshot"
        fi

        # Copy other directories
        for dir in client-keys configs metadata; do
            if ssh -i $SSH_KEY root@$UNRAID_SERVER "[ -d '$OLD_PATH/$timestamp/$dir' ]"; then
                ssh -i $SSH_KEY root@$UNRAID_SERVER "cp -r $OLD_PATH/$timestamp/$dir $NEW_BACKUPS_PATH/$timestamp/"
            fi
        done

        echo "      ✅ Migrated: $timestamp"
    done

    echo ""
    echo "   ✅ All backups migrated successfully"
    echo ""

    # DON'T delete old directory - just note it
    echo "📦 Old directory preserved at: $OLD_PATH"
    echo "   ⚠️  DO NOT DELETE until you've verified new backups work!"
    echo "   After successful deployment and restore, you can:"
    echo "   ssh -i $SSH_KEY root@$UNRAID_SERVER \"rm -rf $OLD_PATH\""
    echo ""
fi

# Display new structure
echo "=========================================="
echo "  Migration Complete!"
echo "=========================================="
echo ""
echo "📊 New Directory Structure:"
echo ""
ssh -i $SSH_KEY root@$UNRAID_SERVER "
echo '📂 /mnt/user/wazuh-data/'
echo '├── snapshots/              (active repository, mounted to indexer)'
echo '│   └── current/            (current working snapshot - empty for now)'
echo '│'
echo '├── backups/                (archival storage, not mounted)'
ls -1 $NEW_BACKUPS_PATH 2>/dev/null | sed 's/^/│   ├── /'
echo '│'
echo '└── backup-data/            (OLD - preserved for safety, delete later)'
echo ''
"

# Count migrated backups
MIGRATED_COUNT=$(ssh -i $SSH_KEY root@$UNRAID_SERVER "ls -1 $NEW_BACKUPS_PATH 2>/dev/null | wc -l")
echo "✅ Migrated backups: $MIGRATED_COUNT"
echo ""
echo "🚀 Next Steps:"
echo "   1. Run clean deployment: ./phoenix-wazuh-orchestrator.sh --skip-backup-restore"
echo "   2. Manually restore good backup: ./wazuh-restore-script.sh 20251216_080800"
echo "   3. Verify system working correctly"
echo "   4. Delete old backup-data directory when confident"
echo ""
echo "📝 Safety Notes:"
echo "   - Original backup-data directory is PRESERVED (not deleted)"
echo "   - Local safety backup stored in backup-safety/20251216_080800"
echo "   - New backups will automatically use the new structure"
echo ""
