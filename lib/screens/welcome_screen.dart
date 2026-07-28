import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:betstop_kenya/screens/onboarding_screen.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B1613),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 40),
              
              // Icon in rounded square
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: const Color(0xFF12211D),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(
                  Icons.psychology_outlined,
                  size: 64,
                  color: Color(0xFF2BC08E),
                ),
              ),
              
              const SizedBox(height: 32),
              
              // Headline
              Text(
                'Take back control',
                style: GoogleFonts.fraunces(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFFEAF3EF),
                ),
                textAlign: TextAlign.center,
              ),
              
              const SizedBox(height: 12),
              
              // Subtext
              const Text(
                'Track your spending, set limits, and get support when you need it most.',
                style: TextStyle(
                  fontSize: 16,
                  color: Color(0xFF8FA69D),
                ),
                textAlign: TextAlign.center,
              ),
              
              const SizedBox(height: 48),
              
              // Primary button
              ElevatedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const OnboardingScreen(),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2BC08E),
                  foregroundColor: const Color(0xFF0B1613),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Get started',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              
              const SizedBox(height: 16),
              
              // Secondary link
              TextButton(
                onPressed: () {
                  // TODO: Navigate to login screen when implemented
                },
                child: const Text(
                  'Already have an account? Log in',
                  style: TextStyle(
                    fontSize: 14,
                    color: Color(0xFF8FA69D),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
