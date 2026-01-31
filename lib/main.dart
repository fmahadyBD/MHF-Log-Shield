import 'package:flutter/material.dart';
import 'package:mhf_log_shield/ui/screens/home_screen.dart';
import 'package:mhf_log_shield/services/background_logger.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize background tasks
  BackgroundLogger.initialize();
  
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