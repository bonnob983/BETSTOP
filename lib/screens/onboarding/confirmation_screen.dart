import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:betstop_kenya/models/signup_flow_state.dart';
import 'package:betstop_kenya/services/signup_service.dart';

class ConfirmationScreen extends StatefulWidget {
  const ConfirmationScreen({super.key});

  @override
  State<ConfirmationScreen> createState() => _ConfirmationScreenState();
}

class _ConfirmationScreenState extends State<ConfirmationScreen> {
  bool _isSubmitting = false;

  String _getCommitmentType() {
    final state = context.read<SignupFlowState>();
    if (state.exclusionType == ExclusionType.full) {
      return 'Full Exclusion';
    } else {
      return 'Responsible Gambling';
    }
  }

  String _getEndDate() {
    final state = context.read<SignupFlowState>();
    DateTime endDate;

    if (state.exclusionType == ExclusionType.full) {
      endDate = DateTime.now().add(const Duration(days: 365));
    } else if (state.partialDuration != null) {
      final hours = _parseDurationToHours(state.partialDuration!);
      endDate = DateTime.now().add(Duration(hours: hours));
    } else {
      endDate = DateTime.now();
    }

    return DateFormat('MMMM d, yyyy').format(endDate);
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

  Future<void> _handleConfirm() async {
    setState(() {
      _isSubmitting = true;
    });

    try {
      final state = context.read<SignupFlowState>();
      final success = await SignupService().submitSignup(state);

      if (mounted) {
        if (success) {
          state.reset();
          Navigator.pushNamedAndRemoveUntil(context, '/home', (route) => false);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to complete signup. Please try again.')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<SignupFlowState>();
    final commitmentType = _getCommitmentType();
    final endDate = _getEndDate();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Confirm Your Commitment'),
        backgroundColor: const Color(0xFF0B1613),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 20),
              Text(
                'Review your commitment',
                style: GoogleFonts.fraunces(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF2BC08E),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Please review your commitment before confirming. This action cannot be undone.',
                style: TextStyle(
                  fontSize: 16,
                  color: Color(0xFF8FA69D),
                ),
              ),
              const SizedBox(height: 32),
              _buildSummaryCard(
                title: 'Commitment Type',
                value: commitmentType,
                icon: Icons.shield,
              ),
              const SizedBox(height: 16),
              _buildSummaryCard(
                title: 'End Date',
                value: endDate,
                icon: Icons.calendar_today,
              ),
              const SizedBox(height: 16),
              if (state.exclusionType == ExclusionType.full)
                _buildSummaryCard(
                  title: 'Email',
                  value: state.email ?? 'Not provided',
                  icon: Icons.email,
                ),
              const SizedBox(height: 32),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A3A32),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: const Color(0xFF2BC08E),
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.info_outline,
                      color: Color(0xFF2BC08E),
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        state.exclusionType == ExclusionType.full
                            ? 'Full exclusion lasts for 1 year. You will not be able to uninstall the app during this period.'
                            : 'Your commitment will be enforced until the end date.',
                        style: const TextStyle(
                          fontSize: 14,
                          color: Color(0xFFEAF3EF),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: _isSubmitting ? null : _handleConfirm,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: const Color(0xFF2BC08E),
                ),
                child: _isSubmitting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF0B1613)),
                        ),
                      )
                    : const Text(
                        'Confirm & Start',
                        style: TextStyle(fontSize: 18, color: Color(0xFF0B1613)),
                      ),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                },
                child: const Text(
                  'Go back',
                  style: TextStyle(color: Color(0xFF8FA69D)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryCard({
    required String title,
    required String value,
    required IconData icon,
  }) {
    return Card(
      color: const Color(0xFF12211D),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF0B1613),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                color: const Color(0xFF2BC08E),
                size: 24,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Color(0xFF8FA69D),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFEAF3EF),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
