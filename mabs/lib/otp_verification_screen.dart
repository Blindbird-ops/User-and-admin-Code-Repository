// lib/otp_verification_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart' as auth_sdk;
import 'package:mabs/firebase_service.dart';
import 'package:mabs/login_screen.dart';
import 'package:mabs/session_manager.dart';
import 'package:confetti/confetti.dart';



class OtpVerificationScreen extends StatefulWidget {
  final String identifier; 
  final bool isEmail;
  final String? uid; 
  final String? token; // <--- ADD THIS
  final String? username; 
  final Map<String, dynamic>? pendingUserData; 

  const OtpVerificationScreen({
    super.key,
    required this.identifier,
    required this.isEmail,
    this.uid,
    this.token, // <--- ADD THIS
    this.username,
    this.pendingUserData,
  });

  @override
  _OtpVerificationScreenState createState() => _OtpVerificationScreenState();
}

class _OtpVerificationScreenState extends State<OtpVerificationScreen> {
  final TextEditingController _codeController = TextEditingController();
  final FirebaseService _firebaseService = FirebaseService();
  final auth_sdk.FirebaseAuth _auth = auth_sdk.FirebaseAuth.instance;

  bool _isLoading = false;
  
  // --- MODIFIED: Add a state to track if SMS is currently flying ---
  bool _isSmsSending = false; 
  
  String? _verificationId; // Only for Phone
  int _countdown = 60;
  Timer? _timer;
  late ConfettiController _confettiController;


  @override
  void initState() {
    super.initState();
    _startTimer();
    _confettiController = ConfettiController(duration: const Duration(seconds: 3));

    // --- CRITICAL: Send the code immediately when screen opens ---
    if (widget.isEmail) {
      _sendCustomEmailOtp();
    } else {
      _sendSmsCode();
    }
  }

  void _startTimer() {
    setState(() => _countdown = 60);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_countdown == 0) {
        timer.cancel();
      } else {
        setState(() => _countdown--);
      }
    });
  }

  Future<void> _onBackPressed() async {
    // 1. Show a warning dialog
    final shouldCancel = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Cancel Registration?"),
        content: const Text("If you go back now, your account will not be verified and your data will be saved."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false), // Stay on screen
            child: const Text("Stay"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true), // Leave screen
            child: const Text("Yes, Cancel", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    // 2. If they clicked "Yes, Cancel"
    if (shouldCancel == true) {
      // If it's an email registration, wipe the ghost account!
      if (widget.isEmail && widget.uid != null && widget.token != null) {
        setState(() => _isLoading = true);
        await _firebaseService.deleteUnverifiedAccount(widget.uid!, widget.token!);
      }
      
      // Finally, go back to the registration form
      if (mounted) {
        Navigator.pop(context); 
      }
    }
  }

  // -------------------------
  // EMAIL LOGIC (Custom Backend)
  // -------------------------
  Future<void> _sendCustomEmailOtp() async {
    try {
      await _firebaseService.sendEmailOTP(
        widget.identifier, 
        widget.username ?? "User"
      );
      
      if (mounted) {
        // --- FIX: Clear previous snacks before showing new one ---
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("8-digit code sent to your email."),
            backgroundColor: Colors.green,
          )
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to send email: $e"), backgroundColor: Colors.red)
        );
      }
    }
  }

  Future<void> _verifyEmailCode() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) return;

    setState(() => _isLoading = true);

    try {
      // Force email to lowercase and trim spaces to prevent mismatch
      final cleanEmail = widget.identifier.trim().toLowerCase();
      
      await _firebaseService.verifyEmailOTP(
        cleanEmail, 
        code, 
        widget.uid // <--- REMOVED THE !
      );
      _onSuccess(); 
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          // Made the error message more readable
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red) 
        );
      }
    }
  }
  // -------------------------
  // PHONE LOGIC (Firebase SDK)
  // -------------------------
  Future<void> _sendSmsCode() async {
    // --- MODIFIED: Update state to show we are sending ---
    setState(() {
      _isSmsSending = true;
      _verificationId = null; // Reset this so button disables
    });

    try {
      await _auth.verifyPhoneNumber(
        phoneNumber: '+63${widget.identifier.substring(1)}', 
        verificationCompleted: (auth_sdk.PhoneAuthCredential credential) async {
          // This happens on Android auto-resolution
          setState(() => _isSmsSending = false);
          await _completePhoneAuth(credential);
        },
        verificationFailed: (auth_sdk.FirebaseAuthException e) {
          // --- MODIFIED: Stop loading and show error ---
          setState(() => _isSmsSending = false);
          if (mounted) {
             ScaffoldMessenger.of(context).clearSnackBars();
             ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text("SMS Failed: ${e.message}"), backgroundColor: Colors.red));
          }
        },
        codeSent: (String verId, int? resendToken) {
          // --- MODIFIED: SMS Sent successfully, enable the button now ---
          setState(() {
            _verificationId = verId;
            _isSmsSending = false;
          });
          if (mounted) {
            ScaffoldMessenger.of(context).clearSnackBars();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("Code sent! Check your messages."), backgroundColor: Colors.green));
          }
        },
        codeAutoRetrievalTimeout: (String verId) {
          if (mounted) {
            setState(() {
              _verificationId = verId;
              _isSmsSending = false;
            });
          }
        },
      );
    } catch (e) {
      // --- FIX: Handle generic errors so app doesn't hang ---
      print(e);
      setState(() => _isSmsSending = false);
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Error sending SMS: $e"), backgroundColor: Colors.red));
      }
    }
  }

  Future<void> _completePhoneAuth(auth_sdk.PhoneAuthCredential credential) async {
    try {
      setState(() => _isLoading = true);
      final userCred = await _auth.signInWithCredential(credential);
      final uid = userCred.user!.uid;

      if (widget.pendingUserData != null) {
        // --- REGISTRATION MODE ---
        await _firebaseService.savePhoneUser(
          uid: uid,
          phoneNumber: widget.identifier,
          username: widget.pendingUserData!['username'],
          title: widget.pendingUserData!['title'],
          firstName: widget.pendingUserData!['firstName'],
          middleName: widget.pendingUserData!['middleName'],
          lastName: widget.pendingUserData!['lastName'],
          street: widget.pendingUserData!['street'],
          role: 'user',
          birthdate: widget.pendingUserData!['birthdate'],
          sex: widget.pendingUserData!['sex'],
          province: widget.pendingUserData!['province'],
          municipality: widget.pendingUserData!['municipality'],
          barangay: widget.pendingUserData!['barangay'],
        );
      } else {
        // --- LOGIN MODE ---
        String? tokenNullable = await userCred.user!.getIdToken();
        final token = tokenNullable ?? "";
        final userProfile = await _firebaseService.fetchUserData(token);

        if (userProfile == null) {
          await userCred.user!.delete();
          setState(() => _isLoading = false);

          if (mounted) {
            showDialog(
              context: context,
              builder: (_) => AlertDialog(
                title: const Text("Account Not Found"),
                content: const Text("This phone number is not registered. Please sign up first."),
                actions: [
                  TextButton(
                    onPressed: () {
                      Navigator.pop(context); 
                      Navigator.pop(context); 
                    },
                    child: const Text("OK"),
                  ),
                ],
              ),
            );
          }
          return;
        }
      }
      await SessionManager.recordLogin();

      _onSuccess();
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text("Verification Failed: $e"), backgroundColor: Colors.red));
      }
    }
  }

  Future<void> _verifyPhoneCode() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) return;

    // --- LOGIC REMOVED: We no longer need the "If null return snackbar" check
    // because the button is disabled below if _verificationId is null.

    setState(() => _isLoading = true);
    
    try {
      final credential = auth_sdk.PhoneAuthProvider.credential(
        verificationId: _verificationId!,
        smsCode: code,
      );
      await _completePhoneAuth(credential);
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Invalid Code: $e"), backgroundColor: Colors.red)
        );
      }
    }
  }

  void _onSuccess() {
    _timer?.cancel();
    _confettiController.play(); 

    showDialog(
      context: context,
      barrierDismissible: false, // Forces the user to click the button
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        elevation: 16,
        // --- ADDED SingleChildScrollView HERE TO FIX THE OVERFLOW ---
        child: SingleChildScrollView( 
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 1. Success Icon (Big Green Checkmark)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check_circle, 
                    color: Colors.green, 
                    size: 60
                  ),
                ),
                const SizedBox(height: 24),
                
                // 2. Clear, Exciting Title
                const Text(
                  "Verification Complete! 🎉",
                  style: TextStyle(
                    fontSize: 22, 
                    fontWeight: FontWeight.bold, 
                    color: Colors.black87
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                
                // 3. Insightful, Dynamic Message
                Text(
                  "Your ${widget.isEmail ? 'email address' : 'phone number'} has been successfully verified. Your account is now secure.",
                  style: const TextStyle(fontSize: 14, color: Colors.black54, height: 1.5),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                
                // 4. Primary Call-to-Action Button with YOUR exact routing logic
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepPurple,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 4,
                    ),
                    onPressed: () {
                      // --- YOUR EXACT ORIGINAL LOGIC ---
                      Navigator.pushAndRemoveUntil(
                          context,
                          MaterialPageRoute(builder: (_) => const LoginScreen()),
                          (route) => false);
                    },
                    child: const Text(
                      "Go to Login", 
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    bool isPhoneAndWaitingForId = !widget.isEmail && _verificationId == null;
    bool isButtonDisabled = _isLoading || _isSmsSending || isPhoneAndWaitingForId;

    String buttonText = "Verify";
    if (_isSmsSending) buttonText = "Sending SMS...";
    else if (isPhoneAndWaitingForId) buttonText = "Waiting for SMS...";
    else if (_isLoading) buttonText = "Verifying...";

    // --- WRAP SCAFFOLD IN POPSCOPE TO CATCH ANDROID BACK BUTTON ---
    return PopScope(
      canPop: false, // Prevents automatic popping
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _onBackPressed(); // Trigger our custom logic instead
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.isEmail ? "Verify Email" : "Verify Phone"),
          backgroundColor: Colors.deepPurple,
          foregroundColor: Colors.white,
          // --- OVERRIDE THE APP BAR BACK BUTTON ---
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _onBackPressed, 
          ),
        ),
        
        // ==========================================
        // THIS IS WHAT YOU WERE MISSING: THE STACK
        // ==========================================
        body: Stack(
          children: [
            // 1. YOUR EXISTING UI
            Container(
              height: double.infinity,
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.deepPurple.shade400, Colors.deepPurple.shade200],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16.0),
                  child: Card(
                    elevation: 8.0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    child: ConstrainedBox(
                      constraints:
                          const BoxConstraints(minHeight: 300, maxWidth: 600),
                      child: Padding(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              widget.isEmail ? Icons.mark_email_read : Icons.sms,
                              size: 60,
                              color: Colors.deepPurple,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              "Enter the ${widget.isEmail ? '8-digit' : '6-digit'} code sent to:",
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  fontSize: 16, color: Colors.black54),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              widget.identifier,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.deepPurple,
                              ),
                            ),
                            const SizedBox(height: 32),
                            TextField(
                              controller: _codeController,
                              keyboardType: TextInputType.number,
                              autofillHints: const [AutofillHints.oneTimeCode],
                              textAlign: TextAlign.center,
                              maxLength: widget.isEmail ? 8 : 6,
                              style: const TextStyle(
                                  fontSize: 24, letterSpacing: 8, color: Colors.black87),
                              decoration: const InputDecoration(
                                hintText: "--------",
                                counterText: "",
                                border: OutlineInputBorder(),
                                enabledBorder: OutlineInputBorder(
                                  borderSide: BorderSide(color: Colors.grey),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderSide:
                                      BorderSide(color: Colors.deepPurple, width: 2),
                                ),
                              ),
                            ),
                            const SizedBox(height: 24),
                            SizedBox(
                              width: double.infinity,
                              height: 50,
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.deepPurple,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8)),
                                ),
                                onPressed: isButtonDisabled
                                  ? null 
                                  : () {
                                      if (widget.isEmail) {
                                        _verifyEmailCode();
                                      } else {
                                        _verifyPhoneCode();
                                      }
                                    },
                                child: _isLoading || _isSmsSending
                                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                    : Text(buttonText),
                              ),
                            ),
                            const SizedBox(height: 16),
                            TextButton(
                              onPressed: _countdown == 0 && !_isSmsSending
                                  ? () {
                                      if (widget.isEmail) {
                                        _sendCustomEmailOtp();
                                      } else {
                                        _sendSmsCode();
                                      }
                                      _startTimer();
                                    }
                                  : null,
                              child: Text(
                                _countdown > 0
                                    ? "Resend in $_countdown s"
                                    : "Resend Code",
                                style: TextStyle(
                                  color: (_countdown > 0 || _isSmsSending)
                                      ? Colors.grey
                                      : Colors.deepPurple,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            
            // ==========================================
            // 2. THE CONFETTI WIDGET ON TOP OF EVERYTHING
            // ==========================================
            Align(
              alignment: Alignment.topCenter,
              child: ConfettiWidget(
                confettiController: _confettiController,
                blastDirectionality: BlastDirectionality.directional,
                blastDirection: -3.14 / 2, // Points straight up
                emissionFrequency: 0.05,
                numberOfParticles: 25,
                maxBlastForce: 80,
                minBlastForce: 40,
                gravity: 0.6,
                colors: const [
                  Colors.green, 
                  Colors.blue, 
                  Colors.pink, 
                  Colors.orange, 
                  Colors.purple, 
                  Colors.yellow, 
                  Colors.white
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}