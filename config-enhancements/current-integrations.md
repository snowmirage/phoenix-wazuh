# Current Wazuh Integrations Documentation

## Overview
This document tracks all systems currently integrated with our Wazuh SIEM deployment.

## Agent-Based Integrations

### 1. **Wazuh Manager (Self-Monitoring)**
- **Type**: Built-in agent
- **Agent Name**: `wazuh.manager`
- **IP**: 10.2.0.85
- **Platform**: Docker container (Wazuh Manager)
- **Status**: Active ✅
- **Detection Capabilities**:
  - SSH authentication monitoring
  - PAM session tracking
  - System log analysis
  - Container monitoring

**Recent Alert Examples**:
```json
{
  "rule": "sshd: authentication success",
  "level": 3,
  "timestamp": "2025-07-20T00:28:04.635Z"
}
{
  "rule": "PAM: Login session opened/closed", 
  "level": 3,
  "timestamp": "2025-07-20T00:28:04.711Z"
}
```

### 2. **External Agents** (User-Deployed)
> **Status**: Mentioned by user - requires documentation
> 
> **Action Required**: 
> - Identify which systems have agents installed
> - Document agent configurations
> - Catalog medium/low severity findings mentioned by user

## Syslog-Based Integrations

### 1. **Planned Integrations** (Not Yet Configured)
- **Network Devices**: Targeting 10.0.0.0/8 subnet
- **Unraid System Logs**: Local system monitoring
- **Pi-hole DNS Logs**: DNS security monitoring
- **pfSense/Firewall Logs**: Network security events

**Configuration Endpoint**: 
- **IP**: 10.2.0.85
- **Port**: 514/UDP
- **Allowed Networks**: 10.0.0.0/8

## Alert Analysis

### Current Alert Patterns
Based on initial analysis, the system is detecting:

1. **Authentication Events** (Level 3)
   - SSH login successes
   - PAM session management
   - Normal operational activities

2. **System Activities** (Level 3)
   - Session opened/closed events
   - Standard authentication flows

### Alert Severity Levels
- **Level 3**: Low severity - informational events
- **Levels 7-10**: Medium severity (user mentioned seeing these)
- **Levels 12+**: High severity - critical security events

## Enhancement Opportunities

### Immediate Priorities
1. **Document external agents** - identify systems with deployed agents
2. **Configure syslog sources** - network devices, firewalls, DNS servers
3. **Enable vulnerability scanning** - on existing agents
4. **Implement CIS benchmarks** - security configuration assessment

### Integration Gaps
1. **Vulnerability Management**: No scanner integration yet
2. **Threat Intelligence**: No external feeds configured
3. **Network Monitoring**: Limited to agent-based only
4. **Compliance Monitoring**: CIS/NIST benchmarks not enabled

## Next Steps

1. **Audit Current Environment**:
   ```bash
   # Get agent list
   curl -k -u admin:admin 'https://10.2.0.85:55000/agents'
   
   # Analyze alert patterns
   curl -k -u admin:admin 'https://10.2.0.86:9200/wazuh-alerts-*/_search?size=100'
   ```

2. **Configure Missing Integrations**:
   - Enable vulnerability detection on agents
   - Set up threat intelligence feeds
   - Configure CIS benchmark scanning

3. **Enhance Detection Capabilities**:
   - Custom rules for environment-specific threats
   - Advanced correlation rules
   - MITRE ATT&CK mapping

## References
- [Wazuh Agent Configuration](https://documentation.wazuh.com/current/user-manual/agents/)
- [Syslog Configuration](https://documentation.wazuh.com/current/user-manual/manager/wazuh-logtest.html)
- [Alert Analysis](https://documentation.wazuh.com/current/user-manual/manager/manual-alert-generation.html)