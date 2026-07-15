import 'dart:async';
import 'package:another_telephony/telephony.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:betstop_kenya/services/api_service.dart';

@pragma('vm:entry-point')
void onBackgroundMessage(SmsMessage message) {
  // Background SMS handler - called when app is in background
  // Note: Full SMS parsing logic requires isolate-safe storage access
  // For now, log the message. When app comes to foreground,
  // the foreground handler will process any missed messages.
  debugPrint('Background SMS received: ${message.address} - ${message.body}');
}

class SmsService {
  static final SmsService _instance = SmsService._internal();
  factory SmsService() => _instance;
  SmsService._internal();

  final Telephony telephony = Telephony.instance;
  final _storage = const FlutterSecureStorage();
  final _apiService = ApiService();
  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  List<dynamic> _cachedPaybills = [];
  Timer? _syncTimer;
  Timer? _retryTimer;

  Future<void> initialize() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings initializationSettings =
        InitializationSettings(android: initializationSettingsAndroid);
    await _notifications.initialize(initializationSettings);

    _cachedPaybills = await _apiService.getCachedPaybills();

    if (await _apiService.shouldSyncPaybills()) {
      await _syncPaybills();
    }

    _syncTimer = Timer.periodic(
      const Duration(hours: 24),
      (_) => _syncPaybills(),
    );

    bool? permissionsGranted = await telephony.requestPhoneAndSmsPermissions;
    if (permissionsGranted ?? false) {
      telephony.listenIncomingSms(
        onNewMessage: (SmsMessage message) {
          _handleIncomingSms(message.address ?? '', message.body ?? '');
        },
        onBackgroundMessage: onBackgroundMessage,
        listenInBackground: true,
      );
    }
  }

  Future<void> _syncPaybills() async {
    try {
      final paybills = await _apiService.getPaybills();
      await _apiService.cachePaybills(paybills);
      _cachedPaybills = paybills;
    } catch (e) {
      print('Failed sync: $e');
    }
  }

  void _handleIncomingSms(String sender, String body) {
    final senderUpper = sender.toUpperCase();
    if (senderUpper.contains('MPESA') ||
        senderUpper.contains('M-PESA')) {
      _parseMpesaSms(body);
    }
  }

  void _parseMpesaSms(String smsBody) {
    // Extract transaction ID (alphanumeric code at start, e.g., "QGH7XXXXXX")
    final transactionIdRegex = RegExp(r'^([A-Z0-9]{10})\s', caseSensitive: false);
    final transactionMatch = transactionIdRegex.firstMatch(smsBody);
    final transactionId = transactionMatch?.group(1);
    
    if (transactionId == null) {
      print('No transaction ID found in SMS');
      return;
    }

    // Extract amount (Ksh with optional space)
    final amountRegex = RegExp(r'Ksh\s?([\d,]+\.?\d*)', caseSensitive: false);
    final amountMatch = amountRegex.firstMatch(smsBody);
    if (amountMatch == null) return;

    final amount = double.tryParse(
      amountMatch.group(1)!.replaceAll(',', ''),
    );
    if (amount == null) return;

    // Extract account number from "for account X" pattern
    // NOTE: This assumes paybill format. Buy-goods transactions may use different wording
    // (e.g., "for till number" or "to merchant"). Real SMS samples needed to validate.
    final accountRegex = RegExp(r'for account\s+(\d{6,})', caseSensitive: false);
    final accountMatch = accountRegex.firstMatch(smsBody);
    if (accountMatch == null) {
      print('No account number found in "for account X" pattern - may be buy-goods format');
      return;
    }

    final accountNumber = accountMatch.group(1)!;

    dynamic matchingPaybill;
    for (final pb in _cachedPaybills) {
      if (pb['paybill'] == accountNumber) {
        matchingPaybill = pb;
        break;
      }
    }

    if (matchingPaybill != null) {
      _reportDetection(
        accountNumber,
        amount,
        matchingPaybill['site_name'],
        smsBody,
        transactionId,
      );
    }
  }

  Future<void> _reportDetection(
    String paybill,
    double amount,
    String siteName,
    String smsText,
    String transactionId,
  ) async {
    // Check if transaction ID was already processed (deduplication)
    final alreadyProcessed = await _storage.read(key: 'txn_$transactionId');
    if (alreadyProcessed != null) {
      print('Transaction $transactionId already processed, skipping');
      return;
    }

    try {
      final token = await _storage.read(key: 'jwt_token');
      if (token != null) {
        await _apiService.reportSmsDetection(
          token: token,
          paybill: paybill,
          amountKes: amount,
          smsText: smsText,
        );
        // Mark transaction as processed after successful report
        await _storage.write(key: 'txn_$transactionId', value: DateTime.now().toIso8601String());
        await _showNotification(siteName, amount);
      }
    } catch (e) {
      print('Failed to report detection: $e');
      // Queue for retry
      await _queuePendingDetection(
        paybill: paybill,
        amount: amount,
        siteName: siteName,
        smsText: smsText,
        transactionId: transactionId,
      );
    }
  }

  Future<void> _showNotification(String site, double amount) async {
    const AndroidNotificationDetails android =
        AndroidNotificationDetails(
      'betstop_detections',
      'BetStop Detections',
      channelDescription: 'Gambling alerts',
      importance: Importance.high,
      priority: Priority.high,
    );
    const NotificationDetails details =
        NotificationDetails(android: android);
    await _notifications.show(
      0,
      'BetStop Detection',
      'Payment to $site detected',
      details,
    );
  }

  Future<void> _queuePendingDetection({
    required String paybill,
    required double amount,
    required String siteName,
    required String smsText,
    required String transactionId,
  }) async {
    final pending = await _storage.read(key: 'pending_detections');
    List<Map<String, dynamic>> queue = [];
    if (pending != null) {
      try {
        queue = List<Map<String, dynamic>>.from(
          (await _storage.read(key: 'pending_detections') as String)
              .split('|')
              .where((s) => s.isNotEmpty)
              .map((s) => Map<String, dynamic>.from(
                    s.split(',').map((e) => e.split(':')).fold(
                      <String, dynamic>{},
                      (map, pair) => {
                        ...map,
                        if (pair.length == 2) pair[0]: pair[1]
                      },
                    ),
                  )),
        );
      } catch (e) {
        print('Failed to parse pending queue: $e');
        queue = [];
      }
    }

    queue.add({
      'paybill': paybill,
      'amount': amount.toString(),
      'siteName': siteName,
      'smsText': smsText,
      'transactionId': transactionId,
      'timestamp': DateTime.now().toIso8601String(),
    });

    final queueString = queue
        .map((e) => 'paybill:${e['paybill']},amount:${e['amount']},siteName:${e['siteName']},smsText:${e['smsText']},transactionId:${e['transactionId']},timestamp:${e['timestamp']}')
        .join('|');
    await _storage.write(key: 'pending_detections', value: queueString);

    // Start retry timer if not already running
    if (_retryTimer == null) {
      _retryTimer = Timer.periodic(
        const Duration(minutes: 15),
        (_) => _flushPendingDetections(),
      );
    }
  }

  Future<void> _flushPendingDetections() async {
    final pending = await _storage.read(key: 'pending_detections');
    if (pending == null || pending.isEmpty) {
      _retryTimer?.cancel();
      _retryTimer = null;
      return;
    }

    try {
      final token = await _storage.read(key: 'jwt_token');
      if (token == null) return;

      List<Map<String, dynamic>> queue = [];
      final entries = pending.split('|').where((s) => s.isNotEmpty);
      
      for (final entry in entries) {
        try {
          final parts = entry.split(',').map((e) => e.split(':'));
          final detection = <String, dynamic>{};
          for (final pair in parts) {
            if (pair.length == 2) {
              detection[pair[0]] = pair[1];
            }
          }

          await _apiService.reportSmsDetection(
            token: token,
            paybill: detection['paybill'] as String,
            amountKes: double.tryParse(detection['amount'] as String) ?? 0.0,
            smsText: detection['smsText'] as String,
          );
          
          // Mark transaction as processed
          await _storage.write(
            key: 'txn_${detection['transactionId']}',
            value: DateTime.now().toIso8601String(),
          );
        } catch (e) {
          print('Failed to retry detection: $e');
          // Re-add the failed entry as a Map to the queue
          final parts = entry.split(',').map((e) => e.split(':'));
          final detection = <String, dynamic>{};
          for (final pair in parts) {
            if (pair.length == 2) {
              detection[pair[0]] = pair[1];
            }
          }
          queue.add(detection);
        }
      }

      // Update queue with remaining failed items
      final queueString = queue.join('|');
      if (queueString.isEmpty) {
        await _storage.delete(key: 'pending_detections');
        _retryTimer?.cancel();
        _retryTimer = null;
      } else {
        await _storage.write(key: 'pending_detections', value: queueString);
      }
    } catch (e) {
      print('Failed to flush pending detections: $e');
    }
  }

  void dispose() {
    _syncTimer?.cancel();
    _retryTimer?.cancel();
  }
}