# Wazuh Configuration Enhancements

This sub-project focuses on enhancing the deployed Wazuh SIEM with advanced detection capabilities, integrations, and security configurations.

## Project Structure

```
wazuh-config-enhancements/
├── README.md                           # This file
├── current-integrations.md             # Documentation of current system integrations
├── vulnerability-scanning/             # Vulnerability detection configurations
├── cis-benchmarks/                     # CIS benchmark implementation
├── threat-intelligence/                # Threat intel feed configurations
├── external-integrations/              # OpenVAS, Nessus, etc.
└── custom-rules/                       # Custom detection rules
```

## Current Environment Status

- **Wazuh Version**: 4.12.0
- **Deployment**: Docker Compose on Unraid
- **Base Configuration**: Complete and operational
- **Network**: Custom br2.2 (10.2.0.85-87)
- **Storage**: 2-year retention configured

## Enhancement Goals

### 1. **Current System Documentation** 📋
- [ ] Document existing agent deployments
- [ ] Map syslog sources and configurations
- [ ] Catalog current alert types and severity levels

### 2. **Vulnerability Management** 🔍
- [ ] Enable built-in vulnerability scanning on agents
- [ ] Configure vulnerability detection rules
- [ ] Investigate OpenVAS integration
- [ ] Research Nessus log parsing

### 3. **Security Benchmarks** ✅
- [ ] Implement CIS benchmark scanning
- [ ] Configure compliance reporting
- [ ] Set up configuration assessment

### 4. **Threat Intelligence** 🌐
- [ ] VirusTotal API integration
- [ ] AlienVault OTX feed integration
- [ ] MISP platform research
- [ ] Custom threat feed development

### 5. **Enhanced Detection** 🎯
- [ ] Custom rule development
- [ ] MITRE ATT&CK mapping expansion
- [ ] Behavioral analysis configuration
- [ ] Advanced correlation rules

## Quick Start

1. **Review current alerts**: Access dashboard at https://10.2.0.87:5601
2. **Check agent status**: Review deployed agents and their configurations
3. **Analyze findings**: Understand current detection patterns
4. **Plan enhancements**: Prioritize based on environment needs

## References

- [Wazuh Documentation](https://documentation.wazuh.com/)
- [MITRE ATT&CK Framework](https://attack.mitre.org/)
- [CIS Controls](https://www.cisecurity.org/controls/)
- [NIST Cybersecurity Framework](https://www.nist.gov/cyberframework)