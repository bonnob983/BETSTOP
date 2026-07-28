import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:betstop_kenya/services/device_admin_service.dart';

/// Full-screen warning shown when user attempts to deactivate device admin
class DeactivationWarningScreen extends StatefulWidget {
  const DeactivationWarningScreen({super.key});

  @override
  State<DeactivationWarningScreen> createState() => _DeactivationWarningScreenState();
}

class _DeactivationWarningScreenState extends State<DeactivationWarningScreen> {
  final _storage = const FlutterSecureStorage();
  final _deviceAdminService = DeviceAdminService();
  
  Map<String, dynamic>? _deactivationStatus;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadDeactivationStatus();
  }

  Future<void> _loadDeactivationStatus() async {
    try {
      final status = await _deviceAdminService.checkDeactivationStatus();
      setState(() {
        _deactivationStatus = status;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _confirmDeactivation() async {
    try {
      final result = await _deviceAdminService.confirmDeactivation();
      
      if (result['success'] == true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Deactivation confirmed. Go to Settings > Security > Device Admin Apps to remove BetStop.'),
              duration: Duration(seconds: 5),
            ),
          );
          Navigator.pop(context);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to confirm deactivation: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final hasPendingRequest = _deactivationStatus?['has_pending_request'] ?? false;
    final canRemove = _deactivationStatus?['can_remove'] ?? false;
    final hoursPassed = _deactivationStatus?['hours_passed'] ?? 0.0;
    final commitmentEndDate = _deactivationStatus?['commitment_end_date'];

    return Scaffold(
      backgroundColor: const Color(0xFF0B1613),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                size: 80,
                color: Colors.orange,
              ),
              const SizedBox(height: 24),
              const Text(
                'Deactivation Requested',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFEAF3EF),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                hasPendingRequest
                    ? 'You requested to deactivate BetStop ${hoursPassed.toStringAsFixed(1)} hours ago.'
                    : 'Your deactivation request has been logged.',
                style: const TextStyle(
                  fontSize: 16,
                  color: Color(0xFF8FA69D),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              if (commitmentEndDate != null)
                Text(
                  'Your commitment ends on: ${_formatDate(commitmentEndDate)}',
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF8FA69D),
                  ),
                  textAlign: TextAlign.center,
                ),
              const SizedBox(height: 32),
              if (!canRemove)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF12211D),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFF2BC08E)),
                  ),
                  child: Column(
                    children: [
                      const Text(
                        '24-Hour Cooling Period',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                          color: Color(0xFFEAF3EF),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'You can fully remove BetStop in ${(24 - hoursPassed).toStringAsFixed(1)} hours if you still want to.',
                        style: const TextStyle(
                          fontSize: 14,
                          color: Color(0xFF8FA69D),
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'We\'ll notify you when the 24 hours are up.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF8FA69D),
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 32),
              if (canRemove)
                ElevatedButton(
                  onPressed: _confirmDeactivation,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2BC08E),
                    foregroundColor: const Color(0xFF0B1613),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Remove BetStop Protection',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                )
              else
                ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2BC08E),
                    foregroundColor: const Color(0xFF0B1613),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Keep BetStop Active',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(String dateString) {
    try {
      final date = DateTime.parse(dateString);
      return '${date.day}/${date.month}/${date.year}';
    } catch (e) {
      return dateString;
    }
  }
}
