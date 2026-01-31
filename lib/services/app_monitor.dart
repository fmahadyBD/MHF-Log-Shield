import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';

// Device monitoring packages
import 'package:device_apps/device_apps.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:battery_plus/battery_plus.dart';

// Local imports
import 'package:mhf_log_shield/utils/log_sender.dart';
import 'package:mhf_log_shield/data/repositories/settings_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppMonitor {
  final SettingsRepository _settings;
  final LogSender _logSender;
  List<Application> _previousApps = [];
  Timer? _monitorTimer;
  final Battery _battery = Battery();
  final Connectivity _connectivity = Connectivity();
  final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();
  
  // NEW: Track app versions for update detection
  final Map<String, String> _appVersions = {};
  final Map<String, String> _appInstallSources = {};
  
  // Stream subscriptions for cleanup
  StreamSubscription<BatteryState>? _batterySubscription;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  AppMonitor(this._settings, this._logSender);

  /// Start monitoring device and apps
  Future<void> startMonitoring() async {
    await _settings.initialize();
    
    // Get initial app list with versions
    _previousApps = await DeviceApps.getInstalledApplications(
      includeAppIcons: false,
      includeSystemApps: true,
      onlyAppsWithLaunchIntent: false,
    );
    
    // NEW: Cache initial app versions and install sources
    await _cacheAppVersions();
    await _cacheInstallSources();
    
    print('[AppMonitor] Monitoring ${_previousApps.length} apps');
    
    // Send device info once
    await _logDeviceInfo();
    
    // Start periodic checks
    _monitorTimer = Timer.periodic(
      const Duration(seconds: 10),
      (timer) => _checkForChanges(),
    );
    
    // Start real-time device monitoring
    _startDeviceMonitoring();
    
    print('[AppMonitor] Monitoring started successfully');
  }
  
  /// Stop all monitoring
  void stopMonitoring() {
    _monitorTimer?.cancel();
    _monitorTimer = null;
    _batterySubscription?.cancel();
    _connectivitySubscription?.cancel();
    print('[AppMonitor] Monitoring stopped');
  }
  
  /// Check for app installation/uninstallation/update changes
  Future<void> _checkForChanges() async {
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
      
      // NEW: Check for app updates
      for (final app in currentApps) {
        if (_previousApps.any((a) => a.packageName == app.packageName)) {
          await _checkForAppUpdate(app);
        }
      }
      
      // Update previous apps list and cache
      _previousApps = currentApps;
      await _cacheAppVersions();
      
    } catch (e) {
      print('[AppMonitor] Error checking changes: $e');
    }
  }
  
  /// NEW: Cache app versions for update detection
  Future<void> _cacheAppVersions() async {
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
  
  /// NEW: Get install source (requires API 30+/Android 11+)
  Future<String> _getInstallSource(String packageName) async {
    try {
      if (Platform.isAndroid) {
        // Try to get install source using platform channel
        const platform = MethodChannel('app_monitor_channel');
        final result = await platform.invokeMethod<String>(
          'getInstallSource',
          {'packageName': packageName},
        );
        
        if (result != null) {
          // Map installer package to readable name
          return _mapInstallSource(result);
        }
      }
    } catch (e) {
      print('[AppMonitor] Error getting install source: $e');
    }
    
    return 'Unknown';
  }
  
  /// NEW: Map installer package to readable name
  String _mapInstallSource(String installerPackage) {
    final Map<String, String> sourceMap = {
      'com.android.vending': 'Google Play Store',
      'com.amazon.venezia': 'Amazon Appstore',
      'com.samsung.android.app.galaxyappstore': 'Samsung Galaxy Store',
      'com.huawei.appmarket': 'Huawei AppGallery',
      'com.xiaomi.market': 'Xiaomi App Store',
      'com.oppo.market': 'Oppo App Market',
      'com.vivo.appstore': 'Vivo App Store',
      'com.tencent.android.qqdownloader': 'Tencent App Center',
      'com.sec.android.app.samsungapps': 'Samsung Apps (old)',
      'com.lenovo.leos.appstore': 'Lenovo App Store',
    };
    
    return sourceMap[installerPackage] ?? 
           (installerPackage.contains('packageinstaller') ? 'Manual APK' : installerPackage);
  }
  
  /// NEW: Cache install sources
  Future<void> _cacheInstallSources() async {
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
  
  /// NEW: Check for app updates
  Future<void> _checkForAppUpdate(Application app) async {
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
  
  /// Log when an app is installed
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
      
      // Get install date (approximate)
      final installDate = _getApproximateInstallDate();
      
      final appType = app.systemApp ? 'System App' : 'User App';
      final message = '📱 APP INSTALLED\n'
                      '• Name: ${app.appName}\n'
                      '• Package: ${app.packageName}\n'
                      '• Type: $appType\n'
                      '• Version: $version ($versionCode)\n'
                      '• Source: $installSource\n'
                      '• Installed: $installDate';
      
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
  
  /// NEW: Log when an app is updated
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
                      '• Source: $installSource\n'
                      '• Updated: ${DateTime.now().toString()}';
      
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
  
  /// Log when an app is uninstalled
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
                      '• Source: $installSource\n'
                      '• Uninstalled: ${DateTime.now().toString()}';
      
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
  
  /// Enhanced: Store app event with more details
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
  
  /// NEW: Get approximate install date (works for Android API 30+)
  String _getApproximateInstallDate() {
    return DateTime.now().toString(); // For older APIs, use current time
  }
  
  /// Start monitoring device states (battery, network)
  Future<void> _startDeviceMonitoring() async {
    try {
      // Monitor battery changes
      _batterySubscription = _battery.onBatteryStateChanged.listen((BatteryState state) async {
        await _logBatteryChange(state);
      });
      
      // Monitor network changes
      _connectivitySubscription = _connectivity.onConnectivityChanged.listen((List<ConnectivityResult> results) async {
        if (results.isNotEmpty) {
          await _logNetworkChange(results.first);
        }
      });
      
    } catch (e) {
      print('[AppMonitor] Error starting device monitoring: $e');
    }
  }
  
  /// Log battery state change
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
  
  /// Log network connectivity change
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
  
  /// Log periodic device status
  Future<void> _logPeriodicStatus() async {
    final serverUrl = _settings.getServerUrl();
    if (serverUrl.isEmpty) return;
    
    try {
      final batteryLevel = await _battery.batteryLevel;
      final networkResults = await _connectivity.checkConnectivity();
      final networkStr = networkResults.isNotEmpty 
          ? _getNetworkTypeString(networkResults.first)
          : 'No Connection';
      final appCount = _previousApps.length;
      
      final message = '📊 Status Update | '
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
  
  /// Log device information (once)
  Future<void> _logDeviceInfo() async {
    final serverUrl = _settings.getServerUrl();
    if (serverUrl.isEmpty) return;
    
    try {
      if (Platform.isAndroid) {
        final androidInfo = await _deviceInfo.androidInfo;
        
        final message = '📱 Device Info | '
                        'Model: ${androidInfo.model} | '
                        'Android: ${androidInfo.version.release} | '
                        'SDK: ${androidInfo.version.sdkInt} | '
                        'Brand: ${androidInfo.brand} | '
                        'Device: ${androidInfo.device}';
        
        await _logSender.sendCustomLog(
          serverUrl, 
          '', 
          message, 
          'INFO'
        );
        
        print('[AppMonitor] $message');
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
  
  /// Get current installed apps count
  Future<int> getInstalledAppsCount() async {
    try {
      final apps = await DeviceApps.getInstalledApplications();
      return apps.length;
    } catch (e) {
      print('[AppMonitor] Error getting app count: $e');
      return 0;
    }
  }
  
  /// Get all installed apps with details
  Future<List<Map<String, dynamic>>> getAllInstalledApps() async {
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
  
  /// Get device information
  Future<Map<String, dynamic>> getDeviceInformation() async {
    try {
      if (Platform.isAndroid) {
        final androidInfo = await _deviceInfo.androidInfo;
        return {
          'model': androidInfo.model,
          'brand': androidInfo.brand,
          'device': androidInfo.device,
          'android_version': androidInfo.version.release,
          'sdk_version': androidInfo.version.sdkInt,
          'board': androidInfo.board,
          'bootloader': androidInfo.bootloader,
          'fingerprint': androidInfo.fingerprint,
          'hardware': androidInfo.hardware,
          'host': androidInfo.host,
          'id': androidInfo.id,
          'manufacturer': androidInfo.manufacturer,
          'product': androidInfo.product,
          'tags': androidInfo.tags,
          'type': androidInfo.type,
          'is_physical_device': androidInfo.isPhysicalDevice,
        };
      }
      return {};
    } catch (e) {
      print('[AppMonitor] Error getting device information: $e');
      return {};
    }
  }
  
  /// Get current battery status
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
  
  /// Get current network status
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



  // In AppMonitor class (where you have the MethodChannel)
static Future<void> saveServerUrlForNative(String serverUrl) async {
  try {
    const platform = MethodChannel('app_monitor_channel'); // Use your existing channel
    await platform.invokeMethod('saveServerUrl', {'url': serverUrl});
    print('[AppMonitor] Server URL saved for native components: $serverUrl');
  } catch (e) {
    print('[AppMonitor] Error saving server URL: $e');
  }
}


}