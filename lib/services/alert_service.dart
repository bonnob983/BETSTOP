import 'dart:convert';
import 'package:http/http.dart' as http;

/// Alert Service
/// 
/// Handles alert events logging and guardian notifications
/// for VPN disable/switch events
class AlertService {
  static const String baseUrl = 'https://betstop-production.up.railway.app';
  
  /// Log VPN disable/switch event and notify guardian
  /// 
  /// This calls a new backend endpoint that:
  /// 1. Logs the event to alert_events table (event_type='vpn_disabled_or_switched')
  /// 2. Sends SMS to guardian via Africa's Talking integration
  Future<void> logVpnDisableEvent({
    required String token,
    required String userId,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/alerts/vpn-disabled'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'user_id': userId,
          'event_type': 'vpn_disabled_or_switched',
          'timestamp': DateTime.now().toIso8601String(),
        }),
      );
      
      if (response.statusCode != 200) {
        throw Exception('Failed to log VPN disable event: ${response.body}');
      }
      
      print('VPN disable event logged successfully');
    } catch (e) {
      print('Error logging VPN disable event: $e');
      // Don't throw - this is a non-critical notification
    }
  }
  
  /// Report a site not blocked (for manual review)
  /// 
  /// Submits to blocklist_suggestions table
  Future<void> reportUnblockedSite({
    required String token,
    required String userId,
    required String domain,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/blocklist/suggestions'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'domain': domain.toLowerCase(),
          'submitted_by_user_id': userId,
          'status': 'pending',
          'submitted_at': DateTime.now().toIso8601String(),
        }),
      );
      
      if (response.statusCode != 201) {
        throw Exception('Failed to report unblocked site: ${response.body}');
      }
      
      print('Unblocked site reported successfully');
    } catch (e) {
      throw Exception('Failed to report unblocked site: $e');
    }
  }
}
