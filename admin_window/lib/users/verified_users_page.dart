// lib/users/verified_users_page.dart

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:admin_window/users/verified_user.dart';
import 'package:admin_window/users/verification_submission.dart';
import 'package:admin_window/services/data_service.dart';
import 'package:admin_window/firebase_service.dart';
import 'package:admin_window/models/string_extensions.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

// Your chosen theme colors
const Color themePrimaryColor = Color(0xFF5E35B1);
const Color themeAccentColor = Color(0xFFF3E5F5);
const Color pageBackgroundColor = Color(0xFFF5F5F7);
const Color cardBackgroundColor = Colors.white;

class VerifiedUsersPage extends StatefulWidget {
  final String token;
  const VerifiedUsersPage({super.key, required this.token});

  @override
  _VerifiedUsersPageState createState() => _VerifiedUsersPageState();
}

class _VerifiedUsersPageState extends State<VerifiedUsersPage> {
  List<VerifiedUser> _allVerifiedUsers = [];
  List<VerifiedUser> _filteredUsers = [];
  final TextEditingController _searchController = TextEditingController();

  VerifiedUser? _selectedUser;
  VerificationSubmission? _selectedUserSubmission;

  // Optional approval metadata
  String? _selectedApprovalNote;
  String? _selectedApprovedAt;
  String? _selectedApprovedBy;

  bool _isLoading = true;
  bool _isLoadingDetails = false;
  String? _errorMessage;

  late final DataService _dataService;
  final FirebaseService _firebaseService = FirebaseService(); 
  String? _adminEmail;
  bool _isProcessingAction = false;

  @override
  void initState() {
    super.initState();
    _dataService = DataService(); 
    _fetchAdminEmail();
    _fetchVerifiedUsers();
    _searchController.addListener(_filterUsers);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _dataService.close(); // Good practice to close resources
    super.dispose();
  }

  String _formatLabel(String key) {
    if (key.isEmpty) return key;
    if (key.toLowerCase() == 'tin') return 'TIN';
    if (key.toLowerCase() == 'sss') return 'SSS';

    String formatted = key.replaceAllMapped(
      RegExp(r'([a-z])([A-Z])'), 
      (Match m) => '${m[1]} ${m[2]}'
    );
    formatted = formatted.replaceAll('_', ' ');
    return formatted[0].toUpperCase() + formatted.substring(1);
  }

  Future<void> _fetchAdminEmail() async {
    try {
      final email = await _dataService.getCurrentUserEmail();
      if (mounted) setState(() => _adminEmail = email);
    } catch (_) {}
  }

  Future<void> _logAction(String message) async {
    if (_adminEmail != null) {
      await _firebaseService.recordAdminLog(widget.token, message, _adminEmail!);
    }
  }

  Future<void> _fetchVerifiedUsers() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _selectedUser = null;
      _selectedUserSubmission = null;
      _selectedApprovalNote = null;
      _selectedApprovedAt = null;
      _selectedApprovedBy = null;
    });
    try {
      final data = await _dataService.getData("users");
      if (mounted && data != null) {
        final List<VerifiedUser> users = [];
        data.forEach((userId, userData) {
          if (userData['role'] == 'user' && (userData['isVerified'] as bool? ?? false)) {
            users.add(VerifiedUser.fromJson(userId, userData));
          }
        });
        users.sort((a, b) => a.fullName.compareTo(b.fullName));
        setState(() {
          _allVerifiedUsers = users;
          _filteredUsers = users;
          _isLoading = false;
        });
      } else if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) setState(() => _errorMessage = 'Failed to fetch users: $e');
    }
  }

  void _filterUsers() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredUsers = _allVerifiedUsers.where((user) {
        final nameMatches = user.fullName.toLowerCase().contains(query);
        final emailMatches = user.email.toLowerCase().contains(query);
        final phoneMatches = (user.phoneNumber ?? "").toLowerCase().contains(query);
        return nameMatches || emailMatches || phoneMatches;
      }).toList();
    });
  }

  Future<void> _onUserSelected(VerifiedUser user) async {
    setState(() {
      _selectedUser = user;
      _isLoadingDetails = true;
      _selectedUserSubmission = null;
      _selectedApprovalNote = null;
      _selectedApprovedAt = null;
      _selectedApprovedBy = null;
    });

    try {
      final submissionData = await _dataService.getData("verificationSubmissions/${user.id}");
      if (mounted && submissionData != null) {
        setState(() {
          _selectedUserSubmission = VerificationSubmission.fromJson(user.id, submissionData);
          try { _selectedApprovalNote = (submissionData['approvalNote'] as String?)?.trim(); } catch (_) {}
          try { _selectedApprovedAt = (submissionData['approvedAt'] as String?)?.trim(); } catch (_) {}
          try { _selectedApprovedBy = (submissionData['approvedBy'] as String?)?.trim(); } catch (_) {}
        });
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _isLoadingDetails = false);
    }
  }

  // ==========================================
  // DESKTOP-STYLE DIALOGS START HERE
  // ==========================================

  Future<void> _handleUnverifyAction(String userId) async {
    if (_adminEmail == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Admin credentials not loaded.'), backgroundColor: Colors.red));
      return;
    }

    final reasonController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final userName = _selectedUser?.fullName ?? "this user";

    // 1. Ask for reason with a detailed, desktop dialog
    final String? reason = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        elevation: 24,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: Colors.grey.shade300))
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: Colors.red.shade700, size: 24),
                    const SizedBox(width: 12),
                    const Text('Revoke Verification', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: () => Navigator.of(context).pop(null),
                      splashRadius: 20,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              ),
              // Body
              Padding(
                padding: const EdgeInsets.all(24.0),
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      RichText(
                        text: TextSpan(
                          style: const TextStyle(color: Colors.black87, fontSize: 14, height: 1.4),
                          children: [
                            const TextSpan(text: 'You are about to unverify '),
                            TextSpan(text: userName.toTitleCase(), style: const TextStyle(fontWeight: FontWeight.bold)),
                            const TextSpan(text: '. This will remove their verified badge and restrict their access to verified-only features.'),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: Colors.red.shade200),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.info_outline, color: Colors.red, size: 20),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'This action will be recorded by the system and linked it to your admin account.',
                                style: TextStyle(color: Colors.red.shade900, fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Text('Reason for Revocation *', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: reasonController,
                        autofocus: true,
                        maxLines: 3,
                        decoration: InputDecoration(
                          hintText: 'e.g., Documents found to be invalid...',
                          border: const OutlineInputBorder(),
                          contentPadding: const EdgeInsets.all(12),
                          focusedBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: Colors.red.shade700, width: 2),
                            borderRadius: BorderRadius.circular(4)
                          )
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'A reason is strictly required.';
                          }
                          if (value.trim().length < 5) {
                            return 'Please provide a more detailed reason.';
                          }
                          return null;
                        },
                      ),
                    ],
                  ),
                ),
              ),
              // Footer
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(8)),
                  border: Border(top: BorderSide(color: Colors.grey.shade300)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                      ),
                      onPressed: () => Navigator.of(context).pop(null),
                      child: const Text('Cancel', style: TextStyle(color: Colors.black87)), 
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.gpp_bad, size: 18),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red.shade700, 
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                      ),
                      label: const Text('Proceed to Authorization'),
                      onPressed: () {
                        if (formKey.currentState!.validate()) {
                          Navigator.of(context).pop(reasonController.text.trim());
                        }
                      },
                    ),
                  ],
                ),
              )
            ],
          ),
        ),
      ),
    );

    if (reason == null) return;

    // 2. Ask for Password with improved dialog
    final password = await _showPasswordConfirmationDialog();
    if (password == null) return; 

    setState(() => _isProcessingAction = true);

    try {
      final isPasswordCorrect = await _dataService.verifyAdminPassword(_adminEmail!, password);
      if (!mounted) return;

      if (isPasswordCorrect) {
        await _unverifyUser(userId, reason);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Incorrect password. Action aborted.'), backgroundColor: Colors.red));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isProcessingAction = false);
    }
  }

  Future<String?> _showPasswordConfirmationDialog() async {
    final passwordController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    bool isPasswordObscured = true;

    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, dialogSetState) {
            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              elevation: 24,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 450),
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Header
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                        decoration: BoxDecoration(
                          border: Border(bottom: BorderSide(color: Colors.grey.shade300))
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.admin_panel_settings, color: themePrimaryColor, size: 24),
                            const SizedBox(width: 12),
                            const Text('Admin Authorization', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                            const Spacer(),
                            IconButton(
                              icon: const Icon(Icons.close, size: 20),
                              onPressed: () => Navigator.of(context).pop(null),
                              splashRadius: 20,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                          ],
                        ),
                      ),
                      // Body
                      Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'To finalize this action, please enter your admin password. This ensures secure handling of user data.',
                              style: TextStyle(color: Colors.black87, fontSize: 14, height: 1.4),
                            ),
                            const SizedBox(height: 20),
                            TextFormField(
                              controller: passwordController,
                              obscureText: isPasswordObscured,
                              autofocus: true,
                              decoration: InputDecoration(
                                labelText: 'Password',
                                border: const OutlineInputBorder(),
                                prefixIcon: const Icon(Icons.lock_outline),
                                suffixIcon: IconButton(
                                  icon: Icon(isPasswordObscured ? Icons.visibility_off : Icons.visibility),
                                  onPressed: () => dialogSetState(() => isPasswordObscured = !isPasswordObscured),
                                ),
                              ),
                              validator: (value) => (value == null || value.isEmpty) ? 'Password is required' : null,
                              onFieldSubmitted: (_) {
                                if (formKey.currentState?.validate() ?? false) {
                                  Navigator.of(context).pop(passwordController.text);
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                      // Footer
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: const BorderRadius.vertical(bottom: Radius.circular(8)),
                          border: Border(top: BorderSide(color: Colors.grey.shade300)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                              ),
                              onPressed: () => Navigator.of(context).pop(null),
                              child: const Text('Cancel', style: TextStyle(color: Colors.black87)), 
                            ),
                            const SizedBox(width: 12),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: themePrimaryColor, 
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                              ),
                              onPressed: () {
                                if (formKey.currentState?.validate() ?? false) {
                                  Navigator.of(context).pop(passwordController.text);
                                }
                              },
                              child: const Text('Confirm Action'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _unverifyUser(String userId, String reason) async {
    setState(() => _isLoading = true);
    try {
      await _dataService.updateData('users/$userId', {'isVerified': false});

      final Map<String, dynamic> revocationData = {
        'status': 'revoked',
        'revokedAt': DateTime.now().toUtc().toIso8601String(),
        'revokedBy': _adminEmail,
        'revocationReason': reason, 
      };

      final sub = await _dataService.getData('verificationSubmissions/$userId');
      if (sub == null || sub.isEmpty) {
        await _dataService.updateData('verificationSubmissions/$userId', revocationData);      
      } else {
        await _dataService.updateData('verificationSubmissions/$userId', revocationData);
      }

      final String userName = _selectedUser?.fullName ?? "Unknown User";
      await _logAction("Revoked verification for $userName. Reason: $reason");

      if (mounted) {
        // Detailed Success Dialog (Desktop style)
        await showDialog(
          context: context,
          builder: (ctx) => Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            elevation: 24,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 450),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Header
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    decoration: BoxDecoration(
                      border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.check_circle, color: Colors.green, size: 28),
                        const SizedBox(width: 12),
                        const Text(
                          "Verification Revoked", 
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)
                        ),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.close, size: 20),
                          onPressed: () => Navigator.of(ctx).pop(),
                          splashRadius: 20,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ],
                    ),
                  ),
                  // Body
                  Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        RichText(
                          text: TextSpan(
                            style: const TextStyle(fontSize: 15, color: Colors.black87),
                            children: [
                              TextSpan(text: userName.toTitleCase(), style: const TextStyle(fontWeight: FontWeight.bold)),
                              const TextSpan(text: " has been successfully unverified. Their status has been updated in the system."),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: Colors.grey.shade300)
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text("Logged Reason:", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black54, fontSize: 12)),
                              const SizedBox(height: 4),
                              Text(reason, style: const TextStyle(fontSize: 14, fontStyle: FontStyle.italic, color: Colors.black87)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Footer
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(8)),
                      border: Border(top: BorderSide(color: Colors.grey.shade300)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        ElevatedButton(
                          onPressed: () => Navigator.of(ctx).pop(),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: themePrimaryColor,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                          ),
                          child: const Text("Done", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                        )
                      ],
                    ),
                  )
                ],
              ),
            ),
          ),
        );
      }

      await _fetchVerifiedUsers();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Operation failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showImageDialog(BuildContext context, String imageUrl) {
    showDialog(
      context: context,
      builder: (BuildContext context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(40), // Desktop breathing room
        child: Stack(
          alignment: Alignment.center,
          children: [
            GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 800, maxHeight: 800), // Max window size
                child: InteractiveViewer(
                  child: Image.network(
                    imageUrl,
                    fit: BoxFit.contain,
                    loadingBuilder: (context, child, progress) =>
                        progress == null ? child : const Center(child: CircularProgressIndicator(color: Colors.white)),
                  ),
                ),
              ),
            ),
            // Added explicit close button for better UX
            Positioned(
              top: 0,
              right: 0,
              child: IconButton(
                icon: const Icon(Icons.cancel, color: Colors.white, size: 36),
                onPressed: () => Navigator.of(context).pop(),
                tooltip: 'Close Image',
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // END OF IMPROVED DIALOGS
  // ==========================================

  Future<void> _openGoogleMaps(String address) async {
    final trimmed = address.trim();
    if (trimmed.isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Address is empty')));
      return;
    }
    final encoded = Uri.encodeComponent(trimmed);
    final uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$encoded');

    final mode = kIsWeb ? LaunchMode.platformDefault : LaunchMode.externalApplication;
    try {
      final launched = await launchUrl(uri, mode: mode);
      if (!launched) throw 'Could not launch $uri';
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not open Google Maps: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: pageBackgroundColor,
      appBar: AppBar(
        title: const Text('Verified Users Directory'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 1,
      ),
      body: Stack(
        children: [
          Column(children: [_buildHeader(), Expanded(child: _buildBody())]),
          _buildDetailPanel(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(16.0),
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('All Verified Users', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(
            '${_filteredUsers.length} users found. Click on a user to view their details.',
            style: const TextStyle(color: Colors.grey, fontSize: 16),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search verified users...',
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              filled: true,
              fillColor: pageBackgroundColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_errorMessage != null) return Center(child: Text(_errorMessage!));
    if (_filteredUsers.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, size: 60, color: Colors.grey),
            SizedBox(height: 16),
            Text('No verified users found.', style: TextStyle(fontSize: 18, color: Colors.grey)),
          ],
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16.0),
      itemCount: _filteredUsers.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final user = _filteredUsers[index];
        
        String contactInfo = user.email;
        if (contactInfo.isEmpty && user.phoneNumber != null) {
          contactInfo = user.phoneNumber!;
        } else if (contactInfo.isEmpty) {
          contactInfo = 'No Contact Info';
        }

        return Material(
          color: _selectedUser?.id == user.id ? themeAccentColor : pageBackgroundColor,
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: CircleAvatar(
              radius: 24,
              backgroundColor: themePrimaryColor,
              child: Text(
                user.fullName.isNotEmpty ? user.fullName[0].toUpperCase() : '?',
                style: const TextStyle(fontSize: 20, color: Colors.white),
              ),
            ),
            title: Text(user.fullName.toTitleCase(), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            subtitle: Text(contactInfo, style: const TextStyle(fontSize: 14, color: Colors.grey)),
            trailing: const Icon(Icons.chevron_right, color: Colors.grey),
            onTap: () => _onUserSelected(user),
          ),
        );
      },
    );
  }

  String _formatDate(String? dateString) {
    if (dateString == null || dateString.isEmpty) {
      return 'N/A';
    }
    try {
      final DateTime date = DateTime.parse(dateString);
      return DateFormat.yMMMMd().format(date);
    } catch (e) {
      return dateString;
    }
  }
  
  Widget _buildDetailPanel() {
    String formatDateTime(String? iso) {
      if (iso == null || iso.isEmpty) return 'N/A';
      try {
        final dt = DateTime.parse(iso).toLocal();
        final y = dt.year.toString().padLeft(4, '0');
        final m = dt.month.toString().padLeft(2, '0');
        final d = dt.day.toString().padLeft(2, '0');
        final hh = dt.hour.toString().padLeft(2, '0');
        final mm = dt.minute.toString().padLeft(2, '0');
        return '$y-$m-$d $hh:$mm';
      } catch (_) {
        return iso;
      }
    }

    Color statusColor(String status) {
      switch (status.toLowerCase()) {
        case 'approved': return Colors.green.shade700;
        case 'rejected': return Colors.red.shade700;
        case 'revoked': return Colors.red.shade800;
        case 'pending': default: return Colors.orange.shade700;
      }
    }

    final s = _selectedUserSubmission;
    final docs = s?.supportingDocUrls ?? const <String>[];
    final approvalNote = _selectedApprovalNote;
    final approvedAt = _selectedApprovedAt;
    final approvedBy = _selectedApprovedBy;

    return AnimatedPositioned(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      top: 0,
      bottom: 0,
      right: _selectedUser != null ? 0 : -450,
      width: 450,
      child: Material(
        elevation: 8,
        child: Container(
          color: Colors.white,
          child: Column(
            children: [
              Container(
                color: pageBackgroundColor,
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Icon(Icons.person, color: themePrimaryColor),
                    const SizedBox(width: 8),
                    const Text('Resident Details', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const Spacer(),
                    IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => _selectedUser = null)),
                  ],
                ),
              ),
              Expanded(
                child: _isLoadingDetails
                    ? const Center(child: CircularProgressIndicator())
                    : _selectedUser == null
                        ? const SizedBox.shrink()
                        : SingleChildScrollView(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Center(
                                  child: CircleAvatar(
                                    radius: 40,
                                    backgroundColor: themePrimaryColor,
                                    child: Text(
                                      _selectedUser!.fullName.isNotEmpty ? _selectedUser!.fullName[0].toUpperCase() : '?',
                                      style: const TextStyle(fontSize: 32, color: Colors.white),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Center(
                                  child: Text(_selectedUser!.fullName.toTitleCase(), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                                ),
                                const SizedBox(height: 8),
                                Center(
                                  child: Chip(
                                    label: const Text('Verified'),
                                    backgroundColor: Colors.green.shade100,
                                    labelStyle: TextStyle(color: Colors.green.shade800),
                                    avatar: Icon(Icons.check_circle, color: Colors.green.shade800, size: 16),
                                  ),
                                ),

                                if (approvalNote != null && approvalNote.trim().isNotEmpty) ...[
                                  const SizedBox(height: 12),
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.green.shade50,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: Colors.green.shade100),
                                    ),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Icon(Icons.record_voice_over, color: Colors.green.shade700),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(approvalNote, style: TextStyle(fontWeight: FontWeight.w700, color: Colors.green.shade900)),
                                              if (approvedBy != null && approvedBy.trim().isNotEmpty) ...[
                                                const SizedBox(height: 6),
                                                Text('Approved by: $approvedBy', style: TextStyle(color: Colors.green.shade800)),
                                              ],
                                              if (approvedAt != null && approvedAt.trim().isNotEmpty) ...[
                                                const SizedBox(height: 6),
                                                Text('Approved: ${formatDateTime(approvedAt)}', style: TextStyle(color: Colors.grey.shade700)),
                                              ],
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],

                                const Divider(height: 30),

                                if (_selectedUser!.email.isNotEmpty)
                                  _buildInfoRow('Email Address', _selectedUser!.email),
                                if (_selectedUser!.phoneNumber != null)
                                  _buildInfoRow('Phone Number', _selectedUser!.phoneNumber!),

                                _buildInfoRow('Username', (_selectedUser!.username ?? 'N/A').toTitleCase()),
                                _buildAddressRow('Full Address', _selectedUser!.fullAddress),
                                _buildInfoRow('Date Registered', _formatDate(_selectedUser!.createdAt)),

                                if (s != null) ...[
                                  const Divider(height: 30),
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                        decoration: BoxDecoration(
                                          color: statusColor(s.status).withOpacity(0.10),
                                          borderRadius: BorderRadius.circular(20),
                                          border: Border.all(color: statusColor(s.status).withOpacity(0.3)),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              s.status.toLowerCase() == 'approved'
                                                  ? Icons.verified
                                                  : s.status.toLowerCase() == 'rejected'
                                                      ? Icons.cancel
                                                      : s.status.toLowerCase() == 'revoked'
                                                          ? Icons.gpp_bad
                                                          : Icons.hourglass_top,
                                              size: 18,
                                              color: statusColor(s.status),
                                            ),
                                            const SizedBox(width: 6),
                                            Text(s.status.toUpperCase(), style: TextStyle(fontWeight: FontWeight.w700, color: statusColor(s.status))),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          'Submitted: ${formatDateTime(s.submittedAt)}',
                                          style: TextStyle(color: Colors.grey.shade700),
                                          textAlign: TextAlign.right,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 16),

                                  Text('Submitted Documents', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey.shade700)),
                                  const SizedBox(height: 8),

                                  _buildInfoRow('ID Type', _formatLabel(s.idType ?? 'N/A')),
                                  
                                  ...s.fields.entries.map((entry) {
                                    final prettyLabel = _formatLabel(entry.key);
                                    return _buildInfoRow(prettyLabel, '${entry.value}');
                                  }),

                                  const SizedBox(height: 16),

                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Expanded(child: _buildImageCard('ID Image', s.idImageUrl)),
                                      const SizedBox(width: 16),
                                      Expanded(child: _buildImageCard('Selfie', s.selfieImageUrl)),
                                    ],
                                  ),

                                  if (docs.isNotEmpty) ...[
                                    const SizedBox(height: 16),
                                    const Text('Supporting Documents', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.black54)),
                                    const SizedBox(height: 8),
                                    Builder(builder: (context) {
                                      const double docImageHeight = 140;
                                      const double itemTotalHeight = docImageHeight + 40;
                                      return SizedBox(
                                        height: itemTotalHeight,
                                        child: ListView.separated(
                                          scrollDirection: Axis.horizontal,
                                          itemCount: docs.length,
                                          separatorBuilder: (_, __) => const SizedBox(width: 12),
                                          itemBuilder: (_, i) => SizedBox(
                                            width: 260,
                                            child: _buildDocImageCard('Document ${i + 1}', docs[i], imageHeight: docImageHeight),
                                          ),
                                        ),
                                      );
                                    }),
                                  ],
                                ],

                                const Divider(height: 40),

                                SizedBox(
                                  width: double.infinity,
                                  child: OutlinedButton.icon(
                                    icon: const Icon(Icons.gpp_bad_outlined),
                                    label: _isProcessingAction
                                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                                        : const Text('Unverify User'),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.red.shade700,
                                      side: BorderSide(color: Colors.red.shade700),
                                      padding: const EdgeInsets.symmetric(vertical: 16),
                                      textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                    ),
                                    onPressed: _isProcessingAction 
                                      ? null 
                                      : () => _handleUnverifyAction(_selectedUser!.id),
                                  ),
                                ),
                              ],
                            ),
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(), style: const TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          SelectableText(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildAddressRow(String label, String address) {
    final raw = address.trim();
    final display = raw.isEmpty ? 'N/A' : raw.toTitleCase();
    final isDisabled = raw.isEmpty || raw.toLowerCase() == 'n/a';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(), style: const TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: SelectableText(display, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500))),
              IconButton(
                tooltip: 'Open in Google Maps',
                icon: const Icon(Icons.location_on, color: themePrimaryColor),
                onPressed: isDisabled ? null : () => _openGoogleMaps(raw),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildImageCard(String title, String? imageUrl) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black54)),
        const SizedBox(height: 8),
        Card(
          clipBehavior: Clip.antiAlias,
          elevation: 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          child: InkWell(
            onTap: (imageUrl != null && imageUrl.isNotEmpty) ? () => _showImageDialog(context, imageUrl) : null,
            child: Container(
              height: 120,
              width: double.infinity,
              color: Colors.grey.shade100,
              child: (imageUrl == null || imageUrl.isEmpty)
                  ? const Center(child: Text('Not Provided'))
                  : Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.network(
                          imageUrl,
                          fit: BoxFit.contain,
                          loadingBuilder: (context, child, progress) =>
                              progress == null ? child : const Center(child: CircularProgressIndicator()),
                        ),
                        Positioned(
                          bottom: 4,
                          right: 4,
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(color: Colors.black.withOpacity(0.5), shape: BoxShape.circle),
                            child: const Icon(Icons.zoom_in, color: Colors.white, size: 16),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDocImageCard(String title, String? imageUrl, {double imageHeight = 140}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.black54)),
        const SizedBox(height: 6),
        Card(
          clipBehavior: Clip.antiAlias,
          elevation: 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          child: InkWell(
            onTap: (imageUrl != null && imageUrl.isNotEmpty) ? () => _showImageDialog(context, imageUrl) : null,
            child: Container(
              height: imageHeight,
              width: double.infinity,
              color: Colors.grey.shade100,
              child: (imageUrl == null || imageUrl.isEmpty)
                  ? const Center(child: Text('Not Provided', style: TextStyle(color: Colors.grey)))
                  : Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.network(
                          imageUrl,
                          fit: BoxFit.contain,
                          loadingBuilder: (context, child, progress) =>
                              progress == null ? child : const Center(child: CircularProgressIndicator()),
                          errorBuilder: (context, error, stack) => const Center(child: Icon(Icons.error, color: Colors.red)),
                        ),
                        Positioned(
                          bottom: 4,
                          right: 4,
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(color: Colors.black.withOpacity(0.5), shape: BoxShape.circle),
                            child: const Icon(Icons.zoom_in, color: Colors.white, size: 16),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ],
    );
  }
}