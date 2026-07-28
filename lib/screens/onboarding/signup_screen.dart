import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:betstop_kenya/models/signup_flow_state.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _guardianNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _guardianPhoneController = TextEditingController();
  final _commitmentLetterController = TextEditingController();

  final _phoneRegex = RegExp(r'^(?:\+254|0)7\d{8}$');

  @override
  void dispose() {
    _nameController.dispose();
    _guardianNameController.dispose();
    _phoneController.dispose();
    _guardianPhoneController.dispose();
    _commitmentLetterController.dispose();
    super.dispose();
  }

  String? _validatePhone(String? value) {
    if (value == null || value.isEmpty) {
      return 'Phone number is required';
    }
    if (!_phoneRegex.hasMatch(value)) {
      return 'Enter a valid Kenyan phone number (e.g., 0712345678 or +254712345678)';
    }
    return null;
  }

  void _handleNext() {
    if (_formKey.currentState!.validate()) {
      final state = context.read<SignupFlowState>();
      state.updateName(_nameController.text);
      state.updateGuardianName(_guardianNameController.text);
      state.updatePhone(_phoneController.text);
      state.updateGuardianPhone(_guardianPhoneController.text);
      state.updateCommitmentLetter(_commitmentLetterController.text);
      
      Navigator.pushNamed(context, '/exclusion_type');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sign Up'),
        backgroundColor: const Color(0xFF0B1613),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 20),
                Text(
                  'Tell us about yourself',
                  style: GoogleFonts.fraunces(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF2BC08E),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'We need some information to set up your self-exclusion.',
                  style: TextStyle(
                    fontSize: 16,
                    color: Color(0xFF8FA69D),
                  ),
                ),
                const SizedBox(height: 32),
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Your Name',
                    hintText: 'Enter your full name',
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Name is required';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _guardianNameController,
                  decoration: const InputDecoration(
                    labelText: 'Guardian Name',
                    hintText: 'Enter your guardian\'s full name',
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Guardian name is required';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _phoneController,
                  decoration: const InputDecoration(
                    labelText: 'Your Phone Number',
                    hintText: '0712345678 or +254712345678',
                  ),
                  keyboardType: TextInputType.phone,
                  validator: _validatePhone,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _guardianPhoneController,
                  decoration: const InputDecoration(
                    labelText: 'Guardian Phone Number',
                    hintText: '0712345678 or +254712345678',
                  ),
                  keyboardType: TextInputType.phone,
                  validator: _validatePhone,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _commitmentLetterController,
                  decoration: const InputDecoration(
                    labelText: 'Commitment Letter',
                    hintText: 'Write a letter to yourself about why you want to stop gambling...',
                  ),
                  maxLines: 5,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Commitment letter is required';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 32),
                ElevatedButton(
                  onPressed: _handleNext,
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
      ),
    );
  }
}
