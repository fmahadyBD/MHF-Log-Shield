import 'dart:io';
import 'package:flutter/material.dart';
import 'package:mhf_log_shield/core/platform/platform_service_factory.dart';
import 'package:mhf_log_shield/data/repositories/settings_repository.dart';
import 'package:mhf_log_shield/services/advanced_monitor.dart';
import 'package:mhf_log_shield/ui/screens/settings_screen.dart';
import 'package:mhf_log_shield/utils/connection_tester.dart';
import 'package:mhf_log_shield/utils/log_sender.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final SettingsRepository _settings = SettingsRepository();
  final LogSender _logSender = LogSender();
  late final String _platformName;
  late final bool _isAndroid;
  
  bool _isConfigured = false;
  bool _isCollecting = false;
  bool _isAdvancedMonitoring = false;
  String _connectionMode = 'UDP';
  String _serverAddress = '';
  bool _isTesting = false;
  Map<String, dynamic> _monitoringStats = {};

  @override
  void initState() {
    super.initState();
    _platformName = Platform.operatingSystem;
    _isAndroid = Platform.isAndroid;
    _loadCurrentSettings();
    _checkPermissions();
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

    // Save server URL for platform components if configured
    if (serverUrl.isNotEmpty) {
      try {
        await AdvancedMonitor.saveServerUrlForNative(serverUrl);
      } catch (e) {
        print('Warning: Could not save server URL: $e');
      }
    }

    await _checkMonitoringStatus();
  }

  Future<void> _checkPermissions() async {
    if (_isAndroid) {
      try {
        final hasPermissions = await AdvancedMonitor.hasUsageStatsPermission();
        if (!hasPermissions) {
          await AdvancedMonitor.checkAndRequestPermissions();
        }
      } catch (e) {
        print('Error checking permissions: $e');
      }
    }
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
        _showMessage('Connection successful');
      } else {
        _showMessage('Connection failed', isError: true);
      }
    } catch (e) {
      _showMessage('Connection error: $e', isError: true);
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
        _showMessage('Test log sent successfully');
      } else {
        _showMessage('Failed to send test log', isError: true);
      }
    } catch (e) {
      _showMessage('Error: $e', isError: true);
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
      text: 'Test log from MHF Log Shield',
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
                    .map((level) => DropdownMenuItem(
                          value: level,
                          child: Text(level),
                        ))
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
                _showMessage('Custom log sent');
              } else {
                _showMessage('Failed to send custom log', isError: true);
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
    await _settings.setCollectLogs(newState);

    setState(() {
      _isCollecting = newState;
    });

    if (newState) {
      try {
        await AdvancedMonitor.startAdvancedMonitoring();
        await _checkMonitoringStatus();
        _showMessage('Monitoring started');
      } catch (e) {
        _showMessage('Error starting: $e', isError: true);
        await _settings.setCollectLogs(false);
        setState(() {
          _isCollecting = false;
        });
      }
    } else {
      try {
        await AdvancedMonitor.stopAdvancedMonitoring();
        await _checkMonitoringStatus();
        _showMessage('Monitoring stopped');
      } catch (e) {
        _showMessage('Error stopping: $e', isError: true);
      }
    }
  }

  Future<void> _checkMonitoringStats() async {
    _showMessage('Checking monitoring statistics...');

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
                _buildStatItem(
                  'Status',
                  _monitoringStats['is_running'] == true ? 'Active' : 'Inactive',
                ),
                if (_monitoringStats['current_interval'] != null)
                  _buildStatItem(
                    'Interval',
                    '${_monitoringStats['current_interval']} seconds',
                  ),
                if (_monitoringStats['events_processed'] != null)
                  _buildStatItem(
                    'Events Processed',
                    '${_monitoringStats['events_processed']}',
                  ),
                if (_monitoringStats['pending_events'] != null)
                  _buildStatItem(
                    'Pending Events',
                    '${_monitoringStats['pending_events']}',
                  ),
                if (_monitoringStats['last_foreground_app'] != null)
                  _buildStatItem(
                    'Last App',
                    _monitoringStats['last_foreground_app']?.toString() ?? 'None',
                  ),
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
      _showMessage('Error checking stats: $e', isError: true);
    }
  }

  Future<void> _testNativeReceivers() async {
    if (!_isConfigured) {
      _showMessage('Configure server first', isError: true);
      return;
    }

    if (!_isAndroid) {
      _showMessage('Native receivers only available on Android', isError: true);
      return;
    }

    _showMessage('Testing native receivers...');

    setState(() {
      _isTesting = true;
    });

    try {
      await AdvancedMonitor.testNativeReceivers();
      _showMessage('Native receivers test triggered');
    } catch (e) {
      _showMessage('Error: $e', isError: true);
    } finally {
      setState(() {
        _isTesting = false;
      });
    }
  }

  Future<void> _setMonitoringInterval() async {
    TextEditingController intervalController = TextEditingController(
      text: (_monitoringStats['current_interval'] ?? 30).toString(),
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Set Monitoring Interval'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: intervalController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Interval (seconds)',
                hintText: 'Enter interval in seconds',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final interval = int.tryParse(intervalController.text);
              if (interval != null && interval >= 5) {
                await AdvancedMonitor.setMonitoringInterval(interval);
                Navigator.pop(context);
                _showMessage('Interval set to $interval seconds');
                await _checkMonitoringStats();
              } else {
                _showMessage('Enter valid interval (min 5 seconds)', isError: true);
              }
            },
            child: const Text('Set'),
          ),
        ],
      ),
    );
  }

  void _showMessage(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('MHF Log Shield'),
        actions: [
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
            const SizedBox(height: 20),
            _buildCollectionCard(),
            const SizedBox(height: 20),
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
            const Icon(Icons.security, size: 48, color: Colors.blue),
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
              ),
              const SizedBox(height: 4),
              Text(
                'Mode: $_connectionMode',
                style: const TextStyle(fontSize: 12, color: Colors.blue),
              ),
            ],
            const SizedBox(height: 8),
            if (_isAdvancedMonitoring)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'Active',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.green,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              )
            else if (_isCollecting)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'Periodic',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.blue,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCollectionCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              _isCollecting ? Icons.play_arrow : Icons.stop,
              color: _isCollecting ? Colors.green : Colors.red,
              size: 32,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _isCollecting ? 'Monitoring Active' : 'Monitoring Inactive',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _isCollecting
                        ? 'Log collection is running'
                        : 'Log collection is paused',
                    style: const TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControlButtons() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Start/Stop Monitoring Button
        ElevatedButton(
          onPressed: _isTesting ? null : _toggleCollection,
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
            backgroundColor: _isCollecting ? Colors.red : Colors.green,
          ),
          child: _isTesting
              ? const SizedBox(
                  height: 24,
                  width: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(Colors.white),
                  ),
                )
              : Text(
                  _isCollecting ? 'Stop Monitoring' : 'Start Monitoring',
                  style: const TextStyle(fontSize: 16),
                ),
        ),

        const SizedBox(height: 12),

        // Server Configuration Button
        if (!_isConfigured)
          ElevatedButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SettingsScreen()),
              ).then((_) => _loadCurrentSettings());
            },
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: const Text(
              'Configure Server',
              style: TextStyle(fontSize: 16),
            ),
          ),

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

        if (_isAndroid) ...[
          const SizedBox(height: 12),
          // Test Native Receivers Button (Android only)
          OutlinedButton.icon(
            onPressed: _isTesting ? null : _testNativeReceivers,
            icon: const Icon(Icons.phone_android),
            label: const Text('Test Native Receivers'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        ],

        if (_isAdvancedMonitoring) ...[
          const SizedBox(height: 12),
          // Set Interval Button
          OutlinedButton.icon(
            onPressed: _isTesting ? null : _setMonitoringInterval,
            icon: const Icon(Icons.timer),
            label: const Text('Set Interval'),
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