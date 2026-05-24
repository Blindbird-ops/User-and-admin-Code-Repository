// lib/users/non_verified_users_page.dart

import 'package:flutter/material.dart';
import 'package:admin_window/users/non_verified_user.dart';
import 'package:admin_window/services/data_service.dart';
import 'package:admin_window/firebase_service.dart'; 
import 'package:intl/intl.dart';
import 'package:admin_window/models/string_extensions.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:admin_window/users/verification_submission.dart'; 

const Color themePrimaryColor = Color(0xFF5E35B1); // Deep Purple
const Color themeAccentColor = Color(0xFFF3E5F5);  // Light Purple
const Color cardBackgroundColor = Colors.white;
const Color pageBackgroundColor = Color(0xFFF5F5F7);

class NonVerifiedUsersPage extends StatefulWidget {
  final String token;
  const NonVerifiedUsersPage({super.key, required this.token});

  @override
  _NonVerifiedUsersPageState createState() => _NonVerifiedUsersPageState();
}

class _NonVerifiedUsersPageState extends State<NonVerifiedUsersPage> {
  // --- State ---
  List<NonVerifiedUser> _allNonVerifiedUsers = [];
  List<NonVerifiedUser> _filteredUsers = [];
  final TextEditingController _searchController = TextEditingController();
  NonVerifiedUser? _selectedUser;
  VerificationSubmission? _selectedUserSubmission; 

  bool _isLoadingList = true;
  bool _isLoadingDetails = false;
  late final DataService _dataService;
  
  final FirebaseService _firebaseService = FirebaseService(); 

  String? _adminEmail;
  bool _isProcessingAction = false;

  @override
  void initState() {
    super.initState();
    _dataService = DataService(); 
    _fetchAdminEmail();
    _fetchNonVerifiedUsers();
    _searchController.addListener(_filterUsers);
  }

  @override
  void dispose() {
    _searchController.dispose();
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

  Future<void> _fetchNonVerifiedUsers() async {
    setState(() {
      _isLoadingList = true;
      _selectedUser = null;
    });

    try {
      final usersData = await _dataService.getData("users");
      if (!mounted) return;

      final List<NonVerifiedUser> users = [];
      if (usersData != null) {
        usersData.forEach((userId, userData) {
          final isVerified = userData['isVerified'] as bool? ?? false;
          if (userData['role'] == 'user' && !isVerified) {
            users.add(NonVerifiedUser.fromJson(userId, userData));
          }
        });
      }

      setState(() {
        _allNonVerifiedUsers = users;
        _filteredUsers = users;
        _isLoadingList = false;
      });
    } catch (e) {
      print("Failed to fetch non-verified users: $e");
    }
  }

  void _filterUsers() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredUsers = _allNonVerifiedUsers.where((user) {
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
      print("Error loading submission: $e");
    } finally {
      if (mounted) setState(() => _isLoadingDetails = false);
    }
  } 

  // ==========================================
  // DESKTOP-STYLE DIALOGS START HERE
  // ==========================================

  Future<void> _executeSecureAction({
    required String userId,
    required bool isApproved,
    String? approvalNote,
  }) async {
    if (_adminEmail == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Admin credentials not loaded.'), backgroundColor: Colors.red));
      return;
    }

    // 1. Ask for Password
    final password = await _showPasswordConfirmationDialog();
    if (password == null) return; 

    setState(() => _isProcessingAction = true);

    try {
      // 2. Verify Password
      final isPasswordCorrect = await _dataService.verifyAdminPassword(_adminEmail!, password);
      if (!mounted) return;

      if (isPasswordCorrect) {
        // 3. Process
        await _processVerification(userId, isApproved, approvalNote: approvalNote);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Incorrect password. Action aborted.'), backgroundColor: Colors.red));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isProcessingAction = false);
    }
  }

  Future<void> _processVerification(String userId, bool isApproved, {String? approvalNote}) async {
    setState(() => _isLoadingList = true);
    try {
      await _dataService.updateData('users/$userId', {'isVerified': isApproved});

      final submissionUpdate = {
        'status': isApproved ? 'approved' : 'rejected',
        if (approvalNote != null) 'approvalNote': approvalNote,
        if (isApproved) 'approvedAt': DateTime.now().toUtc().toIso8601String(),
        if (isApproved) 'approvedBy': _adminEmail 
      };

      await _dataService.updateData('verificationSubmissions/$userId', submissionUpdate);
      
      final String userName = _selectedUser?.fullName ?? "Unknown User";
      await _logAction("Approved (In-Person) verification for: $userName. Note: $approvalNote");

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
                          "Action Successful", 
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
                              TextSpan(text: isApproved ? " has been officially verified." : " status has been updated."),
                            ],
                          ),
                        ),
                        if (approvalNote != null && approvalNote.isNotEmpty) ...[
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
                                const Text("Admin Note:", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black54, fontSize: 12)),
                                const SizedBox(height: 4),
                                Text(approvalNote, style: const TextStyle(fontSize: 14, fontStyle: FontStyle.italic, color: Colors.black87)),
                              ],
                            ),
                          ),
                        ]
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
                          child: const Text("OK", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
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

      await _fetchNonVerifiedUsers();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Operation failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoadingList = false);
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
                      // Desktop Header
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
                      // Desktop Body
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
                      // Desktop Footer
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

  Future<String?> _showInPersonApprovalDialog() async {
    final noteController = TextEditingController();
    DateTime selectedDate = DateTime.now();
    String? selectedReason;
    final reasons = ['No ID Provided', 'Verified by Relative', 'Barangay Record Match', 'Other'];
    final userName = _selectedUser?.fullName ?? "this user";

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
                constraints: const BoxConstraints(maxWidth: 600), // Wide Desktop Window
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // --- Header ---
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                      decoration: BoxDecoration(
                        border: Border(bottom: BorderSide(color: Colors.grey.shade300))
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.how_to_reg, color: themePrimaryColor, size: 24), 
                          const SizedBox(width: 12), 
                          const Text(
                            'In-Person Verification', 
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)
                          ), 
                          const Spacer(),
                          IconButton(
                            icon: const Icon(Icons.close, size: 20), 
                            onPressed: () => Navigator.of(context).pop(null),
                            splashRadius: 20,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          )
                        ]
                      ),
                    ),
                    
                    // --- Body ---
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start, 
                        children: [
                          // Information Alert Box
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.blue.shade50,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: Colors.blue.shade200),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.info_outline, color: Colors.blue.shade700, size: 20),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    'Use this to manually verify ${userName.toTitleCase()} if they presented physical documents at the barangay hall.',
                                    style: TextStyle(color: Colors.blue.shade900, fontSize: 13),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),
                          
                          // Form Grid
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                flex: 2,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('Primary Reason *', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                                    const SizedBox(height: 8),
                                    Wrap(
                                      spacing: 8, 
                                      runSpacing: 8, 
                                      children: reasons.map((r) {
                                        final isSelected = selectedReason == r;
                                        return ChoiceChip(
                                          label: Text(r), 
                                          selected: isSelected, 
                                          selectedColor: themePrimaryColor, 
                                          backgroundColor: Colors.grey.shade100,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(4),
                                            side: BorderSide(color: isSelected ? themePrimaryColor : Colors.grey.shade300)
                                          ), 
                                          labelStyle: TextStyle(
                                            color: isSelected ? Colors.white : Colors.black87,
                                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal
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
                                          }
                                        );
                                      }).toList()
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 24),
                              Expanded(
                                flex: 1,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('Verification Date', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                                    const SizedBox(height: 8),
                                    InkWell(
                                      onTap: () async {
                                        final picked = await showDatePicker(
                                          context: context, 
                                          initialDate: selectedDate, 
                                          firstDate: DateTime(2000), 
                                          lastDate: DateTime.now()
                                        ); 
                                        if (picked != null) setState(() => selectedDate = picked); 
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                        decoration: BoxDecoration(
                                          border: Border.all(color: Colors.grey.shade400),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(DateFormat('MMM dd, yyyy').format(selectedDate), style: const TextStyle(fontSize: 14)),
                                            const Icon(Icons.calendar_today, size: 16, color: Colors.grey),
                                          ],
                                        ),
                                      ),
                                    )
                                  ],
                                ),
                              )
                            ],
                          ),
                          const SizedBox(height: 24),
                          
                          const Text('Additional Notes', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: noteController, 
                            maxLines: 3, 
                            maxLength: 250, 
                            decoration: InputDecoration(
                              hintText: 'e.g., Verified by Admin via physical ID check...', 
                              border: const OutlineInputBorder(),
                              contentPadding: const EdgeInsets.all(12),
                              focusedBorder: OutlineInputBorder(
                                borderSide: const BorderSide(color: themePrimaryColor, width: 2),
                                borderRadius: BorderRadius.circular(4)
                              )
                            )
                          ),
                        ]
                      ),
                    ),

                    // --- Footer ---
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
                            child: const Text('Cancel', style: TextStyle(color: Colors.black87))
                          ), 
                          const SizedBox(width: 12), 
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: themePrimaryColor, 
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                            ), 
                            onPressed: selectedReason == null 
                              ? null 
                              : () {
                                  final note = noteController.text.trim();
                                  final result = note.isEmpty 
                                      ? 'Approved in person: ${selectedReason ?? 'Verified at Barangay Hall'} on ${DateFormat.yMMMd().format(selectedDate)}' 
                                      : note;
                                  Navigator.of(context).pop(result);
                                }, 
                            child: const Text('Proceed to Authorization')
                          )
                        ]
                      ),
                    )
                  ],
                ),
              );
            },
          ),
        );
      },
    );
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
    if (trimmed.isEmpty) return;
    final encoded = Uri.encodeComponent(trimmed);
    final uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$encoded');
    try { await launchUrl(uri, mode: LaunchMode.externalApplication); } catch (_) {}
  }

  // --- UI BUILD ---
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: pageBackgroundColor,
      appBar: AppBar(title: const Text('Non-Verified Users Management'), backgroundColor: const Color.fromARGB(255, 97, 147, 245), foregroundColor: Colors.white, elevation: 1),
      body: Row(children: [Container(width: 350, color: cardBackgroundColor, child: _buildUserListPane()), const VerticalDivider(width: 1), Expanded(child: AnimatedSwitcher(duration: const Duration(milliseconds: 200), child: _buildDetailView()))]),
    );
  }

  Widget _buildUserListPane() {
    return Column(children: [
      Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 8), child: TextField(controller: _searchController, decoration: InputDecoration(hintText: 'Search by Name, Email, Phone...', prefixIcon: const Icon(Icons.search), filled: true, fillColor: pageBackgroundColor, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none), suffixIcon: _searchController.text.isNotEmpty ? IconButton(icon: const Icon(Icons.clear), onPressed: _searchController.clear) : null))),
      Expanded(child: _buildUserList()),
    ]);
  }

  Widget _buildUserList() {
    if (_isLoadingList) return const Center(child: CircularProgressIndicator());
    if (_filteredUsers.isEmpty) return const Center(child: Text('No users found.', style: TextStyle(color: Colors.grey)));
    return ListView.builder(padding: const EdgeInsets.all(8), itemCount: _filteredUsers.length, itemBuilder: (context, index) {
      final user = _filteredUsers[index];
      final isSelected = _selectedUser?.id == user.id;
      
      String contactInfo = user.email;
      if ((contactInfo.isEmpty || contactInfo == 'N/A') && user.phoneNumber != null) {
        contactInfo = user.phoneNumber!;
      }

      return Card(elevation: 0, margin: const EdgeInsets.symmetric(vertical: 4), color: isSelected ? themeAccentColor : Colors.transparent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)), child: ListTile(leading: CircleAvatar(backgroundColor: isSelected ? themePrimaryColor : themeAccentColor, child: Text(user.fullName.isNotEmpty ? user.fullName[0].toUpperCase() : '?', style: TextStyle(color: isSelected ? Colors.white : themePrimaryColor, fontWeight: FontWeight.bold))), title: Text(user.fullName.toTitleCase(), style: TextStyle(fontSize: 16, fontWeight: isSelected ? FontWeight.bold : FontWeight.w600)), subtitle: Text(contactInfo, style: TextStyle(fontSize: 14, color: Colors.grey[600])), onTap: () => _onUserSelected(user)));
    });
  }

  Widget _buildDetailView() {
    if (_isLoadingDetails) return const Center(child: CircularProgressIndicator());
    if (_selectedUser == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.people_outline, size: 80, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text('Select a user to review their details', style: TextStyle(fontSize: 22, color: Colors.grey[600]))
          ],
        ),
      );
    }

    return SingleChildScrollView(
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
              child: Column(children: [
                _buildInfoCard(Icons.badge_outlined, 'Full Name', _selectedUser!.fullName.toTitleCase()),
                if (_selectedUser!.email.isNotEmpty && _selectedUser!.email != 'N/A')
                  _buildInfoCard(Icons.email_outlined, 'Email', _selectedUser!.email),
                if (_selectedUser!.phoneNumber != null)
                  _buildInfoCard(Icons.phone_android, 'Phone Number', _selectedUser!.phoneNumber!),
                _buildInfoCard(Icons.account_circle_outlined, 'Username', _selectedUser!.username),
                _buildAddressCard(Icons.pin_drop_outlined, 'Address', _selectedUser!.fullAddress),
              ]),
            ),
          ),
          
          const SizedBox(height: 32),
          _buildSectionHeader('ID Information'),
          const SizedBox(height: 16),

          if (_selectedUserSubmission != null) ...[
            Card(
              elevation: 1,
              color: cardBackgroundColor,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 16.0),
                child: Column(
                  children: [
                    _buildInfoCard(Icons.credit_card, 'ID Type', _selectedUserSubmission!.idType),
                    
                    ..._selectedUserSubmission!.fields.entries.map((entry) {
                      return _buildInfoCard(Icons.notes, _formatLabel(entry.key), '${entry.value}');
                    }),

                    const SizedBox(height: 20),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_selectedUserSubmission!.idImageUrl?.isNotEmpty == true)
                          Expanded(child: _buildImagePreview("ID Image", _selectedUserSubmission!.idImageUrl!)),
                        if (_selectedUserSubmission!.selfieImageUrl?.isNotEmpty == true)
                          Expanded(child: _buildImagePreview("Selfie", _selectedUserSubmission!.selfieImageUrl!)),
                      ],
                    )
                  ],
                ),
              ),
            ),
          ] else ...[
            Container(
              padding: const EdgeInsets.all(20),
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: Colors.yellow[100],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.withOpacity(0.3))
              ),
              child: Row(children: [
                const Icon(Icons.info_outline, color: Colors.orange),
                const SizedBox(width: 16),
                const Expanded(child: Text('User has not submitted documents online. You may approve them if verified in person.', style: TextStyle(fontSize: 16)))
              ]),
            ),
          ],

          const SizedBox(height: 32),
          _buildSectionHeader('Actions'),
          const SizedBox(height: 16),
          
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.check_circle_outline, color: Colors.white),
              label: const Text('Approve (In-Person)'),
              style: ElevatedButton.styleFrom(
                backgroundColor: themePrimaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 20),
                textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)
              ),
              onPressed: _isProcessingAction ? null : () async {
                final note = await _showInPersonApprovalDialog();
                if (note != null) _executeSecureAction(userId: _selectedUser!.id, isApproved: true, approvalNote: note);
              }
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImagePreview(String label, String url) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 8.0),
          child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black54)),
        ),
        const SizedBox(height: 8),
        Card(
          clipBehavior: Clip.antiAlias,
          elevation: 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          margin: const EdgeInsets.symmetric(horizontal: 8),
          child: InkWell(
            onTap: () => _showImageDialog(context, url),
            child: Container(
              height: 150,
              width: double.infinity,
              color: Colors.grey.shade100,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.network(
                    url, 
                    fit: BoxFit.cover, 
                    loadingBuilder: (context, child, progress) => progress == null ? child : const Center(child: CircularProgressIndicator()),
                    errorBuilder: (_,__,___) => const Center(child: Icon(Icons.error, color: Colors.red))
                  ),
                  Positioned(
                    bottom: 4,
                    right: 4,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(color: Colors.black.withOpacity(0.6), shape: BoxShape.circle),
                      child: const Icon(Icons.zoom_in, color: Colors.white, size: 18),
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

  Widget _buildSectionHeader(String title) => Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.black87));
  
  Widget _buildInfoCard(IconData icon, String label, String? value) => ListTile(
    leading: CircleAvatar(backgroundColor: themeAccentColor, child: Icon(icon, size: 22, color: themePrimaryColor)), 
    title: Text(label, style: TextStyle(fontSize: 14, color: Colors.grey[600])), 
    subtitle: SelectableText(value ?? 'N/A', style: const TextStyle(fontSize: 17, color: Colors.black87, fontWeight: FontWeight.w500))
  );
  
  Widget _buildAddressCard(IconData icon, String label, String address) => ListTile(
    leading: CircleAvatar(backgroundColor: themeAccentColor, child: Icon(icon, size: 22, color: themePrimaryColor)), 
    title: Text(label, style: TextStyle(fontSize: 14, color: Colors.grey[600])), 
    subtitle: SelectableText(address, style: const TextStyle(fontSize: 17, color: Colors.black87, fontWeight: FontWeight.w500)), 
    trailing: IconButton(icon: const Icon(Icons.location_on, color: themePrimaryColor), onPressed: () => _openGoogleMaps(address))
  );
}