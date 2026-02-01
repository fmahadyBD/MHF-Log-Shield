import 'dart:async';
import 'dart:io';

// Device monitoring packages
import 'package:device_apps/device_apps.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:battery_plus/battery_plus.dart';

// Local imports
import 'package:mhf_log_shield/utils/log_sender.dart';
import 'package:mhf_log_shield/data/repositories/settings_repository.dart';
import 'package:mhf_log_shield/services/background_logger.dart';

class AppMonitor {
  final SettingsRepository _settings;
  final LogSender _logSender;
  
  // Android-specific: App tracking
  List<Application> _previousApps = [];
  final Map<String, String> _appVersions = {};
  
  // Cross-platform: Device tracking
  Timer? _monitorTimer;
  final Battery _battery = Battery();
  final Connectivity _connectivity = Connectivity();
  final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();
  
  // Stream subscriptions for cleanup
  StreamSubscription<BatteryState>? _batterySubscription;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  AppMonitor(this._settings, this._logSender);

  /// Start monitoring device and apps (cross-platform)
  Future<void> startMonitoring() async {
    await _settings.initialize();
    
    print('[AppMonitor] Starting monitoring');
    
    // Check if on Android for app monitoring
    if (Platform.isAndroid) {
      await _startAndroidAppMonitoring();
    } else {
      print('[AppMonitor] App install monitoring only available on Android');
    }
    
    // Start cross-platform device monitoring
    await _startDeviceMonitoring();
    
    print('[AppMonitor] Monitoring started successfully');
  }

  /// Android-specific app monitoring
  Future<void> _startAndroidAppMonitoring() async {
    try {
      // Get initial app list with versions
      _previousApps = await DeviceApps.getInstalledApplications(
        includeAppIcons: false,
        includeSystemApps: true,
        onlyAppsWithLaunchIntent: false,
      );
      
      // Cache initial app versions
      await _cacheAppVersions();
      
      // Log initial app count
      await _logInitialAppCount();
      
      print('[AppMonitor] Monitoring ${_previousApps.length} apps');
      
      // Start periodic app checks
      _monitorTimer = Timer.periodic(
        const Duration(seconds: 30),
        (timer) => _checkForAppChanges(),
      );
      
    } catch (e) {
      print('[AppMonitor] Error starting Android app monitoring: $e');
    }
  }

  /// Log initial app count
  Future<void> _logInitialAppCount() async {
    final serverUrl = _settings.getServerUrl();
    if (serverUrl.isEmpty) return;
    
    try {
      final totalApps = _previousApps.length;
      final systemApps = _previousApps.where((app) => app.systemApp).length;
      final userApps = totalApps - systemApps;
      
      final message = '📱 Initial App Inventory\n'
                      '• Total Apps: $totalApps\n'
                      '• User Apps: $userApps\n'
                      '• System Apps: $systemApps';
      
      await _logSender.sendCustomLog(
        serverUrl, 
        '', 
        message, 
        'INFO'
      );
      
      print('[AppMonitor] Logged initial app count: $totalApps total, $userApps user, $systemApps system');
    } catch (e) {
      print('[AppMonitor] Error logging initial app count: $e');
    }
  }
  
  /// Stop all monitoring
  Future<void> stopMonitoring() async {
    print('[AppMonitor] Stopping monitoring');
    
    // Stop timers
    _monitorTimer?.cancel();
    _monitorTimer = null;
    
    // Cancel subscriptions
    _batterySubscription?.cancel();
    _connectivitySubscription?.cancel();
    
    print('[AppMonitor] Monitoring stopped');
  }
  
  /// Check for app installation/uninstallation/update changes (Android only)
  Future<void> _checkForAppChanges() async {
    if (!Platform.isAndroid) {
      return;
    }
    
    try {
      final serverUrl = _settings.getServerUrl();
      if (serverUrl.isEmpty) {
        print('[AppMonitor] Server not configured');
        return;
      }
      
      final currentApps = await DeviceApps.getInstalledApplications(
        includeAppIcons: false,
        includeSystemApps: true,
        onlyAppsWithLaunchIntent: false,
      );
      
      // Check for new installations
      for (final app in currentApps) {
        if (!_previousApps.any((a) => a.packageName == app.packageName)) {
          await _logAppInstallation(app);
        }
      }
      
      // Check for uninstallations
      for (final app in _previousApps) {
        if (!currentApps.any((a) => a.packageName == app.packageName)) {
          await _logAppUninstallation(app);
        }
      }
      
      // Check for app updates
      for (final app in currentApps) {
        if (_previousApps.any((a) => a.packageName == app.packageName)) {
          await _checkForAppUpdate(app);
        }
      }
      
      // Update previous apps list and cache
      _previousApps = currentApps;
      await _cacheAppVersions();
      
    } catch (e) {
      print('[AppMonitor] Error checking app changes: $e');
    }
  }
  
  /// Cache app versions for update detection (Android only)
  Future<void> _cacheAppVersions() async {
    if (!Platform.isAndroid) return;
    
    _appVersions.clear();
    for (final app in _previousApps) {
      try {
        final appWithData = await DeviceApps.getApp(app.packageName);
        if (appWithData != null && appWithData.versionName != null) {
          _appVersions[app.packageName] = appWithData.versionName!;
        }
      } catch (e) {
        // Ignore errors for individual apps
      }
    }
  }
  
  /// Check for app updates (Android only)
  Future<void> _checkForAppUpdate(Application app) async {
    if (!Platform.isAndroid) return;
    
    try {
      final currentApp = await DeviceApps.getApp(app.packageName);
      if (currentApp == null || currentApp.versionName == null) return;
      
      final previousVersion = _appVersions[app.packageName];
      final currentVersion = currentApp.versionName!;
      
      if (previousVersion != null && 
          previousVersion != currentVersion && 
          currentVersion.isNotEmpty) {
        await _logAppUpdate(app, previousVersion, currentVersion);
      }
    } catch (e) {
      print('[AppMonitor] Error checking app update: $e');
    }
  }
  
  /// Log when an app is installed (Android only)
  Future<void> _logAppInstallation(Application app) async {
    final serverUrl = _settings.getServerUrl();
    if (serverUrl.isEmpty) return;
    
    try {
      // Get app details
      final appWithData = await DeviceApps.getApp(app.packageName);
      final version = appWithData?.versionName ?? 'Unknown';
      final versionCode = appWithData?.versionCode?.toString() ?? 'Unknown';
      
      final appType = app.systemApp ? 'System App' : 'User App';
      final message = '📱 APP INSTALLED\n'
                      '• Name: ${app.appName}\n'
                      '• Package: ${app.packageName}\n'
                      '• Type: $appType\n'
                      '• Version: $version ($versionCode)';
      
      // Send immediately to server
      final success = await _logSender.sendCustomLog(
        serverUrl, 
        '', 
        message, 
        'INFO'
      );
      
      if (success) {
        print('[AppMonitor] ✅ App installed log sent: ${app.appName} v$version');
      } else {
        print('[AppMonitor] ❌ Failed to send app installed log');
        await BackgroundLogger.storeAppEventOffline('install', app.appName, app.packageName);
      }
      
      // Cache the version
      _appVersions[app.packageName] = version;
      
    } catch (e) {
      print('[AppMonitor] Failed to send installation log: $e');
      await BackgroundLogger.storeAppEventOffline('install', app.appName, app.packageName);
    }
  }
  
  /// Log when an app is updated (Android only)
  Future<void> _logAppUpdate(Application app, String oldVersion, String newVersion) async {
    final serverUrl = _settings.getServerUrl();
    if (serverUrl.isEmpty) return;
    
    try {
      final appWithData = await DeviceApps.getApp(app.packageName);
      final versionCode = appWithData?.versionCode?.toString() ?? 'Unknown';
      
      final appType = app.systemApp ? 'System App' : 'User App';
      final message = '🔄 APP UPDATED\n'
                      '• Name: ${app.appName}\n'
                      '• Package: ${app.packageName}\n'
                      '• Type: $appType\n'
                      '• Old Version: $oldVersion\n'
                      '• New Version: $newVersion ($versionCode)';
      
      // Send immediately to server
      final success = await _logSender.sendCustomLog(
        serverUrl, 
        '', 
        message, 
        'INFO'
      );
      
      if (success) {
        print('[AppMonitor] ✅ App update log sent: ${app.appName} $oldVersion → $newVersion');
      } else {
        print('[AppMonitor] ❌ Failed to send app update log');
        await BackgroundLogger.storeAppEventOffline('update', app.appName, app.packageName);
      }
      
    } catch (e) {
      print('[AppMonitor] Failed to send update log: $e');
      await BackgroundLogger.storeAppEventOffline('update', app.appName, app.packageName);
    }
  }
  
  /// Log when an app is uninstalled (Android only)
  Future<void> _logAppUninstallation(Application app) async {
    final serverUrl = _settings.getServerUrl();
    if (serverUrl.isEmpty) return;
    
    try {
      final oldVersion = _appVersions[app.packageName] ?? 'Unknown';
      
      final appType = app.systemApp ? 'System App' : 'User App';
      final message = '🗑️ APP UNINSTALLED\n'
                      '• Name: ${app.appName}\n'
                      '• Package: ${app.packageName}\n'
                      '• Type: $appType\n'
                      '• Last Version: $oldVersion';
      
      // Send immediately to server
      final success = await _logSender.sendCustomLog(
        serverUrl, 
        '', 
        message, 
        'INFO'
      );
      
      if (success) {
        print('[AppMonitor] ✅ App uninstalled log sent: ${app.appName}');
      } else {
        print('[AppMonitor] ❌ Failed to send app uninstalled log');
        await BackgroundLogger.storeAppEventOffline('uninstall', app.appName, app.packageName);
      }
      
      // Remove from cache
      _appVersions.remove(app.packageName);
      
    } catch (e) {
      print('[AppMonitor] Failed to send uninstallation log: $e');
      await BackgroundLogger.storeAppEventOffline('uninstall', app.appName, app.packageName);
    }
  }
  
  /// Start cross-platform device monitoring
  Future<void> _startDeviceMonitoring() async {
    // Send device info once
    await _logDeviceInfo();
    
    // Start periodic device status checks
    Timer.periodic(
      const Duration(minutes: 5),
      (timer) => _logPeriodicStatus(),
    );
    
    // Monitor battery changes (cross-platform)
    _batterySubscription = _battery.onBatteryStateChanged.listen((BatteryState state) async {
      await _logBatteryChange(state);
    });
    
    // Monitor network changes (cross-platform)
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen((List<ConnectivityResult> results) async {
      if (results.isNotEmpty) {
        await _logNetworkChange(results.first);
      }
    });
  }
  
  /// Log battery state change (cross-platform)
  Future<void> _logBatteryChange(BatteryState state) async {
    final serverUrl = _settings.getServerUrl();
    if (serverUrl.isEmpty) return;
    
    try {
      final level = await _battery.batteryLevel;
      final stateStr = _getBatteryStateString(state);
      
      // Only log significant changes (every 10% or state change)
      if (stateStr != _lastBatteryState || (level % 10 == 0 && level != _lastBatteryLevel)) {
        final message = '🔋 Battery: $level% - $stateStr';
        
        final success = await _logSender.sendCustomLog(
          serverUrl, 
          '', 
          message, 
          'INFO'
        );
        
        if (success) {
          print('[AppMonitor] ✅ Battery log sent: $message');
          _lastBatteryState = stateStr;
          _lastBatteryLevel = level;
        }
      }
    } catch (e) {
      print('[AppMonitor] Error getting battery info: $e');
    }
  }
  
  String _lastBatteryState = '';
  int _lastBatteryLevel = 0;
  
  /// Log network connectivity change (cross-platform)
  Future<void> _logNetworkChange(ConnectivityResult result) async {
    final serverUrl = _settings.getServerUrl();
    if (serverUrl.isEmpty) return;
    
    final networkStr = _getNetworkTypeString(result);
    
    // Only log if network type changed
    if (networkStr != _lastNetworkState) {
      final message = '🌐 Network changed: $networkStr';
      
      try {
        final success = await _logSender.sendCustomLog(
          serverUrl, 
          '', 
          message, 
          'INFO'
        );
        
        if (success) {
          print('[AppMonitor] ✅ Network log sent: $message');
          _lastNetworkState = networkStr;
        }
      } catch (e) {
        print('[AppMonitor] Error logging network change: $e');
      }
    }
  }
  
  String _lastNetworkState = '';
  
  /// Log periodic device status (cross-platform)
  Future<void> _logPeriodicStatus() async {
    final serverUrl = _settings.getServerUrl();
    if (serverUrl.isEmpty) return;
    
    try {
      final batteryLevel = await _battery.batteryLevel;
      final networkResults = await _connectivity.checkConnectivity();
      final networkStr = networkResults.isNotEmpty 
          ? _getNetworkTypeString(networkResults.first)
          : 'No Connection';
      
      final appCount = Platform.isAndroid ? _previousApps.length : 0;
      
      final message = '📊 Status Update | '
                      'Platform: ${Platform.operatingSystem} | '
                      'Apps: $appCount | '
                      'Battery: $batteryLevel% | '
                      'Network: $networkStr';
      
      final success = await _logSender.sendCustomLog(
        serverUrl, 
        '', 
        message, 
        'INFO'
      );
      
      if (success) {
        print('[AppMonitor] ✅ Periodic status log sent');
      }
      
    } catch (e) {
      print('[AppMonitor] Error logging periodic status: $e');
    }
  }
  
  /// Log device information (cross-platform)
  Future<void> _logDeviceInfo() async {
    final serverUrl = _settings.getServerUrl();
    if (serverUrl.isEmpty) return;
    
    try {
      final deviceInfo = await getDeviceInformation();
      final platformName = Platform.operatingSystem;
      
      String message = '📱 $platformName Device Info\n';
      
      if (Platform.isAndroid) {
        message += '• Model: ${deviceInfo['model']}\n'
                   '• Android: ${deviceInfo['android_version']}\n'
                   '• SDK: ${deviceInfo['sdk_version']}\n'
                   '• Brand: ${deviceInfo['brand']}';
      } else if (Platform.isIOS) {
        message += '• Device: ${deviceInfo['name']}\n'
                   '• Model: ${deviceInfo['model']}\n'
                   '• iOS: ${deviceInfo['system_version']}';
      } else {
        message += '• Platform: $platformName';
      }
      
      final success = await _logSender.sendCustomLog(
        serverUrl, 
        '', 
        message, 
        'INFO'
      );
      
      if (success) {
        print('[AppMonitor] ✅ Device info log sent');
      }
      
    } catch (e) {
      print('[AppMonitor] Error getting device info: $e');
    }
  }
  
  /// Helper: Convert battery state to string
  String _getBatteryStateString(BatteryState state) {
    switch (state) {
      case BatteryState.full:
        return 'Full';
      case BatteryState.charging:
        return 'Charging';
      case BatteryState.discharging:
        return 'Discharging';
      default:
        return 'Unknown';
    }
  }
  
  /// Helper: Convert network type to string
  String _getNetworkTypeString(ConnectivityResult result) {
    switch (result) {
      case ConnectivityResult.wifi:
        return 'WiFi';
      case ConnectivityResult.mobile:
        return 'Mobile Data';
      case ConnectivityResult.ethernet:
        return 'Ethernet';
      case ConnectivityResult.vpn:
        return 'VPN';
      case ConnectivityResult.bluetooth:
        return 'Bluetooth';
      case ConnectivityResult.other:
        return 'Other';
      default:
        return 'No Connection';
    }
  }
  
  /// Get current installed apps count (Android only)
  Future<int> getInstalledAppsCount() async {
    if (!Platform.isAndroid) {
      return 0;
    }
    
    try {
      final apps = await DeviceApps.getInstalledApplications();
      return apps.length;
    } catch (e) {
      print('[AppMonitor] Error getting app count: $e');
      return 0;
    }
  }
  
  /// Get all installed apps with details (Android only)
  Future<List<Map<String, dynamic>>> getAllInstalledApps() async {
    if (!Platform.isAndroid) {
      return [{
        'note': 'App list only available on Android',
        'platform': Platform.operatingSystem,
      }];
    }
    
    try {
      final apps = await DeviceApps.getInstalledApplications(
        includeAppIcons: false,
        includeSystemApps: true,
        onlyAppsWithLaunchIntent: false,
      );
      
      return apps.map((app) => {
        'name': app.appName,
        'package': app.packageName,
        'system_app': app.systemApp,
        'enabled': app.enabled,
      }).toList();
    } catch (e) {
      print('[AppMonitor] Error getting installed apps: $e');
      return [];
    }
  }

  /// Get device information (cross-platform)
  Future<Map<String, dynamic>> getDeviceInformation() async {
    try {
      if (Platform.isAndroid) {
        final androidInfo = await _deviceInfo.androidInfo;
        return {
          'platform': 'Android',
          'model': androidInfo.model,
          'brand': androidInfo.brand,
          'android_version': androidInfo.version.release,
          'sdk_version': androidInfo.version.sdkInt,
        };
      } else if (Platform.isIOS) {
        final iosInfo = await _deviceInfo.iosInfo;
        return {
          'platform': 'iOS',
          'name': iosInfo.name,
          'model': iosInfo.model,
          'system_version': iosInfo.systemVersion,
        };
      } else {
        return {'platform': Platform.operatingSystem};
      }
    } catch (e) {
      print('[AppMonitor] Error getting device information: $e');
      return {'platform': Platform.operatingSystem, 'error': e.toString()};
    }
  }
  
  /// Get current battery status (cross-platform)
  Future<Map<String, dynamic>> getBatteryStatus() async {
    try {
      final level = await _battery.batteryLevel;
      final state = await _battery.batteryState;
      
      return {
        'level': level,
        'state': state.toString(),
        'state_string': _getBatteryStateString(state),
      };
    } catch (e) {
      print('[AppMonitor] Error getting battery status: $e');
      return {'level': -1, 'state': 'unknown', 'state_string': 'Unknown'};
    }
  }
  
  /// Get current network status (cross-platform)
  Future<Map<String, dynamic>> getNetworkStatus() async {
    try {
      final results = await _connectivity.checkConnectivity();
      final result = results.isNotEmpty ? results.first : ConnectivityResult.none;
      
      return {
        'type': result.name,
        'type_string': _getNetworkTypeString(result),
        'has_connection': result != ConnectivityResult.none,
      };
    } catch (e) {
      print('[AppMonitor] Error getting network status: $e');
      return {
        'type': 'unknown', 
        'type_string': 'Unknown', 
        'has_connection': false
      };
    }
  }
}