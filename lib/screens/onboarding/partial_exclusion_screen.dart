import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:betstop_kenya/models/signup_flow_state.dart';

class PartialExclusionScreen extends StatefulWidget {
  const PartialExclusionScreen({super.key});

  @override
  State<PartialExclusionScreen> createState() => _PartialExclusionScreenState();
}

class _PartialExclusionScreenState extends State<PartialExclusionScreen> {
  String? _selectedDuration;

  final List<Map<String, String>> _durationOptions = [
    {'value': '12h', 'label': '12 hours'},
    {'value': '24h', 'label': '24 hours'},
    {'value': '7d', 'label': '1 week'},
    {'value': '30d', 'label': '1 month'},
  ];

  void _handleNext() {
    if (_selectedDuration != null) {
      final state = context.read<SignupFlowState>();
      state.updatePartialDuration(_selectedDuration!);
      
      Navigator.pushNamed(context, '/confirmation');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Responsible Gambling'),
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
                'Choose your duration',
                style: GoogleFonts.fraunces(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF2BC08E),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Select how long you want to limit your gambling access.',
                style: TextStyle(
                  fontSize: 16,
                  color: Color(0xFF8FA69D),
                ),
              ),
              const SizedBox(height: 32),
              ..._durationOptions.map((option) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _buildDurationCard(
                    label: option['label']!,
                    value: option['value']!,
                    isSelected: _selectedDuration == option['value'],
                    onTap: () {
                      setState(() {
                        _selectedDuration = option['value'];
                      });
                    },
                  ),
                );
              }),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: _selectedDuration != null ? _handleNext : null,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text(
                  'Next',
                  style: TextStyle(fontSize: 18),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDurationCard({
    required String label,
    required String value,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Card(
        color: isSelected ? const Color(0xFF1A3A32) : const Color(0xFF12211D),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: isSelected ? const Color(0xFF2BC08E) : Colors.transparent,
            width: 2,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isSelected ? const Color(0xFF2BC08E) : const Color(0xFF0B1613),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.access_time,
                  color: isSelected ? const Color(0xFF0B1613) : const Color(0xFF2BC08E),
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFEAF3EF),
                  ),
                ),
              ),
              if (isSelected)
                const Icon(
                  Icons.check_circle,
                  color: Color(0xFF2BC08E),
                  size: 28,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
