// lib/login_screen.dart
import 'package:mabs/session_manager.dart'; // Import the new file
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mabs/forgot_password_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'firebase_service.dart';
import 'user_screen.dart';
import 'multi_step_registration_form.dart'; 
import 'otp_verification_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController phoneController = TextEditingController();
  
  final FirebaseService firebaseService = FirebaseService();

  bool isLoading = false;
  bool _obscurePassword = true;
  String? _loginError;
  bool _bootstrapping = true;
  bool _isEmailLogin = true; 

  static const _kIdToken = 'idToken';
  static const _kRefreshToken = 'refreshToken';
  static const _kExpiresAt = 'expiresAt';
  static const _kUid = 'uid';
  static const _kEmail = 'email';

  @override
  void initState() {
    super.initState();
    _tryAutoLogin();
  }

  Future<void> _tryAutoLogin() async {
    final prefs = await SharedPreferences.getInstance();

    // ---------------------------------------------------------
    // 1. CHECK 90-DAY SESSION EXPIRY
    // ---------------------------------------------------------
    bool isExpired = await SessionManager.isSessionExpired();
    
    if (isExpired) {
      // 1. Clear session data immediately
      await prefs.clear(); 
      await FirebaseAuth.instance.signOut();
      await SessionManager.clearSession();
      
      setState(() => _bootstrapping = false);
      
      if (!mounted) return;

      // 2. SHOW USER-FRIENDLY DIALOG
      await showDialog(
        context: context,
        barrierDismissible: false, // User MUST click the button
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.security, color: Colors.deepPurple),
              SizedBox(width: 10),
              Text("Session Expired"),
            ],
          ),
          content: const Text(
            "For your security, your session expires every 90 days.\n\n"
            "This helps keep your personal data safe. Please log in again to continue using BaSe App.",
            style: TextStyle(fontSize: 15, height: 1.5),
          ),
          actions: [
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () {
                  Navigator.pop(ctx); // Close Dialog
                  // Stay on Login Screen (we are already here)
                },
                child: const Text("Log In Now"),
              ),
            ),
          ],
        ),
      );
      return; // Stop execution here
    }
    // ---------------------------------------------------------

    // ------------------------------------

    final savedRefreshToken = prefs.getString(_kRefreshToken);
    final savedIdToken = prefs.getString(_kIdToken);
    final savedExpiresAt = prefs.getInt(_kExpiresAt) ?? 0;

    if (savedRefreshToken == null) {
      // ... (Rest of your existing code remains the same) ...
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser != null && !currentUser.isAnonymous) {
        try {
          String? idToken = await currentUser.getIdToken();
          if (idToken != null) {
             await _handleSuccessfulLogin(idToken, currentUser.uid, currentUser.email ?? "", false);
             return;
          }
        } catch (e) {
          print("Error restoring phone session: $e");
        }
      }
      setState(() => _bootstrapping = false);
      return;
    }

    try {
      // ... (Your existing Token Refresh logic here) ...
      String idToken = savedIdToken ?? '';
      int now = DateTime.now().millisecondsSinceEpoch;

      if (idToken.isEmpty || now >= (savedExpiresAt - 30 * 1000)) {
        final refreshed = await firebaseService.refreshIdTokenFull(savedRefreshToken);
        idToken = refreshed.idToken;

        final newExpiresAt = DateTime.now().millisecondsSinceEpoch + refreshed.expiresIn * 1000;
        await prefs.setString(_kIdToken, refreshed.idToken);
        await prefs.setString(_kRefreshToken, refreshed.refreshToken);
        await prefs.setInt(_kExpiresAt, newExpiresAt);
        if (refreshed.uid.isNotEmpty) {
          await prefs.setString(_kUid, refreshed.uid);
        }
      }

      if (FirebaseAuth.instance.currentUser == null) {
        await FirebaseAuth.instance.signInAnonymously();
      }

      final user = await firebaseService.fetchUserData(idToken);
      final uid = user?['uid'] as String? ?? prefs.getString(_kUid) ?? '';
      final email = user?['email'] as String? ?? prefs.getString(_kEmail) ?? '';
      
      bool isVerified = false;
      if (user != null) {
        isVerified = user['isVerified'] ?? false;
        await prefs.setBool('cached_is_verified', isVerified);
      } else {
        isVerified = prefs.getBool('cached_is_verified') ?? false;
      }

      if (uid.isEmpty) {
        setState(() => _bootstrapping = false);
        return;
      }

      if (user != null) {
        await prefs.setString(_kUid, uid);
        await prefs.setString(_kEmail, email);
      }

      if (!mounted) return;
      
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => UserScreen(
            token: idToken,
            uid: uid,
            email: email,
            isVerified: isVerified,
          ),
        ),
      );
    } catch (e) {
      setState(() => _bootstrapping = false);
    }
  }

  Future<void> _saveSession({
    required String idToken,
    required String refreshToken,
    required int expiresIn,
    required String uid,
    required String email,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    
    // --- NEW: RECORD LOGIN TIME ---
    await SessionManager.recordLogin();
    // ------------------------------

    final expiresAt = DateTime.now().millisecondsSinceEpoch + (expiresIn * 1000);
    await prefs.setString(_kIdToken, idToken);
    await prefs.setString(_kRefreshToken, refreshToken);
    await prefs.setInt(_kExpiresAt, expiresAt);
    await prefs.setString(_kUid, uid);
    await prefs.setString(_kEmail, email);
  }
  
  Future<void> _handleSuccessfulLogin(String idToken, String uid, String email, bool isRefresh) async {
      final userData = await firebaseService.fetchUserData(idToken);
      if (userData == null) throw AuthException('Failed to fetch user data');
      
      if (!isRefresh) {
        await _saveSession(
          idToken: idToken,
          refreshToken: "", 
          expiresIn: 3600,
          uid: userData['uid'] ?? uid,
          email: userData['email'] ?? email,
        );
      }

      await firebaseService.cleanOldLogs(idToken);
      await firebaseService.recordLog(
        idToken,
        'User logged in successfully',
        role: userData['role'] ?? 'user',
      );

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => UserScreen(
            token: idToken,
            uid: userData['uid'] ?? uid,
            email: userData['email'] ?? email,
            isVerified: userData['isVerified'] ?? false,
          ),
        ),
      );
  }

  Future<void> _loginWithEmail() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      isLoading = true;
      _loginError = null;
    });

    try {
      final session = await firebaseService.signInWithTokens(
        emailController.text.trim(),
        passwordController.text.trim(),
      );

      // Sync with SDK (Optional but good for some features)
      try {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: emailController.text.trim(),
          password: passwordController.text.trim(),
        );
      } catch (e) {
        print("SDK Sync error (Non-fatal): $e");
      }

      // --- VERIFICATION LOGIC ---
      final emailVerified = await firebaseService.isEmailVerified(session.idToken);
      final userData = await firebaseService.fetchUserData(session.idToken);
      
      bool canLogin = emailVerified;

      // Only check isVerified from database. manualAuth is gone.
      if (userData != null) {
        if (userData['isVerified'] == true) canLogin = true;
      }

      if (!canLogin) {
        // Redirect to OTP Screen (It will send the email automatically there)
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => OtpVerificationScreen(
            identifier: emailController.text.trim(),
            isEmail: true,
            uid: session.uid,
            username: userData?['username'] ?? "User",
          )),
        );
        setState(() => isLoading = false);
        return;
      }

      // --- SUCCESSFUL LOGIN ---
      await _saveSession(
        idToken: session.idToken,
        refreshToken: session.refreshToken,
        expiresIn: session.expiresIn,
        uid: userData?['uid'] ?? session.uid,
        email: userData?['email'] ?? session.email,
      );
      
      await firebaseService.cleanOldLogs(session.idToken);
      await firebaseService.recordLog(
        session.idToken,
        'User logged in successfully',
        role: userData?['role'] ?? 'user',
      );

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => UserScreen(
            token: session.idToken,
            uid: userData?['uid'] ?? session.uid,
            email: userData?['email'] ?? session.email,
            isVerified: userData?['isVerified'] ?? false,
          ),
        ),
      );

    } on AuthException catch (e) {
      setState(() => _loginError = e.message);
    } catch (e) {
      setState(() => _loginError = 'An unexpected error occurred. Please try again.');
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> _loginWithPhone() async {
    final phoneInput = phoneController.text.trim();
    
    // 1. Basic Validation
    if (phoneInput.isEmpty || phoneInput.length != 9) {
       setState(() => _loginError = "Please enter the remaining 9 digits.");
       return;
    }
    
    setState(() => isLoading = true); 

    // 2. Format for Cloud Function (+63...)
    String formattingForBackend = "+639$phoneInput"; 

    // 3. Format for OTP Screen (09...)
    String formattingForUi = "09$phoneInput";

    try {
      // 4. Call the Cloud Function
      bool exists = await firebaseService.checkPhoneExists(formattingForBackend);

      if (!exists) {
        setState(() {
          isLoading = false;
          _loginError = "This number is not registered. Please sign up first.";
        });
        return; 
      }

      // 5. If exists, proceed to SMS
      setState(() => isLoading = false);
      
      if (!mounted) return;
      Navigator.push(
        context, 
        MaterialPageRoute(builder: (_) => OtpVerificationScreen(
          identifier: formattingForUi, 
          isEmail: false,
        ))
      );

    } catch (e) {
      setState(() {
        isLoading = false;
        _loginError = "Connection error. Please try again.";
      });
      print("Check Phone Error: $e");
    }
  }

  void _onForgotPasswordPressed() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ForgotPasswordScreen()),
    );
  }


  @override
  Widget build(BuildContext context) {
    if (_bootstrapping) {
      return Scaffold(
        body: Container(
          decoration: BoxDecoration(gradient: LinearGradient(colors: [Colors.deepPurple.shade400, Colors.deepPurple.shade200], begin: Alignment.topCenter, end: Alignment.bottomCenter)),
          child: const Center(child: CircularProgressIndicator(color: Colors.white)),
        ),
      );
    }

    final screenHeight = MediaQuery.of(context).size.height;
    return Scaffold(
      body: Container(
        height: double.infinity,
        decoration: BoxDecoration(gradient: LinearGradient(colors: [Colors.deepPurple.shade400, Colors.deepPurple.shade200], begin: Alignment.topCenter, end: Alignment.bottomCenter)),
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: screenHeight),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Form(
                  key: _formKey,
                  child: Card(
                    elevation: 8,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Image.asset('assets/images/LOGO transparent.png', height: 240),
                          const SizedBox(height: 16),
                          const Text('Welcome Back', textAlign: TextAlign.center, style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.deepPurple)),
                          const SizedBox(height: 16),

                          Container(
                            padding: const EdgeInsets.all(4),
                            margin: const EdgeInsets.only(bottom: 20),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade200,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: GestureDetector(
                                    onTap: () => setState(() { _isEmailLogin = true; _loginError = null; }),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(vertical: 12),
                                      decoration: BoxDecoration(
                                        color: _isEmailLogin ? Colors.white : Colors.transparent,
                                        borderRadius: BorderRadius.circular(10),
                                        boxShadow: _isEmailLogin ? [const BoxShadow(color: Colors.black12, blurRadius: 4)] : [],
                                      ),
                                      child: const Text("Email", textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold)),
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: GestureDetector(
                                    onTap: () => setState(() { _isEmailLogin = false; _loginError = null; }),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(vertical: 12),
                                      decoration: BoxDecoration(
                                        color: !_isEmailLogin ? Colors.white : Colors.transparent,
                                        borderRadius: BorderRadius.circular(10),
                                        boxShadow: !_isEmailLogin ? [const BoxShadow(color: Colors.black12, blurRadius: 4)] : [],
                                      ),
                                      child: const Text("Phone", textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold)),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          if (_loginError != null)
                            Container(
                              padding: const EdgeInsets.all(12),
                              margin: const EdgeInsets.only(bottom: 16),
                              decoration: BoxDecoration(
                                color: Colors.red.shade50,
                                border: Border.all(color: Colors.red.shade200),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(_loginError!, style: TextStyle(color: Colors.red.shade700, fontSize: 14)),
                            ),

                          if (_isEmailLogin) ...[
                             TextFormField(
                              controller: emailController,
                              keyboardType: TextInputType.emailAddress,
                              decoration: const InputDecoration(
                                labelText: "Email",
                                prefixIcon: Icon(Icons.email),
                                border: OutlineInputBorder(),
                              ),
                              validator: (value) => (value == null || value.isEmpty) ? "Please enter email" : null,
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: passwordController,
                              obscureText: _obscurePassword,
                              decoration: InputDecoration(
                                labelText: "Password",
                                prefixIcon: const Icon(Icons.lock),
                                border: const OutlineInputBorder(),
                                suffixIcon: IconButton(
                                  icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                                ),
                              ),
                              validator: (value) => (value == null || value.isEmpty) ? "Please enter password" : null,
                            ),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(onPressed: _onForgotPasswordPressed, child: const Text("Forgot Password?")),
                            ),
                          ] else ...[
                            TextFormField(
                              controller: phoneController,
                              keyboardType: TextInputType.phone,
                              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(9)],
                              decoration: const InputDecoration(
                                labelText: "Mobile Number",
                                prefixText: "09",
                                prefixStyle: TextStyle(color: Colors.black, fontSize: 16),
                                hintText: "xxxxxxxxx", 
                                prefixIcon: Icon(Icons.phone),
                                border: OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(8)),
                              child: const Text(
                                "We will send a 6-digit code to log you in instantly.",
                                style: TextStyle(fontSize: 12, color: Colors.blue),
                                textAlign: TextAlign.center,
                              ),
                            ),
                            const SizedBox(height: 20),
                          ],

                          const SizedBox(height: 10),
                          isLoading
                              ? const Center(child: CircularProgressIndicator())
                              : ElevatedButton(
                                  onPressed: _isEmailLogin ? _loginWithEmail : _loginWithPhone,
                                  style: ElevatedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                    child: Text(_isEmailLogin ? "Login" : "Send Code", style: const TextStyle(fontSize: 16)),
                                  ),
                                ),
                          const SizedBox(height: 12),
                          TextButton(
                            onPressed: () {
                              Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const MultiStepRegistrationForm())); 
                            },
                            child: const Text("Don't have an account? Register"),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}