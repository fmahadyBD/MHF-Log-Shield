import 'package:flutter/material.dart';
import 'package:mhf_log_shield/core/platform/platform_service_factory.dart';
import 'package:mhf_log_shield/services/background_logger.dart';
import 'package:mhf_log_shield/ui/screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize platform services
  await PlatformServiceFactory.initializePlatformServices();
  
  // Initialize background logger
  BackgroundLogger.initialize();
  
  runApp(const MhfLogShieldApp());
}

class MhfLogShieldApp extends StatelessWidget {
  const MhfLogShieldApp({super.key});

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