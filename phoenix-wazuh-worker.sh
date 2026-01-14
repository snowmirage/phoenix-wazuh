#!/bin/bash

# Phoenix Wazuh Worker Script - Fresh Install with Official Approach
# Follows official Wazuh Docker deployment with generated certificates
# This script runs ON the Phoenix Unraid server to deploy Docker containers

# Parse parameters from orchestrator
WAZUH_VERSION=$1

echo "==========================================="
echo "  Phoenix Wazuh Docker Deployment Worker"
echo "  Executing on Phoenix Unraid Server"
echo "  Mode: FRESH INSTALL (Official Approach)"
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

echo "📤 Step 2: Setting up configuration directories..."

# Create the config directory structure
mkdir -p $UNRAID_NVME_PATH/config/wazuh_indexer_ssl_certs
mkdir -p $UNRAID_NVME_PATH/config/wazuh_cluster
mkdir -p $UNRAID_NVME_PATH/config/wazuh_dashboard
mkdir -p $UNRAID_NVME_PATH/config/wazuh_indexer

# Copy config files from the cloned repo
cp single-node/config/wazuh_cluster/wazuh_manager.conf $UNRAID_NVME_PATH/config/wazuh_cluster/
cp single-node/config/wazuh_dashboard/opensearch_dashboards.yml $UNRAID_NVME_PATH/config/wazuh_dashboard/
cp single-node/config/wazuh_dashboard/wazuh.yml $UNRAID_NVME_PATH/config/wazuh_dashboard/
cp single-node/config/wazuh_indexer/wazuh.indexer.yml $UNRAID_NVME_PATH/config/wazuh_indexer/
cp single-node/config/wazuh_indexer/internal_users.yml $UNRAID_NVME_PATH/config/wazuh_indexer/

# Copy our pre-edited docker-compose (already copied by orchestrator)
# The orchestrator copies docker-compose-unraid.yml to this location
cp $UNRAID_NVME_PATH/docker-compose-unraid.yml $UNRAID_NVME_PATH/docker-compose.yml

# Copy certs.yml for certificate generation
cp single-node/config/certs.yml $UNRAID_NVME_PATH/config/certs.yml

# Add path.repo to indexer config for snapshot support
echo '' >> $UNRAID_NVME_PATH/config/wazuh_indexer/wazuh.indexer.yml
echo 'path.repo: ["/usr/share/wazuh-indexer/snapshots"]' >> $UNRAID_NVME_PATH/config/wazuh_indexer/wazuh.indexer.yml

echo "✅ Configuration files copied"
echo ""

echo "🔐 Step 3: Generating SSL certificates..."
cd $UNRAID_NVME_PATH

# Create certificate generation compose file
cat > generate-certs.yml << 'CERTEOF'
services:
  generator:
    image: wazuh/wazuh-certs-generator:0.0.2
    hostname: wazuh-certs-generator
    volumes:
      - ./config/wazuh_indexer_ssl_certs/:/certificates/
      - ./config/certs.yml:/config/certs.yml
CERTEOF

echo "Running certificate generator..."
docker compose -f generate-certs.yml run --rm generator

if [ ! -f "$UNRAID_NVME_PATH/config/wazuh_indexer_ssl_certs/root-ca.pem" ]; then
    echo "❌ Error: Certificate generation failed"
    exit 1
fi

echo "✅ SSL certificates generated successfully"

# List generated certificates
echo "Generated certificates:"
ls -la $UNRAID_NVME_PATH/config/wazuh_indexer_ssl_certs/
echo ""

echo "🔧 Step 4: Creating data directories..."

# Create data directories on array
mkdir -p $UNRAID_DATA_PATH/{wazuh_logs,wazuh_queue,wazuh_var_multigroups,wazuh-indexer-data}
mkdir -p /mnt/user/wazuh-data/snapshots

# Set proper permissions for data directories
chown -R 1000:1000 $UNRAID_DATA_PATH/
chmod -R 755 $UNRAID_DATA_PATH/

# Set permissions for indexer data directory specifically
chown -R 1000:1000 $UNRAID_DATA_PATH/wazuh-indexer-data
chmod 755 $UNRAID_DATA_PATH/wazuh-indexer-data

# Set permissions for snapshots directory
chown -R 1000:1000 /mnt/user/wazuh-data/snapshots
chmod 755 /mnt/user/wazuh-data/snapshots

echo "✅ Data directories created with proper permissions"
echo ""

echo "🚀 Step 5: Starting Wazuh deployment..."
cd $UNRAID_NVME_PATH
docker-compose up -d

echo ""
echo "⏳ Step 5.5: Waiting for indexer to initialize..."

# Configuration
INDEXER_IP="10.2.0.86"
INDEXER_TIMEOUT=300  # 5 minutes

# Wait for indexer to respond
echo "   Waiting for indexer to start (timeout: ${INDEXER_TIMEOUT}s)..."
INDEXER_READY=false
ELAPSED=0
while [ $ELAPSED -lt $INDEXER_TIMEOUT ]; do
    # Check if indexer is responding (might return auth error but that's OK)
    RESPONSE=$(curl -k -s --max-time 5 "https://$INDEXER_IP:9200/" 2>/dev/null)
    if [ -n "$RESPONSE" ]; then
        echo "   ✅ Indexer process responding (after ${ELAPSED}s)"
        INDEXER_READY=true
        break
    fi

    if [ $((ELAPSED % 10)) -eq 0 ] && [ $ELAPSED -gt 0 ]; then
        echo "   ⏳ Still waiting for indexer to start... (${ELAPSED}s elapsed)"
    fi

    sleep 2
    ELAPSED=$((ELAPSED + 2))
done

if [ "$INDEXER_READY" = false ]; then
    echo "   ❌ ERROR: Indexer failed to start after ${INDEXER_TIMEOUT}s"
    exit 1
fi

# Give indexer time to fully initialize
echo "   ⏳ Allowing indexer to fully initialize (45s)..."
sleep 45
echo ""

echo "🔐 Step 6: Initializing OpenSearch Security..."
echo "   Running securityadmin.sh with generated certificates..."

# Run security initialization using the generated certificates
SECURITY_INIT_OUTPUT=$(docker exec wazuh-wazuh.indexer-1 bash -c '
  JAVA_HOME=/usr/share/wazuh-indexer/jdk \
  /usr/share/wazuh-indexer/plugins/opensearch-security/tools/securityadmin.sh \
    -cd /usr/share/wazuh-indexer/config/opensearch-security/ \
    -cacert /usr/share/wazuh-indexer/config/certs/root-ca.pem \
    -cert /usr/share/wazuh-indexer/config/certs/admin.pem \
    -key /usr/share/wazuh-indexer/config/certs/admin-key.pem \
    -icl -nhnv -h localhost
' 2>&1)

if echo "$SECURITY_INIT_OUTPUT" | grep -q "Done with success"; then
    echo "   ✅ Security initialization completed successfully"
else
    echo "   ⚠️  Security initialization output:"
    echo "$SECURITY_INIT_OUTPUT" | tail -20
    # Check if it's just because index already exists
    if echo "$SECURITY_INIT_OUTPUT" | grep -q "already exists"; then
        echo "   ✅ Security index already exists - continuing"
    else
        echo "   ❌ Security initialization may have failed - check output above"
    fi
fi
echo ""

echo "   ⏳ Waiting for security to propagate (15s)..."
sleep 15

# Check cluster health
echo "   Checking cluster health..."
HEALTH=$(curl -k -s --max-time 10 -u admin:SecretPassword "https://$INDEXER_IP:9200/_cluster/health" 2>/dev/null)

if echo "$HEALTH" | grep -q '"status":"green"'; then
    echo "   ✅ Cluster health: GREEN"
elif echo "$HEALTH" | grep -q '"status":"yellow"'; then
    echo "   ✅ Cluster health: YELLOW (acceptable for single-node)"
else
    echo "   ⚠️  Cluster health check returned: $HEALTH"
fi

echo "   ✅ Indexer ready and security initialized"
echo ""

echo "⏳ Step 7: Waiting for all services to stabilize..."
sleep 30

echo "Container status:"
docker-compose ps

echo ""
echo "Cleaning up temporary files..."
rm -rf $WORK_DIR
rm -f $UNRAID_NVME_PATH/generate-certs.yml

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
echo "🔑 Default Credentials:"
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
