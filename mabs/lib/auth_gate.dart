import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'firebase_service.dart';
import 'login_screen.dart';
import 'user_screen.dart';
import 'onboarding_screen.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  static const _kIdToken = 'idToken';
  static const _kRefreshToken = 'refreshToken';
  static const _kExpiresAt = 'expiresAt';
  static const _kUid = 'uid';
  static const _kEmail = 'email';

  Future<_GateResult> _resolve() async {
    final prefs = await SharedPreferences.getInstance();

    // 1) Onboarding check
    final seen = prefs.getBool('onboardingCompleted') ?? false;
    if (!seen) {
      return _GateResult.onboarding();
    }

    // 2) Session resolution
    final service = FirebaseService();
    final refreshToken = prefs.getString(_kRefreshToken);
    final savedIdToken = prefs.getString(_kIdToken);
    final savedExpiresAt = prefs.getInt(_kExpiresAt) ?? 0;

    // No session -> go to login
    if (refreshToken == null) {
      return _GateResult.login();
    }

    String idToken = savedIdToken ?? '';
    final now = DateTime.now().millisecondsSinceEpoch;

    // Refresh if missing or near expiry (30s buffer)
    if (idToken.isEmpty || now >= (savedExpiresAt - 30 * 1000)) {
      try {
        final refreshed = await service.refreshIdTokenFull(refreshToken);
        idToken = refreshed.idToken;

        final newExpiresAt = DateTime.now().millisecondsSinceEpoch + (refreshed.expiresIn * 1000);
        await prefs.setString(_kIdToken, refreshed.idToken);
        await prefs.setString(_kRefreshToken, refreshed.refreshToken);
        await prefs.setInt(_kExpiresAt, newExpiresAt);
        if (refreshed.uid.isNotEmpty) {
          await prefs.setString(_kUid, refreshed.uid);
        }
      } catch (_) {
        return _GateResult.login();
      }
    }

    // Fetch profile to confirm session and get flags
    try {
      final user = await service.fetchUserData(idToken);
      if (user == null) return _GateResult.login();

      final uid = user['uid'] as String? ?? (prefs.getString(_kUid) ?? '');
      final email = user['email'] as String? ?? (prefs.getString(_kEmail) ?? '');
      final isVerified = user['isVerified'] ?? false;

      await prefs.setString(_kUid, uid);
      await prefs.setString(_kEmail, email);

      return _GateResult.user(idToken, uid, email, isVerified);
    } catch (_) {
      return _GateResult.login();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_GateResult>(
      future: _resolve(),
      builder: (context, snap) {
        if (!snap.hasData) return const _Splash();
        final r = snap.data!;
        switch (r.route) {
          case _Route.onboarding:
            return const OnboardingScreen();
          case _Route.login:
            return const LoginScreen();
          case _Route.user:
            return UserScreen(
              token: r.idToken!,
              uid: r.uid!,
              email: r.email!,
              isVerified: r.isVerified,
            );
        }
      },
    );
  }
}

enum _Route { onboarding, login, user }

class _GateResult {
  final _Route route;
  final String? idToken;
  final String? uid;
  final String? email;
  final bool isVerified;

  _GateResult._(this.route, {this.idToken, this.uid, this.email, this.isVerified = false});

  factory _GateResult.onboarding() => _GateResult._(_Route.onboarding);
  factory _GateResult.login() => _GateResult._(_Route.login);
  factory _GateResult.user(String idToken, String uid, String email, bool isVerified) =>
      _GateResult._(_Route.user, idToken: idToken, uid: uid, email: email, isVerified: isVerified);
}

class _Splash extends StatelessWidget {
  const _Splash();
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.deepPurple.shade400, Colors.deepPurple.shade200],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: const Center(child: CircularProgressIndicator(color: Colors.white)),
    );
  }
}