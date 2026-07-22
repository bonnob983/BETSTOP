import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:betstop_kenya/screens/onboarding_screen.dart';
import 'package:betstop_kenya/screens/dashboard_screen.dart';
import 'package:betstop_kenya/screens/deactivation_warning_screen.dart';
import 'package:betstop_kenya/services/sms_service.dart';
import 'package:betstop_kenya/services/app_detection_service.dart';
import 'package:betstop_kenya/services/blocklist_service.dart';
import 'package:betstop_kenya/services/vpn_monitor_service.dart';
import 'package:betstop_kenya/services/device_admin_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Supabase
  await Supabase.initialize(
    url: 'https://zknpyzsroafubeuonnjk.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InprbnB5enNyb2FmdWJldW9ubmprIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODI4OTU0NzQsImV4cCI6MjA5ODQ3MTQ3NH0.yCQY2MINCKJ4kgaJNcucwPX2k2aD2orukelsk3Z9pjk',
  );
  
  // Initialize secure storage
  const storage = FlutterSecureStorage();
  
  // Check if user is already registered
  final token = await storage.read(key: 'jwt_token');
  
  // Initialize SMS service if logged in
  if (token != null) {
    await SmsService().initialize();
    
    // Initialize blocking services
    final supabase = Supabase.instance.client;
    final blocklistService = BlocklistService(supabase);
    
    // Initialize app detection service
    final appDetectionService = AppDetectionService();
    await appDetectionService.setBlocklistService(blocklistService);
    await appDetectionService.initialize();
    
    // Start VPN monitoring
    final vpnMonitorService = VpnMonitorService();
    await vpnMonitorService.startMonitoring();
  }
  
  runApp(BetStopApp(isLoggedIn: token != null));
}

class BetStopApp extends StatefulWidget {
  final bool isLoggedIn;
  
  const BetStopApp({super.key, required this.isLoggedIn});

  @override
  State<BetStopApp> createState() => _BetStopAppState();
}

class _BetStopAppState extends State<BetStopApp> {
  final _deviceAdminService = DeviceAdminService();
  bool _showDeactivationWarning = false;

  @override
  void initState() {
    super.initState();
    
    if (widget.isLoggedIn) {
      // Start deactivation listener
      _deviceAdminService.startDeactivationListener();
      
      // Set callback to show warning screen
      _deviceAdminService.onDeactivationRequested = () {
        if (mounted) {
          setState(() => _showDeactivationWarning = true);
        }
      };
    }
  }

  @override
  void dispose() {
    _deviceAdminService.stopDeactivationListener();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BetStop Kenya',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.dark(
          primary: const Color(0xFF00C853),
          secondary: const Color(0xFF00C853),
          background: const Color(0xFF0D0D0D),
          surface: const Color(0xFF1A1A1A),
        ),
        scaffoldBackgroundColor: const Color(0xFF0D0D0D),
        useMaterial3: true,
      ),
      home: _showDeactivationWarning
          ? const DeactivationWarningScreen()
          : (widget.isLoggedIn ? const DashboardScreen() : const OnboardingScreen()),
    );
  }
}
