// lib/screens/submitted_requests_page.dart

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:url_launcher/url_launcher.dart';
import 'package:admin_window/users/non_verified_user.dart';
import 'package:admin_window/users/verification_submission.dart';
import 'package:admin_window/services/data_service.dart';
import 'package:admin_window/firebase_service.dart'; 
import 'package:admin_window/models/string_extensions.dart';

// Your finalized theme colors for consistency
const Color themePrimaryColor = Color(0xFF5E35B1); // Deep Purple
const Color themeAccentColor = Color(0xFFF3E5F5);  // Light Purple
const Color cardBackgroundColor = Colors.white;
const Color pageBackgroundColor = Color(0xFFF5F5F7);

class SubmittedRequestsPage extends StatefulWidget {
  final String token;
  const SubmittedRequestsPage({super.key, required this.token});

  @override
  _SubmittedRequestsPageState createState() => _SubmittedRequestsPageState();
}

class _SubmittedRequestsPageState extends State<SubmittedRequestsPage> {
  List<NonVerifiedUser> _allPendingUsers = [];
  List<NonVerifiedUser> _filteredUsers = [];
  final TextEditingController _searchController = TextEditingController();
  NonVerifiedUser? _selectedUser;
  VerificationSubmission? _selectedUserSubmission;
  bool _isLoadingList = true;
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
    _fetchPendingSubmissions();
    _searchController.addListener(_filterUsers);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _dataService.close(); 
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
      if (mounted) {
        setState(() {
          _adminEmail = email;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not retrieve admin credentials: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _logAction(String message) async {
    if (_adminEmail != null) {
      try {
        await _firebaseService.recordAdminLog(widget.token, message, _adminEmail!);
      } catch (e) {
        print("Failed to log action: $e");
      }
    }
  }

  bool _hasSubmissionContent(Map<String, dynamic> sub) {
    final idImg = (sub['idImageUrl'] as String?)?.isNotEmpty == true;
    final selfie = (sub['selfieImageUrl'] as String?)?.isNotEmpty == true;
    final docs = (sub['supportingDocUrls'] is List) && (sub['supportingDocUrls'] as List).isNotEmpty;
    final fieldsMap = sub['fields'];
    final hasFieldsMap = fieldsMap is Map && fieldsMap.isNotEmpty;
    final submittedAt = (sub['submittedAt'] as String?)?.isNotEmpty == true;

    const meta = {
      'status', 'rejectionReason', 'approvalNote', 'approvedAt', 
      'approvedBy', 'revokedAt', 'revokedBy', 'userId', 'idType', 
    };

    final hasLegacyFields = sub.keys.any((k) =>
      !meta.contains(k) &&
      k != 'idImageUrl' &&
      k != 'selfieImageUrl' &&
      k != 'supportingDocUrls' &&
      k != 'fields' &&
      k != 'submittedAt'
    );

    return idImg || selfie || docs || hasFieldsMap || submittedAt || hasLegacyFields;
  }

  Future<void> _fetchPendingSubmissions() async {
    setState(() {
      _isLoadingList = true;
      _errorMessage = null; 
      _selectedUser = null;
      _selectedUserSubmission = null;
    });

    try {
      final usersData = await _dataService.getData("users");
      final submissionsData = await _dataService.getData("verificationSubmissions");

      if (!mounted) return;

      final List<NonVerifiedUser> users = [];
      if (usersData != null && submissionsData != null) {
        final Set<String> pendingUserIds = {};
        submissionsData.forEach((userId, submissionData) {
          if (submissionData is Map) {
            final status = (submissionData['status'] as String?)?.toLowerCase();
            final hasContent = _hasSubmissionContent(Map<String, dynamic>.from(submissionData));
            if (status == 'pending' && hasContent) {
              pendingUserIds.add(userId);
            }
          }
        });

        for (var userId in pendingUserIds) {
          if (usersData.containsKey(userId)) {
            users.add(NonVerifiedUser.fromJson(userId, usersData[userId]));
          }
        }
      }

      setState(() {
        _allPendingUsers = users;
        _filteredUsers = users;
        _isLoadingList = false;
      });

    } catch (e) {
      print("Failed to fetch submissions (continuing to show loading): $e");
    }
  }

  void _filterUsers() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredUsers = _allPendingUsers.where((user) {
        final nameLower = user.fullName.toLowerCase();
        final emailLower = user.email.toLowerCase();
        final phoneLower = (user.phoneNumber ?? "").toLowerCase();
        return nameLower.contains(query) || emailLower.contains(query) || phoneLower.contains(query);
      }).toList();
    });
  }

  Future<void> _onUserSelected(NonVerifiedUser user) async {
    setState(() {
      _selectedUser = user;
      _isLoadingDetails = true;
      _selectedUserSubmission = null;
    });
    try {
      final submissionData = await _dataService.getData("verificationSubmissions/${user.id}");
      if (submissionData != null) {
        if (mounted) {
          setState(() {
            _selectedUserSubmission = VerificationSubmission.fromJson(user.id, submissionData);
          });
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not load documents for this user: $e')));
    } finally {
      if (mounted) setState(() => _isLoadingDetails = false);
    }
  }

  // ==========================================
  // DESKTOP-STYLE DIALOGS START HERE
  // ==========================================

  Future<void> _handleVerificationAction({
    required bool isApproved,
    required String userId,
  }) async {
    if (_adminEmail == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Admin credentials not loaded. Cannot proceed.'), backgroundColor: Colors.red),
      );
      return;
    }

    final userName = _selectedUser?.fullName ?? "this user";
    String? adminNote;

    // 1. Show Approve or Reject Dialog
    if (isApproved) {
      adminNote = await _showApproveDialog(userName);
      if (adminNote == null) return; // User canceled
    } else {
      adminNote = await _showRejectDialog(userName);
      if (adminNote == null) return; // User canceled
    }

    // 2. Show Password Authorization
    final password = await _showPasswordConfirmationDialog();
    if (password == null) return; // User canceled password entry

    setState(() { _isProcessingAction = true; });

    try {
      final isPasswordCorrect = await _dataService.verifyAdminPassword(_adminEmail!, password);
      if (!mounted) return;

      if (isPasswordCorrect) {
        await _processVerification(userId, isApproved, adminNote: adminNote);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Incorrect password. Action canceled.'), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('An error occurred: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() { _isProcessingAction = false; });
    }
  }

  Future<void> _processVerification(String userId, bool isApproved, {String? adminNote}) async {
    setState(() => _isProcessingAction = true);
    final userName = _selectedUser?.fullName ?? "Unknown User";

    try {
      if (isApproved) {
        await _dataService.updateData('users/$userId', {'isVerified': true});
        await _dataService.updateData('verificationSubmissions/$userId', {
          'status': 'approved',
          'approvedBy': _adminEmail,
          'approvedAt': DateTime.now().toIso8601String(),
          if (adminNote != null && adminNote.isNotEmpty) 'approvalNote': adminNote,
        });
        
        await _logAction("Approved online verification for: $userName.");

        if (mounted) {
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
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey.shade300))),
                      child: const Row(
                        children: [
                          Icon(Icons.check_circle, color: Colors.green, size: 28),
                          SizedBox(width: 12),
                          Text("Request Approved", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Text("${userName.toTitleCase()} has been officially verified and granted full access.", style: const TextStyle(fontSize: 15)),
                    ),
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
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4))
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
      } else {
        final submissionUpdate = {
          'status': 'rejected',
          'rejectionReason': adminNote ?? 'No reason provided.',
          'processedAt': DateTime.now().toIso8601String(),
          'rejectedBy': _adminEmail
        };
        await _dataService.updateData('verificationSubmissions/$userId', submissionUpdate);
        
        await _logAction("Rejected verification for: $userName. Reason: $adminNote");

        if (mounted) {
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
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey.shade300))),
                      child: const Row(
                        children: [
                          Icon(Icons.cancel, color: Colors.red, size: 28),
                          SizedBox(width: 12),
                          Text("Request Rejected", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.all(24.0),
                      child: Text("The verification request has been rejected. The user will be notified of the reason so they can re-submit.", style: TextStyle(fontSize: 15)),
                    ),
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
                              backgroundColor: Colors.grey.shade800, 
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4))
                            ),
                            child: const Text("Close", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
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
      }
      await _fetchPendingSubmissions();
    } catch(e) { 
      print("Error processing verification: $e");
      if (mounted) {
         ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red));
      }
    } finally { 
      if (mounted) setState(() => _isProcessingAction = false); 
    }
  }

  Future<String?> _showApproveDialog(String userName) async {
    final noteController = TextEditingController();

    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          elevation: 24,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey.shade300))),
                  child: Row(
                    children: [
                      const Icon(Icons.verified, color: Colors.green, size: 24),
                      const SizedBox(width: 12),
                      const Text('Approve Request', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close, size: 20),
                        onPressed: () => Navigator.of(context).pop(null),
                        splashRadius: 20,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      )
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: Colors.green.shade200),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline, color: Colors.green.shade700, size: 20),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'You are about to approve ${userName.toTitleCase()}. They will gain full access to verified features.',
                                style: TextStyle(color: Colors.green.shade900, fontSize: 14),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      const Text('Admin Note (Optional)', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: noteController,
                        maxLines: 2,
                        maxLength: 150,
                        decoration: InputDecoration(
                          hintText: 'e.g., Documents verified and match system records.',
                          border: const OutlineInputBorder(),
                          contentPadding: const EdgeInsets.all(12),
                          focusedBorder: OutlineInputBorder(
                            borderSide: const BorderSide(color: Colors.green, width: 2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
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
                        icon: const Icon(Icons.check, size: 18),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green.shade700,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                        ),
                        onPressed: () {
                          Navigator.of(context).pop(noteController.text.trim());
                        },
                        label: const Text('Proceed to Authorization'),
                      )
                    ],
                  ),
                )
              ],
            ),
          ),
        );
      },
    );
  }

  Future<String?> _showRejectDialog(String userName) async {
    final noteController = TextEditingController();
    String? selectedReason;
    final reasons = ['Blurry/Unreadable ID', 'Mismatched Information', 'Expired Document', 'Selfie Does Not Match', 'Other'];
    final formKey = GlobalKey<FormState>();

    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          elevation: 24,
          child: StatefulBuilder(
            builder: (context, setState) {
              return ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 550),
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey.shade300))),
                        child: Row(
                          children: [
                            Icon(Icons.cancel, color: Colors.red.shade700, size: 24),
                            const SizedBox(width: 12),
                            const Text('Reject Request', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                            const Spacer(),
                            IconButton(
                              icon: const Icon(Icons.close, size: 20),
                              onPressed: () => Navigator.of(context).pop(null),
                              splashRadius: 20,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            )
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Select Rejection Reason *', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: reasons.map((r) {
                                final isSelected = selectedReason == r;
                                return ChoiceChip(
                                  label: Text(r),
                                  selected: isSelected,
                                  selectedColor: Colors.red.shade600,
                                  backgroundColor: Colors.grey.shade100,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(4),
                                    side: BorderSide(color: isSelected ? Colors.red.shade600 : Colors.grey.shade300),
                                  ),
                                  labelStyle: TextStyle(
                                    color: isSelected ? Colors.white : Colors.black87,
                                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                  ),
                                  onSelected: (sel) {
                                    setState(() {
                                      if (sel) {
                                        selectedReason = r;
                                        if (r != 'Other') {
                                          noteController.text = r;
                                        } else {
                                          noteController.clear();
                                        }
                                      } else {
                                        selectedReason = null;
                                        noteController.clear();
                                      }
                                    });
                                  },
                                );
                              }).toList(),
                            ),
                            const SizedBox(height: 24),
                            const Text('Detailed Note (Required for User) *', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                            const SizedBox(height: 8),
                            TextFormField(
                              controller: noteController,
                              maxLines: 3,
                              maxLength: 250,
                              decoration: InputDecoration(
                                hintText: 'Please provide clear instructions on what the user needs to fix...',
                                border: const OutlineInputBorder(),
                                contentPadding: const EdgeInsets.all(12),
                                focusedBorder: OutlineInputBorder(
                                  borderSide: BorderSide(color: Colors.red.shade700, width: 2),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'A reason is strictly required so the user knows what to fix.';
                                }
                                return null;
                              },
                            ),
                          ],
                        ),
                      ),
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
                              onPressed: selectedReason == null
                                  ? null
                                  : () {
                                      if (formKey.currentState!.validate()) {
                                        Navigator.of(context).pop(noteController.text.trim());
                                      }
                                    },
                              label: const Text('Proceed to Authorization'),
                            )
                          ],
                        ),
                      )
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
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
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey.shade300))),
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
                      Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Please enter your admin password to securely confirm this action.', style: TextStyle(color: Colors.black87, fontSize: 14)),
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

  void _showImageDialog(BuildContext context, String imageUrl) {
    showDialog(
      context: context,
      builder: (BuildContext context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(40), 
        child: Stack(
          alignment: Alignment.center,
          children: [
            GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 800, maxHeight: 800), 
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

  Future<void> _openGoogleMaps(String address) async {
    final trimmed = address.trim();
    if (trimmed.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Address is empty')));
      }
      return;
    }
    final encoded = Uri.encodeComponent(trimmed);
    final uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$encoded');

    final mode = kIsWeb ? LaunchMode.platformDefault : LaunchMode.externalApplication;
    try {
      final launched = await launchUrl(uri, mode: mode);
      if (!launched) {
        throw 'Could not launch $uri';
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not open Google Maps: $e')));
      }
    }
  }

  // ==========================================================
  // Build Methods
  // ==========================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: pageBackgroundColor,
      appBar: AppBar(
        title: const Text('Pending Verification Requests'),
        backgroundColor: cardBackgroundColor,
        foregroundColor: Colors.black87,
        elevation: 1,
      ),
      body: Row(
        children: [
          Container(width: 350, color: cardBackgroundColor, child: _buildUserListPane()),
          const VerticalDivider(width: 1),
          Expanded(child: AnimatedSwitcher(duration: const Duration(milliseconds: 200), child: _buildDetailView())),
        ],
      ),
    );
  }

  Widget _buildUserListPane() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search by Name or Email...',
              prefixIcon: const Icon(Icons.search, size: 20),
              isDense: true,
              filled: true,
              fillColor: pageBackgroundColor,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(icon: const Icon(Icons.clear, size: 20), onPressed: _searchController.clear)
                  : null,
            ),
          ),
        ),
        Expanded(child: _buildUserList()),
      ],
    );
  }

   Widget _buildUserList() {
    if (_isLoadingList) return const Center(child: CircularProgressIndicator());
    if (_errorMessage != null) return Center(child: Text(_errorMessage!));
    if (_filteredUsers.isEmpty) {
      return const Center(child: Text('No pending submissions.', style: TextStyle(color: Colors.grey)));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: _filteredUsers.length,
      itemBuilder: (context, index) {
        final user = _filteredUsers[index];
        final isSelected = _selectedUser?.id == user.id;
        
        String contactInfo = user.email;
        if ((contactInfo.isEmpty || contactInfo == 'N/A') && user.phoneNumber != null) {
          contactInfo = user.phoneNumber!;
        }

        return Card(
          elevation: 0,
          margin: const EdgeInsets.symmetric(vertical: 4),
          color: isSelected ? themeAccentColor : Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: isSelected ? themePrimaryColor : themeAccentColor,
              child: Text(
                user.fullName.isNotEmpty ? user.fullName[0].toUpperCase() : '?',
                style: TextStyle(color: isSelected ? Colors.white : themePrimaryColor, fontWeight: FontWeight.bold),
              ),
            ),
            title: Text(
              user.fullName.toTitleCase(),
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: isSelected ? themePrimaryColor : Colors.black87),
            ),
            subtitle: Text(contactInfo, style: TextStyle(fontSize: 14, color: Colors.grey[600])),
            trailing: const Chip(label: Text('Pending'), backgroundColor: Colors.orangeAccent, labelStyle: TextStyle(color: Colors.white, fontSize: 12)),
            onTap: () => _onUserSelected(user),
          ),
        );
      },
    );
  }

  Widget _buildDetailView() {
    if (_isLoadingDetails) {
      return Container(key: const ValueKey('loading'), child: const Center(child: CircularProgressIndicator()));
    }
    if (_selectedUser == null) {
      return Container(
        key: const ValueKey('placeholder'),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.rule_folder_outlined, size: 80, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text('Select a submission to review', style: TextStyle(fontSize: 22, color: Colors.grey[600])),
          ],
        ),
      );
    }
    return Container(
      key: ValueKey(_selectedUser!.id),
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 48.0, vertical: 32.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader('User Profile'),
            const SizedBox(height: 16),
            Card(
              elevation: 1,
              color: cardBackgroundColor,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 16.0),
                child: Column(
                  children: [
                    _buildInfoCard(Icons.badge_outlined, 'Full Name', _selectedUser!.fullName.toTitleCase()),
                    
                    if (_selectedUser!.email.isNotEmpty && _selectedUser!.email != 'N/A')
                       _buildInfoCard(Icons.email_outlined, 'Email', _selectedUser!.email),
                    
                    if (_selectedUser!.phoneNumber != null)
                       _buildInfoCard(Icons.phone_android, 'Phone Number', _selectedUser!.phoneNumber!),

                    _buildInfoCard(Icons.account_circle_outlined, 'Username', _selectedUser!.username ?? 'N/A'),
                    _buildAddressInfoCard(Icons.pin_drop_outlined, 'Birthplace Address', _selectedUser!.fullAddress),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 32),
            _buildSectionHeader('Submitted Documents'),
            const SizedBox(height: 16),
            _buildSubmissionContent(),
          ],
        ),
      ),
    );
  }

  Widget _buildSubmissionContent() {
    final s = _selectedUserSubmission;
    if (s == null) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: Colors.yellow[100], borderRadius: BorderRadius.circular(8)),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.info_outline, color: Colors.orange),
            SizedBox(width: 16),
            Text('Could not load submission details.', style: TextStyle(fontSize: 16)),
          ],
        ),
      );
    }

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
        case 'pending': default: return Colors.orange.shade700;
      }
    }

    final docs = s.supportingDocUrls;

    return Card(
      elevation: 1,
      color: cardBackgroundColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
                        s.status.toLowerCase() == 'approved' ? Icons.verified
                        : s.status.toLowerCase() == 'rejected' ? Icons.cancel
                        : Icons.hourglass_top,
                        size: 18,
                        color: statusColor(s.status),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        s.status.toUpperCase(),
                        style: TextStyle(fontWeight: FontWeight.w700, color: statusColor(s.status)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Date Submitted: ${formatDateTime(s.submittedAt)}',
                    style: TextStyle(color: Colors.grey[700]),
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),
            _buildInfoCard(Icons.credit_card_outlined, 'ID/Document Type', _formatLabel(s.idType ?? 'N/A')),

            ...s.fields.entries.map((entry) {
              final prettyLabel = _formatLabel(entry.key);
              return _buildInfoCard(Icons.notes_outlined, prettyLabel, '${entry.value}');
            }),
            
            const SizedBox(height: 24),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _buildImageCard('ID/Document Image', s.idImageUrl)),
                const SizedBox(width: 24),
                Expanded(child: _buildImageCard('Selfie with ID', s.selfieImageUrl)),
              ],
            ),

            if (docs.isNotEmpty) ...[
              const SizedBox(height: 32),
              const Padding(
                padding: EdgeInsets.only(left: 4.0),
                child: Text('Supporting Documents', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black54)),
              ),
              const SizedBox(height: 8),
              Builder(builder: (context) {
                const double docImageHeight = 180;
                const double itemTotalHeight = docImageHeight + 40;
                return SizedBox(
                  height: itemTotalHeight,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: docs.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 12),
                    itemBuilder: (_, i) => SizedBox(
                      width: 280,
                      child: _buildDocImageCard('Document ${i + 1}', docs[i], imageHeight: docImageHeight),
                    ),
                  ),
                );
              }),
            ],

            const SizedBox(height: 40),
            const Divider(),
            const SizedBox(height: 16),

            // ---- NEW ACTION BUTTONS ----
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.cancel_outlined),
                    label: _isProcessingAction
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Reject Request'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red.shade700,
                      side: BorderSide(color: Colors.red.shade700, width: 1.5),
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                      textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    onPressed: _isProcessingAction ? null : () => _handleVerificationAction(isApproved: false, userId: _selectedUser!.id),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.check_circle_outline, color: Colors.white),
                    label: _isProcessingAction
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text('Approve Request'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green.shade700,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                      textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    onPressed: _isProcessingAction ? null : () => _handleVerificationAction(isApproved: true, userId: _selectedUser!.id),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // --- UI BUILD HELPERS ---
  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4.0, bottom: 4.0),
      child: Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.black87)),
    );
  }

  Widget _buildInfoCard(IconData icon, String label, String value) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: themeAccentColor,
        child: Icon(icon, size: 22, color: themePrimaryColor),
      ),
      title: Text(label, style: TextStyle(fontSize: 14, color: Colors.grey[600])),
      subtitle: SelectableText(
        value,
        style: const TextStyle(fontSize: 17, color: Colors.black87, fontWeight: FontWeight.w500),
      ),
    );
  }

  Widget _buildAddressInfoCard(IconData icon, String label, String address) {
    final raw = address.trim();
    final display = raw.isEmpty ? 'N/A' : raw.toTitleCase();
    final isDisabled = raw.isEmpty || raw.toLowerCase() == 'n/a';

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: themeAccentColor,
        child: Icon(icon, size: 22, color: themePrimaryColor),
      ),
      title: Text(label, style: TextStyle(fontSize: 14, color: Colors.grey[600])),
      subtitle: SelectableText(
        display,
        style: const TextStyle(fontSize: 17, color: Colors.black87, fontWeight: FontWeight.w500),
      ),
      trailing: IconButton(
        tooltip: 'Open in Google Maps',
        icon: const Icon(Icons.location_on, color: themePrimaryColor),
        onPressed: isDisabled ? null : () => _openGoogleMaps(raw),
      ),
    );
  }

  Widget _buildDocImageCard(String title, String? imageUrl, {double imageHeight = 180}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4.0),
          child: Text(
            title,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.black54),
          ),
        ),
        const SizedBox(height: 6),
        Card(
          clipBehavior: Clip.antiAlias,
          elevation: 2,
          shadowColor: Colors.black.withOpacity(0.1),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                          errorBuilder: (context, error, stack) =>
                              const Center(child: Icon(Icons.error, color: Colors.red)),
                        ),
                        Positioned(
                          bottom: 8,
                          right: 8,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(color: Colors.black.withOpacity(0.5), shape: BoxShape.circle),
                            child: const Icon(Icons.zoom_in, color: Colors.white, size: 20),
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

  Widget _buildImageCard(String title, String? imageUrl) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4.0),
          child: Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black54),
          ),
        ),
        const SizedBox(height: 8),
        Card(
          clipBehavior: Clip.antiAlias,
          elevation: 2,
          shadowColor: Colors.black.withOpacity(0.1),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: InkWell(
            onTap: (imageUrl != null && imageUrl.isNotEmpty) ? () => _showImageDialog(context, imageUrl) : null,
            child: Container(
              height: 250,
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
                          errorBuilder: (context, error, stack) =>
                              const Center(child: Icon(Icons.error, color: Colors.red)),
                        ),
                        Positioned(
                          bottom: 8,
                          right: 8,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(color: Colors.black.withOpacity(0.5), shape: BoxShape.circle),
                            child: const Icon(Icons.zoom_in, color: Colors.white, size: 20),
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