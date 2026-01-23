import 'dart:io';
import 'dart:convert';

class LogSender {
  Future<bool> sendTestLog(String serverUrl, String apiKey) async {
    if (serverUrl.isEmpty) {
      print('[LogSender] ERROR: Server not configured');
      return false;
    }

    print('[LogSender] Sending test log to $serverUrl');
    
    if (apiKey.isEmpty) {
      return _sendTestLogViaUdp(serverUrl);
    } else {
      return _sendTestLogViaApi(serverUrl, apiKey);
    }
  }

  Future<bool> _sendTestLogViaUdp(String serverUrl) async {
    try {
      // Parse server URL
      final parts = serverUrl.split(':');
      final host = parts[0];
      final port = parts.length > 1 ? int.tryParse(parts[1]) ?? 1514 : 1514;
      
      // Create UDP socket
      final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      
      // Try different formats until one works
      final logFormats = [
        _createSyslogFormat(),
        _createSimpleTextFormat(),
        _createKeyValueFormat(),
        _createJsonFormat(), // Last resort
      ];
      
      bool success = false;
      
      for (final logMessage in logFormats) {
        final data = utf8.encode(logMessage);
        
        print('[LogSender] Trying format: ${_getFormatName(logMessage)}');
        print('[LogSender] Message: ${logMessage.length > 50 ? '${logMessage.substring(0, 50)}...' : logMessage}');
        
        final sent = socket.send(data, InternetAddress(host), port);
        
        if (sent > 0) {
          print('[LogSender] SUCCESS: Sent ${logMessage.length} chars via UDP');
          print('[LogSender] Format used: ${_getFormatName(logMessage)}');
          success = true;
          
          // Give time for packet to arrive
          await Future.delayed(const Duration(milliseconds: 100));
          break;
        }
      }
      
      socket.close();
      return success;
      
    } catch (e) {
      print('[LogSender] UDP ERROR: $e');
      return false;
    }
  }

  Future<bool> _sendTestLogViaApi(String serverUrl, String apiKey) async {
    print('[LogSender] REST API log sending not implemented yet');
    print('[LogSender] Using UDP fallback');
    return _sendTestLogViaUdp(serverUrl);
  }

  // FORMAT 1: Syslog format (RFC3164) - Best for Wazuh
  String _createSyslogFormat() {
    final now = DateTime.now().toUtc();
    final timestamp = '${now.year}-${_twoDigits(now.month)}-${_twoDigits(now.day)}T${_twoDigits(now.hour)}:${_twoDigits(now.minute)}:${_twoDigits(now.second)}Z';
    
    // Priority 13 = user-level, info message
    // Format: <PRI>TIMESTAMP HOSTNAME APP[PID]: MESSAGE
    return '<13>$timestamp mobile-device MHFLogShield[1000]: Test log from MHF Log Shield mobile application';
  }

  // FORMAT 2: Simple text format
  String _createSimpleTextFormat() {
    final now = DateTime.now().toUtc();
    final timestamp = '${_twoDigits(now.hour)}:${_twoDigits(now.minute)}:${_twoDigits(now.second)}';
    
    // Simple timestamp + message
    return '[$timestamp UTC] MHFLogShield - Test message from mobile app';
  }

  // FORMAT 3: Key=Value format (Wazuh can parse this)
  String _createKeyValueFormat() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    
    // Key=value pairs separated by spaces
    return 'timestamp=$timestamp app=MHF_Log_Shield level=INFO message="Test log from mobile application" device=mobile';
  }

  // FORMAT 4: JSON format (if Wazuh is configured for JSON)
  String _createJsonFormat() {
    final timestamp = DateTime.now().toIso8601String();
    
    final logData = {
      'timestamp': timestamp,
      'hostname': 'mobile-device',
      'app_name': 'MHF_Log_Shield',
      'log_level': 'INFO',
      'message': 'Test log from MHF Log Shield mobile application',
      'event_type': 'test',
      'test_id': '${DateTime.now().millisecondsSinceEpoch}',
      'device_info': {
        'app_version': '1.0.0',
        'platform': 'Flutter',
      }
    };
    
    return json.encode(logData);
  }

  // Helper to identify format
  String _getFormatName(String logMessage) {
    if (logMessage.startsWith('<')) return 'Syslog';
    if (logMessage.startsWith('[')) return 'Simple Text';
    if (logMessage.contains('=')) return 'Key-Value';
    if (logMessage.startsWith('{')) return 'JSON';
    return 'Unknown';
  }

  // Send a custom log with specified level
  Future<bool> sendCustomLog(String serverUrl, String apiKey, String message, String level) async {
    if (serverUrl.isEmpty) {
      print('[LogSender] ERROR: Server not configured');
      return false;
    }

    try {
      final parts = serverUrl.split(':');
      final host = parts[0];
      final port = parts.length > 1 ? int.tryParse(parts[1]) ?? 1514 : 1514;
      
      final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      
      // Use syslog format for custom logs
      final logMessage = _createCustomSyslogLog(message, level);
      final data = utf8.encode(logMessage);
      
      print('[LogSender] Sending custom log: ${logMessage.length} chars');
      print('[LogSender] Format: Syslog with level $level');
      
      final sent = socket.send(data, InternetAddress(host), port);
      socket.close();
      
      if (sent > 0) {
        print('[LogSender] Custom log sent successfully');
        return true;
      } else {
        print('[LogSender] Failed to send custom log');
        return false;
      }
    } catch (e) {
      print('[LogSender] ERROR: $e');
      return false;
    }
  }

  // Create custom syslog message with proper priority
  String _createCustomSyslogLog(String message, String level) {
    final now = DateTime.now().toUtc();
    final timestamp = '${now.year}-${_twoDigits(now.month)}-${_twoDigits(now.day)}T${_twoDigits(now.hour)}:${_twoDigits(now.minute)}:${_twoDigits(now.second)}Z';
    
    // Map level to syslog priority
    final priority = _getSyslogPriority(level);
    
    // Format: <PRI>TIMESTAMP HOSTNAME APP[PID]: LEVEL: MESSAGE
    return '<$priority>$timestamp mobile-device MHFLogShield[1000]: $level: $message';
  }

  // Get syslog priority number based on level
  int _getSyslogPriority(String level) {
    switch (level.toUpperCase()) {
      case 'DEBUG': return 15;     // Debug-level messages
      case 'INFO': return 14;      // Informational messages
      case 'NOTICE': return 13;    // Normal but significant
      case 'WARNING': return 12;   // Warning conditions
      case 'ERROR': return 11;     // Error conditions
      case 'CRITICAL': return 10;  // Critical conditions
      case 'ALERT': return 9;      // Action must be taken immediately
      case 'EMERGENCY': return 8;  // System is unusable
      default: return 14;          // Default to INFO
    }
  }

  // Send multiple test logs with different formats
  Future<List<bool>> sendMultipleTestLogs(String serverUrl, String apiKey) async {
    if (serverUrl.isEmpty) {
      print('[LogSender] ERROR: Server not configured');
      return [false, false, false];
    }

    final results = <bool>[];
    
    // Send 3 different format logs
    results.add(await _sendSpecificFormat(serverUrl, _createSyslogFormat(), 'Syslog'));
    await Future.delayed(const Duration(milliseconds: 500));
    
    results.add(await _sendSpecificFormat(serverUrl, _createSimpleTextFormat(), 'Simple Text'));
    await Future.delayed(const Duration(milliseconds: 500));
    
    results.add(await _sendSpecificFormat(serverUrl, _createKeyValueFormat(), 'Key-Value'));
    
    return results;
  }

  Future<bool> _sendSpecificFormat(String serverUrl, String logMessage, String formatName) async {
    try {
      final parts = serverUrl.split(':');
      final host = parts[0];
      final port = parts.length > 1 ? int.tryParse(parts[1]) ?? 1514 : 1514;
      
      final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      final data = utf8.encode(logMessage);
      
      print('[LogSender] Sending $formatName format: ${logMessage.length} chars');
      
      final sent = socket.send(data, InternetAddress(host), port);
      socket.close();
      
      return sent > 0;
    } catch (e) {
      print('[LogSender] $formatName ERROR: $e');
      return false;
    }
  }

  // Utility method for two-digit formatting
  String _twoDigits(int n) => n.toString().padLeft(2, '0');
}