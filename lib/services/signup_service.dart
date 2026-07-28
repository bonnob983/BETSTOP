import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:betstop_kenya/models/signup_flow_state.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SignupService {
  final storage = const FlutterSecureStorage();
  static const String _backendUrl = 'https://betstop-production-033f.up.railway.app';

  Future<bool> submitSignup(SignupFlowState state) async {
    try {
      print('Starting signup for phone: ${state.phone}');
      
      // Calculate cooling hours
      int coolingHours;
      if (state.exclusionType == ExclusionType.full) {
        coolingHours = 365 * 24;
      } else {
        coolingHours = _parseDurationToHours(state.partialDuration!);
      }
      
      print('Calling Railway backend API...');
      final response = await http.post(
        Uri.parse('$_backendUrl/api/signup/complete'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'phone': state.phone,
          'name': state.name,
          'guardian_name': state.guardianName,
          'guardian_phone': state.guardianPhone,
          'guardian_pin': '1234', // Default PIN for now
          'cooling_hours': coolingHours,
          'letter_to_self': state.commitmentLetter,
          'commitment_type': state.exclusionType == ExclusionType.full ? 'full_exclusion' : 'responsible_gambling',
          'email': state.email,
          'id_card_base64': state.idCardFile, // Base64 encoded image if full exclusion
        }),
      );

      print('Response status: ${response.statusCode}');
      print('Response body: ${response.body}');

      if (response.statusCode == 201) {
        final data = jsonDecode(response.body);
        final token = data['token'];
        
        // Store JWT token
        await storage.write(key: 'jwt_token', value: token);
        print('Token stored successfully');
        
        return true;
      } else {
        print('Signup failed with status: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      print('Signup error: $e');
      print('Error type: ${e.runtimeType}');
      return false;
    }
  }

  int _parseDurationToHours(String duration) {
    switch (duration) {
      case '12h':
        return 12;
      case '24h':
        return 24;
      case '7d':
        return 24 * 7;
      case '30d':
        return 24 * 30;
      default:
        return 24;
    }
  }
}
