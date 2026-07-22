import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:betstop_kenya/services/api_service.dart';

/// Device Admin Service
/// 
/// Manages device admin activation, deactivation requests, and 24-hour cooldown.
class DeviceAdminService {
  static const MethodChannel _channel = MethodChannel('com.example.betstop_kenya/device_admin');
  static const String _deactivationAction = 'com.example.betstop_kenya.DEACTIVATION_REQUESTED';
  
  static final DeviceAdminService _instance = DeviceAdminService._internal();
  factory DeviceAdminService() => _instance;
  DeviceAdminService._internal();
  
  final _apiService = ApiService();
  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
  
  Function()? onDeactivationRequested;
  bool _initialized = false;
  bool _isListening = false;
  
  /// Check if device admin is currently active
  Future<bool> isAdminActive() async {
    try {
      final result = await _channel.invokeMethod<bool>('isAdminActive');
      return result ?? false;
    } catch (e) {
      debugPrint('Error checking device admin status: $e');
      return false;
    }
  }
  
  /// Request device admin permission from user
  Future<bool> requestAdminPermission() async {
    try {
      final result = await _channel.invokeMethod<bool>('requestAdminPermission');
      return result ?? false;
    } catch (e) {
      debugPrint('Error requesting device admin permission: $e');
      return false;
    }
  }
  
  /// Remove device admin (only after 24-hour cooldown)
  Future<bool> removeAdmin() async {
    try {
      final result = await _channel.invokeMethod<bool>('removeAdmin');
      return result ?? false;
    } catch (e) {
      debugPrint('Error removing device admin: $e');
      return false;
    }
  }
  
  /// Start listening for deactivation requests from native Android
  void startDeactivationListener() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onDeactivationRequested') {
        await _handleDeactivationRequest();
      }
    });
    _isListening = true;
  }
  
  /// Stop listening for deactivation requests
  void stopDeactivationListener() {
    _channel.setMethodCallHandler(null);
    _isListening = false;
  }
  
  /// Handle deactivation request from Android
  Future<void> _handleDeactivationRequest() async {
    try {
      final token = await _apiService.getToken();
      if (token == null) return;
      
      final result = await _apiService.post(
        '/api/device-admin/deactivate',
        {},
        token: token,
      );
      
      debugPrint('Deactivation request logged: $result');
      
      // Schedule 24-hour notification
      await _scheduleFollowUpNotification();
      
      // Re-register device admin immediately
      await _reRegisterAdmin();
      
      // Notify UI to show warning screen
      onDeactivationRequested?.call();
    } catch (e) {
      debugPrint('Error handling deactivation request: $e');
    }
  }
  
  /// Re-register device admin after deactivation attempt
  Future<void> _reRegisterAdmin() async {
    try {
      await _channel.invokeMethod('reRegisterAdmin');
      debugPrint('Device admin re-registered');
    } catch (e) {
      debugPrint('Error re-registering device admin: $e');
    }
  }
  
  /// Schedule follow-up notification for 24 hours later
  Future<void> _scheduleFollowUpNotification() async {
    try {
      // Initialize timezone if not already done
      if (!_initialized) {
        tz_data.initializeTimeZones();
        _initialized = true;
      }

      const AndroidInitializationSettings initializationSettingsAndroid =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      const InitializationSettings initializationSettings =
          InitializationSettings(android: initializationSettingsAndroid);
      await _notifications.initialize(initializationSettings);

      const AndroidNotificationDetails androidPlatformChannelSpecifics =
          AndroidNotificationDetails(
        'betstop_deactivation',
        'BetStop Deactivation',
        channelDescription: 'Notifications for BetStop deactivation requests',
        importance: Importance.high,
        priority: Priority.high,
      );
      const NotificationDetails platformChannelSpecifics =
          NotificationDetails(android: androidPlatformChannelSpecifics);

      // Schedule notification for 24 hours from now
      await _notifications.zonedSchedule(
        0,
        'Still want to leave BetStop?',
        'You asked to leave BetStop yesterday. Tap to confirm if you still want to remove it.',
        tz.TZDateTime.now(tz.local).add(const Duration(hours: 24)),
        platformChannelSpecifics,
        androidAllowWhileIdle: true,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );

      debugPrint('24-hour follow-up notification scheduled');
    } catch (e) {
      debugPrint('Error scheduling notification: $e');
    }
  }
  
  /// Check deactivation status from server
  Future<Map<String, dynamic>> checkDeactivationStatus() async {
    try {
      final token = await _apiService.getToken();
      if (token == null) {
        return {'has_pending_request': false, 'can_remove': false};
      }
      
      final result = await _apiService.get(
        '/api/device-admin/status',
        token: token,
      );
      
      return result;
    } catch (e) {
      debugPrint('Error checking deactivation status: $e');
      return {'has_pending_request': false, 'can_remove': false};
    }
  }
  
  /// Confirm deactivation (after 24-hour cooldown)
  Future<Map<String, dynamic>> confirmDeactivation() async {
    try {
      final token = await _apiService.getToken();
      if (token == null) {
        throw Exception('No token found');
      }
      
      final result = await _apiService.post(
        '/api/device-admin/confirm',
        {},
        token: token,
      );
      
      return result;
    } catch (e) {
      debugPrint('Error confirming deactivation: $e');
      throw e;
    }
  }
  
  void dispose() {
    stopDeactivationListener();
  }
}
