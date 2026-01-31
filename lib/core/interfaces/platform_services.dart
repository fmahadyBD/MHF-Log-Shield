import 'package:mhf_log_shield/data/repositories/settings_repository.dart';

abstract class PlatformServices {
  // Monitoring Control
  Future<void> startAllMonitoring();
  Future<void> stopAllMonitoring();
  
  // App Monitoring (Android only)
  Future<void> startAppInstallMonitoring();
  Future<void> stopAppInstallMonitoring();
  Future<String> getInstallSource(String packageName);
  
  // Device Monitoring (Cross-platform)
  Future<void> startScreenMonitoring();
  Future<void> stopScreenMonitoring();
  Future<void> startPowerMonitoring();
  Future<void> stopPowerMonitoring();
  Future<void> startNetworkMonitoring();
  Future<void> stopNetworkMonitoring();
  
  // Service Management
  Future<void> startForegroundService();
  Future<void> stopForegroundService();
  Future<void> startBackgroundMonitoring();
  Future<void> stopBackgroundMonitoring();
  
  // Permission Management
  Future<bool> checkAllPermissions();
  Future<void> requestAllPermissions();
  Future<bool> hasUsageStatsPermission();
  Future<void> requestUsageStatsPermission();
  
  // Log Sending
  Future<void> sendToWazuh(String eventType, String message);
  Future<void> sendTestEvent();
  
  // Monitoring Data
  Future<Map<String, dynamic>> getMonitoringStats();
  Future<Map<String, dynamic>> getMonitoringData();
  Future<Map<String, int>> getPendingEventsCount();
  Future<void> clearMonitoringData();
  
  // Server Configuration
  Future<void> saveServerUrl(String serverUrl);
  Future<Map<String, dynamic>> getServerUrlStatus();
  Future<void> testWazuhConnection();
  
  // Settings
  Future<void> setMonitoringInterval(int seconds);
  
  // Platform Info
  String getPlatformName();
  bool canMonitorAppInstalls();
  bool canMonitorScreenState();
  bool canMonitorPower();
  bool canMonitorNetwork();
  bool canRunForegroundService();
  bool canRunBackgroundTasks();
  
  // Feature Flags
  bool hasNativeAppInstallReceiver();
  bool hasNativeScreenReceiver();
  bool hasNativePowerReceiver();
  bool hasNativeBootReceiver();
  
  // Device Info
  Future<Map<String, dynamic>> getDeviceInfo();
}