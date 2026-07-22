package com.example.betstop_kenya.deviceadmin

import android.app.Activity
import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Method Channel Handler for Device Admin operations
 * 
 * Handles Flutter-to-Native communication for device admin management.
 */
class DeviceAdminChannelHandler(
    private val context: Context,
    private val activity: Activity?
) : MethodChannel.MethodCallHandler {
    
    companion object {
        private const val TAG = "DeviceAdminChannel"
        private const val REQUEST_CODE_ENABLE_ADMIN = 1001
        
        var pendingResult: MethodChannel.Result? = null
        
        fun handleActivityResult(requestCode: Int, resultCode: Int): Boolean {
            if (requestCode == REQUEST_CODE_ENABLE_ADMIN) {
                val success = resultCode == Activity.RESULT_OK
                pendingResult?.success(success)
                pendingResult = null
                return true
            }
            return false
        }
    }
    
    private val devicePolicyManager: DevicePolicyManager by lazy {
        context.getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
    }
    
    private val componentName: ComponentName by lazy {
        ComponentName(context, BetStopDeviceAdminReceiver::class.java)
    }
    
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isAdminActive" -> {
                result.success(devicePolicyManager.isAdminActive(componentName))
            }
            "requestAdminPermission" -> {
                requestAdminPermission(result)
            }
            "removeAdmin" -> {
                removeAdmin(result)
            }
            "reRegisterAdmin" -> {
                reRegisterAdmin(result)
            }
            else -> {
                result.notImplemented()
            }
        }
    }
    
    private fun requestAdminPermission(result: MethodChannel.Result) {
        try {
            if (devicePolicyManager.isAdminActive(componentName)) {
                result.success(true)
                return
            }
            
            val intent = Intent(DevicePolicyManager.ACTION_ADD_DEVICE_ADMIN)
            intent.putExtra(DevicePolicyManager.EXTRA_DEVICE_ADMIN, componentName)
            intent.putExtra(DevicePolicyManager.EXTRA_ADD_EXPLANATION, 
                "BetStop needs device admin permission to prevent uninstallation during your commitment period.")
            
            activity?.startActivityForResult(intent, REQUEST_CODE_ENABLE_ADMIN)
            pendingResult = result
        } catch (e: Exception) {
            Log.e(TAG, "Error requesting device admin permission", e)
            result.success(false)
        }
    }
    
    private fun removeAdmin(result: MethodChannel.Result) {
        try {
            if (!devicePolicyManager.isAdminActive(componentName)) {
                result.success(true)
                return
            }
            
            val success = devicePolicyManager.removeActiveAdmin(componentName)
            result.success(success)
        } catch (e: Exception) {
            Log.e(TAG, "Error removing device admin", e)
            result.success(false)
        }
    }
    
    private fun reRegisterAdmin(result: MethodChannel.Result) {
        try {
            if (devicePolicyManager.isAdminActive(componentName)) {
                result.success(true)
                return
            }
            
            val intent = Intent(DevicePolicyManager.ACTION_ADD_DEVICE_ADMIN)
            intent.putExtra(DevicePolicyManager.EXTRA_DEVICE_ADMIN, componentName)
            intent.putExtra(DevicePolicyManager.EXTRA_ADD_EXPLANATION, 
                "Re-enabling BetStop protection after deactivation request.")
            
            activity?.startActivityForResult(intent, REQUEST_CODE_ENABLE_ADMIN)
            result.success(true)
        } catch (e: Exception) {
            Log.e(TAG, "Error re-registering device admin", e)
            result.success(false)
        }
    }
}
