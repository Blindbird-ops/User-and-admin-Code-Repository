// lib/settings_page.dart

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: Text("Settings", style: GoogleFonts.lato(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: ListView(
        children: [
          const SizedBox(height: 20),
          
          // --- 1. Account Section ---
          _buildSectionHeader("Account & Security"),
          _buildListTile(
            context,
            icon: Icons.lock_reset,
            title: "Change Password",
            subtitle: "Receive an email to reset your password",
            onTap: () => _showChangePasswordDialog(context),
          ),
          
          // --- 2. Support & Legal Section ---
          _buildSectionHeader("Support & Legal"),
          // NEW: User Guide Button
          _buildListTile(
            context,
            icon: Icons.menu_book_rounded, 
            title: "User Guide / FAQ",
            subtitle: "Learn how to use the app features",
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const UserGuidePage())),
          ),
          _buildListTile(
            context,
            icon: Icons.description_outlined,
            title: "Terms and Conditions",
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TermsConditionsPage())),
          ),
          _buildListTile(
            context,
            icon: Icons.privacy_tip_outlined,
            title: "Privacy Policy",
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PrivacyPolicyPage())),
          ),
          
          // --- 3. App Info Section ---
          _buildSectionHeader("App Info"),
          _buildListTile(
            context,
            icon: Icons.info_outline,
            title: "About BaSe App",
            subtitle: "Version 1.0.0",
            onTap: () {
              showAboutDialog(
                context: context,
                applicationName: "BaSe App",
                applicationVersion: "1.0.0",
                applicationLegalese: "© 2026 Barangay Services",
                applicationIcon: const Icon(Icons.home_work, size: 50, color: Colors.deepPurple),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title.toUpperCase(),
        style: GoogleFonts.lato(
          fontSize: 13,
          fontWeight: FontWeight.bold,
          color: Colors.deepPurple.shade700,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildListTile(BuildContext context, {required IconData icon, required String title, String? subtitle, required VoidCallback onTap}) {
    return Container(
      color: Colors.white,
      margin: const EdgeInsets.only(bottom: 1), // Thin divider effect
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: Colors.deepPurple.withOpacity(0.1), shape: BoxShape.circle),
          child: Icon(icon, color: Colors.deepPurple),
        ),
        title: Text(title, style: GoogleFonts.lato(fontWeight: FontWeight.w600)),
        subtitle: subtitle != null ? Text(subtitle, style: GoogleFonts.lato(fontSize: 12)) : null,
        trailing: const Icon(Icons.chevron_right, color: Colors.grey),
        onTap: onTap,
      ),
    );
  }

  void _showChangePasswordDialog(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.email == null || user.email!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("No email associated with this account.")));
      return;
    }

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Reset Password"),
        content: Text("Send a password reset email to ${user.email}?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple, foregroundColor: Colors.white),
            onPressed: () async {
              Navigator.pop(context);
              try {
                await FirebaseAuth.instance.sendPasswordResetEmail(email: user.email!);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Email sent! Check your inbox.")));
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
                }
              }
            },
            child: const Text("Send Email"),
          ),
        ],
      ),
    );
  }
}

// ==========================================================
// SUB-PAGE: USER GUIDE
// ==========================================================
class UserGuidePage extends StatelessWidget {
  const UserGuidePage({super.key});

  final List<Map<String, String>> _guideItems = const [
    {
      "title": "How to Verify my Account?",
      "content": "1. Go to the 'Profile' tab.\n"
                 "2. Click the 'Verify Account' button.\n"
                 "3. Upload a clear photo of your Valid ID.\n"
                 "4. Upload a Selfie holding that ID.\n"
                 "5. Wait for the Admin to approve your request."
    },
    {
      "title": "How to Request a Document?",
      "content": "1. Ensure your account is verified.\n"
                 "2. Go to the 'Home' dashboard.\n"
                 "3. Tap 'Request Document'.\n"
                 "4. Select the document type (e.g., Barangay Clearance).\n"
                 "5. Fill in the required details and submit."
    },
    {
      "title": "How to Book an Appointment?",
      "content": "1. On the Home Dashboard, tap 'Request Appointment'.\n"
                 "2. Select a Date and Time.\n"
                 "3. Enter the purpose of your visit.\n"
                 "4. Wait for confirmation notification."
    },
    {
      "title": "How to File a Complaint?",
      "content": "1. Tap the 'Complaint' button on the dashboard.\n"
                 "2. Enter the name of the person you are complaining against.\n"
                 "3. Describe the incident in detail.\n"
                 "4. The Barangay Secretary will review your case."
    },
    {
      "title": "Checking Request Status",
      "content": "You can track your documents and appointments by tapping 'View Request Status' on the main dashboard. You will see if your request is Pending, Processing, Approved, or Rejected."
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: Text("User Guide", style: GoogleFonts.lato(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _guideItems.length,
        itemBuilder: (context, index) {
          final item = _guideItems[index];
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: ExpansionTile(
              leading: CircleAvatar(
                backgroundColor: Colors.deepPurple.shade50,
                child: Text("${index + 1}", style: const TextStyle(color: Colors.deepPurple, fontWeight: FontWeight.bold)),
              ),
              title: Text(
                item["title"]!,
                style: GoogleFonts.lato(fontWeight: FontWeight.w700, fontSize: 16),
              ),
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  child: Text(
                    item["content"]!,
                    style: GoogleFonts.lato(fontSize: 15, height: 1.5, color: Colors.grey.shade800),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ==========================================================
// SUB-PAGE: TERMS & CONDITIONS
// ==========================================================
class TermsConditionsPage extends StatelessWidget {
  const TermsConditionsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Terms and Conditions"), backgroundColor: Colors.deepPurple, foregroundColor: Colors.white),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Terms of Use", style: GoogleFonts.lato(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Text(
              "1. Acceptance of Terms\nBy accessing and using the BaSe App, you accept and agree to be bound by the terms and provision of this agreement.\n\n"
              "2. User Responsibilities\nUsers are responsible for maintaining the confidentiality of their account information and for all activities that occur under their account.\n\n"
              "3. Data Accuracy\nYou agree to provide accurate, current, and complete information during the registration and verification process.\n\n"
              "4. Prohibited Activities\nHarassment, submitting false documents, or any illegal use of the application is strictly prohibited and may result in account termination.",
              style: GoogleFonts.lato(fontSize: 16, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}

// ==========================================================
// SUB-PAGE: PRIVACY POLICY
// ==========================================================
class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Privacy Policy"), backgroundColor: Colors.deepPurple, foregroundColor: Colors.white),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Privacy Policy", style: GoogleFonts.lato(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Text(
              "1. Information Collection\nWe collect personal information such as name, address, and contact details solely for the purpose of providing barangay services.\n\n"
              "2. Use of Information\nYour data is used to verify your residency, process document requests, and manage appointments.\n\n"
              "3. Data Protection\nWe implement security measures to maintain the safety of your personal information. We do not sell or trade your data to outside parties.\n\n"
              "4. Contact Us\nIf you have any questions regarding this privacy policy, please contact the Barangay Secretary.",
              style: GoogleFonts.lato(fontSize: 16, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}