

# 🛡️ MHF Log Shield - Mobile Log Collector for Wazuh

A real-time log collection application that sends device and application logs to a Wazuh SIEM server. Supports both Android and iOS platforms.

## 📱 Features

- **Cross-platform** - Works on Android & iOS
- **Real-time monitoring** - Device status, app installations, network changes
- **Wazuh Integration** - UDP and REST API support
- **Offline storage** - Stores logs when offline, sends when connected
- **Background monitoring** - Works even when app is closed

## 🏗️ Build the App

### Debug Build (Testing)
```bash
flutter clean
flutter pub get
flutter build apk --debug
```

### Release Build (Production)
```bash
flutter clean
flutter pub get
flutter build apk --release
```

### iOS Build (Mac Only)
```bash
flutter build ios --release
# Then open ios/Runner.xcworkspace in Xcode for signing
```

## 📡 Wazuh Server Configuration

### 1. **Configure Wazuh Manager to Receive Logs**

Edit `/var/ossec/etc/ossec.conf` on your Wazuh server:

```xml
<ossec_config>
  <!-- Add remote syslog reception -->
  <remote>
    <connection>syslog</connection>
    <port>514</port>
    <protocol>udp</protocol>
    <allowed-ips>0.0.0.0/0</allowed-ips>  <!-- Or restrict to your network -->
  </remote>
  
  <!-- Optional: Enable REST API for iOS/advanced use -->
  <remote>
    <connection>secure</connection>
    <port>55000</port>
    <protocol>tcp</protocol>
    <allowed-ips>0.0.0.0/0</allowed-ips>
  </remote>
</ossec_config>
```

### 2. **Add Custom Decoder**

Create or edit `/var/ossec/etc/decoders/local_decoder.xml`:

```xml
<decoder name="mhf-log-shield">
  <prematch>MHFLogShield</prematch>
  <regex>MHFLogShield\[(\d+)\]:\s+(\w+):\s+(.+)$</regex>
  <order>pid, level, message</order>
</decoder>

<decoder name="mhf-app-event">
  <prematch>📱 APP</prematch>
  <regex>📱 APP (\w+)\s*\n• Name: (.+)\n• Package: (.+)\n• Type: (.+)\n• Version: (.+)\n• Source: (.+)</regex>
  <order>event_type, app_name, package, app_type, version, source</order>
</decoder>

<decoder name="mhf-device-status">
  <prematch>📱 Status Update</prematch>
  <regex>📱 Status Update \| Platform: (\w+) \| Apps: (\d+) \| Battery: (\d+)% \| Network: (.+)</regex>
  <order>platform, app_count, battery, network</order>
</decoder>
```

### 3. **Add Custom Rules**

Edit `/var/ossec/etc/rules/local_rules.xml`:

```xml
<group name="mhf_log_shield,">
  <!-- General MHF Log Shield messages -->
  <rule id="100000" level="3">
    <decoded_as>mhf-log-shield</decoded_as>
    <description>MHF Log Shield: $(message)</description>
  </rule>
  
  <!-- App installation events -->
  <rule id="100001" level="5">
    <decoded_as>mhf-app-event</decoded_as>
    <field name="event_type">INSTALLED</field>
    <description>MHF: App installed - $(app_name) (v$(version))</description>
  </rule>
  
  <!-- App update events -->
  <rule id="100002" level="4">
    <decoded_as>mhf-app-event</decoded_as>
    <field name="event_type">UPDATED</field>
    <description>MHF: App updated - $(app_name) to v$(version)</description>
  </rule>
  
  <!-- App uninstall events -->
  <rule id="100003" level="5">
    <decoded_as>mhf-app-event</decoded_as>
    <field name="event_type">UNINSTALLED</field>
    <description>MHF: App uninstalled - $(app_name)</description>
  </rule>
  
  <!-- Device status updates -->
  <rule id="100004" level="2">
    <decoded_as>mhf-device-status</decoded_as>
    <description>MHF: Device status - $(platform), $(app_count) apps, $(battery)% battery, $(network)</description>
  </rule>
  
  <!-- Error messages -->
  <rule id="100005" level="8">
    <match>MHFLogShield.*ERROR</match>
    <description>MHF Log Shield ERROR: $(message)</description>
  </rule>
  
  <!-- Warning messages -->
  <rule id="100006" level="4">
    <match>MHFLogShield.*WARNING</match>
    <description>MHF Log Shield WARNING: $(message)</description>
  </rule>
  
  <!-- Critical battery level -->
  <rule id="100007" level="6">
    <if_sid>100004</if_sid>
    <field name="battery" type="pcre2">^[0-9]$|^1[0-4]$</field>
    <description>CRITICAL: Device battery low ($(battery)%)</description>
  </rule>
</group>
```

### 4. **Restart Wazuh Services**

```bash
# Restart Wazuh manager
systemctl restart wazuh-manager

# Check service status
systemctl status wazuh-manager

# Check logs for errors
tail -f /var/ossec/logs/ossec.log
```

## 📱 Mobile App Setup

### Android Configuration
1. Install the APK on Android device
2. Open the app and go to Settings
3. Enter Wazuh server IP: `192.168.x.x:514` (UDP) or `192.168.x.x:55000` (REST API)
4. Enable log collection
5. Grant required permissions when prompted

### iOS Configuration
1. Build and install via Xcode or TestFlight
2. Enter Wazuh server details
3. **Note**: iOS works better with REST API mode (port 55000)

## 🔍 Monitoring & Verification

### Check Logs on Wazuh Server

```bash
# Monitor incoming logs in real-time
sudo tail -f /var/ossec/logs/archives/archives.log | grep MHF

# Check alerts
sudo tail -f /var/ossec/logs/alerts/alerts.log | grep "Rule: 1000"

# Verify remote configuration
sudo netstat -tulpn | grep 514
sudo netstat -tulpn | grep 55000
```

### Test Connection from Mobile
1. In app: Click "Test Connection"
2. Check Wazuh server logs for test message
3. Verify alerts appear in Wazuh dashboard

## 🐛 Troubleshooting

### No Logs Received
```bash
# Check firewall rules
sudo ufw status
sudo ufw allow 514/udp
sudo ufw allow 55000/tcp

# Verify Wazuh is listening
sudo netstat -tulpn | grep -E '(514|55000)'

# Check Wazuh logs
tail -f /var/ossec/logs/ossec.log

# Test from another machine
echo "Test message" | nc -u WAZUH_IP 514
```

### Android Permission Issues
- Ensure app has "Usage Access" permission enabled
- Check "Allow background activity" is enabled
- Verify device not in battery saving mode

### iOS Network Issues
- Add `NSAppTransportSecurity` to Info.plist
- Use REST API mode (port 55000) instead of UDP
- Ensure local network permission is granted

## 📊 Log Format Examples

### App Installation
```
<13>2024-01-15T10:30:45Z mobile-device MHFLogShield[1000]: INFO: 📱 APP INSTALLED
• Name: WhatsApp
• Package: com.whatsapp
• Type: User App
• Version: 2.23.25.84 (123456)
• Source: Google Play Store
```

### Device Status
```
<13>2024-01-15T10:35:00Z mobile-device MHFLogShield[1000]: INFO: 📱 Status Update | Platform: Android | Apps: 45 | Battery: 78% | Network: WiFi
```

### Test Message
```
<13>2024-01-15T10:40:00Z mobile-device MHFLogShield[1000]: INFO: Test log from MHF Log Shield mobile application
```

## 🔧 Development

### Project Structure
```
mhf_log_shield/
├── lib/                    # Dart/Flutter code
│   ├── core/              # Platform interfaces
│   ├── data/              # Repositories
│   ├── services/          # Monitoring services
│   ├── ui/                # Screens & widgets
│   └── utils/             # Utilities
├── android/               # Android native code
├── ios/                   # iOS native code
└── pubspec.yaml          # Dependencies
```

### Dependencies
```yaml
# Key packages:
- device_info_plus     # Device information
- connectivity_plus    # Network monitoring
- battery_plus        # Battery status
- device_apps         # App monitoring (Android)
- workmanager         # Background tasks
- shared_preferences  # Local storage
```

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Commit your changes
4. Push to the branch
5. Create a Pull Request

## ⚠️ Disclaimer

This tool is for legitimate security monitoring and compliance purposes only. Ensure you have proper authorization before monitoring any device.

---
