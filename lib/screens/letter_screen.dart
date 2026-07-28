import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:betstop_kenya/services/api_service.dart';

class LetterScreen extends StatelessWidget {
  final String letterToSelf;
  final String siteName;
  
  const LetterScreen({
    super.key,
    required this.letterToSelf,
    required this.siteName,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B1613),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.block,
                          size: 64,
                          color: Color(0xFF2BC08E),
                        ),
                        const SizedBox(height: 24),
                        const Text(
                          'Gambling Detected',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF2BC08E),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Payment to $siteName detected',
                          style: const TextStyle(
                            fontSize: 16,
                            color: Color(0xFF8FA69D),
                          ),
                        ),
                        const SizedBox(height: 40),
                        Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: const Color(0xFF12211D),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFF2BC08E), width: 2),
                          ),
                          child: Text(
                            letterToSelf,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 20,
                              fontStyle: FontStyle.italic,
                              color: Color(0xFFEAF3EF),
                              height: 1.5,
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        const Text(
                          'Your guardian has been notified.',
                          style: TextStyle(
                            fontSize: 16,
                            color: Color(0xFF8FA69D),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => _showHelpDialog(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2BC08E),
                    foregroundColor: const Color(0xFF0B1613),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'I Need Help',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showHelpDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF12211D),
        title: const Text(
          'Get Help',
          style: TextStyle(color: Color(0xFF2BC08E)),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text(
              'Kenya Gambling Helpline',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            SizedBox(height: 8),
            Text(
              '0800 723 253',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF2BC08E)),
            ),
            SizedBox(height: 16),
            Text(
              'Free, confidential support available 24/7.',
              style: TextStyle(color: Color(0xFF8FA69D)),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}
