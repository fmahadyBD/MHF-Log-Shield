import 'package:flutter/material.dart';
import 'package:mhf_log_shield/data/repositories/settings_repository.dart';
import 'package:mhf_log_shield/ui/screens/settings_screen.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MHF Log Shield',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final SettingsRepository _settings = SettingsRepository();
  bool _isConfigured = false;
  bool _isCollecting = false;

  @override
  void initState() {
    super.initState();
    _checkConfiguration();
  }

  Future<void> _checkConfiguration() async {
    await _settings.initialize();
    setState(() {
      _isConfigured = _settings.isConfigured();
      _isCollecting = _settings.getCollectLogs();
    });
  }

  void _toggleCollection() {
    setState(() {
      _isCollecting = !_isCollecting;
    });
    _settings.setCollectLogs(_isCollecting);
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_isCollecting ? 'Log collection started' : 'Log collection stopped'),
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
                MaterialPageRoute(
                  builder: (context) => const SettingsScreen(),
                ),
              );
              await _checkConfiguration();
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Status Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    const Icon(
                      Icons.shield,
                      size: 50,
                      color: Colors.blue,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _isConfigured ? 'Ready' : 'Not Configured',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: _isConfigured ? Colors.green : Colors.orange,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      _isConfigured 
                        ? 'Wazuh server configured'
                        : 'Configure Wazuh server in settings',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            
            // Collection Status
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    Icon(
                      _isCollecting ? Icons.play_arrow : Icons.stop,
                      color: _isCollecting ? Colors.green : Colors.red,
                      size: 30,
                    ),
                    const SizedBox(width: 15),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _isCollecting ? 'Collecting Logs' : 'Stopped',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            _isCollecting 
                              ? 'Logs are being collected'
                              : 'Log collection is stopped',
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            
            // Control Buttons
            if (_isConfigured)
              ElevatedButton(
                onPressed: _toggleCollection,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: _isCollecting ? Colors.red : Colors.green,
                ),
                child: Row(
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
                    MaterialPageRoute(
                      builder: (context) => const SettingsScreen(),
                    ),
                  ).then((_) => _checkConfiguration());
                },
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.settings),
                    SizedBox(width: 10),
                    Text(
                      'Configure Now',
                      style: TextStyle(fontSize: 16),
                    ),
                  ],
                ),
              ),
            
            const SizedBox(height: 10),
            
            ElevatedButton.icon(
              onPressed: () {
                // Manual sync - we'll implement later
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Manual sync not implemented yet')),
                );
              },
              icon: const Icon(Icons.sync),
              label: const Text('Manual Sync'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
            
            const Spacer(),
            
            // Info Section
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'App Status:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text('• Database: Skipped for now'),
                    Text('• Settings: ${_isConfigured ? 'Configured' : 'Not configured'}'),
                    Text('• Collection: ${_isCollecting ? 'Active' : 'Inactive'}'),
                    const SizedBox(height: 8),
                    const Text(
                      'Next Steps:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const Text('1. Configure Wazuh server'),
                    const Text('2. Start log collection'),
                    const Text('3. Database will be added later'),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}