import 'package:shared_preferences/shared_preferences.dart';

class SettingsRepository {
  static const String _serverUrlKey = 'server_url';
  static const String _apiKeyKey = 'api_key';
  static const String _autoSyncKey = 'auto_sync';
  static const String _collectLogsKey = 'collect_logs';

  late SharedPreferences _prefs;

  Future<void> initialize() async {
    _prefs = await SharedPreferences.getInstance();
  }

  // Server URL
  Future<void> setServerUrl(String url) async {
    await _prefs.setString(_serverUrlKey, url);
  }

  String getServerUrl() {
    return _prefs.getString(_serverUrlKey) ?? '';
  }

  // API Key (Optional)
  Future<void> setApiKey(String key) async {
    await _prefs.setString(_apiKeyKey, key);
  }

  String getApiKey() {
    return _prefs.getString(_apiKeyKey) ?? '';
  }

  // Auto Sync
  Future<void> setAutoSync(bool enabled) async {
    await _prefs.setBool(_autoSyncKey, enabled);
  }

  bool getAutoSync() {
    return _prefs.getBool(_autoSyncKey) ?? true;
  }

  // Collect Logs
  Future<void> setCollectLogs(bool enabled) async {
    await _prefs.setBool(_collectLogsKey, enabled);
  }

  bool getCollectLogs() {
    return _prefs.getBool(_collectLogsKey) ?? false;
  }

  // Check if configured
  bool isConfigured() {
    final url = getServerUrl();
    return url.isNotEmpty && url.startsWith('http');
  }

  // Clear all settings
  Future<void> clearAll() async {
    await _prefs.clear();
  }
}