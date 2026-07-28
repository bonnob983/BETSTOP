import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:betstop_kenya/models/signup_flow_state.dart';

class FullExclusionScreen extends StatefulWidget {
  const FullExclusionScreen({super.key});

  @override
  State<FullExclusionScreen> createState() => _FullExclusionScreenState();
}

class _FullExclusionScreenState extends State<FullExclusionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _letterController = TextEditingController();
  XFile? _idCardImage;
  final ImagePicker _picker = ImagePicker();
  bool _isSubmitting = false;

  final _emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');

  @override
  void dispose() {
    _emailController.dispose();
    _letterController.dispose();
    super.dispose();
  }

  String? _validateEmail(String? value) {
    if (value == null || value.isEmpty) {
      return 'Email is required';
    }
    if (!_emailRegex.hasMatch(value)) {
      return 'Enter a valid email address';
    }
    return null;
  }

  String? _validateLetter(String? value) {
    if (value == null || value.isEmpty) {
      return 'Letter is required';
    }
    if (value.length < 20) {
      return 'Letter must be at least 20 characters';
    }
    return null;
  }

  Future<void> _pickIdCard() async {
    final XFile? image = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
    );

    if (image != null) {
      setState(() {
        _idCardImage = image;
        final state = context.read<SignupFlowState>();
        state.updateIdCardFile(image.path);
      });
    }
  }

  void _handleNext() {
    if (_formKey.currentState!.validate() && _idCardImage != null) {
      final state = context.read<SignupFlowState>();
      state.updateEmail(_emailController.text);
      state.updateExclusionLetterFile(_letterController.text);
      
      Navigator.pushNamed(context, '/confirmation');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Full Exclusion'),
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
                  'Complete your registration',
                  style: GoogleFonts.fraunces(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF2BC08E),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'We need a few more details for full exclusion.',
                  style: TextStyle(
                    fontSize: 16,
                    color: Color(0xFF8FA69D),
                  ),
                ),
                const SizedBox(height: 32),
                TextFormField(
                  controller: _emailController,
                  decoration: const InputDecoration(
                    labelText: 'Email Address',
                    hintText: 'your.email@example.com',
                  ),
                  keyboardType: TextInputType.emailAddress,
                  validator: _validateEmail,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _letterController,
                  decoration: const InputDecoration(
                    labelText: 'Letter requesting full exclusion',
                    hintText: 'Write a letter explaining why you want full exclusion...',
                  ),
                  maxLines: 5,
                  validator: _validateLetter,
                ),
                const SizedBox(height: 16),
                _buildIdCardUpload(),
                const SizedBox(height: 32),
                ElevatedButton(
                  onPressed: (_formKey.currentState?.validate() ?? false) && _idCardImage != null
                      ? _handleNext
                      : null,
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

  Widget _buildIdCardUpload() {
    return Card(
      color: const Color(0xFF12211D),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: InkWell(
        onTap: _pickIdCard,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _idCardImage != null ? const Color(0xFF2BC08E) : const Color(0xFF0B1613),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  _idCardImage != null ? Icons.check_circle : Icons.add_a_photo,
                  color: _idCardImage != null ? const Color(0xFF0B1613) : const Color(0xFF2BC08E),
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Upload ID Card',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFEAF3EF),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _idCardImage != null ? 'Image selected' : 'Tap to upload your ID card',
                      style: TextStyle(
                        fontSize: 14,
                        color: _idCardImage != null ? const Color(0xFF2BC08E) : const Color(0xFF8FA69D),
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right,
                color: Color(0xFF8FA69D),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
