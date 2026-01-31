# mhf_log_shield
This is a real-time log collection application that sends logs to a Wazuh server.

## Build the App

### Debug Build
```bash
flutter clean
flutter pub get
flutter build apk --debug
```

### Release Build
```bash
flutter clean
flutter pub get
flutter build apk --release
```

## Android Setup for Wazuh

### Server Configuration
* Configure the Wazuh server with port 514 for log reception
* Ensure the Android device and Wazuh server are on the same network
* The Wazuh server IP should be correctly configured in the app

### Monitoring Logs
* Check TCP dump in the Wazuh terminal to verify logs are being received
* Logs will appear in the Wazuh dashboard after successful configuration

## Wazuh Local Rules Configuration

Add the following configuration to your Wazuh `local_rules.xml` file:

```xml
<group name="mhf_log_shield">
  <rule id="100000" level="3">
    <match>MHFLogShield</match>
    <description>MHF Log Shield app message</description>
  </rule>
  
  <rule id="100001" level="5">
    <match>MHFLogShield.*ERROR</match>
    <description>MHF Log Shield error message</description>
  </rule>
</group>
```