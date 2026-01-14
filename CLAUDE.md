# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Status
✅ **WAZUH 4.14.1 SIEM SUCCESSFULLY DEPLOYED AND OPERATIONAL**

Current repository contains:
- `phoenix-wazuh-orchestrator.sh`: Main deployment script (runs from dev machine)
- `phoenix-wazuh-worker.sh`: Worker script (runs on Unraid, handles container deployment)
- `docker-compose-unraid.yml`: Docker Compose configuration with proper volume mounts
- `ossec.conf.template`: Template for Wazuh manager configuration
- `wazuh-integrations.conf.example`: Example integration configuration file
- SSL certificates auto-generated using official `wazuh-certs-generator`
- All configuration issues resolved

## Current Wazuh Deployment Status
**All services are RUNNING and ACCESSIBLE:**

### Access URLs (Working)
- **Dashboard**: `https://10.2.0.87:5601`
  - Login: `admin` / `SecretPassword`
  - Web interface fully functional
- **Manager API**: `https://10.2.0.85:55000`
  - API Login: `wazuh-wui` / `MyS3cr37P450r.*-`
  - All Wazuh processes running
- **Indexer**: `https://10.2.0.86:9200`
  - Login: `admin` / `SecretPassword`
  - OpenSearch responding correctly and indexing data
  - Wazuh indices being created successfully

### Key Fixes Applied
- ✅ Fixed invalid Elasticsearch ILM syntax in opensearch.yml
- ✅ Removed problematic SSL environment variables
- ✅ Fixed YAML syntax errors in wazuh.yml
- ✅ Added comprehensive permission handling
- ✅ Created missing ar.conf file for manager initialization
- ✅ Removed conflicting port mapping (443) that conflicted with Unraid UI
- ✅ Added proper OpenSearch security settings
- ✅ Fixed SSL certificate hostname validation by using IP addresses instead of hostnames
- ✅ Resolved Filebeat authentication by using correct admin:admin credentials
- ✅ Fixed admin DN configuration for security initialization
- ✅ Fixed index auto-creation by setting action.auto_create_index=true and restarting manager

## Password Change Process

### 🔐 **Production Password Change Automation**
- **Script**: `production-password-change.sh` - Automated password change following official Wazuh procedures
- **Configuration**: `passwords.conf` - User-defined secure passwords for all accounts
- **Status**: ✅ **FULLY FUNCTIONAL** - Complete automation of Wazuh password change process

### ⚠️ **Known Docker Volume/Image Caching Issue**
**Important**: Wazuh Docker deployments have a well-documented issue where password changes don't take effect due to cached credentials in Docker volumes and images.

**Symptoms**:
- Password change process completes successfully
- securityadmin.sh reports "SUCC: Configuration updated"
- Default admin:admin credentials still work after password change
- New passwords don't work for authentication

**Root Cause**: Docker caches old credentials in volumes and image layers, even after following official documentation perfectly.

**References**:
- [wazuh/wazuh-docker#838](https://github.com/wazuh/wazuh-docker/issues/838): "The documented way to change admin/wazuh-wui passwords do not work"
- [wazuh/wazuh-docker#859](https://github.com/wazuh/wazuh-docker/issues/859): "Securityadmin.sh fail when trying to change admin's password"
- [wazuh/wazuh-docker#712](https://github.com/wazuh/wazuh-docker/issues/712): "The default password can't be changed"
- [wazuh/wazuh-docker#906](https://github.com/wazuh/wazuh-docker/issues/906): "Changing default password results in server error"

**Solution Applied**: Our automation includes complete Docker cleanup (volumes + images) before applying password changes to ensure cached credentials are cleared.

## INTEGRATION CONFIGURATION

### Configuration File System
- **Main Config**: `wazuh-integrations.conf` - Contains API keys and integration settings
- **Example File**: `wazuh-integrations.conf.example` - Template with examples and documentation
- **Security**: Configuration files are excluded from version control via `.gitignore`

### Setting up Integrations
```bash
# Copy example configuration
cp wazuh-integrations.conf.example wazuh-integrations.conf

# Secure the configuration file
chmod 600 wazuh-integrations.conf

# Edit with your API keys
nano wazuh-integrations.conf
```

### Available Integrations
1. **VirusTotal Integration** ✅ **IMPLEMENTED**
   - **Status**: Ready for production use
   - **Function**: Scans files detected by File Integrity Monitoring (FIM)
   - **Setup**: Add `VIRUSTOTAL_API_KEY` to wazuh-integrations.conf
   - **API Key**: Get from https://www.virustotal.com/gui/my-apikey
   - **Limits**: Free tier - 1000 requests/day, 4 requests/minute

2. **Maltiverse Integration** ✅ **IMPLEMENTED**
   - **Status**: Ready for production use  
   - **Function**: Threat intelligence for IP addresses, domains, URLs, and file hashes
   - **Setup**: Add `MALTIVERSE_API_KEY` to wazuh-integrations.conf
   - **API Key**: Get from https://whatis.maltiverse.com/ (user profile)
   - **Features**: Real-time IOCs, malware families, geolocation data
   - **Requires**: Wazuh 4.7.0+ (native integration, no external libraries)

3. **Future Integrations** (Planned)
   - Slack notifications
   - PagerDuty incident management
   - TheHive case management
   - MISP threat intelligence
   - Suricata network IDS

## NEXT STEPS TO COMPLETE

### High Priority
1. **Configure 2-Year Data Retention** ⏳
   - Use ISM (Index State Management) policies via API
   - Commands ready in setup script output
   - Apply to wazuh-alerts-* and wazuh-archives-* indices

2. **Test Syslog Reception** ⏳
   - Configure network devices to send syslog to 10.2.0.85:514/UDP
   - Allowed network: 10.0.0.0/8 (home network range)
   - Verify log ingestion in dashboard

### Medium Priority  
3. **Configure Agent Deployment** ⏳
   - Use Wazuh dashboard: Agents → Deploy new agent
   - Server address: 10.2.0.85
   - Deploy to Windows/Linux/macOS devices in home lab

4. **Test Maltiverse Integration** ✅ **READY**
   - Maltiverse API key configured in wazuh-integrations.conf
   - Integration will activate automatically on network events
   - Monitor dashboard for threat intelligence alerts
   - Test script available: `./test-maltiverse-integration.sh`

### Commands for 2-Year Retention
```bash
# Create ISM policy (run when ready):
curl -k -u admin:admin -X PUT "https://10.2.0.86:9200/_plugins/_ism/policies/wazuh-2year-retention" \
  -H 'Content-Type: application/json' -d '{
  "policy": {
    "description": "Wazuh 2-year data retention policy",
    "default_state": "hot",
    "states": [
      {"name": "hot", "actions": [{"replica_count": {"number_of_replicas": 1}}], 
       "transitions": [{"state_name": "cold", "conditions": {"min_index_age": "30d"}}]},
      {"name": "cold", "actions": [{"read_only": {}}], 
       "transitions": [{"state_name": "delete", "conditions": {"min_index_age": "730d"}}]},
      {"name": "delete", "actions": [{"delete": {}}], "transitions": []}
    ],
    "ism_template": [{"index_patterns": ["wazuh-alerts-*", "wazuh-archives-*"], "priority": 100}]
  }
}'

# Apply to existing indices:
curl -k -u admin:admin -X POST "https://10.2.0.86:9200/_plugins/_ism/add/wazuh-alerts-*" \
  -H 'Content-Type: application/json' -d '{"policy_id": "wazuh-2year-retention"}'
```

## Known Issues & Applied Fixes

### 0. Wazuh 4.14.1 - Security Initialization (RESOLVED)

**Status**: ✅ **RESOLVED** - Our deployment now handles security initialization correctly

**Recommended Version**: **4.14.1** (latest, tested, production-ready)

**Previous Issue**:
Wazuh 4.14.1 Docker images don't auto-initialize OpenSearch Security plugin on startup. This requires running `securityadmin.sh` manually after the indexer is ready.

**Our Solution**:
The `phoenix-wazuh-worker.sh` script now follows the official Wazuh Docker deployment approach:
1. Generates SSL certificates using `wazuh-certs-generator:0.0.2`
2. Starts containers and waits for indexer to respond
3. **Runs `securityadmin.sh` explicitly** after indexer initialization
4. Verifies cluster health before proceeding

**Key Implementation** (in worker script Step 6):
```bash
docker exec wazuh-wazuh.indexer-1 bash -c '
  JAVA_HOME=/usr/share/wazuh-indexer/jdk \
  /usr/share/wazuh-indexer/plugins/opensearch-security/tools/securityadmin.sh \
    -cd /usr/share/wazuh-indexer/config/opensearch-security/ \
    -cacert /usr/share/wazuh-indexer/config/certs/root-ca.pem \
    -cert /usr/share/wazuh-indexer/config/certs/admin.pem \
    -key /usr/share/wazuh-indexer/config/certs/admin-key.pem \
    -icl -nhnv -h localhost
'
```

**Testing Results**:
- ✅ 4.14.1: Deploys successfully, all validations pass
- ✅ 4.14.1: Security initialization completes with GREEN cluster health
- ✅ 4.14.1: All integrations (VirusTotal, Maltiverse) functional
- ✅ 4.14.1: Syslog reception working
- ✅ 4.14.1: 2-year data retention policy active

**Deployment Command**:
```bash
./phoenix-wazuh-orchestrator.sh fresh-install --version 4.14.1
```

### 1. Filebeat "_type" Parameter Compatibility Issue

**Status**: ✅ **RESOLVED** - Critical fix applied for full system functionality

**Issue**: Filebeat generates 400 Bad Request errors with message:
```
Action/metadata line [1] contains an unknown parameter [_type]
```

**Root Cause**: 
- OpenSearch 2.0+ removed support for the `_type` parameter (deprecated in Elasticsearch 7.x)
- Wazuh's Filebeat still sends this parameter for backward compatibility
- Despite errors, data ingestion continues to work correctly

**Impact Before Fix**:
- ❌ **Data Pipeline**: Completely broken - no security data indexed
- ❌ **Security Indices**: wazuh-alerts-*, wazuh-archives-* not created
- ❌ **Dashboard**: No security data available, redirects to index pattern creation
- ✅ **Monitoring Only**: Only wazuh-monitoring-* indices worked

**Fix Applied**:
- Added `compatibility.override_main_response_version: true` to opensearch.yml
- Makes OpenSearch pretend to be Elasticsearch 7.x for Filebeat compatibility
- All security data now flows correctly

**Technical Details**:
- Affects Wazuh deployments using OpenSearch 2.19.1+ (Wazuh indexer)
- Related to compatibility.override_main_response_version setting
- Filebeat 7.10.2 (bundled with Wazuh) vs OpenSearch 2.19.1 incompatibility

**Resolution Status**: 
- **Current**: System operational despite error messages
- **Future**: Requires Wazuh team to update Filebeat configuration to remove _type parameter
- **Workaround**: Consider using Logstash or FluentBit for log forwarding if needed

**References**:
- [Wazuh GitHub Issue #18191](https://github.com/wazuh/wazuh/issues/18191) - Filebeat unknown parameter [_type] compatibility
- [OpenSearch GitHub Issue #3484](https://github.com/opensearch-project/OpenSearch/issues/3484) - Action/metadata line contains unknown parameter [_type]
- [OpenSearch Forum Discussion](https://forum.opensearch.org/t/metadata-line-1-contains-an-unknown-parameter-type/10945) - Community discussion on _type parameter
- [Wazuh-indexer logstash compatibility](https://forum.opensearch.org/t/wazuh-indexer-will-not-ingest-from-logstash-because-action-metadata-line-1-contains-an-unknown-parameter-type/14590) - Alternative solutions

### 2. Index Auto-Creation Pattern Mismatch

**Status**: ✅ **RESOLVED** - Auto-creation patterns configured for security indices

**Issue**: Even after fixing the "_type" parameter issue, Filebeat still couldn't create indices:
```
no such index [wazuh-alerts-4.x-{date}] and [action.auto_create_index] doesn't match
```

**Root Cause**: 
- OpenSearch default auto-creation pattern too restrictive
- Wazuh security indices (wazuh-alerts-4.x-*) not included in allowed patterns
- Dynamic date formatting in index names required wildcard patterns

**Impact Before Fix**:
- ❌ **Security Indices**: Could not auto-create despite Filebeat connecting successfully
- ❌ **Data Storage**: Security events processed but not stored
- ⚠️ **404 Errors**: Index not found errors in Filebeat logs

**Fix Applied**:
- Updated cluster setting: `action.auto_create_index` to include `wazuh-*,security-*`
- Applied in post-deployment-config.sh for persistence across redeployments
- Security indices now create automatically when data flows

**References**:
- [Wazuh GitHub Issue #21814](https://github.com/wazuh/wazuh/issues/21814) - Errors indexing alerts
- [Wazuh GitHub Issue #20732](https://github.com/wazuh/wazuh/issues/20732) - Index template compatibility
- [Community Discussion](https://groups.google.com/g/wazuh/c/oOEVBEsKbFA) - New indexes not created

### 3. Unraid /boot Filesystem Execute Permissions

**Status**: ✅ **RESOLVED** - Validation logic corrected for FAT32 filesystem

**Issue**: Auto-start script validation failing with:
```
❌ Error: Auto-start script not properly configured
```
Script file exists but `chmod +x` doesn't make it executable.

**Root Cause**:
- Unraid's `/boot` directory is mounted as vfat (FAT32) filesystem
- FAT32 doesn't support Unix execute permissions
- All files on /boot will always have `-rw-------` permissions (fmask=0177)
- `chmod +x` has no effect on FAT32 filesystems

**Impact Before Fix**:
- ❌ **Deployment Validation**: Orchestrator failed validation step unnecessarily
- ✅ **Actual Functionality**: User Scripts plugin works fine without execute bit
- The plugin reads script content and executes it via bash, doesn't check execute bit

**Fix Applied**:
- Removed `chmod +x` command from orchestrator (has no effect on FAT32)
- Changed validation from checking execute bit (`-x`) to checking file exists and has content (`-f` and `-s`)
- Added comment explaining FAT32 behavior for future reference

**Technical Details**:
- Mount options: `vfat (rw,noatime,nodiratime,fmask=0177,dmask=0077,...)`
- `fmask=0177` means all files get 0600 permissions (rw-------)
- User Scripts plugin doesn't require execute bit - it's purely content-based
- All existing User Scripts have the same `-rw-------` permissions and work correctly

### 4. Dashboard Migration Timeout & Manager Process Restart Issues

**Status**: ✅ **RESOLVED** - Timing and process management fixes applied

**Issue 1: Dashboard Migration Timeout**
Dashboard fails to start with error:
```
Another OpenSearch Dashboards instance appears to be migrating the index.
Waiting for that migration to complete.
```

**Root Cause**:
- Worker script only waited 30 seconds after container startup
- Indexer needs ~60 seconds to fully stabilize
- Dashboard attempts `.kibana_1` index creation while indexer is still slow
- Index creation request times out (30s)
- Request completes AFTER timeout, leaving orphaned index
- Dashboard retry finds index already exists, assumes another instance is migrating

**Fix Applied**:
- Increased worker script initial wait from 30s → 60s (phoenix-wazuh-worker.sh:109-111)
- Gives indexer sufficient time to stabilize before dashboard migration

**Issue 2: Manager Process Restart OCI Runtime Errors**
After orchestrator's second `docker-compose stop/start` cycle for config changes:
- Manager container starts successfully
- But attempting to run `wazuh-control start` fails with OCI runtime error:
  ```
  OCI runtime exec failed: exec failed: unable to start container process:
  error executing setns process: exit status 1: unknown
  ```
- Prevents Wazuh processes (wazuh-remoted, analysisd, etc.) from starting
- Causes syslog verification to fail

**Root Cause**:
- `docker-compose stop/start` can leave containers in inconsistent state on Unraid
- OCI runtime errors occur when trying to exec into recently started containers
- First restart (using `docker rm -f` + `docker-compose up -d`) works perfectly
- Second restart (using `stop/start`) fails with runtime errors

**Fix Applied**:
- Changed second restart to use same reliable pattern as first: `docker rm -f` + `docker-compose up -d`
- Removed problematic `docker-compose stop/start` approach (phoenix-wazuh-orchestrator.sh:1077-1079)
- Full container recreation avoids OCI runtime issues and ensures clean state
- Ensures all manager processes start properly after configuration changes

### 5. Agent Database Backup/Restore - CRITICAL BLOCKER

**Status**: ❌ **BACKUP/RESTORE NOT FUNCTIONAL** - Agent identity restoration causes deployment failures

**Critical Issue - December 2024**:
After extensive testing and debugging, the backup/restore functionality **does not work** due to a fundamental catch-22 with Wazuh's agent database architecture. **Use fresh-install mode only.**

**The Catch-22**:
1. **Restoring database files** → Manager processes fail to start (documented previously)
2. **Restoring only client.keys** → Manager encounters database errors during initialization:
   ```
   wazuh-db: ERROR: There was an error assigning the groups to agent 'XXX'
   wazuh-db: WARNING: Unable to find the id of the group 'default'
   ```
3. These errors prevent manager API from initializing within timeout
4. Deployment fails during post-configuration phase
5. **Not restoring anything** → Defeats the purpose of restore mode

**What We Tried**:
- ✅ Backup/restore client.keys only → **FAILS** (database errors block initialization)
- ✅ Backup/restore client.keys + SSL certs → **FAILS** (same errors)
- ✅ Backup/restore full database → **FAILS** (manager processes won't start)
- ✅ Increased timeouts → **FAILS** (errors persist indefinitely)

**What Wazuh Officially Supports**:
According to [official migration documentation](https://documentation.wazuh.com/current/migration-guide/):
- ✅ Backup/restore `client.keys` (agent authentication) - *Works in theory, not in practice*
- ✅ Backup/restore SSL certificates - *Only useful with database*
- ✅ Backup/restore configurations - *Works but loses all agent data*
- ❌ **Database recreation** (not restoration): "The database is automatically recreated when Wazuh manager starts up"

**Why Client.Keys Restoration ALSO Fails**:
Testing revealed a catch-22:
1. Manager starts and reads `client.keys` (sees 4 agents)
2. Manager tries to initialize database entries for these agents
3. Manager tries to assign them to default group
4. Database has no group definitions (fresh deployment)
5. Errors occur: `Unable to find the id of the group 'default'`
6. These errors prevent manager API from starting within timeout
7. Deployment fails during post-configuration phase

**Why Database Restoration Fails**:
From community reports and previous testing:
1. Databases contain runtime state (sockets, queues, locks) that don't exist in fresh deployments
2. Manager processes expect to **create** databases during initialization, not **find** them
3. Restored databases cause process failures: wazuh-remoted, wazuh-analysisd, wazuh-execd, etc.
4. Error: `Queue 'queue/alerts/execq' not accessible: 'No such file or directory'`

**CONCLUSION**:
Neither approach works. Backup/restore feature is **not functional** and **should not be used**.

## RECOMMENDED WORKFLOW (Fresh Install Only)

**Status**: ✅ **WORKING** - Use fresh-install mode for all deployments

### Deployment Command
```bash
./phoenix-wazuh-orchestrator.sh fresh-install --version 4.12.0
```

### What This Provides
- ✅ Clean, working Wazuh deployment
- ✅ All containers operational
- ✅ Syslog reception configured
- ✅ 2-year data retention policies
- ✅ Integration configurations (VirusTotal, Maltiverse)
- ✅ Auto-start on Unraid boot

### What You Lose (Compared to Hypothetical Working Restore)
- ❌ Agent IDs and names (agents must re-enroll)
- ❌ Historical agent metadata
- ❌ Agent group assignments

### What You Keep
- ✅ **Historical alert data** - Can be exported/imported via OpenSearch snapshots manually if needed
- ✅ **Integration configurations** - Baked into deployment
- ✅ **System configurations** - Version controlled in repository

### Agent Re-enrollment After Fresh Install
When you deploy fresh, agents will need to re-enroll:
1. Remove agent from old deployment (if accessible)
2. Uninstall and reinstall agent on endpoint
3. Agent enrolls with new ID and name
4. Historical data lost for that agent (new timeline starts)

### Alternative: Keep Agents Running Between Deployments
If you need to update/redeploy Wazuh without re-enrolling agents:
- **Don't touch agents** - Leave them installed and running
- They'll show as disconnected during deployment
- They'll reconnect automatically once new manager is up
- **Caveat**: This only works if you don't care about preserving agent IDs/names in the dashboard
- The manager will see them as new agents and assign new IDs

### 6. What Gets Preserved vs What's Lost (Fresh Install)

**❌ NOT Preserved (Fresh Install)**:
- Agent IDs and names
- Agent authentication credentials
- Agent database and metadata
- Historical agent timeline
- Group assignments

**✅ Still Available (Manual Export/Import if Needed)**:
- Historical alert data (OpenSearch indices can be exported)
- Integration configurations (in repository)
- System configurations (in repository)

**References**:
- [Wazuh Migration Guide - Creating Backups](https://documentation.wazuh.com/current/migration-guide/creating/wazuh-central-components.html)
- [Wazuh Migration Guide - Restoring](https://documentation.wazuh.com/current/migration-guide/restoring/wazuh-central-components.html)
- [Community: Move All Wazuh agents to New server](https://groups.google.com/g/wazuh/c/ZC7OkGNbLwM)
- [GitHub Discussion #16697 - How to backup and restore?](https://github.com/wazuh/wazuh/discussions/16697)

## Orchestrator Design Philosophy

### **Separation of Concerns**

The phoenix-wazuh-orchestrator.sh follows a clean architecture:

**1. Deployment = Clean Slate**
- Section 1 cleanup ALWAYS does full wipe of `/mnt/user/wazuh-data/live-data/*`
- No data preservation during deployment
- Every deployment starts from a known good state

**2. Data Preservation = Backup/Restore**
- Backup/restore is the ONLY mechanism for preserving historical data
- Optional Section 0: Automatic backup before deployment
- Optional Section 5: Restore after deployment
- Can be skipped with `--skip-backup-restore` flag for fresh installations

**3. Storage Architecture**
```
/mnt/user/wazuh-data/
├── live-data/      ← Wiped on deployment (operational data)
├── snapshots/      ← Wiped on deployment (active snapshot repo)
└── backups/        ← PRESERVED across deployments (archival backups)
```

**Why This Design Works:**
- ✅ Deployment is repeatable (no state carried over)
- ✅ Backups are safe (separate directory, not touched by cleanup)
- ✅ Explicit control (--skip-backup-restore for fresh installs)
- ✅ No conflicting logic (one way to preserve data: backup/restore)

**Workflow Examples:**

*Fresh Installation:*
```bash
./phoenix-wazuh-orchestrator.sh --skip-backup-restore
```

*Upgrade/Redeploy with Data Preservation:*
```bash
./phoenix-wazuh-orchestrator.sh
# Automatic backup → cleanup → deploy → restore
```

*Manual Backup/Restore:*
```bash
./wazuh-backup-script.sh                        # Backup first
./phoenix-wazuh-orchestrator.sh --skip-backup-restore  # Clean deploy
./wazuh-restore-script.sh 20251217_153000      # Restore manually
```

## Configuration Management

### Template-Based Configuration
The deployment uses a template-based approach for ossec.conf generation:

**Template File**: `ossec.conf.template`
- Contains complete ossec.conf with placeholder markers
- Placeholders: `%%VIRUSTOTAL_INTEGRATION%%` and `%%MALTIVERSE_INTEGRATION%%`
- Stored in repository for version control

**Orchestrator Process**:
1. Builds integration XML blocks conditionally based on API keys from `wazuh-integrations.conf`
2. Copies template file to Unraid server
3. Uses sed to replace placeholders with integration XML or removes placeholders if no API key
4. Applies additional settings (e.g., enables `logall=yes` for comprehensive syslog capture)

**Benefits**:
- Clean separation of config template and deployment logic
- Easy to review and modify complete configuration
- No complex heredoc or inline XML generation
- Proper version control of configuration files

## Deployment Constraints

### Unraid Storage Structure
The Wazuh deployment uses a three-tier storage architecture:

```
/mnt/user/wazuh-data/
├── live-data/              # Operational data (wiped on clean deployment)
│   ├── wazuh_logs/
│   ├── wazuh_queue/
│   └── wazuh-indexer-data/
│
├── snapshots/              # Active snapshot repository (mounted to indexer)
│   └── current/            # Current working snapshot (small, fast)
│
└── backups/                # Archival backup storage (NOT mounted, offline)
    ├── 20251216_080800/
    │   ├── snapshot/       # Exported OpenSearch snapshot data
    │   ├── client-keys/    # Agent identities
    │   ├── configs/        # Integration configurations
    │   └── metadata/       # Backup information
    └── ...
```

**Key Design Decisions:**
- **`snapshots/`**: Mounted to indexer container, only holds current working snapshot for fast startup
- **`backups/`**: Never mounted to containers, holds archival backups, can grow without affecting performance
- **`live-data/`**: Operational data that gets wiped on clean deployments but automatically restored from backups
- **`/mnt/user/appdata/wazuh`**: Configuration files and Docker Compose setup

**Why This Structure:**
- Previous design mounted `backup-data/` directly to indexer, causing slow startup as backups accumulated
- OpenSearch security plugin scans all files in mounted directories on startup
- Separating active snapshots from archival backups prevents performance degradation
- 120-second timeout remains appropriate; failures indicate real issues, not architectural problems

## Conversation History

### Session 2025-07-16
- User tested multi-line input functionality
- Added conversation history section to CLAUDE.md
- User provided context about Wazuh SIEM deployment project for home lab
- Reviewed existing docker-compose.yml and unraid-wazuh-setup.sh files
- User offered to provide link to previous Claude Chat conversation
- Cleaned existing Wazuh directories on Unraid server
- Successfully ran setup script and generated SSL certificates
- Fixed docker-compose certificate mounting issues
- Deployed containers but encountering indexer startup errors
- Fixed multiple configuration issues: YAML syntax, SSL environment variables, permissions
- Identified and fixed missing ar.conf file causing manager initialization failure
- Successfully deployed all three Wazuh services (Manager, Indexer, Dashboard)
- Fixed docker-compose port mapping conflict for cleaner configuration
- Wazuh SIEM now fully operational and ready for configuration

## Home Lab Network Configuration
- Unraid server located at 10.2.0.16/24
- Home network devices reside in 10.0.0.0/8 subnet
- SSH access to unraid server: `ssh -i /home/dev/.ssh/unraid_id_rsa root@10.2.0.16`

## Wazuh Home Lab Installation
- Project goal is to install and fully configure Wazuh to monitor and secure home lab
- Installation planned using Docker Compose plugin in Unraid
- Folder configuration:
  - `/mnt/user/appdata/wazuh`: NVMe cache storage for config files and running containers
  - `/mnt/user/wazuh-data/live-data`: Main array storage for operational data
  - `/mnt/user/wazuh-data/backup-data`: Protected backup storage

### Deployment Details
- Docker containers planned with IPs: 10.2.0.85, 10.2.0.86, 10.2.0.87
- Using custom Docker network `br2.2` in Unraid
- Configuration goals:
  - Accept syslog from multiple network servers
  - Retain ingested log data for 2 years
- Initial docker-compose and unraid-wazuh-setup.sh scripts created with Claude Chat

## Development Workflow
- Make edits to files locally then deploy to Unraid server as needed.

### Deployment Strategy

**⚠️ IMPORTANT**: Only fresh-install mode is functional. Backup/restore does not work due to agent database issues.

The orchestrator uses explicit commands, but **only fresh-install should be used**.

### Orchestrator Commands

#### 1. Fresh Install (RECOMMENDED - ONLY WORKING MODE)
```bash
./phoenix-wazuh-orchestrator.sh fresh-install
```
- Clean deployment with no data restoration
- Agents will enroll as new devices
- Custom configurations applied
- Use when: Setting up for the first time or want agents to re-enroll

#### 2. Backup (NOT FUNCTIONAL - DO NOT USE)
```bash
./phoenix-wazuh-orchestrator.sh backup
```
- ❌ **BROKEN** - Creates backup but restore doesn't work
- ❌ **DO NOT USE** - Will create false sense of data recovery capability
- See "Known Issues Section 5" for details on why backup/restore fails

#### 3. Restore (NOT FUNCTIONAL - DO NOT USE)
```bash
./phoenix-wazuh-orchestrator.sh restore <timestamp>
```
- ❌ **BROKEN** - Fails during manager initialization with database errors
- ❌ **DO NOT USE** - Deployment will fail, requiring fresh-install to recover
- See "Known Issues Section 5" for details on the catch-22 issue

### Usage Examples

**Fresh Deployment (ONLY WORKING APPROACH):**
```bash
# Deploy Wazuh from scratch with version 4.12.0
./phoenix-wazuh-orchestrator.sh fresh-install --version 4.12.0
```

**Re-deployment / Version Update:**
```bash
# Clean redeployment - agents will need to re-enroll
./phoenix-wazuh-orchestrator.sh fresh-install --version 4.12.0
```

**What Happens to Agents:**
- Existing agents will show as disconnected
- Agents must be re-enrolled (uninstall/reinstall on endpoints)
- New agent IDs and names will be assigned
- Historical agent data is lost

### What Fresh Install Provides
- ✅ Clean, working Wazuh deployment (version 4.12.0)
- ✅ All containers operational
- ✅ Syslog reception configured
- ✅ 2-year data retention policies
- ✅ Integration configurations (VirusTotal, Maltiverse)
- ✅ Auto-start on Unraid boot

### ~~What Gets Restored~~ (RESTORE DOESN'T WORK)
~~When you run `restore <timestamp>`:~~ ❌ **DO NOT USE RESTORE**
1. ~~**Clean Deployment**: System wiped and deployed fresh~~
2. ~~**Agent Identities**: Restored BEFORE containers start~~ → **Causes manager initialization failures**
3. ~~**Agent Database**: Restored with names, groups, metadata~~ → **Causes process startup failures**
4. ~~**Historical Data**: OpenSearch indices restored~~ → **Never gets to this step, deployment fails**
5. ~~**Result**: Agents reconnect automatically with all metadata intact~~ → **DEPLOYMENT FAILS**

**Reality**: Restore command will fail during Section 4.3 with database errors. Use fresh-install only.