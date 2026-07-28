import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:betstop_kenya/services/api_service.dart';
import 'package:betstop_kenya/services/device_admin_service.dart';
import 'package:betstop_kenya/screens/dashboard_screen.dart';
import 'package:betstop_kenya/screens/permission_setup_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _storage = const FlutterSecureStorage();
  final _apiService = ApiService();
  final _deviceAdminService = DeviceAdminService();

  int _currentStep = 0;

  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();

  final _guardianNameController = TextEditingController();
  final _guardianPhoneController = TextEditingController();

  final _pinController = TextEditingController();
  final _confirmPinController = TextEditingController();

  final _letterController = TextEditingController();

  int _coolingHours = 24;
  bool _isLoading = false;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _guardianNameController.dispose();
    _guardianPhoneController.dispose();
    _pinController.dispose();
    _confirmPinController.dispose();
    _letterController.dispose();
    super.dispose();
  }

  Future<void> _requestSmsPermission() async {
    final status = await Permission.sms.request();

    if (status.isGranted) {
      _submitRegistration();
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('SMS permission denied'),
          ),
        );
      }
    }
  }

  Future<void> _submitRegistration() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final result = await _apiService.register(
        phone: _phoneController.text,
        name: _nameController.text,
        guardianName: _guardianNameController.text,
        guardianPhone: _guardianPhoneController.text,
        guardianPin: _pinController.text,
        coolingHours: _coolingHours,
        letterToSelf: _letterController.text,
      );

      await _storage.write(key: 'jwt_token', value: result['token']);
      await _storage.write(key: 'user_id', value: result['user_id']);

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const PermissionSetupScreen()),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Registration failed: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _nextStep() {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    
    if (_currentStep < 3) {
      setState(() => _currentStep++);
    } else {
      _showPermissionDialog();
    }
  }

  void _showPermissionDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Permissions Required'),
        content: const Text(
          'BetStop needs SMS and device admin permissions to function properly and prevent uninstallation during your commitment.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _requestPermissions();
            },
            child: const Text('Allow'),
          ),
        ],
      ),
    );
  }

  Future<void> _requestPermissions() async {
    setState(() => _isLoading = true);

    try {
      // Request SMS permission
      final smsStatus = await Permission.sms.request();
      if (!smsStatus.isGranted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('SMS permission denied')),
          );
        }
        setState(() => _isLoading = false);
        return;
      }

      // Request device admin permission
      final adminGranted = await _deviceAdminService.requestAdminPermission();
      if (!adminGranted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Device admin permission denied')),
          );
        }
        setState(() => _isLoading = false);
        return;
      }

      // Start deactivation listener
      _deviceAdminService.startDeactivationListener();

      // Submit registration
      await _submitRegistration();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Permission request failed: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 40),
                const Text(
                  'BetStop',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF2BC08E),
                  ),
                ),
                Text(
                  'Take back control',
                  style: GoogleFonts.fraunces(
                    color: const Color(0xFFA8E6CE),
                  ),
                ),

                const SizedBox(height: 30),

                Expanded(child: _buildStep()),

                Row(
                  children: [
                    if (_currentStep > 0)
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => setState(() => _currentStep--),
                          child: const Text('Back'),
                        ),
                      ),
                    if (_currentStep > 0) const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _nextStep,
                        child: _isLoading
                            ? const CircularProgressIndicator()
                            : Text(_currentStep == 3 ? 'Complete' : 'Next'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStep() {
    switch (_currentStep) {
      case 0:
        return _step1();
      case 1:
        return _step2();
      case 2:
        return _step3();
      case 3:
        return _step4();
      default:
        return const SizedBox();
    }
  }

  Widget _step1() {
    return Column(
      children: [
        TextFormField(
          controller: _nameController,
          decoration: const InputDecoration(labelText: 'Name'),
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return 'Name is required';
            }
            final trimmed = value.trim();
            if (trimmed.length < 2) {
              return 'Name must be at least 2 characters';
            }
            if (!RegExp(r"^[a-zA-Z\s'\-]+$").hasMatch(trimmed)) {
              return 'Name can only contain letters, spaces, apostrophes, and hyphens';
            }
            return null;
          },
        ),
        TextFormField(
          controller: _phoneController,
          decoration: const InputDecoration(labelText: 'Phone'),
          keyboardType: TextInputType.phone,
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return 'Phone is required';
            }
            if (!RegExp(r'^[0-9]{10,15}$').hasMatch(value.trim())) {
              return 'Phone must be 10-15 digits';
            }
            return null;
          },
        ),
      ],
    );
  }

  Widget _step2() {
    return Column(
      children: [
        TextFormField(
          controller: _guardianNameController,
          decoration: const InputDecoration(labelText: 'Guardian Name'),
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return 'Guardian name is required';
            }
            final trimmed = value.trim();
            if (trimmed.length < 2) {
              return 'Name must be at least 2 characters';
            }
            if (!RegExp(r"^[a-zA-Z\s'\-]+$").hasMatch(trimmed)) {
              return 'Name can only contain letters, spaces, apostrophes, and hyphens';
            }
            return null;
          },
        ),
        TextFormField(
          controller: _guardianPhoneController,
          decoration: const InputDecoration(labelText: 'Guardian Phone'),
          keyboardType: TextInputType.phone,
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return 'Guardian phone is required';
            }
            if (!RegExp(r'^[0-9]{10,15}$').hasMatch(value.trim())) {
              return 'Phone must be 10-15 digits';
            }
            return null;
          },
        ),
      ],
    );
  }

  Widget _step3() {
    return Column(
      children: [
        TextFormField(
          controller: _pinController,
          decoration: const InputDecoration(labelText: 'PIN'),
          keyboardType: TextInputType.number,
          validator: (value) {
            if (value == null || value.isEmpty) {
              return 'PIN is required';
            }
            if (!RegExp(r'^[0-9]{4}$').hasMatch(value)) {
              return 'PIN must be exactly 4 digits';
            }
            return null;
          },
        ),
        TextFormField(
          controller: _confirmPinController,
          decoration: const InputDecoration(labelText: 'Confirm PIN'),
          keyboardType: TextInputType.number,
          validator: (value) {
            if (value == null || value.isEmpty) {
              return 'Please confirm your PIN';
            }
            if (value != _pinController.text) {
              return 'PINs do not match';
            }
            if (!RegExp(r'^[0-9]{4}$').hasMatch(value)) {
              return 'PIN must be exactly 4 digits';
            }
            return null;
          },
        ),
      ],
    );
  }

  Widget _step4() {
    return Column(
      children: [
        TextFormField(
          controller: _letterController,
          decoration: const InputDecoration(labelText: 'Letter to Self'),
          maxLines: 5,
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return 'Letter is required';
            }
            if (value.trim().length < 10) {
              return 'Letter must be at least 10 characters';
            }
            return null;
          },
        ),
      ],
    );
  }
}