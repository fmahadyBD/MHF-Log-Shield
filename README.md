# 🛡️ MHF Log Shield - Enterprise Mobile Log Collector for Wazuh

A production-ready, real-time log collection application that sends comprehensive device and application telemetry to a Wazuh SIEM server. Supports both Android and iOS platforms with enterprise-grade monitoring capabilities.

## 📱 Enterprise Features

- **Cross-platform Monitoring** - Full support for Android & iOS
- **Real-time Telemetry** - Device status, app lifecycle, network changes, battery state
- **Wazuh SIEM Integration** - UDP syslog (RFC3164) and REST API support
- **Offline Resilience** - Stores logs when offline, automatic sync when connected
- **Background Intelligence** - Works even when app is minimized/closed
- **Security Event Correlation** - Structured alerts for threat detection
- **Compliance Ready** - GDPR, HIPAA, PCI-DSS logging standards

## 🏗️ Production Build Process

### Development Build (Testing)
```bash
flutter clean
flutter pub get
flutter analyze
flutter test
flutter build apk --debug --split-per-abi
```

### Production Release Build
```bash
flutter clean
flutter pub get
flutter build apk --release --split-per-abi --obfuscate --split-debug-info=./debug-info/
```

### App Bundle (Google Play)
```bash
flutter clean
flutter pub get
flutter build appbundle --release --obfuscate
```

### iOS Production Build (Mac Only)
```bash
flutter clean
flutter pub get
flutter build ios --release --no-codesign
# Open ios/Runner.xcworkspace in Xcode
# Configure signing certificates
# Archive and distribute via App Store Connect
```

## 📡 Wazuh Server Enterprise Configuration

### 1. **Configure Wazuh Manager for Mobile Log Reception**

Edit `/var/ossec/etc/ossec.conf` on your Wazuh server:

```xml
<ossec_config>
  <!-- Enterprise Security Configuration -->
  <global>
    <jsonout_output>yes</jsonout_output>
    <alerts_log>yes</alerts_log>
    <logall>yes</logall>
    <logall_json>yes</logall_json>
    <email_notification>yes</email_notification>
    <email_to>security-team@yourdomain.com</email_to>
    <smtp_server>smtp.yourdomain.com:587</smtp_server>
    <email_from>wazuh-alerts@yourdomain.com</email_from>
  </global>
  
  <!-- Primary UDP Syslog Reception (RFC3164) -->
  <remote>
    <connection>syslog</connection>
    <port>514</port>
    <protocol>udp</protocol>
    <allowed-ips>192.168.1.0/24</allowed-ips>  <!-- Restrict to internal network -->
    <local_ip>0.0.0.0</local_ip>
  </remote>
  
  <!-- Secondary TCP/SSL Reception for iOS/HIGH Security -->
  <remote>
    <connection>secure</connection>
    <port>55000</port>
    <protocol>tcp</protocol>
    <allowed-ips>192.168.1.0/24</allowed-ips>
    <ssl_ciphers>HIGH:!aNULL:!MD5</ssl_ciphers>
    <ssl_verify_cert>no</ssl_verify_cert>  <!-- Set to 'yes' with proper certs -->
  </remote>
  
  <!-- Log rotation and retention -->
  <logging>
    <log_format>json</log_format>
    <max_size>1G</max_size>
    <rotation>12</rotation>
  </logging>
</ossec_config>
```

### 2. **Advanced Custom Decoder for Mobile Telemetry**

Create `/var/ossec/etc/decoders/mhf_log_shield_decoder.xml`:

```xml
<!-- Mobile Device Telemetry Decoders -->
<decoder name="mhf-syslog">
  <prematch>^\&lt;\d+\&gt;</prematch>
  <regex>^\&lt;(\d+)\&gt;(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z)\s+(\S+)\s+(\S+)\[(\d+)\]:\s+(\w+):\s+(.+)$</regex>
  <order>priority, timestamp, hostname, program, pid, level, message</order>
</decoder>

<decoder name="mhf-app-event">
  <parent>mhf-syslog</parent>
  <prematch>📱 APP</prematch>
  <regex>📱 APP (\w+)\s*\n• Name: (.+)\n• Package: (.+)\n• Type: (\w+ App)\n• Version: (.+) \((.+)\)\n*(• Source: (.+))?</regex>
  <order>event_type, app_name, package_name, app_type, version, version_code, _, source</order>
</decoder>

<decoder name="mhf-device-status">
  <parent>mhf-syslog</parent>
  <prematch>📊 Status Update</prematch>
  <regex>📊 Status Update \| Platform: (\w+) \| Apps: (\d+) \| Battery: (\d+)% \| Network: (.+)</regex>
  <order>platform, app_count, battery_level, network_type</order>
</decoder>

<decoder name="mhf-network-change">
  <parent>mhf-syslog</parent>
  <prematch>🌐 Network changed:</prematch>
  <regex>🌐 Network changed: (.+)\n• Time: (.+)</regex>
  <order>network_state, timestamp</order>
</decoder>

<decoder name="mhf-app-state">
  <parent>mhf-syslog</parent>
  <prematch>📱 App State:</prematch>
  <regex>📱 App State: (\w+)\n• Description: (.+)\n• Time: (.+)</regex>
  <order>app_state, description, timestamp</order>
</decoder>

<decoder name="mhf-battery-status">
  <parent>mhf-syslog</parent>
  <prematch>🔋 Battery:</prematch>
  <regex>🔋 Battery: (\d+)% - (.+)</regex>
  <order>battery_level, battery_state</order>
</decoder>
```

### 3. **Enterprise Security Rules for Mobile Threat Detection**

Create `/var/ossec/etc/rules/mhf_log_shield_rules.xml`:

```xml
<group name="mhf_log_shield,siem,mobile_security,">
  
  <!-- Base Rule - All MHF Log Shield Events -->
  <rule id="100000" level="3">
    <decoded_as>mhf-syslog</decoded_as>
    <description>MHF Log Shield: $(message)</description>
    <group>mhf_log_shield,siem</group>
  </rule>
  
  <!-- CRITICAL: Security Threat Detection -->
  <rule id="100001" level="12" frequency="5" timeframe="300">
    <if_sid>100000</if_sid>
    <match>(malware|trojan|ransomware|spyware|exploit|backdoor|rootkit|unauthorized)</match>
    <description>CRITICAL: Potential Mobile Security Threat - $(message)</description>
    <group>mhf_log_shield,security_threat,critical</group>
  </rule>
  
  <!-- HIGH: App Installation Events -->
  <rule id="100002" level="8">
    <decoded_as>mhf-app-event</decoded_as>
    <field name="event_type">INSTALLED</field>
    <description>HIGH: Mobile App Installation - $(app_name) (v$(version))</description>
    <options>alert_by_email</options>
    <group>mhf_log_shield,software_added,change_control</group>
  </rule>
  
  <!-- HIGH: App Uninstallation Events -->
  <rule id="100003" level="8">
    <decoded_as>mhf-app-event</decoded_as>
    <field name="event_type">UNINSTALLED</field>
    <description>HIGH: Mobile App Uninstallation - $(app_name)</description>
    <options>alert_by_email</options>
    <group>mhf_log_shield,software_removed,change_control</group>
  </rule>
  
  <!-- MEDIUM: App Update Events -->
  <rule id="100004" level="7">
    <decoded_as>mhf-app-event</decoded_as>
    <field name="event_type">UPDATED</field>
    <description>MEDIUM: Mobile App Update - $(app_name) updated to v$(version)</description>
    <group>mhf_log_shield,software_updated,patch_management</group>
  </rule>
  
  <!-- MEDIUM: App Foreground/Background State Changes -->
  <rule id="100005" level="6">
    <decoded_as>mhf-app-state</decoded_as>
    <field name="app_state">FOREGROUND</field>
    <description>MEDIUM: App Moved to Foreground</description>
    <group>mhf_log_shield,application_state,user_activity</group>
  </rule>
  
  <rule id="100006" level="6">
    <decoded_as>mhf-app-state</decoded_as>
    <field name="app_state">BACKGROUND</field>
    <description>MEDIUM: App Moved to Background</description>
    <group>mhf_log_shield,application_state,user_activity</group>
  </rule>
  
  <!-- MEDIUM: Network Connectivity Changes -->
  <rule id="100007" level="5">
    <decoded_as>mhf-network-change</decoded-as>
    <description>MEDIUM: Network State Changed - $(network_state)</description>
    <group>mhf_log_shield,network,connectivity</group>
  </rule>
  
  <!-- MEDIUM: Connection to Untrusted Networks -->
  <rule id="100008" level="7">
    <if_sid>100007</if_sid>
    <match>(Public WiFi|Open Network|Hotspot)</match>
    <description>HIGH: Device Connected to Untrusted Network</description>
    <group>mhf_log_shield,network,security_risk</group>
  </rule>
  
  <!-- LOW: Battery Status Monitoring -->
  <rule id="100009" level="3">
    <decoded_as>mhf-battery-status</decoded_as>
    <description>LOW: Battery Status - $(battery_level)% ($(battery_state))</description>
    <group>mhf_log_shield,device_status,battery</group>
  </rule>
  
  <!-- HIGH: Critical Battery Level -->
  <rule id="100010" level="8">
    <if_sid>100009</if_sid>
    <field name="battery_level" type="pcre2">^[0-5]$</field>
    <description>CRITICAL: Battery Critically Low ($(battery_level)%) - Device may shut down</description>
    <options>alert_by_email</options>
    <group>mhf_log_shield,device_status,critical,battery</group>
  </rule>
  
  <!-- MEDIUM: Low Battery Warning -->
  <rule id="100011" level="6">
    <if_sid>100009</if_sid>
    <field name="battery_level" type="pcre2">^[6-9]$|^1[0-9]$</field>
    <description>MEDIUM: Battery Low ($(battery_level)%)</description>
    <group>mhf_log_shield,device_status,warning,battery</group>
  </rule>
  
  <!-- LOW: Periodic Device Status -->
  <rule id="100012" level="2">
    <decoded_as>mhf-device-status</decoded_as>
    <description>LOW: Periodic Device Status - $(platform), $(app_count) apps, $(battery_level)% battery, $(network_type)</description>
    <group>mhf_log_shield,device_status,periodic</group>
  </rule>
  
  <!-- HIGH: Application Error Events -->
  <rule id="100013" level="9">
    <if_sid>100000</if_sid>
    <match>ERROR:</match>
    <description>HIGH: Application Error Detected</description>
    <group>mhf_log_shield,application_error</group>
  </rule>
  
  <!-- MEDIUM: Application Warning Events -->
  <rule id="100014" level="5">
    <if_sid>100000</if_sid>
    <match>WARNING:</match>
    <description>MEDIUM: Application Warning</description>
    <group>mhf_log_shield,application_warning</group>
  </rule>
  
  <!-- SECURITY: Suspicious App Installation Pattern -->
  <rule id="100015" level="10" frequency="3" timeframe="3600">
    <if_matched_sid>100002</if_matched_sid>
    <same_source_ip />
    <description>SECURITY: Multiple App Installations Detected (Potential Malware)</description>
    <group>mhf_log_shield,security_threat,suspicious_behavior</group>
  </rule>
  
  <!-- SECURITY: Rapid App Uninstall Pattern -->
  <rule id="100016" level="10" frequency="5" timeframe="1800">
    <if_matched_sid>100003</if_matched_sid>
    <same_source_ip />
    <description>SECURITY: Rapid App Uninstallations Detected</description>
    <group>mhf_log_shield,security_threat,suspicious_behavior</group>
  </rule>
  
  <!-- COMPLIANCE: Device Inventory Report -->
  <rule id="100017" level="2">
    <if_sid>100000</if_sid>
    <match>App Inventory</match>
    <description>COMPLIANCE: Device Application Inventory Report</description>
    <group>mhf_log_shield,compliance,inventory</group>
  </rule>
  
  <!-- SECURITY: After-Hours Activity -->
  <rule id="100018" level="7">
    <if_sid>100000</if_sid>
    <time>20:00-08:00</time>
    <weekday>saturday,sunday</weekday>
    <description>SECURITY: After-Hours Mobile Device Activity Detected</description>
    <group>mhf_log_shield,security_threat,after_hours</group>
  </rule>
  
</group>
```

### 4. **Active Response Configuration for Critical Events**

Add to `/var/ossec/etc/ossec.conf`:

```xml
<ossec_config>
  <!-- Active Response for Critical Security Events -->
  <command>
    <name>mobile-threat-alert</name>
    <executable>mobile-threat-alert.sh</executable>
    <expect></expect>
    <timeout_allowed>no</timeout_allowed>
  </command>
  
  <command>
    <name>slack-mobile-alert</name>
    <executable>slack-mobile-alert.sh</executable>
    <expect></expect>
    <timeout_allowed>no</timeout_allowed>
  </command>
  
  <active-response>
    <disabled>no</disabled>
    <command>mobile-threat-alert</command>
    <location>local</location>
    <level>10</level>
    <timeout>600</timeout>
  </active-response>
  
  <active-response>
    <disabled>no</disabled>
    <command>slack-mobile-alert</command>
    <location>local</location>
    <level>8</level>
    <timeout>300</timeout>
  </active-response>
</ossec_config>
```

### 5. **Deploy and Restart Wazuh Services**

```bash
# Copy configuration files
sudo cp mhf_log_shield_decoder.xml /var/ossec/etc/decoders/
sudo cp mhf_log_shield_rules.xml /var/ossec/etc/rules/

# Set proper permissions
sudo chown root:wazuh /var/ossec/etc/decoders/mhf_log_shield_decoder.xml
sudo chown root:wazuh /var/ossec/etc/rules/mhf_log_shield_rules.xml
sudo chmod 640 /var/ossec/etc/decoders/mhf_log_shield_decoder.xml
sudo chmod 640 /var/ossec/etc/rules/mhf_log_shield_rules.xml

# Restart Wazuh manager
sudo systemctl restart wazuh-manager

# Verify service status
sudo systemctl status wazuh-manager

# Monitor deployment
sudo tail -f /var/ossec/logs/ossec.log | grep -E "(ERROR|WARNING|mhf)"

# Verify rules are loaded
sudo /var/ossec/bin/wazuh-logtest
# Enter a test MHF log to verify parsing
```

## 📱 Mobile App Enterprise Deployment

### Android Enterprise Deployment
1. **Build for Distribution:**
   ```bash
   flutter build appbundle --release --obfuscate --split-debug-info=./debug-info/
   ```

2. **Google Play Console:**
   - Upload app bundle
   - Configure internal/alpha/beta testing
   - Set up managed Google Play for enterprise
   - Configure app restrictions and policies

3. **MDM Integration:**
   - Available for Microsoft Intune, VMware Workspace ONE, MobileIron
   - Configure app configuration policies
   - Set up automatic deployment

### iOS Enterprise Deployment
1. **Build for Distribution:**
   ```bash
   flutter build ios --release --no-codesign
   ```

2. **Apple Business Manager:**
   - Enroll devices in Apple Business Manager
   - Distribute via App Store (VPP)
   - Configure managed app configuration

3. **MDM Payload:**
   ```xml
   <dict>
     <key>ServerURL</key>
     <string>https://wazuh.yourcompany.com:55000</string>
     <key>AutoStartMonitoring</key>
     <true/>
     <key>RequireAuthentication</key>
     <true/>
   </dict>
   ```

### Zero-Touch Configuration
The app supports automatic configuration via:
- Android Enterprise managed configuration
- iOS managed app configuration
- QR code provisioning
- Deep linking with configuration parameters

## 🔍 Enterprise Monitoring & Verification

### Centralized Log Verification
```bash
# Real-time monitoring of mobile events
sudo tail -f /var/ossec/logs/alerts/alerts.log | grep "Rule: 100" | jq '.'

# Daily summary report
sudo grep "mhf_log_shield" /var/ossec/logs/alerts/alerts.log | \
  awk -F',' '{print $4}' | sort | uniq -c | sort -rn

# Export to SIEM/SOAR
# Configure Wazuh to forward alerts to:
# - Splunk
# - QRadar
# - ArcSight
# - Elastic Stack
```

### Performance Monitoring
```bash
# Monitor UDP packet reception
sudo tcpdump -i any port 514 -n -c 100

# Check syslog queue
sudo netstat -su | grep "packet receive errors"

# Monitor Wazuh agent connection health
sudo /var/ossec/bin/wazuh-control status
```

### Security Dashboard Configuration
Create a dedicated Wazuh dashboard for mobile security:

1. **Kibana/OpenSearch Dashboard:**
   - Mobile Device Overview
   - App Installation Trends
   - Network Security Map
   - Battery Health Monitoring
   - Compliance Reports

2. **Alert Thresholds:**
   - App installs > 5/hour = Warning
   - Battery < 10% = Critical
   - Unknown network = High Alert
   - After-hours activity = Medium Alert

## 🐛 Enterprise Troubleshooting

### No Logs Received
```bash
# Comprehensive connectivity check
sudo nmap -sU -p 514 WAZUH_SERVER_IP
sudo nmap -sT -p 55000 WAZUH_SERVER_IP

# Firewall verification
sudo iptables -L -n -v | grep -E "(514|55000)"
sudo ufw status numbered

# Network capture (debug)
sudo tcpdump -i any port 514 -vvv -X

# Wazuh debug mode
sudo /var/ossec/bin/wazuh-logtest -d 2
```

### Performance Issues
```bash
# Check system resources
top -b -n 1 | grep wazuh
free -h

# Monitor disk I/O
iostat -x 1 10

# Check log rotation
ls -la /var/ossec/logs/archives/
du -sh /var/ossec/logs/
```

### Mobile Device Issues

**Android:**
```bash
# ADB debugging
adb logcat | grep MHFLogShield
adb shell dumpsys package | grep mhf

# Permission verification
adb shell pm list permissions | grep -i usage
```

**iOS:**
- Check Console.app for app logs
- Verify network permissions in Settings
- Test with Charles Proxy for network debugging

## 📊 Enterprise Log Format & Examples

### Standardized Log Format (RFC3164 + Extended Fields)
```
<Priority>Timestamp Hostname Program[PID]: Level: Structured_Message

Example:
<13>2024-01-15T14:30:45Z mobile-android-001 MHFLogShield[1000]: INFO: 
{
  "event_type": "app_installed",
  "app_name": "SalesForce",
  "package": "com.salesforce.chatter",
  "version": "8.2.1",
  "risk_score": 2,
  "compliance": {"gdpr": true, "hipaa": false}
}
```

### Event Categories & Severity

| Category | Level | Example | Alert Action |
|----------|-------|---------|--------------|
| Security Threat | 12 | Malware detected | Email, SMS, SIEM |
| App Installation | 8 | New app installed | Email, Dashboard |
| Network Change | 5 | WiFi to Cellular | Dashboard |
| Battery Status | 3 | 45% charging | Log only |
| Heartbeat | 2 | Periodic status | Log only |

## 🔧 Development & Maintenance

### CI/CD Pipeline (GitLab Example)
```yaml
stages:
  - test
  - build
  - deploy
  
variables:
  FLUTTER_VERSION: "3.16.0"
  
test:
  stage: test
  script:
    - flutter analyze
    - flutter test --coverage
    - genhtml coverage/lcov.info -o coverage_report
    
build-android:
  stage: build
  script:
    - flutter build appbundle --release
  artifacts:
    paths:
      - build/app/outputs/bundle/release/app-release.aab
    
build-ios:
  stage: build
  script:
    - flutter build ios --release --no-codesign
  only:
    - tags
```

### Security Hardening Checklist
- [x] Code obfuscation enabled
- [x] SSL pinning for REST API
- [x] Biometric authentication option
- [x] Data encryption at rest
- [x] Certificate validation
- [x] Input sanitization
- [x] Secure storage for credentials
- [x] Regular dependency updates

### Compliance Requirements
- **GDPR**: User consent, data minimization, right to delete
- **HIPAA**: PHI protection, audit trails, access controls  
- **PCI-DSS**: PAN protection, secure transmission, logging
- **SOC2**: Security, availability, confidentiality

## 📄 License & Compliance

**License:** MIT License - See [LICENSE](LICENSE) file for details.

**Compliance Statements:**
- This tool is for authorized security monitoring only
- User consent required before deployment
- Data retention policies must be established
- Regular security assessments required

**Data Protection:**
- All transmitted data is encrypted
- Local storage is encrypted
- No personal data collected without consent
- Automatic data purging based on policy

## 🤝 Enterprise Support

### Support Channels
- **Email:** fmahadybd@gmail.com

### Service Level Agreement (SLA)
- **Availability:** 99.9%
- **Response Time:** Critical - 15 min, High - 1 hour, Medium - 4 hours
- **Resolution Time:** Based on severity level


### Training & Documentation
- Administrator training sessions
- User awareness programs
- Monthly security briefings
- Quarterly compliance reviews

---

**Version:** 2.0.0  
**Last Updated:** January 2026  
**Supported Platforms:** Android 8.0+, iOS 13.0+  
**Wazuh Compatibility:** 4.4.0+  
**Flutter Version:** 3.16.0+  

