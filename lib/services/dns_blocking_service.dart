import 'package:flutter/services.dart';
import 'blocklist_service.dart';

/// DNS Blocking Service
/// 
/// This service provides a Flutter interface to the native Android VPN service
/// that implements DNS-only website blocking for known licensed betting operators.
/// 
/// The native VPN routes ONLY DNS traffic through the tunnel (single /32 host route),
/// not all traffic like competitor apps. This ensures zero perceptible impact on
/// speed or battery life.
/// 
/// Note: This blocks known licensed betting operators, updated as new ones are verified.
/// It does not block all gambling sites.
/// 
/// Usage:
/// ```dart
/// final dnsService = DnsBlockingService(blocklistService);
/// await dnsService.loadBlocklist(); // Fetch from Supabase
/// await dnsService.startBlocking(); // Prompts user for VPN permission
/// await dnsService.stopBlocking();
/// ```
class DnsBlockingService {
  static const MethodChannel _channel = MethodChannel('com.example.betstop_kenya/dns_block');
  
  final BlocklistService _blocklistService;
  
  bool _isBlocking = false;
  List<String> _currentBlocklist = [];
  
  /// Whether DNS blocking is currently active
  bool get isBlocking => _isBlocking;
  
  /// Current blocklist being used
  List<String> get currentBlocklist => List.unmodifiable(_currentBlocklist);
  
  DnsBlockingService(this._blocklistService);
  
  /// Load blocklist from Supabase and update the native VPN service
  Future<void> loadBlocklist() async {
    try {
      _currentBlocklist = await _blocklistService.fetchBlockedDomains();
      
      // Update the native VPN service with the new blocklist
      await _channel.invokeMethod('updateBlocklist', {
        'domains': _currentBlocklist,
      });
    } catch (e) {
      throw Exception('Failed to load blocklist: $e');
    }
  }
  
  /// Start DNS blocking
  /// 
  /// This will prompt the user to grant VPN permission if not already granted.
  /// Returns a string indicating the result:
  /// - "VPN_PERMISSION_REQUESTED": User needs to grant permission
  /// - "VPN_STARTED": VPN service started successfully
  /// 
  /// Throws a PlatformException if the native call fails.
  Future<String> startBlocking() async {
    try {
      final result = await _channel.invokeMethod('startDnsBlocking');
      if (result == 'VPN_STARTED') {
        _isBlocking = true;
      }
      return result;
    } on PlatformException catch (e) {
      throw Exception('Failed to start DNS blocking: ${e.message}');
    }
  }
  
  /// Stop DNS blocking
  /// 
  /// Stops the VPN service and restores normal DNS resolution.
  /// Returns "VPN_STOPPED" on success.
  /// 
  /// Throws a PlatformException if the native call fails.
  Future<String> stopBlocking() async {
    try {
      final result = await _channel.invokeMethod('stopDnsBlocking');
      if (result == 'VPN_STOPPED') {
        _isBlocking = false;
      }
      return result;
    } on PlatformException catch (e) {
      throw Exception('Failed to stop DNS blocking: ${e.message}');
    }
  }
  
  /// Request VPN permission and start VPN service
  /// 
  /// This method waits for both permission grant AND VPN service startup confirmation.
  /// Returns a Map with:
  /// - 'success': bool - true if VPN is active, false otherwise
  /// - 'error': String? - error reason if failed (null if success)
  /// 
  /// Error reasons:
  /// - 'PERMISSION_DENIED': User denied VPN permission
  /// - 'VPN_START_FAILED': VPN service failed to start
  Future<Map<String, dynamic>> requestVpnPermissionAndStart() async {
    try {
      final result = await _channel.invokeMethod('requestVpnPermissionAndStart');
      if (result['success'] == true) {
        _isBlocking = true;
      }
      return Map<String, dynamic>.from(result);
    } on PlatformException catch (e) {
      throw Exception('Failed to request VPN permission and start: ${e.message}');
    }
  }
  
  /// Check if VPN is currently active
  /// 
  /// Returns true if VPN service is running, false otherwise.
  /// This checks the actual OS-level VPN state, not just cached state.
  Future<bool> isVpnActive() async {
    try {
      final result = await _channel.invokeMethod('isVpnActive');
      _isBlocking = result as bool;
      return result;
    } on PlatformException catch (e) {
      throw Exception('Failed to check VPN status: ${e.message}');
    }
  }
}
