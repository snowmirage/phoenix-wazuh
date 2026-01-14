# Backup/Restore Version Archive

**Date**: December 20, 2025

## Purpose
This directory contains the backup/restore implementation that was attempted but found to be non-functional due to Wazuh agent database architecture limitations.

## Files Archived
- `phoenix-wazuh-orchestrator.sh` - Orchestrator with backup/restore commands
- `phoenix-wazuh-worker.sh` - Worker with agent identity restoration (Step 4.5)
- `wazuh-backup-script.sh` - Backup script for historical data and agent identities
- `wazuh-restore-script.sh` - Restore script (non-functional)
- `capture-golden-keys.sh` - Golden keys capture script
- `migrate-backup-structure.sh` - Backup structure migration script

## Why This Was Archived
After extensive testing, the backup/restore functionality was found to have a fundamental catch-22:

1. **Restoring database files** → Manager processes fail to start
2. **Restoring only client.keys** → Database errors prevent manager initialization
3. **Not restoring anything** → Defeats purpose of restore

Additionally, even fresh installs began failing after these changes were implemented, suggesting the backup/restore code introduced regressions that affect clean deployments.

## Replacement
The main directory now contains clean versions that:
- Support **fresh-install only**
- Remove all backup/restore functionality
- Ensure stable, repeatable deployments
- Work correctly with agents reconnecting during deployment

## Reference
See CLAUDE.md "Known Issues Section 5" for detailed documentation of why backup/restore doesn't work with Wazuh's architecture.
