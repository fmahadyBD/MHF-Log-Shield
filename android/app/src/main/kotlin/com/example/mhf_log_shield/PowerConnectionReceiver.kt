package com.example.mhf_log_shield

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.BatteryManager
import android.util.Log
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.text.SimpleDateFormat
import java.util.*
import java.util.concurrent.Executors
import com.example.mhf_log_shield.WazuhSender

class PowerConnectionReceiver : BroadcastReceiver() {
    private val executor = Executors.newSingleThreadExecutor()
    
    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action
        
        val event = when (action) {
            Intent.ACTION_POWER_CONNECTED -> "POWER_CONNECTED"
            Intent.ACTION_POWER_DISCONNECTED -> "POWER_DISCONNECTED"
            Intent.ACTION_BATTERY_LOW -> "BATTERY_LOW"
            Intent.ACTION_BATTERY_OKAY -> "BATTERY_OKAY"
            else -> "UNKNOWN"
        }
        
        // Get battery level if available
        var batteryLevel = -1
        if (action == Intent.ACTION_BATTERY_CHANGED || 
            action == Intent.ACTION_POWER_CONNECTED || 
            action == Intent.ACTION_POWER_DISCONNECTED) {
            
            val level = intent.getIntExtra(BatteryManager.EXTRA_LEVEL, -1)
            val scale = intent.getIntExtra(BatteryManager.EXTRA_SCALE, -1)
            if (level != -1 && scale != -1) {
                batteryLevel = (level * 100) / scale
            }
        }
        
        Log.d("PowerConnectionReceiver", "Power event: $event, Battery: $batteryLevel%")
        
        storePowerEvent(context, event, batteryLevel)
        sendPowerLog(context, event, batteryLevel)
        sendToWazuh(context, event, batteryLevel) // NEW: Send directly to Wazuh
    }
    
    private fun storePowerEvent(context: Context, event: String, batteryLevel: Int) {
        val prefs = context.getSharedPreferences("monitoring_events", Context.MODE_PRIVATE)
        val timestamp = System.currentTimeMillis()
        val events = prefs.getStringSet("power_events", mutableSetOf())?.toMutableSet() ?: mutableSetOf()
        
        events.add("$timestamp|$event|$batteryLevel")
        if (events.size > 50) {
            val sorted = events.sorted().takeLast(50)
            events.clear()
            events.addAll(sorted)
        }
        
        prefs.edit().putStringSet("power_events", events).apply()
    }
    
    private fun sendPowerLog(context: Context, event: String, batteryLevel: Int) {
        val serviceIntent = Intent(context, MonitoringForegroundService::class.java)
        serviceIntent.action = "ACTION_LOG_EVENT"
        serviceIntent.putExtra("event_type", "power_$event")
        serviceIntent.putExtra("battery_level", batteryLevel)
        
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
            context.startForegroundService(serviceIntent)
        } else {
            context.startService(serviceIntent)
        }
    }
    
 // In PowerConnectionReceiver.kt - replace sendToWazuh call with:
private fun sendToWazuh(context: Context, event: String, batteryLevel: Int) {
    executor.execute {
        try {
            val batteryText = if (batteryLevel != -1) " (Battery: $batteryLevel%)" else ""
            WazuhSender.sendToWazuh(context, "POWER_EVENT", "Power: $event$batteryText")
        } catch (e: Exception) {
            Log.e("PowerConnectionReceiver", "Error sending to Wazuh: $e")
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