import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:betstop_kenya/models/signup_flow_state.dart';

class ExclusionTypeScreen extends StatefulWidget {
  const ExclusionTypeScreen({super.key});

  @override
  State<ExclusionTypeScreen> createState() => _ExclusionTypeScreenState();
}

class _ExclusionTypeScreenState extends State<ExclusionTypeScreen> {
  ExclusionType? _selectedType;

  void _handleNext() {
    if (_selectedType != null) {
      final state = context.read<SignupFlowState>();
      state.updateExclusionType(_selectedType!);
      
      if (_selectedType == ExclusionType.full) {
        Navigator.pushNamed(context, '/full_exclusion');
      } else {
        Navigator.pushNamed(context, '/partial_exclusion');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Choose Your Path'),
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
                'Choose your commitment path',
                style: GoogleFonts.fraunces(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF2BC08E),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Select the level of protection that works for you.',
                style: TextStyle(
                  fontSize: 16,
                  color: Color(0xFF8FA69D),
                ),
              ),
              const SizedBox(height: 32),
              _buildExclusionCard(
                title: 'Full Exclusion',
                description: 'Blocks all gambling access for a full year. Strongest protection.',
                icon: Icons.security,
                isSelected: _selectedType == ExclusionType.full,
                onTap: () {
                  setState(() {
                    _selectedType = ExclusionType.full;
                  });
                },
              ),
              const SizedBox(height: 16),
              _buildExclusionCard(
                title: 'Responsible Gambling',
                description: 'Set your own limit — urge toggle, weekly, or monthly.',
                icon: Icons.tune,
                isSelected: _selectedType == ExclusionType.partial,
                onTap: () {
                  setState(() {
                    _selectedType = ExclusionType.partial;
                  });
                },
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: _selectedType != null ? _handleNext : null,
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

  Widget _buildExclusionCard({
    required String title,
    required String description,
    required IconData icon,
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
                  icon,
                  color: isSelected ? const Color(0xFF0B1613) : const Color(0xFF2BC08E),
                  size: 32,
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
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFEAF3EF),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFF8FA69D),
                      ),
                    ),
                  ],
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
