import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:mhf_log_shield/data/repositories/settings_repository.dart';
import 'package:mhf_log_shield/ui/screens/home_screen.dart';
import 'package:mhf_log_shield/utils/connection_tester.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final SettingsRepository _settings = SettingsRepository();

  
  final TextEditingController _serverUrlController = TextEditingController();
  final TextEditingController _apiKeyController = TextEditingController();
  
  bool _autoSync = true;
  bool _collectLogs = false;
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isTesting = false;


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
    
    String serverUrl = _serverUrlController.text.trim();
    
    if (serverUrl.isEmpty) {
      _showMessage('Please enter server address', isError: true);
      return;
    }
    
    // Clean up and format the server URL
    serverUrl = _formatServerUrl(serverUrl);
    
    if (!_isValidServerUrl(serverUrl)) {
      _showMessage('Invalid server address format', isError: true);
      return;
    }
    
    setState(() {
      _isSaving = true;
    });
    
    try {
      // Update controller with formatted URL
      _serverUrlController.text = serverUrl;
      
      // Save to settings repository
      await _settings.setServerUrl(serverUrl);
      await _settings.setApiKey(_apiKeyController.text.trim());
      await _settings.setAutoSync(_autoSync);
      await _settings.setCollectLogs(_collectLogs);
      

      
      _showMessage('Settings saved successfully!');
      
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

  String _formatServerUrl(String url) {
    String cleanUrl = url.trim();
    
    // Remove any trailing slashes
    cleanUrl = cleanUrl.replaceAll(RegExp(r'/$'), '');
    
    // Remove protocol if present (we'll always use raw IP:port)
    cleanUrl = cleanUrl.replaceAll(RegExp(r'^https?://'), '');
    
    // If no port specified, add default port 1514
    if (!cleanUrl.contains(':')) {
      cleanUrl = '$cleanUrl:1514';
    }
    
    return cleanUrl;
  }

  bool _isValidServerUrl(String url) {
    try {
      // Split into host and port
      final parts = url.split(':');
      if (parts.length != 2) return false;
      
      final host = parts[0];
      final port = int.tryParse(parts[1]);
      
      if (port == null || port < 1 || port > 65535) {
        return false;
      }
      
      // Check if it's an IP address
      final ipPattern = RegExp(r'^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$');
      if (ipPattern.hasMatch(host)) {
        // Validate IP parts
        final ipParts = host.split('.');
        for (var part in ipParts) {
          final num = int.tryParse(part);
          if (num == null || num < 0 || num > 255) {
            return false;
          }
        }
        return true;
      }
      
      // Could be a hostname - allow it
      return host.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<void> _testConnection() async {
    if (_isTesting) return;
    
    String serverUrl = _serverUrlController.text.trim();
    final apiKey = _apiKeyController.text.trim();
    
    if (serverUrl.isEmpty) {
      _showMessage('Please enter server address first', isError: true);
      return;
    }
    
    // Format the URL
    serverUrl = _formatServerUrl(serverUrl);
    _serverUrlController.text = serverUrl;
    
    setState(() {
      _isTesting = true;
    });
    
    try {
      bool isConnected;
      if (apiKey.isEmpty) {
        isConnected = await ConnectionTester.testUdp(serverUrl);
      } else {
        isConnected = await ConnectionTester.testRestApi(serverUrl, apiKey);
      }

      if (isConnected) {
        _showMessage('✅ Connection successful!');
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
        _serverUrlController.clear();
        _apiKeyController.clear();
        
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
          if (_isSaving)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(Colors.white),
                  ),
                ),
              ),
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
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Server Configuration
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Server Configuration',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _serverUrlController,
                    decoration: InputDecoration(
                      labelText: 'Server Address',
                      hintText: '192.168.1.100',
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.dns),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.info_outline),
                        onPressed: () {
                          showDialog(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('Server Address Format'),
                              content: const Text(
                                'Enter IP address only (e.g., 192.168.1.100)\n'
                                'Port 1514 will be added automatically for UDP mode.\n'
                                'For REST API mode, use port 55000.',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text('OK'),
                                ),
                              ],
                            ),
                          );
                        },
                        tooltip: 'Format: IP address only',
                      ),
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9\.:]')),
                    ],
                    keyboardType: TextInputType.number,
                    onChanged: (value) {
                      // Auto-suggest port 1514
                      if (value.isNotEmpty && 
                          !value.contains(':') && 
                          RegExp(r'^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$').hasMatch(value)) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (_serverUrlController.text == value) {
                            setState(() {
                              _serverUrlController.text = '$value:1514';
                              _serverUrlController.selection = TextSelection.fromPosition(
                                TextPosition(offset: _serverUrlController.text.length)
                              );
                            });
                          }
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Port 1514 will be added automatically for UDP mode',
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
                  const SizedBox(height: 8),
                  const Text(
                    'Empty = UDP mode (port 1514)\nWith API key = REST API mode (port 55000)',
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
          
          const SizedBox(height: 16),
          
          // Test Connection Button
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Test Connection',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Test that logs can reach your server before enabling monitoring.',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _isTesting || _isSaving ? null : _testConnection,
                    icon: _isTesting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation(Colors.white),
                            ),
                          )
                        : const Icon(Icons.wifi_find, size: 20),
                    label: Text(_isTesting ? 'Testing...' : 'Test Connection'),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 48),
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          // App Settings
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Monitoring Settings',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
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
          
          const SizedBox(height: 24),
          
          // Save Button
          ElevatedButton(
            onPressed: _isSaving ? null : _saveSettings,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              backgroundColor: Colors.blue,
            ),
            child: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(Colors.white),
                    ),
                  )
                : const Text(
                    'Save Settings',
                    style: TextStyle(fontSize: 16),
                  ),
          ),
          
          const SizedBox(height: 12),
          
          // Clear Settings Button
          OutlinedButton(
            onPressed: _isSaving ? null : _clearSettings,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              side: const BorderSide(color: Colors.red),
            ),
            child: const Text(
              'Clear All Settings',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }
}