import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'firebase_service.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  _ForgotPasswordScreenState createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final PageController _pageController = PageController();
  final FirebaseService _firebaseService = FirebaseService();
  
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _otpController = TextEditingController();
  final TextEditingController _passController = TextEditingController();
  final TextEditingController _confirmPassController = TextEditingController();

  bool _isLoading = false;
  bool _obscurePass = true;

  // --- HELPER: Show Dialog ---
  void _showDialog(String title, String message, {bool isSuccess = false}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(isSuccess ? Icons.check_circle : Icons.error, color: isSuccess ? Colors.green : Colors.red),
            const SizedBox(width: 10),
            Text(title),
          ],
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              if (isSuccess && title == "Password Reset") {
                Navigator.pop(context); // Go back to Login
              }
            },
            child: const Text("OK"),
          )
        ],
      ),
    );
  }

  // STEP 1: Send OTP
  Future<void> _step1SendOtp() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      _showDialog("Invalid Email", "Please enter a valid email address.");
      return;
    }

    setState(() => _isLoading = true);
    try {
      await _firebaseService.sendEmailOTP(email, "User");
      // Move to Step 2
      _pageController.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.ease);
    } catch (e) {
      _showDialog("Failed", e.toString());
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // STEP 2: Verify OTP
  Future<void> _step2VerifyOtp() async {
    final code = _otpController.text.trim();
    if (code.length != 8) {
      _showDialog("Invalid Code", "Please enter the 8-digit code.");
      return;
    }

    setState(() => _isLoading = true);
    try {
      // Validate with server (doesn't delete code yet)
      await _firebaseService.validateOtp(_emailController.text.trim(), code);
      // Move to Step 3
      _pageController.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.ease);
    } catch (e) {
      _showDialog("Verification Failed", e.toString());
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // STEP 3: Reset Password
  Future<void> _step3ResetPassword() async {
    final pass = _passController.text;
    if (pass != _confirmPassController.text) {
      _showDialog("Mismatch", "Passwords do not match.");
      return;
    }
    if (pass.length < 6) {
      _showDialog("Weak Password", "Password must be at least 6 characters.");
      return;
    }

    setState(() => _isLoading = true);
    try {
      // Final call: Checks OTP again and updates password
      await _firebaseService.resetPasswordWithOtp(
        _emailController.text.trim(),
        _otpController.text.trim(),
        pass,
      );
      _showDialog("Password Reset", "Your password has been changed successfully. Please login.", isSuccess: true);
    } catch (e) {
      _showDialog("Reset Failed", e.toString());
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Reset Password")),
      body: PageView(
        controller: _pageController,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          // --- PAGE 1: EMAIL ---
          _buildPage(
            title: "Forgot Password?",
            subtitle: "Enter your email to receive a code.",
            child: TextField(
              controller: _emailController,
              decoration: const InputDecoration(labelText: "Email", border: OutlineInputBorder(), prefixIcon: Icon(Icons.email)),
            ),
            btnText: "Send Code",
            onPressed: _step1SendOtp,
          ),

          // --- PAGE 2: OTP ---
          _buildPage(
            title: "Verify Code",
            subtitle: "Enter the 8-digit code sent to your email.",
            child: TextField(
              controller: _otpController,
              keyboardType: TextInputType.number,
              maxLength: 8,
              textAlign: TextAlign.center,
              style: const TextStyle(letterSpacing: 4, fontSize: 20),
              decoration: const InputDecoration(labelText: "Code", border: OutlineInputBorder(), counterText: ""),
            ),
            btnText: "Verify",
            onPressed: _step2VerifyOtp,
          ),

          // --- PAGE 3: PASSWORD ---
          _buildPage(
            title: "New Password",
            subtitle: "Create a new strong password.",
            child: Column(
              children: [
                TextField(
                  controller: _passController,
                  obscureText: _obscurePass,
                  decoration: InputDecoration(
                    labelText: "New Password", 
                    border: const OutlineInputBorder(), 
                    suffixIcon: IconButton(icon: Icon(_obscurePass ? Icons.visibility : Icons.visibility_off), onPressed: () => setState(() => _obscurePass = !_obscurePass))
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _confirmPassController,
                  obscureText: _obscurePass,
                  decoration: const InputDecoration(labelText: "Confirm Password", border: OutlineInputBorder()),
                ),
              ],
            ),
            btnText: "Reset Password",
            onPressed: _step3ResetPassword,
          ),
        ],
      ),
    );
  }

  Widget _buildPage({required String title, required String subtitle, required Widget child, required String btnText, required VoidCallback onPressed}) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(title, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(subtitle, textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade600)),
          const SizedBox(height: 32),
          child,
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: _isLoading ? null : onPressed,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurple,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
              ),
              child: _isLoading ? const CircularProgressIndicator(color: Colors.white) : Text(btnText, style: const TextStyle(fontSize: 16)),
            ),
          ),
        ],
      ),
    );
  }
}