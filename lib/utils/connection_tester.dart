import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;

class ConnectionTester {
  static Future<bool> testUdp(String serverUrl) async {
    try {
      // Parse server URL
      final parts = serverUrl.split(':');
      final host = parts[0];
      final port = parts.length > 1 ? int.tryParse(parts[1]) ?? 1514 : 1514;
      
      print('[UDP Test] Connecting to $host:$port');
      
      // Validate IP address
      if (!_isValidIp(host)) {
        print('[UDP Test] ERROR: Invalid IP address: $host');
        return false;
      }
      
      // Send UDP packet
      final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      
      // Create test message
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final testMessage = 'MHF_LOG_SHIELD_TEST_$timestamp';
      final data = utf8.encode(testMessage);
      
      print('[UDP Test] Sending: "$testMessage"');
      
      final sent = socket.send(data, InternetAddress(host), port);
      socket.close();
      
      if (sent > 0) {
        print('[UDP Test] SUCCESS: Packet sent ($sent bytes)');
        return true;
      } else {
        print('[UDP Test] FAILED: Could not send packet');
        return false;
      }
    } catch (e) {
      print('[UDP Test] ERROR: $e');
      return false;
    }
  }
  
  static Future<bool> testRestApi(String serverUrl, String apiKey) async {
    try {
      String url = serverUrl.trim();
      
      if (url.isEmpty) {
        print('[REST API Test] ERROR: Empty server URL');
        return false;
      }
      
      // Add protocol if missing
      if (!url.startsWith('http')) {
        url = 'https://$url';
      }
      
      // Add default port if missing
      if (!url.contains(':55000')) {
        url = '$url:55000';
      }
      
      // Clean URL
      url = url.replaceAll(RegExp(r'/$'), '');
      
      print('[REST API Test] Connecting to $url');
      
      final response = await http.get(
        Uri.parse('$url/'),
        headers: {'Authorization': 'Bearer $apiKey'},
      ).timeout(const Duration(seconds: 5));
      
      print('[REST API Test] Response status: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        print('[REST API Test] SUCCESS: Connection established');
        return true;
      } else {
        print('[REST API Test] FAILED: HTTP ${response.statusCode}');
        return false;
      }
    } catch (e) {
      print('[REST API Test] ERROR: $e');
      return false;
    }
  }
  
  static bool _isValidIp(String ip) {
    try {
      final regex = RegExp(r'^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$');
      if (!regex.hasMatch(ip)) return false;
      
      final parts = ip.split('.');
      for (var part in parts) {
        final num = int.tryParse(part);
        if (num == null || num < 0 || num > 255) return false;
      }
      return true;
    } catch (_) {
      return false;
    }
  }
}