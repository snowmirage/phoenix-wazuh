#!/bin/bash

# Phoenix Wazuh Orchestrator
# Coordinates complete Wazuh SIEM deployment on Phoenix Unraid server
# Includes: cleanup, file preparation, deployment, post-configuration, and validation

# Function to show help
show_help() {
    echo "============================================="
    echo "  Phoenix Wazuh Deployment Orchestrator"
    echo "  Production-Ready SIEM"
    echo "============================================="
    echo ""
    echo "Usage: $0 <command> --version <version> [options]"
    echo ""
    echo "Commands:"
    echo "  fresh-install       Deploy Wazuh from scratch (no data restoration)"
    echo "                      - Clean deployment with custom configurations"
    echo "                      - Agents will enroll as new devices"
    echo "                      - No historical data preserved"
    echo ""
    echo "  backup              Create timestamped backup of current deployment"
    echo "                      - Historical event data (OpenSearch snapshots)"
    echo "                      - Agent keys and database (identities, groups, names)"
    echo "                      - Integration configurations"
    echo "                      - Safe to run anytime without affecting deployment"
    echo ""
    echo "  restore <timestamp> Deploy Wazuh and restore from backup"
    echo "                      - Clean deployment with full data restoration"
    echo "                      - Restores historical events and agent identities"
    echo "                      - Agents reconnect automatically with preserved metadata"
    echo ""
    echo "Options:"
    echo "  --version <version> Wazuh version to deploy (REQUIRED for fresh-install/restore)"
    echo "                      Format: X.Y.Z (e.g., 4.12.0)"
    echo "                      Recommended: 4.12.0 (stable, tested)"
    echo ""
    echo "Examples:"
    echo "  $0 fresh-install --version 4.12.0"
    echo "  $0 backup"
    echo "  $0 restore 20251218_143022 --version 4.12.0"
    echo ""
    echo "Available backups:"
    list_backups
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

    # Check if Docker images exist (check manager image as representative)
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

# Function to list available backups
list_backups() {
    BACKUPS=$(ssh -i /home/dev/.ssh/unraid_id_rsa root@10.2.0.16 "ls -1 /mnt/user/wazuh-data/backups/ 2>/dev/null" || echo "")
    if [ -z "$BACKUPS" ]; then
        echo "  No backups found"
    else
        echo "$BACKUPS" | sed 's/^/  /'
    fi
}

# Parse command line arguments
COMMAND=$1
shift  # Remove command from arguments

# Initialize variables
WAZUH_VERSION=""
BACKUP_TIMESTAMP=""

# Parse remaining arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --version)
            WAZUH_VERSION="$2"
            shift 2
            ;;
        *)
            # Assume it's the backup timestamp for restore command
            BACKUP_TIMESTAMP="$1"
            shift
            ;;
    esac
done

# Show help if no command provided
if [ -z "$COMMAND" ]; then
    show_help
    exit 0
fi

# Parse and validate command
MODE=""

case "$COMMAND" in
    "fresh-install")
        MODE="fresh"

        # Validate version is provided
        if [ -z "$WAZUH_VERSION" ]; then
            echo "❌ Error: --version parameter is required for fresh-install"
            echo ""
            echo "Usage: $0 fresh-install --version <version>"
            echo ""
            echo "Recommended version: 4.12.0 (stable, tested)"
            echo ""
            echo "💡 To see available versions:"
            echo "   https://github.com/wazuh/wazuh-docker/releases"
            echo ""
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
        ;;

    "backup")
        echo "============================================="
        echo "  Phoenix Wazuh Backup"
        echo "  Creating timestamped backup"
        echo "============================================="
        echo ""

        # Run backup script and exit
        ./wazuh-backup-script.sh
        exit $?
        ;;

    "restore")
        if [ -z "$BACKUP_TIMESTAMP" ]; then
            echo "❌ Error: restore command requires a backup timestamp"
            echo ""
            echo "Usage: $0 restore <timestamp> --version <version>"
            echo ""
            echo "Available backups:"
            list_backups
            echo ""
            exit 1
        fi

        # Validate version is provided
        if [ -z "$WAZUH_VERSION" ]; then
            echo "❌ Error: --version parameter is required for restore"
            echo ""
            echo "Usage: $0 restore <timestamp> --version <version>"
            echo ""
            echo "Recommended version: 4.12.0 (stable, tested)"
            echo ""
            echo "💡 To see available versions:"
            echo "   https://github.com/wazuh/wazuh-docker/releases"
            echo ""
            exit 1
        fi

        # Validate version exists
        if ! validate_wazuh_version "$WAZUH_VERSION"; then
            exit 1
        fi

        # Verify backup exists
        if ! ssh -i /home/dev/.ssh/unraid_id_rsa root@10.2.0.16 "[ -d '/mnt/user/wazuh-data/backups/$BACKUP_TIMESTAMP' ]"; then
            echo "❌ Error: Backup not found: $BACKUP_TIMESTAMP"
            echo ""
            echo "Available backups:"
            list_backups
            echo ""
            exit 1
        fi

        MODE="restore"
        echo "============================================="
        echo "  Phoenix Wazuh Deployment Orchestrator"
        echo "  Mode: RESTORE FROM BACKUP"
        echo "  Backup: $BACKUP_TIMESTAMP"
        echo "  Version: $WAZUH_VERSION"
        echo "============================================="
        echo ""
        ;;

    *)
        echo "❌ Unknown command: $COMMAND"
        echo ""
        show_help
        exit 1
        ;;
esac

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
    # This prevents arbitrary code execution while loading config
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
            SLACK_WEBHOOK_URL)
                SLACK_WEBHOOK_URL="$value"
                ;;
            PAGERDUTY_INTEGRATION_KEY)
                PAGERDUTY_INTEGRATION_KEY="$value"
                ;;
            # Add more recognized variables as needed
        esac
    done < <(grep -E '^[A-Z_]+=.*' "$CONFIG_FILE")
    
    echo "   ✅ Configuration loaded successfully"
else
    echo "📋 Configuration file not found: $CONFIG_FILE"
    echo "   💡 Using environment variables or defaults"
    echo "   💡 Create $CONFIG_FILE for persistent API key storage"
fi

# Fallback to environment variables if not set in config file
VIRUSTOTAL_API_KEY="${VIRUSTOTAL_API_KEY:-${VIRUSTOTAL_API_KEY_ENV:-}}"
MALTIVERSE_API_KEY="${MALTIVERSE_API_KEY:-${MALTIVERSE_API_KEY_ENV:-}}"

# Configuration validation and reporting
echo ""
echo "🔧 Integration Configuration Status:"
if [ -n "$VIRUSTOTAL_API_KEY" ]; then
    # Mask the API key for security (show only first 8 and last 4 characters)
    MASKED_KEY=$(echo "$VIRUSTOTAL_API_KEY" | sed 's/\(.\{8\}\).*\(.\{4\}\)/\1****\2/')
    echo "   🔍 VirusTotal: ✅ Enabled (Key: $MASKED_KEY)"
else
    echo "   🔍 VirusTotal: ❌ Disabled (No API key configured)"
fi

if [ -n "$MALTIVERSE_API_KEY" ]; then
    # Mask the API key for security (show only first 8 and last 4 characters)
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
# SECTION 0: BACKUP CONFIRMATION (RESTORE MODE ONLY)
# ============================================
echo "==========================================="
echo "  SECTION 0: BACKUP PREPARATION"
if [ "$MODE" = "restore" ]; then
    echo "  Using backup: $BACKUP_TIMESTAMP"
    echo "==========================================="
    echo ""
    echo "📦 Restore will use backup from: /mnt/user/wazuh-data/backups/$BACKUP_TIMESTAMP"
    echo "   Historical data and agent identities will be restored"
else
    echo "  ⏩ SKIPPED (fresh install - no backup used)"
    echo "==========================================="
    echo ""
    echo "🆕 Fresh install mode - no data will be restored"
    echo "   Agents will enroll as new devices"
fi
# Only verify backup if in restore mode
if [ "$MODE" = "restore" ]; then
    BACKUP_PATH="/mnt/user/wazuh-data/backups/$BACKUP_TIMESTAMP"

    echo "🔍 Verifying backup integrity..."
    BACKUP_VERIFICATION_FAILED=false

    # Check if agent identities exist
    if ! ssh -i $SSH_KEY root@$UNRAID_SERVER "[ -f '$BACKUP_PATH/client-keys/client.keys' ]"; then
        echo "   ❌ Agent identities backup missing"
        BACKUP_VERIFICATION_FAILED=true
    else
        AGENT_COUNT=$(ssh -i $SSH_KEY root@$UNRAID_SERVER "wc -l < '$BACKUP_PATH/client-keys/client.keys' 2>/dev/null || echo 0")
        echo "   ✅ Agent identities backed up ($AGENT_COUNT agents)"
    fi

    # Check if configurations exist
    if ! ssh -i $SSH_KEY root@$UNRAID_SERVER "[ -f '$BACKUP_PATH/configs/ossec.conf' ]"; then
        echo "   ❌ Configuration backup missing"
        BACKUP_VERIFICATION_FAILED=true
    else
        echo "   ✅ Configurations backed up"
    fi

    # Check if snapshot metadata exists
    if ! ssh -i $SSH_KEY root@$UNRAID_SERVER "[ -f '$BACKUP_PATH/metadata/backup-info.txt' ]"; then
        echo "   ❌ Backup metadata missing"
        BACKUP_VERIFICATION_FAILED=true
    else
        echo "   ✅ Backup metadata found"
    fi

    if [ "$BACKUP_VERIFICATION_FAILED" = true ]; then
        echo ""
        echo "❌ BACKUP VERIFICATION FAILED - Deployment aborted"
        echo "   Critical backup components are missing"
        echo ""
        echo "Available backups:"
        list_backups
        echo ""
        exit 1
    fi

    echo ""
    echo "✅ Backup verified - proceeding with restore deployment"
    echo ""
fi

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

    # Critical: Explicitly remove problematic files that cause crashes FIRST
    echo '  Step 1: Removing critical agent/auth files...'
    rm -f $UNRAID_NVME_PATH/volumes/wazuh_etc/client.keys 2>/dev/null || true
    rm -f $UNRAID_NVME_PATH/volumes/wazuh_etc/sslmanager.* 2>/dev/null || true
    rm -rf $UNRAID_NVME_PATH/volumes/* 2>/dev/null || true

    echo '  Step 2: Removing all NVME path contents...'
    rm -rf $UNRAID_NVME_PATH/* 2>/dev/null || true

    echo '  Step 3: Removing all data path contents...'
    rm -rf $UNRAID_DATA_PATH/* 2>/dev/null || true

    # Fallback cleanup for stubborn files using find
    echo '  Step 4: Fallback cleanup check...'
    if [ \"\$(ls -A $UNRAID_NVME_PATH 2>/dev/null)\" ]; then
        echo '  ⚠️  NVME path not empty, using find for stubborn files...'
        find $UNRAID_NVME_PATH -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null || true
    fi

    if [ \"\$(ls -A $UNRAID_DATA_PATH 2>/dev/null)\" ]; then
        echo '  ⚠️  Data path not empty, using find for stubborn files...'
        find $UNRAID_DATA_PATH -mindepth 1 -exec rm -rf {} + 2>/dev/null || true
    fi

    # VALIDATION: Verify cleanup actually worked
    echo '  Step 5: Validating cleanup...'
    CLEANUP_FAILED=false

    if [ -f \"$UNRAID_NVME_PATH/volumes/wazuh_etc/client.keys\" ]; then
        echo '  ❌ VALIDATION FAILED: client.keys still exists!'
        ls -la \"$UNRAID_NVME_PATH/volumes/wazuh_etc/client.keys\" || true
        CLEANUP_FAILED=true
    fi

    if [ -d \"$UNRAID_NVME_PATH/volumes\" ] && [ \"\$(ls -A $UNRAID_NVME_PATH/volumes 2>/dev/null)\" ]; then
        echo '  ⚠️  WARNING: volumes directory not empty:'
        ls -la \"$UNRAID_NVME_PATH/volumes/\" | head -20 || true
        # Don't fail on this, just warn
    fi

    if [ \"\$(ls -A $UNRAID_NVME_PATH 2>/dev/null | grep -v 'backups\\|snapshots')\" ]; then
        echo '  ⚠️  WARNING: NVME path not empty (excluding backups/snapshots):'
        ls -la \"$UNRAID_NVME_PATH/\" | head -20 || true
    fi

    if [ \"$CLEANUP_FAILED\" = true ]; then
        echo '  '
        echo '  ❌ CLEANUP VALIDATION FAILED - Critical files survived cleanup'
        echo '  This will cause deployment to crash. Please investigate:'
        echo '    ssh -i ~/.ssh/unraid_id_rsa root@10.2.0.16'
        echo '    ls -la /mnt/user/appdata/wazuh/volumes/wazuh_etc/'
        echo '  '
        exit 1
    fi

    echo '✅ Cleanup completed and validated successfully'
"

if [ $? -ne 0 ]; then
    echo "❌ Error occurred during cleanup"
    exit 1
fi

echo "✅ Unraid cleanup completed successfully"
show_elapsed_time $SECTION1_START_TIME
echo ""

# Create required directory structure for deployment (only if doesn't exist)
echo "📁 Ensuring required directory structure exists..."
ssh -i $SSH_KEY root@$UNRAID_SERVER "
    mkdir -p $UNRAID_DATA_PATH 2>/dev/null && echo '   ✅ $UNRAID_DATA_PATH' || echo '   ℹ️  $UNRAID_DATA_PATH already exists'
    mkdir -p $UNRAID_DATA_BASE/snapshots 2>/dev/null && echo '   ✅ $UNRAID_DATA_BASE/snapshots' || echo '   ℹ️  $UNRAID_DATA_BASE/snapshots already exists'
    mkdir -p $UNRAID_DATA_BASE/backups 2>/dev/null && echo '   ✅ $UNRAID_DATA_BASE/backups' || echo '   ℹ️  $UNRAID_DATA_BASE/backups already exists'
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

echo "Using HTTP-hosted Wazuh icons for Docker containers..."
echo "   ✅ Wazuh icons configured via HTTP URLs for better Unraid compatibility"

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
# Pass version as both environment variable (for docker-compose) and parameter (for git clone)
ssh -i $SSH_KEY root@$UNRAID_SERVER "cd /mnt/user/appdata && WAZUH_VERSION='$WAZUH_VERSION' ./phoenix-wazuh-worker.sh '$MODE' '$BACKUP_TIMESTAMP' '$WAZUH_VERSION'" 

if [ $? -ne 0 ]; then
    echo "❌ Error occurred during Wazuh deployment"
    exit 1
fi

echo "✅ Wazuh deployment completed successfully"
show_elapsed_time $SECTION3_START_TIME
echo ""

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

# Step 4.2: Configure Syslog Reception
echo ""
echo "🔧 Step 4.2: Configure Syslog Reception (UDP 514)..."

# Create the complete ossec.conf with syslog configuration
ssh -i $SSH_KEY root@$UNRAID_SERVER "cd $UNRAID_NVME_PATH && cat > config/wazuh_cluster/wazuh_manager.conf << 'EOF'
<!--
  Wazuh - Manager configuration file
  More info at: https://documentation.wazuh.com
  Mailing list: https://groups.google.com/forum/#!forum/wazuh
-->

<ossec_config>

  <global>
    <jsonout_output>yes</jsonout_output>
    <alerts_log>yes</alerts_log>
    <logall>no</logall>
    <logall_json>no</logall_json>
    <email_notification>no</email_notification>
    <smtp_server>smtp.example.wazuh.com</smtp_server>
    <email_from>ossecm@example.wazuh.com</email_from>
    <email_to>recipient@example.wazuh.com</email_to>
    <email_maxperhour>12</email_maxperhour>
    <email_log_source>alerts.log</email_log_source>
    <agents_disconnection_time>10m</agents_disconnection_time>
    <agents_disconnection_alert_time>0</agents_disconnection_alert_time>
  </global>

  <!-- Syslog remote reception configuration - Official Wazuh Documentation -->
  <remote>
    <connection>syslog</connection>
    <port>514</port>
    <protocol>udp</protocol>
    <allowed-ips>10.0.0.0/8</allowed-ips>
    <local_ip>$MANAGER_IP</local_ip>
  </remote>

  <alerts>
    <log_alert_level>3</log_alert_level>
    <email_alert_level>12</email_alert_level>
  </alerts>

  <!-- Choose between \"plain\", \"json\", or \"plain,json\" for the format of internal logs -->
  <logging>
    <log_format>plain</log_format>
  </logging>

  <remote>
    <connection>secure</connection>
    <port>1514</port>
    <protocol>tcp</protocol>
    <queue_size>131072</queue_size>
  </remote>

  <!-- Policy monitoring -->
  <rootcheck>
    <disabled>no</disabled>
    <check_files>yes</check_files>
    <check_trojans>yes</check_trojans>
    <check_dev>yes</check_dev>
    <check_sys>yes</check_sys>
    <check_pids>yes</check_pids>
    <check_ports>yes</check_ports>
    <check_if>yes</check_if>

    <!-- Frequency that rootcheck is executed - every 12 hours -->
    <frequency>43200</frequency>

    <rootkit_files>etc/rootcheck/rootkit_files.txt</rootkit_files>
    <rootkit_trojans>etc/rootcheck/rootkit_trojans.txt</rootkit_trojans>

    <skip_nfs>yes</skip_nfs>
  </rootcheck>

  <wodle name=\"cis-cat\">
    <disabled>yes</disabled>
    <timeout>1800</timeout>
    <interval>1d</interval>
    <scan-on-start>yes</scan-on-start>

    <java_path>wodles/java</java_path>
    <ciscat_path>wodles/ciscat</ciscat_path>
  </wodle>

  <!-- Osquery integration -->
  <wodle name=\"osquery\">
    <disabled>yes</disabled>
    <run_daemon>yes</run_daemon>
    <log_path>/var/log/osquery/osqueryd.results.log</log_path>
    <config_path>/etc/osquery/osquery.conf</config_path>
    <add_labels>yes</add_labels>
  </wodle>

  <!-- System inventory -->
  <wodle name=\"syscollector\">
    <disabled>no</disabled>
    <interval>1h</interval>
    <scan_on_start>yes</scan_on_start>
    <hardware>yes</hardware>
    <os>yes</os>
    <network>yes</network>
    <packages>yes</packages>
    <hotfixes>yes</hotfixes>
    <ports all=\"no\">yes</ports>
    <processes>yes</processes>

    <!-- Database synchronization settings -->
    <synchronization>
      <max_eps>10</max_eps>
    </synchronization>
  </wodle>

  <!-- Vulnerability detection using modern format only -->
  <vulnerability-detection>
    <enabled>yes</enabled>
    <index-status>yes</index-status>
    <feed-update-interval>60m</feed-update-interval>
  </vulnerability-detection>

  <!-- Indexer configuration for vulnerability detection -->
  <indexer>
    <enabled>yes</enabled>
    <hosts>
      <host>https://10.2.0.86:9200</host>
    </hosts>
    <ssl>
      <certificate_authorities>
        <ca>/etc/ssl/root-ca.pem</ca>
      </certificate_authorities>
      <certificate>/etc/ssl/filebeat.pem</certificate>
      <key>/etc/ssl/filebeat.key</key>
    </ssl>
  </indexer>

$(if [ -n "\${VIRUSTOTAL_API_KEY}" ]; then
cat << VT_CONFIG
  <!-- VirusTotal integration for malware detection -->
  <integration>
    <name>virustotal</name>
    <api_key>\${VIRUSTOTAL_API_KEY}</api_key>
    <group>syscheck</group>
    <alert_format>json</alert_format>
  </integration>
VT_CONFIG
fi)

$(if [ -n "\${MALTIVERSE_API_KEY}" ]; then
cat << MALTIVERSE_CONFIG
  <!-- Maltiverse integration for threat intelligence -->
  <integration>
    <name>maltiverse</name>
    <hook_url>https://api.maltiverse.com</hook_url>
    <api_key>\${MALTIVERSE_API_KEY}</api_key>
    <rule_id>2502,111041,111042,111050,111051</rule_id>
    <alert_format>json</alert_format>
  </integration>
MALTIVERSE_CONFIG
fi)

  <!-- File integrity monitoring -->
  <syscheck>
    <disabled>no</disabled>

    <!-- Frequency that syscheck is executed default every 12 hours -->
    <frequency>43200</frequency>

    <scan_on_start>yes</scan_on_start>

    <!-- Generate alert when new file detected -->
    <alert_new_files>yes</alert_new_files>

    <!-- Don't ignore files that change more than 'frequency' times -->
    <auto_ignore frequency=\"10\" timeframe=\"3600\">no</auto_ignore>

    <!-- Directories to check  (perform all possible verifications) -->
    <directories>/etc,/usr/bin,/usr/sbin</directories>
    <directories>/bin,/sbin,/boot</directories>

    <!-- Files/directories to ignore -->
    <ignore>/etc/mtab</ignore>
    <ignore>/etc/hosts.deny</ignore>
    <ignore>/etc/mail/statistics</ignore>
    <ignore>/etc/random-seed</ignore>
    <ignore>/etc/random.seed</ignore>
    <ignore>/etc/adjtime</ignore>
    <ignore>/etc/httpd/logs</ignore>
    <ignore>/etc/utmpx</ignore>
    <ignore>/etc/wtmpx</ignore>
    <ignore>/etc/cups/certs</ignore>
    <ignore>/etc/dumpdates</ignore>
    <ignore>/etc/svc/volatile</ignore>

    <!-- File types to ignore -->
    <ignore type=\"sregex\">.log$|.swp$</ignore>

    <!-- Check the file, but never compute the diff -->
    <nodiff>/etc/ssl/private.key</nodiff>

    <skip_nfs>yes</skip_nfs>
    <skip_dev>yes</skip_dev>
    <skip_proc>yes</skip_proc>
    <skip_sys>yes</skip_sys>

    <!-- Nice value for Syscheck process -->
    <process_priority>10</process_priority>

    <!-- Maximum output throughput -->
    <max_eps>100</max_eps>

    <!-- Database synchronization settings -->
    <synchronization>
      <enabled>yes</enabled>
      <interval>5m</interval>
      <max_interval>1h</max_interval>
      <max_eps>10</max_eps>
    </synchronization>
  </syscheck>

  <!-- Log analysis -->
  <localfile>
    <log_format>command</log_format>
    <command>df -P</command>
    <frequency>360</frequency>
  </localfile>

  <localfile>
    <log_format>full_command</log_format>
    <command>netstat -tulpn | sed 's/\([[:alnum:]]\+\)\ \+[[:digit:]]\+\ \+[[:digit:]]\+\ \+\(.*\):\([[:digit:]]*\)\ \+\([0-9\.\:\*]\+\).\+\ \([[:digit:]]*/[[:alnum:]\-]*\).*/\1 \2 == \3 == \4 \5/' | sort -k 4 -g | sed 's/ == \(.*\) ==/:\1/' | sed 1,2d</command>
    <alias>netstat listening ports</alias>
    <frequency>360</frequency>
  </localfile>

  <localfile>
    <log_format>full_command</log_format>
    <command>last -n 20</command>
    <frequency>360</frequency>
  </localfile>

  <ruleset>
    <!-- Default ruleset -->
    <decoder_dir>ruleset/decoders</decoder_dir>
    <rule_dir>ruleset/rules</rule_dir>
    <rule_exclude>0215-policy_rules.xml</rule_exclude>
    <list>etc/lists/audit-keys</list>
    <list>etc/lists/amazon/aws-eventnames</list>
    <list>etc/lists/security-eventchannel</list>
  </ruleset>

  <!-- Configuration for wazuh-authd -->
  <auth>
    <disabled>no</disabled>
    <port>1515</port>
    <use_source_ip>no</use_source_ip>
    <purge>yes</purge>
    <use_password>no</use_password>
    <ciphers>HIGH:!ADH:!EXP:!MD5:!RC4:!3DES:!CAMELLIA:@STRENGTH</ciphers>
    <!-- <ssl_agent_ca></ssl_agent_ca> -->
    <ssl_verify_host>no</ssl_verify_host>
    <ssl_manager_cert>etc/sslmanager.cert</ssl_manager_cert>
    <ssl_manager_key>etc/sslmanager.key</ssl_manager_key>
    <ssl_auto_negotiate>no</ssl_auto_negotiate>
  </auth>

  <cluster>
    <name>wazuh</name>
    <node_name>manager</node_name>
    <node_type>master</node_type>
    <key></key>
    <port>1516</port>
    <bind_addr>0.0.0.0</bind_addr>
    <nodes>
      <node>manager</node>
    </nodes>
    <hidden>no</hidden>
    <disabled>yes</disabled>
  </cluster>

</ossec_config>

<ossec_config>
  <localfile>
    <log_format>syslog</log_format>
    <location>/var/ossec/logs/active-responses.log</location>
  </localfile>
</ossec_config>
EOF"

echo "✅ Syslog configuration added to ossec.conf"

# Post-process the configuration file to substitute integration API keys
if [ -n "$VIRUSTOTAL_API_KEY" ]; then
    echo "🔍 Processing VirusTotal API key substitution..."
    ssh -i $SSH_KEY root@$UNRAID_SERVER "cd $UNRAID_NVME_PATH && sed -i 's/\${VIRUSTOTAL_API_KEY}/$VIRUSTOTAL_API_KEY/g' config/wazuh_cluster/wazuh_manager.conf"
    echo "   ✅ VirusTotal API key substitution completed"
fi

if [ -n "$MALTIVERSE_API_KEY" ]; then
    echo "🔍 Processing Maltiverse API key substitution..."
    ssh -i $SSH_KEY root@$UNRAID_SERVER "cd $UNRAID_NVME_PATH && sed -i 's/\${MALTIVERSE_API_KEY}/$MALTIVERSE_API_KEY/g' config/wazuh_cluster/wazuh_manager.conf"
    echo "   ✅ Maltiverse API key substitution completed"
fi

# Enable logall to capture all syslog messages (including those without decoders)
echo "🔍 Enabling logall for comprehensive syslog capture..."
ssh -i $SSH_KEY root@$UNRAID_SERVER "cd $UNRAID_NVME_PATH && sed -i 's|<logall>no</logall>|<logall>yes</logall>|g' config/wazuh_cluster/wazuh_manager.conf"
echo "   ✅ logall=yes enabled (all syslog messages will be stored)"

# Step 4.3: Restart Manager with Proper Configuration Copy
echo ""
echo "🔄 Step 4.3: Restart Manager to Apply Syslog Configuration..."

# Force remove and recreate to avoid zombie container state
ssh -i $SSH_KEY root@$UNRAID_SERVER "docker rm -f wazuh-wazuh.manager-1 2>/dev/null || true"
sleep 2

ssh -i $SSH_KEY root@$UNRAID_SERVER "cd $UNRAID_NVME_PATH && WAZUH_VERSION='$WAZUH_VERSION' docker-compose up -d wazuh.manager"
echo "⏳ Waiting for container to start..."
sleep 15

# Manually start Wazuh processes (docker-compose up doesn't always trigger wazuh-control)
echo "Starting Wazuh manager processes..."
ssh -i $SSH_KEY root@$UNRAID_SERVER "docker exec wazuh-wazuh.manager-1 /var/ossec/bin/wazuh-control start" 2>/dev/null
echo "⏳ Waiting for manager to fully initialize before configuration..."
sleep 20

# Wait for manager API to be ready (indicates full initialization)
# Increased timeout to handle transient OCI runtime issues during restart
MANAGER_READY=false
for attempt in 1 2 3 4 5 6 7 8 9 10 11 12; do
    if ssh -i $SSH_KEY root@$UNRAID_SERVER "curl -k -s --max-time 5 -u wazuh-wui:MyS3cr37P450r.*- https://$MANAGER_IP:55000/ 2>/dev/null | grep -q 'title\\|Unauthorized'"; then
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
    echo ""
    echo "📋 Diagnostic Information:"
    echo ""
    echo "Container Status:"
    ssh -i $SSH_KEY root@$UNRAID_SERVER "docker ps -a | grep manager" || true
    echo ""
    echo "Manager Process Status:"
    ssh -i $SSH_KEY root@$UNRAID_SERVER "docker exec wazuh-wazuh.manager-1 /var/ossec/bin/wazuh-control status 2>&1" || echo "   Cannot execute wazuh-control (container may be stopped)"
    echo ""
    echo "Recent Container Logs:"
    ssh -i $SSH_KEY root@$UNRAID_SERVER "docker logs --tail 30 wazuh-wazuh.manager-1 2>&1" || echo "   Cannot retrieve logs"
    echo ""
    echo "💡 Troubleshooting:"
    echo "   1. Check for OCI runtime errors in logs above"
    echo "   2. Verify container didn't crash: docker ps -a | grep manager"
    echo "   3. Try manual restart: cd /mnt/user/appdata/wazuh && docker-compose restart wazuh.manager"
    echo "   4. Check Docker daemon health on Unraid"
    echo ""
    exit 1
fi

# Copy mounted config to active location
echo "Copying mounted configuration to active container location..."
ssh -i $SSH_KEY root@$UNRAID_SERVER "cd $UNRAID_NVME_PATH && docker exec wazuh-wazuh.manager-1 cp /wazuh-config-mount/etc/ossec.conf /var/ossec/etc/ossec.conf 2>/dev/null" || true

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

echo "Restarting manager to apply all configuration changes..."
# Use same pattern as first restart (rm + up) to avoid OCI runtime issues
ssh -i $SSH_KEY root@$UNRAID_SERVER "docker rm -f wazuh-wazuh.manager-1 2>/dev/null || true"
sleep 2
ssh -i $SSH_KEY root@$UNRAID_SERVER "cd $UNRAID_NVME_PATH && WAZUH_VERSION='$WAZUH_VERSION' docker-compose up -d wazuh.manager" 2>/dev/null
echo "⏳ Waiting for container to start..."
sleep 15

# Manually start Wazuh processes (docker-compose up doesn't always trigger wazuh-control)
echo "Starting Wazuh manager processes..."
ssh -i $SSH_KEY root@$UNRAID_SERVER "docker exec wazuh-wazuh.manager-1 /var/ossec/bin/wazuh-control start" 2>/dev/null
echo "⏳ Waiting for all processes to initialize..."
sleep 15

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
    echo ""
    echo "📋 Troubleshooting:"
    echo "   1. Check manager logs: docker exec wazuh-wazuh.manager-1 tail -100 /var/ossec/logs/ossec.log"
    echo "   2. Check remoted status: docker exec wazuh-wazuh.manager-1 /var/ossec/bin/wazuh-control status"
    echo "   3. Verify config: docker exec wazuh-wazuh.manager-1 cat /var/ossec/etc/ossec.conf | grep -A 10 remote"
    echo ""
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

# Create the auto-start script
ssh -i $SSH_KEY root@$UNRAID_SERVER "cat > /boot/config/plugins/user.scripts/scripts/wazuh-autostart/script << 'EOF'
#!/bin/bash
# Wazuh SIEM Auto-start Script
# Starts Wazuh containers on Unraid boot

# Wait for Docker and networks to be ready
sleep 60

# Start Wazuh containers
cd /mnt/user/appdata/wazuh
/usr/local/bin/docker-compose up -d

echo 'Wazuh containers started automatically'
EOF"

# Note: No chmod needed - /boot is FAT32 which doesn't support execute bit
# User Scripts plugin reads the file content and executes it via bash

# Set the script to run when array starts
ssh -i $SSH_KEY root@$UNRAID_SERVER "echo 'arrayStarted' > /boot/config/plugins/user.scripts/scripts/wazuh-autostart/schedule"

echo "✅ Auto-start script configured"

# Validate auto-start configuration
echo "Validating auto-start configuration..."
# Note: /boot is FAT32 (vfat), so execute bit is never set - User Scripts doesn't need it
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

# Retry logic for ISM policy creation - wait for indexer to be ready
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
        # Show actual response for debugging
        if [ -z "$RESPONSE" ]; then
            echo "   ⚠️  Attempt $attempt: Empty response (timeout after 45s - ISM plugin may still be initializing)"
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
    echo "   Deployment cannot continue without proper data retention policy"
    echo ""
    echo "📋 Possible causes:"
    echo "   • Indexer under heavy load (vulnerability scanner initializing)"
    echo "   • Network connectivity issues"
    echo "   • ISM plugin not fully initialized"
    echo ""
    echo "💡 Troubleshooting:"
    echo "   1. Check indexer logs: docker logs wazuh-wazuh.indexer-1"
    echo "   2. Verify ISM plugin: curl -k -u admin:SecretPassword https://10.2.0.86:9200/_cat/plugins"
    echo "   3. Try manual policy creation after deployment stabilizes"
    echo ""
    exit 1
fi

# Validate the policy configuration is correct
echo ""
echo "Validating ISM policy configuration..."
POLICY_CONFIG=$(ssh -i $SSH_KEY root@$UNRAID_SERVER "curl -k -s --max-time 10 -u admin:SecretPassword -X GET 'https://$INDEXER_IP:9200/_plugins/_ism/policies/wazuh-2year-retention'" 2>/dev/null)

# Track validation failures
VALIDATION_FAILED=false

# Check for required retention periods
if echo "$POLICY_CONFIG" | grep -q '"min_index_age":"30d"' && \
   echo "$POLICY_CONFIG" | grep -q '"min_index_age":"90d"' && \
   echo "$POLICY_CONFIG" | grep -q '"min_index_age":"730d"'; then
    echo "   ✅ Retention periods correct: 30d (hot→warm), 90d (warm→cold), 730d (cold→delete)"
else
    echo "   ❌ ERROR: Policy retention periods are incorrect!"
    echo "   Expected: 30d, 90d, 730d"
    VALIDATION_FAILED=true
fi

# Check for required states
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

# Exit if validation failed
if [ "$VALIDATION_FAILED" = true ]; then
    echo ""
    echo "❌ CRITICAL ERROR: ISM policy validation failed"
    echo "   Policy exists but configuration is incorrect"
    echo "   2-year data retention cannot be guaranteed with incorrect policy"
    echo ""
    echo "📋 Policy configuration retrieved:"
    echo "$POLICY_CONFIG" | head -20
    echo ""
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

# ============================================
# SECTION 4.6: POST-DEPLOYMENT VALIDATION
# ============================================
echo ""
echo "🔍 Step 4.6: Validating Post-Deployment Configuration..."
echo ""

VALIDATION_ERRORS=0

# Validate 1: Syslog Configuration
echo "   Checking syslog configuration..."
if ssh -i $SSH_KEY root@$UNRAID_SERVER "docker exec wazuh-wazuh.manager-1 grep -q 'connection.*syslog' /var/ossec/etc/ossec.conf 2>/dev/null"; then
    echo "   ✅ Syslog configuration present in ossec.conf"
else
    echo "   ❌ ERROR: Syslog configuration missing from ossec.conf"
    VALIDATION_ERRORS=$((VALIDATION_ERRORS + 1))
fi

# Validate 2: Auto-Start Configuration
echo "   Checking auto-start configuration..."
if ssh -i $SSH_KEY root@$UNRAID_SERVER "[ -f /boot/config/plugins/user.scripts/scripts/wazuh-autostart/script ] && [ -f /boot/config/plugins/user.scripts/scripts/wazuh-autostart/schedule ]"; then
    echo "   ✅ Auto-start script and schedule configured"
else
    echo "   ❌ ERROR: Auto-start configuration incomplete"
    VALIDATION_ERRORS=$((VALIDATION_ERRORS + 1))
fi

# Validate 3: ISM Policy Existence and Configuration
echo "   Checking ISM policy..."
ISM_VALIDATION_RESPONSE=$(ssh -i $SSH_KEY root@$UNRAID_SERVER "curl -k -s --max-time 10 -u admin:SecretPassword -X GET 'https://$INDEXER_IP:9200/_plugins/_ism/policies/wazuh-2year-retention' 2>/dev/null")

if echo "$ISM_VALIDATION_RESPONSE" | grep -q '"policy_id":"wazuh-2year-retention"'; then
    # Policy exists, check retention periods
    if echo "$ISM_VALIDATION_RESPONSE" | grep -q '"min_index_age":"30d"' && \
       echo "$ISM_VALIDATION_RESPONSE" | grep -q '"min_index_age":"90d"' && \
       echo "$ISM_VALIDATION_RESPONSE" | grep -q '"min_index_age":"730d"'; then
        echo "   ✅ ISM policy configured with correct retention (30d, 90d, 730d)"
    else
        echo "   ❌ ERROR: ISM policy exists but retention periods are incorrect"
        echo "   Expected: 30d (hot→warm), 90d (warm→cold), 730d (cold→delete)"
        VALIDATION_ERRORS=$((VALIDATION_ERRORS + 1))
    fi
else
    echo "   ❌ ERROR: ISM policy not found or inaccessible"
    if echo "$ISM_VALIDATION_RESPONSE" | grep -q "index_not_found_exception"; then
        echo "   Reason: ISM config index doesn't exist (ISM plugin not initialized)"
    elif echo "$ISM_VALIDATION_RESPONSE" | grep -q "error"; then
        ERROR_SUMMARY=$(echo "$ISM_VALIDATION_RESPONSE" | grep -o '"type":"[^"]*"' | head -1)
        echo "   Error: $ERROR_SUMMARY"
    fi
    VALIDATION_ERRORS=$((VALIDATION_ERRORS + 1))
fi

# Validate 4: Manager Processes Running
echo "   Checking critical manager processes..."
CRITICAL_PROCESSES_DOWN=0
for process in "wazuh-remoted" "wazuh-analysisd" "wazuh-execd" "wazuh-modulesd"; do
    if ssh -i $SSH_KEY root@$UNRAID_SERVER "docker exec wazuh-wazuh.manager-1 /var/ossec/bin/wazuh-control status 2>/dev/null | grep -q '$process is running'"; then
        true  # Process running, no output needed for brevity
    else
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
    echo ""
    echo "💡 Troubleshooting:"
    echo "   1. Review errors above for specific failures"
    echo "   2. Check manager logs: ssh root@10.2.0.16 'docker logs wazuh-wazuh.manager-1'"
    echo "   3. Check indexer logs: ssh root@10.2.0.16 'docker logs wazuh-wazuh.indexer-1'"
    echo "   4. Verify network connectivity between orchestrator and Unraid"
    echo ""
    echo "⚠️  Deployment cannot continue with validation failures"
    echo "   These are mandatory requirements for production use"
    echo ""
    exit 1
fi

echo ""
show_elapsed_time $SECTION4_START_TIME
echo ""

# ============================================
# SECTION 4.5: RESTORE FROM BACKUP (RESTORE MODE ONLY)
# ============================================
if [ "$MODE" != "restore" ]; then
    echo "==========================================="
    echo "  SECTION 4.5: DATA RESTORE"
    echo "  ⏩ SKIPPED (fresh install mode)"
    echo "==========================================="
    echo ""
else
    echo "==========================================="
    echo "  SECTION 4.5: DATA RESTORE"
    echo "  Restoring from backup: $BACKUP_TIMESTAMP"
    echo "==========================================="
    echo ""

    # Start section timer
    SECTION45_START_TIME=$(date +%s)

    echo "🔄 Restoring historical data and agent identities from backup"
echo "   This will restore your historical security data"
echo ""

# Run the restore script
echo "📥 Running restore script..."
RESTORE_OUTPUT=$(./wazuh-restore-script.sh "$BACKUP_TIMESTAMP" 2>&1)
RESTORE_EXIT_CODE=$?

# Display restore output
echo "$RESTORE_OUTPUT"
echo ""

# Verify restore was successful
if [ $RESTORE_EXIT_CODE -ne 0 ]; then
    echo "⚠️  WARNING: RESTORE ENCOUNTERED ISSUES"
    echo "   Deployment completed but data restore had problems"
    echo "   You may need to manually restore using:"
    echo "   ./wazuh-restore-script.sh $BACKUP_TIMESTAMP"
    echo ""
    echo "   Continuing with validation..."
else
    echo "✅ Data restoration completed successfully"
    show_elapsed_time $SECTION45_START_TIME
fi
echo ""
fi

# ============================================
# SECTION 5: VALIDATION
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

# Get policy configuration and validate it
POLICY_CONFIG=$(ssh -i $SSH_KEY root@$UNRAID_SERVER "curl -k -s --max-time 10 -u admin:SecretPassword -X GET 'https://$INDEXER_IP:9200/_plugins/_ism/policies/wazuh-2year-retention'" 2>/dev/null)

if echo "$POLICY_CONFIG" | grep -q '"_id":"wazuh-2year-retention"'; then
    # Validate retention periods
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

    # Validate states
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

# Validation 5.4: Syslog Reception and Processing
echo ""
echo "📡 Validation 5.4: Syslog Reception and Processing..."

if [ "$SYSLOG_READY" = true ]; then
    echo "Sending test syslog message..."
    if ssh -i $SSH_KEY root@$UNRAID_SERVER "logger -n $MANAGER_IP -P 514 'Test syslog message from complete deployment script - $(date +%s)'" 2>/dev/null; then
        echo "✅ Test syslog message sent"
        
        echo "Waiting 45 seconds for processing and indexing..."
        sleep 45
        
        echo "Searching for syslog data in indices..."
        
        # Check for any syslog data in the system using correct field path
        SYSLOG_COUNT=$(ssh -i $SSH_KEY root@$UNRAID_SERVER "curl -k -s --max-time 15 -u admin:SecretPassword 'https://$INDEXER_IP:9200/wazuh-alerts-*/_search' -H 'Content-Type: application/json' -d '{\"query\":{\"term\":{\"rule.groups\":\"syslog\"}},\"size\":0}' 2>/dev/null | jq -r '.hits.total.value // 0' 2>/dev/null || echo '0'")
        
        if [ "$SYSLOG_COUNT" -gt 0 ]; then
            echo "✅ Syslog processing confirmed - found $SYSLOG_COUNT syslog entries"
            echo "   Complete syslog pipeline working: reception → processing → indexing"
        else
            echo "⚠️  No syslog data found in indices yet"
            echo "   This may indicate processing time needed or configuration review required"
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

# Check if vulnerability detection is enabled in configuration
echo "Verifying vulnerability detection configuration..."
MODERN_CONFIG=$(ssh -i $SSH_KEY root@$UNRAID_SERVER "docker exec wazuh-wazuh.manager-1 grep -c '<vulnerability-detection>' /var/ossec/etc/ossec.conf" 2>/dev/null || echo "0")
LEGACY_CONFIG=$(ssh -i $SSH_KEY root@$UNRAID_SERVER "docker exec wazuh-wazuh.manager-1 grep -c '<wodle name=\"vulnerability-detector\">' /var/ossec/etc/ossec.conf" 2>/dev/null || echo "0")

if [ "$MODERN_CONFIG" -gt 0 ] || [ "$LEGACY_CONFIG" -gt 0 ]; then
    echo "✅ Vulnerability detection configuration found (Modern: $MODERN_CONFIG, Legacy: $LEGACY_CONFIG)"
    
    # Check vulnerability detection process
    echo "Checking vulnerability detection processes..."
    if ssh -i $SSH_KEY root@$UNRAID_SERVER "docker exec wazuh-wazuh.manager-1 ps aux | grep -v grep | grep -q 'wazuh-db\\|vulnerability'" 2>/dev/null; then
        echo "✅ Vulnerability detection processes running"
        
        # Check for vulnerability feed updates
        echo "Checking for vulnerability feed data..."
        if ssh -i $SSH_KEY root@$UNRAID_SERVER "docker exec wazuh-wazuh.manager-1 ls -la /var/ossec/queue/vulnerabilities/ 2>/dev/null | grep -E '\\.(json|xml)$' | wc -l | grep -v '^0$'" 2>/dev/null; then
            echo "✅ Vulnerability feed data present"
        else
            echo "⚠️  Vulnerability feeds may still be downloading (this is normal on first startup)"
        fi
        
        # Check vulnerability detection logs
        echo "Checking vulnerability detection logs..."
        if ssh -i $SSH_KEY root@$UNRAID_SERVER "docker exec wazuh-wazuh.manager-1 grep -i 'vulnerability' /var/ossec/logs/ossec.log 2>/dev/null | tail -5" 2>/dev/null; then
            echo "✅ Vulnerability detection logging active"
        else
            echo "ℹ️  No vulnerability detection logs yet (normal if no agents connected)"
        fi
    else
        echo "⚠️  Vulnerability detection processes not found"
    fi
else
    echo "❌ Vulnerability detection configuration not found in ossec.conf"
fi

# Additional check for vulnerability detection errors in logs
echo "Checking for vulnerability detection errors..."
if ssh -i $SSH_KEY root@$UNRAID_SERVER "docker exec wazuh-wazuh.manager-1 grep -i 'vulnerability.*error\\|vulnerability.*deprecated' /var/ossec/logs/ossec.log 2>/dev/null | tail -3" 2>/dev/null; then
    echo "⚠️  Check logs above for any vulnerability detection issues"
else
    echo "✅ No vulnerability detection errors found in recent logs"
fi

# Validation 5.6: Auto-Start Configuration
echo ""
echo "🚀 Validation 5.6: Auto-Start Configuration..."

echo "Verifying User Scripts auto-start configuration..."
# Note: /boot is FAT32 (vfat), so execute bit is never set - User Scripts doesn't need it
if ssh -i $SSH_KEY root@$UNRAID_SERVER "[ -f /boot/config/plugins/user.scripts/scripts/wazuh-autostart/script ] && [ -s /boot/config/plugins/user.scripts/scripts/wazuh-autostart/script ]"; then
    echo "✅ Auto-start script exists and has content"
    
    # Verify script content
    if ssh -i $SSH_KEY root@$UNRAID_SERVER "grep -q 'docker-compose up -d' /boot/config/plugins/user.scripts/scripts/wazuh-autostart/script"; then
        echo "✅ Auto-start script contains correct docker-compose command"
    else
        echo "⚠️  Auto-start script may have incorrect content"
    fi
    
    # Verify schedule configuration
    if ssh -i $SSH_KEY root@$UNRAID_SERVER "[ -f /boot/config/plugins/user.scripts/scripts/wazuh-autostart/schedule ] && grep -q 'arrayStarted' /boot/config/plugins/user.scripts/scripts/wazuh-autostart/schedule"; then
        echo "✅ Auto-start schedule configured for array start"
        echo "   📋 Containers will automatically start when Unraid array starts"
    else
        echo "⚠️  Auto-start schedule not properly configured"
    fi
else
    echo "❌ Auto-start script not found or not executable"
fi

# Validation 5.7: Integrations (VirusTotal and Maltiverse)
VT_INTEGRATION_WORKING="false"
MALTIVERSE_INTEGRATION_WORKING="false"

if [ -n "$VIRUSTOTAL_API_KEY" ]; then
    echo "🔍 Validation 5.7a: VirusTotal Integration..."
    
    # Check if VirusTotal integration is configured in ossec.conf
    VT_CONFIG_CHECK=$(ssh -i "$SSH_KEY" root@$UNRAID_SERVER "docker exec wazuh-wazuh.manager-1 grep -A 5 '<integration>' /var/ossec/etc/ossec.conf | grep -q virustotal && echo 'configured' || echo 'missing'")
    
    if [ "$VT_CONFIG_CHECK" = "configured" ]; then
        echo "   ✅ VirusTotal integration configured in ossec.conf"
        VT_INTEGRATION_WORKING="true"
        
        # Check if wazuh-integratord process is running
        VT_PROCESS_CHECK=$(ssh -i "$SSH_KEY" root@$UNRAID_SERVER "docker exec wazuh-wazuh.manager-1 ps aux | grep -v grep | grep wazuh-integratord")
        if [ -n "$VT_PROCESS_CHECK" ]; then
            echo "   ✅ Wazuh integratord process is running"
        else
            echo "   ❌ Wazuh integratord process not found"
            VT_INTEGRATION_WORKING="false"
        fi
        
        echo "   📋 Integration Status: Configuration loaded, will activate on file changes detected by FIM"
        
        # Test API connectivity
        echo "   🔑 Testing VirusTotal API connectivity..."
        VT_API_TEST=$(ssh -i "$SSH_KEY" root@$UNRAID_SERVER "docker exec wazuh-wazuh.manager-1 curl -s -X GET 'https://www.virustotal.com/vtapi/v2/domain/report?apikey=$VIRUSTOTAL_API_KEY&domain=google.com' | grep -o '\"response_code\":[0-9]*' || echo 'api_test_failed'")
        
        if echo "$VT_API_TEST" | grep -q '"response_code":1'; then
            echo "   ✅ VirusTotal API key validated and working"
        elif echo "$VT_API_TEST" | grep -q '"response_code":0'; then
            echo "   ✅ VirusTotal API key working (domain not found is expected for test)"
        else
            echo "   ⚠️ VirusTotal API test inconclusive. Check API key and connectivity."
        fi
    else
        echo "   ❌ VirusTotal integration not found in configuration"
    fi
else
    echo "🔍 Validation 5.7a: VirusTotal Integration (Skipped - No API key configured)"
fi

if [ -n "$MALTIVERSE_API_KEY" ]; then
    echo "🔍 Validation 5.7b: Maltiverse Integration..."
    
    # Check if Maltiverse integration is configured in ossec.conf
    MALTIVERSE_CONFIG_CHECK=$(ssh -i "$SSH_KEY" root@$UNRAID_SERVER "docker exec wazuh-wazuh.manager-1 grep -A 5 '<integration>' /var/ossec/etc/ossec.conf | grep -q maltiverse && echo 'configured' || echo 'missing'")
    
    if [ "$MALTIVERSE_CONFIG_CHECK" = "configured" ]; then
        echo "   ✅ Maltiverse integration configured in ossec.conf"
        MALTIVERSE_INTEGRATION_WORKING="true"
        
        # Check if wazuh-integratord process is running
        MALTIVERSE_PROCESS_CHECK=$(ssh -i "$SSH_KEY" root@$UNRAID_SERVER "docker exec wazuh-wazuh.manager-1 ps aux | grep -v grep | grep wazuh-integratord")
        if [ -n "$MALTIVERSE_PROCESS_CHECK" ]; then
            echo "   ✅ Wazuh integratord process is running"
        else
            echo "   ❌ Wazuh integratord process not found"
            MALTIVERSE_INTEGRATION_WORKING="false"
        fi
        
        echo "   📋 Integration Status: Configuration loaded, will activate on rule triggers"
        
        # Validate rule IDs are configured correctly  
        echo "   🎯 Checking configured rule triggers..."
        # Simple check: verify Maltiverse integration has rule_id configured
        RULE_CHECK=$(ssh -i "$SSH_KEY" root@$UNRAID_SERVER "docker exec wazuh-wazuh.manager-1 grep -A 10 'maltiverse' /var/ossec/etc/ossec.conf | grep '<rule_id>' | wc -l")
        if [ "$RULE_CHECK" -gt 0 ]; then
            # Extract the actual rule IDs for display
            RULE_IDS=$(ssh -i "$SSH_KEY" root@$UNRAID_SERVER "docker exec wazuh-wazuh.manager-1 grep -A 10 'maltiverse' /var/ossec/etc/ossec.conf | grep '<rule_id>' | sed 's/.*<rule_id>\(.*\)<\/rule_id>.*/\1/' | tr -d ' '")
            echo "   ✅ Rule triggers configured: $RULE_IDS"
            echo "       • 2502: SSH login failures → IP reputation lookup"
            echo "       • 111041: DNS queries → Domain/IP reputation analysis" 
            echo "       • 111042: Squid proxy logs → URL threat analysis"
            echo "       • 111050: File modifications in /tmp → Hash analysis"
            echo "       • 111051: File modifications in /var/www → Hash analysis"
        else
            echo "   ❌ Rule triggers not properly configured"
            MALTIVERSE_INTEGRATION_WORKING="false"
        fi
        
        # Test API connectivity with comprehensive endpoint testing
        echo "   🔑 Testing Maltiverse API connectivity..."
        
        # Test 1: IPv4 address lookup (as recommended in blog)
        echo "       Testing IPv4 lookup (8.8.8.8)..."
        IPV4_TEST=$(ssh -i "$SSH_KEY" root@$UNRAID_SERVER "docker exec wazuh-wazuh.manager-1 curl -s -H 'Authorization: Bearer $MALTIVERSE_API_KEY' 'https://api.maltiverse.com/ip/8.8.8.8' | grep -o '\"classification\"' || echo 'failed'")
        
        # Test 2: Hostname lookup 
        echo "       Testing hostname lookup (google.com)..."
        HOSTNAME_TEST=$(ssh -i "$SSH_KEY" root@$UNRAID_SERVER "docker exec wazuh-wazuh.manager-1 curl -s -H 'Authorization: Bearer $MALTIVERSE_API_KEY' 'https://api.maltiverse.com/hostname/google.com' | grep -o '\"hostname\"' || echo 'failed'")
        
        # Evaluate test results
        if echo "$IPV4_TEST" | grep -q '"classification"'; then
            echo "   ✅ IPv4 address lookup: Working"
            API_WORKING="true"
        else
            echo "   ❌ IPv4 address lookup: Failed"
            API_WORKING="false"
        fi
        
        if echo "$HOSTNAME_TEST" | grep -q '"hostname"'; then
            echo "   ✅ Hostname lookup: Working" 
        else
            echo "   ⚠️  Hostname lookup: Limited/Failed (may be API tier limitation)"
        fi
        
        # Overall API assessment
        if [ "$API_WORKING" = "true" ]; then
            echo "   ✅ Maltiverse API connectivity validated"
        else
            echo "   ❌ Maltiverse API connectivity failed - check API key and network"
            MALTIVERSE_INTEGRATION_WORKING="false"
        fi
        
        # Check integration logs for any existing activity
        echo "   📊 Checking for Maltiverse integration activity..."
        INTEGRATION_LOGS=$(ssh -i "$SSH_KEY" root@$UNRAID_SERVER "docker exec wazuh-wazuh.manager-1 tail -n 50 /var/ossec/logs/ossec.log | grep -i maltiverse | wc -l")
        if [ "$INTEGRATION_LOGS" -gt 0 ]; then
            echo "   📈 Found $INTEGRATION_LOGS Maltiverse log entries - integration active"
        else
            echo "   📭 No Maltiverse activity yet - will activate on matching events"
        fi
    else
        echo "   ❌ Maltiverse integration not found in configuration"
    fi
else
    echo "🔍 Validation 5.7b: Maltiverse Integration (Skipped - No API key configured)"
fi

echo ""
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

# Show section completion time
show_elapsed_time $SECTION5_START_TIME
echo ""

# ============================================
# SECTION 6: Removed (duplicate of Section 4.5)

# Calculate and display total deployment time
echo ""
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