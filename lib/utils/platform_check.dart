// utils/platform_check.dart
import 'dart:io';

class PlatformCheck {
  static bool isAndroid = Platform.isAndroid;
  static bool isIOS = Platform.isIOS;
  
  static bool canMonitorAppInstalls() => isAndroid;
  static bool canUseWorkManager() => isAndroid;
  static bool canUseForegroundService() => isAndroid;
  
  static String getPlatformName() {
    if (isAndroid) return 'Android';
    if (isIOS) return 'iOS';
    return 'Unknown';
  }
}