#!/bin/bash

# Capture Golden Agent Keys Script
# Run this after agents have successfully connected to save their identities
# These keys will be automatically restored on all future deployments

echo "=========================================="
echo "  Capture Golden Agent Keys"
echo "  Preserving Agent Identities"
echo "=========================================="
echo ""

# Configuration
UNRAID_SERVER="10.2.0.16"
SSH_KEY="/home/dev/.ssh/unraid_id_rsa"
GOLDEN_KEYS_PATH="/mnt/user/wazuh-data/golden-agent-keys"

echo "🎯 Target: Phoenix Unraid server at $UNRAID_SERVER"
echo "💾 Golden keys destination: $GOLDEN_KEYS_PATH"
echo ""

# Check if Wazuh manager is running
echo "🔍 Checking if Wazuh manager is running..."
if ! ssh -i $SSH_KEY root@$UNRAID_SERVER "docker ps | grep -q wazuh.manager"; then
    echo "❌ ERROR: Wazuh manager container is not running"
    echo "   Please deploy Wazuh first and ensure agents are connected"
    exit 1
fi
echo "   ✅ Manager is running"
echo ""

# Check how many agents are connected
echo "📊 Checking connected agents..."
AGENT_STATUS=$(ssh -i $SSH_KEY root@$UNRAID_SERVER "docker exec wazuh-wazuh.manager-1 /var/ossec/bin/agent_control -l 2>/dev/null | grep -E 'ID: [0-9]{3}.*Active'" | wc -l)

if [ "$AGENT_STATUS" -eq 0 ]; then
    echo "⚠️  WARNING: No active agents detected"
    echo ""
    echo "Current agent status:"
    ssh -i $SSH_KEY root@$UNRAID_SERVER "docker exec wazuh-wazuh.manager-1 /var/ossec/bin/agent_control -l 2>/dev/null"
    echo ""
    read -p "Do you want to capture keys anyway? (y/N): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Cancelled - please wait for agents to connect first"
        exit 1
    fi
else
    echo "   ✅ Found $AGENT_STATUS active agent(s)"
    echo ""
    echo "Active agents:"
    ssh -i $SSH_KEY root@$UNRAID_SERVER "docker exec wazuh-wazuh.manager-1 /var/ossec/bin/agent_control -l 2>/dev/null | grep -E 'ID: [0-9]{3}'"
    echo ""
fi

# Confirm with user
read -p "Capture these agent keys as golden keys? (y/N): " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cancelled"
    exit 0
fi

# Create golden keys directory if it doesn't exist
echo "📁 Ensuring golden keys directory exists..."
ssh -i $SSH_KEY root@$UNRAID_SERVER "mkdir -p $GOLDEN_KEYS_PATH && chown -R 1000:100 $GOLDEN_KEYS_PATH"
echo ""

# Capture client.keys
echo "🔑 Capturing agent credentials (client.keys)..."
ssh -i $SSH_KEY root@$UNRAID_SERVER "docker exec wazuh-wazuh.manager-1 cat /var/ossec/etc/client.keys > $GOLDEN_KEYS_PATH/client.keys 2>/dev/null"

# Capture sslmanager.key
echo "🔐 Capturing SSL manager private key (sslmanager.key)..."
ssh -i $SSH_KEY root@$UNRAID_SERVER "docker exec wazuh-wazuh.manager-1 cat /var/ossec/etc/sslmanager.key > $GOLDEN_KEYS_PATH/sslmanager.key 2>/dev/null"

# Capture sslmanager.cert
echo "📜 Capturing SSL manager certificate (sslmanager.cert)..."
ssh -i $SSH_KEY root@$UNRAID_SERVER "docker exec wazuh-wazuh.manager-1 cat /var/ossec/etc/sslmanager.cert > $GOLDEN_KEYS_PATH/sslmanager.cert 2>/dev/null"

# Capture agent database (metadata, groups, registration info)
echo "🗄️  Capturing agent database (metadata, groups, names)..."
ssh -i $SSH_KEY root@$UNRAID_SERVER "docker exec wazuh-wazuh.manager-1 tar -czf - /var/ossec/queue/db/*.db* 2>/dev/null | cat > $GOLDEN_KEYS_PATH/wazuh-db.tar.gz"

# Set proper permissions
ssh -i $SSH_KEY root@$UNRAID_SERVER "chmod 600 $GOLDEN_KEYS_PATH/* && chown 1000:100 $GOLDEN_KEYS_PATH/*"

# Verify capture
echo ""
echo "🔍 Verifying golden keys capture..."
if ssh -i $SSH_KEY root@$UNRAID_SERVER "[ -f $GOLDEN_KEYS_PATH/client.keys ] && [ -f $GOLDEN_KEYS_PATH/sslmanager.key ] && [ -f $GOLDEN_KEYS_PATH/sslmanager.cert ] && [ -f $GOLDEN_KEYS_PATH/wazuh-db.tar.gz ]"; then
    CAPTURED_AGENTS=$(ssh -i $SSH_KEY root@$UNRAID_SERVER "wc -l < $GOLDEN_KEYS_PATH/client.keys")
    echo "   ✅ All files captured successfully"
    echo ""
    echo "=========================================="
    echo "  Golden Keys Captured!"
    echo "=========================================="
    echo ""
    echo "📦 Captured Files:"
    ssh -i $SSH_KEY root@$UNRAID_SERVER "ls -lh $GOLDEN_KEYS_PATH/"
    echo ""
    echo "👥 Agent Count: $CAPTURED_AGENTS"
    echo "📍 Location: $GOLDEN_KEYS_PATH"
    echo ""
    echo "🎉 SUCCESS: These agent identities will now persist across ALL deployments"
    echo "   - Agents will automatically reconnect after clean deployments"
    echo "   - No manual re-enrollment needed"
    echo "   - Works with version upgrades"
    echo ""
    echo "🚀 To test: Run ./phoenix-wazuh-orchestrator.sh --skip-backup-restore"
    echo "   Agents should automatically reconnect with their existing identities"
    echo ""
else
    echo "   ❌ ERROR: Failed to capture all files"
    echo ""
    echo "Missing files:"
    ssh -i $SSH_KEY root@$UNRAID_SERVER "ls -la $GOLDEN_KEYS_PATH/"
    exit 1
fi
