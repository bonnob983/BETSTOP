import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  static const String baseUrl = 'https://betstop-production.up.railway.app';

  Future<Map<String, dynamic>> register({
    required String phone,
    required String name,
    required String guardianName,
    required String guardianPhone,
    required String guardianPin,
    required int coolingHours,
    required String letterToSelf,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/auth/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'phone': phone,
        'name': name,
        'guardian_name': guardianName,
        'guardian_phone': guardianPhone,
        'guardian_pin': guardianPin,
        'cooling_hours': coolingHours,
        'letter_to_self': letterToSelf,
      }),
    );
    if (response.statusCode == 201) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Registration failed: ${response.body}');
    }
  }

  Future<Map<String, dynamic>> getDashboard(String token) async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/user/dashboard'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to fetch dashboard: ${response.body}');
    }
  }

  Future<List<dynamic>> getRecentDetections(String token) async {
    return [];
  }

  Future<Map<String, dynamic>> reportSmsDetection({
    required String token,
    required String paybill,
    required double amountKes,
    required String smsText,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/detections/sms'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'paybill': paybill,
        'amount_kes': amountKes,
        'sms_text': smsText,
      }),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to report SMS detection: ${response.body}');
    }
  }

  Future<List<dynamic>> getPaybills() async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/paybills'),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to fetch paybills: ${response.body}');
    }
  }

  Future<void> cachePaybills(List<dynamic> paybills) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('cached_paybills', jsonEncode(paybills));
    await prefs.setString('paybills_last_sync', DateTime.now().toIso8601String());
  }

  Future<List<dynamic>> getCachedPaybills() async {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString('cached_paybills');
    if (cached != null) {
      return jsonDecode(cached);
    }
    return [];
  }

  Future<bool> shouldSyncPaybills() async {
    final prefs = await SharedPreferences.getInstance();
    final lastSync = prefs.getString('paybills_last_sync');
    if (lastSync == null) return true;
    final lastSyncDate = DateTime.parse(lastSync);
    final now = DateTime.now();
    return now.difference(lastSyncDate).inHours >= 24;
  }

  Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> body, {
    String? token,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl$path'),
      headers: {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      },
      body: jsonEncode(body),
    );
    if (response.statusCode == 200 || response.statusCode == 201) {
      return jsonDecode(response.body);
    } else {
      throw Exception('POST request failed: ${response.body}');
    }
  }

  Future<Map<String, dynamic>> get(
    String path, {
    String? token,
  }) async {
    final response = await http.get(
      Uri.parse('$baseUrl$path'),
      headers: {
        if (token != null) 'Authorization': 'Bearer $token',
      },
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('GET request failed: ${response.body}');
    }
  }

  Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('jwt_token');
  }
}