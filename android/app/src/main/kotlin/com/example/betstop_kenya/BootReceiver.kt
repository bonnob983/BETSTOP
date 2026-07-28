package com.example.betstop_kenya

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * Boot receiver to auto-start VPN service after device reboot
 * DISABLED: Auto-start is too risky until VPN DNS cleanup is proven stable
 * User must manually start VPN through app UI to ensure proper state management
 */
class BootReceiver : BroadcastReceiver() {
    
    companion object {
        private const val TAG = "BootReceiver"
    }
    
    override fun onReceive(context: Context?, intent: Intent?) {
        if (context == null || intent == null) return
        
        if (intent.action == Intent.ACTION_BOOT_COMPLETED) {
            Log.i(TAG, "Boot completed received - VPN auto-start DISABLED for safety")
            // VPN auto-start disabled until DNS cleanup mechanism is proven stable
            // User must manually start VPN through app UI
        }
    }
}
