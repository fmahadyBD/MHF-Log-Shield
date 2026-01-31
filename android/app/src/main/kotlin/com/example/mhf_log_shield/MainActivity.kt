package com.example.mhf_log_shield

import android.app.AlertDialog
import android.app.AppOpsManager
import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.content.pm.PackageManager
import android.Manifest
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.os.BatteryManager
import android.net.ConnectivityManager
import android.net.NetworkInfo
import android.content.IntentFilter

class MainActivity : FlutterActivity() {
    private val CHANNEL = "app_monitor_channel"
    private val ADVANCED_CHANNEL = "advanced_monitor_channel"
    private val PERMISSION_REQUEST_CODE = 1001
    private val USAGE_STATS_PERMISSION_REQUEST_CODE = 1002
    
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        requestNeededPermissions()
        Log.d("MainActivity", "=== MainActivity Created ===")
    }
    
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        Log.d("MainActivity", "=== Configuring Flutter Engine ===")
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            Log.d("MainActivity", "Method called: ${call.method}")
            
            when (call.method) {
                "getInstallSource" -> {
                    val packageName = call.argument<String>("packageName")
                    if (packageName != null) {
                        val installSource = getInstallSource(packageName)
                        result.success(installSource)
                    } else {
                        result.error("ERROR", "Package name is null", null)
                    }
                }
                "startForegroundService" -> {
                    startForegroundService()
                    result.success(true)
                }
                "stopForegroundService" -> {
                    stopForegroundService()
                    result.success(true)
                }
                "checkPermissions" -> {
                    val granted = checkAllPermissions()
                    result.success(granted)
                }
                "requestUsageStatsPermission" -> {
                    requestUsageStatsPermission()
                    result.success(true)
                }
                "hasUsageStatsPermission" -> {
                    val hasPermission = hasUsageStatsPermission()
                    result.success(hasPermission)
                }
                "checkAndRequestAllPermissions" -> {
                    checkAndRequestAllPermissions()
                    result.success(true)
                }
                "saveServerUrl" -> {
                    val url = call.argument<String>("url")
                    if (url != null) {
                        saveServerUrlForNative(url)
                        result.success(true)
                    } else {
                        result.error("ERROR", "URL is null", null)
                    }
                }
                "triggerTestEvent" -> {
                    triggerTestEvents()
                    result.success(true)
                }
                "startMonitoringService" -> {
                    startMonitoringService()
                    result.success(true)
                }
                "getServerUrlStatus" -> {
                    val status = getServerUrlStatus()
                    result.success(status)
                }
                "testWazuhConnection" -> {
                    testWazuhConnection()
                    result.success(true)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, ADVANCED_CHANNEL).setMethodCallHandler { call, result ->
            Log.d("MainActivity", "Advanced method called: ${call.method}")
            
            when (call.method) {
                "startMonitoringService" -> {
                    startMonitoringService()
                    result.success(true)
                }
                "stopMonitoringService" -> {
                    stopMonitoringService()
                    result.success(true)
                }
                "isMonitoringRunning" -> {
                    result.success(isServiceRunning(MonitoringForegroundService::class.java))
                }
                "getPendingEventsCount" -> {
                    val counts = getPendingEventsCount()
                    result.success(counts)
                }
                "setMonitoringInterval" -> {
                    val seconds = call.argument<Int>("seconds") ?: 30
                    val interval = seconds * 1000L
                    val prefs = getSharedPreferences("monitoring_settings", Context.MODE_PRIVATE)
                    prefs.edit().putLong("monitoring_interval", interval).apply()
                    result.success(true)
                }
                "getMonitoringStats" -> {
                    val stats = getMonitoringStats()
                    result.success(stats)
                }
                "getMonitoringData" -> {
                    val data = getMonitoringData()
                    result.success(data)
                }
                "clearMonitoringData" -> {
                    clearMonitoringData()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }
    
    private fun requestNeededPermissions() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            val permissions = mutableListOf<String>()
            
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) 
                != PackageManager.PERMISSION_GRANTED) {
                permissions.add(Manifest.permission.POST_NOTIFICATIONS)
            }
            
            if (permissions.isNotEmpty()) {
                ActivityCompat.requestPermissions(this, permissions.toTypedArray(), PERMISSION_REQUEST_CODE)
            }
        }
        
        if (!hasUsageStatsPermission()) {
            showUsageStatsPermissionDialog()
        }
    }
    
    private fun checkAllPermissions(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) 
                != PackageManager.PERMISSION_GRANTED) {
                return false
            }
        }
        return hasUsageStatsPermission()
    }
    
    private fun checkAndRequestAllPermissions() {
        requestNeededPermissions()
    }
    
    private fun hasUsageStatsPermission(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            val appOps = getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
            val mode = appOps.checkOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                android.os.Process.myUid(),
                packageName
            )
            return mode == AppOpsManager.MODE_ALLOWED
        }
        return true
    }
    
    private fun requestUsageStatsPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP && !hasUsageStatsPermission()) {
            val intent = Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)
            startActivity(intent)
        }
    }
    
    private fun showUsageStatsPermissionDialog() {
        AlertDialog.Builder(this)
            .setTitle("App Usage Permission")
            .setMessage("For app usage tracking, you need to grant usage access permission. This allows the app to monitor which apps you're using and for how long.")
            .setPositiveButton("Open Settings") { dialog, _ ->
                dialog.dismiss()
                requestUsageStatsPermission()
            }
            .setNegativeButton("Later") { dialog, _ ->
                dialog.dismiss()
            }
            .setCancelable(false)
            .show()
    }
    
    private fun getInstallSource(packageName: String): String {
        return try {
            val packageManager = applicationContext.packageManager
            val installerPackageName = packageManager.getInstallerPackageName(packageName)
            
            installerPackageName?.let {
                when (it) {
                    "com.android.vending" -> "Google Play Store"
                    "com.amazon.venezia" -> "Amazon Appstore"
                    "com.samsung.android.app.galaxyappstore" -> "Samsung Galaxy Store"
                    "com.huawei.appmarket" -> "Huawei AppGallery"
                    "com.xiaomi.market" -> "Xiaomi App Store"
                    "com.oppo.market" -> "Oppo App Market"
                    "com.vivo.appstore" -> "Vivo App Store"
                    "com.tencent.android.qqdownloader" -> "Tencent App Center"
                    "com.sec.android.app.samsungapps" -> "Samsung Apps"
                    "com.lenovo.leos.appstore" -> "Lenovo App Store"
                    "com.android.packageinstaller" -> "Manual Install"
                    else -> it
                }
            } ?: "Unknown"
        } catch (e: Exception) {
            "Unknown"
        }
    }
    
    private fun startForegroundService() {
        Log.d("MainActivity", "Starting foreground service")
        
        val serviceIntent = Intent(this, ForegroundService::class.java)
        serviceIntent.action = ForegroundService.ACTION_START
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(serviceIntent)
        } else {
            startService(serviceIntent)
        }
        
        startMonitoringService()
    }
    
    private fun startMonitoringService() {
        Log.d("MainActivity", "Starting monitoring service")
        
        try {
            val serviceIntent = Intent(this, MonitoringForegroundService::class.java)
            serviceIntent.action = MonitoringForegroundService.ACTION_START
            
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(serviceIntent)
            } else {
                startService(serviceIntent)
            }
            
            Log.d("MainActivity", "✓ Monitoring service started")
        } catch (e: Exception) {
            Log.e("MainActivity", "✗ Error starting monitoring service: $e")
        }
    }
    
    private fun stopForegroundService() {
        Log.d("MainActivity", "Stopping foreground service")
        
        val serviceIntent = Intent(this, ForegroundService::class.java)
        serviceIntent.action = ForegroundService.ACTION_STOP
        startService(serviceIntent)
        
        stopMonitoringService()
    }
    
    private fun stopMonitoringService() {
        Log.d("MainActivity", "Stopping monitoring service")
        
        try {
            val monitoringIntent = Intent(this, MonitoringForegroundService::class.java)
            monitoringIntent.action = MonitoringForegroundService.ACTION_STOP
            startService(monitoringIntent)
            
            Log.d("MainActivity", "✓ Monitoring service stop requested")
        } catch (e: Exception) {
            Log.e("MainActivity", "✗ Error stopping monitoring service: $e")
        }
    }
    
    private fun isServiceRunning(serviceClass: Class<*>): Boolean {
        return try {
            val manager = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            val services = manager.getRunningServices(Integer.MAX_VALUE)
            services.any { it.service.className == serviceClass.name }
        } catch (e: Exception) {
            Log.e("MainActivity", "Error checking service status: $e")
            false
        }
    }
    
    private fun getPendingEventsCount(): Map<String, Any> {
        return try {
            val prefs = getSharedPreferences("monitoring_events", Context.MODE_PRIVATE)
            mapOf(
                "app_events" to (prefs.getStringSet("app_events", mutableSetOf())?.size ?: 0),
                "screen_events" to (prefs.getStringSet("screen_events", mutableSetOf())?.size ?: 0),
                "power_events" to (prefs.getStringSet("power_events", mutableSetOf())?.size ?: 0),
                "foreground_events" to (prefs.getStringSet("foreground_events", mutableSetOf())?.size ?: 0)
            )
        } catch (e: Exception) {
            Log.e("MainActivity", "Error getting pending events: $e")
            mapOf<String, Any>()
        }
    }
    
    private fun getMonitoringStats(): Map<String, Any> {
        return try {
            val serviceRunning = isServiceRunning(MonitoringForegroundService::class.java)
            val prefs = getSharedPreferences("monitoring_data", Context.MODE_PRIVATE)
            val settingsPrefs = getSharedPreferences("monitoring_settings", Context.MODE_PRIVATE)
            
            val interval = settingsPrefs.getLong("monitoring_interval", 30000L)
            val lastCheck = prefs.getLong("last_monitoring_check", 0L)
            val eventsProcessed = prefs.getInt("events_processed_total", 0)
            
            val pendingEvents = getPendingEventsCount()
            val totalPending = pendingEvents.values.sumBy { (it as? Int) ?: 0 }
            
            val stats = mutableMapOf<String, Any>()
            stats["is_running"] = serviceRunning
            stats["current_interval"] = (interval / 1000)
            stats["last_check"] = lastCheck
            stats["events_processed"] = eventsProcessed
            stats["pending_events"] = totalPending
            stats["detailed_pending"] = pendingEvents
            stats["has_usage_permission"] = hasUsageStatsPermission()
            stats["has_notification_permission"] = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
            } else {
                true
            }
            stats["last_foreground_app"] = (prefs.getString("last_foreground_app", "None") ?: "None")
            stats["last_screen_event"] = (prefs.getString("last_screen_event", "None") ?: "None")
            stats["last_power_event"] = (prefs.getString("last_power_event", "None") ?: "None")
            
            stats
        } catch (e: Exception) {
            Log.e("MainActivity", "Error getting monitoring stats: $e")
            mapOf("error" to (e.message ?: "Unknown error"))
        }
    }
    
    private fun getMonitoringData(): Map<String, Any> {
        val data = mutableMapOf<String, Any>()
        
        try {
            data["timestamp"] = System.currentTimeMillis()
            
            try {
                val batteryIntent = registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
                batteryIntent?.let {
                    val level = it.getIntExtra(BatteryManager.EXTRA_LEVEL, -1)
                    val scale = it.getIntExtra(BatteryManager.EXTRA_SCALE, -1)
                    if (level != -1 && scale != -1) {
                        data["battery_percent"] = (level * 100) / scale
                    }
                }
            } catch (e: Exception) {
                data["battery_percent"] = -1
            }
            
            try {
                val connectivityManager = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
                val activeNetwork = connectivityManager.activeNetworkInfo
                data["network_type"] = activeNetwork?.typeName ?: "Unknown"
                data["is_connected"] = activeNetwork?.isConnected ?: false
            } catch (e: Exception) {
                data["network_type"] = "Unknown"
                data["is_connected"] = false
            }
            
        } catch (e: Exception) {
            Log.e("MainActivity", "Error getting monitoring data: $e")
            data["error"] = e.message ?: "Unknown error"
        }
        
        return data
    }
    
    private fun clearMonitoringData() {
        try {
            val prefs = getSharedPreferences("monitoring_events", Context.MODE_PRIVATE)
            prefs.edit().clear().apply()
            
            val dataPrefs = getSharedPreferences("monitoring_data", Context.MODE_PRIVATE)
            dataPrefs.edit().clear().apply()
            
            val settingsPrefs = getSharedPreferences("monitoring_settings", Context.MODE_PRIVATE)
            settingsPrefs.edit().remove("monitoring_interval").apply()
            
            Log.d("MainActivity", "✓ Monitoring data cleared")
        } catch (e: Exception) {
            Log.e("MainActivity", "Error clearing monitoring data: $e")
        }
    }
    
    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        
        when (requestCode) {
            PERMISSION_REQUEST_CODE -> {
                val allGranted = grantResults.all { it == PackageManager.PERMISSION_GRANTED }
                if (allGranted) {
                    Log.d("MainActivity", "✓ All permissions granted")
                } else {
                    Log.d("MainActivity", "✗ Some permissions denied")
                }
            }
            USAGE_STATS_PERMISSION_REQUEST_CODE -> {
                if (hasUsageStatsPermission()) {
                    Log.d("MainActivity", "✓ Usage stats permission granted")
                } else {
                    Log.d("MainActivity", "✗ Usage stats permission denied")
                }
            }
        }
    }
    
    private fun storeMonitoringEvent(type: String, data: String) {
        try {
            val prefs = getSharedPreferences("monitoring_events", Context.MODE_PRIVATE)
            val events = prefs.getStringSet("${type}_events", mutableSetOf())?.toMutableSet() ?: mutableSetOf()
            
            val timestamp = System.currentTimeMillis()
            events.add("$timestamp|$data")
            
            if (events.size > 100) {
                val sorted = events.sorted().takeLast(100).toMutableSet()
                events.clear()
                events.addAll(sorted)
            }
            
            prefs.edit().putStringSet("${type}_events", events).apply()
            prefs.edit().putString("last_${type}_event", data).apply()
            
            Log.d("MainActivity", "✓ Event stored: $type - $data")
        } catch (e: Exception) {
            Log.e("MainActivity", "Error storing event: $e")
        }
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

    private fun saveServerUrlForNative(serverUrl: String) {
        Log.d("MainActivity", "=== SAVING SERVER URL ===")
        Log.d("MainActivity", "Received URL: '$serverUrl'")
        
        try {
            val cleanUrl = serverUrl
                .replace("http://", "")
                .replace("https://", "")
                .trim()
            
            Log.d("MainActivity", "Cleaned URL: '$cleanUrl'")
            
            val prefConfigs = listOf(
                Pair("monitoring_settings", "server_url"),
                Pair("app_monitor", "wazuh_server_url"),
                Pair("app_monitor", "server_url")
            )
            
            var savedCount = 0
            prefConfigs.forEach { (prefName, key) ->
                try {
                    val prefs = getSharedPreferences(prefName, Context.MODE_PRIVATE)
                    prefs.edit().putString(key, cleanUrl).apply()
                    savedCount++
                    Log.d("MainActivity", "✓ Saved to $prefName -> $key")
                } catch (e: Exception) {
                    Log.e("MainActivity", "✗ Error saving to $prefName: $e")
                }
            }
            
            try {
                val flutterPrefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                flutterPrefs.edit().putString("flutter.server_url", cleanUrl).apply()
                savedCount++
                Log.d("MainActivity", "✓ Saved to FlutterSharedPreferences")
            } catch (e: Exception) {
                Log.e("MainActivity", "✗ Error saving to FlutterSharedPreferences: $e")
            }
            
            Log.d("MainActivity", "✓ Server URL saved to $savedCount locations")
            
            startMonitoringService()
            
            sendTestLogToWazuh()
            
        } catch (e: Exception) {
            Log.e("MainActivity", "✗ Error saving server URL: $e")
        }
    }
    
    private fun sendTestLogToWazuh() {
        Log.d("MainActivity", "Sending test log to Wazuh...")
        
        WazuhSender.sendToWazuh(this, "CONFIG_TEST", "Server URL saved successfully from MainActivity")
        
        Log.d("MainActivity", "✓ Test log sent to Wazuh")
    }
    
    private fun getServerUrlStatus(): Map<String, Any> {
        Log.d("MainActivity", "Checking server URL status...")
        
        val status = mutableMapOf<String, Any>()
        val locations = mutableMapOf<String, String>()
        
        val checkLocations = listOf(
            Pair("monitoring_settings", "server_url"),
            Pair("app_monitor", "wazuh_server_url"),
            Pair("app_monitor", "server_url")
        )
        
        checkLocations.forEach { (prefName, key) ->
            try {
                val prefs = getSharedPreferences(prefName, Context.MODE_PRIVATE)
                val url = prefs.getString(key, null)
                locations["$prefName.$key"] = url ?: ""
                
                Log.d("MainActivity", "$prefName.$key = '$url'")
            } catch (e: Exception) {
                locations["$prefName.$key"] = "ERROR: ${e.message}"
            }
        }
        
        try {
            val flutterPrefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val flutterUrl = flutterPrefs.getString("flutter.server_url", null)
            locations["FlutterSharedPreferences.flutter.server_url"] = flutterUrl ?: ""
            Log.d("MainActivity", "FlutterSharedPreferences.flutter.server_url = '$flutterUrl'")
        } catch (e: Exception) {
            locations["FlutterSharedPreferences"] = "ERROR: ${e.message}"
        }
        
        val anyUrlSet = locations.values.any { it.isNotEmpty() && it != "null" }
        val firstUrl = locations.values.firstOrNull { it.isNotEmpty() && it != "null" } ?: ""
        
        status["locations"] = locations
        status["any_url_set"] = anyUrlSet
        status["first_url_found"] = firstUrl
        status["timestamp"] = System.currentTimeMillis()
        
        Log.d("MainActivity", "Server URL status: Any URL set = $anyUrlSet")
        
        return status
    }
    
    private fun testWazuhConnection() {
        Log.d("MainActivity", "=== TESTING WAZUH CONNECTION ===")
        
        val urlStatus = getServerUrlStatus()
        val anyUrlSet = urlStatus["any_url_set"] as? Boolean ?: false
        
        if (!anyUrlSet) {
            Log.e("MainActivity", "✗ Cannot test: No server URL configured")
            return
        }
        
        WazuhSender.sendToWazuh(this, "CONNECTION_TEST", 
            "Test message from MainActivity at ${System.currentTimeMillis()}")
        
        Log.d("MainActivity", "✓ Wazuh test initiated")
    }
    
    private fun triggerTestEvents() {
        try {
            Log.d("MainActivity", "=== TRIGGERING TEST EVENTS ===")
            
            WazuhSender.sendToWazuh(this, "APP_EVENT", "TEST: App 'TestApp' (com.test.app) - INSTALLED")
            WazuhSender.sendToWazuh(this, "SCREEN_EVENT", "TEST: Screen: SCREEN_ON")
            WazuhSender.sendToWazuh(this, "POWER_EVENT", "TEST: Power: CONNECTED (85%)")
            
            Log.d("MainActivity", "✓ Test events sent to Wazuh")
            
        } catch (e: Exception) {
            Log.e("MainActivity", "✗ Error triggering test events: $e")
        }
    }
    
    fun saveWazuhServerUrl(url: String) {
        saveServerUrlForNative(url)
    }
}