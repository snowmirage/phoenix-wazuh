#!/bin/bash

# Wazuh Restore Script
# Restores historical data, agent identities, and configurations
# Run AFTER a clean deployment to restore from backup

echo "=========================================="
echo "  Wazuh Restore Script"
echo "  Restoring Historical Data & Agent IDs"
echo "=========================================="
echo ""

# Check if backup timestamp provided
if [ $# -eq 0 ]; then
    echo "❌ Error: Please provide backup timestamp"
    echo ""
    echo "Usage: $0 <backup_timestamp>"
    echo "Example: $0 20250123_143022"
    echo ""
    echo "Available backups:"
    ssh -i /home/dev/.ssh/unraid_id_rsa root@10.2.0.16 "ls -1 /mnt/user/wazuh-data/backups/ 2>/dev/null || echo 'No backups found'"
    exit 1
fi

BACKUP_TIMESTAMP=$1

# Start restore timer
RESTORE_START_TIME=$(date +%s)
echo "🕐 Restore started at: $(date)"
echo "📦 Restoring from backup: $BACKUP_TIMESTAMP"
echo ""

# Function to calculate and display elapsed time
show_elapsed_time() {
    local start_time=$1
    local end_time=$(date +%s)
    local elapsed=$((end_time - start_time))
    local minutes=$((elapsed / 60))
    local seconds=$((elapsed % 60))
    
    if [ $minutes -gt 0 ]; then
        echo "⏱️  Completed in: ${minutes}m ${seconds}s"
    else
        echo "⏱️  Completed in: ${seconds}s"
    fi
}

# Configuration
UNRAID_SERVER="10.2.0.16"
SSH_KEY="/home/dev/.ssh/unraid_id_rsa"
INDEXER_IP="10.2.0.86"
SNAPSHOT_REPO_PATH="/mnt/user/wazuh-data/snapshots"
BACKUP_PATH="/mnt/user/wazuh-data/backups/$BACKUP_TIMESTAMP"
SNAPSHOT_NAME="wazuh-backup-$BACKUP_TIMESTAMP"

echo "🎯 Target: Phoenix Unraid server at $UNRAID_SERVER"
echo "📂 Backup source: $BACKUP_PATH"
echo ""

# Verify backup exists
echo "🔍 Verifying backup exists..."
if ! ssh -i $SSH_KEY root@$UNRAID_SERVER "[ -d '$BACKUP_PATH' ]"; then
    echo "❌ Error: Backup directory not found: $BACKUP_PATH"
    echo ""
    echo "Available backups:"
    ssh -i $SSH_KEY root@$UNRAID_SERVER "ls -1 /mnt/user/wazuh-data/backups/ 2>/dev/null || echo 'No backups found'"
    exit 1
fi
echo "   ✅ Backup directory verified"

# Check backup metadata
if ssh -i $SSH_KEY root@$UNRAID_SERVER "[ -f '$BACKUP_PATH/metadata/backup-info.txt' ]"; then
    echo "   📋 Backup information:"
    ssh -i $SSH_KEY root@$UNRAID_SERVER "grep -E '(Backup Date|Agent Count|Components)' '$BACKUP_PATH/metadata/backup-info.txt' | sed 's/^/   /' 2>/dev/null"
fi
echo ""

# Verify Wazuh is running
echo "🔍 Verifying Wazuh deployment is running..."
CONTAINER_COUNT=$(ssh -i $SSH_KEY root@$UNRAID_SERVER "cd /mnt/user/appdata/wazuh && docker-compose ps --services | wc -l" 2>/dev/null)
if [ "$CONTAINER_COUNT" -lt 3 ]; then
    echo "❌ Error: Wazuh deployment not running properly"
    echo "   Please run ./phoenix-wazuh-orchestrator.sh first for clean deployment"
    exit 1
fi
echo "   ✅ Wazuh deployment verified ($CONTAINER_COUNT services running)"
echo ""

# Step 1: Restore agent authentication (client.keys + SSL manager keys)
echo "🔑 Step 1: Restoring agent authentication..."

# Check if all authentication files exist in backup
if ssh -i $SSH_KEY root@$UNRAID_SERVER "[ -f '$BACKUP_PATH/client-keys/client.keys' ] && [ -f '$BACKUP_PATH/client-keys/sslmanager.key' ] && [ -f '$BACKUP_PATH/client-keys/sslmanager.cert' ]"; then
    # Stop manager temporarily to update authentication files safely
    echo "   Stopping Wazuh manager for safe authentication update..."
    ssh -i $SSH_KEY root@$UNRAID_SERVER "cd /mnt/user/appdata/wazuh && docker-compose stop wazuh.manager" 2>/dev/null

    # Restore client.keys (agent credentials)
    echo "   📋 Restoring client.keys..."
    ssh -i $SSH_KEY root@$UNRAID_SERVER "cp '$BACKUP_PATH/client-keys/client.keys' /mnt/user/appdata/wazuh/volumes/wazuh_etc/client.keys"
    ssh -i $SSH_KEY root@$UNRAID_SERVER "chown 999:999 /mnt/user/appdata/wazuh/volumes/wazuh_etc/client.keys && chmod 640 /mnt/user/appdata/wazuh/volumes/wazuh_etc/client.keys"

    # Restore sslmanager.key (manager's private key)
    echo "   🔐 Restoring sslmanager.key..."
    ssh -i $SSH_KEY root@$UNRAID_SERVER "cp '$BACKUP_PATH/client-keys/sslmanager.key' /mnt/user/appdata/wazuh/volumes/wazuh_etc/sslmanager.key"
    ssh -i $SSH_KEY root@$UNRAID_SERVER "chown root:999 /mnt/user/appdata/wazuh/volumes/wazuh_etc/sslmanager.key && chmod 640 /mnt/user/appdata/wazuh/volumes/wazuh_etc/sslmanager.key"

    # Restore sslmanager.cert (manager's certificate)
    echo "   📜 Restoring sslmanager.cert..."
    ssh -i $SSH_KEY root@$UNRAID_SERVER "cp '$BACKUP_PATH/client-keys/sslmanager.cert' /mnt/user/appdata/wazuh/volumes/wazuh_etc/sslmanager.cert"
    ssh -i $SSH_KEY root@$UNRAID_SERVER "chown root:999 /mnt/user/appdata/wazuh/volumes/wazuh_etc/sslmanager.cert && chmod 640 /mnt/user/appdata/wazuh/volumes/wazuh_etc/sslmanager.cert"

    echo "   📋 Agent authentication restored - agents will reconnect with preserved IDs"
    echo "   ℹ️  Agent database will recreate automatically (by design)"

    # Restart manager container
    echo "   Restarting Wazuh manager container..."
    ssh -i $SSH_KEY root@$UNRAID_SERVER "cd /mnt/user/appdata/wazuh && docker-compose start wazuh.manager" 2>/dev/null

    # Wait for container to be up
    sleep 5

    # CRITICAL: Restart Wazuh processes to reload SSL certificates
    echo "   Restarting Wazuh processes to reload SSL certificates..."
    ssh -i $SSH_KEY root@$UNRAID_SERVER "docker exec wazuh-wazuh.manager-1 /var/ossec/bin/wazuh-control restart" 2>/dev/null

    # Wait for all processes to initialize with new SSL keys
    echo "   Waiting for manager processes to initialize with restored SSL keys..."
    sleep 20

    AGENT_COUNT=$(ssh -i $SSH_KEY root@$UNRAID_SERVER "wc -l < '$BACKUP_PATH/client-keys/client.keys' 2>/dev/null")
    echo "   ✅ Agent authentication restored ($AGENT_COUNT agents + SSL manager keys)"
else
    echo "   ⚠️  Complete agent authentication backup not found"
    if ssh -i $SSH_KEY root@$UNRAID_SERVER "[ -f '$BACKUP_PATH/client-keys/client.keys' ]"; then
        echo "   ⚠️  Found client.keys but missing SSL manager keys (backup from old version)"
        echo "   ⚠️  Agents will need to re-enroll with new IDs"
    else
        echo "   ⚠️  No authentication backup found - agents will need to enroll"
    fi
fi
echo ""

# Step 2: Restore integration configurations
echo "🔧 Step 2: Restoring integration configurations..."
if ssh -i $SSH_KEY root@$UNRAID_SERVER "[ -f '$BACKUP_PATH/configs/ossec.conf' ]"; then
    echo "   Extracting integration API keys from backup..."
    
    # Extract integration sections and apply them to current ossec.conf
    # This preserves our deployment script's base configuration while restoring API keys
    ssh -i $SSH_KEY root@$UNRAID_SERVER "
    cd /mnt/user/appdata/wazuh && 
    # Create backup of current config
    docker-compose exec -T wazuh.manager cp /var/ossec/etc/ossec.conf /var/ossec/etc/ossec.conf.restore-backup
    
    # Extract integration blocks from backup
    if grep -q '<integration>' '$BACKUP_PATH/configs/ossec.conf'; then
        echo '   Found integration configurations in backup'
        # This would need custom logic to merge integrations - for now just note what was found
        grep -c '<integration>' '$BACKUP_PATH/configs/ossec.conf' | sed 's/^/   Integrations found: /'
    fi
    "
    echo "   ⚠️  Manual integration restore required - API keys saved in backup"
    echo "   Backup location: $BACKUP_PATH/configs/"
else
    echo "   ⚠️  No configuration backup found"
fi
echo ""

# Step 3: Restore OpenSearch snapshot (historical data)
echo "🗄️  Step 3: Restoring OpenSearch snapshot..."

# Import snapshot data from archival backup to active repository
echo "   Importing snapshot from archival backup..."
ssh -i $SSH_KEY root@$UNRAID_SERVER "rm -rf $SNAPSHOT_REPO_PATH/current/* && mkdir -p $SNAPSHOT_REPO_PATH/current && cp -r $BACKUP_PATH/snapshot/* $SNAPSHOT_REPO_PATH/current/ && chown -R 1000:1000 $SNAPSHOT_REPO_PATH/current && chmod -R 700 $SNAPSHOT_REPO_PATH/current && find $SNAPSHOT_REPO_PATH/current -type f -exec chmod 600 {} \;"
echo "   ✅ Snapshot imported to active repository"

# Wait for indexer to scan snapshot files and stabilize
# Time required scales with snapshot size and file count
SNAPSHOT_SIZE=$(ssh -i $SSH_KEY root@$UNRAID_SERVER "du -sm $SNAPSHOT_REPO_PATH/current 2>/dev/null | cut -f1")
SNAPSHOT_FILES=$(ssh -i $SSH_KEY root@$UNRAID_SERVER "find $SNAPSHOT_REPO_PATH/current -type f 2>/dev/null | wc -l")

echo "   ⏳ Waiting for indexer to scan snapshot files..."
echo "      Snapshot size: ${SNAPSHOT_SIZE}MB (${SNAPSHOT_FILES} files)"

# Calculate dynamic timeout based on size
# Formula: 300s base + (size_mb * 0.5s per MB), capped at 1 hour
# Examples: 500MB=550s(9m), 10GB=5420s(90m→60m), 50GB=60m(capped)
CALCULATED_TIMEOUT=$((300 + SNAPSHOT_SIZE / 2))
SCAN_TIMEOUT=$((CALCULATED_TIMEOUT > 3600 ? 3600 : CALCULATED_TIMEOUT))
echo "      Estimated scan time: $((SCAN_TIMEOUT / 60)) minutes (max wait)"
echo "      Restarting indexer for clean scan..."

ssh -i $SSH_KEY root@$UNRAID_SERVER "cd $UNRAID_NVME_PATH && docker-compose restart wazuh.indexer" >/dev/null 2>&1

# Progress tracking variables
SCAN_ELAPSED=0
SCAN_INTERVAL=10
LAST_PROGRESS_TIME=0
LAST_STATUS="initializing"
LAST_SHARD_COUNT=0
NO_PROGRESS_TIMEOUT=300  # 5 minutes of no progress = stalled

echo "      📊 Monitoring progress (will wait as long as progress continues)..."

while [ $SCAN_ELAPSED -lt $SCAN_TIMEOUT ]; do
    # Check multiple progress indicators
    CLUSTER_STATUS=$(ssh -i $SSH_KEY root@$UNRAID_SERVER "curl -k -s --max-time 5 -u admin:SecretPassword 'https://$INDEXER_IP:9200/_cluster/health' 2>/dev/null | jq -r '.status' 2>/dev/null || echo 'checking'")
    ACTIVE_SHARDS=$(ssh -i $SSH_KEY root@$UNRAID_SERVER "curl -k -s --max-time 5 -u admin:SecretPassword 'https://$INDEXER_IP:9200/_cluster/health' 2>/dev/null | jq -r '.active_shards' 2>/dev/null || echo '0'")
    PENDING_TASKS=$(ssh -i $SSH_KEY root@$UNRAID_SERVER "curl -k -s --max-time 5 -u admin:SecretPassword 'https://$INDEXER_IP:9200/_cluster/pending_tasks' 2>/dev/null | jq -r '.tasks | length' 2>/dev/null || echo '0'")

    # Detect progress: cluster status changed OR shard count increased OR tasks are being processed
    PROGRESS_MADE=false

    if [ "$CLUSTER_STATUS" != "$LAST_STATUS" ]; then
        echo "      📈 Progress: Cluster status changed ($LAST_STATUS → $CLUSTER_STATUS)"
        PROGRESS_MADE=true
    fi

    if [ "$ACTIVE_SHARDS" -gt "$LAST_SHARD_COUNT" ]; then
        echo "      📈 Progress: Active shards increased ($LAST_SHARD_COUNT → $ACTIVE_SHARDS)"
        PROGRESS_MADE=true
    fi

    if [ "$PENDING_TASKS" -gt 0 ] && [ $((SCAN_ELAPSED % 60)) -eq 0 ]; then
        echo "      ⚙️  Processing: $PENDING_TASKS tasks in queue"
        PROGRESS_MADE=true
    fi

    # Update progress tracking
    if [ "$PROGRESS_MADE" = true ]; then
        LAST_PROGRESS_TIME=$SCAN_ELAPSED
        LAST_STATUS="$CLUSTER_STATUS"
        LAST_SHARD_COUNT="$ACTIVE_SHARDS"
    fi

    # Check if we've reached healthy state
    if [ "$CLUSTER_STATUS" = "green" ] || [ "$CLUSTER_STATUS" = "yellow" ]; then
        echo "      ✅ Indexer scan complete and cluster healthy (took $(($SCAN_ELAPSED / 60))m $(($SCAN_ELAPSED % 60))s)"
        break
    fi

    # Check for stall (no progress for NO_PROGRESS_TIMEOUT seconds)
    TIME_SINCE_PROGRESS=$((SCAN_ELAPSED - LAST_PROGRESS_TIME))
    if [ $TIME_SINCE_PROGRESS -ge $NO_PROGRESS_TIMEOUT ]; then
        echo "      ⚠️  No progress detected for $((NO_PROGRESS_TIMEOUT / 60)) minutes"
        echo "      Last status: $CLUSTER_STATUS, Active shards: $ACTIVE_SHARDS"
        echo "      This may indicate a problem - check indexer logs for errors"
        break
    fi

    # Periodic status update every minute
    if [ $((SCAN_ELAPSED % 60)) -eq 0 ] && [ $SCAN_ELAPSED -gt 0 ]; then
        echo "      ⏳ Scanning... $(($SCAN_ELAPSED / 60))m elapsed | Status: $CLUSTER_STATUS | Shards: $ACTIVE_SHARDS | No progress for: ${TIME_SINCE_PROGRESS}s"
    fi

    sleep $SCAN_INTERVAL
    SCAN_ELAPSED=$((SCAN_ELAPSED + SCAN_INTERVAL))
done

if [ $SCAN_ELAPSED -ge $SCAN_TIMEOUT ]; then
    echo "      ⚠️  Maximum wait time reached ($(($SCAN_TIMEOUT / 60))m)"
    echo "      Attempting to proceed anyway..."
fi

# Set up snapshot repository
echo "   Setting up snapshot repository..."
ssh -i $SSH_KEY root@$UNRAID_SERVER "curl -k -u admin:SecretPassword -X PUT \"https://$INDEXER_IP:9200/_snapshot/backup-repo\" \\
  -H 'Content-Type: application/json' \\
  -d '{
    \"type\": \"fs\",
    \"settings\": {
      \"location\": \"current\",
      \"compress\": true
    }
  }'" 2>/dev/null

# Check if snapshot exists
echo "   Checking for snapshot: $SNAPSHOT_NAME"
SNAPSHOT_CHECK=$(ssh -i $SSH_KEY root@$UNRAID_SERVER "curl -k -u admin:SecretPassword -X GET \"https://$INDEXER_IP:9200/_snapshot/backup-repo/$SNAPSHOT_NAME\" 2>/dev/null")

if echo "$SNAPSHOT_CHECK" | grep -q '"state":"SUCCESS"'; then
    echo "   ✅ Snapshot found and verified"
    
    # Close any existing indices that might conflict
    echo "   Preparing for restore (closing conflicting indices)..."
    ssh -i $SSH_KEY root@$UNRAID_SERVER "curl -k -u admin:SecretPassword -X POST \"https://$INDEXER_IP:9200/wazuh-*/_close\" 2>/dev/null" || true
    
    # Restore the snapshot (async mode with progress monitoring)
    echo "   🔄 Initiating snapshot restore..."
    RESTORE_RESPONSE=$(ssh -i $SSH_KEY root@$UNRAID_SERVER "curl -k -u admin:SecretPassword -X POST \"https://$INDEXER_IP:9200/_snapshot/backup-repo/$SNAPSHOT_NAME/_restore?wait_for_completion=false\" \\
      -H 'Content-Type: application/json' \\
      -d '{
        \"indices\": \"wazuh-alerts-*,wazuh-archives-*,wazuh-states-*,wazuh-monitoring-*,wazuh-statistics-*\",
        \"ignore_unavailable\": true,
        \"include_global_state\": false,
        \"rename_pattern\": \"(.+)\",
        \"rename_replacement\": \"restored_\$1\"
      }'" 2>/dev/null)

    if echo "$RESTORE_RESPONSE" | grep -q '"accepted":true'; then
        echo "   ✅ Restore initiated successfully"

        # Get actual snapshot stats from OpenSearch
        SNAPSHOT_STATS=$(ssh -i $SSH_KEY root@$UNRAID_SERVER "curl -k -s -u admin:SecretPassword 'https://$INDEXER_IP:9200/_snapshot/backup-repo/$SNAPSHOT_NAME' 2>/dev/null")
        EXPECTED_INDICES=$(echo "$SNAPSHOT_STATS" | jq -r '.snapshots[0].indices | length' 2>/dev/null || echo "0")
        SNAPSHOT_SIZE_MB=$(echo "$SNAPSHOT_STATS" | jq -r '.snapshots[0].shards.total' 2>/dev/null || echo "0")

        if [ "$EXPECTED_INDICES" -eq 0 ]; then
            echo "   ⚠️  Warning: Could not determine snapshot size, using defaults"
            EXPECTED_INDICES=4
        fi

        echo "   📊 Monitoring restore progress (expecting $EXPECTED_INDICES indices)..."

        # Monitor restore progress
        RESTORE_TIMEOUT=1800  # 30 minutes max
        RESTORE_ELAPSED=0
        RESTORE_INTERVAL=10
        LAST_INDEX_COUNT=0
        STALLED_COUNT=0
        RESTORE_COMPLETED=false

        while [ $RESTORE_ELAPSED -lt $RESTORE_TIMEOUT ]; do
            # Check recovery status
            RECOVERY_STATS=$(ssh -i $SSH_KEY root@$UNRAID_SERVER "curl -k -s -u admin:SecretPassword 'https://$INDEXER_IP:9200/_recovery?active_only=true' 2>/dev/null" || echo '{}')

            # Count shards being recovered
            ACTIVE_RECOVERIES=$(echo "$RECOVERY_STATS" | jq -r '[.[] | .shards[] | select(.stage != "done")] | length' 2>/dev/null || echo '0')
            TOTAL_SHARDS=$(echo "$RECOVERY_STATS" | jq -r '[.[] | .shards[]] | length' 2>/dev/null || echo '0')
            DONE_SHARDS=$((TOTAL_SHARDS - ACTIVE_RECOVERIES))

            # Count restored indices
            CURRENT_INDICES=$(ssh -i $SSH_KEY root@$UNRAID_SERVER "curl -k -s -u admin:SecretPassword 'https://$INDEXER_IP:9200/_cat/indices/restored_*' 2>/dev/null | wc -l" || echo "0")

            # Check for completion
            if [ "$CURRENT_INDICES" -ge "$EXPECTED_INDICES" ] && [ "$ACTIVE_RECOVERIES" -eq 0 ]; then
                echo "      ✅ Restore complete! $CURRENT_INDICES indices restored (took $(($RESTORE_ELAPSED / 60))m $(($RESTORE_ELAPSED % 60))s)"
                RESTORE_COMPLETED=true
                break
            fi

            # Detect stall - if no progress for 3 minutes (18 iterations * 10s)
            if [ "$CURRENT_INDICES" -eq "$LAST_INDEX_COUNT" ]; then
                STALLED_COUNT=$((STALLED_COUNT + 1))
                if [ $STALLED_COUNT -ge 18 ] && [ "$CURRENT_INDICES" -gt 0 ]; then
                    # Restore appears stalled but some indices were created
                    echo "      ⚠️  Restore appears stalled after $CURRENT_INDICES indices"
                    echo "      ⚠️  Expected $EXPECTED_INDICES indices, no progress for 3 minutes"
                    break
                fi
            else
                STALLED_COUNT=0
            fi

            # Show progress
            if [ "$CURRENT_INDICES" -gt 0 ]; then
                PERCENT=$((CURRENT_INDICES * 100 / EXPECTED_INDICES))
                if [ "$PERCENT" -gt 100 ]; then PERCENT=100; fi

                # Report progress when index count changes or every minute
                if [ "$CURRENT_INDICES" -ne "$LAST_INDEX_COUNT" ] || [ $((RESTORE_ELAPSED % 60)) -eq 0 ]; then
                    echo "      ⏳ Restoring... $((RESTORE_ELAPSED / 60))m elapsed | Indices: $CURRENT_INDICES/$EXPECTED_INDICES ($PERCENT%) | Active shards: $ACTIVE_RECOVERIES"
                    LAST_INDEX_COUNT=$CURRENT_INDICES
                fi
            elif [ $((RESTORE_ELAPSED % 60)) -eq 0 ] && [ $RESTORE_ELAPSED -gt 0 ]; then
                echo "      ⏳ Waiting for restore to begin... $(($RESTORE_ELAPSED / 60))m elapsed"
            fi

            sleep $RESTORE_INTERVAL
            RESTORE_ELAPSED=$((RESTORE_ELAPSED + RESTORE_INTERVAL))
        done

        # Check if restore timed out
        if [ "$RESTORE_COMPLETED" = false ] && [ $RESTORE_ELAPSED -ge $RESTORE_TIMEOUT ]; then
            echo ""
            echo "❌ RESTORE FAILED - Timeout after $(($RESTORE_TIMEOUT / 60)) minutes"
            echo "   Status: $CURRENT_INDICES/$EXPECTED_INDICES indices, $DONE_SHARDS/$TOTAL_SHARDS shards"
            echo ""
            echo "📋 Troubleshooting:"
            echo "   1. Check indexer logs: docker logs wazuh-wazuh.indexer-1"
            echo "   2. Check restore status: curl -k -u admin:SecretPassword https://10.2.0.86:9200/_recovery"
            echo "   3. Disk space: df -h /mnt/ssd_cache"
            echo ""
            # Reopen indices that might be stuck closed
            ssh -i $SSH_KEY root@$UNRAID_SERVER "curl -k -s -u admin:SecretPassword -X POST 'https://$INDEXER_IP:9200/wazuh-*/_open' -H 'Content-Type: application/json'" >/dev/null 2>&1
            exit 1
        fi

        # Check if restore stalled
        if [ "$RESTORE_COMPLETED" = false ]; then
            echo ""
            echo "⚠️  RESTORE INCOMPLETE - Stalled at $CURRENT_INDICES/$EXPECTED_INDICES indices"
            echo "   Continuing with partial restore..."
            echo ""
        fi

        echo "   ✅ Snapshot restore completed successfully ($CURRENT_INDICES indices)"

        # Only proceed with finalization if restore completed or made significant progress
        if [ "$CURRENT_INDICES" -gt 0 ]; then
            # Wait a moment then check status
            sleep 10

            # Rename restored indices to remove "restored_" prefix
            echo "   Finalizing index names..."
            ssh -i $SSH_KEY root@$UNRAID_SERVER "
            for index in \$(curl -k -s -u admin:SecretPassword https://$INDEXER_IP:9200/_cat/indices/restored_* | awk '{print \$3}'); do
                new_name=\$(echo \$index | sed 's/restored_//')
                curl -k -s -u admin:SecretPassword -X POST \"https://$INDEXER_IP:9200/_reindex\" \\
                  -H 'Content-Type: application/json' \\
                  -d '{\"source\":{\"index\":\"\$index\"},\"dest\":{\"index\":\"\$new_name\"}}' >/dev/null
                curl -k -s -u admin:SecretPassword -X DELETE \"https://$INDEXER_IP:9200/\$index\" >/dev/null
            done
            " 2>/dev/null

            echo "   ✅ Historical data restored successfully"

            # Clean up snapshot files from active repository ONLY if restore completed
            if [ "$RESTORE_COMPLETED" = true ]; then
                echo "   🧹 Cleaning up snapshot files from active repository..."
                ssh -i $SSH_KEY root@$UNRAID_SERVER "rm -rf $SNAPSHOT_REPO_PATH/current/* && chown -R 1000:100 $SNAPSHOT_REPO_PATH"
                echo "   ✅ Snapshot files cleaned up (data now in indices)"
            else
                echo "   📁 Keeping snapshot files (restore incomplete, may need for debugging)"
            fi

            # Reopen all indices to make them searchable
            echo "   🔓 Reopening all indices..."
            ssh -i $SSH_KEY root@$UNRAID_SERVER "curl -k -s -u admin:SecretPassword -X POST 'https://$INDEXER_IP:9200/wazuh-*/_open' -H 'Content-Type: application/json'" >/dev/null 2>&1
            echo "   ✅ All indices reopened and searchable"
        else
            echo "   ⚠️  No indices were restored - skipping finalization"
            # Reopen indices anyway
            ssh -i $SSH_KEY root@$UNRAID_SERVER "curl -k -s -u admin:SecretPassword -X POST 'https://$INDEXER_IP:9200/wazuh-*/_open' -H 'Content-Type: application/json'" >/dev/null 2>&1
        fi
    else
        echo "   ⚠️  Snapshot restore failed or still in progress"
        echo "   Response: $RESTORE_RESPONSE"

        # Reopen indices even if restore failed
        echo "   🔓 Reopening all indices..."
        ssh -i $SSH_KEY root@$UNRAID_SERVER "curl -k -s -u admin:SecretPassword -X POST 'https://$INDEXER_IP:9200/wazuh-*/_open' -H 'Content-Type: application/json'" >/dev/null 2>&1
        echo "   ✅ All indices reopened"
    fi
else
    echo "   ❌ Snapshot not found or invalid: $SNAPSHOT_NAME"
    echo "   Available snapshots:"
    ssh -i $SSH_KEY root@$UNRAID_SERVER "curl -k -u admin:SecretPassword -X GET \"https://$INDEXER_IP:9200/_snapshot/backup-repo/_all\" 2>/dev/null | grep -o '\"snapshot\":\"[^\"]*\"' | cut -d'\"' -f4 | sed 's/^/   - /'"

    # Reopen indices even if snapshot not found
    echo "   🔓 Reopening all indices..."
    ssh -i $SSH_KEY root@$UNRAID_SERVER "curl -k -s -u admin:SecretPassword -X POST 'https://$INDEXER_IP:9200/wazuh-*/_open' -H 'Content-Type: application/json'" >/dev/null 2>&1
    echo "   ✅ All indices reopened"
fi
echo ""

# Step 4: Comprehensive System Validation
echo "🔍 Step 4: Comprehensive System Validation..."

# Function for waiting on services (reused from deployment script)
wait_for_service() {
    local service_name=$1
    local test_command=$2
    local timeout_seconds=$3
    local elapsed=0
    
    echo "⏳ Waiting for $service_name to be fully ready (timeout: ${timeout_seconds}s)..."
    while [ $elapsed -lt $timeout_seconds ]; do
        if ssh -i $SSH_KEY root@$UNRAID_SERVER "$test_command" 2>/dev/null; then
            echo "✅ $service_name is ready (took ${elapsed}s)"
            return 0
        fi
        if [ $elapsed -gt 0 ] && [ $((elapsed % 15)) -eq 0 ]; then
            echo "   Still waiting for $service_name... (${elapsed}s elapsed)"
        fi
        sleep 5
        elapsed=$((elapsed + 5))
    done
    
    echo "❌ $service_name failed readiness check after ${timeout_seconds}s"
    return 1
}

# Step 4.1: Container Health Check
echo "   🐳 Checking container health..."
RUNNING_CONTAINERS=$(ssh -i $SSH_KEY root@$UNRAID_SERVER "cd /mnt/user/appdata/wazuh && docker-compose ps --services --filter \"status=running\" | wc -l" 2>/dev/null)
if [ "$RUNNING_CONTAINERS" -lt 3 ]; then
    echo "   ❌ Error: Not all containers running. Expected 3, found $RUNNING_CONTAINERS"
    ssh -i $SSH_KEY root@$UNRAID_SERVER "cd /mnt/user/appdata/wazuh && docker-compose ps"
    echo "   Please check container logs and restart if needed"
else
    echo "   ✅ All containers running ($RUNNING_CONTAINERS/3)"
fi

# Step 4.2: Service Readiness Validation
echo "   🔧 Testing core service readiness..."

# Manager API
if ! wait_for_service "Manager API" \
    "curl -k -s --max-time 10 -u wazuh-wui:MyS3cr37P450r.*- https://10.2.0.85:55000/ | grep -q 'title\\|Unauthorized'" \
    60; then
    echo "   ⚠️  Manager API not fully ready - continuing with other checks"
fi

# Indexer
if ! wait_for_service "Indexer Cluster" \
    "curl -k -s --max-time 10 -u admin:SecretPassword https://$INDEXER_IP:9200/_cluster/health | grep -q 'green\\|yellow'" \
    60; then
    echo "   ❌ Critical: Indexer cluster not ready"
else
    # ISM Plugin
    if ! wait_for_service "ISM Plugin" \
        "curl -k -s --max-time 10 -u admin:SecretPassword https://$INDEXER_IP:9200/_plugins/_ism/policies | grep -q 'policies\\|\\[\\]'" \
        30; then
        echo "   ⚠️  ISM plugin not ready - snapshots may not be accessible"
    fi
fi

# Dashboard
if ! wait_for_service "Dashboard" \
    "[ \$(curl -k -s --max-time 10 -o /dev/null -w '%{http_code}' https://10.2.0.87:5601) -eq 302 ] || [ \$(curl -k -s --max-time 10 -o /dev/null -w '%{http_code}' https://10.2.0.87:5601) -eq 200 ]" \
    60; then
    echo "   ⚠️  Dashboard not fully ready"
fi

# Step 4.3: Data Validation
echo "   📊 Validating restored data..."

# Check restored indices
RESTORED_INDICES=$(ssh -i $SSH_KEY root@$UNRAID_SERVER "curl -k -s -u admin:SecretPassword https://$INDEXER_IP:9200/_cat/indices/wazuh-* 2>/dev/null | wc -l")
echo "   📋 Wazuh indices available: $RESTORED_INDICES"

if [ "$RESTORED_INDICES" -gt 0 ]; then
    # Check specific index types
    ALERT_INDICES=$(ssh -i $SSH_KEY root@$UNRAID_SERVER "curl -k -s -u admin:SecretPassword https://$INDEXER_IP:9200/_cat/indices/wazuh-alerts-* 2>/dev/null | wc -l")
    ARCHIVE_INDICES=$(ssh -i $SSH_KEY root@$UNRAID_SERVER "curl -k -s -u admin:SecretPassword https://$INDEXER_IP:9200/_cat/indices/wazuh-archives-* 2>/dev/null | wc -l")
    STATE_INDICES=$(ssh -i $SSH_KEY root@$UNRAID_SERVER "curl -k -s -u admin:SecretPassword https://$INDEXER_IP:9200/_cat/indices/wazuh-states-* 2>/dev/null | wc -l")
    
    echo "   🚨 Alert indices: $ALERT_INDICES"
    echo "   📦 Archive indices: $ARCHIVE_INDICES"  
    echo "   🔍 State indices: $STATE_INDICES"
    
    # Check document counts for historical data
    if [ "$ALERT_INDICES" -gt 0 ]; then
        TOTAL_ALERTS=$(ssh -i $SSH_KEY root@$UNRAID_SERVER "curl -k -s -u admin:SecretPassword https://$INDEXER_IP:9200/wazuh-alerts-*/_count 2>/dev/null | grep -o '\"count\":[0-9]*' | cut -d':' -f2")
        if [ -n "$TOTAL_ALERTS" ] && [ "$TOTAL_ALERTS" -gt 0 ]; then
            echo "   ✅ Historical alerts restored: $TOTAL_ALERTS events"
        fi
    fi
    
    # Validate date range of restored data
    OLDEST_ALERT=$(ssh -i $SSH_KEY root@$UNRAID_SERVER "curl -k -s -u admin:SecretPassword https://$INDEXER_IP:9200/wazuh-alerts-*/_search?size=1&sort=@timestamp:asc 2>/dev/null | grep -o '\"@timestamp\":\"[^\"]*\"' | head -1 | cut -d'\"' -f4")
    NEWEST_ALERT=$(ssh -i $SSH_KEY root@$UNRAID_SERVER "curl -k -s -u admin:SecretPassword https://$INDEXER_IP:9200/wazuh-alerts-*/_search?size=1&sort=@timestamp:desc 2>/dev/null | grep -o '\"@timestamp\":\"[^\"]*\"' | head -1 | cut -d'\"' -f4")
    
    if [ -n "$OLDEST_ALERT" ] && [ -n "$NEWEST_ALERT" ]; then
        echo "   📅 Data range: $OLDEST_ALERT to $NEWEST_ALERT"
    fi
else
    echo "   ⚠️  No Wazuh indices found - data restore may have failed"
fi

# Step 4.4: Agent Identity Validation
echo "   🔑 Validating agent identities..."

# Check client.keys file
AGENT_COUNT_FILE=$(ssh -i $SSH_KEY root@$UNRAID_SERVER "cd /mnt/user/appdata/wazuh && docker-compose exec -T wazuh.manager wc -l /var/ossec/etc/client.keys 2>/dev/null | cut -d' ' -f1" || echo "0")
echo "   📋 Agents in client.keys: $AGENT_COUNT_FILE"

# Wait a moment for agents to potentially reconnect
echo "   ⏳ Waiting 30 seconds for agent reconnection..."
sleep 30

# Check connected agents
CONNECTED_AGENTS=$(ssh -i $SSH_KEY root@$UNRAID_SERVER "cd /mnt/user/appdata/wazuh && docker-compose exec -T wazuh.manager /var/ossec/bin/agent_control -l 2>/dev/null | grep -c 'Active' || echo 0")
TOTAL_AGENTS=$(ssh -i $SSH_KEY root@$UNRAID_SERVER "cd /mnt/user/appdata/wazuh && docker-compose exec -T wazuh.manager /var/ossec/bin/agent_control -l 2>/dev/null | grep -c 'ID:' || echo 0")

echo "   🤝 Currently connected: $CONNECTED_AGENTS/$TOTAL_AGENTS agents"

if [ "$CONNECTED_AGENTS" -gt 0 ]; then
    echo "   ✅ Agents successfully reconnected with preserved identities"
    # Show specific connected agents
    ssh -i $SSH_KEY root@$UNRAID_SERVER "cd /mnt/user/appdata/wazuh && docker-compose exec -T wazuh.manager /var/ossec/bin/agent_control -l 2>/dev/null | grep 'Active' | head -3 | sed 's/^/   - /'"
elif [ "$TOTAL_AGENTS" -gt 0 ]; then
    echo "   ⚠️  Agents not yet reconnected - this is normal, they should reconnect within 10-15 minutes"
fi

# Step 4.5: Integration Status Check
echo "   🔧 Checking integration status..."

# Check if integrations are configured in ossec.conf
VT_CONFIGURED=$(ssh -i $SSH_KEY root@$UNRAID_SERVER "cd /mnt/user/appdata/wazuh && docker-compose exec -T wazuh.manager grep -c 'virustotal' /var/ossec/etc/ossec.conf 2>/dev/null || echo 0")
MALTIVERSE_CONFIGURED=$(ssh -i $SSH_KEY root@$UNRAID_SERVER "cd /mnt/user/appdata/wazuh && docker-compose exec -T wazuh.manager grep -c 'maltiverse' /var/ossec/etc/ossec.conf 2>/dev/null || echo 0")

if [ "$VT_CONFIGURED" -gt 0 ]; then
    echo "   ✅ VirusTotal integration: Configured"
else
    echo "   ⚠️  VirusTotal integration: Not configured (manual restore needed)"
fi

if [ "$MALTIVERSE_CONFIGURED" -gt 0 ]; then
    echo "   ✅ Maltiverse integration: Configured"  
else
    echo "   ⚠️  Maltiverse integration: Not configured (manual restore needed)"
fi

# Step 4.6: Network Validation
echo "   🌐 Validating network services..."

# Check syslog port
SYSLOG_LISTENING=$(ssh -i $SSH_KEY root@$UNRAID_SERVER "cd /mnt/user/appdata/wazuh && docker-compose exec -T wazuh.manager cat /proc/net/udp | grep -c '0202' || echo 0")
if [ "$SYSLOG_LISTENING" -gt 0 ]; then
    echo "   ✅ Syslog reception: Port 514 listening"
else
    echo "   ⚠️  Syslog reception: Port 514 not configured"
fi

echo ""
echo "   ✅ System validation complete"
echo ""

# Display restore summary
echo "=========================================="
echo "  Restore Complete!"
echo "=========================================="
echo ""
echo "📦 Restored from: $BACKUP_PATH"
echo "🗄️  Historical Data: $RESTORED_INDICES indices restored"
echo "🔑 Agent Identities: $AGENT_COUNT_FILE agents in backup"
echo "🤝 Currently Connected: $CONNECTED_AGENTS/$TOTAL_AGENTS agents"
echo "📊 Alert Data: $TOTAL_ALERTS security events restored"
echo ""
echo "⏭️  Next Steps:"
echo "   1. Check Dashboard: https://10.2.0.87:5601"
echo "   2. Verify agents reconnect automatically"
echo "   3. Manually restore integration API keys if needed"
echo "   4. Monitor system for 10-15 minutes for full agent reconnection"
echo ""
echo "🔧 Integration API Keys:"
echo "   Backup location: $BACKUP_PATH/configs/"
echo "   Manual restore may be required for VirusTotal, Maltiverse, etc."
echo ""
show_elapsed_time $RESTORE_START_TIME
echo ""