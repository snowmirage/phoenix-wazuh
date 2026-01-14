# Production-Ready Wazuh SIEM Deployment for Unraid

Complete home lab security monitoring solution with unified deployment, syslog reception, and 2-year data retention.

## Overview

This deployment provides a fully functional Wazuh SIEM system with:
- **Single-command deployment** - Complete automation from cleanup to validation
- **Syslog reception** from network devices (UDP 514)  
- **2-year data retention policy** with Index State Management
- **Production-grade configuration** with comprehensive validation
- **Home lab optimized** for 10.x.x.x networks

## Core Files

- `phoenix-wazuh-orchestrator.sh` - **🎯 MAIN DEPLOYMENT ORCHESTRATOR** (Use this!)
- `phoenix-wazuh-worker.sh` - Docker deployment worker (runs on Phoenix Unraid server)
- `docker-compose-unraid.yml` - Unraid-optimized Docker Compose configuration
- `certs-unraid.yml` - SSL certificate generation configuration

## Complete Deployment Process

### **🚀 Single Command Deployment** (Recommended)

```bash
# Complete production deployment - everything automated!
./phoenix-wazuh-orchestrator.sh
```

**That's it!** One command for complete Wazuh SIEM deployment including:
- ✅ Cleanup existing deployment
- ✅ Copy all required files to Unraid
- ✅ Deploy Wazuh containers with SSL certificates
- ✅ Configure syslog reception (UDP 514)
- ✅ Enable vulnerability scanning
- ✅ Set up 2-year data retention
- ✅ Comprehensive validation and testing

### **Manual Step-by-Step Process** (Legacy)

For reference only - use the unified script above instead:

```bash
# 1. Clean environment and copy files
ssh -i /home/dev/.ssh/unraid_id_rsa root@10.2.0.16 "docker rm -f \$(docker ps -aq --filter 'name=wazuh')"

# 2. SSH to Unraid  
ssh -i /home/dev/.ssh/unraid_id_rsa root@10.2.0.16

# 3. Run core deployment
cd /mnt/user/appdata && ./phoenix-wazuh-worker.sh

# 4. Run post-deployment configuration manually
# (This is all automated in the unified script)
```

## System Configuration

### **Network Configuration**
- **IPs**: Manager (10.2.0.85), Indexer (10.2.0.86), Dashboard (10.2.0.87)  
- **Network**: Custom Unraid network `br2.2`
- **Syslog Reception**: UDP port 514 on Manager IP (10.2.0.85)
- **Allowed Networks**: 10.0.0.0/8 (home lab range)

### **Storage Configuration**  
- **Configs**: `/mnt/user/appdata/wazuh` (NVME cache storage)
- **Data**: `/mnt/user/wazuh-data` (Main array storage)  
- **Retention**: 2-year data retention with ISM policies
- **Base**: Official wazuh-docker repository v4.14.1

### **Security Configuration**
- **SSL Certificates**: Auto-generated for all services
- **Authentication**: Secure API keys and dashboard credentials

## Access Information

### **Web Access**
- **Dashboard**: https://10.2.0.87:5601
- **Manager API**: https://10.2.0.85:55000
- **Indexer**: https://10.2.0.86:9200

### **Credentials**
- **Dashboard**: admin / SecretPassword
- **API**: wazuh-wui / MyS3cr37P450r.*-
- **Indexer**: admin / SecretPassword

### **Syslog Testing**
Test syslog reception from any device on your 10.x.x.x network:
```bash
logger -n 10.2.0.85 -P 514 'Test message from [hostname]'
```

## Post-Deployment Features

The `wazuh-post-deployment.sh` script configures:

### **🔧 Syslog Reception (Step 2)**
- Configures UDP port 514 reception  
- Updates ossec.conf with syslog remote configuration
- Allows syslog from 10.0.0.0/8 network range
- Graceful manager restart with validation

### **💾 2-Year Data Retention (Step 4)**  
- Creates ISM (Index State Management) policy
- **Hot State**: 0-30 days (active, replicated)
- **Warm State**: 30-90 days (less frequent access) 
- **Cold State**: 90-730 days (read-only)
- **Delete**: After 730 days
- Applies to both wazuh-alerts-* and wazuh-archives-* indices

### **🔍 Comprehensive Validation (Step 5)**
- Complete container log analysis for errors/warnings  
- System health checks and resource monitoring
- Certificate validation and SSL connectivity testing
- Retention policy verification
- Test syslog message transmission

## Benefits of This Approach

- ✅ **Automated Workflow**: Single cleanup command handles everything
- ✅ **Production-Ready**: Complete syslog + retention configuration  
- ✅ **Official Base**: Uses official wazuh-docker repository v4.14.1
- ✅ **Zero Manual Steps**: Automatic deployment file copying via SSH
- ✅ **Comprehensive Validation**: Built-in error checking and system health monitoring
- ✅ **Enterprise Features**: 2-year retention, SSL certificates, syslog reception
- ✅ **Home Lab Optimized**: Configured for 10.x.x.x networks and Unraid
- ✅ **Repeatable Deployments**: Version-controlled configurations with data-safe redeployment
- ✅ **Complete Documentation**: Built-in system validation and configuration reporting

## Key Features Delivered

### **🏠 Home Lab SIEM**
- Complete security monitoring for home networks
- Syslog reception from routers, switches, servers, and IoT devices  
- Custom network range support (10.0.0.0/8)
- Unraid integration with proper storage paths

### **📊 Enterprise Data Management**  
- 2-year data retention with automatic lifecycle management
- Index State Management with hot/warm/cold/delete transitions
- Efficient storage utilization and cost optimization
- Retention policy applied to all security indices

### **🔒 Security Hardening**
- SSL certificate generation for all services
- Secure API authentication and dashboard access
- Certificate-based inter-service communication  
- Production-grade security configuration

### **⚙️ Operational Excellence**
- Automated deployment with comprehensive validation
- Built-in error detection and system health monitoring
- Graceful container management with proper restart sequences
- Complete deployment logging and troubleshooting information

## Deployment Validation

After successful deployment, you'll see:
- ✅ All containers running with 0 restarts
- ✅ Syslog port 514 listening on Manager IP
- ✅ 2-year retention policy active and applied  
- ✅ SSL certificates generated and configured
- ✅ Test syslog message successfully sent
- ✅ Dashboard accessible via HTTPS
- ✅ Complete system health validation passed

## Expected Startup Issues (Normal Behavior)

During fresh deployments, you may see the following **temporary errors** that **automatically resolve** within 2-3 minutes:

### **Indexer Startup Issues (NORMAL)**

**Security Backend Initialization (15-20 errors)**
```
[ERROR] Not yet initialized (you may need to run securityadmin)
```
- **Cause**: Security plugin initializing during first 2-3 minutes
- **Resolution**: Automatic - stops once initialization completes
- **Action**: None required

**File Permission Warnings (8 warnings)**
```
File /usr/share/wazuh-indexer/bin/opensearch has insecure file permissions (should be 0600)
```
- **Impact**: Low security risk (files are container-internal)
- **Cause**: Container default permissions (755 vs 600)
- **Action**: None required for functionality

**Storage Performance Warnings**
```
health check took [89237ms] which is above the warn threshold of [5s]
```
- **Cause**: Heavy I/O during initial index creation
- **Pattern**: Only during startup/high load periods
- **Resolution**: Performance stabilizes after startup

### **Manager Startup Issues (NORMAL)**

**Elasticsearch Bulk Operation Timeouts (2-4 errors)**
```
failed to perform any bulk index operations: Client.Timeout exceeded
```
- **Cause**: Indexer under heavy load during startup
- **Pattern**: Only during first 2-3 minutes
- **Resolution**: Operations retry automatically and succeed

**Vulnerability Index Connection Delays**
```
IndexerConnector initialization failed for index 'wazuh-states-vulnerabilities'
```
- **Cause**: Vulnerability scanner connecting before indexer ready
- **Resolution**: Automatic retry until connection succeeds
- **Impact**: Temporary delay, then normal operation

### **Dashboard Startup Issues (NORMAL)**

**Initial Connection Errors (3-5 errors)**
```
[ConnectionError]: connect ECONNREFUSED 10.2.0.86:9200
```
- **Cause**: Dashboard starts before indexer accepts connections
- **Timing**: First 30-60 seconds only
- **Resolution**: Connects successfully once indexer ready

### **When to Be Concerned**

❌ **Contact support if you see:**
- Errors persisting **after 5+ minutes** of uptime
- Containers repeatedly restarting
- HTTP 5xx errors when accessing dashboard after startup
- "CRITICAL" or "FATAL" level messages
- Persistent connection refused errors after initial startup

✅ **Normal operation indicators:**
- All containers show "Up" status with no restarts
- Dashboard accessible at https://10.2.0.87:5601
- Indexer cluster health shows "green" or "yellow"
- Resource usage stabilizes below 10% CPU after startup