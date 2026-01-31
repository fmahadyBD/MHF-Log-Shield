import 'dart:async';
import 'dart:io';

// Background task package
import 'package:flutter/services.dart';
import 'package:workmanager/workmanager.dart';

// Storage package
import 'package:shared_preferences/shared_preferences.dart';

// Core imports
import 'package:mhf_log_shield/core/interfaces/platform_services.dart';
import 'package:mhf_log_shield/core/platform/platform_service_factory.dart';

// Device monitoring packages
import 'package:device_apps/device_apps.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';

// Local imports
import 'package:mhf_log_shield/utils/log_sender.dart';
import 'package:mhf_log_shield/data/repositories/settings_repository.dart';

class BackgroundLogger {
  static const String _logStorageKey = 'pending_logs';
  static const String _appEventsKey = 'app_events';
  static final PlatformServices _platformServices = 
      PlatformServiceFactory.getPlatformServices();

  /// Initialize background work manager (cross-platform)
  static void initialize() {
    // Only initialize Workmanager on platforms that support it
    if (_platformServices.canRunBackgroundTasks()) {
      Workmanager().initialize(
        callbackDispatcher,
        isInDebugMode: true, // Set to false in production
      );
      
      print('[BackgroundLogger] Background work manager initialized');
    } else {
      print('[BackgroundLogger] Background tasks not supported on ${_platformServices.getPlatformName()}');
    }
  }

  /// Start continuous logging (cross-platform)
  static Future<void> startLogging() async {
    final settings = SettingsRepository();
    await settings.initialize();

    if (!settings.getCollectLogs()) {
      print('[BackgroundLogger] Log collection is disabled in settings');
      return;
    }

    final serverUrl = settings.getServerUrl();
    if (serverUrl.isEmpty) {
      print('[BackgroundLogger] Server URL not configured');
      return;
    }

    print('[BackgroundLogger] Starting continuous logging on ${_platformServices.getPlatformName()}...');

    // Start periodic logging
    await _startPeriodicLogging(serverUrl);
  }

  static Future<void> _startPeriodicLogging(String serverUrl) async {
    // Start logging every 30 seconds
    Timer.periodic(const Duration(seconds: 30), (timer) async {
      try {
        await _sendPeriodicLog(serverUrl);
      } catch (e) {
        print('[BackgroundLogger] Error in periodic log: $e');
      }
    });

    // Also start app monitoring if platform supports it
    if (_platformServices.canMonitorAppInstalls()) {
      await _startAppMonitoring(serverUrl);
    }
  }

  static Future<void> _sendPeriodicLog(String serverUrl) async {
    try {
      final logSender = LogSender();
      final battery = Battery();
      final connectivity = Connectivity();

      final batteryLevel = await battery.batteryLevel;
      final networkResults = await connectivity.checkConnectivity();
      final networkStatus = networkResults.isNotEmpty
          ? networkResults.first
          : ConnectivityResult.none;

      String networkType;
      switch (networkStatus) {
        case ConnectivityResult.wifi:
          networkType = 'WiFi';
          break;
        case ConnectivityResult.mobile:
          networkType = 'Mobile Data';
          break;
        case ConnectivityResult.ethernet:
          networkType = 'Ethernet';
          break;
        default:
          networkType = 'No Connection';
      }

      final platform = _platformServices.getPlatformName();
      final message =
          '📱 Background Check | Platform: $platform | '
          'Battery: $batteryLevel% | '
          'Network: $networkType';

      await logSender.sendCustomLog(serverUrl, '', message, 'INFO');
      print('[BackgroundLogger] Sent periodic log');
    } catch (e) {
      print('[BackgroundLogger] Error sending periodic log: $e');
      await storeLogOffline('Periodic log failed: $e');
    }
  }

  static Future<void> _startAppMonitoring(String serverUrl) async {
    print('[BackgroundLogger] Starting app monitoring...');

    try {
      final logSender = LogSender();
      final apps = await DeviceApps.getInstalledApplications();
      final appCount = apps.length;

      // Log initial app count
      final message = '📊 Background App Count | Total Apps: $appCount';
      await logSender.sendCustomLog(serverUrl, '', message, 'INFO');

      print('[BackgroundLogger] Initial app count logged: $appCount');
    } catch (e) {
      print('[BackgroundLogger] Error in app monitoring: $e');
    }
  }

  /// Start background monitoring tasks (platform-specific)
  static Future<void> startBackgroundMonitoring() async {
    print('[BackgroundLogger] Starting background monitoring on ${_platformServices.getPlatformName()}');
    
    // Start platform-specific services
    if (_platformServices.canRunForegroundService()) {
      try {
        await _platformServices.startForegroundService();
      } catch (e) {
        print('[BackgroundLogger] Error starting foreground service: $e');
      }
    }

    // Register periodic task if platform supports it
    if (_platformServices.canRunBackgroundTasks()) {
      try {
        await Workmanager().registerPeriodicTask(
          "logSyncTask",
          "logSync",
          frequency: const Duration(minutes: 15),
          constraints: Constraints(
            networkType: NetworkType.connected,
            requiresBatteryNotLow: false,
            requiresCharging: false,
            requiresDeviceIdle: false,
            requiresStorageNotLow: false,
          ),
          initialDelay: const Duration(seconds: 30),
          existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
        );
        
        print('[BackgroundLogger] Background tasks registered');
      } catch (e) {
        print('[BackgroundLogger] Error registering background tasks: $e');
      }
    } else {
      print('[BackgroundLogger] Background tasks not supported on this platform');
    }
  }

  static Future<void> stopBackgroundMonitoring() async {
    print('[BackgroundLogger] Stopping background monitoring');
    
    // Stop platform services
    if (_platformServices.canRunForegroundService()) {
      try {
        await _platformServices.stopForegroundService();
      } catch (e) {
        print('[BackgroundLogger] Error stopping foreground service: $e');
      }
    }

    // Cancel background tasks
    if (_platformServices.canRunBackgroundTasks()) {
      try {
        await Workmanager().cancelAll();
        print('[BackgroundLogger] All background tasks cancelled');
      } catch (e) {
        print('[BackgroundLogger] Error cancelling background tasks: $e');
      }
    }
  }

  /// Store log when device is offline (cross-platform)
  static Future<void> storeLogOffline(String log) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final List<String> pendingLogs =
          prefs.getStringList(_logStorageKey) ?? [];

      final timestamp = DateTime.now().toIso8601String();
      pendingLogs.add('$timestamp|$log');

      // Keep only last 1000 logs to prevent storage issues
      if (pendingLogs.length > 1000) {
        pendingLogs.removeRange(0, pendingLogs.length - 1000);
      }

      await prefs.setStringList(_logStorageKey, pendingLogs);

      print('[BackgroundLogger] Stored offline log: ${log.length} chars');
    } catch (e) {
      print('[BackgroundLogger] Error storing offline log: $e');
    }
  }

  /// Send all pending logs when device comes online (cross-platform)
  static Future<void> sendPendingLogs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pendingLogs = prefs.getStringList(_logStorageKey) ?? [];

      if (pendingLogs.isEmpty) {
        print('[BackgroundLogger] No pending logs to send');
        return;
      }

      final settings = SettingsRepository();
      await settings.initialize();
      final serverUrl = settings.getServerUrl();

      if (serverUrl.isEmpty) {
        print('[BackgroundLogger] Server not configured, keeping logs stored');
        return;
      }

      final logSender = LogSender();
      final connectivity = Connectivity();
      final networkResults = await connectivity.checkConnectivity();

      // Only send if we have network connection
      if (networkResults.isEmpty ||
          networkResults.first == ConnectivityResult.none) {
        print('[BackgroundLogger] No network, keeping logs stored');
        return;
      }

      print('[BackgroundLogger] Sending ${pendingLogs.length} pending logs');

      int successCount = 0;
      int failCount = 0;
      List<String> failedLogs = [];

      for (var logEntry in pendingLogs) {
        try {
          // Parse timestamp and message
          final parts = logEntry.split('|');
          if (parts.length >= 2) {
            final message = parts.sublist(1).join('|');
            await logSender.sendCustomLog(serverUrl, '', message, 'INFO');
            successCount++;

            // Small delay to prevent overwhelming the server
            await Future.delayed(const Duration(milliseconds: 100));
          }
        } catch (e) {
          failCount++;
          failedLogs.add(logEntry);
          print('[BackgroundLogger] Failed to send log: $e');

          // If we get network error, stop trying and keep remaining logs
          if (e is SocketException || e.toString().contains('network')) {
            print('[BackgroundLogger] Network error, stopping send');
            // Add remaining logs to failed logs
            final currentIndex = pendingLogs.indexOf(logEntry);
            failedLogs.addAll(pendingLogs.sublist(currentIndex + 1));
            break;
          }
        }
      }

      // Keep only failed logs
      await prefs.setStringList(_logStorageKey, failedLogs);
      print(
        '[BackgroundLogger] Sent $successCount logs, ${failedLogs.length} failed/remaining',
      );
    } catch (e) {
      print('[BackgroundLogger] Error sending pending logs: $e');
    }
  }

  /// Store app event for offline tracking (cross-platform)
  static Future<void> storeAppEventOffline(
    String event,
    String appName,
    String packageName,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final List<String> appEvents = prefs.getStringList(_appEventsKey) ?? [];

      final timestamp = DateTime.now().toIso8601String();
      appEvents.add('$timestamp|$event|$appName|$packageName');

      // Keep only last 500 events
      if (appEvents.length > 500) {
        appEvents.removeRange(0, appEvents.length - 500);
      }

      await prefs.setStringList(_appEventsKey, appEvents);

      print('[BackgroundLogger] Stored app event: $event - $appName');
    } catch (e) {
      print('[BackgroundLogger] Error storing app event: $e');
    }
  }

  /// Get pending logs count (cross-platform)
  static Future<int> getPendingLogsCount() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pendingLogs = prefs.getStringList(_logStorageKey) ?? [];
      return pendingLogs.length;
    } catch (e) {
      print('[BackgroundLogger] Error getting pending logs count: $e');
      return 0;
    }
  }

  /// Get app events count (cross-platform)
  static Future<int> getAppEventsCount() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final appEvents = prefs.getStringList(_appEventsKey) ?? [];
      return appEvents.length;
    } catch (e) {
      print('[BackgroundLogger] Error getting app events count: $e');
      return 0;
    }
  }

  /// Clear all stored logs (for testing/reset) (cross-platform)
  static Future<void> clearAllStoredLogs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_logStorageKey);
      await prefs.remove(_appEventsKey);
      print('[BackgroundLogger] All stored logs cleared');
    } catch (e) {
      print('[BackgroundLogger] Error clearing stored logs: $e');
    }
  }
}

/// Callback dispatcher for background tasks (cross-platform)
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    print('[BackgroundTask] Task started: $task');

    try {
      switch (task) {
        case 'logSync':
          await _executeLogSync();
          return Future.value(true);

        case 'startMonitoring':
          await _executeStartMonitoring();
          return Future.value(true);

        default:
          print('[BackgroundTask] Unknown task: $task');
          return Future.value(false);
      }
    } catch (e) {
      print('[BackgroundTask] Error in task $task: $e');
      return Future.value(false);
    }
  });
}

/// Execute log synchronization task (cross-platform)
Future<void> _executeLogSync() async {
  print('[BackgroundTask] Executing log sync');

  try {
    // Send any pending logs
    await BackgroundLogger.sendPendingLogs();

    // Check for app changes
    final settings = SettingsRepository();
    await settings.initialize();

    if (settings.getCollectLogs()) {
      // Send device status
      await _sendDeviceStatus(settings);

      // Check for app changes if platform supports it
      final platformServices = PlatformServiceFactory.getPlatformServices();
      if (platformServices.canMonitorAppInstalls()) {
        await _checkForAppChanges(settings);
      }
    }

    print('[BackgroundTask] Log sync completed');
  } catch (e) {
    print('[BackgroundTask] Error in log sync: $e');
  }
}

/// Execute start monitoring task (cross-platform)
Future<void> _executeStartMonitoring() async {
  print('[BackgroundTask] Executing start monitoring');

  try {
    final settings = SettingsRepository();
    await settings.initialize();

    if (settings.getCollectLogs()) {
      // Log device information
      await _logDeviceInformation(settings);
    }

    print('[BackgroundTask] Start monitoring completed');
  } catch (e) {
    print('[BackgroundTask] Error in start monitoring: $e');
  }
}

/// Send current device status (cross-platform)
Future<void> _sendDeviceStatus(SettingsRepository settings) async {
  final serverUrl = settings.getServerUrl();
  if (serverUrl.isEmpty) return;

  try {
    final battery = Battery();
    final connectivity = Connectivity();
    final logSender = LogSender();

    final batteryLevel = await battery.batteryLevel;
    final networkResults = await connectivity.checkConnectivity();
    final batteryState = await battery.batteryState;

    // Get network type
    final networkStatus = networkResults.isNotEmpty
        ? networkResults.first
        : ConnectivityResult.none;

    String networkType;
    switch (networkStatus) {
      case ConnectivityResult.wifi:
        networkType = 'WiFi';
        break;
      case ConnectivityResult.mobile:
        networkType = 'Mobile Data';
        break;
      case ConnectivityResult.ethernet:
        networkType = 'Ethernet';
        break;
      case ConnectivityResult.vpn:
        networkType = 'VPN';
        break;
      case ConnectivityResult.bluetooth:
        networkType = 'Bluetooth';
        break;
      case ConnectivityResult.other:
        networkType = 'Other';
        break;
      default:
        networkType = 'No Connection';
    }

    // Get battery state string
    String batteryStateStr;
    switch (batteryState) {
      case BatteryState.full:
        batteryStateStr = 'Full';
        break;
      case BatteryState.charging:
        batteryStateStr = 'Charging';
        break;
      case BatteryState.discharging:
        batteryStateStr = 'Discharging';
        break;
      default:
        batteryStateStr = 'Unknown';
    }

    final platformServices = PlatformServiceFactory.getPlatformServices();
    final platform = platformServices.getPlatformName();
    
    final message =
        '📱 Background Status | '
        'Platform: $platform | '
        'Battery: $batteryLevel% ($batteryStateStr) | '
        'Network: $networkType';

    await logSender.sendCustomLog(serverUrl, '', message, 'INFO');

    print('[BackgroundTask] Sent device status');
  } catch (e) {
    print('[BackgroundTask] Error sending device status: $e');
  }
}

/// Check for app changes in background (Android only)
Future<void> _checkForAppChanges(SettingsRepository settings) async {
  final serverUrl = settings.getServerUrl();
  if (serverUrl.isEmpty) return;

  try {
    final currentApps = await DeviceApps.getInstalledApplications();
    final appCount = currentApps.length;

    final logSender = LogSender();
    final message = '📊 Background App Count | Total Apps: $appCount';

    await logSender.sendCustomLog(serverUrl, '', message, 'INFO');

    print('[BackgroundTask] Checked app count: $appCount');
  } catch (e) {
    print('[BackgroundTask] Error checking app changes: $e');
  }
}

/// Log device information (cross-platform)
Future<void> _logDeviceInformation(SettingsRepository settings) async {
  final serverUrl = settings.getServerUrl();
  if (serverUrl.isEmpty) return;

  try {
    final platformServices = PlatformServiceFactory.getPlatformServices();
    final deviceInfo = await platformServices.getDeviceInfo();
    final platform = platformServices.getPlatformName();

    final logSender = LogSender();
    final message = '📱 Background Device Info | '
                    'Platform: $platform | '
                    'Device: ${deviceInfo['model'] ?? deviceInfo['name'] ?? 'Unknown'}';

    await logSender.sendCustomLog(serverUrl, '', message, 'INFO');

    print('[BackgroundTask] Sent device information');
  } catch (e) {
    print('[BackgroundLogger] Error logging device information: $e');
  }
}