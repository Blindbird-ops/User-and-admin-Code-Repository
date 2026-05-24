import 'package:shared_preferences/shared_preferences.dart';

class SessionManager {
  static const String _keyLastLogin = 'last_interactive_login_timestamp';
  static const int _maxDays = 90; 

  /// Call this when the user enters their password or OTP successfully
  static Future<void> recordLogin() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyLastLogin, DateTime.now().millisecondsSinceEpoch);
  }

  /// Returns TRUE if the session is expired (older than 90 days)
  static Future<bool> isSessionExpired() async {
    final prefs = await SharedPreferences.getInstance();
    final int? lastLoginMs = prefs.getInt(_keyLastLogin);

    // If never recorded (e.g., fresh install or legacy user), we assume valid
    // and start the timer now to be safe.
    if (lastLoginMs == null) {
      await recordLogin();
      return false;
    }

    final lastLoginDate = DateTime.fromMillisecondsSinceEpoch(lastLoginMs);
    final difference = DateTime.now().difference(lastLoginDate).inDays;

    return difference >= _maxDays;
  }
  
  /// Clears the session timestamp (used during logout)
  static Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyLastLogin);
  }
}