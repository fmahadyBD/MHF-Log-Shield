import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mhf_log_shield/data/repositories/settings_repository.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final SettingsRepository _settings = SettingsRepository();
  static const MethodChannel _channel = MethodChannel('app_monitor_channel');
  
  final TextEditingController _serverUrlController = TextEditingController();
  final TextEditingController _apiKeyController = TextEditingController();
  
  bool _autoSync = true;
  bool _collectLogs = false;
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadCurrentSettings();
  }

  Future<void> _loadCurrentSettings() async {
    await _settings.initialize();
    
    setState(() {
      _serverUrlController.text = _settings.getServerUrl();
      _apiKeyController.text = _settings.getApiKey();
      _autoSync = _settings.getAutoSync();
      _collectLogs = _settings.getCollectLogs();
      _isLoading = false;
    });
  }

  Future<void> _saveSettings() async {
    if (_isSaving) return;
    
    final serverUrl = _serverUrlController.text.trim();
    
    // Validate server URL if provided
    if (serverUrl.isNotEmpty) {
      if (!_isValidServerUrl(serverUrl)) {
        _showMessage('Invalid server address format', isError: true);
        return;
      }
    }
    
    setState(() {
      _isSaving = true;
    });
    
    try {
      // Save to settings repository
      await _settings.setServerUrl(serverUrl);
      await _settings.setApiKey(_apiKeyController.text.trim());
      await _settings.setAutoSync(_autoSync);
      await _settings.setCollectLogs(_collectLogs);
      
      // NEW: Also save server URL for native components
      if (serverUrl.isNotEmpty) {
        try {
          await _channel.invokeMethod('saveServerUrl', {'url': serverUrl});
          print('[SettingsScreen] Server URL saved for native components');
        } catch (e) {
          print('[SettingsScreen] Error saving URL to native: $e');
          // Continue anyway - this is not critical
        }
      }
      
      // Show success message
      _showMessage('Settings saved successfully!');
      
      // Wait a bit before navigating back
      await Future.delayed(const Duration(milliseconds: 500));
      
      if (mounted) {
        Navigator.pop(context);
      }
      
    } catch (e) {
      _showMessage('Error saving settings: $e', isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  bool _isValidServerUrl(String url) {
    // Remove protocol if present
    var cleanUrl = url;
    if (cleanUrl.startsWith('http://')) {
      cleanUrl = cleanUrl.substring(7);
    } else if (cleanUrl.startsWith('https://')) {
      cleanUrl = cleanUrl.substring(8);
    }
    
    // Check if it's IP:port format or just IP
    final parts = cleanUrl.split(':');
    if (parts.length > 2) return false;
    
    // Validate IP address
    final ipPattern = RegExp(
      r'^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$'
    );
    
    if (!ipPattern.hasMatch(parts[0])) {
      // Could be a hostname - allow it
      return true;
    }
    
    // Validate IP parts
    final ipParts = parts[0].split('.');
    for (var part in ipParts) {
      final num = int.tryParse(part);
      if (num == null || num < 0 || num > 255) {
        return false;
      }
    }
    
    return true;
  }

  void _showMessage(String message, {bool isError = false}) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError ? Colors.red : Colors.green,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        actions: [
          IconButton(
            icon: _isSaving 
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(Colors.white),
                    ),
                  )
                : const Icon(Icons.save),
            onPressed: _isSaving ? null : _saveSettings,
            tooltip: 'Save Settings',
          ),
        ],
      ),
      body: _buildSettingsForm(),
    );
  }

  Widget _buildSettingsForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Wazuh Server Section
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Wazuh Server Configuration',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _serverUrlController,
                    decoration: const InputDecoration(
                      labelText: 'Server Address*',
                      hintText: '192.168.1.100 or 192.168.1.100:1514',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.dns),
                    ),
                    onChanged: (value) {
                      // Auto-add default port if missing
                      if (value.isNotEmpty && 
                          !value.contains(':') && 
                          !value.contains('http')) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (_serverUrlController.text == value) {
                            _serverUrlController.text = '$value:1514';
                            _serverUrlController.selection = TextSelection.fromPosition(
                              TextPosition(offset: _serverUrlController.text.length)
                            );
                          }
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Default port: 1514 for UDP, 55000 for REST API',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _apiKeyController,
                    decoration: const InputDecoration(
                      labelText: 'API Key (Optional)',
                      hintText: 'Leave empty for UDP mode',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.key),
                    ),
                    obscureText: true,
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Note: Empty API key = UDP mode (port 1514)\n'
                    'With API key = REST API mode (port 55000)\n'
                    'Recommended: Use UDP mode for better performance',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 20),
          
          // Connection Test Section
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Test Connection',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Before enabling monitoring, test that logs can reach your Wazuh server.',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _isSaving ? null : _testConnection,
                    icon: const Icon(Icons.wifi_find, size: 20),
                    label: const Text('Test Connection Now'),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 48),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Check Wazuh server after testing:',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const Text(
                    'sudo tail -f /var/ossec/logs/archives/archives.log',
                    style: TextStyle(
                      fontSize: 11,
                      fontFamily: 'Monospace',
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 20),
          
          // App Settings Section
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'App Settings',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 20),
                  SwitchListTile(
                    title: const Text('Auto Sync'),
                    subtitle: const Text('Automatically sync logs with server'),
                    value: _autoSync,
                    onChanged: (value) {
                      setState(() {
                        _autoSync = value;
                      });
                    },
                  ),
                  SwitchListTile(
                    title: const Text('Collect Logs'),
                    subtitle: const Text('Start collecting logs automatically'),
                    value: _collectLogs,
                    onChanged: (value) {
                      setState(() {
                        _collectLogs = value;
                      });
                    },
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 30),
          
          // Save Button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isSaving ? null : _saveSettings,
              icon: _isSaving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation(Colors.white),
                      ),
                    )
                  : const Icon(Icons.save),
              label: Text(
                _isSaving ? 'Saving...' : 'Save Settings',
                style: const TextStyle(fontSize: 16),
              ),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: Colors.blue,
                disabledBackgroundColor: Colors.grey,
              ),
            ),
          ),
          
          const SizedBox(height: 20),
          
          // Clear Settings Button
          OutlinedButton.icon(
            onPressed: _isSaving ? null : _clearSettings,
            icon: const Icon(Icons.delete_outline, size: 20),
            label: const Text('Clear All Settings'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 48),
              foregroundColor: Colors.red,
              side: const BorderSide(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _testConnection() async {
    final serverUrl = _serverUrlController.text.trim();
    final apiKey = _apiKeyController.text.trim();
    
    if (serverUrl.isEmpty) {
      _showMessage('Please enter server address first', isError: true);
      return;
    }
    
    // Save temporarily for testing
    await _settings.setServerUrl(serverUrl);
    if (apiKey.isNotEmpty) {
      await _settings.setApiKey(apiKey);
    }
    
    // Navigate back to home to test
    if (mounted) {
      Navigator.pop(context);
      // Trigger test in home screen
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Go to Home screen and click "Test Connection"'),
            duration: Duration(seconds: 5),
          ),
        );
      });
    }
  }
  
  Future<void> _clearSettings() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Settings'),
        content: const Text('Are you sure you want to clear all settings?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    
    if (confirmed == true) {
      setState(() {
        _isSaving = true;
      });
      
      try {
        await _settings.clearAll();
        
        // Clear controllers
        _serverUrlController.clear();
        _apiKeyController.clear();
        
        // Reset to defaults
        setState(() {
          _autoSync = true;
          _collectLogs = false;
        });
        
        _showMessage('All settings cleared');
        
      } catch (e) {
        _showMessage('Error clearing settings: $e', isError: true);
      } finally {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }
}