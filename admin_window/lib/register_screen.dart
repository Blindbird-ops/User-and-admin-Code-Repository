// lib/register_screen.dart
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'firebase_service.dart';

class RegisterScreen extends StatefulWidget {
  final String? adminToken;
  const RegisterScreen({super.key, this.adminToken});
  @override
  _RegisterScreenState createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final FirebaseService firebaseService = FirebaseService();
  bool isLoading = false;

  final TextEditingController emailController = TextEditingController();
  final TextEditingController usernameController = TextEditingController();
  final TextEditingController firstNameController = TextEditingController();
  final TextEditingController middleNameController = TextEditingController();
  final TextEditingController lastNameController = TextEditingController();
  final TextEditingController addressController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController confirmPasswordController = TextEditingController();
  // --- CLOUD FUNCTION URLs ---
  final String sendOtpUrl = "https://sendemailotp-wxghgf7viq-uc.a.run.app";
  // Assuming your verify function follows the same pattern:
  final String verifyOtpUrl = "https://verifyemailotp-wxghgf7viq-uc.a.run.app";
  // We store the UID of the newly created user here so we can verify them later
  String? _newlyCreatedUserId;
  @override
  void dispose() {
    emailController.dispose();
    usernameController.dispose();
    firstNameController.dispose();
    middleNameController.dispose();
    lastNameController.dispose();
    addressController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();
    super.dispose();
  }
  
  String generateOTP() {
    var rnd = Random();
    var next = rnd.nextInt(900000) + 100000; // Generates number between 100000 and 999999
    return next.toString();
  }
  void _signUp() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => isLoading = true);
    try {
      final email = emailController.text.trim();
      final username = usernameController.text.trim();
      // 1. Create Account via Service
      String? token = await firebaseService.signUp(
        email: email,
        username: username,
        firstName: firstNameController.text.trim(),
        middleName: middleNameController.text.trim(),
        lastName: lastNameController.text.trim(),
        address: addressController.text.trim(),
        password: passwordController.text.trim(),
        role: 'admin',
        adminToken: widget.adminToken,
      );
      if (token != null) {
        // 2. Fetch the UID of the new user. 
        // We need this for the verify function to mark them as verified in DB.
        final userData = await firebaseService.fetchUserData(token);
        if (userData != null) {
          _newlyCreatedUserId = userData['uid'];
        }
        // 3. TRIGGER CLOUD FUNCTION TO SEND EMAIL
        // We do not send a 'code' here because your index.js generates its own code.
        try {
          final response = await http.post(
            Uri.parse(sendOtpUrl),
            headers: {"Content-Type": "application/json"},
            body: jsonEncode({
              "data": {
                "email": email,
                "username": username,
              }
            }),
          );
          print("Email Send Response: ${response.statusCode}");
        } catch (emailError) {
          print("Error sending email: $emailError");
          // We continue even if this fails technically, to let the user try entering code 
          // (or Resend logic could be added later)
        } 
        if (mounted) {
          setState(() => isLoading = false);
          // 4. Show the Dialog
          _showOtpInputDialog(); 
        }
      } 
    } catch (e) {
      setState(() => isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Registration Error: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }
  // UPDATED DIALOG: Verifies against the Cloud Function
  void _showOtpInputDialog() {
    final otpController = TextEditingController();
    bool isVerifying = false;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('Verify Email'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('A code has been sent to ${emailController.text}.'),
                const SizedBox(height: 10),
                const Text('Please enter the code from the email.', style: TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 20),
                TextField(
                  controller: otpController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: "Enter Code",
                    border: OutlineInputBorder(),
                  ),
                ),
                if (isVerifying)
                  const Padding(
                    padding: EdgeInsets.only(top: 15),
                    child: CircularProgressIndicator(),
                  ),
              ],
            ),
            actions: [
              TextButton(
                child: const Text('Cancel'),
                onPressed: () {
                  Navigator.of(dialogContext).pop(); 
                },
              ),
              ElevatedButton(
                onPressed: isVerifying ? null : () async {
                  final code = otpController.text.trim();
                  if (code.isEmpty) return;
                  setDialogState(() => isVerifying = true);
                  try {
                    // Call the VERIFY cloud function
                    final response = await http.post(
                      Uri.parse(verifyOtpUrl),
                      headers: {"Content-Type": "application/json"},
                      body: jsonEncode({
                        "data": {
                          "email": emailController.text.trim(),
                          "code": code,
                          "uid": _newlyCreatedUserId // Pass UID to update DB
                        }
                      }),
                    );
                    final responseData = json.decode(response.body);
                    // Firebase Functions return result inside "result" key for onCall, 
                    // or error inside "error"
                    if (response.statusCode == 200 && responseData['error'] == null) {
                      // SUCCESS!
                      if (mounted) {
                        Navigator.of(dialogContext).pop(); // Close dialog
                        Navigator.of(context).pop(); // Go back to previous screen
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text("Admin Verified Successfully!"), backgroundColor: Colors.green),
                        );
                      }
                    } else {
                      // FAILURE
                      String msg = responseData['error']?['message'] ?? "Invalid Code";
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(msg), backgroundColor: Colors.red),
                        );
                      }
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text("Verification Error: $e"), backgroundColor: Colors.red),
                      );
                    }
                  } finally {
                    if (mounted) {
                      setDialogState(() => isVerifying = false);
                    }
                  }
                },
                child: const Text('Confirm'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
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
      child: Scaffold(
        backgroundColor: Colors.transparent, 
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 500),
              child: Card(
                elevation: 12.0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 32),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          margin: const EdgeInsets.only(bottom: 20),
                          child: Image.asset(
                            'assets/LOGO transparent.png', 
                            width: 150,
                            height: 150,
                            fit: BoxFit.contain,
                          ),
                        ),
                        Text(
                          'Add Admin Account',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue.shade900,
                          ),
                        ),
                        const SizedBox(height: 24),
                        _buildTextField(emailController, "Email", Icons.email, isEmail: true),
                        const SizedBox(height: 16),
                        _buildTextField(usernameController, "Username", Icons.person),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(child: _buildTextField(firstNameController, "First Name", Icons.badge)),
                            const SizedBox(width: 16),
                            Expanded(child: _buildTextField(lastNameController, "Last Name", Icons.badge_outlined)),
                          ],
                        ),
                        const SizedBox(height: 16),
                        _buildTextField(middleNameController, "Middle Name (Optional)", Icons.short_text, isOptional: true),
                        const SizedBox(height: 16),
                        _buildTextField(addressController, "Address", Icons.location_on),
                        const SizedBox(height: 16),
                        _buildTextField(passwordController, "Password", Icons.lock, isPassword: true),
                        const SizedBox(height: 16),
                        _buildTextField(confirmPasswordController, "Confirm Password", Icons.lock_outline, isPassword: true, isConfirm: true),
                        const SizedBox(height: 32),
                        isLoading
                            ? const CircularProgressIndicator()
                            : SizedBox(
                                width: double.infinity,
                                height: 50,
                                child: ElevatedButton(
                                  onPressed: _signUp,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.blue.shade900,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: const Text("Create Account", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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
      ),
    );
  }

  Widget _buildTextField(
    TextEditingController controller, 
    String label, 
    IconData icon, 
    {bool isPassword = false, bool isEmail = false, bool isOptional = false, bool isConfirm = false}
  ) {
    return TextFormField(
      controller: controller,
      obscureText: isPassword,
      keyboardType: isEmail ? TextInputType.emailAddress : TextInputType.text,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: Colors.blue.shade800),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
        fillColor: Colors.grey.shade50,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      validator: (value) {
        if (isOptional) return null;
        if (value == null || value.isEmpty) return "$label is required";
        if (isEmail && !RegExp(r'\S+@\S+\.\S+').hasMatch(value)) return "Invalid email format";
        if (isPassword && value.length < 6) return "Min 6 characters";
        if (isConfirm && value != passwordController.text) return "Passwords do not match";
        return null;
      },
    );
  }
}