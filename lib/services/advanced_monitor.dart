import 'dart:async';
import 'dart:io';
import 'package:battery_plus/battery_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:mhf_log_shield/data/repositories/settings_repository.dart';
import 'package:mhf_log_shield/utils/log_sender.dart';

class AdvancedMonitor {
  static Timer? _monitoringTimer;
  static final Battery _battery = Battery();
  static final Connectivity _connectivity = Connectivity();

  /// Start monitoring
  static Future<void> startAdvancedMonitoring() async {
    print('🟢 Starting monitoring');
    
    // Stop any existing timer
    _monitoringTimer?.cancel();
    
    // Start new timer (every 5 minutes)
    _monitoringTimer = Timer.periodic(
      const Duration(minutes: 5),
      (timer) async {
        await _sendMonitoringData();
      },
    );
    
    // Send immediate status
    await _sendMonitoringData();
  }

  /// Stop monitoring
  static Future<void> stopAdvancedMonitoring() async {
    print('🔴 Stopping monitoring');
    _monitoringTimer?.cancel();
    _monitoringTimer = null;
  }

  /// Check if monitoring is running
  static Future<bool> isMonitoringRunning() async {
    return _monitoringTimer != null;
  }

  /// Send monitoring data
  static Future<void> _sendMonitoringData() async {
    try {
      final settings = SettingsRepository();
      await settings.initialize();
      
      final serverUrl = settings.getServerUrl();
      if (serverUrl.isEmpty) return;
      
      // Get device info
      final batteryLevel = await _battery.batteryLevel;
      final networkResults = await _connectivity.checkConnectivity();
      final networkType = _getNetworkType(networkResults);
      final platform = Platform.operatingSystem;
      
      // Create message
      final message = '📊 Device Status | '
                      'Platform: $platform | '
                      'Battery: $batteryLevel% | '
                      'Network: $networkType';
      
      // Send to server
      final logSender = LogSender();
      await logSender.sendCustomLog(serverUrl, '', message, 'INFO');
      
      print('📤 Sent monitoring data');
    } catch (e) {
      print('❌ Monitoring error: $e');
    }
  }

  /// Get network type string
  static String _getNetworkType(List<ConnectivityResult> results) {
    if (results.isEmpty) return 'No Connection';
    
    switch (results.first) {
      case ConnectivityResult.wifi: return 'WiFi';
      case ConnectivityResult.mobile: return 'Mobile Data';
      case ConnectivityResult.ethernet: return 'Ethernet';
      case ConnectivityResult.vpn: return 'VPN';
      case ConnectivityResult.bluetooth: return 'Bluetooth';
      case ConnectivityResult.other: return 'Other';
      default: return 'No Connection';
    }
  }

  /// Get monitoring stats (simple version)
  static Future<Map<String, dynamic>> getMonitoringStats() async {
    return {
      'is_running': _monitoringTimer != null,
      'mode': 'Dart-only',
      'platform': Platform.operatingSystem,
    };
  }

  /// Set monitoring interval
  static Future<void> setMonitoringInterval(int seconds) async {
    print('⏰ Interval set to $seconds seconds');
    
    if (_monitoringTimer != null) {
      // Restart with new interval
      await stopAdvancedMonitoring();
      _monitoringTimer = Timer.periodic(
        Duration(seconds: seconds),
        (timer) async {
          await _sendMonitoringData();
        },
      );
    }
  }

  /// Other methods (just print, don't actually do anything)
  static Future<void> testNativeReceivers() async {
    print('📡 Native receivers not available in Dart-only mode');
  }

  static Future<void> testWazuhConnection() async {
    print('🔗 Wazuh connection test not available');
  }

  static Future<void> saveServerUrlForNative(String serverUrl) async {
    print('💾 Server URL saved: $serverUrl');
  }

  static Future<void> checkAndRequestPermissions() async {
    print('🔓 Permissions not needed in Dart-only mode');
  }

  static Future<bool> hasUsageStatsPermission() async {
    return false;
  }
}