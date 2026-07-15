package com.example.betstop_kenya

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * Boot receiver to auto-start VPN service after device reboot
 * Only starts VPN if vpn_setup_complete flag is set (user has previously granted VPN permission)
 */
class BootReceiver : BroadcastReceiver() {
    
    companion object {
        private const val TAG = "BootReceiver"
        private const val PREFS_NAME = "betstop_vpn"
        private const val VPN_SETUP_COMPLETE_KEY = "vpn_setup_complete"
    }
    
    override fun onReceive(context: Context?, intent: Intent?) {
        if (context == null || intent == null) return
        
        if (intent.action == Intent.ACTION_BOOT_COMPLETED) {
            Log.i(TAG, "Boot completed received")
            
            // Check if VPN setup was previously completed
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val vpnSetupComplete = prefs.getBoolean(VPN_SETUP_COMPLETE_KEY, false)
            
            if (vpnSetupComplete) {
                Log.i(TAG, "VPN setup complete flag is true, starting VPN service")
                
                // Start VPN service directly without UI
                val vpnIntent = Intent(context, com.example.betstop_kenya.dnsblock.DnsVpnService::class.java)
                vpnIntent.action = "START"
                context.startService(vpnIntent)
                
                Log.i(TAG, "VPN service started from boot receiver")
            } else {
                Log.i(TAG, "VPN setup complete flag is false, not starting VPN service")
            }
        }
    }
}
