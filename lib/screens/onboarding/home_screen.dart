import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Map<String, dynamic>? _userData;
  Map<String, dynamic>? _commitmentData;
  Map<String, dynamic>? _guardianData;
  int _blockedAppsCount = 0;
  int _blockedDomainsCount = 0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final supabase = Supabase.instance.client;
      
      // Get current user (assuming we have auth)
      final user = supabase.auth.currentUser;
      if (user == null) {
        // Handle not logged in - redirect to signup
        if (mounted) {
          Navigator.pushReplacementNamed(context, '/signup');
        }
        return;
      }

      // Fetch user data
      final userResponse = await supabase
          .from('users')
          .select('*')
          .eq('id', user.id)
          .single();

      if (userResponse == null) throw Exception('User not found');

      // Fetch commitment data
      final commitmentResponse = await supabase
          .from('commitments')
          .select('*')
          .eq('user_id', user.id)
          .eq('is_active', true)
          .maybeSingle();

      // Fetch guardian data
      final guardianResponse = await supabase
          .from('guardians')
          .select('*')
          .eq('user_id', user.id)
          .maybeSingle();

      // Count blocked apps (assuming user_id column exists)
      // Simplified - just fetching all and counting
      final blockedAppsData = await supabase
          .from('blocked_apps')
          .select('id')
          .eq('user_id', user.id);

      // Count blocked domains (assuming user_id column exists)
      // Simplified - just fetching all and counting
      final blockedDomainsData = await supabase
          .from('blocked_domains')
          .select('id')
          .eq('user_id', user.id);

      if (mounted) {
        setState(() {
          _userData = userResponse;
          _commitmentData = commitmentResponse;
          _guardianData = guardianResponse;
          _blockedAppsCount = (blockedAppsData as List?)?.length ?? 0;
          _blockedDomainsCount = (blockedDomainsData as List?)?.length ?? 0;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error loading home data: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  String _getExclusionStatus() {
    if (_commitmentData == null) {
      return 'No active exclusion';
    }

    final commitmentEnd = _commitmentData!['commitment_end'];
    if (commitmentEnd == null) {
      return 'Active — indefinite';
    }

    final endDate = DateTime.parse(commitmentEnd);
    final now = DateTime.now();
    final remaining = endDate.difference(now);

    if (remaining.isNegative) {
      return 'Expired';
    }

    if (remaining.inDays > 0) {
      return '${remaining.inDays} days remaining';
    } else {
      return '${remaining.inHours} hours remaining';
    }
  }

  Future<void> _contactGuardian() async {
    if (_guardianData == null) return;

    final phone = _guardianData!['phone'];
    final uri = Uri.parse('tel:$phone');

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not launch phone dialer')),
        );
      }
    }
  }

  void _viewBlockedList() {
    // TODO: Navigate to blocked apps/sites screen
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Blocked list screen - TODO')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('BetStop'),
        backgroundColor: const Color(0xFF0B1613),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildWelcomeCard(),
                    const SizedBox(height: 20),
                    _buildExclusionStatusCard(),
                    const SizedBox(height: 20),
                    _buildStatsGrid(),
                    const SizedBox(height: 20),
                    _buildActionButtons(),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildWelcomeCard() {
    final name = _userData?['name'] ?? 'User';
    final streakDays = _userData?['streak_days'] ?? 0;

    return Card(
      color: const Color(0xFF12211D),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Welcome back, $name',
              style: GoogleFonts.fraunces(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: const Color(0xFFEAF3EF),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Day $streakDays clean',
              style: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: Color(0xFF2BC08E),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExclusionStatusCard() {
    final status = _getExclusionStatus();

    return Card(
      color: const Color(0xFF12211D),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF2BC08E),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.shield,
                color: Color(0xFF0B1613),
                size: 28,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Exclusion Status',
                    style: TextStyle(
                      fontSize: 14,
                      color: Color(0xFF8FA69D),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    status,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFEAF3EF),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsGrid() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Your Stats',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Color(0xFFEAF3EF),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                title: 'Blocked Apps',
                value: _blockedAppsCount.toString(),
                icon: Icons.block,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildStatCard(
                title: 'Blocked Sites',
                value: _blockedDomainsCount.toString(),
                icon: Icons.language,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required IconData icon,
  }) {
    return Card(
      color: const Color(0xFF12211D),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Icon(
              icon,
              color: const Color(0xFF2BC08E),
              size: 32,
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Color(0xFFEAF3EF),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF8FA69D),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ElevatedButton.icon(
          onPressed: _contactGuardian,
          icon: const Icon(Icons.phone),
          label: const Text('Contact Guardian'),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _viewBlockedList,
          icon: const Icon(Icons.list),
          label: const Text('View Blocked List'),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
        ),
      ],
    );
  }
}
