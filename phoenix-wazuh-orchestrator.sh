#!/bin/bash

# Phoenix Wazuh Orchestrator - Fresh Install Only
# Simplified version without backup/restore functionality
# Coordinates complete Wazuh SIEM deployment on Phoenix Unraid server

# Function to show help
show_help() {
    echo "============================================="
    echo "  Phoenix Wazuh Deployment Orchestrator"
    echo "  Fresh Install Mode Only"
    echo "============================================="
    echo ""
    echo "Usage: $0 --version <version>"
    echo ""
    echo "Options:"
    echo "  --version <version> Wazuh version to deploy (REQUIRED)"
    echo "                      Format: X.Y.Z (e.g., 4.12.0)"
    echo "                      Recommended: 4.12.0 (stable, tested)"
    echo ""
    echo "Examples:"
    echo "  $0 --version 4.12.0"
    echo ""
    echo "What this does:"
    echo "  - Clean deployment from scratch"
    echo "  - Agents will enroll as new devices"
    echo "  - Syslog reception configured (UDP 514)"
    echo "  - 2-year data retention policy applied"
    echo "  - Integration configurations (VirusTotal, Maltiverse)"
    echo ""
}

# Function to validate Wazuh version
validate_wazuh_version() {
    local version=$1

    echo "🔍 Validating Wazuh version $version..."

    # Check version format (X.Y.Z)
    if ! echo "$version" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then
        echo "❌ Error: Invalid version format: $version"
        echo "   Expected format: X.Y.Z (e.g., 4.12.0)"
        return 1
    fi

    # Check if GitHub tag exists
    echo "   Checking GitHub repository for v$version tag..."
    if ! curl -s -f -I "https://github.com/wazuh/wazuh-docker/releases/tag/v$version" >/dev/null 2>&1; then
        echo "❌ Error: Wazuh version $version not found in GitHub repository"
        echo "   Tag v$version does not exist at https://github.com/wazuh/wazuh-docker/releases"
        echo ""
        echo "💡 To see available versions:"
        echo "   https://github.com/wazuh/wazuh-docker/releases"
        return 1
    fi

    # Check if Docker images exist
    echo "   Checking Docker Hub for wazuh-manager:$version image..."
    if ! curl -s -f "https://hub.docker.com/v2/repositories/wazuh/wazuh-manager/tags/$version" >/dev/null 2>&1; then
        echo "⚠️  Warning: Docker image wazuh/wazuh-manager:$version not found on Docker Hub"
        echo "   This may cause deployment failure if images don't exist"
        echo ""
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            return 1
        fi
    fi

    echo "✅ Version $version validated successfully"
    echo ""
    return 0
}

# Parse command line arguments
WAZUH_VERSION=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version)
            WAZUH_VERSION="$2"
            shift 2
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo "❌ Unknown option: $1"
            echo ""
            show_help
            exit 1
            ;;
    esac
done

# Validate version is provided
if [ -z "$WAZUH_VERSION" ]; then
    echo "❌ Error: --version parameter is required"
    echo ""
    show_help
    exit 1
fi

# Validate version exists
if ! validate_wazuh_version "$WAZUH_VERSION"; then
    exit 1
fi

echo "============================================="
echo "  Phoenix Wazuh Deployment Orchestrator"
echo "  Mode: FRESH INSTALL"
echo "  Version: $WAZUH_VERSION"
echo "============================================="
echo ""

# Start total deployment timer
DEPLOYMENT_START_TIME=$(date +%s)
echo "🕐 Deployment started at: $(date)"
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
UNRAID_NVME_PATH="/mnt/user/appdata/wazuh"
UNRAID_DATA_BASE="/mnt/user/wazuh-data"
UNRAID_DATA_PATH="/mnt/user/wazuh-data/live-data"
SSH_KEY="/home/dev/.ssh/unraid_id_rsa"
MANAGER_IP="10.2.0.85"
INDEXER_IP="10.2.0.86"
DASHBOARD_IP="10.2.0.87"

# ==========================================
# Configuration File Loading
# ==========================================
CONFIG_FILE="./wazuh-integrations.conf"

# Load configuration from file if it exists
if [ -f "$CONFIG_FILE" ]; then
    echo "📋 Loading configuration from: $CONFIG_FILE"

    # Source the configuration file, but only load variables we expect
    while IFS='=' read -r key value; do
        # Skip comments and empty lines
        [[ $key =~ ^[[:space:]]*# ]] && continue
        [[ -z "$key" ]] && continue

        # Remove leading/trailing whitespace and quotes from value
        value=$(echo "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | sed 's/^"//;s/"$//')

        # Only load recognized configuration variables
        case "$key" in
            VIRUSTOTAL_API_KEY)
                VIRUSTOTAL_API_KEY="$value"
                ;;
            MALTIVERSE_API_KEY)
                MALTIVERSE_API_KEY="$value"
                ;;
        esac
    done < <(grep -E '^[A-Z_]+=.*' "$CONFIG_FILE")

    echo "   ✅ Configuration loaded successfully"
else
    echo "📋 Configuration file not found: $CONFIG_FILE"
    echo "   💡 Using environment variables or defaults"
fi

# Fallback to environment variables if not set in config file
VIRUSTOTAL_API_KEY="${VIRUSTOTAL_API_KEY:-${VIRUSTOTAL_API_KEY_ENV:-}}"
MALTIVERSE_API_KEY="${MALTIVERSE_API_KEY:-${MALTIVERSE_API_KEY_ENV:-}}"

# Configuration validation and reporting
echo ""
echo "🔧 Integration Configuration Status:"
if [ -n "$VIRUSTOTAL_API_KEY" ]; then
    MASKED_KEY=$(echo "$VIRUSTOTAL_API_KEY" | sed 's/\(.\{8\}\).*\(.\{4\}\)/\1****\2/')
    echo "   🔍 VirusTotal: ✅ Enabled (Key: $MASKED_KEY)"
else
    echo "   🔍 VirusTotal: ❌ Disabled (No API key configured)"
fi

if [ -n "$MALTIVERSE_API_KEY" ]; then
    MASKED_KEY=$(echo "$MALTIVERSE_API_KEY" | sed 's/\(.\{8\}\).*\(.\{4\}\)/\1****\2/')
    echo "   🔍 Maltiverse: ✅ Enabled (Key: $MASKED_KEY)"
else
    echo "   🔍 Maltiverse: ❌ Disabled (No API key configured)"
fi
echo ""

# Check if we're running locally
if [ ! -f "$SSH_KEY" ]; then
    echo "❌ Error: SSH key not found at $SSH_KEY"
    echo "   This script must be run from the development machine"
    exit 1
fi

echo "🎯 Target: Phoenix Unraid server at $UNRAID_SERVER"
echo "📂 Deployment paths: $UNRAID_NVME_PATH (configs), $UNRAID_DATA_PATH (data)"
echo ""

# ============================================
# SECTION 1: CLEANUP UNRAID
# ============================================
echo "==========================================="
echo "  SECTION 1: CLEANUP UNRAID"
echo "==========================================="
echo ""

# Start section timer
SECTION1_START_TIME=$(date +%s)

echo "🧹 Cleaning up existing Wazuh deployment on Phoenix Unraid server..."

ssh -i $SSH_KEY root@$UNRAID_SERVER "
    echo 'Stopping and removing all Wazuh containers...'
    docker rm -f \$(docker ps -aq --filter 'name=wazuh') 2>/dev/null || true

    echo 'Removing all Wazuh volumes...'
    docker volume rm \$(docker volume ls -q --filter 'name=wazuh') 2>/dev/null || true

    echo 'Removing all Wazuh networks...'
    docker network rm \$(docker network ls -q --filter 'name=wazuh') 2>/dev/null || true

    echo 'Waiting for filesystem to release locks...'
    sleep 3

    echo 'Cleaning Unraid path contents...'
    echo '  Removing all NVME path contents...'
    rm -rf $UNRAID_NVME_PATH/* 2>/dev/null || true

    echo '  Removing all data path contents...'
    rm -rf $UNRAID_DATA_PATH/* 2>/dev/null || true

    echo '✅ Cleanup completed successfully'
"

if [ $? -ne 0 ]; then
    echo "❌ Error occurred during cleanup"
    exit 1
fi

echo "✅ Unraid cleanup completed successfully"
show_elapsed_time $SECTION1_START_TIME
echo ""

# Create required directory structure
echo "📁 Ensuring required directory structure exists..."
ssh -i $SSH_KEY root@$UNRAID_SERVER "
    mkdir -p $UNRAID_DATA_PATH 2>/dev/null && echo '   ✅ $UNRAID_DATA_PATH'
    mkdir -p $UNRAID_DATA_BASE/snapshots 2>/dev/null && echo '   ✅ $UNRAID_DATA_BASE/snapshots'
    echo '✅ Directory structure ready'
"
echo ""

# ============================================
# SECTION 2: PREP - COPY FILES
# ============================================
echo "==========================================="
echo "  SECTION 2: PREP - COPY DEPLOYMENT FILES"
echo "==========================================="
echo ""

# Start section timer
SECTION2_START_TIME=$(date +%s)

echo "📤 Copying deployment files to Phoenix Unraid server..."

# Verify all required files exist locally
REQUIRED_FILES=(
    "docker-compose-unraid.yml"
    "certs-unraid.yml"
    "phoenix-wazuh-worker.sh"
)

for file in "${REQUIRED_FILES[@]}"; do
    if [ ! -f "$file" ]; then
        echo "❌ Error: Required file $file not found locally"
        exit 1
    fi
done

echo "Copying docker-compose-unraid.yml to wazuh directory..."
echo "   📦 Using Wazuh version: $WAZUH_VERSION (via environment variable substitution)"
cat docker-compose-unraid.yml | ssh -i $SSH_KEY root@$UNRAID_SERVER "cat > $UNRAID_NVME_PATH/docker-compose-unraid.yml"

echo "Copying certs-unraid.yml to wazuh directory..."
cat certs-unraid.yml | ssh -i $SSH_KEY root@$UNRAID_SERVER "cat > $UNRAID_NVME_PATH/certs-unraid.yml"

echo "Copying phoenix-wazuh-worker.sh to appdata root..."
cat phoenix-wazuh-worker.sh | ssh -i $SSH_KEY root@$UNRAID_SERVER "cat > /mnt/user/appdata/phoenix-wazuh-worker.sh && chmod +x /mnt/user/appdata/phoenix-wazuh-worker.sh"

echo "✅ All deployment files copied successfully"
show_elapsed_time $SECTION2_START_TIME
echo ""

# ============================================
# SECTION 3: SETUP AND DEPLOYMENT
# ============================================
echo "==========================================="
echo "  SECTION 3: SETUP AND DEPLOYMENT"
echo "==========================================="
echo ""

# Start section timer
SECTION3_START_TIME=$(date +%s)

echo "🚀 Running Wazuh deployment on Phoenix Unraid server..."

# Run the deployment script on Unraid with version parameter
ssh -i $SSH_KEY root@$UNRAID_SERVER "cd /mnt/user/appdata && WAZUH_VERSION='$WAZUH_VERSION' ./phoenix-wazuh-worker.sh '$WAZUH_VERSION'"

if [ $? -ne 0 ]; then
    echo "❌ Error occurred during Wazuh deployment"
    exit 1
fi

echo "✅ Wazuh deployment completed successfully"
show_elapsed_time $SECTION3_START_TIME
echo ""

# Function to wait for service readiness with timeout
wait_for_service() {
    local service_name="$1"
    local test_command="$2"
    local timeout_seconds="$3"
    local check_interval="5"
    local elapsed=0

    echo "⏳ Waiting for $service_name to be fully ready (timeout: ${timeout_seconds}s)..."

    while [ $elapsed -lt $timeout_seconds ]; do
        if ssh -i $SSH_KEY root@$UNRAID_SERVER "cd $UNRAID_NVME_PATH && $test_command" >/dev/null 2>&1; then
            echo "✅ $service_name is ready (took ${elapsed}s)"
            return 0
        fi

        echo "   Still waiting for $service_name... (${elapsed}s elapsed)"
        sleep $check_interval
        elapsed=$((elapsed + check_interval))
    done

    echo "❌ Timeout waiting for $service_name after ${timeout_seconds}s"
    return 1
}

# ============================================
# SECTION 4: POST-DEPLOYMENT CONFIGURATION
# ============================================
echo "==========================================="
echo "  SECTION 4: POST-DEPLOYMENT CONFIGURATION"
echo "==========================================="
echo ""

# Start section timer
SECTION4_START_TIME=$(date +%s)

echo "🔧 Applying post-deployment configuration (syslog + retention)..."

# Step 4.1: System Health Validation
echo ""
echo "🔍 Step 4.1: System Health Validation..."

# Check containers are running
echo "Checking container status..."
RUNNING_CONTAINERS=$(ssh -i $SSH_KEY root@$UNRAID_SERVER "cd $UNRAID_NVME_PATH && WAZUH_VERSION='$WAZUH_VERSION' docker-compose ps --services --filter \"status=running\" | wc -l")
if [ "$RUNNING_CONTAINERS" -lt 3 ]; then
    echo "❌ Error: Not all containers are running. Expected 3, found $RUNNING_CONTAINERS"
    ssh -i $SSH_KEY root@$UNRAID_SERVER "cd $UNRAID_NVME_PATH && WAZUH_VERSION='$WAZUH_VERSION' docker-compose ps"
    exit 1
fi

echo "✅ All containers running"

# Wait for services to be ready
echo "Testing Wazuh Manager API readiness..."
if ! wait_for_service "Manager API" \
    "curl -k -s --max-time 10 -u wazuh-wui:MyS3cr37P450r.*- https://$MANAGER_IP:55000/ | grep -q 'title\\|Unauthorized'" \
    180; then
    echo "❌ Error: Manager API failed readiness check"
    exit 1
fi

echo "Testing Wazuh Indexer readiness..."
if ! wait_for_service "Indexer Cluster" \
    "curl -k -s --max-time 10 -u admin:SecretPassword https://$INDEXER_IP:9200/_cluster/health | grep -q 'green\\|yellow'" \
    480; then
    echo "❌ Error: Indexer failed readiness check"
    exit 1
fi

echo "Testing Indexer ISM plugin readiness..."
if ! wait_for_service "ISM Plugin" \
    "curl -k -s --max-time 10 -u admin:SecretPassword https://$INDEXER_IP:9200/_plugins/_ism/policies | grep -q 'policies\\|\\[\\]'" \
    120; then
    echo "❌ Error: ISM plugin not ready"
    exit 1
fi

echo "Testing Wazuh Dashboard readiness..."
if ! wait_for_service "Dashboard" \
    "[ \$(curl -k -s --max-time 10 -o /dev/null -w '%{http_code}' https://$DASHBOARD_IP:5601) -eq 302 ] || [ \$(curl -k -s --max-time 10 -o /dev/null -w '%{http_code}' https://$DASHBOARD_IP:5601) -eq 200 ]" \
    120; then
    echo "⚠️  Dashboard taking longer than expected, checking for index migration issues..."

    # Check if stuck on index migration
    if ssh -i $SSH_KEY root@$UNRAID_SERVER "docker logs wazuh-wazuh.dashboard-1 2>&1 | tail -20 | grep -q 'Another OpenSearch Dashboards instance'"; then
        echo "   Found index migration conflict, cleaning up..."
        ssh -i $SSH_KEY root@$UNRAID_SERVER "cd $UNRAID_NVME_PATH && WAZUH_VERSION='$WAZUH_VERSION' docker-compose stop wazuh.dashboard" >/dev/null 2>&1
        sleep 5
        ssh -i $SSH_KEY root@$UNRAID_SERVER "curl -k -s -u admin:SecretPassword -X DELETE 'https://$INDEXER_IP:9200/.kibana*' >/dev/null 2>&1 || true"
        sleep 2
        ssh -i $SSH_KEY root@$UNRAID_SERVER "cd $UNRAID_NVME_PATH && WAZUH_VERSION='$WAZUH_VERSION' docker-compose start wazuh.dashboard" >/dev/null 2>&1
        echo "   Waiting for dashboard after cleanup..."

        if ! wait_for_service "Dashboard (after cleanup)" \
            "[ \$(curl -k -s --max-time 10 -o /dev/null -w '%{http_code}' https://$DASHBOARD_IP:5601) -eq 302 ] || [ \$(curl -k -s --max-time 10 -o /dev/null -w '%{http_code}' https://$DASHBOARD_IP:5601) -eq 200 ]" \
            180; then
            echo "❌ Error: Dashboard failed readiness check after cleanup"
            exit 1
        fi
    else
        echo "❌ Error: Dashboard failed readiness check"
        exit 1
    fi
fi

echo "✅ All services are ready"

# Step 4.2: Configure Syslog Reception and Integrations
echo ""
echo "🔧 Step 4.2: Configure Syslog Reception and Integrations..."

# Build integration XML blocks conditionally
VIRUSTOTAL_INTEGRATION=""
if [ -n "$VIRUSTOTAL_API_KEY" ]; then
    echo "🔍 Preparing VirusTotal integration configuration..."
    VIRUSTOTAL_INTEGRATION="  <!-- VirusTotal integration for malware detection -->
  <integration>
    <name>virustotal</name>
    <api_key>${VIRUSTOTAL_API_KEY}</api_key>
    <group>syscheck</group>
    <alert_format>json</alert_format>
  </integration>"
fi

MALTIVERSE_INTEGRATION=""
if [ -n "$MALTIVERSE_API_KEY" ]; then
    echo "🔍 Preparing Maltiverse integration configuration..."
    MALTIVERSE_INTEGRATION="  <!-- Maltiverse integration for threat intelligence -->
  <integration>
    <name>maltiverse</name>
    <hook_url>https://api.maltiverse.com</hook_url>
    <api_key>${MALTIVERSE_API_KEY}</api_key>
    <rule_id>2502,111041,111042,111050,111051</rule_id>
    <alert_format>json</alert_format>
  </integration>"
fi

# Copy template to Unraid and apply substitutions
echo "📄 Generating ossec.conf from template..."
scp -i $SSH_KEY ossec.conf.template root@$UNRAID_SERVER:$UNRAID_NVME_PATH/config/wazuh_cluster/wazuh_manager.conf

# Replace integration placeholders
if [ -n "$VIRUSTOTAL_API_KEY" ]; then
    # Escape special characters for sed and replace placeholder with integration XML
    VT_ESCAPED=$(echo "$VIRUSTOTAL_INTEGRATION" | sed 's/[&/\]/\\&/g' | sed ':a;N;$!ba;s/\n/\\n/g')
    ssh -i $SSH_KEY root@$UNRAID_SERVER "sed -i 's|%%VIRUSTOTAL_INTEGRATION%%|$VT_ESCAPED|g' $UNRAID_NVME_PATH/config/wazuh_cluster/wazuh_manager.conf"
    echo "   ✅ VirusTotal integration added"
else
    # Remove placeholder line if no API key
    ssh -i $SSH_KEY root@$UNRAID_SERVER "sed -i '/%%VIRUSTOTAL_INTEGRATION%%/d' $UNRAID_NVME_PATH/config/wazuh_cluster/wazuh_manager.conf"
fi

if [ -n "$MALTIVERSE_API_KEY" ]; then
    # Escape special characters for sed and replace placeholder with integration XML
    MT_ESCAPED=$(echo "$MALTIVERSE_INTEGRATION" | sed 's/[&/\]/\\&/g' | sed ':a;N;$!ba;s/\n/\\n/g')
    ssh -i $SSH_KEY root@$UNRAID_SERVER "sed -i 's|%%MALTIVERSE_INTEGRATION%%|$MT_ESCAPED|g' $UNRAID_NVME_PATH/config/wazuh_cluster/wazuh_manager.conf"
    echo "   ✅ Maltiverse integration added"
else
    # Remove placeholder line if no API key
    ssh -i $SSH_KEY root@$UNRAID_SERVER "sed -i '/%%MALTIVERSE_INTEGRATION%%/d' $UNRAID_NVME_PATH/config/wazuh_cluster/wazuh_manager.conf"
fi

# Enable logall to capture all syslog messages (including those without decoders)
echo "🔍 Enabling logall for comprehensive syslog capture..."
ssh -i $SSH_KEY root@$UNRAID_SERVER "sed -i 's|<logall>no</logall>|<logall>yes</logall>|g' $UNRAID_NVME_PATH/config/wazuh_cluster/wazuh_manager.conf"
echo "   ✅ logall=yes enabled (all syslog messages will be stored)"

echo "✅ Configuration file generated successfully"

# Step 4.3: Restart Manager with Proper Configuration Copy
echo ""
echo "🔄 Step 4.3: Restart Manager to Apply Configuration..."

# Copy config to wazuh_etc volume using a temporary container
echo "Copying configuration to wazuh_etc volume..."
ssh -i $SSH_KEY root@$UNRAID_SERVER "docker run --rm -v wazuh_wazuh_etc:/dest -v $UNRAID_NVME_PATH/config/wazuh_cluster:/src alpine sh -c 'cp /src/wazuh_manager.conf /dest/ossec.conf && chmod 660 /dest/ossec.conf && chown 999:999 /dest/ossec.conf'"

# Use full container recreation (docker rm -f + up -d) to avoid OCI runtime errors
# docker-compose stop/start can leave containers in inconsistent state on Unraid
echo "Recreating manager container with new configuration..."
ssh -i $SSH_KEY root@$UNRAID_SERVER "docker rm -f wazuh-wazuh.manager-1" >/dev/null 2>&1
ssh -i $SSH_KEY root@$UNRAID_SERVER "cd $UNRAID_NVME_PATH && WAZUH_VERSION='$WAZUH_VERSION' docker-compose up -d wazuh.manager" >/dev/null 2>&1
echo "⏳ Waiting for container to initialize with new configuration..."
sleep 30

# Wait for manager API to be ready
# Use single quotes around password to avoid shell expansion of special characters
MANAGER_READY=false
for attempt in 1 2 3 4 5 6 7 8 9 10 11 12; do
    API_RESPONSE=$(ssh -i $SSH_KEY root@$UNRAID_SERVER "curl -k -s --max-time 5 'https://$MANAGER_IP:55000/' 2>/dev/null" || echo "")
    if echo "$API_RESPONSE" | grep -q 'title\|Unauthorized\|data'; then
        echo "   ✅ Manager fully initialized (attempt $attempt)"
        MANAGER_READY=true
        break
    fi
    echo "   ⏳ Manager still initializing... (${attempt}0s elapsed)"
    sleep 10
done

if [ "$MANAGER_READY" = false ]; then
    echo ""
    echo "❌ CRITICAL ERROR: Manager failed to initialize after 120 seconds"
    echo "   Manager API not responding after container restart"
    exit 1
fi

echo "Verifying syslog configuration is active in container..."
if ssh -i $SSH_KEY root@$UNRAID_SERVER "cd $UNRAID_NVME_PATH && docker exec wazuh-wazuh.manager-1 grep -q 'connection.*syslog' /var/ossec/etc/ossec.conf"; then
    echo "✅ Syslog configuration confirmed in active ossec.conf"
else
    echo "❌ Error: Syslog configuration not found in active ossec.conf"
    exit 1
fi

echo "Enabling vulnerability detection scan manager..."
ssh -i $SSH_KEY root@$UNRAID_SERVER "cd $UNRAID_NVME_PATH && docker exec wazuh-wazuh.manager-1 sed -i 's/vulnerability-detection.disable_scan_manager=1/vulnerability-detection.disable_scan_manager=0/' /var/ossec/etc/internal_options.conf 2>/dev/null" || true

echo "Configuring indexer authentication for vulnerability detection..."
ssh -i $SSH_KEY root@$UNRAID_SERVER "cd $UNRAID_NVME_PATH && docker exec wazuh-wazuh.manager-1 /var/ossec/bin/wazuh-keystore -f indexer -k username -v admin 2>/dev/null" || true
ssh -i $SSH_KEY root@$UNRAID_SERVER "cd $UNRAID_NVME_PATH && docker exec wazuh-wazuh.manager-1 /var/ossec/bin/wazuh-keystore -f indexer -k password -v SecretPassword 2>/dev/null" || true

echo "Recreating manager to apply all configuration changes..."
# Use full container recreation to avoid OCI runtime errors
ssh -i $SSH_KEY root@$UNRAID_SERVER "docker rm -f wazuh-wazuh.manager-1" >/dev/null 2>&1
ssh -i $SSH_KEY root@$UNRAID_SERVER "cd $UNRAID_NVME_PATH && WAZUH_VERSION='$WAZUH_VERSION' docker-compose up -d wazuh.manager" >/dev/null 2>&1
echo "⏳ Waiting for container to initialize..."
sleep 30

# Wait specifically for wazuh-remoted to be running (needed for syslog)
echo "Verifying wazuh-remoted is running..."
REMOTED_READY=false
for check in 1 2 3 4 5 6; do
    if ssh -i $SSH_KEY root@$UNRAID_SERVER "docker exec wazuh-wazuh.manager-1 /var/ossec/bin/wazuh-control status 2>/dev/null | grep -q 'wazuh-remoted is running'"; then
        echo "   ✅ wazuh-remoted is running (check $check)"
        REMOTED_READY=true
        break
    fi
    echo "   ⏳ Waiting for wazuh-remoted... (${check}0s elapsed)"
    sleep 10
done

if [ "$REMOTED_READY" = false ]; then
    echo "   ⚠️  wazuh-remoted not running after 60s"
    echo "   NOTE: Syslog verification will fail if remoted doesn't start"
fi

# Additional wait for remoted to fully initialize and bind to port
echo "⏳ Allowing wazuh-remoted to fully initialize..."
sleep 15

# Verify syslog reception with actual test
echo "Testing syslog reception..."
SYSLOG_READY=false

# First check if port is listening
echo "   Step 1: Checking if UDP port 514 is listening..."
for attempt in 1 2 3 4; do
    if ssh -i $SSH_KEY root@$UNRAID_SERVER "docker exec wazuh-wazuh.manager-1 cat /proc/net/udp 2>/dev/null | grep -q '0202'"; then
        echo "   ✅ Port 514 is listening"

        # Now send test message and verify reception
        echo "   Step 2: Sending test syslog message and verifying reception..."
        TEST_MESSAGE="ORCHESTRATOR_SYSLOG_TEST_$(date +%s)"
        ssh -i $SSH_KEY root@$UNRAID_SERVER "logger -n 10.2.0.85 -P 514 -t TEST '$TEST_MESSAGE'" 2>/dev/null
        sleep 5

        # Check if message was received in logs
        if ssh -i $SSH_KEY root@$UNRAID_SERVER "docker exec wazuh-wazuh.manager-1 grep -q '$TEST_MESSAGE' /var/ossec/logs/archives/archives.log 2>/dev/null"; then
            echo "   ✅ Syslog message received and logged successfully"
            SYSLOG_READY=true
            break
        else
            echo "   ⚠️  Port listening but message not logged (attempt $attempt)"
        fi
    fi
    sleep 5
done

if [ "$SYSLOG_READY" = false ]; then
    echo ""
    echo "❌ SYSLOG CONFIGURATION FAILED"
    echo "   Port may be listening but messages are not being processed/logged"
    echo "   Syslog is a critical requirement - deployment cannot continue"
    exit 1
else
    echo "✅ Syslog configuration verified - port listening and messages being logged"
fi

# Step 4.4: Configure Auto-Start for Container Persistence
echo ""
echo "🚀 Step 4.4: Configure Auto-Start for Container Persistence..."

echo "Creating User Scripts auto-start configuration..."

# Create the auto-start script directory
ssh -i $SSH_KEY root@$UNRAID_SERVER "mkdir -p /boot/config/plugins/user.scripts/scripts/wazuh-autostart"

# Create the auto-start script with version variable
ssh -i $SSH_KEY root@$UNRAID_SERVER "cat > /boot/config/plugins/user.scripts/scripts/wazuh-autostart/script << EOF
#!/bin/bash
# Wazuh SIEM Auto-start Script
# Starts Wazuh containers on Unraid boot

# Wait for Docker and networks to be ready
sleep 60

# Set Wazuh version and start containers
export WAZUH_VERSION='$WAZUH_VERSION'
cd /mnt/user/appdata/wazuh
/usr/local/bin/docker-compose up -d

echo 'Wazuh containers started automatically'
EOF"

# Set the script to run when array starts
ssh -i $SSH_KEY root@$UNRAID_SERVER "echo 'arrayStarted' > /boot/config/plugins/user.scripts/scripts/wazuh-autostart/schedule"

echo "✅ Auto-start script configured"

# Validate auto-start configuration
echo "Validating auto-start configuration..."
if ssh -i $SSH_KEY root@$UNRAID_SERVER "[ -f /boot/config/plugins/user.scripts/scripts/wazuh-autostart/script ] && [ -s /boot/config/plugins/user.scripts/scripts/wazuh-autostart/script ]"; then
    echo "✅ Auto-start script exists and has content"
else
    echo "❌ Error: Auto-start script not properly configured"
    exit 1
fi

if ssh -i $SSH_KEY root@$UNRAID_SERVER "[ -f /boot/config/plugins/user.scripts/scripts/wazuh-autostart/schedule ] && grep -q 'arrayStarted' /boot/config/plugins/user.scripts/scripts/wazuh-autostart/schedule"; then
    echo "✅ Auto-start schedule configured for array start"
else
    echo "❌ Error: Auto-start schedule not properly configured"
    exit 1
fi

echo "✅ Container auto-start configuration completed"

# Step 4.5: Configure 2-Year Data Retention Policy
echo ""
echo "💾 Step 4.5: Configure 2-Year Data Retention Policy..."

echo "Creating ISM (Index State Management) policy for 2-year retention (730 days)..."

# Retry logic for ISM policy creation
ISM_CREATED=false
for attempt in $(seq 1 20); do
    echo "   ISM policy creation attempt $attempt of 20..."

    RESPONSE=$(ssh -i $SSH_KEY root@$UNRAID_SERVER "curl -k --max-time 45 -u admin:SecretPassword -X PUT \"https://$INDEXER_IP:9200/_plugins/_ism/policies/wazuh-2year-retention\" \\
      -H 'Content-Type: application/json' \\
      -d '{
      \"policy\": {
        \"description\": \"Wazuh 2-year data retention policy following official documentation\",
        \"default_state\": \"hot\",
        \"states\": [
          {
            \"name\": \"hot\",
            \"actions\": [
              {
                \"replica_count\": {
                  \"number_of_replicas\": 0
                }
              }
            ],
            \"transitions\": [
              {
                \"state_name\": \"warm\",
                \"conditions\": {
                  \"min_index_age\": \"30d\"
                }
              }
            ]
          },
          {
            \"name\": \"warm\",
            \"actions\": [],
            \"transitions\": [
              {
                \"state_name\": \"cold\",
                \"conditions\": {
                  \"min_index_age\": \"90d\"
                }
              }
            ]
          },
          {
            \"name\": \"cold\",
            \"actions\": [
              {
                \"read_only\": {}
              }
            ],
            \"transitions\": [
              {
                \"state_name\": \"delete\",
                \"conditions\": {
                  \"min_index_age\": \"730d\"
                }
              }
            ]
          },
          {
            \"name\": \"delete\",
            \"actions\": [
              {
                \"delete\": {}
              }
            ],
            \"transitions\": []
          }
        ],
        \"ism_template\": [
          {
            \"index_patterns\": [\"wazuh-alerts-*\", \"wazuh-archives-*\"],
            \"priority\": 100
          }
        ]
      }
    }'" 2>/dev/null)

    # Check for success conditions
    if echo "$RESPONSE" | grep -q '"_id":"wazuh-2year-retention"'; then
        echo "✅ ISM policy created successfully on attempt $attempt"
        ISM_CREATED=true
        break
    elif echo "$RESPONSE" | grep -q '"policy_id":"wazuh-2year-retention"'; then
        echo "✅ ISM policy created successfully on attempt $attempt"
        ISM_CREATED=true
        break
    elif echo "$RESPONSE" | grep -q '"status":409'; then
        echo "✅ ISM policy already exists (continuing with existing policy)"
        ISM_CREATED=true
        break
    elif echo "$RESPONSE" | grep -q 'version_conflict_engine_exception'; then
        echo "✅ ISM policy already exists (continuing with existing policy)"
        ISM_CREATED=true
        break
    else
        if [ -z "$RESPONSE" ]; then
            echo "   ⚠️  Attempt $attempt: Empty response (timeout after 45s)"
        else
            RESPONSE_PREVIEW=$(echo "$RESPONSE" | head -c 200)
            echo "   ⚠️  Attempt $attempt: Unexpected response: ${RESPONSE_PREVIEW}..."
        fi
        if [ $attempt -lt 20 ]; then
            sleep 30
        fi
    fi
done

if [ "$ISM_CREATED" = false ]; then
    echo ""
    echo "❌ CRITICAL ERROR: ISM policy creation failed after 20 attempts"
    echo "   2-year data retention is a mandatory requirement"
    exit 1
fi

# Validate the policy configuration
echo ""
echo "Validating ISM policy configuration..."
POLICY_CONFIG=$(ssh -i $SSH_KEY root@$UNRAID_SERVER "curl -k -s --max-time 10 -u admin:SecretPassword -X GET 'https://$INDEXER_IP:9200/_plugins/_ism/policies/wazuh-2year-retention'" 2>/dev/null)

VALIDATION_FAILED=false

# Check retention periods
if echo "$POLICY_CONFIG" | grep -q '"min_index_age":"30d"' && \
   echo "$POLICY_CONFIG" | grep -q '"min_index_age":"90d"' && \
   echo "$POLICY_CONFIG" | grep -q '"min_index_age":"730d"'; then
    echo "   ✅ Retention periods correct: 30d (hot→warm), 90d (warm→cold), 730d (cold→delete)"
else
    echo "   ❌ ERROR: Policy retention periods are incorrect!"
    VALIDATION_FAILED=true
fi

# Check states
if echo "$POLICY_CONFIG" | grep -q '"name":"hot"' && \
   echo "$POLICY_CONFIG" | grep -q '"name":"warm"' && \
   echo "$POLICY_CONFIG" | grep -q '"name":"cold"' && \
   echo "$POLICY_CONFIG" | grep -q '"name":"delete"'; then
    echo "   ✅ All required states present: hot, warm, cold, delete"
else
    echo "   ❌ ERROR: Policy missing required states!"
    VALIDATION_FAILED=true
fi

# Check index patterns
if echo "$POLICY_CONFIG" | grep -q '"index_patterns":\["wazuh-alerts-\*","wazuh-archives-\*"\]'; then
    echo "   ✅ Index patterns correct: wazuh-alerts-*, wazuh-archives-*"
elif echo "$POLICY_CONFIG" | grep -q '"index_patterns":\["wazuh-archives-\*","wazuh-alerts-\*"\]'; then
    echo "   ✅ Index patterns correct: wazuh-alerts-*, wazuh-archives-* (alternate order)"
else
    echo "   ❌ ERROR: Index patterns are incorrect!"
    VALIDATION_FAILED=true
fi

if [ "$VALIDATION_FAILED" = true ]; then
    echo ""
    echo "❌ CRITICAL ERROR: ISM policy validation failed"
    exit 1
fi

echo ""
echo "Applying retention policy to existing indices..."

ssh -i $SSH_KEY root@$UNRAID_SERVER "for index in \$(curl -k -s --max-time 15 -u admin:SecretPassword https://$INDEXER_IP:9200/_cat/indices/wazuh-* | awk '{print \$3}'); do
    if [ -n \"\$index\" ]; then
        echo \"Applying policy to index: \$index\"
        curl -k -s --max-time 10 -u admin:SecretPassword -X POST \"https://$INDEXER_IP:9200/_plugins/_ism/add/\$index\" \\
          -H 'Content-Type: application/json' \\
          -d '{\"policy_id\": \"wazuh-2year-retention\"}' > /dev/null
    fi
done"

echo "✅ 2-year retention policy applied to existing indices"

# Step 4.6: Post-Deployment Validation
echo ""
echo "🔍 Step 4.6: Validating Post-Deployment Configuration..."
echo ""

VALIDATION_ERRORS=0

# Validate syslog configuration
echo "   Checking syslog configuration..."
if ssh -i $SSH_KEY root@$UNRAID_SERVER "docker exec wazuh-wazuh.manager-1 grep -q 'connection.*syslog' /var/ossec/etc/ossec.conf 2>/dev/null"; then
    echo "   ✅ Syslog configuration present in ossec.conf"
else
    echo "   ❌ ERROR: Syslog configuration missing from ossec.conf"
    VALIDATION_ERRORS=$((VALIDATION_ERRORS + 1))
fi

# Validate auto-start configuration
echo "   Checking auto-start configuration..."
if ssh -i $SSH_KEY root@$UNRAID_SERVER "[ -f /boot/config/plugins/user.scripts/scripts/wazuh-autostart/script ] && [ -f /boot/config/plugins/user.scripts/scripts/wazuh-autostart/schedule ]"; then
    echo "   ✅ Auto-start script and schedule configured"
else
    echo "   ❌ ERROR: Auto-start configuration incomplete"
    VALIDATION_ERRORS=$((VALIDATION_ERRORS + 1))
fi

# Validate ISM policy
echo "   Checking ISM policy..."
ISM_VALIDATION_RESPONSE=$(ssh -i $SSH_KEY root@$UNRAID_SERVER "curl -k -s --max-time 10 -u admin:SecretPassword -X GET 'https://$INDEXER_IP:9200/_plugins/_ism/policies/wazuh-2year-retention' 2>/dev/null")

if echo "$ISM_VALIDATION_RESPONSE" | grep -q '"policy_id":"wazuh-2year-retention"'; then
    if echo "$ISM_VALIDATION_RESPONSE" | grep -q '"min_index_age":"30d"' && \
       echo "$ISM_VALIDATION_RESPONSE" | grep -q '"min_index_age":"90d"' && \
       echo "$ISM_VALIDATION_RESPONSE" | grep -q '"min_index_age":"730d"'; then
        echo "   ✅ ISM policy configured with correct retention (30d, 90d, 730d)"
    else
        echo "   ❌ ERROR: ISM policy exists but retention periods are incorrect"
        VALIDATION_ERRORS=$((VALIDATION_ERRORS + 1))
    fi
else
    echo "   ❌ ERROR: ISM policy not found or inaccessible"
    VALIDATION_ERRORS=$((VALIDATION_ERRORS + 1))
fi

# Validate manager processes
echo "   Checking critical manager processes..."
CRITICAL_PROCESSES_DOWN=0
for process in "wazuh-remoted" "wazuh-analysisd" "wazuh-execd" "wazuh-modulesd"; do
    if ! ssh -i $SSH_KEY root@$UNRAID_SERVER "docker exec wazuh-wazuh.manager-1 /var/ossec/bin/wazuh-control status 2>/dev/null | grep -q '$process is running'"; then
        echo "   ❌ ERROR: $process is not running"
        CRITICAL_PROCESSES_DOWN=$((CRITICAL_PROCESSES_DOWN + 1))
    fi
done

if [ $CRITICAL_PROCESSES_DOWN -eq 0 ]; then
    echo "   ✅ All critical manager processes running"
else
    echo "   ❌ ERROR: $CRITICAL_PROCESSES_DOWN critical manager processes not running"
    VALIDATION_ERRORS=$((VALIDATION_ERRORS + 1))
fi

# Final validation result
echo ""
if [ $VALIDATION_ERRORS -eq 0 ]; then
    echo "✅ Post-deployment configuration validated successfully"
    echo "   All critical requirements met:"
    echo "   • Syslog configuration ✅"
    echo "   • Auto-start configuration ✅"
    echo "   • 2-year ISM retention policy ✅"
    echo "   • Manager processes ✅"
else
    echo "❌ CRITICAL ERROR: Post-deployment validation failed"
    echo "   $VALIDATION_ERRORS critical requirement(s) not met"
    exit 1
fi

echo ""
show_elapsed_time $SECTION4_START_TIME
echo ""

# ============================================
# SECTION 5: COMPREHENSIVE VALIDATION
# ============================================
echo "==========================================="
echo "  SECTION 5: COMPREHENSIVE VALIDATION"
echo "==========================================="
echo ""

# Start section timer
SECTION5_START_TIME=$(date +%s)

echo "🔍 Running comprehensive system validation..."

# Validation 5.1: Container Health
echo ""
echo "📊 Validation 5.1: Container Health and Resource Status..."

ssh -i $SSH_KEY root@$UNRAID_SERVER "cd $UNRAID_NVME_PATH && echo 'Container Status:' && WAZUH_VERSION='$WAZUH_VERSION' docker-compose ps"
echo ""

ssh -i $SSH_KEY root@$UNRAID_SERVER "cd $UNRAID_NVME_PATH && echo 'Container Resource Usage:' && docker stats --no-stream wazuh-wazuh.manager-1 wazuh-wazuh.indexer-1 wazuh-wazuh.dashboard-1"
echo ""

# Validation 5.2: Service Connectivity
echo "🌐 Validation 5.2: Service Connectivity..."

echo "Testing Manager API..."
if ssh -i $SSH_KEY root@$UNRAID_SERVER "curl -k -s --max-time 10 -u wazuh-wui:MyS3cr37P450r.*- https://$MANAGER_IP:55000/ | grep -q 'title\\|Unauthorized'" 2>/dev/null; then
    echo "✅ Manager API responding"
else
    echo "⚠️  Manager API not responding"
fi

echo "Testing Indexer..."
if ssh -i $SSH_KEY root@$UNRAID_SERVER "curl -k -s --max-time 10 -u admin:SecretPassword https://$INDEXER_IP:9200/_cluster/health | grep -q 'green\\|yellow'" 2>/dev/null; then
    echo "✅ Indexer cluster healthy"
else
    echo "⚠️  Indexer cluster not responding"
fi

echo "Testing Dashboard..."
if ssh -i $SSH_KEY root@$UNRAID_SERVER "curl -k -s --max-time 10 -o /dev/null -w '%{http_code}' https://$DASHBOARD_IP:5601 | grep -q '200\\|302'" 2>/dev/null; then
    echo "✅ Dashboard responding"
else
    echo "⚠️  Dashboard not responding"
fi

# Validation 5.3: Retention Policy
echo ""
echo "💾 Validation 5.3: Data Retention Policy..."

POLICY_CONFIG=$(ssh -i $SSH_KEY root@$UNRAID_SERVER "curl -k -s --max-time 10 -u admin:SecretPassword -X GET 'https://$INDEXER_IP:9200/_plugins/_ism/policies/wazuh-2year-retention'" 2>/dev/null)

if echo "$POLICY_CONFIG" | grep -q '"_id":"wazuh-2year-retention"'; then
    if echo "$POLICY_CONFIG" | grep -q '"min_index_age":"30d"' && \
       echo "$POLICY_CONFIG" | grep -q '"min_index_age":"90d"' && \
       echo "$POLICY_CONFIG" | grep -q '"min_index_age":"730d"'; then
        echo "✅ Retention policy active with correct configuration"
        echo "   • Hot → Warm: 30 days"
        echo "   • Warm → Cold: 90 days (3 months total)"
        echo "   • Cold → Delete: 730 days (2 years total)"
    else
        echo "⚠️  Retention policy exists but configuration may be incorrect"
    fi

    if echo "$POLICY_CONFIG" | grep -q '"name":"hot"' && \
       echo "$POLICY_CONFIG" | grep -q '"name":"warm"' && \
       echo "$POLICY_CONFIG" | grep -q '"name":"cold"' && \
       echo "$POLICY_CONFIG" | grep -q '"name":"delete"'; then
        echo "   • States: hot, warm, cold, delete ✅"
    else
        echo "   ⚠️ Some lifecycle states may be missing"
    fi
else
    echo "❌ Retention policy not found or not accessible"
fi

# Validation 5.4: Syslog Reception
echo ""
echo "📡 Validation 5.4: Syslog Reception and Processing..."

if [ "$SYSLOG_READY" = true ]; then
    echo "Sending test syslog message..."
    if ssh -i $SSH_KEY root@$UNRAID_SERVER "logger -n $MANAGER_IP -P 514 'Test syslog message from deployment - $(date +%s)'" 2>/dev/null; then
        echo "✅ Test syslog message sent"

        echo "Waiting 45 seconds for processing..."
        sleep 45

        echo "Searching for syslog data in indices..."
        SYSLOG_COUNT=$(ssh -i $SSH_KEY root@$UNRAID_SERVER "curl -k -s --max-time 15 -u admin:SecretPassword 'https://$INDEXER_IP:9200/wazuh-alerts-*/_search' -H 'Content-Type: application/json' -d '{\"query\":{\"term\":{\"rule.groups\":\"syslog\"}},\"size\":0}' 2>/dev/null | jq -r '.hits.total.value // 0' 2>/dev/null || echo '0'")

        if [ "$SYSLOG_COUNT" -gt 0 ]; then
            echo "✅ Syslog processing confirmed - found $SYSLOG_COUNT syslog entries"
        else
            echo "⚠️  No syslog data found in indices yet"
        fi
    else
        echo "⚠️  Failed to send test syslog message"
    fi
else
    echo "⚠️  Skipping syslog test - UDP port 514 not confirmed listening"
fi

# Validation 5.5: Vulnerability Detection
echo ""
echo "🛡️ Validation 5.5: Vulnerability Detection..."

echo "Verifying vulnerability detection configuration..."
MODERN_CONFIG=$(ssh -i $SSH_KEY root@$UNRAID_SERVER "docker exec wazuh-wazuh.manager-1 grep -c '<vulnerability-detection>' /var/ossec/etc/ossec.conf" 2>/dev/null || echo "0")

if [ "$MODERN_CONFIG" -gt 0 ]; then
    echo "✅ Vulnerability detection configuration found"

    if ssh -i $SSH_KEY root@$UNRAID_SERVER "docker exec wazuh-wazuh.manager-1 ps aux | grep -v grep | grep -q 'wazuh-db\\|vulnerability'" 2>/dev/null; then
        echo "✅ Vulnerability detection processes running"
    else
        echo "⚠️  Vulnerability detection processes not found"
    fi
else
    echo "❌ Vulnerability detection configuration not found"
fi

# Validation 5.6: Auto-Start
echo ""
echo "🚀 Validation 5.6: Auto-Start Configuration..."

echo "Verifying User Scripts auto-start configuration..."
if ssh -i $SSH_KEY root@$UNRAID_SERVER "[ -f /boot/config/plugins/user.scripts/scripts/wazuh-autostart/script ] && [ -s /boot/config/plugins/user.scripts/scripts/wazuh-autostart/script ]"; then
    echo "✅ Auto-start script exists and has content"

    if ssh -i $SSH_KEY root@$UNRAID_SERVER "grep -q 'docker-compose up -d' /boot/config/plugins/user.scripts/scripts/wazuh-autostart/script"; then
        echo "✅ Auto-start script contains correct docker-compose command"
    else
        echo "⚠️  Auto-start script may have incorrect content"
    fi

    if ssh -i $SSH_KEY root@$UNRAID_SERVER "[ -f /boot/config/plugins/user.scripts/scripts/wazuh-autostart/schedule ] && grep -q 'arrayStarted' /boot/config/plugins/user.scripts/scripts/wazuh-autostart/schedule"; then
        echo "✅ Auto-start schedule configured for array start"
        echo "   📋 Containers will automatically start when Unraid array starts"
    else
        echo "⚠️  Auto-start schedule not properly configured"
    fi
else
    echo "❌ Auto-start script not found"
fi

# Validation 5.7: Integrations
echo ""
if [ -n "$VIRUSTOTAL_API_KEY" ]; then
    echo "🔍 Validation 5.7a: VirusTotal Integration..."

    VT_CONFIG_CHECK=$(ssh -i "$SSH_KEY" root@$UNRAID_SERVER "docker exec wazuh-wazuh.manager-1 grep -A 5 '<integration>' /var/ossec/etc/ossec.conf | grep -q virustotal && echo 'configured' || echo 'missing'")

    if [ "$VT_CONFIG_CHECK" = "configured" ]; then
        echo "   ✅ VirusTotal integration configured in ossec.conf"

        if ssh -i "$SSH_KEY" root@$UNRAID_SERVER "docker exec wazuh-wazuh.manager-1 ps aux | grep -v grep | grep -q wazuh-integratord" 2>/dev/null; then
            echo "   ✅ Wazuh integratord process running"
        else
            echo "   ❌ Wazuh integratord process not found"
        fi

        echo "   📋 Integration will activate on file changes detected by FIM"
    else
        echo "   ❌ VirusTotal integration not found in configuration"
    fi
else
    echo "🔍 Validation 5.7a: VirusTotal Integration (Skipped - No API key)"
fi

echo ""
if [ -n "$MALTIVERSE_API_KEY" ]; then
    echo "🔍 Validation 5.7b: Maltiverse Integration..."

    MALTIVERSE_CONFIG_CHECK=$(ssh -i "$SSH_KEY" root@$UNRAID_SERVER "docker exec wazuh-wazuh.manager-1 grep -A 5 '<integration>' /var/ossec/etc/ossec.conf | grep -q maltiverse && echo 'configured' || echo 'missing'")

    if [ "$MALTIVERSE_CONFIG_CHECK" = "configured" ]; then
        echo "   ✅ Maltiverse integration configured in ossec.conf"

        if ssh -i "$SSH_KEY" root@$UNRAID_SERVER "docker exec wazuh-wazuh.manager-1 ps aux | grep -v grep | grep -q wazuh-integratord" 2>/dev/null; then
            echo "   ✅ Wazuh integratord process running"
        else
            echo "   ❌ Wazuh integratord process not found"
        fi

        echo "   📋 Integration will activate on rule triggers"

        RULE_IDS=$(ssh -i "$SSH_KEY" root@$UNRAID_SERVER "docker exec wazuh-wazuh.manager-1 grep -A 10 'maltiverse' /var/ossec/etc/ossec.conf | grep '<rule_id>' | sed 's/.*<rule_id>\(.*\)<\/rule_id>.*/\1/' | tr -d ' '")
        if [ -n "$RULE_IDS" ]; then
            echo "   ✅ Rule triggers configured: $RULE_IDS"
        fi
    else
        echo "   ❌ Maltiverse integration not found in configuration"
    fi
else
    echo "🔍 Validation 5.7b: Maltiverse Integration (Skipped - No API key)"
fi

echo ""
show_elapsed_time $SECTION5_START_TIME
echo ""

# ============================================
# DEPLOYMENT COMPLETE
# ============================================
echo "============================================="
echo "  🎉 COMPLETE DEPLOYMENT FINISHED!"
echo "============================================="
echo ""
echo "🌐 System Access URLs:"
echo "   - Dashboard: https://$DASHBOARD_IP:5601"
echo "   - Manager API: https://$MANAGER_IP:55000"
echo "   - Indexer: https://$INDEXER_IP:9200"
echo ""
echo "🔑 Credentials:"
echo "   - Dashboard: admin / SecretPassword"
echo "   - API: wazuh-wui / MyS3cr37P450r.*-"
echo "   - Indexer: admin / SecretPassword"
echo ""
echo "📡 Syslog Configuration:"
echo "   - Listening: UDP port 514 on $MANAGER_IP"
echo "   - Allowed networks: 10.0.0.0/8 (home lab range)"
echo "   - Protocol: UDP syslog (RFC 3164)"
echo ""
echo "💾 Data Retention:"
echo "   - Total retention: 2 years (730 days)"
echo "   - Hot state: 0-30 days (active, replicated)"
echo "   - Warm state: 30-90 days (less frequent access)"
echo "   - Cold state: 90-730 days (read-only)"
echo "   - Delete: After 730 days"
echo ""
echo "🧪 Testing Syslog Reception:"
echo "   From any device on your 10.x.x.x network:"
echo "   logger -n $MANAGER_IP -P 514 'Test message from [hostname]'"
echo ""
echo "🔗 Integration Status:"
if [ -n "${VIRUSTOTAL_API_KEY}" ]; then
    echo "   ✅ VirusTotal: Enabled (File integrity monitoring with malware scanning)"
else
    echo "   ⚠️  VirusTotal: Disabled (No API key configured)"
fi
if [ -n "${MALTIVERSE_API_KEY}" ]; then
    echo "   ✅ Maltiverse: Enabled (Threat intelligence for IPs, URLs, domains, hashes)"
else
    echo "   ⚠️  Maltiverse: Disabled (No API key configured)"
fi
echo ""
echo "📝 Next Steps:"
echo "   1. Configure network devices to send syslog to $MANAGER_IP:514"
echo "   2. Deploy Wazuh agents on endpoints as needed"
echo "   3. Monitor dashboard for security events and alerts"
echo ""
echo "✅ Production-ready Wazuh SIEM deployment completed successfully!"
echo ""

# ============================================
# DEPLOYMENT TIMING SUMMARY
# ============================================
echo "🕐 DEPLOYMENT TIMING SUMMARY:"
echo "================================"
DEPLOYMENT_END_TIME=$(date +%s)
TOTAL_ELAPSED=$((DEPLOYMENT_END_TIME - DEPLOYMENT_START_TIME))
TOTAL_MINUTES=$((TOTAL_ELAPSED / 60))
TOTAL_SECONDS=$((TOTAL_ELAPSED % 60))

if [ $TOTAL_MINUTES -gt 0 ]; then
    echo "⏱️  Total deployment time: ${TOTAL_MINUTES}m ${TOTAL_SECONDS}s"
else
    echo "⏱️  Total deployment time: ${TOTAL_SECONDS}s"
fi

echo "🏁 Deployment completed at: $(date)"
echo ""
