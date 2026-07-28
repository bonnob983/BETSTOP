import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
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
    return ChangeNotifierProvider(
      create: (_) => SignupFlowState(),
      child: MaterialApp(
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
            : (widget.isLoggedIn ? const DashboardScreen() : const SignupScreen()),
      ),
    );
  }
}
