import 'package:flutter/material.dart';
import 'package:mhf_log_shield/data/repositories/settings_repository.dart';
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
  String _connectionMode = 'UDP';
  String _serverAddress = '';
  bool _isTesting = false;

  @override
  void initState() {
    super.initState();
    _loadCurrentSettings();
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
        _showMessage('$successCount out of ${results.length} test logs sent successfully');
        
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
                'sudo tail -f /var/ossec/logs/archives/archives.log'
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
      text: 'Custom test log from MHF Log Shield app'
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
                items: ['DEBUG', 'INFO', 'WARNING', 'ERROR', 'CRITICAL']
                    .map((level) => DropdownMenuItem(
                          value: level,
                          child: Text(level),
                        ))
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

  void _toggleCollection() {
    if (!_isConfigured) {
      _showMessage('Configure server first', isError: true);
      return;
    }
    
    final newState = !_isCollecting;
    
    setState(() {
      _isCollecting = newState;
    });
    
    _settings.setCollectLogs(newState);
    
    _showMessage(
      newState ? 'Log collection started' : 'Log collection stopped',
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
                style: const TextStyle(
                  fontSize: 14,
                  color: Colors.grey,
                ),
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
                    _isCollecting ? 'Collecting Logs' : 'Stopped',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _isCollecting 
                      ? 'Logs are being sent to $_serverAddress'
                      : 'Collection is paused',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade600,
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
                        _isCollecting ? 'Stop Collection' : 'Start Collection',
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
        
        // Multiple Format Test Button
        OutlinedButton.icon(
          onPressed: _isTesting ? null : _sendMultipleTestLogs,
          icon: const Icon(Icons.format_list_bulleted, size: 18),
          label: const Text('Test Multiple Formats'),
        ),
        
        const SizedBox(height: 12),
        
        // Manual Sync Button
        ElevatedButton.icon(
          onPressed: () {
            _showMessage('Manual sync feature coming soon');
          },
          icon: const Icon(Icons.sync),
          label: const Text('Manual Sync'),
          style: ElevatedButton.styleFrom(
            minimumSize: const Size(double.infinity, 50),
          ),
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
              'App Status',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 12),
            _buildStatusRow('Server Configuration', _isConfigured ? 'Configured' : 'Not configured'),
            _buildStatusRow('Connection Mode', _connectionMode),
            _buildStatusRow('Log Collection', _isCollecting ? 'Active' : 'Inactive'),
            const SizedBox(height: 12),
            const Text(
              'Log Testing:',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 8),
            const Text('• "Send Test Log": Tries 4 different formats'),
            const Text('• "Test Multiple Formats": Sends 3 formats separately'),
            const Text('• "Custom Log": Send specific messages'),
            const SizedBox(height: 8),
            const Text(
              'To verify on Wazuh:',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
            const Text('sudo tail -f /var/ossec/logs/archives/archives.log'),
            const Text('Filter by: MHFLogShield or mobile-device'),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text('$label:', style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(width: 8),
          Text(
            value,
            style: TextStyle(
              color: value.contains('Not') || value.contains('Inactive')
                  ? Colors.orange
                  : Colors.green,
            ),
          ),
        ],
      ),
    );
  }
}