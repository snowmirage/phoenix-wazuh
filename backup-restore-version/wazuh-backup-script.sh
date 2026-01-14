#!/bin/bash

# Wazuh Backup Script
# Creates backups of historical data, agent identities, and configurations
# Stores backups in protected backup-data directory

echo "=========================================="
echo "  Wazuh Backup Script"
echo "  Preserving Historical Data & Agent IDs"
echo "=========================================="
echo ""

# Start backup timer
BACKUP_START_TIME=$(date +%s)
echo "🕐 Backup started at: $(date)"
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
BACKUP_BASE_PATH="/mnt/user/wazuh-data/backups"
BACKUP_TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_PATH="$BACKUP_BASE_PATH/$BACKUP_TIMESTAMP"

echo "🎯 Target: Phoenix Unraid server at $UNRAID_SERVER"
echo "💾 Backup destination: $BACKUP_PATH"
echo ""

# Create backup directory structure
echo "📁 Creating backup directory structure..."
ssh -i $SSH_KEY root@$UNRAID_SERVER "mkdir -p $BACKUP_PATH/{snapshot,client-keys,configs,metadata} && chown -R 1000:100 $BACKUP_PATH"
echo "   ✅ Backup directories created"
echo ""

# Ensure snapshot repository directory exists
echo "📁 Ensuring snapshot repository exists..."
ssh -i $SSH_KEY root@$UNRAID_SERVER "mkdir -p $SNAPSHOT_REPO_PATH/current && chown -R 1000:100 $SNAPSHOT_REPO_PATH"
echo "   ✅ Snapshot repository ready"
echo ""

# Step 1: Create OpenSearch snapshot for historical data
echo "🗄️  Step 1: Creating OpenSearch snapshot for historical data..."
SNAPSHOT_NAME="wazuh-backup-$BACKUP_TIMESTAMP"

# Create snapshot repository if it doesn't exist
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

echo "   Creating snapshot: $SNAPSHOT_NAME"
SNAPSHOT_RESPONSE=$(ssh -i $SSH_KEY root@$UNRAID_SERVER "curl -k -u admin:SecretPassword -X PUT \"https://$INDEXER_IP:9200/_snapshot/backup-repo/$SNAPSHOT_NAME?wait_for_completion=true\" \\
  -H 'Content-Type: application/json' \\
  -d '{
    \"indices\": \"wazuh-alerts-*,wazuh-archives-*,wazuh-states-*,wazuh-monitoring-*,wazuh-statistics-*\",
    \"ignore_unavailable\": true,
    \"include_global_state\": false,
    \"metadata\": {
      \"taken_by\": \"wazuh-backup-script\",
      \"taken_at\": \"$(date)\",
      \"description\": \"Automated backup of Wazuh historical data\"
    }
  }'" 2>/dev/null)

if echo "$SNAPSHOT_RESPONSE" | grep -q '"state":"SUCCESS"'; then
    echo "   ✅ OpenSearch snapshot created successfully"
else
    echo "   ❌ ERROR: OpenSearch snapshot failed"
    echo "   Response: $SNAPSHOT_RESPONSE"
    echo ""
    echo "❌ BACKUP FAILED - OpenSearch snapshot could not be created"
    echo "   Possible causes:"
    echo "   - Wazuh containers not running"
    echo "   - Indexer not accessible at $INDEXER_IP:9200"
    echo "   - Authentication failed"
    echo ""
    exit 1
fi

# Export snapshot data to archival backup
echo "   📦 Exporting snapshot to archival backup..."
ssh -i $SSH_KEY root@$UNRAID_SERVER "cp -r $SNAPSHOT_REPO_PATH/current/* $BACKUP_PATH/snapshot/ 2>/dev/null && chown -R 1000:100 $BACKUP_PATH/snapshot"
echo "   ✅ Snapshot exported to backup"
echo ""

# Step 2: Backup agent authentication (client.keys + SSL manager keys)
echo "🔑 Step 2: Backing up agent authentication..."

# Backup client.keys (agent credentials)
echo "   📋 Backing up client.keys..."
ssh -i $SSH_KEY root@$UNRAID_SERVER "cd /mnt/user/appdata/wazuh && docker-compose exec -T wazuh.manager cat /var/ossec/etc/client.keys > $BACKUP_PATH/client-keys/client.keys 2>/dev/null"

# Backup sslmanager.key (manager's private key for agent communication)
echo "   🔐 Backing up sslmanager.key..."
ssh -i $SSH_KEY root@$UNRAID_SERVER "cd /mnt/user/appdata/wazuh && docker-compose exec -T wazuh.manager cat /var/ossec/etc/sslmanager.key > $BACKUP_PATH/client-keys/sslmanager.key 2>/dev/null"

# Backup sslmanager.cert (manager's certificate for agent communication)
echo "   📜 Backing up sslmanager.cert..."
ssh -i $SSH_KEY root@$UNRAID_SERVER "cd /mnt/user/appdata/wazuh && docker-compose exec -T wazuh.manager cat /var/ossec/etc/sslmanager.cert > $BACKUP_PATH/client-keys/sslmanager.cert 2>/dev/null"

# Check if all authentication files were backed up successfully
if ! ssh -i $SSH_KEY root@$UNRAID_SERVER "[ -f $BACKUP_PATH/client-keys/client.keys ] && [ -f $BACKUP_PATH/client-keys/sslmanager.key ] && [ -f $BACKUP_PATH/client-keys/sslmanager.cert ]"; then
    echo "   ❌ ERROR: Agent authentication backup failed"
    echo ""
    echo "❌ BACKUP FAILED - Could not extract agent authentication files"
    echo "   Possible causes:"
    echo "   - Wazuh manager container not running"
    echo "   - Docker compose not accessible"
    echo ""
    exit 1
fi

CLIENT_KEYS_SIZE=$(ssh -i $SSH_KEY root@$UNRAID_SERVER "wc -l < $BACKUP_PATH/client-keys/client.keys 2>/dev/null || echo 0")
echo "   ✅ Agent authentication backed up ($CLIENT_KEYS_SIZE agents + SSL manager keys)"
echo ""

# Step 3: Backup integration configurations
echo "🔧 Step 3: Backing up integration configurations..."
ssh -i $SSH_KEY root@$UNRAID_SERVER "cd /mnt/user/appdata/wazuh && docker-compose exec -T wazuh.manager cat /var/ossec/etc/ossec.conf > $BACKUP_PATH/configs/ossec.conf 2>/dev/null"

# Check if ossec.conf backup was successful
if ! ssh -i $SSH_KEY root@$UNRAID_SERVER "[ -f $BACKUP_PATH/configs/ossec.conf ]"; then
    echo "   ❌ ERROR: ossec.conf backup failed"
    echo ""
    echo "❌ BACKUP FAILED - Could not extract configuration"
    echo "   Possible causes:"
    echo "   - Wazuh manager container not running"
    echo "   - Configuration file not found in container"
    echo ""
    exit 1
fi

# Extract API keys from ossec.conf
echo "   Extracting integration API keys..."
ssh -i $SSH_KEY root@$UNRAID_SERVER "grep -A 10 -B 2 'integration>' $BACKUP_PATH/configs/ossec.conf > $BACKUP_PATH/configs/integrations-extract.conf 2>/dev/null || echo 'No integrations found'"
echo "   ✅ Integration configurations backed up"
echo ""

# Step 4: Create backup metadata
echo "📋 Step 4: Creating backup metadata..."
ssh -i $SSH_KEY root@$UNRAID_SERVER "cat > $BACKUP_PATH/metadata/backup-info.txt << EOF
Wazuh Backup Information
========================
Backup Date: $(date)
Backup Timestamp: $BACKUP_TIMESTAMP
Snapshot Name: $SNAPSHOT_NAME
Agent Count: $CLIENT_KEYS_SIZE
Indexer IP: $INDEXER_IP

Components Backed Up:
- OpenSearch Snapshot: wazuh-alerts-*, wazuh-archives-*, wazuh-states-*, wazuh-monitoring-*, wazuh-statistics-*
- Agent Identities: client.keys ($CLIENT_KEYS_SIZE agents)
- Agent Database: Agent names, groups, registration timestamps, metadata
- Integration Configs: ossec.conf with API keys
- Backup Metadata: This file

Restore Instructions:
1. Run clean deployment: ./phoenix-wazuh-orchestrator.sh
2. Run restore script: ./wazuh-restore-script.sh $BACKUP_TIMESTAMP
3. Verify agents reconnect with original identities

Created by: wazuh-backup-script.sh
EOF"

echo "   ✅ Backup metadata created"
echo ""

# Step 5: Verify backup integrity
echo "🔍 Step 5: Verifying backup integrity..."
SNAPSHOT_INFO=$(ssh -i $SSH_KEY root@$UNRAID_SERVER "curl -k -u admin:SecretPassword -X GET \"https://$INDEXER_IP:9200/_snapshot/backup-repo/$SNAPSHOT_NAME\" 2>/dev/null")

if echo "$SNAPSHOT_INFO" | grep -q '"state":"SUCCESS"'; then
    SNAPSHOT_SIZE=$(echo "$SNAPSHOT_INFO" | grep -o '"size_in_bytes":[0-9]*' | cut -d':' -f2)
    SNAPSHOT_SIZE_MB=$((SNAPSHOT_SIZE / 1024 / 1024))
    echo "   ✅ Snapshot verified: ${SNAPSHOT_SIZE_MB}MB"
else
    echo "   ⚠️  Snapshot verification failed or still in progress"
fi

# Check file backups
CONFIG_SIZE=$(ssh -i $SSH_KEY root@$UNRAID_SERVER "du -sh $BACKUP_PATH/configs/ 2>/dev/null | cut -f1")
echo "   ✅ Configuration files: $CONFIG_SIZE"
echo ""

# Display backup summary
echo "=========================================="
echo "  Backup Complete!"
echo "=========================================="
echo ""
echo "📦 Backup Location: $BACKUP_PATH"
echo "📸 Snapshot Name: $SNAPSHOT_NAME"
echo "👥 Agents Backed Up: $CLIENT_KEYS_SIZE"
echo "🔧 Configurations: Saved"
echo ""
echo "🚀 To restore this backup:"
echo "   1. Run: ./phoenix-wazuh-orchestrator.sh (clean install)"
echo "   2. Run: ./wazuh-restore-script.sh $BACKUP_TIMESTAMP"
echo ""
show_elapsed_time $BACKUP_START_TIME
echo ""