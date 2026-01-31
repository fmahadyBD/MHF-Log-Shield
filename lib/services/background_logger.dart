import 'dart:async';
import 'dart:io';

// Background task package
import 'package:flutter/services.dart';
import 'package:workmanager/workmanager.dart';

// Storage package
import 'package:shared_preferences/shared_preferences.dart';

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

  /// Initialize background work manager
  static void initialize() {
    Workmanager().initialize(
      callbackDispatcher,
      isInDebugMode: true, // Set to false in production
    );

    print('[BackgroundLogger] Initialized');
  }

  // Add this method to actually start sending logs
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

    print('[BackgroundLogger] Starting continuous logging...');

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

    // Also start app monitoring
    await _startAppMonitoring(serverUrl);
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

      final message =
          '📱 Periodic Check | Battery: $batteryLevel% | Network: $networkType';

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
      final message = '📊 Initial App Count | Total Apps: $appCount';
      await logSender.sendCustomLog(serverUrl, '', message, 'INFO');

      print('[BackgroundLogger] Initial app count logged: $appCount');
    } catch (e) {
      print('[BackgroundLogger] Error in app monitoring: $e');
    }
  }

  static Future<void> startBackgroundMonitoring() async {
    // Start foreground service for Android 8+
    if (Platform.isAndroid) {
      try {
        const platform = MethodChannel('app_monitor_channel');
        await platform.invokeMethod('startForegroundService');
      } catch (e) {
        print('[BackgroundLogger] Error starting foreground service: $e');
      }
    }

    // Register periodic task (every 15 minutes - minimum allowed)
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
  }

  static Future<void> stopBackgroundMonitoring() async {
    if (Platform.isAndroid) {
      try {
        const platform = MethodChannel('app_monitor_channel');
        await platform.invokeMethod('stopForegroundService');
      } catch (e) {
        print('[BackgroundLogger] Error stopping foreground service: $e');
      }
    }

    await Workmanager().cancelAll();
    print('[BackgroundLogger] All background tasks cancelled');
  }

  /// Store log when device is offline
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

  /// Send all pending logs when device comes online
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

  /// Store app event for offline tracking
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

  /// Get pending logs count
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

  /// Get app events count
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

  /// Clear all stored logs (for testing/reset)
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

/// Callback dispatcher for background tasks
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

/// Execute log synchronization task
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

      // Check for app changes
      await _checkForAppChanges(settings);
    }

    print('[BackgroundTask] Log sync completed');
  } catch (e) {
    print('[BackgroundTask] Error in log sync: $e');
  }
}

/// Execute start monitoring task
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

/// Send current device status
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

    // Get network type string - FIXED: Handle List<ConnectivityResult>
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

    final message =
        '📱 Device Status | '
        'Battery: $batteryLevel% ($batteryStateStr) | '
        'Network: $networkType';

    await logSender.sendCustomLog(serverUrl, '', message, 'INFO');

    print('[BackgroundTask] Sent device status');
  } catch (e) {
    print('[BackgroundTask] Error sending device status: $e');
  }
}

/// Check for app changes in background
Future<void> _checkForAppChanges(SettingsRepository settings) async {
  final serverUrl = settings.getServerUrl();
  if (serverUrl.isEmpty) return;

  try {
    final currentApps = await DeviceApps.getInstalledApplications();
    final appCount = currentApps.length;

    final logSender = LogSender();
    final message = '📊 App Count Check | Total Apps: $appCount';

    await logSender.sendCustomLog(serverUrl, '', message, 'INFO');

    print('[BackgroundTask] Checked app count: $appCount');
  } catch (e) {
    print('[BackgroundTask] Error checking app changes: $e');
  }
}

/// Log device information
Future<void> _logDeviceInformation(SettingsRepository settings) async {
  final serverUrl = settings.getServerUrl();
  if (serverUrl.isEmpty) return;

  try {
    final deviceInfo = DeviceInfoPlugin();
    final logSender = LogSender();

    final androidInfo = await deviceInfo.androidInfo;

    final message =
        '📱 Device Information | '
        'Model: ${androidInfo.model} | '
        'Android: ${androidInfo.version.release} (SDK ${androidInfo.version.sdkInt}) | '
        'Brand: ${androidInfo.brand} | '
        'Manufacturer: ${androidInfo.manufacturer}';

    await logSender.sendCustomLog(serverUrl, '', message, 'INFO');

    print('[BackgroundTask] Sent device information');
  } catch (e) {
    print('[BackgroundLogger] Error logging device information: $e');
  }
}
