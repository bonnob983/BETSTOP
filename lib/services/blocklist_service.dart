import 'package:supabase_flutter/supabase_flutter.dart';

/// Blocklist Service
/// 
/// Fetches blocked domains and apps from Supabase
/// Only returns entries where is_active=true
class BlocklistService {
  final SupabaseClient _supabase;
  
  BlocklistService(this._supabase);
  
  /// Fetch blocked domains from Supabase
  /// Only returns domains where is_active=true
  Future<List<String>> fetchBlockedDomains() async {
    try {
      final response = await _supabase
          .from('blocked_domains')
          .select('domain')
          .eq('is_active', true);
      
      final domains = <String>[];
      for (final row in response as List) {
        final domain = row['domain'] as String?;
        if (domain != null && domain.isNotEmpty) {
          domains.add(domain.toLowerCase());
        }
      }
      
      return domains;
    } catch (e) {
      throw Exception('Failed to fetch blocked domains: $e');
    }
  }
  
  /// Fetch blocked apps from Supabase
  /// Only returns apps where is_active=true
  Future<List<String>> fetchBlockedApps() async {
    try {
      final response = await _supabase
          .from('blocked_apps')
          .select('package_name')
          .eq('is_active', true);
      
      final apps = <String>[];
      for (final row in response as List) {
        final packageName = row['package_name'] as String?;
        if (packageName != null && packageName.isNotEmpty) {
          apps.add(packageName);
        }
      }
      
      return apps;
    } catch (e) {
      throw Exception('Failed to fetch blocked apps: $e');
    }
  }
  
  /// Add a new domain to the blocklist
  /// Defaults to pending_review=true and is_active=false
  /// Returns the created record
  Future<Map<String, dynamic>> addDomain({
    required String domain,
    required String addedBy,
  }) async {
    try {
      final response = await _supabase.from('blocked_domains').insert({
        'domain': domain.toLowerCase(),
        'is_active': false, // Not active until reviewed
        'pending_review': true, // Requires manual review
        'added_by': addedBy,
      }).select();
      
      return response.first as Map<String, dynamic>;
    } catch (e) {
      throw Exception('Failed to add domain: $e');
    }
  }
  
  /// Add a new app to the blocklist
  /// Defaults to pending_review=true and is_active=false
  /// Returns the created record
  Future<Map<String, dynamic>> addApp({
    required String packageName,
    required String appName,
    required String addedBy,
  }) async {
    try {
      final response = await _supabase.from('blocked_apps').insert({
        'package_name': packageName,
        'app_name': appName,
        'is_active': false, // Not active until reviewed
        'pending_review': true, // Requires manual review
        'added_by': addedBy,
      }).select();
      
      return response.first as Map<String, dynamic>;
    } catch (e) {
      throw Exception('Failed to add app: $e');
    }
  }
}
