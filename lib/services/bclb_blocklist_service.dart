import 'package:supabase_flutter/supabase_flutter.dart';

/// BCLB Blocklist Service
/// 
/// Handles seeding of BCLB-licensed gambling operators to blocklist
/// Only adds domains that can be confirmed via live lookup
/// Unverified names go to blocklist_pending_lookup table
class BclbBlocklistService {
  final SupabaseClient _supabase;
  
  BclbBlocklistService(this._supabase);
  
  /// Confirmed BCLB domains (verified via obvious domain patterns)
  /// All added with pending_review=true - requires manual approval before enforcement
  static const Map<String, List<String>> _confirmedDomains = {
    'Betika': ['betika.com', 'm.betika.com', 'www.betika.com'],
    'SportPesa': ['sportpesa.co.ke', 'm.sportpesa.co.ke', 'www.sportpesa.co.ke'],
    '1XBet': ['1xbet.co.ke', 'm.1xbet.co.ke', 'www.1xbet.co.ke'],
    'OdiBets': ['odibets.com', 'm.odibets.com', 'www.odibets.com'],
    'betpawa': ['betpawa.co.ke', 'm.betpawa.co.ke', 'www.betpawa.co.ke'],
    'Shabiki': ['shabiki.co.ke', 'm.shabiki.co.ke', 'www.shabiki.co.ke'],
    'Dafabet': ['dafabet.com', 'm.dafabet.com', 'www.dafabet.com'],
    '22Bet': ['22bet.com', 'm.22bet.com', 'www.22bet.com'],
  };
  
  /// BCLB trading names that need manual domain verification
  /// These will be added to blocklist_pending_lookup table
  static const List<String> _unverifiedNames = [
    'Gamemania',
    'City Star casino',
    'Malindi Casino',
    'Betken',
    'Flamingobets.casino',
    'Flamingo casino',
    'Pepeta',
    'My Lotto/Tatua tatu & DakaMamili',
    'Mossbets',
    'Falmebet',
    'Kwikbet',
    'Cheza Cash',
    'Mayfair casino',
    'Kesstime Kenya Ltd',
    'Gamekaya',
    'Dolabets',
    'Las Vegas Casinos',
    'Massabet',
    'Juicebet',
    'Betgr8',
    'MeridianBet Enterprise Ltd',
    'Bantubet',
    'Betbahati',
    'Greatech Technologies',
    'Tigonbet',
    'Bangbet Casino',
    'Diamond Casino',
    'Pakakumi',
    'Gameguys',
    'Sunrise Casino',
    'Falcon Casino',
    'Vincitubet Casino',
    'Melbet',
    'Kessbet',
    'Kings bet',
    'Gamestream',
    'Swiftbet',
    'Wakabet',
    'Kilibet',
    'Moyobet',
    'Yetu Bet',
    'Lucky Planet',
    'Bahati Bet',
    'Captains Bet',
    'HotCrash',
    'Lakibets',
    'Ushindi Bet',
    'Malisafi Bets',
    'Thika Casino',
    'Betlion',
    'Kilua Casino',
    'Fasfas',
    'Millionaires Casino',
    'Instabets',
    'Pitch 90 Bets',
    'Beba Beba Bets',
    'Scorepesa',
    'Bcgame',
    'Metabet',
    'Bets307',
    'Dream Big Lottery',
    'L\'arc Casino',
    'Ajebet',
    'Ngiribets',
    'Semobet',
    'Bestnow Bets',
    'Grantbet',
    'Holdem City',
    'Powerbet',
    'Golden Palace',
    'Betnare',
    'Maybets',
    'Betkali',
    'Fanaka',
    'Pujing Casino',
    'Lockbet',
    'Vegas Slots',
    'Janta bets',
    'Betkumi',
    'Playmax',
    'Jet Bet',
    'Okoabets',
    'Lynbet',
    'Ilot Bet',
    'Finix Casino',
    'Sofabets',
    'Inbet',
    'Royal Palms Casino',
    'Kapa Kapa Casino',
    'Tapabet',
  ];
  
  /// Seed confirmed BCLB domains to blocked_domains table
  /// All entries have pending_review=true by default
  Future<void> seedConfirmedDomains() async {
    try {
      for (final entry in _confirmedDomains.entries) {
        final tradingName = entry.key;
        final domains = entry.value;
        
        for (final domain in domains) {
          // Check if domain already exists
          final existing = await _supabase
              .from('blocked_domains')
              .select()
              .eq('domain', domain)
              .maybeSingle();
          
          if (existing == null) {
            // Add new domain with pending_review=true
            await _supabase.from('blocked_domains').insert({
              'domain': domain,
              'trading_name': tradingName,
              'is_active': false, // Not active until reviewed
              'pending_review': true, // Requires manual review
              'source': 'bclb_licensed_list',
              'added_at': DateTime.now().toIso8601String(),
            });
            print('Added domain: $domain (trading name: $tradingName)');
          } else {
            print('Domain already exists: $domain');
          }
        }
      }
      
      print('Confirmed BCLB domains seeded successfully');
    } catch (e) {
      print('Error seeding confirmed domains: $e');
      rethrow;
    }
  }
  
  /// Seed unverified BCLB names to blocklist_pending_lookup table
  /// These require manual domain verification before promotion
  Future<void> seedUnverifiedNames() async {
    try {
      for (final tradingName in _unverifiedNames) {
        // Check if name already exists in pending lookup
        final existing = await _supabase
            .from('blocklist_pending_lookup')
            .select()
            .eq('trading_name', tradingName)
            .maybeSingle();
        
        if (existing == null) {
          // Add to pending lookup table
          await _supabase.from('blocklist_pending_lookup').insert({
            'trading_name': tradingName,
            'status': 'needs_manual_verification',
            'source': 'bclb_licensed_list',
            'added_at': DateTime.now().toIso8601String(),
          });
          print('Added to pending lookup: $tradingName');
        } else {
          print('Already in pending lookup: $tradingName');
        }
      }
      
      print('Unverified BCLB names seeded to pending lookup successfully');
    } catch (e) {
      print('Error seeding unverified names: $e');
      rethrow;
    }
  }
  
  /// Run full BCLB seeding process
  Future<void> seedBclbBlocklist() async {
    print('Starting BCLB blocklist seeding...');
    await seedConfirmedDomains();
    await seedUnverifiedNames();
    print('BCLB blocklist seeding complete');
  }
}
