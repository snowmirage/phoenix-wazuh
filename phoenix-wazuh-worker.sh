#!/bin/bash

# Phoenix Wazuh Worker Script - Fresh Install Only
# Simplified version without backup/restore functionality
# This script runs ON the Phoenix Unraid server to deploy Docker containers

# Parse parameters from orchestrator
WAZUH_VERSION=$1

echo "==========================================="
echo "  Phoenix Wazuh Docker Deployment Worker"
echo "  Executing on Phoenix Unraid Server"
echo "  Mode: FRESH INSTALL"
echo "  Wazuh Version: $WAZUH_VERSION"
echo "==========================================="
echo ""

# Export version for docker-compose
export WAZUH_VERSION

# Configuration
UNRAID_NVME_PATH="/mnt/user/appdata/wazuh"
UNRAID_DATA_PATH="/mnt/user/wazuh-data/live-data"
WORK_DIR="$UNRAID_NVME_PATH/temp"

# Verify we're running on Unraid
if [ ! -d "/mnt/user" ]; then
    echo "❌ Error: This script must run on the Unraid server"
    echo "   Please copy this script to Unraid and run it there"
    exit 1
fi

# Verify directories exist
if [ ! -d "$UNRAID_NVME_PATH" ] || [ ! -d "$UNRAID_DATA_PATH" ]; then
    echo "❌ Error: Required Unraid directories do not exist"
    echo "   Expected: $UNRAID_NVME_PATH and $UNRAID_DATA_PATH"
    echo "   Please run cleanup script first"
    exit 1
fi

# Verify our pre-edited files exist
if [ ! -f "$UNRAID_NVME_PATH/docker-compose-unraid.yml" ]; then
    echo "❌ Error: Pre-edited docker-compose-unraid.yml not found"
    echo "   Please copy docker-compose-unraid.yml to $UNRAID_NVME_PATH"
    exit 1
fi

if [ ! -f "$UNRAID_NVME_PATH/certs-unraid.yml" ]; then
    echo "❌ Error: Pre-edited certs-unraid.yml not found"
    echo "   Please copy certs-unraid.yml to $UNRAID_NVME_PATH"
    exit 1
fi

echo "📥 Step 1: Setting up official Wazuh configuration files..."
echo "Creating temporary work directory..."
mkdir -p $WORK_DIR
cd $WORK_DIR

echo "Cloning wazuh-docker repository for config files..."
git clone https://github.com/wazuh/wazuh-docker.git -b v$WAZUH_VERSION .

if [ ! -d "single-node" ]; then
    echo "❌ Error: Failed to clone repository or single-node directory not found"
    exit 1
fi

echo "✅ Repository cloned successfully"
echo ""

echo "📤 Step 2: Copying official files to Unraid paths..."
# Copy everything except docker-compose.yml (we'll use our pre-edited version)
cp -r single-node/* $UNRAID_NVME_PATH/
cd $UNRAID_NVME_PATH

# Replace with our pre-edited files
cp docker-compose-unraid.yml docker-compose.yml
cp certs-unraid.yml config/certs.yml

# Add path.repo to indexer config for snapshot support
echo '' >> config/wazuh_indexer/wazuh.indexer.yml
echo 'path.repo: ["/usr/share/wazuh-indexer/snapshots"]' >> config/wazuh_indexer/wazuh.indexer.yml

echo "✅ Files copied and replaced with Unraid versions (docker-compose.yml, certs.yml, wazuh.indexer.yml)"
echo ""

echo "🔧 Step 3: Creating volume directories..."

echo "Creating volume directories..."
mkdir -p volumes/{wazuh_api_configuration,wazuh_etc,wazuh_integrations,wazuh_active_response,wazuh_agentless,wazuh_wodles,filebeat_etc,filebeat_var,wazuh-dashboard-config,wazuh-dashboard-custom}
mkdir -p $UNRAID_DATA_PATH/{wazuh_logs,wazuh_queue,wazuh_var_multigroups,wazuh-indexer-data}

echo "Setting proper permissions..."
chown -R 1000:users volumes/ $UNRAID_DATA_PATH/
chmod -R 755 volumes/ $UNRAID_DATA_PATH/

# Create ar.conf file to prevent manager initialization failure
echo "Creating ar.conf file for active response configuration..."
mkdir -p volumes/wazuh_etc/shared
touch volumes/wazuh_etc/shared/ar.conf
chown root:999 volumes/wazuh_etc/shared/ar.conf
chmod 660 volumes/wazuh_etc/shared/ar.conf

echo "✅ Volume setup completed"
echo ""

echo "🔐 Step 4: Generating certificates using official method..."
echo "Running official certificate generation..."
docker-compose -f generate-indexer-certs.yml run --rm generator

# Set proper permissions on certificates
chown -R 1000:users config/
chmod -R 755 config/

echo "Certificate files created:"
ls -la config/wazuh_indexer_ssl_certs/

echo "✅ Certificates generated successfully"
echo ""

echo "🚀 Step 5: Starting Wazuh deployment..."
echo "Starting containers..."
docker-compose up -d

echo ""
echo "⏳ Step 5.5: Waiting for indexer to fully stabilize..."
echo "   This ensures dashboard migration won't fail due to indexer not being ready"
echo ""

# Configuration
INDEXER_IP="10.2.0.86"
INDEXER_TIMEOUT=300  # 5 minutes

# Wait for indexer to respond
echo "   Waiting for indexer to respond (timeout: ${INDEXER_TIMEOUT}s)..."
INDEXER_READY=false
ELAPSED=0
while [ $ELAPSED -lt $INDEXER_TIMEOUT ]; do
    if curl -k -s --max-time 5 -u admin:SecretPassword "https://$INDEXER_IP:9200/" >/dev/null 2>&1; then
        echo "   ✅ Indexer responding (after ${ELAPSED}s)"
        INDEXER_READY=true
        break
    fi

    if [ $((ELAPSED % 10)) -eq 0 ] && [ $ELAPSED -gt 0 ]; then
        echo "   ⏳ Still waiting for indexer to respond... (${ELAPSED}s elapsed)"
    fi

    sleep 2
    ELAPSED=$((ELAPSED + 2))
done

if [ "$INDEXER_READY" = false ]; then
    echo "   ❌ ERROR: Indexer failed to respond after ${INDEXER_TIMEOUT}s"
    echo "   This indicates a real problem with indexer startup"
    exit 1
fi

# Wait for cluster health to be at least YELLOW
echo "   Waiting for indexer cluster health to be ready (timeout: ${INDEXER_TIMEOUT}s)..."
CLUSTER_READY=false
ELAPSED=0
while [ $ELAPSED -lt $INDEXER_TIMEOUT ]; do
    HEALTH=$(curl -k -s --max-time 5 -u admin:SecretPassword "https://$INDEXER_IP:9200/_cluster/health" 2>/dev/null)

    if echo "$HEALTH" | grep -q '"status":"green"'; then
        echo "   ✅ Cluster health: GREEN (after ${ELAPSED}s)"
        CLUSTER_READY=true
        break
    elif echo "$HEALTH" | grep -q '"status":"yellow"'; then
        echo "   ✅ Cluster health: YELLOW (after ${ELAPSED}s)"
        CLUSTER_READY=true
        break
    fi

    if [ $((ELAPSED % 10)) -eq 0 ] && [ $ELAPSED -gt 0 ]; then
        echo "   ⏳ Still waiting for cluster health... (${ELAPSED}s elapsed)"
    fi

    sleep 2
    ELAPSED=$((ELAPSED + 2))
done

if [ "$CLUSTER_READY" = false ]; then
    echo "   ❌ ERROR: Cluster failed to reach healthy state after ${INDEXER_TIMEOUT}s"
    echo "   This indicates a real problem with cluster initialization"
    exit 1
fi

# Additional stabilization wait - let indexer fully settle
echo "   ⏳ Allowing indexer to fully stabilize (30s additional wait)..."
sleep 30

echo "   ✅ Indexer fully ready and stable for dashboard initialization"
echo ""

echo "Container status:"
docker-compose ps

echo ""
echo "Cleaning up temporary files..."
rm -rf $WORK_DIR

echo ""
echo "============================================"
echo "  Deployment Complete!"
echo "==========================================="
echo ""
echo "🌐 Access URLs:"
echo "   - Dashboard: https://10.2.0.87:5601"
echo "   - Manager API: https://10.2.0.85:55000"
echo "   - Indexer: https://10.2.0.86:9200"
echo ""
echo "🔑 Default Credentials (from official deployment):"
echo "   - Dashboard: admin / SecretPassword"
echo "   - API: wazuh-wui / MyS3cr37P450r.*-"
echo ""
echo "📊 Storage Paths:"
echo "   - Configs (NVME): $UNRAID_NVME_PATH"
echo "   - Data (Array): $UNRAID_DATA_PATH"
echo ""
echo "🔍 To check logs:"
echo "   cd $UNRAID_NVME_PATH && docker-compose logs [service]"
echo ""
echo "🔄 To restart deployment:"
echo "   cd $UNRAID_NVME_PATH && docker-compose restart"
echo ""
echo "🛑 To stop deployment:"
echo "   cd $UNRAID_NVME_PATH && docker-compose down"
echo ""
