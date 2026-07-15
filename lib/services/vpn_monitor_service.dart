import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// VPN Monitor Service
/// 
/// Listens for VPN revoke broadcasts from the native Android VPN service
/// and triggers guardian alerts when VPN is disabled or switched
class VpnMonitorService {
  static const MethodChannel _channel = MethodChannel('com.example.betstop_kenya/vpn_monitor');
  static const String _vpnRevokedKey = 'vpn_revoked';
  static const String _vpnRevokedTimeKey = 'vpn_revoked_time';
  
  static final VpnMonitorService _instance = VpnMonitorService._internal();
  factory VpnMonitorService() => _instance;
  VpnMonitorService._internal();
  
  Timer? _checkTimer;
  final _vpnRevokeController = StreamController<bool>.broadcast();
  
  /// Stream that emits true when VPN is revoked
  Stream<bool> get onVpnRevoke => _vpnRevokeController.stream;
  
  /// Start monitoring VPN status
  Future<void> startMonitoring() async {
    try {
      await _channel.invokeMethod('startMonitoring');
      
      // Start periodic check for VPN revoke flag
      _checkTimer?.cancel();
      _checkTimer = Timer.periodic(const Duration(seconds: 2), (_) => _checkVpnRevokeFlag());
      
      debugPrint('VPN monitoring started');
    } catch (e) {
      debugPrint('Failed to start VPN monitoring: $e');
    }
  }
  
  /// Stop monitoring VPN status
  Future<void> stopMonitoring() async {
    try {
      await _channel.invokeMethod('stopMonitoring');
      _checkTimer?.cancel();
      debugPrint('VPN monitoring stopped');
    } catch (e) {
      debugPrint('Failed to stop VPN monitoring: $e');
    }
  }
  
  /// Check if VPN was revoked (called periodically)
  Future<void> _checkVpnRevokeFlag() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final wasRevoked = prefs.getBool(_vpnRevokedKey) ?? false;
      
      if (wasRevoked) {
        // Clear the flag after detecting
        await prefs.setBool(_vpnRevokedKey, false);
        final revokedTime = prefs.getInt(_vpnRevokedTimeKey) ?? DateTime.now().millisecondsSinceEpoch;
        
        debugPrint('VPN revoke detected at ${DateTime.fromMillisecondsSinceEpoch(revokedTime)}');
        _vpnRevokeController.add(true);
      }
    } catch (e) {
      debugPrint('Error checking VPN revoke flag: $e');
    }
  }
  
  /// Check if VPN is currently revoked (for UI banner)
  Future<bool> isVpnRevoked() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_vpnRevokedKey) ?? false;
    } catch (e) {
      debugPrint('Error checking VPN revoked status: $e');
      return false;
    }
  }
  
  void dispose() {
    _checkTimer?.cancel();
    _vpnRevokeController.close();
  }
}
