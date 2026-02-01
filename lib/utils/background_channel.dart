import 'dart:async';
import 'package:flutter/services.dart';
import 'package:mhf_log_shield/services/background_logger.dart';

class IOSBackgroundChannel {
  static const MethodChannel _channel = 
      MethodChannel('com.mhf.logshield/background');
  
  static Future<void> initialize() async {
    try {
      _channel.setMethodCallHandler(_handleMethodCall);
      print('[IOSBackgroundChannel] iOS Background Channel initialized');
      
      // Request initial background time if needed
      await requestBackgroundTime();
    } catch (e) {
      print('[IOSBackgroundChannel] Error initializing iOS background channel: $e');
    }
  }
  
  static Future<dynamic> _handleMethodCall(MethodCall call) async {
    print('[IOSBackgroundChannel] Method call: ${call.method}');
    
    switch (call.method) {
      case 'processBackgroundTask':
        print('[IOSBackgroundChannel] iOS requested background task execution');
        try {
          // Process pending logs
          await BackgroundLogger.sendPendingLogs();
          print('[IOSBackgroundChannel] Background task completed successfully');
          return true;
        } catch (e) {
          print('[IOSBackgroundChannel] Background task error: $e');
          return false;
        }
        
      case 'getBackgroundStatus':
        final pendingLogs = await BackgroundLogger.getPendingLogsCount();
        final appEvents = await BackgroundLogger.getAppEventsCount();
        return {
          'pending_logs': pendingLogs,
          'app_events': appEvents,
          'timestamp': DateTime.now().toIso8601String(),
        };
        
      default:
        print('[IOSBackgroundChannel] Unknown method: ${call.method}');
        throw PlatformException(
          code: 'not_implemented',
          message: 'Method ${call.method} not implemented',
          details: null,
        );
    }
  }
  
  // Request background processing time from iOS
  static Future<bool> requestBackgroundTime() async {
    try {
      print('[IOSBackgroundChannel] Requesting background time from iOS...');
      
      final result = await _channel.invokeMethod('requestBackgroundTime');
      final success = result == true;
      
      print('[IOSBackgroundChannel] Background time request result: $success');
      return success;
    } catch (e) {
      print('[IOSBackgroundChannel] Error requesting background time: $e');
      return false;
    }
  }
  
  // Schedule a background task
  static Future<bool> scheduleBackgroundTask({int delayMinutes = 15}) async {
    try {
      print('[IOSBackgroundChannel] Scheduling background task in $delayMinutes minutes...');
      
      final result = await _channel.invokeMethod('scheduleBackgroundTask', {
        'delayMinutes': delayMinutes,
      });
      
      final success = result == true;
      print('[IOSBackgroundChannel] Background task scheduled: $success');
      return success;
    } catch (e) {
      print('[IOSBackgroundChannel] Error scheduling background task: $e');
      return false;
    }
  }
  
  // Cancel all background tasks
  static Future<bool> cancelAllBackgroundTasks() async {
    try {
      print('[IOSBackgroundChannel] Cancelling all background tasks...');
      
      final result = await _channel.invokeMethod('cancelAllBackgroundTasks');
      final success = result == true;
      
      print('[IOSBackgroundChannel] Background tasks cancelled: $success');
      return success;
    } catch (e) {
      print('[IOSBackgroundChannel] Error cancelling background tasks: $e');
      return false;
    }
  }
  
  // Check if background processing is available
  static Future<bool> isBackgroundProcessingAvailable() async {
    try {
      final result = await _channel.invokeMethod('isBackgroundProcessingAvailable');
      return result == true;
    } catch (e) {
      print('[IOSBackgroundChannel] Error checking background availability: $e');
      return false;
    }
  }
  
  // Get background task statistics
  static Future<Map<String, dynamic>> getBackgroundStats() async {
    try {
      final result = await _channel.invokeMethod('getBackgroundStats');
      if (result is Map) {
        return Map<String, dynamic>.from(result);
      }
      return {};
    } catch (e) {
      print('[IOSBackgroundChannel] Error getting background stats: $e');
      return {};
    }
  }
}