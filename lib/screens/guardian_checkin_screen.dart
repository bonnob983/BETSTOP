import 'package:flutter/material.dart';

class GuardianCheckinScreen extends StatefulWidget {
  final String guardianName;
  final String guardianPhone;
  final String appName;

  const GuardianCheckinScreen({
    super.key,
    required this.guardianName,
    required this.guardianPhone,
    required this.appName,
  });

  @override
  State<GuardianCheckinScreen> createState() => _GuardianCheckinScreenState();
}

class _GuardianCheckinScreenState extends State<GuardianCheckinScreen> {
  final _pinController = TextEditingController();

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFD32F2F), // Red danger tone
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Icon
              const Icon(
                Icons.shield,
                size: 80,
                color: Colors.white,
              ),
              
              const SizedBox(height: 24),
              
              // Headline
              const Text(
                "Let's bring in your guardian",
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
                textAlign: TextAlign.center,
              ),
              
              const SizedBox(height: 16),
              
              // Subtext naming guardian and explaining PIN process
              Text(
                'Your guardian ${widget.guardianName} will receive a PIN. Enter it to continue.',
                style: const TextStyle(
                  fontSize: 16,
                  color: Colors.white,
                ),
                textAlign: TextAlign.center,
              ),
              
              const SizedBox(height: 32),
              
              // PIN input field
              TextField(
                controller: _pinController,
                keyboardType: TextInputType.number,
                maxLength: 4,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.2),
                  hintText: 'PIN',
                  hintStyle: const TextStyle(color: Colors.white70),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                  counterText: '',
                ),
              ),
              
              const SizedBox(height: 32),
              
              // Primary button - Text guardian for PIN
              ElevatedButton(
                onPressed: () {
                  // TODO: Send SMS to guardian with PIN
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('PIN sent to guardian'),
                      backgroundColor: Colors.white,
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFFD32F2F),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: Text(
                  'Text ${widget.guardianName} for the PIN',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              
              const SizedBox(height: 16),
              
              // Secondary muted text - go back to safety
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                },
                child: const Text(
                  'Go back to safety instead',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white70,
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
