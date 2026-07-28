import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:betstop_kenya/services/api_service.dart';
import 'package:betstop_kenya/services/dns_blocking_service.dart';
import 'package:betstop_kenya/services/blocklist_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:betstop_kenya/screens/permission_setup_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {

  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  final ApiService _apiService = ApiService();

  Map<String, dynamic>? _dashboardData;
  List<dynamic>? _recentDetections;

  bool _isLoading = true;
  bool _letterExpanded = false;
  
  // Blocking state
  bool _isBlockingActive = false;
  DnsBlockingService? _dnsBlockingService;
  BlocklistService? _blocklistService;


  @override
  void initState() {
    super.initState();
    _checkVpnStatus();
    _loadData();
  }

  Future<void> _checkVpnStatus() async {
    try {
      final supabase = Supabase.instance.client;
      _blocklistService = BlocklistService(supabase);
      _dnsBlockingService = DnsBlockingService(_blocklistService!);
      
      // Load blocklist from Supabase
      await _dnsBlockingService!.loadBlocklist();
      
      // Check actual VPN status
      final isVpnActive = await _dnsBlockingService!.isVpnActive();
      setState(() {
        _isBlockingActive = isVpnActive;
      });
    } catch (e) {
      print('Error checking VPN status: ${e.toString()}');
      setState(() {
        _isBlockingActive = false;
      });
    }
  }

  Future<void> _loadData() async {

    setState(() {
      _isLoading = true;
    });

    try {

      final token =
          await _storage.read(key: 'jwt_token');

      if (token != null) {

        final dashboard =
            await _apiService.getDashboard(token);

        final detections =
            await _apiService.getRecentDetections(token);


        if (mounted) {

          setState(() {

            _dashboardData = dashboard;
            _recentDetections = detections;
            _isLoading = false;

          });
        }
      }

    } catch(e) {

      if(mounted){

        setState(() {
          _isLoading = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load data: $e')
          ),
        );
      }
    }
  }



  @override
  Widget build(BuildContext context){

    return Scaffold(

      appBar: AppBar(
        title: const Text('BetStop'),
        backgroundColor: const Color(0xFF0B1613),
      ),

      body: _isLoading

      ? const Center(
          child: CircularProgressIndicator(),
        )

      : RefreshIndicator(

          onRefresh: _loadData,

          child: SingleChildScrollView(

            physics: const AlwaysScrollableScrollPhysics(),

            padding: const EdgeInsets.all(16),

            child: Column(

              crossAxisAlignment:
                  CrossAxisAlignment.start,

              children:[

                _buildVpnStatusCard(),

                const SizedBox(height:20),

                _buildStreakCard(),

                const SizedBox(height:20),

                _buildSavedCard(),

                const SizedBox(height:20),

                _buildProgressIndicator(),

                const SizedBox(height:20),

                _buildCommitmentCard(),

                const SizedBox(height:20),

                _buildRecentDetections(),

                const SizedBox(height:20),

                _buildCleanWeekMessage(),

                const SizedBox(height:20),

                _buildGuardianSettings(),

              ],
            ),
          ),
        ),
    );
  }



  Widget _buildStreakCard(){

    final int streakDays =
        (_dashboardData?['streak_days'] ?? 0).toInt();


    return Card(

      color: const Color(0xFF12211D),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),

      child: Padding(

        padding: const EdgeInsets.all(20),

        child: Text(

          'Day $streakDays clean',

          style: TextStyle(
            fontSize:32,
            fontWeight:FontWeight.bold,
            color:Color(0xFF2BC08E),
          ),
        ),
      ),
    );
  }



  Widget _buildSavedCard(){

    final num saved =
        (_dashboardData?['total_saved_kes'] ?? 0);


    final formatter =
        NumberFormat.currency(
          symbol:'KES ',
          decimalDigits:0,
        );


    return Card(

      color: const Color(0xFF12211D),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),

      child: Padding(

        padding: const EdgeInsets.all(20),

        child: Column(

          crossAxisAlignment:
              CrossAxisAlignment.start,

          children:[

            const Text(
              'Saved from betting',
              style: TextStyle(
                color:Color(0xFF8FA69D),
              ),
            ),

            const SizedBox(height:8),

            Text(

              formatter.format(saved),

              style: TextStyle(
                fontSize:24,
                fontWeight:FontWeight.bold,
                color:Color(0xFF2BC08E),
              ),
            ),
          ],
        ),
      ),
    );
  }




  Widget _buildProgressIndicator(){

    final int streakDays =
        (_dashboardData?['streak_days'] ?? 0).toInt();


    final commitmentEnd =
        _dashboardData?['commitment_ends_at'];


    int totalDays = 30;


    if(commitmentEnd != null){

      final DateTime start =
          DateTime.now();

      final DateTime end =
          DateTime.parse(
            commitmentEnd.toString(),
          );


      totalDays =
          end.difference(start).inDays + streakDays;
    }


    if(totalDays <= 0){
      totalDays = 1;
    }


    final double progress =
        (streakDays / totalDays)
        .clamp(0.0,1.0);


    return Card(

      color: const Color(0xFF12211D),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),

      child: Padding(

        padding: const EdgeInsets.all(20),

        child: Column(

          children:[

            LinearProgressIndicator(

              value:progress,

              minHeight:10,

            ),

            const SizedBox(height:12),

            Text(

              '${(progress*100).toStringAsFixed(0)}% of commitment period',

              style: const TextStyle(
                color:Color(0xFF8FA69D),
              ),
            ),
          ],
        ),
      ),
    );
  }



  Widget _buildCommitmentCard(){

    final letter =
        _dashboardData?['letter_to_self'] ?? '';


    return Card(

      color: const Color(0xFF12211D),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),

      child: InkWell(

        onTap:(){

          setState((){

            _letterExpanded =
                !_letterExpanded;

          });
        },


        child: Padding(

          padding: const EdgeInsets.all(20),

          child: Column(

            crossAxisAlignment:
              CrossAxisAlignment.start,

            children:[

              const Text(
                'Your commitment letter',
                style:TextStyle(
                  fontWeight:FontWeight.bold,
                ),
              ),


              if(_letterExpanded)...[

                const SizedBox(height:15),

                Text(
                  letter.toString(),
                  style: const TextStyle(
                    color:Color(0xFF8FA69D),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }



  Widget _buildRecentDetections(){

    if(_recentDetections == null ||
       _recentDetections!.isEmpty){

      return const SizedBox.shrink();
    }


    return Column(

      crossAxisAlignment:
        CrossAxisAlignment.start,

      children:[

        const Text(
          'Recent Activity',
          style:TextStyle(
            fontSize:18,
            fontWeight:FontWeight.bold,
            color:Color(0xFFEAF3EF),
          ),
        ),


        ..._recentDetections!.take(5).map((d){

          return Card(

            color:const Color(0xFF12211D),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child:ListTile(

              title:Text(
                'A site access attempt was blocked',
                style: const TextStyle(
                  color: Color(0xFFEAF3EF),
                ),
              ),

              subtitle:Text(
                d['source'] ?? '',
                style: const TextStyle(
                  color: Color(0xFF8FA69D),
                ),
              ),
            ),
          );
        }),
      ],
    );
  }



  Widget _buildCleanWeekMessage(){

    final int count =
        (_dashboardData?['detections_this_week'] ?? 0)
        .toInt();


    if(count == 0){

      return Card(

        color:Color(0xFF12211D),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),

        child:Padding(

          padding:EdgeInsets.all(20),

          child:Text(
            '🔥 Clean week. Keep going.',
            style:TextStyle(
              fontWeight:FontWeight.bold,
              color: Color(0xFF2BC08E),
            ),
          ),
        ),
      );
    }


    return const SizedBox.shrink();
  }



  Widget _buildGuardianSettings(){

    return Card(

      color:const Color(0xFF12211D),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),

      child:ListTile(

        leading:const Icon(
          Icons.shield,
          color:Color(0xFF2BC08E),
        ),

        title:const Text(
          'Guardian Settings',
          style: TextStyle(
            color: Color(0xFFEAF3EF),
          ),
        ),

        subtitle:const Text(
          'PIN protected monitoring',
          style: TextStyle(
            color: Color(0xFF8FA69D),
          ),
        ),
      ),
    );
  }

  Widget _buildVpnStatusCard() {
    return Card(
      color: const Color(0xFF12211D),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: InkWell(
        onTap: _isBlockingActive ? null : () {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const PermissionSetupScreen()),
          );
        },
        child: ListTile(
          leading: Icon(
            _isBlockingActive ? Icons.vpn_lock : Icons.warning,
            color: _isBlockingActive ? const Color(0xFF2BC08E) : Colors.orange,
          ),
          title: Text(
            _isBlockingActive ? 'Protection: Active' : 'Protection: Inactive — tap to fix',
            style: TextStyle(
              color: _isBlockingActive ? const Color(0xFF2BC08E) : Colors.orange,
              fontWeight: FontWeight.bold,
            ),
          ),
          subtitle: Text(
            _isBlockingActive ? 'VPN blocking is enabled' : 'VPN permission required',
            style: const TextStyle(
              color: Color(0xFF8FA69D),
            ),
          ),
        ),
      ),
    );
  }

}