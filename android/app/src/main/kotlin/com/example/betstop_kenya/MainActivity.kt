package com.example.betstop_kenya

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.VpnService
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val DNS_BLOCK_CHANNEL = "com.example.betstop_kenya/dns_block"
    private val VPN_MONITOR_CHANNEL = "com.example.betstop_kenya/vpn_monitor"
    private val DEVICE_ADMIN_CHANNEL = "com.example.betstop_kenya/device_admin"
    private val TAG = "MainActivity"
    
    private var vpnRevokeReceiver: BroadcastReceiver? = null
    private var deactivationReceiver: BroadcastReceiver? = null
    private var vpnPermissionResult: MethodChannel.Result? = null
    private var timeoutHandler = Handler(Looper.getMainLooper())
    private var timeoutRunnable: Runnable? = null
    private val VPN_START_TIMEOUT_MS = 10000L
    private var deviceAdminHandler: com.example.betstop_kenya.deviceadmin.DeviceAdminChannelHandler? = null
    private var deviceAdminChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // DNS Block channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, DNS_BLOCK_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startDnsBlocking" -> {
                    try {
                        val intent = VpnService.prepare(this@MainActivity)
                        if (intent != null) {
                            // Need to request VPN permission
                            startActivityForResult(intent, 0)
                            result.success("VPN_PERMISSION_REQUESTED")
                        } else {
                            // Permission already granted, start VPN
                            startVpnService()
                            result.success("VPN_STARTED")
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "Error starting DNS blocking: ${e.message}")
                        result.error("VPN_ERROR", e.message, null)
                    }
                }
                "stopDnsBlocking" -> {
                    try {
                        stopVpnService()
                        result.success("VPN_STOPPED")
                    } catch (e: Exception) {
                        Log.e(TAG, "Error stopping DNS blocking: ${e.message}")
                        result.error("VPN_ERROR", e.message, null)
                    }
                }
                "updateBlocklist" -> {
                    try {
                        val domains = call.argument<List<String>>("domains")
                        if (domains != null) {
                            updateBlocklist(domains)
                            result.success("BLOCKLIST_UPDATED")
                        } else {
                            result.error("INVALID_ARGUMENTS", "Domains list is required", null)
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "Error updating blocklist: ${e.message}")
                        result.error("BLOCKLIST_ERROR", e.message, null)
                    }
                }
                "requestVpnPermissionAndStart" -> {
                    try {
                        requestVpnPermissionAndStart(result)
                    } catch (e: Exception) {
                        Log.e(TAG, "Error in requestVpnPermissionAndStart: ${e.message}")
                        result.error("VPN_ERROR", e.message, null)
                    }
                }
                "isVpnActive" -> {
                    try {
                        val isActive = isVpnServiceRunning()
                        result.success(isActive)
                    } catch (e: Exception) {
                        Log.e(TAG, "Error checking VPN status: ${e.message}")
                        result.error("VPN_ERROR", e.message, null)
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
        
        // VPN Monitor channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, VPN_MONITOR_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startMonitoring" -> {
                    startVpnMonitoring()
                    result.success(null)
                }
                "stopMonitoring" -> {
                    stopVpnMonitoring()
                    result.success(null)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
        
        // Device Admin channel
        deviceAdminHandler = com.example.betstop_kenya.deviceadmin.DeviceAdminChannelHandler(this, this)
        deviceAdminChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, DEVICE_ADMIN_CHANNEL)
        deviceAdminChannel?.setMethodCallHandler { call, result ->
            deviceAdminHandler?.onMethodCall(call, result)
        }
        
        // Register deactivation broadcast receiver
        registerDeactivationReceiver()
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        
        // Handle VPN permission result
        if (requestCode == 0) {
            if (resultCode == RESULT_OK) {
                // VPN permission granted, start VPN and wait for service to start
                startVpnService()
                registerVpnStartedListener()
            } else {
                // Permission denied
                vpnPermissionResult?.success(mapOf(
                    "success" to false,
                    "error" to "PERMISSION_DENIED"
                ))
                vpnPermissionResult = null
            }
        }
        
        // Handle device admin permission result
        deviceAdminHandler?.let {
            if (com.example.betstop_kenya.deviceadmin.DeviceAdminChannelHandler.handleActivityResult(requestCode, resultCode)) {
                // Handled by device admin handler
            }
        }
    }

    private fun startVpnService() {
        val intent = Intent(this, com.example.betstop_kenya.dnsblock.DnsVpnService::class.java)
        intent.action = "START"
        startService(intent)
        Log.i(TAG, "VPN service started")
    }

    private fun stopVpnService() {
        val intent = Intent(this, com.example.betstop_kenya.dnsblock.DnsVpnService::class.java)
        intent.action = "STOP"
        startService(intent)
        Log.i(TAG, "VPN service stopped")
    }

    private fun requestVpnPermissionAndStart(result: MethodChannel.Result) {
        vpnPermissionResult = result
        
        val intent = VpnService.prepare(this@MainActivity)
        if (intent != null) {
            // Need to request VPN permission
            startActivityForResult(intent, 0)
        } else {
            // Permission already granted, start VPN directly
            startVpnService()
            registerVpnStartedListener()
        }
    }

    private fun registerVpnStartedListener() {
        com.example.betstop_kenya.dnsblock.DnsVpnService.onVpnStartedListener = {
            runOnUiThread {
                Log.i(TAG, "VPN started listener fired")
                if (isVpnServiceRunning()) {
                    finishVpnResult(success = true, error = null)
                } else {
                    finishVpnResult(success = false, error = "VPN_START_FAILED")
                }
            }
        }

        // Register sustained failure listener
        com.example.betstop_kenya.dnsblock.DnsVpnService.onSustainedFailureListener = {
            runOnUiThread {
                Log.w(TAG, "Sustained DNS failure detected - notifying Flutter")
                // Notify Flutter via method channel
                MethodChannel(flutterEngine?.dartExecutor?.binaryMessenger ?: return@runOnUiThread, DNS_BLOCK_CHANNEL)
                    .invokeMethod("onSustainedDnsFailure", null)
            }
        }

        timeoutRunnable = Runnable {
            Log.e(TAG, "VPN service start timeout")
            finishVpnResult(success = false, error = "VPN_START_FAILED")
        }
        timeoutHandler.postDelayed(timeoutRunnable!!, VPN_START_TIMEOUT_MS)
    }

    private fun finishVpnResult(success: Boolean, error: String?) {
        com.example.betstop_kenya.dnsblock.DnsVpnService.onVpnStartedListener = null
        com.example.betstop_kenya.dnsblock.DnsVpnService.onSustainedFailureListener = null
        timeoutRunnable?.let { timeoutHandler.removeCallbacks(it) }
        timeoutRunnable = null
        if (success) {
            getSharedPreferences("betstop_vpn", Context.MODE_PRIVATE)
                .edit()
                .putBoolean("vpn_setup_complete", true)
                .apply()
        }
        vpnPermissionResult?.success(mapOf(
            "success" to success,
            "error" to error
        ))
        vpnPermissionResult = null
    }

    private fun isVpnServiceRunning(): Boolean {
        return com.example.betstop_kenya.dnsblock.DnsVpnService.isRunning
    }

    private fun updateBlocklist(domains: List<String>) {
        // This will be called by the VPN service when it needs the blocklist
        // For now, we'll store it in a singleton that the VPN service can access
        BlocklistHolder.domains = domains
        Log.i(TAG, "Blocklist updated with ${domains.size} domains")
    }
    
    private fun startVpnMonitoring() {
        if (vpnRevokeReceiver != null) {
            Log.w(TAG, "VPN monitoring already started")
            return
        }
        
        vpnRevokeReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                if (intent?.action == "com.example.betstop_kenya.VPN_REVOKED") {
                    Log.w(TAG, "VPN revoke broadcast received")
                    // Notify Flutter via method channel
                    // For simplicity, we'll use a shared preference flag
                    val prefs = getSharedPreferences("betstop_vpn", Context.MODE_PRIVATE)
                    prefs.edit().putBoolean("vpn_revoked", true).putLong("vpn_revoked_time", System.currentTimeMillis()).apply()
                }
            }
        }
        
        val filter = IntentFilter("com.example.betstop_kenya.VPN_REVOKED")
        registerReceiver(vpnRevokeReceiver, filter)
        Log.i(TAG, "VPN revoke monitoring started")
    }
    
    private fun stopVpnMonitoring() {
        vpnRevokeReceiver?.let {
            unregisterReceiver(it)
            vpnRevokeReceiver = null
            Log.i(TAG, "VPN revoke monitoring stopped")
        }
    }
    
    private fun registerDeactivationReceiver() {
        if (deactivationReceiver != null) {
            Log.w(TAG, "Deactivation receiver already registered")
            return
        }
        
        deactivationReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                if (intent?.action == com.example.betstop_kenya.deviceadmin.BetStopDeviceAdminReceiver.ACTION_DEACTIVATION_REQUESTED) {
                    Log.i(TAG, "Deactivation request broadcast received")
                    // Notify Flutter via method channel
                    deviceAdminChannel?.invokeMethod("onDeactivationRequested", null)
                }
            }
        }
        
        val filter = IntentFilter(com.example.betstop_kenya.deviceadmin.BetStopDeviceAdminReceiver.ACTION_DEACTIVATION_REQUESTED)
        registerReceiver(deactivationReceiver, filter)
        Log.i(TAG, "Deactivation receiver registered")
    }
    
    private fun unregisterDeactivationReceiver() {
        deactivationReceiver?.let {
            unregisterReceiver(it)
            deactivationReceiver = null
            Log.i(TAG, "Deactivation receiver unregistered")
        }
    }
    
    override fun onDestroy() {
        stopVpnMonitoring()
        unregisterDeactivationReceiver()
        com.example.betstop_kenya.dnsblock.DnsVpnService.onVpnStartedListener = null
        com.example.betstop_kenya.dnsblock.DnsVpnService.onSustainedFailureListener = null
        timeoutRunnable?.let { timeoutHandler.removeCallbacks(it) }
        super.onDestroy()
    }
}

// Singleton to hold blocklist data between Flutter and native VPN service
object BlocklistHolder {
    var domains: List<String> = emptyList()
}