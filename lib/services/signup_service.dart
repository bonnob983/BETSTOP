import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:betstop_kenya/models/signup_flow_state.dart';

class SignupService {
  final supabase = Supabase.instance.client;

  Future<bool> submitSignup(SignupFlowState state) async {
    try {
      // Step 1: Insert into users table
      final userResponse = await supabase
          .from('users')
          .insert({
            'phone': state.phone,
            'name': state.name,
            'streak_days': 0,
            'total_saved_kes': 0,
          })
          .select()
          .single();

      final user = userResponse;
      final userId = user['id'];

      // Step 2: Insert into guardians table
      final guardianResponse = await supabase.from('guardians').insert({
        'user_id': userId,
        'name': state.guardianName,
        'phone': state.guardianPhone,
        'pin_hash': _generateDefaultPinHash(),
      });

      if (guardianResponse.error != null) throw guardianResponse.error!;

      // Step 3: Calculate commitment end time
      DateTime commitmentEnd;
      String commitmentType;
      int? coolingHours;

      if (state.exclusionType == ExclusionType.full) {
        commitmentEnd = DateTime.now().add(const Duration(days: 365));
        commitmentType = 'full_exclusion';
        coolingHours = 365 * 24;
      } else {
        coolingHours = _parseDurationToHours(state.partialDuration!);
        commitmentEnd = DateTime.now().add(Duration(hours: coolingHours));
        commitmentType = 'responsible_gambling';
      }

      // Step 4: Upload ID card to Supabase Storage (for full exclusion)
      String? idCardUrl;
      if (state.exclusionType == ExclusionType.full && state.idCardFile != null) {
        idCardUrl = await _uploadIdCard(state.idCardFile!, userId);
      }

      // Step 5: Insert into commitments table
      final commitmentResponse = await supabase.from('commitments').insert({
        'user_id': userId,
        'cooling_hours': coolingHours,
        'commitment_end': commitmentEnd.toIso8601String(),
        'letter_to_self': state.commitmentLetter,
        'is_active': true,
        'email': state.email,
        'id_card_url': idCardUrl,
      });

      if (commitmentResponse.error != null) throw commitmentResponse.error!;

      return true;
    } catch (e) {
      print('Signup error: $e');
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

  String _generateDefaultPinHash() {
    return 'default_pin_hash_placeholder';
  }

  Future<String?> _uploadIdCard(String filePath, String userId) async {
    try {
      final file = File(filePath);
      final fileName = 'id_card_${userId}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      
      // Upload to Supabase Storage
      // Note: You need to create a bucket named 'id_cards' in Supabase Storage
      // and set appropriate permissions
      final response = await supabase.storage
          .from('id_cards')
          .upload(fileName, file);
      
      if (response == null) {
        print('Failed to upload ID card');
        return null;
      }

      // Get public URL
      final urlResponse = supabase.storage
          .from('id_cards')
          .getPublicUrl(fileName);
      
      return urlResponse;
    } catch (e) {
      print('Error uploading ID card: $e');
      return null;
    }
  }
}
