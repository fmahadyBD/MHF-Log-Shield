import 'dart:io';
import 'package:flutter/material.dart';
import 'package:mhf_log_shield/data/repositories/settings_repository.dart';
import 'package:mhf_log_shield/services/background_logger.dart';
import 'package:mhf_log_shield/ui/screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  print('[Main] Initializing MHF Log Shield...');

  try {
    // Initialize settings
    final settings = SettingsRepository();
    await settings.initialize();

    // Initialize background systems
    BackgroundLogger.initialize();

    // Check if we should auto-start monitoring
    final serverUrl = settings.getServerUrl();
    final collectLogs = settings.getCollectLogs();

    if (serverUrl.isNotEmpty && collectLogs) {
      print('[Main] Server configured, ready for manual monitoring start');
    }
  } catch (e) {
    print('[Main] Error during initialization: $e');
  }

  runApp(const MhfLogShieldApp());
}

class MhfLogShieldApp extends StatelessWidget {
  const MhfLogShieldApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MHF Log Shield',
      theme: ThemeData(primarySwatch: Colors.blue, useMaterial3: true),
      home: const HomeScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}