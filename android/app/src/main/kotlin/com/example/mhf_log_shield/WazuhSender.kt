package com.example.mhf_log_shield

import android.content.Context
import android.util.Log
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.text.SimpleDateFormat
import java.util.*
import java.util.concurrent.Executors

object WazuhSender {
    private val executor = Executors.newSingleThreadExecutor()
    
    fun sendToWazuh(context: Context, eventType: String, message: String) {
        executor.execute {
            try {
                Log.d("WazuhSender", "=== SENDING TO WAZUH ===")
                Log.d("WazuhSender", "Event: $eventType")
                Log.d("WazuhSender", "Message: $message")
                
                // Get server URL - CHECK MULTIPLE PLACES
                var serverUrl = ""
                
                // 1. First check app_monitor (where Flutter saves it)
                val appPrefs = context.getSharedPreferences("app_monitor", Context.MODE_PRIVATE)
                serverUrl = appPrefs.getString("wazuh_server_url", "") ?: ""
                
                // 2. If empty, check monitoring_settings
                if (serverUrl.isEmpty()) {
                    val monitorPrefs = context.getSharedPreferences("monitoring_settings", Context.MODE_PRIVATE)
                    serverUrl = monitorPrefs.getString("server_url", "") ?: ""
                }
                
                // 3. If still empty, check Flutter's shared prefs
                if (serverUrl.isEmpty()) {
                    val flutterPrefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                    serverUrl = flutterPrefs.getString("flutter.server_url", "") ?: ""
                }
                
                Log.d("WazuhSender", "Found server URL: '$serverUrl'")
                
                if (serverUrl.isEmpty()) {
                    Log.e("WazuhSender", "❌ ERROR: Server URL is empty! Cannot send logs.")
                    storeForRetry(context, eventType, message)
                    
                    // Save error for debugging
                    saveDebugInfo(context, "NO_SERVER_URL", "Event: $eventType, Message: $message")
                    return@execute
                }
                
                // Clean up URL (remove http:// if present)
                serverUrl = serverUrl.replace("http://", "").replace("https://", "").trim()
                
                // Add default port if not specified
                if (!serverUrl.contains(":")) {
                    serverUrl = "$serverUrl:1514"
                }
                
                Log.d("WazuhSender", "Using server: $serverUrl")
                
                val parts = serverUrl.split(":")
                val host = parts[0]
                val port = if (parts.size > 1) parts[1].toInt() else 1514
                
                // Create timestamp in UTC
                val timestamp = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", Locale.US).apply {
                    timeZone = TimeZone.getTimeZone("UTC")
                }.format(Date())
                
                // Create syslog format message
                val fullMessage = "<13>$timestamp mobile-device MHFLogShield[1000]: [$eventType] $message"
                
                Log.d("WazuhSender", "Sending UDP to $host:$port")
                Log.d("WazuhSender", "Full message: $fullMessage")
                
                // Send UDP packet
                val socket = DatagramSocket()
                socket.soTimeout = 5000 // 5 second timeout
                
                val address = InetAddress.getByName(host)
                val data = fullMessage.toByteArray(Charsets.UTF_8)
                val packet = DatagramPacket(data, data.size, address, port)
                
                socket.send(packet)
                socket.close()
                
                Log.d("WazuhSender", "✅ SUCCESS: Sent to Wazuh!")
                
                // Record success
                saveDebugInfo(context, "SENT_SUCCESS", "Event: $eventType, Server: $serverUrl")
                
            } catch (e: Exception) {
                Log.e("WazuhSender", "❌ ERROR sending to Wazuh: ${e.message}")
                e.printStackTrace()
                
                // Store for retry
                storeForRetry(context, eventType, message)
                
                // Save error details
                saveDebugInfo(context, "SEND_ERROR", "${e.message} - Event: $eventType")
            }
        }
    }
    
    private fun saveDebugInfo(context: Context, key: String, value: String) {
        try {
            val prefs = context.getSharedPreferences("wazuh_debug", Context.MODE_PRIVATE)
            val timestamp = SimpleDateFormat("HH:mm:ss", Locale.US).format(Date())
            prefs.edit().putString("last_$key", "$timestamp - $value").apply()
            
            // Also keep history
            val history = prefs.getStringSet("history", mutableSetOf())?.toMutableSet() ?: mutableSetOf()
            history.add("${System.currentTimeMillis()}|$key|$value")
            
            // Keep only last 50 entries
            if (history.size > 50) {
                val sorted = history.sorted().takeLast(50).toMutableSet()
                history.clear()
                history.addAll(sorted)
            }
            
            prefs.edit().putStringSet("history", history).apply()
        } catch (e: Exception) {
            Log.e("WazuhSender", "Error saving debug info: $e")
        }
    }
    
    private fun storeForRetry(context: Context, eventType: String, message: String) {
        try {
            val prefs = context.getSharedPreferences("pending_wazuh_logs", Context.MODE_PRIVATE)
            val pendingLogs = prefs.getStringSet("logs", mutableSetOf())?.toMutableSet() ?: mutableSetOf()
            
            val timestamp = System.currentTimeMillis()
            val logEntry = "$timestamp|$eventType|${message.replace("|", "-")}"
            pendingLogs.add(logEntry)
            
            // Keep only last 100 events
            if (pendingLogs.size > 100) {
                val sorted = pendingLogs.sorted().takeLast(100).toMutableSet()
                pendingLogs.clear()
                pendingLogs.addAll(sorted)
            }
            
            prefs.edit().putStringSet("logs", pendingLogs).apply()
            Log.d("WazuhSender", "Stored for retry. Total pending: ${pendingLogs.size}")
        } catch (e: Exception) {
            Log.e("WazuhSender", "Error storing for retry: $e")
        }
    }
}