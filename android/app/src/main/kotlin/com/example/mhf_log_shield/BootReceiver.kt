package com.example.mhf_log_shield

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED || 
            intent.action == "android.intent.action.QUICKBOOT_POWERON") {
            // Start your service or background task here
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val serviceIntent = Intent(context, ForegroundService::class.java)
                serviceIntent.action = ForegroundService.ACTION_START
                context.startForegroundService(serviceIntent)
            }
        }
    }
}