import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:mhf_log_shield/data/repositories/settings_repository.dart';
import 'package:mhf_log_shield/services/advanced_monitor.dart';
import 'package:mhf_log_shield/services/background_logger.dart';
import 'package:mhf_log_shield/ui/screens/settings_screen.dart';
import 'package:mhf_log_shield/utils/connection_tester.dart';
import 'package:mhf_log_shield/utils/log_sender.dart';
import 'package:mhf_log_shield/services/app_monitor.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with WidgetsBindingObserver {
  final SettingsRepository _settings = SettingsRepository();
  final LogSender _logSender = LogSender();
  final Battery _battery = Battery();
  final Connectivity _connectivity = Connectivity();
  late final String _platformName;
  late final bool _isAndroid;

  bool _isConfigured = false;
  bool _isCollecting = false;
  bool _isAdvancedMonitoring = false;
  String _connectionMode = 'UDP';
  String _serverAddress = '';
  bool _isTesting = false;
  bool _showNativeWarning = false;
  Map<String, dynamic> _monitoringStats = {};
  AppMonitor? _appMonitor;
  int _pendingLogsCount = 0;
  int _appEventsCount = 0;
  Timer? _statsTimer;
  Timer? _monitoringTimer;
  StreamSubscription<List<ConnectivityResult>>? _networkSubscription;
  Timer? _appStateTimer;
  AppLifecycleState? _currentAppState;
  DateTime? _lastAppStateChange;

  @override
  void initState() {
    super.initState();
    _platformName = Platform.operatingSystem;
    _isAndroid = Platform.isAndroid;
    
    // Add observer for app lifecycle events
    WidgetsBinding.instance.addObserver(this);
    
    _loadCurrentSettings();
    _checkPlatformCapabilities();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _statsTimer?.cancel();
    _monitoringTimer?.cancel();
    _networkSubscription?.cancel();
    _appStateTimer?.cancel();
    _appMonitor?.stopMonitoring();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    _currentAppState = state;
    _lastAppStateChange = DateTime.now();
    
    if (!_isCollecting) return;
    
    final serverUrl = _settings.getServerUrl();
    if (serverUrl.isEmpty) return;
    
    try {
      String stateName = '';
      String description = '';
      
      switch (state) {
        case AppLifecycleState.resumed:
          stateName = 'FOREGROUND';
          description = 'App came to foreground';
          break;
        case AppLifecycleState.inactive:
          stateName = 'INACTIVE';
          description = 'App is inactive';
          break;
        case AppLifecycleState.paused:
          stateName = 'BACKGROUND';
          description = 'App went to background';
          break;
        case AppLifecycleState.detached:
          stateName = 'DETACHED';
          description = 'App is detached';
          break;
        case AppLifecycleState.hidden:
          stateName = 'HIDDEN';
          description = 'App is hidden';
          break;
      }
      
      _logAppState(stateName, description);
    } catch (e) {
      print('App lifecycle error: $e');
    }
  }

  Future<void> _logAppState(String state, String description) async {
    try {
      final serverUrl = _settings.getServerUrl();
      if (serverUrl.isEmpty) return;
      
      final message = '📱 App State: $state\n'
                     '• Description: $description\n'
                     '• Time: ${DateTime.now().toIso8601String()}';
      
      await _logSender.sendCustomLog(serverUrl, '', message, 'INFO');
      print('App state logged: $state');
      
      // Store for offline if needed
      if (!await _logSender.sendCustomLog(serverUrl, '', message, 'INFO')) {
        await BackgroundLogger.storeLogOffline('App state: $state - $description');
      }
    } catch (e) {
      print('Error logging app state: $e');
      await BackgroundLogger.storeLogOffline('App state $state failed: $e');
    }
  }

  Future<void> _checkPlatformCapabilities() async {
    try {
      await AdvancedMonitor.isMonitoringRunning();
    } catch (e) {
      if (e.toString().contains('MissingPluginException')) {
        print('⚠️ Native platform channels not available');
        setState(() {
          _showNativeWarning = true;
        });

        WidgetsBinding.instance.addPostFrameCallback((_) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                '⚠️ Native features unavailable - using basic monitoring',
              ),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 5),
            ),
          );
        });
      }
    }
  }

  Future<void> _loadCurrentSettings() async {
    await _settings.initialize();

    final serverUrl = _settings.getServerUrl();
    final apiKey = _settings.getApiKey();

    setState(() {
      _isConfigured = serverUrl.isNotEmpty;
      _isCollecting = _settings.getCollectLogs();
      _connectionMode = apiKey.isEmpty ? 'UDP' : 'REST API';
      _serverAddress = serverUrl;
    });

    await _checkMonitoringStatus();
    await _updateStats();

    // Start periodic stats update
    _statsTimer = Timer.periodic(const Duration(seconds: 10), (timer) async {
      if (_isCollecting) {
        await _updateStats();
      }
    });
  }

  Future<void> _updateStats() async {
    if (!mounted) return;

    final pendingLogs = await BackgroundLogger.getPendingLogsCount();
    final appEvents = await BackgroundLogger.getAppEventsCount();

    setState(() {
      _pendingLogsCount = pendingLogs;
      _appEventsCount = appEvents;
    });
  }

  Future<void> _checkMonitoringStatus() async {
    try {
      final isRunning = await AdvancedMonitor.isMonitoringRunning();
      setState(() {
        _isAdvancedMonitoring = isRunning;
      });
    } catch (e) {
      print('Error checking monitoring status: $e');
    }
  }

  Future<void> _testConnection() async {
    if (_isTesting) return;

    final serverUrl = _settings.getServerUrl();
    final apiKey = _settings.getApiKey();

    if (serverUrl.isEmpty) {
      _showMessage('Configure server address first', isError: true);
      return;
    }

    setState(() {
      _isTesting = true;
    });

    _showMessage('Testing connection...');

    try {
      bool isConnected;
      if (apiKey.isEmpty) {
        isConnected = await ConnectionTester.testUdp(serverUrl);
      } else {
        isConnected = await ConnectionTester.testRestApi(serverUrl, apiKey);
      }

      if (isConnected) {
        _showMessage('✅ Connection successful');
      } else {
        _showMessage('❌ Connection failed', isError: true);
      }
    } catch (e) {
      _showMessage('❌ Connection error: $e', isError: true);
    } finally {
      setState(() {
        _isTesting = false;
      });
    }
  }

  Future<void> _sendTestLog() async {
    final serverUrl = _settings.getServerUrl();
    final apiKey = _settings.getApiKey();

    if (serverUrl.isEmpty) {
      _showMessage('Configure server first', isError: true);
      return;
    }

    _showMessage('Sending test log...');

    setState(() {
      _isTesting = true;
    });

    try {
      final success = await _logSender.sendTestLog(serverUrl, apiKey);
      if (success) {
        _showMessage('✅ Test log sent successfully');
      } else {
        _showMessage('❌ Failed to send test log', isError: true);
      }
    } catch (e) {
      _showMessage('❌ Error: $e', isError: true);
    } finally {
      setState(() {
        _isTesting = false;
      });
    }
  }

  Future<void> _sendCustomLog() async {
    final serverUrl = _settings.getServerUrl();
    final apiKey = _settings.getApiKey();

    if (serverUrl.isEmpty) {
      _showMessage('Configure server first', isError: true);
      return;
    }

    TextEditingController messageController = TextEditingController(
      text: 'Test log from MHF Log Shield ${DateTime.now().toIso8601String()}',
    );
    String selectedLevel = 'INFO';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Send Custom Log'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                value: selectedLevel,
                items: ['INFO', 'WARNING', 'ERROR']
                    .map(
                      (level) =>
                          DropdownMenuItem(value: level, child: Text(level)),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) selectedLevel = value;
                },
                decoration: const InputDecoration(labelText: 'Log Level'),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: messageController,
                decoration: const InputDecoration(
                  labelText: 'Message',
                  hintText: 'Enter log message',
                ),
                maxLines: 3,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              _showMessage('Sending custom log...');

              setState(() {
                _isTesting = true;
              });

              final success = await _logSender.sendCustomLog(
                serverUrl,
                apiKey,
                messageController.text,
                selectedLevel,
              );

              setState(() {
                _isTesting = false;
              });

              if (success) {
                _showMessage('✅ Custom log sent');
              } else {
                _showMessage('❌ Failed to send custom log', isError: true);
              }
            },
            child: const Text('Send'),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleCollection() async {
    if (!_isConfigured) {
      _showMessage('Configure server first', isError: true);
      return;
    }

    final newState = !_isCollecting;

    setState(() {
      _isTesting = true;
    });

    try {
      if (newState) {
        // START ALL MONITORING
        await _startBasicMonitoring();
        await _startAppMonitoring();
        await _settings.setCollectLogs(true);
        setState(() {
          _isCollecting = true;
        });
        _showMessage('✅ Monitoring started');
      } else {
        // STOP ALL MONITORING
        await _stopBasicMonitoring();
        await _stopAppMonitoring();
        await _settings.setCollectLogs(false);
        setState(() {
          _isCollecting = false;
        });
        _showMessage('⏹️ Monitoring stopped');
      }
    } catch (e) {
      _showMessage('❌ Error: $e', isError: true);
    } finally {
      setState(() {
        _isTesting = false;
      });
    }
  }

  Future<void> _startBasicMonitoring() async {
    print('Starting basic monitoring');
    
    // Start real-time network monitoring
    _networkSubscription = Connectivity().onConnectivityChanged.listen((results) async {
      if (results.isNotEmpty && _isCollecting) {
        final networkStr = _getNetworkTypeString(results.first);
        
        try {
          final serverUrl = _settings.getServerUrl();
          if (serverUrl.isEmpty) return;
          
          final message = '🌐 Network changed: $networkStr\n'
                         '• Time: ${DateTime.now().toIso8601String()}';
          await _logSender.sendCustomLog(serverUrl, '', message, 'INFO');
          print('Network change logged: $networkStr');
        } catch (e) {
          print('Network monitoring error: $e');
          await BackgroundLogger.storeLogOffline('Network change failed: $e');
        }
      }
    });
    
    // Start simple periodic logging
    _monitoringTimer = Timer.periodic(const Duration(minutes: 5), (timer) async {
      if (!_isCollecting) {
        timer.cancel();
        return;
      }
      
      try {
        final serverUrl = _settings.getServerUrl();
        if (serverUrl.isEmpty) return;

        final battery = Battery();
        final connectivity = Connectivity();

        final batteryLevel = await battery.batteryLevel;
        final networkResults = await connectivity.checkConnectivity();
        final networkStr = networkResults.isNotEmpty
            ? _getNetworkTypeString(networkResults.first)
            : 'No Connection';

        final message =
            '📊 Basic Status | '
            'Platform: ${Platform.operatingSystem} | '
            'Battery: $batteryLevel% | '
            'Network: $networkStr';

        await _logSender.sendCustomLog(serverUrl, '', message, 'INFO');
        print('Basic status logged');
      } catch (e) {
        print('Basic monitoring error: $e');
        await BackgroundLogger.storeLogOffline('Basic status failed: $e');
      }
    });
  }

  Future<void> _stopBasicMonitoring() async {
    print('Stopping basic monitoring');
    _monitoringTimer?.cancel();
    _monitoringTimer = null;
    _networkSubscription?.cancel();
    _networkSubscription = null;
  }

  Future<void> _startAppMonitoring() async {
    try {
      // Start App Monitor for app install/uninstall detection
      _appMonitor = AppMonitor(_settings, _logSender);
      await _appMonitor!.startMonitoring();
      print('✅ App monitoring started');
      
      // Start Background Logger for offline storage
      await BackgroundLogger.startLogging();
      print('✅ Background logging started');
      
      // Start app state monitoring
      await _startAppStateMonitoring();
      
    } catch (e) {
      print('⚠️ App monitoring error: $e');
      // Fall back to basic only
    }
  }

  Future<void> _stopAppMonitoring() async {
    try {
      if (_appMonitor != null) {
        await _appMonitor!.stopMonitoring();
        _appMonitor = null;
        print('✅ App monitoring stopped');
      }
      
      await BackgroundLogger.stopBackgroundMonitoring();
      print('✅ Background logging stopped');
      
      _appStateTimer?.cancel();
      _appStateTimer = null;
      
    } catch (e) {
      print('⚠️ Error stopping app monitoring: $e');
    }
  }

  Future<void> _startAppStateMonitoring() async {
    try {
      // Start a timer to periodically log app state
      _appStateTimer = Timer.periodic(const Duration(minutes: 1), (timer) async {
        if (!_isCollecting) {
          timer.cancel();
          return;
        }
        
        await _logPeriodicAppState();
      });
      
      print('✅ App state monitoring started');
      
    } catch (e) {
      print('App state monitoring error: $e');
    }
  }

  Future<void> _logPeriodicAppState() async {
    try {
      final serverUrl = _settings.getServerUrl();
      if (serverUrl.isEmpty) return;
      
      // Get current time
      final now = DateTime.now();
      
      // Log current app state
      String appState = _currentAppState?.toString() ?? 'UNKNOWN';
      String stateTime = _lastAppStateChange?.toIso8601String() ?? 'N/A';
      
      // Get app count if AppMonitor is running
      int appCount = 0;
      if (_appMonitor != null) {
        appCount = await _appMonitor!.getInstalledAppsCount();
      }
      
      final message = '📱 Periodic App State\n'
                     '• Current State: $appState\n'
                     '• Last Change: $stateTime\n'
                     '• Installed Apps: $appCount\n'
                     '• Time: ${now.toIso8601String()}';
      
      await _logSender.sendCustomLog(serverUrl, '', message, 'INFO');
      print('Periodic app state logged');
      
    } catch (e) {
      print('Error logging periodic app state: $e');
      await BackgroundLogger.storeLogOffline('Periodic app state failed: $e');
    }
  }

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

  Future<void> _checkMonitoringStats() async {
    try {
      final stats = await AdvancedMonitor.getMonitoringStats();
      
      // Get additional stats
      int appCount = 0;
      if (_appMonitor != null) {
        appCount = await _appMonitor!.getInstalledAppsCount();
      }
      
      final batteryStatus = await _battery.batteryState;
      
      setState(() {
        _monitoringStats = {
          ...stats,
          'installed_apps': appCount,
          'battery_state': batteryStatus.toString(),
          'current_app_state': _currentAppState?.toString() ?? 'Unknown',
          'last_app_state_change': _lastAppStateChange?.toIso8601String() ?? 'N/A',
        };
      });

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Monitoring Statistics'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildStatItem('Status', _isCollecting ? 'Active' : 'Inactive'),
                _buildStatItem('Pending Logs', '$_pendingLogsCount'),
                _buildStatItem('App Events', '$_appEventsCount'),
                _buildStatItem('Installed Apps', '${_monitoringStats['installed_apps']}'),
                _buildStatItem('Current App State', _monitoringStats['current_app_state']),
                if (_monitoringStats['last_app_state_change'] != 'N/A')
                  _buildStatItem('Last State Change', _monitoringStats['last_app_state_change']),
                _buildStatItem('Battery State', _monitoringStats['battery_state']),
                if (_monitoringStats['current_interval'] != null)
                  _buildStatItem(
                    'Interval',
                    '${_monitoringStats['current_interval']} seconds',
                  ),
              ],
            ),
          ),
          actions: [
            if (_pendingLogsCount > 0)
              ElevatedButton(
                onPressed: () async {
                  Navigator.pop(context);
                  await _sendPendingLogs();
                },
                child: const Text('Send Pending Logs'),
              ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (e) {
      _showMessage('❌ Error checking stats: $e', isError: true);
    }
  }

  Future<void> _sendPendingLogs() async {
    _showMessage('Sending pending logs...');

    setState(() {
      _isTesting = true;
    });

    try {
      await BackgroundLogger.sendPendingLogs();
      await _updateStats();
      _showMessage('✅ Pending logs sent');
    } catch (e) {
      _showMessage('❌ Error: $e', isError: true);
    } finally {
      setState(() {
        _isTesting = false;
      });
    }
  }

  Future<void> _viewDeviceInfo() async {
    try {
      final batteryLevel = await _battery.batteryLevel;
      final batteryState = await _battery.batteryState;
      final networkResults = await _connectivity.checkConnectivity();
      final networkStr = networkResults.isNotEmpty 
          ? _getNetworkTypeString(networkResults.first)
          : 'No Connection';

      // Get app count if AppMonitor is running
      int appCount = 0;
      if (_appMonitor != null) {
        appCount = await _appMonitor!.getInstalledAppsCount();
      }

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Device Information'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildStatItem('Platform', _platformName),
                _buildStatItem('Battery', '$batteryLevel%'),
                _buildStatItem(
                  'Battery State',
                  _getBatteryStateString(batteryState),
                ),
                _buildStatItem('Network', networkStr),
                _buildStatItem(
                  'Monitoring',
                  _isCollecting ? 'Active' : 'Inactive',
                ),
                if (_isCollecting)
                  _buildStatItem('Apps Monitored', '$appCount'),
                if (_currentAppState != null)
                  _buildStatItem('App State', _currentAppState.toString()),
                if (_lastAppStateChange != null)
                  _buildStatItem('Last State Change', _lastAppStateChange!.toIso8601String()),
                if (_showNativeWarning)
                  _buildStatItem('Note', 'Using basic monitoring mode'),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (e) {
      _showMessage('❌ Error: $e', isError: true);
    }
  }

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

  void _showMessage(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('MHF Log Shield'),
        actions: [
          if (_pendingLogsCount > 0)
            Badge(
              label: Text('$_pendingLogsCount'),
              child: IconButton(
                icon: const Icon(Icons.cloud_upload),
                onPressed: _sendPendingLogs,
                tooltip: 'Send Pending Logs',
              ),
            ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SettingsScreen()),
              );
              await _loadCurrentSettings();
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildStatusCard(),
            const SizedBox(height: 16),
            _buildStatsCard(),
            const SizedBox(height: 16),
            _buildControlButtons(),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(
              _isCollecting ? Icons.security : Icons.security_outlined,
              size: 48,
              color: _isCollecting ? Colors.green : Colors.blue,
            ),
            const SizedBox(height: 12),
            Text(
              _isConfigured ? 'Ready' : 'Not Configured',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: _isConfigured ? Colors.green : Colors.orange,
              ),
            ),
            if (_serverAddress.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                _serverAddress,
                style: const TextStyle(fontSize: 14, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Mode: $_connectionMode',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.blue,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 8),
            if (_showNativeWarning)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.warning, size: 14, color: Colors.orange),
                    const SizedBox(width: 6),
                    const Text(
                      'Basic Mode',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.orange,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              )
            else if (_isCollecting)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.circle, size: 8, color: Colors.green),
                    const SizedBox(width: 6),
                    const Text(
                      'Active',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.green,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            if (_currentAppState != null && _isCollecting) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.purple.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.apps, size: 14, color: Colors.purple),
                    const SizedBox(width: 6),
                    Text(
                      'App: ${_currentAppState.toString().split('.').last}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.purple,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Row(
              children: [
                Icon(Icons.analytics, size: 20, color: Colors.blue),
                SizedBox(width: 8),
                Text(
                  'Monitoring Stats',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatWidget(
                  'Pending',
                  '$_pendingLogsCount',
                  Icons.cloud_upload,
                  Colors.orange,
                ),
                _buildStatWidget(
                  'App Events',
                  '$_appEventsCount',
                  Icons.apps,
                  Colors.green,
                ),
                _buildStatWidget(
                  'Status',
                  _isCollecting ? 'ON' : 'OFF',
                  _isCollecting ? Icons.play_arrow : Icons.stop,
                  _isCollecting ? Colors.green : Colors.red,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatWidget(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 24, color: color),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }

  Widget _buildControlButtons() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Start/Stop Monitoring Button
        ElevatedButton.icon(
          onPressed: _isTesting ? null : _toggleCollection,
          icon: _isTesting
              ? const SizedBox(
                  height: 24,
                  width: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(Colors.white),
                  ),
                )
              : Icon(_isCollecting ? Icons.stop : Icons.play_arrow),
          label: Text(
            _isCollecting ? 'Stop Monitoring' : 'Start Monitoring',
            style: const TextStyle(fontSize: 16),
          ),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
            backgroundColor: _isCollecting ? Colors.red : Colors.green,
          ),
        ),

        const SizedBox(height: 12),

        // Server Configuration Button
        if (!_isConfigured)
          ElevatedButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SettingsScreen()),
              ).then((_) => _loadCurrentSettings());
            },
            icon: const Icon(Icons.settings),
            label: const Text(
              'Configure Server',
              style: TextStyle(fontSize: 16),
            ),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),

        if (_isConfigured) ...[
          const SizedBox(height: 12),

          // Test Connection Button
          ElevatedButton.icon(
            onPressed: _isTesting ? null : _testConnection,
            icon: _isTesting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(Colors.white),
                    ),
                  )
                : const Icon(Icons.wifi),
            label: const Text('Test Connection'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              backgroundColor: Colors.orange,
            ),
          ),

          const SizedBox(height: 12),

          // Send Test Log Button
          ElevatedButton.icon(
            onPressed: _isTesting ? null : _sendTestLog,
            icon: const Icon(Icons.send),
            label: const Text('Send Test Log'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),

          const SizedBox(height: 12),

          // Device Info Button
          OutlinedButton.icon(
            onPressed: _isTesting ? null : _viewDeviceInfo,
            icon: const Icon(Icons.phone_android),
            label: const Text('Device Info'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),

          const SizedBox(height: 12),

          // Monitoring Statistics Button
          ElevatedButton.icon(
            onPressed: _isTesting ? null : _checkMonitoringStats,
            icon: const Icon(Icons.analytics),
            label: const Text('View Statistics'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              backgroundColor: Colors.blue,
            ),
          ),

          const SizedBox(height: 12),

          // Custom Log Button
          OutlinedButton.icon(
            onPressed: _isTesting ? null : _sendCustomLog,
            icon: const Icon(Icons.edit),
            label: const Text('Custom Log'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildStatItem(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text('$label:', style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(width: 8),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}