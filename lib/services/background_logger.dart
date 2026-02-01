import 'dart:async';
import 'dart:io';

// Background task package
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:mhf_log_shield/utils/background_channel.dart';
import 'package:workmanager/workmanager.dart';

// Storage package
import 'package:shared_preferences/shared_preferences.dart';

// Local imports
import 'package:mhf_log_shield/utils/log_sender.dart';
import 'package:mhf_log_shield/data/repositories/settings_repository.dart';

class BackgroundLogger {
  static const String _logStorageKey = 'pending_logs';
  static const String _appEventsKey = 'app_events';

  static void initialize() {
    if (Platform.isAndroid) {
      Workmanager().initialize(callbackDispatcher, isInDebugMode: true);
      print('[BackgroundLogger] WorkManager initialized for Android');
    } else if (Platform.isIOS) {
      print('[BackgroundLogger] iOS uses native BackgroundTasks');
    }
  }

  // iOS-specific background monitoring
static Future<void> startIOSBackgroundMonitoring() async {
  if (!Platform.isIOS) return;

  try {
    // Use platform channel to schedule iOS background tasks
    final result = await IOSBackgroundChannel.requestBackgroundTime();
    if (result) {
      print('[BackgroundLogger] iOS background task scheduled');
    } else {
      print('[BackgroundLogger] iOS background task scheduling failed');
    }
  } catch (e) {
    print('[BackgroundLogger] iOS background setup error: $e');
  }
}





  static Future<bool> _hasNetworkConnection() async {
    try {
      final connectivity = Connectivity();
      final result = await connectivity.checkConnectivity();
      return result.isNotEmpty && result.first != ConnectivityResult.none;
    } catch (e) {
      return false;
    }
  }

  /// Start logging
  static Future<void> startLogging() async {
    final settings = SettingsRepository();
    await settings.initialize();

    if (!settings.getCollectLogs()) {
      print('[BackgroundLogger] Log collection is disabled');
      return;
    }

    final serverUrl = settings.getServerUrl();
    if (serverUrl.isEmpty) {
      print('[BackgroundLogger] Server URL not configured');
      return;
    }

    print('[BackgroundLogger] Starting logging...');

    // Start periodic logging
    Timer.periodic(const Duration(minutes: 5), (timer) async {
      try {
        await _sendPeriodicLog(serverUrl);
      } catch (e) {
        print('[BackgroundLogger] Error in periodic log: $e');
      }
    });
  }

  static Future<void> _sendPeriodicLog(String serverUrl) async {
    try {
      final logSender = LogSender();
      final message = '📱 Background Check | Time: ${DateTime.now()}';

      await logSender.sendCustomLog(serverUrl, '', message, 'INFO');
      print('[BackgroundLogger] Sent periodic log');
    } catch (e) {
      print('[BackgroundLogger] Error sending periodic log: $e');
      await storeLogOffline('Periodic log failed: $e');
    }
  }

  /// Start background monitoring
  static Future<void> startBackgroundMonitoring() async {
    print('[BackgroundLogger] Starting background monitoring');

    try {
      await Workmanager().registerPeriodicTask(
        "logSyncTask",
        "logSync",
        frequency: const Duration(minutes: 15),
        constraints: Constraints(
          networkType: NetworkType.connected,
          requiresBatteryNotLow: false,
        ),
        initialDelay: const Duration(seconds: 30),
      );

      print('[BackgroundLogger] Background tasks registered');
    } catch (e) {
      print('[BackgroundLogger] Error registering background tasks: $e');
    }
  }

  static Future<void> stopBackgroundMonitoring() async {
    print('[BackgroundLogger] Stopping background monitoring');

    try {
      await Workmanager().cancelAll();
      print('[BackgroundLogger] All background tasks cancelled');
    } catch (e) {
      print('[BackgroundLogger] Error cancelling background tasks: $e');
    }
  }

  /// Store log when device is offline
  static Future<void> storeLogOffline(String log) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final List<String> pendingLogs =
          prefs.getStringList(_logStorageKey) ?? [];

      final timestamp = DateTime.now().toIso8601String();
      pendingLogs.add('$timestamp|$log');

      // Keep only last 1000 logs
      if (pendingLogs.length > 1000) {
        pendingLogs.removeRange(0, pendingLogs.length - 1000);
      }

      await prefs.setStringList(_logStorageKey, pendingLogs);
      print('[BackgroundLogger] Stored offline log');
    } catch (e) {
      print('[BackgroundLogger] Error storing offline log: $e');
    }
  }

  /// Send all pending logs
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
        print('[BackgroundLogger] Server not configured');
        return;
      }

      final logSender = LogSender();

      for (var logEntry in pendingLogs) {
        try {
          final parts = logEntry.split('|');
          if (parts.length >= 2) {
            final message = parts.sublist(1).join('|');
            await logSender.sendCustomLog(serverUrl, '', message, 'INFO');
          }
        } catch (e) {
          print('[BackgroundLogger] Failed to send log: $e');
        }
      }

      // Clear sent logs
      await prefs.setStringList(_logStorageKey, []);
      print('[BackgroundLogger] Sent pending logs');
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
      print('[BackgroundLogger] Stored app event: $event');
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

  /// Clear all stored logs
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
      if (task == 'logSync') {
        await BackgroundLogger.sendPendingLogs();
        return Future.value(true);
      }
      return Future.value(false);
    } catch (e) {
      print('[BackgroundTask] Error in task $task: $e');
      return Future.value(false);
    }
  });
}