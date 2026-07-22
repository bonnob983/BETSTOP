package com.example.betstop_kenya.deviceadmin

import android.app.admin.DeviceAdminReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import android.widget.Toast

/**
 * Device Admin Receiver for BetStop Kenya
 * 
 * Prevents uninstallation while device admin is active.
 * When user attempts to deactivate, logs request to server and shows warning.
 */
class BetStopDeviceAdminReceiver : DeviceAdminReceiver() {
    
    companion object {
        private const val TAG = "BetStopDeviceAdmin"
        const val ACTION_DEACTIVATION_REQUESTED = "com.example.betstop_kenya.DEACTIVATION_REQUESTED"
    }
    
    override fun onDisableRequested(context: Context, intent: Intent): CharSequence {
        Log.w(TAG, "User requested device admin deactivation")
        
        // Send broadcast to Flutter app to handle deactivation request
        val broadcastIntent = Intent(ACTION_DEACTIVATION_REQUESTED)
        context.sendBroadcast(broadcastIntent)
        
        // Show toast to user
        Toast.makeText(
            context,
            "Deactivation request logged. Check BetStop app for details.",
            Toast.LENGTH_LONG
        ).show()
        
        // Return warning message (this is shown in system dialog)
        return "Deactivating BetStop will log your request. You can fully remove the app after 24 hours if you still want to."
    }
    
    override fun onEnabled(context: Context, intent: Intent) {
        super.onEnabled(context, intent)
        Log.i(TAG, "Device admin enabled")
        Toast.makeText(context, "BetStop protection enabled", Toast.LENGTH_SHORT).show()
    }
    
    override fun onDisabled(context: Context, intent: Intent) {
        super.onDisabled(context, intent)
        Log.w(TAG, "Device admin disabled")
        Toast.makeText(context, "BetStop protection disabled", Toast.LENGTH_SHORT).show()
    }
}
