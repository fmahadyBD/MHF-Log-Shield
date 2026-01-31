import 'dart:io';
import '../interfaces/platform_services.dart';
import 'android_platform_services.dart';
import 'ios_platform_services.dart';

class PlatformServiceFactory {
  static PlatformServices? _instance;
  
  static PlatformServices getPlatformServices() {
    if (_instance != null) return _instance!;
    
    if (Platform.isAndroid) {
      _instance = AndroidPlatformServices();
    } else if (Platform.isIOS) {
      _instance = IosPlatformServices();
    } else if (Platform.isLinux) {
      _instance = LinuxPlatformServices();
    } else if (Platform.isWindows) {
      _instance = WindowsPlatformServices();
    } else if (Platform.isMacOS) {
      _instance = MacOSPlatformServices();
    } else {
      _instance = UnsupportedPlatformServices();
    }
    
    return _instance!;
  }
  
  static Future<void> initializePlatformServices() async {
    final services = getPlatformServices();
    
    print('🚀 Initializing platform services for ${services.getPlatformName()}');
    
    // Log platform capabilities
    print('📋 Platform Capabilities:');
    print('  • App Install Monitoring: ${services.canMonitorAppInstalls()}');
    print('  • Screen State Monitoring: ${services.canMonitorScreenState()}');
    print('  • Power Monitoring: ${services.canMonitorPower()}');
    print('  • Network Monitoring: ${services.canMonitorNetwork()}');
    print('  • Foreground Service: ${services.canRunForegroundService()}');
    print('  • Background Tasks: ${services.canRunBackgroundTasks()}');
    print('  • Native Receivers:');
    print('    - App Install: ${services.hasNativeAppInstallReceiver()}');
    print('    - Screen: ${services.hasNativeScreenReceiver()}');
    print('    - Power: ${services.hasNativePowerReceiver()}');
    print('    - Boot: ${services.hasNativeBootReceiver()}');
    
    // Request permissions if needed
    final hasPermissions = await services.checkAllPermissions();
    if (!hasPermissions) {
      print('⚠️ Requesting permissions...');
      await services.requestAllPermissions();
    }
    
    print('✅ Platform services initialized successfully');
  }
  
  static void reset() {
    _instance = null;
  }
}

// Stub implementations for other platforms

class LinuxPlatformServices implements PlatformServices {
  @override String getPlatformName() => 'Linux';
  @override bool canMonitorAppInstalls() => false;
  @override bool canMonitorScreenState() => false;
  @override bool canMonitorPower() => false;
  @override bool canMonitorNetwork() => true;
  @override bool canRunForegroundService() => false;
  @override bool canRunBackgroundTasks() => false;
  @override bool hasNativeAppInstallReceiver() => false;
  @override bool hasNativeScreenReceiver() => false;
  @override bool hasNativePowerReceiver() => false;
  @override bool hasNativeBootReceiver() => false;
  
  @override Future<void> startAllMonitoring() async => print('Linux: Monitoring not available');
  @override Future<void> stopAllMonitoring() async {}
  @override Future<void> startAppInstallMonitoring() async => print('Linux: App install monitoring not available');
  @override Future<void> stopAppInstallMonitoring() async {}
  @override Future<String> getInstallSource(String packageName) async => 'Linux Package Manager';
  @override Future<void> startScreenMonitoring() async => print('Linux: Screen monitoring not available');
  @override Future<void> stopScreenMonitoring() async {}
  @override Future<void> startPowerMonitoring() async => print('Linux: Power monitoring not available');
  @override Future<void> stopPowerMonitoring() async {}
  @override Future<void> startNetworkMonitoring() async => print('Linux: Starting network monitoring');
  @override Future<void> stopNetworkMonitoring() async {}
  @override Future<void> startForegroundService() async => print('Linux: Foreground service not available');
  @override Future<void> stopForegroundService() async {}
  @override Future<void> startBackgroundMonitoring() async => print('Linux: Background monitoring not available');
  @override Future<void> stopBackgroundMonitoring() async {}
  @override Future<bool> checkAllPermissions() async => true;
  @override Future<void> requestAllPermissions() async {}
  @override Future<bool> hasUsageStatsPermission() async => true;
  @override Future<void> requestUsageStatsPermission() async {}
  @override Future<void> sendToWazuh(String eventType, String message) async => print('Linux: Would send to Wazuh: $eventType - $message');
  @override Future<void> sendTestEvent() async => print('Linux: Test event');
  @override Future<Map<String, dynamic>> getMonitoringStats() async => {'platform': 'Linux', 'note': 'Limited capabilities'};
  @override Future<Map<String, dynamic>> getMonitoringData() async => {'platform': 'Linux'};
  @override Future<Map<String, int>> getPendingEventsCount() async => {};
  @override Future<void> clearMonitoringData() async {}
  @override Future<void> saveServerUrl(String serverUrl) async => print('Linux: Server URL saved: $serverUrl');
  @override Future<Map<String, dynamic>> getServerUrlStatus() async => {'platform': 'Linux'};
  @override Future<void> testWazuhConnection() async => print('Linux: Testing Wazuh connection');
  @override Future<void> setMonitoringInterval(int seconds) async => print('Linux: Interval set to $seconds seconds');
  @override Future<Map<String, dynamic>> getDeviceInfo() async => {'platform': 'Linux', 'os': 'Linux'};
}

class WindowsPlatformServices extends LinuxPlatformServices {
  @override String getPlatformName() => 'Windows';
  @override Future<Map<String, dynamic>> getDeviceInfo() async => {'platform': 'Windows', 'os': 'Windows'};
}

class MacOSPlatformServices extends LinuxPlatformServices {
  @override String getPlatformName() => 'macOS';
  @override Future<Map<String, dynamic>> getDeviceInfo() async => {'platform': 'macOS', 'os': 'macOS'};
}

class UnsupportedPlatformServices extends LinuxPlatformServices {
  @override String getPlatformName() => 'Unsupported';
  @override Future<Map<String, dynamic>> getDeviceInfo() async => {'platform': 'Unsupported', 'os': 'Unknown'};
}