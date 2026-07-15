// Unverified gambling app package names for Kenya
// These need verification via adb before being moved to confirmed list
class GamblingPackagesUnverified {
  // Odibets Kenya - UNVERIFIED
  static const String odibets = 'com.odibets';
  
  // MozzartBet Kenya - UNVERIFIED
  static const String mozzartBet = 'com.mozzartbet';
  
  // Get all unverified packages as a list
  static const List<String> all = [
    odibets,
    mozzartBet,
  ];
  
  // Check if a package name is an unverified gambling app
  static bool isUnverified(String packageName) {
    return all.contains(packageName);
  }
}
