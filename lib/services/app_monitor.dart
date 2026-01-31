import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';

// Device monitoring packages
import 'package:device_apps/device_apps.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:battery_plus/battery_plus.dart';

// Core imports
import 'package:mhf_log_shield/core/interfaces/platform_services.dart';
import 'package:mhf_log_shield/core/platform/platform_service_factory.dart';

// Local imports
import 'package:mhf_log_shield/utils/log_sender.dart';
import 'package:mhf_log_shield/data/repositories/settings_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppMonitor {
  final SettingsRepository _settings;
  final LogSender _logSender;
  final PlatformServices _platformServices;
  
  // Android-specific: App tracking
  List<Application> _previousApps = [];
  final Map<String, String> _appVersions = {};
  final Map<String, String> _appInstallSources = {};
  
  // Cross-platform: Device tracking
  Timer? _monitorTimer;
  final Battery _battery = Battery();
  final Connectivity _connectivity = Connectivity();
  final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();
  
  // Stream subscriptions for cleanup
  StreamSubscription<BatteryState>? _batterySubscription;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  AppMonitor(this._settings, this._logSender)
      : _platformServices = PlatformServiceFactory.getPlatformServices();

  /// Start monitoring device and apps (cross-platform)
  Future<void> startMonitoring() async {
    await _settings.initialize();
    
    print('[AppMonitor] Starting monitoring on ${_platformServices.getPlatformName()}');
    
    // Platform-specific initialization
    if (_platformServices.canMonitorAppInstalls()) {
      await _startAndroidAppMonitoring();
    } else {
      print('[AppMonitor] App install monitoring not available on this platform');
    }
    
    // Start cross-platform device monitoring
    await _startDeviceMonitoring();
    
    // Start platform service if available
    if (_platformServices.canRunForegroundService()) {
      await _platformServices.startForegroundService();
    }
    
    // Start background monitoring if available
    if (_platformServices.canRunBackgroundTasks()) {
      await _platformServices.startBackgroundMonitoring();
    }
    
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
      
      // Cache initial app versions and install sources
      await _cacheAppVersions();
      await _cacheInstallSources();
      
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
  
  /// Stop all monitoring
  Future<void> stopMonitoring() async {
    print('[AppMonitor] Stopping monitoring');
    
    // Stop timers
    _monitorTimer?.cancel();
    _monitorTimer = null;
    
    // Cancel subscriptions
    _batterySubscription?.cancel();
    _connectivitySubscription?.cancel();
    
    // Stop platform services
    if (_platformServices.canRunForegroundService()) {
      await _platformServices.stopForegroundService();
    }
    
    if (_platformServices.canRunBackgroundTasks()) {
      await _platformServices.stopBackgroundMonitoring();
    }
    
    print('[AppMonitor] Monitoring stopped');
  }
  
  /// Check for app installation/uninstallation/update changes (Android only)
  Future<void> _checkForAppChanges() async {
    if (!_platformServices.canMonitorAppInstalls()) {
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
    if (!_platformServices.canMonitorAppInstalls()) return;
    
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
  
  /// Cache install sources (Android only)
  Future<void> _cacheInstallSources() async {
    if (!_platformServices.canMonitorAppInstalls()) return;
    
    _appInstallSources.clear();
    for (final app in _previousApps) {
      if (!app.systemApp) { // Only check user apps
        final source = await _getInstallSource(app.packageName);
        _appInstallSources[app.packageName] = source;
      } else {
        _appInstallSources[app.packageName] = 'System';
      }
    }
  }
  
  /// Get install source (Android only)
  Future<String> _getInstallSource(String packageName) async {
    if (!_platformServices.canMonitorAppInstalls()) {
      return 'Not available on ${_platformServices.getPlatformName()}';
    }
    
    try {
      return await _platformServices.getInstallSource(packageName);
    } catch (e) {
      print('[AppMonitor] Error getting install source: $e');
      return 'Unknown';
    }
  }
  
  /// Check for app updates (Android only)
  Future<void> _checkForAppUpdate(Application app) async {
    if (!_platformServices.canMonitorAppInstalls()) return;
    
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
      
      // Get install source
      final installSource = await _getInstallSource(app.packageName);
      
      final appType = app.systemApp ? 'System App' : 'User App';
      final message = '📱 APP INSTALLED\n'
                      '• Name: ${app.appName}\n'
                      '• Package: ${app.packageName}\n'
                      '• Type: $appType\n'
                      '• Version: $version ($versionCode)\n'
                      '• Source: $installSource';
      
      await _logSender.sendCustomLog(
        serverUrl, 
        '', 
        message, 
        'INFO'
      );
      
      print('[AppMonitor] App installed: ${app.appName} v$version from $installSource');
      
      // Cache the install source
      _appInstallSources[app.packageName] = installSource;
      _appVersions[app.packageName] = version;
      
      // Store offline for backup
      await _storeAppEvent('install', app.appName, app.packageName, 
                          version: version, source: installSource);
      
    } catch (e) {
      print('[AppMonitor] Failed to send installation log: $e');
      await _storeAppEvent('install', app.appName, app.packageName);
    }
  }
  
  /// Log when an app is updated (Android only)
  Future<void> _logAppUpdate(Application app, String oldVersion, String newVersion) async {
    final serverUrl = _settings.getServerUrl();
    if (serverUrl.isEmpty) return;
    
    try {
      final appWithData = await DeviceApps.getApp(app.packageName);
      final versionCode = appWithData?.versionCode?.toString() ?? 'Unknown';
      final installSource = _appInstallSources[app.packageName] ?? 'Unknown';
      
      final appType = app.systemApp ? 'System App' : 'User App';
      final message = '🔄 APP UPDATED\n'
                      '• Name: ${app.appName}\n'
                      '• Package: ${app.packageName}\n'
                      '• Type: $appType\n'
                      '• Old Version: $oldVersion\n'
                      '• New Version: $newVersion ($versionCode)\n'
                      '• Source: $installSource';
      
      await _logSender.sendCustomLog(
        serverUrl, 
        '', 
        message, 
        'INFO'
      );
      
      print('[AppMonitor] App updated: ${app.appName} $oldVersion → $newVersion');
      
      // Store offline
      await _storeAppEvent('update', app.appName, app.packageName, 
                          oldVersion: oldVersion, newVersion: newVersion);
      
    } catch (e) {
      print('[AppMonitor] Failed to send update log: $e');
      await _storeAppEvent('update', app.appName, app.packageName);
    }
  }
  
  /// Log when an app is uninstalled (Android only)
  Future<void> _logAppUninstallation(Application app) async {
    final serverUrl = _settings.getServerUrl();
    if (serverUrl.isEmpty) return;
    
    try {
      final oldVersion = _appVersions[app.packageName] ?? 'Unknown';
      final installSource = _appInstallSources[app.packageName] ?? 'Unknown';
      
      final appType = app.systemApp ? 'System App' : 'User App';
      final message = '🗑️ APP UNINSTALLED\n'
                      '• Name: ${app.appName}\n'
                      '• Package: ${app.packageName}\n'
                      '• Type: $appType\n'
                      '• Last Version: $oldVersion\n'
                      '• Source: $installSource';
      
      await _logSender.sendCustomLog(
        serverUrl, 
        '', 
        message, 
        'INFO'
      );
      
      print('[AppMonitor] App uninstalled: ${app.appName}');
      
      // Remove from cache
      _appVersions.remove(app.packageName);
      _appInstallSources.remove(app.packageName);
      
      // Store offline
      await _storeAppEvent('uninstall', app.appName, app.packageName, 
                          version: oldVersion, source: installSource);
      
    } catch (e) {
      print('[AppMonitor] Failed to send uninstallation log: $e');
      await _storeAppEvent('uninstall', app.appName, app.packageName);
    }
  }
  
  /// Store app event with more details
  Future<void> _storeAppEvent(String event, String appName, String packageName, 
                              {String? version, String? oldVersion, String? newVersion, String? source}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final events = prefs.getStringList('app_events') ?? [];
      final timestamp = DateTime.now().toIso8601String();
      
      final eventData = {
        'timestamp': timestamp,
        'event': event,
        'app_name': appName,
        'package': packageName,
        'version': version ?? '',
        'old_version': oldVersion ?? '',
        'new_version': newVersion ?? '',
        'source': source ?? '',
      };
      
      events.add(eventData.entries
          .where((entry) => entry.value.isNotEmpty)
          .map((entry) => '${entry.key}:${entry.value}')
          .join('|'));
      
      // Keep last 200 events
      final recentEvents = events.length > 200 
          ? events.sublist(events.length - 200) 
          : events;
      
      await prefs.setStringList('app_events', recentEvents);
    } catch (e) {
      print('[AppMonitor] Error storing app event: $e');
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
    
    // Start real-time device monitoring if platform supports it
    if (_platformServices.canMonitorScreenState()) {
      await _platformServices.startScreenMonitoring();
    }
    
    if (_platformServices.canMonitorPower()) {
      await _platformServices.startPowerMonitoring();
    }
    
    if (_platformServices.canMonitorNetwork()) {
      await _platformServices.startNetworkMonitoring();
    }
    
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
      final message = '🔋 Battery: $level% - $stateStr';
      
      await _logSender.sendCustomLog(
        serverUrl, 
        '', 
        message, 
        'INFO'
      );
      
      print('[AppMonitor] $message');
    } catch (e) {
      print('[AppMonitor] Error getting battery info: $e');
    }
  }
  
  /// Log network connectivity change (cross-platform)
  Future<void> _logNetworkChange(ConnectivityResult result) async {
    final serverUrl = _settings.getServerUrl();
    if (serverUrl.isEmpty) return;
    
    final networkStr = _getNetworkTypeString(result);
    final message = '🌐 Network changed: $networkStr';
    
    try {
      await _logSender.sendCustomLog(
        serverUrl, 
        '', 
        message, 
        'INFO'
      );
      
      print('[AppMonitor] $message');
    } catch (e) {
      print('[AppMonitor] Error logging network change: $e');
    }
  }
  
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
      
      final appCount = _platformServices.canMonitorAppInstalls() 
          ? _previousApps.length 
          : 0;
      
      final message = '📊 Status Update | '
                      'Platform: ${_platformServices.getPlatformName()} | '
                      'Apps: $appCount | '
                      'Battery: $batteryLevel% | '
                      'Network: $networkStr';
      
      await _logSender.sendCustomLog(
        serverUrl, 
        '', 
        message, 
        'INFO'
      );
      
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
      final platformName = _platformServices.getPlatformName();
      
      String message = '📱 $platformName Device Info';
      
      if (platformName == 'Android') {
        message += ' | '
                    'Model: ${deviceInfo['model']} | '
                    'Android: ${deviceInfo['android_version']} | '
                    'SDK: ${deviceInfo['sdk_version']} | '
                    'Brand: ${deviceInfo['brand']}';
      } else if (platformName == 'iOS') {
        message += ' | '
                    'Device: ${deviceInfo['name']} | '
                    'Model: ${deviceInfo['model']} | '
                    'iOS: ${deviceInfo['system_version']}';
      } else {
        message += ' | Platform: $platformName';
      }
      
      await _logSender.sendCustomLog(
        serverUrl, 
        '', 
        message, 
        'INFO'
      );
      
      print('[AppMonitor] $message');
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
    if (!_platformServices.canMonitorAppInstalls()) {
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
    if (!_platformServices.canMonitorAppInstalls()) {
      return [{
        'note': 'App list not available on ${_platformServices.getPlatformName()}',
        'platform': _platformServices.getPlatformName(),
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
      return await _platformServices.getDeviceInfo();
    } catch (e) {
      print('[AppMonitor] Error getting device information: $e');
      return {'platform': _platformServices.getPlatformName(), 'error': e.toString()};
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
  
  /// Save server URL for native components
  Future<void> saveServerUrlForNative(String serverUrl) async {
    try {
      await _platformServices.saveServerUrl(serverUrl);
      print('[AppMonitor] Server URL saved for native components: $serverUrl');
    } catch (e) {
      print('[AppMonitor] Error saving server URL: $e');
    }
  }
}