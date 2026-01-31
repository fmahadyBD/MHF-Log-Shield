import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';

// Core imports
import 'package:mhf_log_shield/core/interfaces/platform_services.dart';
import 'package:mhf_log_shield/core/platform/platform_service_factory.dart';

// Local imports
import 'package:mhf_log_shield/utils/log_sender.dart';
import 'package:mhf_log_shield/data/repositories/settings_repository.dart';

class AdvancedMonitor {
  static final PlatformServices _platformServices = 
      PlatformServiceFactory.getPlatformServices();
  static Timer? _periodicTimer;
  
  /// Start advanced monitoring (cross-platform)
  static Future<void> startAdvancedMonitoring() async {
    print('[AdvancedMonitor] Starting advanced monitoring on ${_platformServices.getPlatformName()}');
    
    try {
      // Start platform-specific monitoring services
      await _platformServices.startAllMonitoring();
      
      // Start cross-platform Dart monitoring
      _startDartMonitoring();
      
      // Get initial monitoring data
      await _performMonitoringTasks();
      
      print('[AdvancedMonitor] Advanced monitoring started successfully');
    } catch (e) {
      print('[AdvancedMonitor] Error starting monitoring: $e');
    }
  }
  
  static void _startDartMonitoring() {
    // Stop any existing timer
    _periodicTimer?.cancel();
    
    // Start periodic checks (adjust interval based on platform capabilities)
    final interval = _platformServices.canRunBackgroundTasks() 
        ? const Duration(seconds: 30)  // Shorter interval for capable platforms
        : const Duration(minutes: 5);  // Longer interval for limited platforms
    
    _periodicTimer = Timer.periodic(interval, (timer) {
      _performMonitoringTasks();
    });
    
    print('[AdvancedMonitor] Dart monitoring started with ${interval.inSeconds}s interval');
  }
  
  static Future<void> _performMonitoringTasks() async {
    try {
      // Get monitoring data from platform
      final data = await _platformServices.getMonitoringData();
      print('[AdvancedMonitor] Monitoring data: $data');
      
      // Process and send logs if server is configured
      await _processMonitoringData(data);
      
    } catch (e) {
      print('[AdvancedMonitor] Error in monitoring tasks: $e');
    }
  }
  
  static Future<void> _processMonitoringData(Map<String, dynamic> data) async {
    final settings = SettingsRepository();
    await settings.initialize();
    
    final serverUrl = settings.getServerUrl();
    final apiKey = settings.getApiKey();
    final collectLogs = settings.getCollectLogs();
    
    if (serverUrl.isEmpty || !collectLogs) {
      return;
    }
    
    try {
      final logSender = LogSender();
      final platform = _platformServices.getPlatformName();
      final timestamp = DateTime.now().toIso8601String();
      
      // Create log message from monitoring data
      String message = '📊 Advanced Monitor | Platform: $platform | ';
      
      if (data.containsKey('battery_percent')) {
        message += 'Battery: ${data['battery_percent']}% | ';
      }
      
      if (data.containsKey('network_type')) {
        message += 'Network: ${data['network_type']} | ';
      }
      
      if (data.containsKey('is_connected')) {
        message += 'Connected: ${data['is_connected']}';
      }
      
      // Send log
      await logSender.sendCustomLog(serverUrl, apiKey, message, 'INFO');
      
      print('[AdvancedMonitor] Sent monitoring log: ${message.substring(0, 50)}...');
      
    } catch (e) {
      print('[AdvancedMonitor] Error processing monitoring data: $e');
    }
  }
  
  /// Stop advanced monitoring
  static Future<void> stopAdvancedMonitoring() async {
    try {
      _periodicTimer?.cancel();
      _periodicTimer = null;
      
      // Stop platform-specific monitoring
      await _platformServices.stopAllMonitoring();
      
      print('[AdvancedMonitor] Advanced monitoring stopped');
    } catch (e) {
      print('[AdvancedMonitor] Error stopping monitoring: $e');
    }
  }
  
  /// Check if monitoring service is running
  static Future<bool> isMonitoringRunning() async {
    try {
      final stats = await _platformServices.getMonitoringStats();
      return stats['is_running'] == true || stats['service_running'] == true;
    } catch (e) {
      print('[AdvancedMonitor] Error checking service status: $e');
      return false;
    }
  }
  
  /// Get pending events count
  static Future<Map<String, int>> getPendingEventsCount() async {
    try {
      return await _platformServices.getPendingEventsCount();
    } catch (e) {
      print('[AdvancedMonitor] Error getting event counts: $e');
      return {};
    }
  }
  
  /// Set monitoring interval
  static Future<void> setMonitoringInterval(int seconds) async {
    try {
      await _platformServices.setMonitoringInterval(seconds);
      print('[AdvancedMonitor] Monitoring interval set to $seconds seconds');
      
      // Restart timer with new interval
      _periodicTimer?.cancel();
      _periodicTimer = Timer.periodic(
        Duration(seconds: seconds),
        (timer) => _performMonitoringTasks(),
      );
      
    } catch (e) {
      print('[AdvancedMonitor] Error setting interval: $e');
    }
  }
  
  /// Get current monitoring stats
  static Future<Map<String, dynamic>> getMonitoringStats() async {
    try {
      final stats = await _platformServices.getMonitoringStats();
      
      // Add Dart-side info
      final dartStats = Map<String, dynamic>.from(stats);
      dartStats['dart_timer_running'] = _periodicTimer != null;
      dartStats['platform'] = _platformServices.getPlatformName();
      dartStats['capabilities'] = {
        'app_installs': _platformServices.canMonitorAppInstalls(),
        'screen_state': _platformServices.canMonitorScreenState(),
        'power': _platformServices.canMonitorPower(),
        'network': _platformServices.canMonitorNetwork(),
        'foreground_service': _platformServices.canRunForegroundService(),
        'background_tasks': _platformServices.canRunBackgroundTasks(),
      };
      
      return dartStats;
    } catch (e) {
      print('[AdvancedMonitor] Error getting stats: $e');
      return {
        'error': e.toString(),
        'platform': _platformServices.getPlatformName(),
      };
    }
  }
  
  /// Test native receivers (platform-specific)
  static Future<void> testNativeReceivers() async {
    try {
      await _platformServices.sendTestEvent();
      print('[AdvancedMonitor] Native receivers test triggered');
    } catch (e) {
      print('[AdvancedMonitor] Error testing native receivers: $e');
    }
  }
  
  /// Test Wazuh connection
  static Future<void> testWazuhConnection() async {
    try {
      await _platformServices.testWazuhConnection();
      print('[AdvancedMonitor] Wazuh connection test initiated');
    } catch (e) {
      print('[AdvancedMonitor] Error testing Wazuh connection: $e');
    }
  }
  
  /// Clear monitoring data
  static Future<void> clearMonitoringData() async {
    try {
      await _platformServices.clearMonitoringData();
      print('[AdvancedMonitor] Monitoring data cleared');
    } catch (e) {
      print('[AdvancedMonitor] Error clearing monitoring data: $e');
    }
  }
  
  /// Get server URL status
  static Future<Map<String, dynamic>> getServerUrlStatus() async {
    try {
      return await _platformServices.getServerUrlStatus();
    } catch (e) {
      print('[AdvancedMonitor] Error getting server URL status: $e');
      return {'error': e.toString()};
    }
  }
  
  /// Save server URL for native components
  static Future<void> saveServerUrlForNative(String serverUrl) async {
    try {
      await _platformServices.saveServerUrl(serverUrl);
      print('[AdvancedMonitor] Server URL saved for native components');
    } catch (e) {
      print('[AdvancedMonitor] Error saving server URL: $e');
    }
  }
  
  /// Check and request permissions
  static Future<void> checkAndRequestPermissions() async {
    try {
      await _platformServices.requestAllPermissions();
      print('[AdvancedMonitor] Permissions requested');
    } catch (e) {
      print('[AdvancedMonitor] Error requesting permissions: $e');
    }
  }
  
  /// Check if usage stats permission is granted (Android only)
  static Future<bool> hasUsageStatsPermission() async {
    try {
      return await _platformServices.hasUsageStatsPermission();
    } catch (e) {
      print('[AdvancedMonitor] Error checking usage stats permission: $e');
      return false;
    }
  }
}