import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:usage_stats/usage_stats.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:betstop_kenya/config/gambling_packages_unverified.dart';
import 'package:betstop_kenya/screens/blocked_app_overlay.dart';
import 'package:betstop_kenya/services/blocklist_service.dart';

// CONFIRMED gambling app package names for Kenya
class GamblingPackagesConfirmed {
  // SportPesa Kenya - CONFIRMED
  static const String sportPesa = 'com.pevans.sportpesa.ke';
  
  // Betika Kenya - LIKELY (TODO: verify via adb)
  static const String betika = 'com.app.betika.android';
  
  // Get all confirmed packages as a list
  static const List<String> all = [
    sportPesa,
    betika,
  ];
  
  // Check if a package name is a gambling app
  static bool isGamblingApp(String packageName) {
    return all.contains(packageName);
  }
}

class AppDetectionService {
  static final AppDetectionService _instance = AppDetectionService._internal();
  factory AppDetectionService() => _instance;
  AppDetectionService._internal();

  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  Timer? _pollingTimer;
  String? _lastDetectedPackage;
  DateTime? _lastDetectionTime;
  
  // Supabase blocklist service
  BlocklistService? _blocklistService;
  List<String> _blockedApps = [];
  
  // Poll every 4 seconds (within 3-5 second requirement)
  static const Duration _pollInterval = Duration(seconds: 4);

  Future<void> initialize() async {
    // Request PACKAGE_USAGE_STATS permission
    UsageStats.grantUsagePermission();
    
    // Start polling
    _startPolling();
  }
  
  /// Set the blocklist service and load blocked apps from Supabase
  Future<void> setBlocklistService(BlocklistService blocklistService) async {
    _blocklistService = blocklistService;
    await loadBlockedApps();
  }
  
  /// Load blocked apps from Supabase
  Future<void> loadBlockedApps() async {
    if (_blocklistService == null) {
      debugPrint('Blocklist service not set');
      return;
    }
    
    try {
      _blockedApps = await _blocklistService!.fetchBlockedApps();
      debugPrint('Loaded ${_blockedApps.length} blocked apps from Supabase');
    } catch (e) {
      debugPrint('Failed to load blocked apps: $e');
    }
  }

  void _startPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(_pollInterval, (_) => _checkForegroundApp());
  }

  Future<void> _checkForegroundApp() async {
    try {
      // Query usage stats for the last 5 seconds to get current foreground app
      final endTime = DateTime.now();
      final startTime = endTime.subtract(const Duration(seconds: 5));
      
      final events = await UsageStats.queryEvents(
        startTime,
        endTime,
      );

      if (events.isEmpty) return;

      // Get the most recent event (foreground app)
      final sortedEvents = events.toList()
        ..sort((a, b) {
          final aTime = int.tryParse(a.timeStamp ?? '0') ?? 0;
          final bTime = int.tryParse(b.timeStamp ?? '0') ?? 0;
          return bTime.compareTo(aTime);
        });
      
      final latestEvent = sortedEvents.first;
      final packageName = latestEvent.packageName;

      if (packageName == null) return;

      // Skip if same package detected recently (avoid spam)
      if (_lastDetectedPackage == packageName &&
          _lastDetectionTime != null &&
          DateTime.now().difference(_lastDetectionTime!).inSeconds < 10) {
        return;
      }

      // Check if it's a gambling app (from Supabase blocklist or hardcoded)
      final isBlocked = _blockedApps.contains(packageName) || 
                       GamblingPackagesConfirmed.isGamblingApp(packageName);
      
      if (isBlocked) {
        _handleGamblingAppDetected(packageName);
        _lastDetectedPackage = packageName;
        _lastDetectionTime = DateTime.now();
      } else if (GamblingPackagesUnverified.isUnverified(packageName)) {
        // Log unverified package detection for verification
        debugPrint('Unverified gambling package detected: $packageName - needs verification');
      }
    } catch (e) {
      debugPrint('Error checking foreground app: $e');
    }
  }

  Future<void> _handleGamblingAppDetected(String packageName) async {
    debugPrint('Gambling app detected: $packageName');
    
    // Get user data for the overlay
    final streakDays = await _storage.read(key: 'streak_days') ?? '0';
    final savedAmount = await _storage.read(key: 'total_saved_kes') ?? '0';
    final letterSnippet = await _storage.read(key: 'letter_to_self') ?? 
        'Your commitment letter will appear here.';
    
    // Get app name from package name
    final appName = _getAppName(packageName);
    
    // TODO: Show overlay - this requires a navigator context
    // For now, log the detection
    debugPrint('Would show overlay for $appName (streak: $streakDays, saved: KES $savedAmount)');
  }

  String _getAppName(String packageName) {
    switch (packageName) {
      case GamblingPackagesConfirmed.sportPesa:
        return 'SportPesa';
      case GamblingPackagesConfirmed.betika:
        return 'Betika';
      case GamblingPackagesUnverified.odibets:
        return 'Odibets';
      case GamblingPackagesUnverified.mozzartBet:
        return 'MozzartBet';
      default:
        return 'Unknown App';
    }
  }

  void dispose() {
    _pollingTimer?.cancel();
  }
}
