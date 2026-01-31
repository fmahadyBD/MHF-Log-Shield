import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/services.dart';
import '../../core/interfaces/platform_services.dart';
import '../../data/repositories/settings_repository.dart';

class AndroidPlatformServices implements PlatformServices {
  static const MethodChannel _channel = MethodChannel('app_monitor_channel');
  static const MethodChannel _advancedChannel = MethodChannel('advanced_monitor_channel');
  final SettingsRepository _settings = SettingsRepository();
  
  @override
  Future<void> startAllMonitoring() async {
    print('Android: Starting all monitoring services');
    
    // Start foreground service first
    await startForegroundService();
    
    // Start monitoring service
    await _advancedChannel.invokeMethod('startMonitoringService');
    
    // Send initial log
    await sendToWazuh('SYSTEM', 'Android monitoring started - All services running');
    
    print('Android: All monitoring services started');
  }
  
  @override
  Future<void> stopAllMonitoring() async {
    print('Android: Stopping all monitoring services');
    
    await _advancedChannel.invokeMethod('stopMonitoringService');
    await stopForegroundService();
    
    await sendToWazuh('SYSTEM', 'Android monitoring stopped - All services stopped');
    
    print('Android: All monitoring services stopped');
  }
  
  @override
  Future<void> startAppInstallMonitoring() async {
    print('Android: Starting app install monitoring');
    await _channel.invokeMethod('startForegroundService');
  }
  
  @override
  Future<void> stopAppInstallMonitoring() async {
    print('Android: Stopping app install monitoring');
    await _channel.invokeMethod('stopForegroundService');
  }
  
  @override
  Future<String> getInstallSource(String packageName) async {
    try {
      final result = await _channel.invokeMethod(
        'getInstallSource',
        {'packageName': packageName},
      );
      return result as String? ?? 'Unknown';
    } catch (e) {
      print('Error getting install source: $e');
      return 'Error: $e';
    }
  }
  
  @override
  Future<void> startScreenMonitoring() async {
    print('Android: Starting screen monitoring');
    // Screen monitoring is handled by native receivers
    // Just ensure monitoring service is running
    await _advancedChannel.invokeMethod('startMonitoringService');
  }
  
  @override
  Future<void> stopScreenMonitoring() async {
    print('Android: Stopping screen monitoring');
    await _advancedChannel.invokeMethod('stopMonitoringService');
  }
  
  @override
  Future<void> startPowerMonitoring() async {
    print('Android: Starting power monitoring');
    // Power monitoring is handled by native receivers
    await startForegroundService();
  }
  
  @override
  Future<void> stopPowerMonitoring() async {
    print('Android: Stopping power monitoring');
    await stopForegroundService();
  }
  
  @override
  Future<void> startNetworkMonitoring() async {
    print('Android: Starting network monitoring');
    await _advancedChannel.invokeMethod('startMonitoringService');
  }
  
  @override
  Future<void> stopNetworkMonitoring() async {
    print('Android: Stopping network monitoring');
    await _advancedChannel.invokeMethod('stopMonitoringService');
  }
  
  @override
  Future<void> startForegroundService() async {
    print('Android: Starting foreground service');
    try {
      await _channel.invokeMethod('startForegroundService');
      print('Android: Foreground service started');
    } catch (e) {
      print('Error starting foreground service: $e');
      rethrow;
    }
  }
  
  @override
  Future<void> stopForegroundService() async {
    print('Android: Stopping foreground service');
    try {
      await _channel.invokeMethod('stopForegroundService');
      print('Android: Foreground service stopped');
    } catch (e) {
      print('Error stopping foreground service: $e');
    }
  }
  
  @override
  Future<void> startBackgroundMonitoring() async {
    print('Android: Starting background monitoring');
    await _advancedChannel.invokeMethod('startMonitoringService');
  }
  
  @override
  Future<void> stopBackgroundMonitoring() async {
    print('Android: Stopping background monitoring');
    await _advancedChannel.invokeMethod('stopMonitoringService');
  }
  
  @override
  Future<bool> checkAllPermissions() async {
    try {
      final result = await _channel.invokeMethod('checkPermissions');
      return result as bool? ?? false;
    } catch (e) {
      print('Error checking permissions: $e');
      return false;
    }
  }
  
  @override
  Future<void> requestAllPermissions() async {
    try {
      await _channel.invokeMethod('checkAndRequestAllPermissions');
      print('Android: Permission request sent');
    } catch (e) {
      print('Error requesting permissions: $e');
    }
  }
  
  @override
  Future<bool> hasUsageStatsPermission() async {
    try {
      final result = await _channel.invokeMethod('hasUsageStatsPermission');
      return result as bool? ?? false;
    } catch (e) {
      print('Error checking usage stats permission: $e');
      return false;
    }
  }
  
  @override
  Future<void> requestUsageStatsPermission() async {
    try {
      await _channel.invokeMethod('requestUsageStatsPermission');
      print('Android: Usage stats permission request sent');
    } catch (e) {
      print('Error requesting usage stats permission: $e');
    }
  }
  
  @override
  Future<void> sendToWazuh(String eventType, String message) async {
    // Use native WazuhSender for Android
    try {
      // Save server URL if not already saved
      await _settings.initialize();
      final serverUrl = _settings.getServerUrl();
      if (serverUrl.isNotEmpty) {
        await saveServerUrl(serverUrl);
      }
      
      // Trigger test via native
      if (eventType == 'TEST_EVENT') {
        await _advancedChannel.invokeMethod('triggerTestEvent');
      } else {
        // Send via your existing WazuhSender implementation
        print('Android: Would send to Wazuh via native: $eventType - $message');
      }
    } catch (e) {
      print('Error sending to Wazuh: $e');
    }
  }
  
  @override
  Future<void> sendTestEvent() async {
    print('Android: Sending test event');
    await _advancedChannel.invokeMethod('triggerTestEvent');
  }
  
  @override
  Future<Map<String, dynamic>> getMonitoringStats() async {
    try {
      final stats = await _advancedChannel.invokeMethod('getMonitoringStats');
      return Map<String, dynamic>.from(stats ?? {});
    } catch (e) {
      print('Error getting monitoring stats: $e');
      return {'error': e.toString()};
    }
  }
  
  @override
  Future<Map<String, dynamic>> getMonitoringData() async {
    try {
      final data = await _advancedChannel.invokeMethod('getMonitoringData');
      return Map<String, dynamic>.from(data ?? {});
    } catch (e) {
      print('Error getting monitoring data: $e');
      return {'error': e.toString()};
    }
  }
  
  @override
  Future<Map<String, int>> getPendingEventsCount() async {
    try {
      final counts = await _advancedChannel.invokeMethod('getPendingEventsCount');
      return Map<String, int>.from(counts ?? {});
    } catch (e) {
      print('Error getting pending events count: $e');
      return {};
    }
  }
  
  @override
  Future<void> clearMonitoringData() async {
    try {
      await _advancedChannel.invokeMethod('clearMonitoringData');
      print('Android: Monitoring data cleared');
    } catch (e) {
      print('Error clearing monitoring data: $e');
    }
  }
  
  @override
  Future<void> saveServerUrl(String serverUrl) async {
    try {
      await _channel.invokeMethod('saveServerUrl', {'url': serverUrl});
      print('Android: Server URL saved for native components: $serverUrl');
    } catch (e) {
      print('Error saving server URL: $e');
    }
  }
  
  @override
  Future<Map<String, dynamic>> getServerUrlStatus() async {
    try {
      final status = await _channel.invokeMethod('getServerUrlStatus');
      return Map<String, dynamic>.from(status ?? {});
    } catch (e) {
      print('Error getting server URL status: $e');
      return {'error': e.toString()};
    }
  }
  
  @override
  Future<void> testWazuhConnection() async {
    try {
      await _channel.invokeMethod('testWazuhConnection');
      print('Android: Wazuh connection test initiated');
    } catch (e) {
      print('Error testing Wazuh connection: $e');
    }
  }
  
  @override
  Future<void> setMonitoringInterval(int seconds) async {
    try {
      await _advancedChannel.invokeMethod('setMonitoringInterval', {'seconds': seconds});
      print('Android: Monitoring interval set to $seconds seconds');
    } catch (e) {
      print('Error setting monitoring interval: $e');
    }
  }
  
  @override
  String getPlatformName() => 'Android';
  
  @override
  bool canMonitorAppInstalls() => true;
  
  @override
  bool canMonitorScreenState() => true;
  
  @override
  bool canMonitorPower() => true;
  
  @override
  bool canMonitorNetwork() => true;
  
  @override
  bool canRunForegroundService() => true;
  
  @override
  bool canRunBackgroundTasks() => true;
  
  @override
  bool hasNativeAppInstallReceiver() => true;
  
  @override
  bool hasNativeScreenReceiver() => true;
  
  @override
  bool hasNativePowerReceiver() => true;
  
  @override
  bool hasNativeBootReceiver() => true;
  
  @override
  Future<Map<String, dynamic>> getDeviceInfo() async {
    try {
      // Use device_info_plus package
      final deviceInfoPlugin = await DeviceInfoPlugin();
      final androidInfo = await deviceInfoPlugin.androidInfo;
      
      return {
        'platform': 'Android',
        'model': androidInfo.model,
        'brand': androidInfo.brand,
        'device': androidInfo.device,
        'android_version': androidInfo.version.release,
        'sdk_version': androidInfo.version.sdkInt,
        'manufacturer': androidInfo.manufacturer,
        'is_physical_device': androidInfo.isPhysicalDevice,
      };
    } catch (e) {
      print('Error getting Android device info: $e');
      return {'platform': 'Android', 'error': e.toString()};
    }
  }
}