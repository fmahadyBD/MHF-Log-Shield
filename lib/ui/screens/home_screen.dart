import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mhf_log_shield/data/repositories/settings_repository.dart';
import 'package:mhf_log_shield/services/background_logger.dart';
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
  bool _isConfigured = false;
  bool _isCollecting = false;
  bool _isAdvancedMonitoring = false;
  String _connectionMode = 'UDP';
  String _serverAddress = '';
  bool _isTesting = false;
  Map<String, dynamic> _monitoringStats = {};
  bool _hasUsagePermission = false;

  // Method channels
  static const MethodChannel _channel = MethodChannel('app_monitor_channel');
  static const MethodChannel _advancedChannel = MethodChannel(
    'advanced_monitor_channel',
  );

  @override
  void initState() {
    super.initState();
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

    // Save server URL for native components if configured
    if (serverUrl.isNotEmpty) {
      try {
        await _channel.invokeMethod('saveServerUrl', {'url': serverUrl});
        print('[HomeScreen] Server URL loaded and saved for native components');
      } catch (e) {
        print('[HomeScreen] Warning: Could not save server URL to native: $e');
      }
    }

    // Check if monitoring service is running
    await _checkMonitoringStatus();
  }

  Future<void> _testNativeReceivers() async {
    if (!_isConfigured) {
      _showMessage('Configure server first', isError: true);
      return;
    }

    _showMessage('Testing native receivers...');

    setState(() {
      _isTesting = true;
    });

    try {
      // Trigger a test event via native
      final success =
          await _advancedChannel.invokeMethod<bool>('triggerTestEvent') ??
          false;

      if (success) {
        _showMessage(
          'Native receivers test triggered. Check Wazuh server for test logs.',
        );

        // Show instructions
        WidgetsBinding.instance.addPostFrameCallback((_) {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Native Receivers Test'),
              content: const Text(
                'Native components (Screen, Power, App Install receivers) have been triggered.\n\n'
                'Check your Wazuh server for test logs:\n'
                'sudo tail -f /var/ossec/logs/archives/archives.log | grep -i "TEST_EVENT"\n\n'
                'You should see test logs from:\n'
                '• Screen receiver\n'
                '• Power receiver\n'
                '• App install receiver',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        });
      } else {
        _showMessage('Failed to trigger native receivers test', isError: true);
      }
    } catch (e) {
      print('Native receivers test error: $e');
      _showMessage('Error: $e', isError: true);
    } finally {
      setState(() {
        _isTesting = false;
      });
    }
  }

  Future<void> _checkPermissions() async {
    try {
      final hasAllPermissions =
          await _channel.invokeMethod<bool>('checkPermissions') ?? false;
      final hasUsagePerm =
          await _channel.invokeMethod<bool>('hasUsageStatsPermission') ?? false;

      setState(() {
        _hasUsagePermission = hasUsagePerm;
      });

      if (!hasAllPermissions) {
        await _channel.invokeMethod('checkAndRequestAllPermissions');
      }
    } catch (e) {
      print('Error checking permissions: $e');
    }
  }

  Future<void> _checkMonitoringStatus() async {
    try {
      final isRunning =
          await _advancedChannel.invokeMethod<bool>('isMonitoringRunning') ??
          false;
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
      _showMessage('Please configure server address first', isError: true);
      return;
    }

    setState(() {
      _isTesting = true;
    });

    _showMessage('Testing connection...');

    bool isConnected;

    try {
      if (apiKey.isEmpty) {
        isConnected = await ConnectionTester.testUdp(serverUrl);
      } else {
        isConnected = await ConnectionTester.testRestApi(serverUrl, apiKey);
      }

      if (isConnected) {
        _showMessage('Connection successful to $_serverAddress');
      } else {
        _showMessage('Connection failed to $_serverAddress', isError: true);
      }
    } catch (e) {
      print('Connection test error: $e');
      _showMessage('Test error: $e', isError: true);
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
        _showMessage('Test log sent to $_serverAddress');

        // Show verification instructions
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _showVerificationInstructions();
        });
      } else {
        _showMessage('Failed to send test log', isError: true);
      }
    } catch (e) {
      print('Test log error: $e');
      _showMessage('Error: $e', isError: true);
    } finally {
      setState(() {
        _isTesting = false;
      });
    }
  }

  Future<void> _sendMultipleTestLogs() async {
    final serverUrl = _settings.getServerUrl();
    final apiKey = _settings.getApiKey();

    if (serverUrl.isEmpty) {
      _showMessage('Configure server first', isError: true);
      return;
    }

    _showMessage('Sending multiple test formats...');

    setState(() {
      _isTesting = true;
    });

    try {
      final results = await _logSender.sendMultipleTestLogs(serverUrl, apiKey);

      final successCount = results.where((r) => r).length;

      if (successCount > 0) {
        _showMessage(
          '$successCount out of ${results.length} test logs sent successfully',
        );

        // Show verification help
        WidgetsBinding.instance.addPostFrameCallback((_) {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Check Wazuh Server'),
              content: const Text(
                'Test logs sent with 3 different formats:\n'
                '1. Syslog format (RFC3164)\n'
                '2. Simple text format\n'
                '3. Key=Value format\n\n'
                'Check Wazuh logs to see which format is accepted:\n'
                'sudo tail -f /var/ossec/logs/archives/archives.log',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        });
      } else {
        _showMessage('All test logs failed', isError: true);
      }
    } catch (e) {
      print('Multiple test logs error: $e');
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
      text: 'Custom test log from MHF Log Shield app',
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
                initialValue: selectedLevel,
                items: ['DEBUG', 'INFO', 'WARNING', 'ERROR', 'CRITICAL']
                    .map(
                      (level) =>
                          DropdownMenuItem(value: level, child: Text(level)),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) {
                    selectedLevel = value;
                  }
                },
                decoration: const InputDecoration(labelText: 'Log Level'),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: messageController,
                decoration: const InputDecoration(
                  labelText: 'Log Message',
                  hintText: 'Enter test message',
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
                _showMessage('Custom log sent successfully');
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

  void _showVerificationInstructions() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Verify on Wazuh Server'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('To verify logs reached Wazuh:'),
              const SizedBox(height: 16),
              const Text('1. On Wazuh server (192.168.0.117), run:'),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                color: Colors.black87,
                child: const SelectableText(
                  '# Check if logs appear in archives\n'
                  'sudo tail -f /var/ossec/logs/archives/archives.log | grep -i mhf\n\n'
                  '# Check alerts\n'
                  'sudo tail -f /var/ossec/logs/alerts/alerts.log | grep -i mhf',
                  style: TextStyle(
                    color: Colors.white,
                    fontFamily: 'Monospace',
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text('2. Check Wazuh dashboard:'),
              const Text('   • Go to Security Events'),
              const Text('   • Filter by: app_name:MHF_Log_Shield'),
              const Text('   • Or search for: MHFLogShield'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
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

    // Update settings first
    await _settings.setCollectLogs(newState);

    setState(() {
      _isCollecting = newState;
    });

    if (newState) {
      // START ADVANCED MONITORING
      try {
        // First, ensure server URL is saved for native components
        final serverUrl = _settings.getServerUrl();
        if (serverUrl.isNotEmpty) {
          try {
            await _channel.invokeMethod('saveServerUrl', {'url': serverUrl});
            print(
              '[HomeScreen] Server URL saved for native components: $serverUrl',
            );
          } catch (e) {
            print(
              '[HomeScreen] Warning: Could not save server URL to native: $e',
            );
            // Continue anyway - native components might use fallback
          }
        }

        // Start basic foreground service
        await _channel.invokeMethod('startForegroundService');

        // Start advanced monitoring service
        await _advancedChannel.invokeMethod('startMonitoringService');

        // Send initial confirmation
        await _sendInitialConfirmationLog();

        // Update monitoring status
        await _checkMonitoringStatus();

        _showMessage('Advanced monitoring started - Real-time tracking active');
      } catch (e) {
        print('Error starting monitoring: $e');
        _showMessage('Error starting: $e', isError: true);
        // Revert state on error
        await _settings.setCollectLogs(false);
        setState(() {
          _isCollecting = false;
        });
      }
    } else {
      // STOP ADVANCED MONITORING
      try {
        await _advancedChannel.invokeMethod('stopMonitoringService');
        await _channel.invokeMethod('stopForegroundService');

        await _sendStopConfirmationLog();
        await _checkMonitoringStatus();

        _showMessage('Monitoring stopped');
      } catch (e) {
        print('Error stopping monitoring: $e');
        _showMessage('Error stopping: $e', isError: true);
      }
    }
  }

  Future<void> _sendInitialConfirmationLog() async {
    final serverUrl = _settings.getServerUrl();
    final apiKey = _settings.getApiKey();

    if (serverUrl.isEmpty) return;

    try {
      final message =
          '🚀 MHF Log Shield | ADVANCED MONITORING STARTED | '
          'Device: ${Platform.operatingSystem} | '
          'Real-time tracking: ENABLED';
      await _logSender.sendCustomLog(serverUrl, apiKey, message, 'INFO');
      print('[HomeScreen] Advanced monitoring started log sent');
    } catch (e) {
      print('[HomeScreen] Error sending initial log: $e');
    }
  }

  Future<void> _sendStopConfirmationLog() async {
    final serverUrl = _settings.getServerUrl();
    final apiKey = _settings.getApiKey();

    if (serverUrl.isEmpty) return;

    try {
      final message =
          '🛑 MHF Log Shield | MONITORING STOPPED | '
          'Device: ${Platform.operatingSystem}';
      await _logSender.sendCustomLog(serverUrl, apiKey, message, 'INFO');
      print('[HomeScreen] Stop confirmation log sent');
    } catch (e) {
      print('[HomeScreen] Error sending stop log: $e');
    }
  }

  Future<void> _debugLogSending() async {
    final serverUrl = _settings.getServerUrl();
    if (serverUrl.isEmpty) {
      _showMessage('Configure server first', isError: true);
      return;
    }

    setState(() {
      _isTesting = true;
    });

    _showMessage('Running debug tests...');

    try {
      final success = await LogSender.debugLogSending(serverUrl);

      if (success) {
        _showMessage('Debug test PASSED - logs should send');
      } else {
        _showMessage('Debug test FAILED - check console logs', isError: true);
      }
    } catch (e) {
      _showMessage('Debug error: $e', isError: true);
    } finally {
      setState(() {
        _isTesting = false;
      });
    }
  }

  Future<void> _checkMonitoringStats() async {
    _showMessage('Checking monitoring statistics...');

    try {
      final stats = await _advancedChannel.invokeMethod<Map<dynamic, dynamic>>(
        'getMonitoringStats',
      );
      final eventsCount = await _advancedChannel
          .invokeMethod<Map<dynamic, dynamic>>('getPendingEventsCount');

      setState(() {
        _monitoringStats = Map<String, dynamic>.from(stats ?? {});
      });

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Real-time Monitoring Statistics'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildStatItem(
                  'Monitoring Service',
                  _monitoringStats['is_running'] == true
                      ? 'RUNNING ✅'
                      : 'STOPPED ❌',
                ),
                _buildStatItem(
                  'Current Interval',
                  '${_monitoringStats['current_interval'] ?? 30} seconds',
                ),
                _buildStatItem(
                  'Events Processed',
                  '${_monitoringStats['events_processed'] ?? 0}',
                ),
                _buildStatItem(
                  'Pending Events',
                  '${_monitoringStats['pending_events'] ?? 0}',
                ),
                const SizedBox(height: 12),
                const Text(
                  '📊 Detailed Events:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                ..._buildDetailedEvents(eventsCount),
                const SizedBox(height: 12),
                const Text(
                  '🔒 Permissions:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                _buildStatItem(
                  'Usage Stats',
                  _monitoringStats['has_usage_permission'] == true
                      ? 'GRANTED ✅'
                      : 'DENIED ❌',
                ),
                _buildStatItem(
                  'Notifications',
                  _monitoringStats['has_notification_permission'] == true
                      ? 'GRANTED ✅'
                      : 'DENIED ❌',
                ),
                const SizedBox(height: 12),
                const Text(
                  '📱 Recent Activity:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                _buildStatItem(
                  'Last App',
                  _monitoringStats['last_foreground_app']?.toString() ?? 'None',
                ),
                _buildStatItem(
                  'Last Screen Event',
                  _monitoringStats['last_screen_event']?.toString() ?? 'None',
                ),
                _buildStatItem(
                  'Last Power Event',
                  _monitoringStats['last_power_event']?.toString() ?? 'None',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
            if ((_monitoringStats['pending_events'] as int? ?? 0) > 0)
              TextButton(
                onPressed: () async {
                  await _advancedChannel.invokeMethod('clearMonitoringData');
                  Navigator.pop(context);
                  _showMessage('Monitoring data cleared');
                },
                child: const Text('Clear Data'),
              ),
          ],
        ),
      );
    } catch (e) {
      print('Error getting monitoring stats: $e');
      _showMessage('Error checking service: $e', isError: true);
    }
  }

  List<Widget> _buildDetailedEvents(Map<dynamic, dynamic>? eventsCount) {
    final counts = Map<String, dynamic>.from(eventsCount ?? {});
    return counts.entries.map((entry) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            const SizedBox(width: 16),
            Text(
              '• ${entry.key}: ',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            Text('${entry.value}'),
          ],
        ),
      );
    }).toList();
  }

  Future<void> _requestUsagePermission() async {
    try {
      await _channel.invokeMethod('requestUsageStatsPermission');
      _showMessage('Please grant permission in settings');
      await Future.delayed(const Duration(seconds: 2));
      await _checkPermissions();
    } catch (e) {
      print('Error requesting usage permission: $e');
      _showMessage('Error requesting permission: $e', isError: true);
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
            const Text('Set how often to check for changes (in seconds).'),
            const SizedBox(height: 16),
            const Text('Recommended intervals:'),
            const Text('• 10-30 seconds: High accuracy (battery impact)'),
            const Text('• 30-60 seconds: Balanced'),
            const Text('• 60-300 seconds: Battery saving'),
            const SizedBox(height: 16),
            TextFormField(
              controller: intervalController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Interval (seconds)',
                hintText: 'Enter interval in seconds',
              ),
              validator: (value) {
                if (value == null || value.isEmpty)
                  return 'Please enter interval';
                final intVal = int.tryParse(value);
                if (intVal == null || intVal < 5) return 'Minimum 5 seconds';
                return null;
              },
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
                await _advancedChannel.invokeMethod('setMonitoringInterval', {
                  'seconds': interval,
                });
                Navigator.pop(context);
                _showMessage('Monitoring interval set to $interval seconds');
                await _checkMonitoringStats();
              } else {
                _showMessage(
                  'Please enter a valid interval (minimum 5 seconds)',
                  isError: true,
                );
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
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildStatusCard(),
            const SizedBox(height: 20),
            _buildCollectionCard(),
            const SizedBox(height: 20),
            _buildControlButtons(),
            const SizedBox(height: 20),
            _buildInfoSection(),
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
            const Icon(Icons.shield, size: 50, color: Colors.blue),
            const SizedBox(height: 10),
            Text(
              _isConfigured ? 'Ready' : 'Not Configured',
              style: TextStyle(
                fontSize: 20,
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
              Text(
                'Mode: $_connectionMode',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue,
                ),
              ),
              const SizedBox(height: 8),
              if (_isAdvancedMonitoring)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.green),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.notifications_active,
                        size: 14,
                        color: Colors.green,
                      ),
                      SizedBox(width: 4),
                      Text(
                        'REAL-TIME MONITORING',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.green,
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
                    color: Colors.blue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.blue),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.timer, size: 14, color: Colors.blue),
                      SizedBox(width: 4),
                      Text(
                        'PERIODIC MONITORING',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.blue,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              if (!_hasUsagePermission && _isCollecting)
                Container(
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.orange),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.warning, size: 14, color: Colors.orange),
                      const SizedBox(width: 4),
                      Text(
                        'MISSING PERMISSION',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.orange,
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

  Widget _buildCollectionCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              _isCollecting ? Icons.play_arrow : Icons.stop,
              color: _isCollecting ? Colors.green : Colors.red,
              size: 30,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _isCollecting
                        ? (_isAdvancedMonitoring
                              ? 'Real-time Monitoring'
                              : 'Periodic Monitoring')
                        : 'Stopped',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _isCollecting
                        ? '${_isAdvancedMonitoring ? 'Instant detection of:' : 'Checking every 15 min:'}\n'
                              '• App installs/uninstalls\n'
                              '• Screen on/off\n'
                              '• App usage\n'
                              '• Battery & network'
                        : 'Collection is paused',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    maxLines: 5,
                  ),
                  if (_isCollecting) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _checkMonitoringStats,
                            icon: const Icon(Icons.analytics, size: 16),
                            label: const Text('View Stats'),
                            style: ElevatedButton.styleFrom(
                              minimumSize: const Size(double.infinity, 36),
                              backgroundColor: Colors.blue.shade50,
                              foregroundColor: Colors.blue,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (_isAdvancedMonitoring)
                          IconButton(
                            onPressed: _setMonitoringInterval,
                            icon: const Icon(Icons.timer, size: 20),
                            tooltip: 'Set interval',
                            style: IconButton.styleFrom(
                              backgroundColor: Colors.blue.shade50,
                              foregroundColor: Colors.blue,
                            ),
                          ),
                      ],
                    ),
                  ],
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
        // Configure/Start-Stop Button
        if (_isConfigured)
          ElevatedButton(
            onPressed: _isTesting ? null : _toggleCollection,
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 50),
              backgroundColor: _isCollecting ? Colors.red : Colors.green,
              disabledBackgroundColor: Colors.grey,
            ),
            child: _isTesting
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(Colors.white),
                    ),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(_isCollecting ? Icons.stop : Icons.play_arrow),
                      const SizedBox(width: 10),
                      Text(
                        _isCollecting ? 'Stop Monitoring' : 'Start Monitoring',
                        style: const TextStyle(fontSize: 16),
                      ),
                    ],
                  ),
          )
        else
          ElevatedButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SettingsScreen()),
              ).then((_) => _loadCurrentSettings());
            },
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 50),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.settings),
                SizedBox(width: 10),
                Text('Configure Server', style: TextStyle(fontSize: 16)),
              ],
            ),
          ),

        const SizedBox(height: 12),

        // Permission Request Button (if needed)
        if (!_hasUsagePermission && Platform.isAndroid)
          OutlinedButton.icon(
            onPressed: _isTesting ? null : _requestUsagePermission,
            icon: const Icon(Icons.lock_open, size: 18),
            label: const Text('Grant App Usage Permission'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.orange,
              side: const BorderSide(color: Colors.orange),
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
            minimumSize: const Size(double.infinity, 50),
            backgroundColor: Colors.orange,
            disabledBackgroundColor: Colors.grey,
          ),
        ),

        const SizedBox(height: 12),

        // Send Test Log Button
        ElevatedButton.icon(
          onPressed: _isTesting ? null : _sendTestLog,
          icon: const Icon(Icons.send),
          label: const Text('Send Test Log'),
          style: ElevatedButton.styleFrom(
            minimumSize: const Size(double.infinity, 50),
            backgroundColor: Colors.purple,
            disabledBackgroundColor: Colors.grey,
          ),
        ),

        const SizedBox(height: 12),

        // Monitoring Stats Button
        ElevatedButton.icon(
          onPressed: _isTesting ? null : _checkMonitoringStats,
          icon: const Icon(Icons.analytics),
          label: const Text('Monitoring Statistics'),
          style: ElevatedButton.styleFrom(
            minimumSize: const Size(double.infinity, 50),
            backgroundColor: Colors.blue,
            disabledBackgroundColor: Colors.grey,
          ),
        ),

        const SizedBox(height: 12),

        // Multiple Format Test Button
        OutlinedButton.icon(
          onPressed: _isTesting ? null : _sendMultipleTestLogs,
          icon: const Icon(Icons.format_list_bulleted, size: 18),
          label: const Text('Test Multiple Formats'),
        ),

        const SizedBox(height: 12),

        // Debug Button
        OutlinedButton.icon(
          onPressed: _isTesting ? null : _debugLogSending,
          icon: const Icon(Icons.bug_report, size: 18),
          label: const Text('Debug Log Sending'),
          style: OutlinedButton.styleFrom(foregroundColor: Colors.orange),
        ),

        const SizedBox(height: 12),

        // Test Native Receivers Button
        OutlinedButton.icon(
          onPressed: _isTesting ? null : _testNativeReceivers,
          icon: const Icon(Icons.android, size: 18),
          label: const Text('Test Native Receivers'),
          style: OutlinedButton.styleFrom(foregroundColor: Colors.deepPurple),
        ),

        const SizedBox(height: 12),

        // Set Interval Button (only when monitoring)
        if (_isAdvancedMonitoring)
          OutlinedButton.icon(
            onPressed: _isTesting ? null : _setMonitoringInterval,
            icon: const Icon(Icons.timer, size: 18),
            label: const Text('Set Monitoring Interval'),
            style: OutlinedButton.styleFrom(foregroundColor: Colors.teal),
          ),

        const SizedBox(height: 12),

        // Custom Log Button
        OutlinedButton.icon(
          onPressed: _isTesting ? null : _sendCustomLog,
          icon: const Icon(Icons.edit, size: 18),
          label: const Text('Custom Log'),
        ),
      ],
    );
  }

  Widget _buildInfoSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Monitoring Capabilities',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 12),
            _buildCapabilityItem(
              '✅ Instant Detection',
              'App installs/uninstalls, Screen on/off',
            ),
            _buildCapabilityItem('⏱️ 2-5 Seconds', 'App foreground changes'),
            _buildCapabilityItem(
              '⏱️ 30 Seconds',
              'Network connectivity changes',
            ),
            _buildCapabilityItem(
              '⏱️ 1-5 Minutes',
              'Battery level, App usage statistics',
            ),
            const SizedBox(height: 12),
            const Text(
              'Real-time Features:',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 8),
            const Text('• App installation/uninstallation (instant)'),
            const Text('• Screen ON/OFF detection (instant)'),
            const Text('• Power connection events (instant)'),
            const Text('• App foreground changes (2-5 seconds)'),
            const Text('• Network type changes (30 seconds)'),
            const Text('• Battery monitoring (1-5 minutes)'),
            const SizedBox(height: 12),
            const Text(
              'To verify on Wazuh:',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const Text('sudo tail -f /var/ossec/logs/archives/archives.log'),
            const Text('Filter by: MHFLogShield or mobile-device'),
          ],
        ),
      ),
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

  Widget _buildCapabilityItem(String title, String description) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              description,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }
}
