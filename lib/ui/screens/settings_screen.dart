import 'package:flutter/material.dart';
import 'package:mhf_log_shield/data/repositories/settings_repository.dart';

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
    await _settings.setServerUrl(_serverUrlController.text.trim());
    await _settings.setApiKey(_apiKeyController.text.trim());
    await _settings.setAutoSync(_autoSync);
    await _settings.setCollectLogs(_collectLogs);
    
    // Show success message
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Settings saved successfully!'),
          backgroundColor: Colors.green,
        ),
      );
    }
    
    Navigator.pop(context);
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
            icon: const Icon(Icons.save),
            onPressed: _saveSettings,
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
                      labelText: 'Server Address',
                      hintText: '192.168.1.100 or 192.168.1.100:1514',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.dns),
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
                    'With API key = REST API mode (port 55000)',
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
              onPressed: _saveSettings,
              icon: const Icon(Icons.save),
              label: const Text(
                'Save Settings',
                style: TextStyle(fontSize: 16),
              ),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: Colors.blue,
              ),
            ),
          ),
        ],
      ),
    );
  }
}