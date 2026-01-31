package com.example.mhf_log_shield

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.SharedPreferences
import android.net.ConnectivityManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.Log
import java.lang.Math.abs
import java.text.SimpleDateFormat
import java.util.*
import java.util.concurrent.Executors
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import com.example.mhf_log_shield.WazuhSender

class MonitoringForegroundService : Service() {
    
    companion object {
        private const val CHANNEL_ID = "MHF_MONITORING_CHANNEL"
        private const val NOTIFICATION_ID = 101
        const val ACTION_START = "ACTION_START_MONITORING"
        const val ACTION_STOP = "ACTION_STOP_MONITORING"
        const val ACTION_LOG_EVENT = "ACTION_LOG_EVENT"
        private const val TAG = "MonitoringService"
    }
    
    private val handler = Handler(Looper.getMainLooper())
    private val executor = Executors.newSingleThreadExecutor()
    private val monitoringRunnable = object : Runnable {
        override fun run() {
            performMonitoringTasks()
            handler.postDelayed(this, getNextInterval())
        }
    }
    
    // Track last sent logs
    private var lastForegroundPackage = ""
    private var lastForegroundLogTime = 0L
    
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d(TAG, "Service received command: ${intent?.action}")
        
        when (intent?.action) {
            ACTION_START -> {
                Log.d(TAG, "Starting monitoring service")
                startMonitoring()
            }
            ACTION_STOP -> {
                Log.d(TAG, "Stopping monitoring service")
                stopMonitoring()
            }
            ACTION_LOG_EVENT -> {
                Log.d(TAG, "Processing log event")
                handleLogEvent(intent)
            }
        }
        return START_STICKY
    }
    
    private fun startMonitoring() {
        createNotificationChannel()
        startForeground(NOTIFICATION_ID, createNotification())
        
        // Start the monitoring loop
        handler.post(monitoringRunnable)
        
        // Store service start event
        storeEvent("service_events", "Monitoring service started")
        
        Log.d(TAG, "Monitoring service started successfully")
    }
    
    private fun stopMonitoring() {
        handler.removeCallbacks(monitoringRunnable)
        
        // Store service stop event
        storeEvent("service_events", "Monitoring service stopped")
        
        stopForeground(true)
        stopSelf()
        
        Log.d(TAG, "Monitoring service stopped")
    }
    
    private fun performMonitoringTasks() {
        Log.d(TAG, "Performing monitoring tasks")
        
        try {
            // 1. Check battery
            checkBattery()
            
            // 2. Check network
            checkNetwork()
            
            // 3. Check foreground app
            checkForegroundApp()
            
            // 4. Send pending logs
            sendPendingLogs()
            
            // Update last check time
            val prefs = getSharedPreferences("monitoring_data", Context.MODE_PRIVATE)
            prefs.edit().putLong("last_monitoring_check", System.currentTimeMillis()).apply()
            
            // Increment events processed counter
            val eventsProcessed = prefs.getInt("events_processed_total", 0)
            prefs.edit().putInt("events_processed_total", eventsProcessed + 1).apply()
            
        } catch (e: Exception) {
            Log.e(TAG, "Error in monitoring tasks: $e")
        }
    }
    
    private fun getNextInterval(): Long {
        val prefs = getSharedPreferences("monitoring_settings", Context.MODE_PRIVATE)
        return prefs.getLong("monitoring_interval", 30000L)
    }
    
    private fun checkBattery() {
        try {
            val batteryIntent = registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
            batteryIntent?.let {
                val level = it.getIntExtra(android.os.BatteryManager.EXTRA_LEVEL, -1)
                val scale = it.getIntExtra(android.os.BatteryManager.EXTRA_SCALE, -1)
                if (level != -1 && scale != -1) {
                    val batteryPercent = (level * 100) / scale
                    val isCharging = it.getIntExtra(android.os.BatteryManager.EXTRA_PLUGGED, -1) > 0
                    
                    // Send to Wazuh if significant change
                    val prefs = getSharedPreferences("monitoring_data", Context.MODE_PRIVATE)
                    val lastBatteryLevel = prefs.getInt("last_reported_battery", -1)
                    
                    if (abs(lastBatteryLevel - batteryPercent) >= 5 || // Changed by 5% or more
                        System.currentTimeMillis() - prefs.getLong("last_battery_report", 0) > 300000) { // OR 5 minutes passed
                        
                        sendBatteryChangeToWazuh(batteryPercent, isCharging)
                        prefs.edit()
                            .putInt("last_reported_battery", batteryPercent)
                            .putLong("last_battery_report", System.currentTimeMillis())
                            .apply()
                    }
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error checking battery: $e")
        }
    }
    
    private fun checkNetwork() {
        try {
            val connectivityManager = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
            val activeNetwork = connectivityManager.activeNetworkInfo
            
            val networkType = when (activeNetwork?.type) {
                ConnectivityManager.TYPE_WIFI -> "WiFi"
                ConnectivityManager.TYPE_MOBILE -> "Mobile Data"
                ConnectivityManager.TYPE_ETHERNET -> "Ethernet"
                ConnectivityManager.TYPE_VPN -> "VPN"
                else -> "Unknown"
            }
            
            val isConnected = activeNetwork?.isConnected ?: false
            
            val prefs = getSharedPreferences("monitoring_data", Context.MODE_PRIVATE)
            val lastNetworkType = prefs.getString("last_network_type", "")
            val lastConnected = prefs.getBoolean("last_network_connected", false)
            
            // Send to Wazuh if network changed
            if (lastNetworkType != networkType || lastConnected != isConnected) {
                sendNetworkChangeToWazuh(networkType, isConnected)
                
                prefs.edit()
                    .putString("last_network_type", networkType)
                    .putBoolean("last_network_connected", isConnected)
                    .apply()
            }
            
        } catch (e: Exception) {
            Log.e(TAG, "Error checking network: $e")
        }
    }
    
    private fun checkForegroundApp() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            try {
                val usageStatsManager = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
                val currentTime = System.currentTimeMillis()
                val stats = usageStatsManager.queryUsageStats(
                    UsageStatsManager.INTERVAL_DAILY,
                    currentTime - 10000, // Last 10 seconds
                    currentTime
                )
                
                if (stats != null && stats.isNotEmpty()) {
                    val sortedStats = stats.sortedByDescending { it.lastTimeUsed }
                    val currentApp = sortedStats.firstOrNull()
                    
                    currentApp?.packageName?.let { packageName ->
                        val appName = getAppName(packageName)
                        
                        // Store in shared preferences
                        val prefs = getSharedPreferences("monitoring_data", Context.MODE_PRIVATE)
                        val lastApp = prefs.getString("last_foreground_package", "")
                        
                        // Log if app changed
                        if (packageName != lastApp) {
                            // Store locally
                            prefs.edit()
                                .putString("last_foreground_app", appName)
                                .putString("last_foreground_package", packageName)
                                .putLong("last_foreground_time", System.currentTimeMillis())
                                .apply()
                            
                            // Send to Wazuh immediately
                            sendToWazuh("foreground_app", "App in foreground: $appName ($packageName)")
                            
                            Log.d(TAG, "Foreground app changed to: $appName ($packageName)")
                        }
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error checking foreground app: $e")
            }
        }
    }
    
    private fun shouldLogForegroundChange(packageName: String): Boolean {
        val now = System.currentTimeMillis()
        
        // Always log if app changed
        if (packageName != lastForegroundPackage) {
            lastForegroundPackage = packageName
            lastForegroundLogTime = now
            return true
        }
        
        // Log same app every 30 seconds max
        return (now - lastForegroundLogTime) > 30000
    }
    
    private fun getAppName(packageName: String): String {
        return try {
            val pm = packageManager
            val appInfo = pm.getApplicationInfo(packageName, 0)
            pm.getApplicationLabel(appInfo).toString()
        } catch (e: Exception) {
            packageName
        }
    }
    
    private fun storeEvent(eventType: String, data: String) {
        val prefs = getSharedPreferences("monitoring_events", Context.MODE_PRIVATE)
        val events = prefs.getStringSet(eventType, mutableSetOf())?.toMutableSet() ?: mutableSetOf()
        
        val timestamp = System.currentTimeMillis()
        events.add("$timestamp|$data")
        
        // Keep only last 100 events of each type
        if (events.size > 100) {
            val sorted = events.sorted().takeLast(100).toMutableSet()
            events.clear()
            events.addAll(sorted)
        }
        
        prefs.edit().putStringSet(eventType, events).apply()
        Log.d(TAG, "Stored event: $eventType - $data")
    }
    
    private fun handleLogEvent(intent: Intent) {
        val eventType = intent.getStringExtra("event_type") ?: return
        
        when {
            eventType.startsWith("app_") -> {
                val appName = intent.getStringExtra("app_name") ?: "Unknown"
                val packageName = intent.getStringExtra("package_name") ?: ""
                val action = eventType.removePrefix("app_")
                storeEvent("app_events", "App $action: $appName ($packageName)")
            }
            eventType.startsWith("screen_") -> {
                val action = eventType.removePrefix("screen_")
                storeEvent("screen_events", "Screen: $action")
            }
            eventType.startsWith("power_") -> {
                val action = eventType.removePrefix("power_")
                val batteryLevel = intent.getIntExtra("battery_level", -1)
                val batteryText = if (batteryLevel != -1) " (${batteryLevel}%)" else ""
                storeEvent("power_events", "Power: $action$batteryText")
            }
        }
    }
    
    private fun sendPendingLogs() {
        try {
            val prefs = getSharedPreferences("pending_wazuh_logs", Context.MODE_PRIVATE)
            val pendingLogs = prefs.getStringSet("logs", mutableSetOf())?.toMutableSet() ?: mutableSetOf()
            
            if (pendingLogs.isEmpty()) {
                Log.d(TAG, "No pending logs to send")
                return
            }
            
            Log.d(TAG, "Found ${pendingLogs.size} pending logs to send")
            
            val serverUrlPrefs = getSharedPreferences("monitoring_settings", Context.MODE_PRIVATE)
            val serverUrl = serverUrlPrefs.getString("server_url", "") ?: ""
            
            if (serverUrl.isEmpty()) {
                Log.d(TAG, "Server URL not configured, cannot send pending logs")
                return
            }
            
            val parts = serverUrl.split(":")
            val host = parts[0]
            val port = if (parts.size > 1) parts[1].toInt() else 1514
            
            val sentLogs = mutableSetOf<String>()
            val remainingLogs = mutableSetOf<String>()
            
            for (logEntry in pendingLogs) {
                try {
                    val entryParts = logEntry.split("|", limit = 3)
                    if (entryParts.size == 3) {
                        val message = entryParts[2]
                        
                        // Create timestamp for current resend attempt
                        val timestamp = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", Locale.US).apply {
                            timeZone = TimeZone.getTimeZone("UTC")
                        }.format(Date())
                        
                        // Create syslog format message
                        val fullMessage = "<13>$timestamp mobile-device MHFLogShield[1000]: RETRY: $message"
                        
                        val socket = DatagramSocket()
                        val address = InetAddress.getByName(host)
                        val data = fullMessage.toByteArray(Charsets.UTF_8)
                        val packet = DatagramPacket(data, data.size, address, port)
                        
                        socket.send(packet)
                        socket.close()
                        
                        sentLogs.add(logEntry)
                        Log.d(TAG, "Successfully resent pending log: ${message.take(50)}...")
                        
                        // Small delay to avoid overwhelming
                        Thread.sleep(100)
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "Error resending pending log '$logEntry': $e")
                    remainingLogs.add(logEntry)
                }
            }
            
            // Remove sent logs, keep failed ones
            pendingLogs.removeAll(sentLogs)
            pendingLogs.addAll(remainingLogs)
            
            // Update stored pending logs
            prefs.edit().putStringSet("logs", pendingLogs).apply()
            
            Log.d(TAG, "Pending logs processed. Sent: ${sentLogs.size}, Failed: ${remainingLogs.size}, Total pending: ${pendingLogs.size}")
            
        } catch (e: Exception) {
            Log.e(TAG, "Error in sendPendingLogs: $e")
        }
    }
    
    private fun sendToWazuh(eventType: String, message: String) {
        executor.execute {
            try {
                val prefs = getSharedPreferences("monitoring_settings", Context.MODE_PRIVATE)
                val serverUrl = prefs.getString("server_url", "") ?: ""
                
                if (serverUrl.isEmpty()) {
                    Log.d(TAG, "Wazuh server not configured, cannot send: $eventType")
                    return@execute
                }
                
                val parts = serverUrl.split(":")
                val host = parts[0]
                val port = if (parts.size > 1) parts[1].toInt() else 1514
                
                val timestamp = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", Locale.US).apply {
                    timeZone = TimeZone.getTimeZone("UTC")
                }.format(Date())
                
                // Create syslog format message
                val fullMessage = "<13>$timestamp mobile-device MHFLogShield[1000]: $eventType: $message"
                
                val socket = DatagramSocket()
                val address = InetAddress.getByName(host)
                val data = fullMessage.toByteArray(Charsets.UTF_8)
                val packet = DatagramPacket(data, data.size, address, port)
                
                socket.send(packet)
                socket.close()
                
                Log.d(TAG, "Sent to Wazuh: $eventType - $message")
                
            } catch (e: Exception) {
                Log.e(TAG, "Error sending to Wazuh: $eventType - $e")
                // Store for retry
                storeForRetry(eventType, message)
            }
        }
    }
    
    private fun storeForRetry(eventType: String, message: String) {
        val prefs = getSharedPreferences("pending_wazuh_logs", Context.MODE_PRIVATE)
        val pendingLogs = prefs.getStringSet("logs", mutableSetOf())?.toMutableSet() ?: mutableSetOf()
        
        val timestamp = System.currentTimeMillis()
        pendingLogs.add("$timestamp|$eventType|$message")
        
        if (pendingLogs.size > 100) {
            val sorted = pendingLogs.sorted().takeLast(100).toMutableSet()
            pendingLogs.clear()
            pendingLogs.addAll(sorted)
        }
        
        prefs.edit().putStringSet("logs", pendingLogs).apply()
        Log.d(TAG, "Stored for retry: $eventType - $message")
    }
    
    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "MHF Monitoring Service",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Monitoring device activity and sending logs"
                setShowBadge(false)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            }
            
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }
    }
    
    private fun createNotification(): Notification {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
                .setContentTitle("MHF Log Shield")
                .setContentText("Monitoring device activity...")
                .setSmallIcon(R.mipmap.ic_launcher)
                .setPriority(Notification.PRIORITY_LOW)
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .build()
        } else {
            Notification.Builder(this)
                .setContentTitle("MHF Log Shield")
                .setContentText("Monitoring device activity...")
                .setSmallIcon(R.mipmap.ic_launcher)
                .setPriority(Notification.PRIORITY_LOW)
                .setOngoing(true)
                .build()
        }
    }
    
    private fun sendNetworkChangeToWazuh(networkType: String, isConnected: Boolean) {
        val message = "Network changed to: $networkType (Connected: $isConnected)"
        WazuhSender.sendToWazuh(this, "NETWORK_EVENT", message)
    }
    
    private fun sendBatteryChangeToWazuh(batteryPercent: Int, isCharging: Boolean) {
        val message = "Battery: $batteryPercent% - ${if (isCharging) "Charging" else "Discharging"}"
        WazuhSender.sendToWazuh(this, "BATTERY_EVENT", message)
    }
    
    override fun onBind(intent: Intent?): IBinder? = null
}