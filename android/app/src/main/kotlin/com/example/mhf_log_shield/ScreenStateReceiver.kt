package com.example.mhf_log_shield

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.text.SimpleDateFormat
import java.util.*
import java.util.concurrent.Executors
import com.example.mhf_log_shield.WazuhSender 

class ScreenStateReceiver : BroadcastReceiver() {
    private val executor = Executors.newSingleThreadExecutor()
    
    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action
        
        val event = when (action) {
            Intent.ACTION_SCREEN_ON -> "SCREEN_ON"
            Intent.ACTION_SCREEN_OFF -> "SCREEN_OFF"
            Intent.ACTION_USER_PRESENT -> "DEVICE_UNLOCKED"
            else -> "UNKNOWN"
        }
        
        Log.d("ScreenStateReceiver", "Screen event: $event")
        
        storeScreenEvent(context, event)
        sendScreenLog(context, event)
        sendToWazuh(context, event) // NEW: Send directly to Wazuh
    }
    
    private fun storeScreenEvent(context: Context, event: String) {
        val prefs = context.getSharedPreferences("monitoring_events", Context.MODE_PRIVATE)
        val timestamp = System.currentTimeMillis()
        val events = prefs.getStringSet("screen_events", mutableSetOf())?.toMutableSet() ?: mutableSetOf()
        
        events.add("$timestamp|$event")
        if (events.size > 50) {
            val sorted = events.sorted().takeLast(50)
            events.clear()
            events.addAll(sorted)
        }
        
        prefs.edit().putStringSet("screen_events", events).apply()
    }
    
    private fun sendScreenLog(context: Context, event: String) {
        val serviceIntent = Intent(context, MonitoringForegroundService::class.java)
        serviceIntent.action = "ACTION_LOG_EVENT"
        serviceIntent.putExtra("event_type", "screen_$event")
        
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
            context.startForegroundService(serviceIntent)
        } else {
            context.startService(serviceIntent)
        }
    }
    
// In ScreenStateReceiver.kt - replace sendToWazuh call with:
private fun sendToWazuh(context: Context, event: String) {
    executor.execute {
        try {
            WazuhSender.sendToWazuh(context, "SCREEN_EVENT", "Screen: $event")
        } catch (e: Exception) {
            Log.e("ScreenStateReceiver", "Error sending to Wazuh: $e")
        }
    }
}
    
    private fun storeForRetry(context: Context, eventType: String, message: String) {
        val prefs = context.getSharedPreferences("pending_wazuh_logs", Context.MODE_PRIVATE)
        val pendingLogs = prefs.getStringSet("logs", mutableSetOf())?.toMutableSet() ?: mutableSetOf()
        
        val timestamp = System.currentTimeMillis()
        pendingLogs.add("$timestamp|$eventType|$message")
        
        if (pendingLogs.size > 100) {
            val sorted = pendingLogs.sorted().takeLast(100).toMutableSet()
            pendingLogs.clear()
            pendingLogs.addAll(sorted)
        }
        
        prefs.edit().putStringSet("logs", pendingLogs).apply()
    }
}