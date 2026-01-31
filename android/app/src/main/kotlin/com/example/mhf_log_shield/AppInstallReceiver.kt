package com.example.mhf_log_shield

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log
import java.util.concurrent.Executors

class AppInstallReceiver : BroadcastReceiver() {
    private val executor = Executors.newSingleThreadExecutor()
    
    override fun onReceive(context: Context, intent: Intent) {
        Log.d("AppInstallReceiver", "=== APP EVENT DETECTED ===")
        Log.d("AppInstallReceiver", "Action: ${intent.action}")
        
        val action = intent.action
        val packageName = intent.data?.schemeSpecificPart
        
        if (packageName != null) {
            val packageManager = context.packageManager
            val appName = try {
                val appInfo = packageManager.getApplicationInfo(packageName, 0)
                packageManager.getApplicationLabel(appInfo).toString()
            } catch (e: PackageManager.NameNotFoundException) {
                "Unknown"
            }
            
            val event = when (action) {
                Intent.ACTION_PACKAGE_ADDED -> "INSTALLED"
                Intent.ACTION_PACKAGE_REMOVED -> "UNINSTALLED"
                Intent.ACTION_PACKAGE_REPLACED -> "UPDATED"
                else -> "UNKNOWN"
            }
            
            Log.d("AppInstallReceiver", "App: $appName ($packageName)")
            Log.d("AppInstallReceiver", "Event: $event")
            
            // 1. Store event locally
            storeAppEvent(context, event, appName, packageName)
            
            // 2. Send via WazuhSender (ONLY THIS ONE)
            sendToWazuh(context, event, appName, packageName)
            
            // 3. Start service if needed
            startMonitoringService(context)
            
        } else {
            Log.e("AppInstallReceiver", "Package name is null!")
        }
    }
    
    private fun storeAppEvent(context: Context, event: String, appName: String, packageName: String) {
        try {
            val prefs = context.getSharedPreferences("monitoring_events", Context.MODE_PRIVATE)
            val events = prefs.getStringSet("app_events", mutableSetOf())?.toMutableSet() ?: mutableSetOf()
            
            val timestamp = System.currentTimeMillis()
            val eventData = "$timestamp|$event|$appName|$packageName"
            events.add(eventData)
            
            // Keep only last 100 events
            if (events.size > 100) {
                val sorted = events.sorted().takeLast(100)
                events.clear()
                events.addAll(sorted)
            }
            
            prefs.edit().putStringSet("app_events", events).apply()
            
            Log.d("AppInstallReceiver", "✓ Event stored locally")
        } catch (e: Exception) {
            Log.e("AppInstallReceiver", "Error storing event: $e")
        }
    }
    
    private fun sendToWazuh(context: Context, event: String, appName: String, packageName: String) {
        executor.execute {
            try {
                val message = "Application $event: $appName (Package: $packageName)"
                Log.d("AppInstallReceiver", "Sending to Wazuh: $message")
                
                // CALL THE SINGLE WazuhSender OBJECT
                WazuhSender.sendToWazuh(context, "APP_EVENT", message)
                
            } catch (e: Exception) {
                Log.e("AppInstallReceiver", "Error sending to Wazuh: $e")
            }
        }
    }
    
    private fun startMonitoringService(context: Context) {
        try {
            val serviceIntent = Intent(context, MonitoringForegroundService::class.java)
            serviceIntent.action = MonitoringForegroundService.ACTION_START
            
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(serviceIntent)
            } else {
                context.startService(serviceIntent)
            }
            
            Log.d("AppInstallReceiver", "✓ Service started")
        } catch (e: Exception) {
            Log.e("AppInstallReceiver", "Error starting service: $e")
        }
    }
}