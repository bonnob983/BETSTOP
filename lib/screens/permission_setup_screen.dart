import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:betstop_kenya/services/dns_blocking_service.dart';
import 'package:betstop_kenya/services/blocklist_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:betstop_kenya/screens/dashboard_screen.dart';

class PermissionSetupScreen extends StatefulWidget {
  const PermissionSetupScreen({super.key});

  @override
  State<PermissionSetupScreen> createState() => _PermissionSetupScreenState();
}

class _PermissionSetupScreenState extends State<PermissionSetupScreen> {
  final _storage = const FlutterSecureStorage();
  
  // UI State
  SetupState _currentState = SetupState.notStarted;
  String? _errorMessage;
  
  // Services
  DnsBlockingService? _dnsBlockingService;
  BlocklistService? _blocklistService;

  @override
  void initState() {
    super.initState();
    _initializeServices();
  }

  Future<void> _initializeServices() async {
    try {
      final supabase = Supabase.instance.client;
      _blocklistService = BlocklistService(supabase);
      _dnsBlockingService = DnsBlockingService(_blocklistService!);
      
      // Load blocklist from Supabase
      await _dnsBlockingService!.loadBlocklist();
      
      // Check if VPN is already active (e.g., from previous setup)
      final isVpnActive = await _dnsBlockingService!.isVpnActive();
      if (isVpnActive) {
        setState(() {
          _currentState = SetupState.active;
        });
        // Mark setup complete
        await _storage.write(key: 'vpn_setup_complete', value: 'true');
      }
    } catch (e) {
      setState(() {
        _currentState = SetupState.failed;
        _errorMessage = 'Failed to initialize services: $e';
      });
    }
  }

  Future<void> _requestVpnPermission() async {
    setState(() {
      _currentState = SetupState.requestingPermission;
      _errorMessage = null;
    });

    try {
      final result = await _dnsBlockingService!.requestVpnPermissionAndStart();
      
      if (result['success'] == true) {
        setState(() {
          _currentState = SetupState.active;
        });
        // Persist setup complete state
        await _storage.write(key: 'vpn_setup_complete', value: 'true');
        
        // Navigate to Dashboard after short delay
        await Future.delayed(const Duration(seconds: 1));
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const DashboardScreen()),
          );
        }
      } else {
        final errorReason = result['error'] as String?;
        setState(() {
          _currentState = SetupState.failed;
          _errorMessage = _getErrorMessage(errorReason);
        });
      }
    } catch (e) {
      setState(() {
        _currentState = SetupState.failed;
        _errorMessage = 'Unexpected error: $e';
      });
    }
  }

  String _getErrorMessage(String? errorReason) {
    switch (errorReason) {
      case 'PERMISSION_DENIED':
        return 'VPN permission was denied. BetStop needs VPN permission to block gambling websites. Please tap Retry and grant the permission.';
      case 'VPN_START_FAILED':
        return 'VPN service failed to start. This may be due to a system issue. Please tap Retry to try again.';
      default:
        return 'Setup failed: ${errorReason ?? "Unknown error"}. Please tap Retry to try again.';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 40),
              const Text(
                'Setup Protection',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF00C853),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'BetStop needs VPN permission to block gambling websites.',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 40),
              Expanded(
                child: _buildStateContent(),
              ),
              if (_currentState == SetupState.failed)
                Padding(
                  padding: const EdgeInsets.only(top: 20),
                  child: ElevatedButton(
                    onPressed: _requestVpnPermission,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00C853),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: const Text(
                      'Retry',
                      style: TextStyle(fontSize: 18),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStateContent() {
    switch (_currentState) {
      case SetupState.notStarted:
        return _buildNotStartedState();
      case SetupState.requestingPermission:
        return _buildRequestingState();
      case SetupState.startingVpn:
        return _buildStartingVpnState();
      case SetupState.active:
        return _buildActiveState();
      case SetupState.failed:
        return _buildFailedState();
    }
  }

  Widget _buildNotStartedState() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(
          Icons.security,
          size: 80,
          color: Colors.grey,
        ),
        const SizedBox(height: 24),
        const Text(
          'VPN Permission Required',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Tap the button below to grant VPN permission. This will enable BetStop to block gambling websites.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey),
        ),
        const SizedBox(height: 32),
        ElevatedButton(
          onPressed: _requestVpnPermission,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF00C853),
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 32),
          ),
          child: const Text(
            'Grant VPN Permission',
            style: TextStyle(fontSize: 18),
          ),
        ),
      ],
    );
  }

  Widget _buildRequestingState() {
    return const Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        CircularProgressIndicator(
          color: Color(0xFF00C853),
        ),
        SizedBox(height: 24),
        Text(
          'Requesting VPN permission...',
          style: TextStyle(fontSize: 18),
        ),
        SizedBox(height: 16),
        Text(
          'Please grant the permission in the system dialog',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey),
        ),
      ],
    );
  }

  Widget _buildStartingVpnState() {
    return const Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        CircularProgressIndicator(
          color: Color(0xFF00C853),
        ),
        SizedBox(height: 24),
        Text(
          'Starting VPN service...',
          style: TextStyle(fontSize: 18),
        ),
        SizedBox(height: 16),
        Text(
          'This may take a few seconds',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey),
        ),
      ],
    );
  }

  Widget _buildActiveState() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(
          Icons.check_circle,
          size: 80,
          color: Color(0xFF00C853),
        ),
        const SizedBox(height: 24),
        const Text(
          'VPN Active',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Color(0xFF00C853),
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Protection is now enabled',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey),
        ),
        const SizedBox(height: 32),
        const CircularProgressIndicator(
          color: Color(0xFF00C853),
        ),
        const SizedBox(height: 16),
        const Text(
          'Proceeding to dashboard...',
          style: TextStyle(color: Colors.grey),
        ),
      ],
    );
  }

  Widget _buildFailedState() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(
          Icons.error_outline,
          size: 80,
          color: Colors.red,
        ),
        const SizedBox(height: 24),
        const Text(
          'Setup Failed',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.red,
          ),
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            _errorMessage ?? 'An unknown error occurred',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.grey),
          ),
        ),
      ],
    );
  }
}

enum SetupState {
  notStarted,
  requestingPermission,
  startingVpn,
  active,
  failed,
}
