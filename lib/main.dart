import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:betstop_kenya/screens/onboarding_screen.dart';
import 'package:betstop_kenya/screens/dashboard_screen.dart';
import 'package:betstop_kenya/screens/deactivation_warning_screen.dart';
import 'package:betstop_kenya/screens/onboarding/signup_screen.dart';
import 'package:betstop_kenya/screens/onboarding/exclusion_type_screen.dart';
import 'package:betstop_kenya/screens/onboarding/full_exclusion_screen.dart';
import 'package:betstop_kenya/screens/onboarding/partial_exclusion_screen.dart';
import 'package:betstop_kenya/screens/onboarding/confirmation_screen.dart';
import 'package:betstop_kenya/screens/onboarding/home_screen.dart';
import 'package:betstop_kenya/models/signup_flow_state.dart';
import 'package:betstop_kenya/models/auth_state.dart' as auth;
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
  
  runApp(BetStopApp());
}

class BetStopApp extends StatelessWidget {
  const BetStopApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => auth.AppAuthState()),
        ChangeNotifierProvider(create: (_) => SignupFlowState()),
      ],
      child: const _BetStopAppContent(),
    );
  }
}

class _BetStopAppContent extends StatefulWidget {
  const _BetStopAppContent();

  @override
  State<_BetStopAppContent> createState() => _BetStopAppContentState();
}

class _BetStopAppContentState extends State<_BetStopAppContent> {
  final _deviceAdminService = DeviceAdminService();
  bool _showDeactivationWarning = false;
  bool _servicesInitialized = false;

  @override
  void initState() {
    super.initState();
    _initializeServices();
  }

  Future<void> _initializeServices() async {
    final authState = context.read<auth.AppAuthState>();
    
    // Listen to auth state changes
    authState.addListener(_onAuthStateChanged);
    
    // Initialize services if already logged in
    if (authState.isLoggedIn) {
      await _startBlockingServices();
    }
  }

  void _onAuthStateChanged() {
    final authState = context.read<auth.AppAuthState>();
    if (authState.isLoggedIn && !_servicesInitialized) {
      _startBlockingServices();
    }
  }

  Future<void> _startBlockingServices() async {
    if (_servicesInitialized) return;
    
    try {
      await SmsService().initialize();
      
      final supabase = Supabase.instance.client;
      final blocklistService = BlocklistService(supabase);
      
      final appDetectionService = AppDetectionService();
      await appDetectionService.setBlocklistService(blocklistService);
      await appDetectionService.initialize();
      
      final vpnMonitorService = VpnMonitorService();
      await vpnMonitorService.startMonitoring();
      
      // Start deactivation listener
      _deviceAdminService.startDeactivationListener();
      
      // Set callback to show warning screen
      _deviceAdminService.onDeactivationRequested = () {
        if (mounted) {
          setState(() => _showDeactivationWarning = true);
        }
      };
      
      setState(() => _servicesInitialized = true);
    } catch (e) {
      print('Error initializing services: $e');
    }
  }

  @override
  void dispose() {
    _deviceAdminService.stopDeactivationListener();
    context.read<auth.AppAuthState>().removeListener(_onAuthStateChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<auth.AppAuthState>(
      builder: (context, authState, child) {
        return MaterialApp(
          title: 'BetStop Kenya',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            colorScheme: ColorScheme.dark(
              primary: const Color(0xFF2BC08E),
              secondary: const Color(0xFF2BC08E),
              background: const Color(0xFF0B1613),
              surface: const Color(0xFF12211D),
            ),
            scaffoldBackgroundColor: const Color(0xFF0B1613),
            useMaterial3: true,
            cardTheme: CardThemeData(
              color: const Color(0xFF12211D),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            textTheme: TextTheme(
              headlineLarge: GoogleFonts.fraunces(
                color: const Color(0xFFEAF3EF),
              ),
              headlineMedium: GoogleFonts.fraunces(
                color: const Color(0xFFEAF3EF),
              ),
              bodyLarge: const TextStyle(
                color: Color(0xFFEAF3EF),
              ),
              bodyMedium: const TextStyle(
                color: Color(0xFF8FA69D),
              ),
            ),
            inputDecorationTheme: InputDecorationTheme(
              filled: true,
              fillColor: const Color(0xFF12211D),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              labelStyle: const TextStyle(
                color: Color(0xFF8FA69D),
              ),
            ),
            elevatedButtonTheme: ElevatedButtonThemeData(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2BC08E),
                foregroundColor: const Color(0xFF0B1613),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            outlinedButtonTheme: OutlinedButtonThemeData(
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF2BC08E),
                side: const BorderSide(color: Color(0xFF2BC08E)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          routes: {
            '/signup': (context) => const SignupScreen(),
            '/exclusion_type': (context) => const ExclusionTypeScreen(),
            '/full_exclusion': (context) => const FullExclusionScreen(),
            '/partial_exclusion': (context) => const PartialExclusionScreen(),
            '/confirmation': (context) => const ConfirmationScreen(),
            '/home': (context) => const HomeScreen(),
          },
          home: _showDeactivationWarning
              ? const DeactivationWarningScreen()
              : (authState.isLoggedIn ? const DashboardScreen() : const SignupScreen()),
        );
      },
    );
  }
}
