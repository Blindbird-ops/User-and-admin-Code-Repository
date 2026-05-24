import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:connectivity_plus/connectivity_plus.dart'; // Import this
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart'; // Import this
import 'firebase_service.dart';
import 'admin_screen.dart';
import 'secretary_offline_page.dart'; // Ensure you import your offline page 

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final FirebaseService firebaseService = FirebaseService();
  bool isLoading = false;

  @override
  void initState() {
    super.initState();
    _checkAutoLoginOrOffline();
  }

  // --- NEW: AUTO-LOGIN & OFFLINE CHECK ---
  Future<void> _checkAutoLoginOrOffline() async {
    // 1. Check Connectivity
    var connectivityResult = await (Connectivity().checkConnectivity());
    bool isOffline = connectivityResult == ConnectivityResult.none;

    final prefs = await SharedPreferences.getInstance();
    final String? cachedToken = prefs.getString('auth_token');
    final String? cachedUid = prefs.getString('auth_uid');
    final String? cachedEmail = prefs.getString('auth_email');

    if (isOffline) {
      if (cachedUid != null && mounted) {
        _showOfflineDialog(cachedToken, cachedUid);
      }
    } else {
      // --- ONLINE AUTO-LOGIN LOGIC ---
      if (cachedToken != null && cachedUid != null && cachedEmail != null) {
        setState(() => isLoading = true);
        var userData = await firebaseService.fetchUserData(cachedToken);
        
        if (userData != null && userData.isNotEmpty) {
          String userRole = userData['role'] ?? 'user';
          if (userRole == 'admin') {
            if (mounted) {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (context) => AdminScreen(token: cachedToken, userId: cachedUid, email: cachedEmail),
                ),
              );
            }
          } else {
            await prefs.clear();
            if (mounted) setState(() => isLoading = false);
          }
        } else {
          await prefs.clear();
          if (mounted) setState(() => isLoading = false);
        }
      }
    }
  }

  Future<void> _showOfflineDialog(String? token, String uid) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text("No Internet Connection"),
        content: const Text("You are offline. Would you like to proceed to the Secretary Portal in Offline Mode?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context), // Stay on login screen
            child: const Text("Stay Here"),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (_) => SecretaryOfflinePage(firebaseToken: token, userId: uid),
                ),
              );
            },
            child: const Text("Go Offline"),
          ),
        ],
      ),
    );
  }

  // --- CUSTOM FORGOT PASSWORD USING YOUR CLOUD FUNCTIONS ---
  Future<void> _forgotPassword() async {
    final TextEditingController resetEmailController = TextEditingController();
    final TextEditingController otpController = TextEditingController();
    final TextEditingController newPasswordController = TextEditingController();
    // State variables for the dialog
    int step = 1; // 1 = Enter Email, 2 = Enter Code & New Pass
    bool isDialogLoading = false;
    String? dialogError;

    // --- YOUR SPECIFIC CLOUD FUNCTION URLS ---
    const String sendOtpUrl = "https://sendemailotp-wxghgf7viq-uc.a.run.app";
    const String resetPasswordUrl = "https://resetpasswordwithotp-wxghgf7viq-uc.a.run.app";

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            
            // --- STEP 1: SEND EMAIL ---
            Future<void> handleSendOtp() async {
              final email = resetEmailController.text.trim();
              if (email.isEmpty) {
                setStateDialog(() => dialogError = "Please enter your email.");
                return;
              }

              setStateDialog(() { isDialogLoading = true; dialogError = null; });

              try {
                // Your Cloud Function handles { data: { email: ... } } or raw { email: ... }
                // We send wrapped in 'data' to be safe with onCall functions via HTTP
                final response = await http.post(
                  Uri.parse(sendOtpUrl),
                  headers: {"Content-Type": "application/json"},
                  body: jsonEncode({
                    "data": { "email": email }
                  }),
                );

                if (response.statusCode == 200) {
                  // Success: Go to Step 2
                  setStateDialog(() {
                    step = 2;
                    isDialogLoading = false;
                  });
                } else {
                  // Parse error message
                  setStateDialog(() {
                    isDialogLoading = false;
                    dialogError = "Failed: ${response.body}";
                  });
                }
              } catch (e) {
                setStateDialog(() {
                  isDialogLoading = false;
                  dialogError = "Network error. Check connection.";
                });
              }
            }
            // --- STEP 2: RESET PASSWORD ---
            Future<void> handleResetPassword() async {
              final otp = otpController.text.trim();
              final newPass = newPasswordController.text.trim();
              final email = resetEmailController.text.trim();

              if (otp.isEmpty || newPass.isEmpty) {
                setStateDialog(() => dialogError = "All fields are required.");
                return;
              }
              if (newPass.length < 6) {
                setStateDialog(() => dialogError = "Password must be at least 6 characters.");
                return;
              }

              setStateDialog(() { isDialogLoading = true; dialogError = null; });

              try {
                final response = await http.post(
                  Uri.parse(resetPasswordUrl),
                  headers: {"Content-Type": "application/json"},
                  body: jsonEncode({
                    "data": {
                      "email": email,
                      "code": otp, // Note: Your function expects 'code', not 'otp'
                      "newPassword": newPass
                    }
                  }),
                );

                if (response.statusCode == 200) {
                  if (mounted) {
                    Navigator.pop(context); // Close Dialog
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("Password updated successfully! Please log in."), backgroundColor: Colors.green),
                    );
                  }
                } else {
                  setStateDialog(() {
                    isDialogLoading = false;
                    dialogError = "Error: ${response.body}";
                  });
                }
              } catch (e) {
                setStateDialog(() {
                  isDialogLoading = false;
                  dialogError = "Error: $e";
                });
              }
            }
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Text(step == 1 ? "Reset Password" : "Verify & Update"),
              content: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 350, maxWidth: 400),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (step == 1) ...[
                      const Text("Enter your email address. We will send you a verification code via Gmail."),
                      const SizedBox(height: 15),
                      TextField(
                        controller: resetEmailController,
                        decoration: _inputDecoration("Email Address", Icons.email),
                      ),
                    ],
                    
                    if (step == 2) ...[
                      Container(
                        padding: const EdgeInsets.all(8),
                        color: Colors.green.withOpacity(0.1),
                        child: Text("Code sent to ${resetEmailController.text}", style: TextStyle(color: Colors.green[800], fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(height: 15),
                      TextField(
                        controller: otpController,
                        decoration: _inputDecoration("Enter Code", Icons.lock_clock),
                        keyboardType: TextInputType.number,
                      ),
                      const SizedBox(height: 15),
                      TextField(
                        controller: newPasswordController,
                        decoration: _inputDecoration("New Password", Icons.key),
                        obscureText: true,
                      ),
                    ],

                    if (dialogError != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 10.0),
                        child: Text(dialogError!, style: const TextStyle(color: Colors.red, fontSize: 13)),
                      ),
                  ],
                ),
              ),
              actions: [
                if (!isDialogLoading)
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text("Cancel"),
                  ), 
                if (isDialogLoading)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20),
                    child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                else
                  ElevatedButton(
                    onPressed: step == 1 ? handleSendOtp : handleResetPassword,
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade900, foregroundColor: Colors.white),
                    child: Text(step == 1 ? "Send Code" : "Update Password"),
                  ),
              ],
            );
          },
        );
      },
    );
  }
  
  void _login() async {
    if (!mounted) return;

    setState(() => isLoading = true);

    try {
      final emailInput = emailController.text.trim();
      final passwordInput = passwordController.text.trim();

      // 1. Sign in via REST API
      String? token = await firebaseService.signIn(emailInput, passwordInput);

      if (!mounted) return;

      if (token != null) {
        // 2. Sign in via Native SDK (Optional but good for Storage)
        try {
          await FirebaseAuth.instance.signInWithEmailAndPassword(
            email: emailInput,
            password: passwordInput,
          );
        } catch (e) {
          print("Native Auth Warning: $e");
        }

        // 3. Fetch User Data
        var userData = await firebaseService.fetchUserData(token);
        if (userData != null && userData.isNotEmpty) {
          String userRole = userData['role'] ?? 'user';
          String uid = userData['uid'] ?? '';
          String email = userData['email'] ?? '';

          if (userRole != 'admin') {
             ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text("Access denied. You must be an admin to log in."),
                backgroundColor: Colors.red,
              ),
            );
            setState(() => isLoading = false);
            return;
          }

          // --- SAVE CREDENTIALS FOR AUTO-LOGIN ---
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('auth_token', token);
          await prefs.setString('auth_uid', uid);
          await prefs.setString('auth_email', email);
          // ---------------------------------------

          await firebaseService.recordLog(token, "$email logged in", role: userRole);
          await firebaseService.cleanOldLogs(token);

          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => AdminScreen(token: token, userId: uid, email: email,),
            ),
          );
        } else {
          setState(() => isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Login Failed: Could not fetch user data.")),
          );
        }
      } else {
        setState(() => isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Login Failed: Invalid token received.")),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  InputDecoration _inputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: Colors.blue.shade800),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 18),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.blue.shade700.withOpacity(0.4)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.blue.shade700.withOpacity(0.35)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.blue.shade900, width: 2),
      ),
    );
  }

  Widget _featureItem(IconData icon, String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(8),
            ),
            padding: const EdgeInsets.all(8),
            child: Icon(icon, color: Colors.white, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(label, style: const TextStyle(color: Colors.white70, fontSize: 14)),
          ),
        ],
      ),
    );
  }

  Widget _buildLeftPanel(double height) {
    return Container(
      height: height,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: Colors.white.withOpacity(0.04),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Welcome Back',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 8),
          const Text(
            'Secretary Portal',
            style: TextStyle(fontSize: 16, color: Colors.white70),
          ),
          const SizedBox(height: 22),
          _featureItem(Icons.calendar_today_outlined, 'Manage document request and appointments'),
          _featureItem(Icons.people_alt_outlined, 'Application available offline'),
          _featureItem(Icons.note_alt_outlined, 'Manage complaints and resident verification'),
          const Spacer(),
          const Text(
            'Need help? Contact admin',
            style: TextStyle(color: Colors.white60, fontSize: 12),
          ),
        ],
      ),
    );
  }
  Widget _buildFormCard(double width) {
    return Card(
      elevation: 12,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: width,
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/LOGO transparent.png',
              width: 190,
              height: 180,
              fit: BoxFit.contain,
            ),
            const SizedBox(height: 6),
            Text(
              "Sign in to your account",
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: Colors.blue.shade900,
              ),
            ),
            const SizedBox(height: 18),
            TextField(
              controller: emailController,
              decoration: _inputDecoration("Email", Icons.email_outlined),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 14),
            TextField(
              controller: passwordController,
              obscureText: true,
              decoration: _inputDecoration("Password", Icons.lock_outline),
            ),
            
            // --- NEW: FORGOT PASSWORD BUTTON ---
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _forgotPassword,
                child: Text(
                  "Forgot Password?",
                  style: TextStyle(color: Colors.blue.shade700, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            // -----------------------------------

            const SizedBox(height: 10),
            isLoading
                ? CircularProgressIndicator(valueColor: AlwaysStoppedAnimation(Colors.blue.shade700))
                : SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _login,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue.shade900,
                        foregroundColor: Colors.white,
                        elevation: 6,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text(
                        "SIGN IN",
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
            const SizedBox(height: 14),
          ],
        ),
      ),
    );
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Colors.blue.shade900,
              Colors.blue.shade600,
              Colors.blue.shade300,
            ],
            stops: const [0.0, 0.45, 1.0],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 900;
            final containerHeight = isWide ? 520.0 : null;
            return Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 28),
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: isWide ? 1100 : 420),
                  child: isWide
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              flex: 5,
                              child: _buildLeftPanel(containerHeight ?? 480),
                            ),
                            const SizedBox(width: 24),
                            Expanded(
                              flex: 5,
                              child: _buildFormCard(420),
                            ),
                          ],
                        )
                      : _buildFormCard(420),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}