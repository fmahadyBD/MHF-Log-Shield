import 'dart:io';
import 'package:flutter/services.dart';
import 'package:device_info_plus/device_info_plus.dart';
import '../../core/interfaces/platform_services.dart';
import '../../data/repositories/settings_repository.dart';

class IosPlatformServices implements PlatformServices {
  static const MethodChannel _channel = MethodChannel('ios_monitor_channel');
  final SettingsRepository _settings = SettingsRepository();
  final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();
  
  @override
  Future<void> startAllMonitoring() async {
    print('iOS: Starting all available monitoring');
    
    // iOS has limited monitoring capabilities
    await startNetworkMonitoring();
    await startPowerMonitoring();
    
    // Start background task if needed
    await startBackgroundMonitoring();
    
    await sendToWazuh('SYSTEM', 'iOS monitoring started - Limited capabilities');
    
    print('iOS: Available monitoring started');
  }
  
  @override
  Future<void> stopAllMonitoring() async {
    print('iOS: Stopping all monitoring');
    
    await stopBackgroundMonitoring();
    
    await sendToWazuh('SYSTEM', 'iOS monitoring stopped');
    
    print('iOS: All monitoring stopped');
  }
  
  @override
  Future<void> startAppInstallMonitoring() async {
    print('⚠️ iOS: App install monitoring not supported (Apple restriction)');
    // iOS cannot monitor app installs due to privacy restrictions
  }
  
  @override
  Future<void> stopAppInstallMonitoring() async {
    // Nothing to stop
  }
  
  @override
  Future<String> getInstallSource(String packageName) async {
    return 'iOS App Store'; // iOS apps only come from App Store (or TestFlight)
  }
  
  @override
  Future<void> startScreenMonitoring() async {
    print('⚠️ iOS: Screen state monitoring has limited capabilities');
    // iOS can detect some screen events but not as comprehensively as Android
    try {
      await _channel.invokeMethod('startScreenMonitoring');
      print('iOS: Limited screen monitoring started');
    } catch (e) {
      print('iOS: Screen monitoring not available: $e');
    }
  }
  
  @override
  Future<void> stopScreenMonitoring() async {
    try {
      await _channel.invokeMethod('stopScreenMonitoring');
      print('iOS: Screen monitoring stopped');
    } catch (e) {
      print('Error stopping screen monitoring: $e');
    }
  }
  
  @override
  Future<void> startPowerMonitoring() async {
    print('iOS: Starting power monitoring');
    try {
      await _channel.invokeMethod('startPowerMonitoring');
      print('iOS: Power monitoring started');
    } catch (e) {
      print('iOS: Power monitoring not available: $e');
    }
  }
  
  @override
  Future<void> stopPowerMonitoring() async {
    try {
      await _channel.invokeMethod('stopPowerMonitoring');
      print('iOS: Power monitoring stopped');
    } catch (e) {
      print('Error stopping power monitoring: $e');
    }
  }
  
  @override
  Future<void> startNetworkMonitoring() async {
    print('iOS: Starting network monitoring');
    try {
      await _channel.invokeMethod('startNetworkMonitoring');
      print('iOS: Network monitoring started');
    } catch (e) {
      print('iOS: Network monitoring not available: $e');
    }
  }
  
  @override
  Future<void> stopNetworkMonitoring() async {
    try {
      await _channel.invokeMethod('stopNetworkMonitoring');
      print('iOS: Network monitoring stopped');
    } catch (e) {
      print('Error stopping network monitoring: $e');
    }
  }
  
  @override
  Future<void> startForegroundService() async {
    print('⚠️ iOS: Foreground services work differently (Background Modes)');
    try {
      await _channel.invokeMethod('startBackgroundTask');
      print('iOS: Background task started');
    } catch (e) {
      print('iOS: Background task not available: $e');
    }
  }
  
  @override
  Future<void> stopForegroundService() async {
    try {
      await _channel.invokeMethod('stopBackgroundTask');
      print('iOS: Background task stopped');
    } catch (e) {
      print('Error stopping background task: $e');
    }
  }
  
  @override
  Future<void> startBackgroundMonitoring() async {
    print('iOS: Starting background monitoring (limited)');
    try {
      await _channel.invokeMethod('startBackgroundMonitoring');
      print('iOS: Background monitoring started');
    } catch (e) {
      print('iOS: Background monitoring not available: $e');
    }
  }
  
  @override
  Future<void> stopBackgroundMonitoring() async {
    try {
      await _channel.invokeMethod('stopBackgroundMonitoring');
      print('iOS: Background monitoring stopped');
    } catch (e) {
      print('Error stopping background monitoring: $e');
    }
  }
  
  @override
  Future<bool> checkAllPermissions() async {
    try {
      final result = await _channel.invokeMethod('checkPermissions');
      return result as bool? ?? false;
    } catch (e) {
      print('Error checking iOS permissions: $e');
      return false;
    }
  }
  
  @override
  Future<void> requestAllPermissions() async {
    try {
      await _channel.invokeMethod('requestAllPermissions');
      print('iOS: Permission request sent');
    } catch (e) {
      print('Error requesting iOS permissions: $e');
    }
  }
  
  @override
  Future<bool> hasUsageStatsPermission() async {
    // iOS doesn't have "usage stats" permission like Android
    // App usage is very restricted on iOS
    return false;
  }
  
  @override
  Future<void> requestUsageStatsPermission() async {
    print('⚠️ iOS: App usage stats not available (Apple restriction)');
  }
  
  @override
  Future<void> sendToWazuh(String eventType, String message) async {
    // iOS sends logs via HTTP/REST API (UDP may not work well on iOS)
    try {
      await _settings.initialize();
      final serverUrl = _settings.getServerUrl();
      
      if (serverUrl.isEmpty) {
        print('iOS: Cannot send to Wazuh - server URL not configured');
        return;
      }
      
      // Use HTTP POST for iOS (more reliable)
      await _channel.invokeMethod('sendToWazuh', {
        'eventType': eventType,
        'message': message,
        'serverUrl': serverUrl,
      });
      
      print('iOS: Sent to Wazuh via HTTP: $eventType');
    } catch (e) {
      print('Error sending to Wazuh from iOS: $e');
    }
  }
  
  @override
  Future<void> sendTestEvent() async {
    print('iOS: Sending test event');
    await sendToWazuh('TEST_EVENT', 'Test from iOS device');
  }
  
  @override
  Future<Map<String, dynamic>> getMonitoringStats() async {
    try {
      final stats = await _channel.invokeMethod('getMonitoringStats');
      return Map<String, dynamic>.from(stats ?? {});
    } catch (e) {
      print('Error getting iOS monitoring stats: $e');
      return {
        'platform': 'iOS',
        'note': 'Limited monitoring capabilities',
        'can_monitor_app_installs': false,
        'can_monitor_screen': true,
        'can_monitor_power': true,
        'can_monitor_network': true,
      };
    }
  }
  
  @override
  Future<Map<String, dynamic>> getMonitoringData() async {
    try {
      final data = await _channel.invokeMethod('getMonitoringData');
      return Map<String, dynamic>.from(data ?? {});
    } catch (e) {
      print('Error getting iOS monitoring data: $e');
      return {
        'platform': 'iOS',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };
    }
  }
  
  @override
  Future<Map<String, int>> getPendingEventsCount() async {
    return {
      'app_events': 0,
      'screen_events': 0,
      'power_events': 0,
    };
  }
  
  @override
  Future<void> clearMonitoringData() async {
    print('iOS: Clearing monitoring data');
    try {
      await _channel.invokeMethod('clearMonitoringData');
    } catch (e) {
      print('Error clearing iOS monitoring data: $e');
    }
  }
  
  @override
  Future<void> saveServerUrl(String serverUrl) async {
    try {
      await _channel.invokeMethod('saveServerUrl', {'url': serverUrl});
      print('iOS: Server URL saved: $serverUrl');
    } catch (e) {
      print('Error saving server URL on iOS: $e');
    }
  }
  
  @override
  Future<Map<String, dynamic>> getServerUrlStatus() async {
    try {
      final status = await _channel.invokeMethod('getServerUrlStatus');
      return Map<String, dynamic>.from(status ?? {});
    } catch (e) {
      print('Error getting server URL status on iOS: $e');
      return {'platform': 'iOS', 'error': e.toString()};
    }
  }
  
  @override
  Future<void> testWazuhConnection() async {
    print('iOS: Testing Wazuh connection');
    await sendTestEvent();
  }
  
  @override
  Future<void> setMonitoringInterval(int seconds) async {
    print('iOS: Setting monitoring interval to $seconds seconds');
    try {
      await _channel.invokeMethod('setMonitoringInterval', {'seconds': seconds});
    } catch (e) {
      print('Error setting monitoring interval on iOS: $e');
    }
  }
  
  @override
  String getPlatformName() => 'iOS';
  
  @override
  bool canMonitorAppInstalls() => false; // Apple restriction
  
  @override
  bool canMonitorScreenState() => true; // Limited capability
  
  @override
  bool canMonitorPower() => true; // Can monitor battery
  
  @override
  bool canMonitorNetwork() => true; // Can monitor network
  
  @override
  bool canRunForegroundService() => false; // iOS uses Background Modes
  
  @override
  bool canRunBackgroundTasks() => true; // Limited background execution
  
  @override
  bool hasNativeAppInstallReceiver() => false; // Not allowed by Apple
  
  @override
  bool hasNativeScreenReceiver() => true; // Some screen events available
  
  @override
  bool hasNativePowerReceiver() => true; // Battery/power events available
  
  @override
  bool hasNativeBootReceiver() => false; // Limited boot monitoring
  
  @override
  Future<Map<String, dynamic>> getDeviceInfo() async {
    try {
      final iosInfo = await _deviceInfo.iosInfo;
      
      return {
        'platform': 'iOS',
        'name': iosInfo.name,
        'model': iosInfo.model,
        'system_name': iosInfo.systemName,
        'system_version': iosInfo.systemVersion,
        'utsname': {
          'sysname': iosInfo.utsname.sysname,
          'nodename': iosInfo.utsname.nodename,
          'release': iosInfo.utsname.release,
          'version': iosInfo.utsname.version,
          'machine': iosInfo.utsname.machine,
        },
        'is_physical_device': iosInfo.isPhysicalDevice,
      };
    } catch (e) {
      print('Error getting iOS device info: $e');
      return {'platform': 'iOS', 'error': e.toString()};
    }
  }
}