import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';

class AdvancedMonitor {
  static const MethodChannel _channel = MethodChannel('advanced_monitor_channel');
  static Timer? _periodicTimer;
  
  // Start comprehensive monitoring
  static Future<void> startAdvancedMonitoring() async {
    try {
      // Start foreground service
      await _channel.invokeMethod('startMonitoringService');
      
      // Start periodic checks in Dart (for data that doesn't need native)
      _startDartMonitoring();
      
      print('[AdvancedMonitor] Advanced monitoring started');
    } catch (e) {
      print('[AdvancedMonitor] Error starting monitoring: $e');
    }
  }
  
  static void _startDartMonitoring() {
    // Stop any existing timer
    _periodicTimer?.cancel();
    
    // Start timers with different intervals
    _periodicTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      _performMonitoringTasks();
    });
  }
  
  static Future<void> _performMonitoringTasks() async {
    try {
      // Get monitoring data from native
      final data = await _channel.invokeMethod('getMonitoringData');
      print('[AdvancedMonitor] Monitoring data: $data');
      
      // Process and send logs
      await _processMonitoringData(data);
      
    } catch (e) {
      print('[AdvancedMonitor] Error in monitoring tasks: $e');
    }
  }
  
  static Future<void> _processMonitoringData(dynamic data) async {
    // Process data and send logs using your LogSender
    // This integrates with your existing logging system
  }
  
  static Future<void> stopAdvancedMonitoring() async {
    try {
      _periodicTimer?.cancel();
      _periodicTimer = null;
      
      await _channel.invokeMethod('stopMonitoringService');
      
      print('[AdvancedMonitor] Advanced monitoring stopped');
    } catch (e) {
      print('[AdvancedMonitor] Error stopping monitoring: $e');
    }
  }
  
  // Check if monitoring service is running
  static Future<bool> isMonitoringRunning() async {
    try {
      final isRunning = await _channel.invokeMethod('isMonitoringRunning');
      return isRunning == true;
    } catch (e) {
      print('[AdvancedMonitor] Error checking service status: $e');
      return false;
    }
  }
  
  // Get pending events count
  static Future<Map<String, int>> getPendingEventsCount() async {
    try {
      final counts = await _channel.invokeMethod('getPendingEventsCount');
      return Map<String, int>.from(counts);
    } catch (e) {
      print('[AdvancedMonitor] Error getting event counts: $e');
      return {};
    }
  }
  
  // Set monitoring interval
  static Future<void> setMonitoringInterval(int seconds) async {
    try {
      await _channel.invokeMethod('setMonitoringInterval', {'seconds': seconds});
      print('[AdvancedMonitor] Monitoring interval set to $seconds seconds');
    } catch (e) {
      print('[AdvancedMonitor] Error setting interval: $e');
    }
  }
  
  // Get current monitoring stats
  static Future<Map<String, dynamic>> getMonitoringStats() async {
    try {
      final stats = await _channel.invokeMethod('getMonitoringStats');
      return Map<String, dynamic>.from(stats);
    } catch (e) {
      print('[AdvancedMonitor] Error getting stats: $e');
      return {};
    }
  }
}