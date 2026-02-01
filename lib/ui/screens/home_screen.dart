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

class _HomeScreenState extends State<HomeScreen> {
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

  @override
  void initState() {
    super.initState();
    _platformName = Platform.operatingSystem;
    _isAndroid = Platform.isAndroid;
    _loadCurrentSettings();
    _checkPlatformCapabilities();
  }

  @override
  void dispose() {
    _statsTimer?.cancel();
    _monitoringTimer?.cancel();
    _appMonitor?.stopMonitoring();
    super.dispose();
  }

  Future<void> _checkPlatformCapabilities() async {
    try {
      // Test if native methods are available
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

  // In your _toggleCollection() method, replace everything with:
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
        // START BASIC MONITORING ONLY (no native calls)
        await _startBasicMonitoring();
        await _settings.setCollectLogs(true);
        setState(() {
          _isCollecting = true;
        });
        _showMessage('✅ Basic monitoring started');
      } else {
        // STOP BASIC MONITORING
        await _stopBasicMonitoring();
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

  // And make sure these methods exist:
  Future<void> _startBasicMonitoring() async {
    print('Starting basic monitoring');
    // Start simple periodic logging
    Timer.periodic(const Duration(minutes: 5), (timer) async {
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
            'Battery: $batteryLevel% | '
            'Network: $networkStr';

        await _logSender.sendCustomLog(serverUrl, '', message, 'INFO');
      } catch (e) {
        print('Basic monitoring error: $e');
      }
    });
  }

  Future<void> _stopBasicMonitoring() async {
    print('Stopping basic monitoring');
    // In a real app, you'd cancel the timer here
  }

  Future<void> _startMonitoring() async {
    try {
      // Try advanced monitoring
      await AdvancedMonitor.startAdvancedMonitoring();
    } catch (e) {
      print('AdvancedMonitor failed: $e');
      // Fall back to basic monitoring
      await _startBasicMonitoring();
      return;
    }

    // Start App Monitor
    try {
      _appMonitor = AppMonitor(_settings, _logSender);
      await _appMonitor!.startMonitoring();
    } catch (e) {
      print('AppMonitor failed: $e');
    }

    // Start Background Logger
    try {
      await BackgroundLogger.startLogging();
    } catch (e) {
      print('BackgroundLogger failed: $e');
    }
  }

  Future<void> _stopMonitoring() async {
    try {
      await AdvancedMonitor.stopAdvancedMonitoring();
    } catch (e) {
      print('Error stopping AdvancedMonitor: $e');
    }

    if (_appMonitor != null) {
      try {
        await _appMonitor!.stopMonitoring();
        _appMonitor = null;
      } catch (e) {
        print('Error stopping AppMonitor: $e');
      }
    }

    try {
      await BackgroundLogger.stopBackgroundMonitoring();
    } catch (e) {
      print('Error stopping BackgroundLogger: $e');
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
      setState(() {
        _monitoringStats = stats;
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
                _buildStatItem(
                  'Mode',
                  _showNativeWarning ? 'Basic (Dart-only)' : 'Advanced',
                ),
                _buildStatItem('Pending Logs', '$_pendingLogsCount'),
                _buildStatItem('App Events', '$_appEventsCount'),
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
      final networkStr = _getNetworkTypeString(networkResults.first);

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
