import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:showcaseview/showcaseview.dart';
import 'firebase_service.dart'; // Ensure this exists in your lib folder
import 'package:cached_network_image/cached_network_image.dart';

// Import the separated files:
import 'models/verification_models.dart';
import 'pages/verification_page.dart';

class ProfilePage extends StatefulWidget {
  final String uid;
  final String token;
  final String email;
  final String username;
  final String fullName;
  final String address;
  final bool isVerified;
  final String? profileImageUrl;
  final Map<String, dynamic> profileData;
  final Function(VerificationData) onVerify;
  final VoidCallback? onChangePhoto;
  final Future<void> Function(Map<String, dynamic> fields) onUpdateProfile;
  final bool isActive;
  final BuildContext? showcaseContext;

  const ProfilePage({
    super.key,
    required this.uid,
    required this.token,
    required this.email,
    required this.username,
    required this.fullName,
    required this.address,
    required this.isVerified,
    required this.onVerify,
    required this.profileData,
    required this.onUpdateProfile,
    this.onChangePhoto,
    this.profileImageUrl,
    this.isActive = false,
    this.showcaseContext,
  });

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final FirebaseService _firebaseService = FirebaseService();
  
  final ScrollController _scrollController = ScrollController();
  
  VerificationStatus _verificationStatus = VerificationStatus.loading;
  String _rejectionReason = '';
  String? _profileImageUrl;
  final bool _isUploading = false;
  
  // Showcase Keys
  final GlobalKey _cameraKey = GlobalKey();
  final GlobalKey _editKey = GlobalKey();
  final GlobalKey _verifyKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _profileImageUrl = widget.profileImageUrl;
    _fetchVerificationStatus();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _fetchVerificationStatus() async {
    if (widget.isVerified) {
      if (mounted) setState(() => _verificationStatus = VerificationStatus.approved);
      return;
    }

    try {
      final submissionData = await _firebaseService.fetchMyVerificationSubmission(widget.uid, widget.token);
      if (!mounted) return;

      if (submissionData == null) {
        setState(() => _verificationStatus = VerificationStatus.notSubmitted);
      } else {
        final status = (submissionData['status'] as String?)?.toLowerCase() ?? 'pending';
        if (status == 'pending') {
          setState(() => _verificationStatus = VerificationStatus.pending);
        } else if (status == 'rejected') {
          setState(() {
            _verificationStatus = VerificationStatus.rejected;
            _rejectionReason = submissionData['rejectionReason'] ?? 'No reason was provided.';
          });
        } else {
          setState(() => _verificationStatus = VerificationStatus.pending);
        }
      }
    } catch (error) {
      if (mounted) {
        setState(() => _verificationStatus = VerificationStatus.notSubmitted);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Could not check verification status: $error")),
        );
      }
    }
  }

  @override
  void didUpdateWidget(covariant ProfilePage oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.profileImageUrl != oldWidget.profileImageUrl) {
      setState(() => _profileImageUrl = widget.profileImageUrl);
    }
    if (widget.isVerified != oldWidget.isVerified) {
      _fetchVerificationStatus();
    }

    // Only try to show the tutorial when the tab becomes active
    if (widget.isActive && !oldWidget.isActive) {
      _checkAndStartProfileTutorial();
    }
  }

  Future<void> _checkAndStartProfileTutorial() async {
    if (widget.isVerified) return;

    final prefs = await SharedPreferences.getInstance();
    final String key = 'profile_tutorial_shown_${widget.uid}';
    final bool hasSeen = prefs.getBool(key) ?? false;

    if (hasSeen || widget.showcaseContext == null) return;

    // Mark as seen immediately so it doesn't try again
    await prefs.setBool(key, true);

    // Wait for the widget tree to be fully built
    await Future.delayed(const Duration(milliseconds: 500));

    if (!mounted) return;

    // --- FIX STARTS HERE ---
    
    // 1. Check if we navigated to a new screen (e.g., clicked "Edit" really fast)
    if (ModalRoute.of(context)?.isCurrent != true) return;

    // 2. Check if the user switched tabs (e.g., went back to Home)
    // Since ProfilePage is usually in an IndexedStack, it stays 'mounted' 
    // even when hidden, so we MUST check widget.isActive.
    if (!widget.isActive) return;

    // --- FIX ENDS HERE ---

    // Manual Slow Scroll Logic
    final verifyContext = _verifyKey.currentContext;
    if (verifyContext != null) {
      try {
        await Scrollable.ensureVisible(
          verifyContext,
          duration: const Duration(seconds: 2), 
          curve: Curves.easeInOutCubic,
          alignment: 0.5,
        );
      } catch (e) {
        debugPrint("Manual scroll failed, continuing to showcase: $e");
      }
    }

    if (!mounted) return;

    // Start the showcase sequence
    ShowCaseWidget.of(widget.showcaseContext!).startShowCase([
      _verifyKey, // 1st: "Get Verified" card
      _editKey,   // 2nd: "Edit Details" button
      _cameraKey, // 3rd: Camera icon
    ]);
  }

  String _capitalize(String text) => text.isEmpty ? text : text[0].toUpperCase() + text.substring(1);

  String _toTitleCase(String? input) {
    if (input == null) return '';
    final text = input.trim();
    if (text.isEmpty) return '';
    return text
        .split(RegExp(r'\s+'))
        .map((word) {
          if (RegExp(r'^[A-Z0-9]{2,}$').hasMatch(word)) return word;
          return word
              .split('-')
              .map((hyphenatedPart) => hyphenatedPart
                  .split("'")
                  .map((apostrophePart) => _capitalize(apostrophePart.toLowerCase()))
                  .join("'"))
              .join('-');
        })
        .join(' ');
  }

  String _getValueOrDash(dynamic value, {String dash = '—'}) {
    if (value == null) return dash;
    if (value is String && value.trim().isEmpty) return dash;
    return value.toString();
  }

  String _formatDateOrDash(dynamic value) {
    final dateString = _getValueOrDash(value, dash: '');
    if (dateString.isEmpty) return '—';
    final dateTime = DateTime.tryParse(dateString);
    if (dateTime == null) return dateString;
    const List<String> monthNames = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    final monthName = monthNames[dateTime.month - 1];
    return '$monthName ${dateTime.day}, ${dateTime.year}';
  }

  String _titleCaseOrDash(dynamic value) {
    final stringValue = (value ?? '').toString().trim();
    return stringValue.isEmpty ? '—' : _toTitleCase(stringValue);
  }

  String _titleCaseOrEmpty(dynamic value) {
    final stringValue = (value ?? '').toString().trim();
    return stringValue.isEmpty ? '' : _toTitleCase(stringValue);
  }

  String _displayFullNameTitleCase() {
    final profileData = widget.profileData;
    final title = _titleCaseOrEmpty(profileData['title']);
    final firstName = _titleCaseOrEmpty(profileData['firstName']);
    final middleName = _titleCaseOrEmpty(profileData['middleName']);
    final lastName = _titleCaseOrEmpty(profileData['lastName']);
    final nameParts = <String>[
      if (title.isNotEmpty) title,
      if (firstName.isNotEmpty) firstName,
      if (middleName.isNotEmpty) middleName,
      if (lastName.isNotEmpty) lastName
    ];
    if (nameParts.isEmpty) {
      final fallbackName = widget.fullName.trim();
      return fallbackName.isNotEmpty ? _toTitleCase(fallbackName) : _toTitleCase(widget.username);
    }
    return nameParts.join(' ');
  }

  String _displayAddressTitleCase() {
    final profileData = widget.profileData;
    final addressParts = [
      _titleCaseOrEmpty(profileData['address']),
      _titleCaseOrEmpty(profileData['barangay']),
      _titleCaseOrEmpty(profileData['municipality']),
      _titleCaseOrEmpty(profileData['province'])
    ].where((part) => part.isNotEmpty).toList();
    return addressParts.isEmpty ? '—' : addressParts.join(', ');
  }

  Widget _buildHeader() {
    final mediaQuery = MediaQuery.of(context);
    final topPadding = mediaQuery.padding.top;
    const coverHeight = 140.0;
    const avatarSize = 110.0;
    final textScaleFactor = mediaQuery.textScaleFactor;
    final infoBlockHeight = (20.0 * textScaleFactor) + 4.0 + (14.0 * textScaleFactor) + 10.0 + (13.0 * textScaleFactor + 16.0);
    final headerHeight = coverHeight + topPadding + (avatarSize / 2) + infoBlockHeight + 16.0;
    Widget placeholder = Container(
      color: Colors.grey.shade200,
      child: Icon(Icons.person, size: 56, color: Colors.grey.shade500),
    );

    String subtitle = widget.email;
    if (subtitle.isEmpty || subtitle == '—') {
      String phone = widget.profileData['phoneNumber'] ?? '';
      if (phone.isNotEmpty) subtitle = phone;
    }

    return SizedBox(
      height: headerHeight,
      child: Stack(clipBehavior: Clip.none, children: [
        Container(
          height: coverHeight + topPadding,
          width: double.infinity,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.deepPurple.shade700, Colors.deepPurple.shade400],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        Positioned(
          top: coverHeight + topPadding - (avatarSize / 2),
          left: 0,
          right: 0,
          child: Center(
            child: SizedBox(
              width: avatarSize,
              height: avatarSize,
              child: Stack(alignment: Alignment.center, children: [
                CircleAvatar(
                  radius: 55,
                  backgroundColor: Colors.white,
                  child: ClipOval(
                    child: SizedBox(
                      width: 104,
                      height: 104,
                      child: (_profileImageUrl != null && _profileImageUrl!.isNotEmpty)
                          ? CachedNetworkImage(
                              imageUrl: _profileImageUrl!,
                              fit: BoxFit.cover,
                              placeholder: (context, url) => Center(
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                              errorWidget: (context, url, error) => placeholder,
                              // Optional: Animation
                              fadeInDuration: const Duration(milliseconds: 300),
                            )
                          : placeholder,
                    ),
                  ),
                ),
                Positioned(
                  bottom: 4,
                  right: 4,
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white.withOpacity(0.6), width: 1),
                    ),
                    child: Material(
                      color: (widget.onChangePhoto == null ? Colors.black.withOpacity(0.25) : Colors.black.withOpacity(0.40)),
                      shape: const CircleBorder(),
                      clipBehavior: Clip.antiAlias,
                      child: Showcase(
                        key: _cameraKey,
                        title: 'Update Photo',
                        description: 'Tap here to change your profile picture.',
                        targetShapeBorder: const CircleBorder(),
                        enableAutoScroll: true,
                        child: IconButton(
                          padding: const EdgeInsets.all(8),
                          constraints: const BoxConstraints(),
                          splashRadius: 20,
                          icon: Icon(
                            Icons.camera_alt,
                            size: 18,
                            color: Colors.white.withOpacity(widget.onChangePhoto == null ? 0.6 : 0.95),
                          ),
                          tooltip: widget.onChangePhoto == null ? "Unavailable" : "Change profile picture",
                          onPressed: widget.onChangePhoto,
                        ),
                      ),
                    ),
                  ),
                ),
              ]),
            ),
          ),
        ),
        Positioned(
          top: coverHeight + topPadding + (avatarSize / 2) + 8,
          left: 16,
          right: 16,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(
              _displayFullNameTitleCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.lato(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.black87),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.lato(fontSize: 14, color: Colors.black54),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            _buildVerifiedChip(widget.isVerified),
          ]),
        ),
      ]),
    );
  }

  Widget _buildVerifiedChip(bool isVerified) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
      decoration: BoxDecoration(
        color: isVerified ? Colors.green.shade50 : Colors.orange.shade50,
        border: Border.all(color: isVerified ? Colors.green.shade200 : Colors.orange.shade200),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(
          isVerified ? Icons.verified : Icons.error_outline,
          size: 18,
          color: isVerified ? Colors.green : Colors.orange,
        ),
        const SizedBox(width: 6),
        Text(
          isVerified ? "Verified" : "Not Verified",
          style: GoogleFonts.lato(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: isVerified ? Colors.green.shade800 : Colors.orange.shade800,
          ),
        ),
      ]),
    );
  }

  Widget _sectionTitle(String title, IconData icon, {Widget? trailing}) {
    return Row(children: [
      Icon(icon, size: 18, color: Colors.deepPurple),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          title,
          style: GoogleFonts.lato(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.deepPurple.shade700),
        ),
      ),
      if (trailing != null) trailing,
    ]);
  }

  Widget _infoRow({required String label, required String value, IconData? icon}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (icon != null) ...[
          Icon(icon, size: 18, color: Colors.grey.shade600),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              label,
              style: GoogleFonts.lato(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: GoogleFonts.lato(fontSize: 16, color: Colors.black87, fontWeight: FontWeight.w600),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _buildDetailsCard() {
    final profileData = widget.profileData;
    String? displayEmail = _getValueOrDash(profileData['email']);
    bool hasEmail = displayEmail != '—' && displayEmail.isNotEmpty;

    String? displayPhone = _getValueOrDash(profileData['phoneNumber']);
    bool hasPhone = displayPhone != '—' && displayPhone.isNotEmpty;

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _sectionTitle(
            "Profile Details",
            Icons.badge_outlined,
            trailing: Showcase(
              key: _editKey,
              title: 'Edit Details',
              description: 'Tap here to update your personal information.',
              enableAutoScroll: true,
              child: TextButton.icon(
                onPressed: _openEditProfileBottomSheet,
                icon: const Icon(Icons.edit, size: 16),
                label: const Text("Edit"),
                style: TextButton.styleFrom(foregroundColor: Colors.deepPurple),
              ),
            ),
          ),
          const SizedBox(height: 12),
          _infoRow(
            label: "Username",
            value: _getValueOrDash(profileData['username']),
            icon: Icons.person_outline,
          ),
          if (hasEmail) ...[
            const Divider(height: 20),
            _infoRow(label: "Email", value: displayEmail, icon: Icons.email_outlined),
          ],
          if (hasPhone) ...[
            const Divider(height: 20),
            _infoRow(label: "Phone Number", value: displayPhone, icon: Icons.phone_android),
          ],
          const Divider(height: 20),
          _infoRow(
            label: "Full Name",
            value: _displayFullNameTitleCase(),
            icon: Icons.account_circle_outlined,
          ),
          const Divider(height: 20),
          _infoRow(
            label: "Birthplace Address",
            value: _displayAddressTitleCase(),
            icon: Icons.location_on_outlined,
          ),
        ]),
      ),
    );
  }

  Widget _buildMoreInfoCard() {
    final profileData = widget.profileData;
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          title: _sectionTitle("More Information", Icons.info_outline),
          children: [
            _infoRow(label: "Title", value: _titleCaseOrDash(profileData['title'])),
            const Divider(height: 20),
            _infoRow(label: "First Name", value: _titleCaseOrDash(profileData['firstName'])),
            const Divider(height: 20),
            _infoRow(label: "Middle Name", value: _titleCaseOrDash(profileData['middleName'])),
            const Divider(height: 20),
            _infoRow(label: "Last Name", value: _titleCaseOrDash(profileData['lastName'])),
            const Divider(height: 20),
            _infoRow(label: "Birthdate", value: _formatDateOrDash(profileData['birthdate'])),
            const Divider(height: 20),
            _infoRow(label: "Sex", value: _titleCaseOrDash(profileData['sex'])),
            const Divider(height: 20),
            _infoRow(label: "Province", value: _titleCaseOrDash(profileData['province'])),
            const Divider(height: 20),
            _infoRow(label: "Municipality", value: _titleCaseOrDash(profileData['municipality'])),
            const Divider(height: 20),
            _infoRow(label: "Barangay", value: _titleCaseOrDash(profileData['barangay'])),
          ],
        ),
      ),
    );
  }

  Widget _buildVerificationCard() {
    return Showcase(
      key: _verifyKey,
      title: 'Get Verified',
      description: 'Upload your ID here to unlock all app features.',
      enableAutoScroll: true,
      child: Card(
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _sectionTitle("Identity Verification", Icons.verified_user_outlined),
            const SizedBox(height: 12),
            _buildVerificationStatusContent(),
          ]),
        ),
      ),
    );
  }

  Widget _buildVerificationStatusContent() {
    switch (_verificationStatus) {
      case VerificationStatus.loading:
        return const Center(child: CircularProgressIndicator());
      case VerificationStatus.approved:
        return _buildStatusMessage(
          "Your account has been verified. Thank you!",
          Icons.verified,
          Colors.green,
        );
      case VerificationStatus.pending:
        return Column(children: [
          _buildStatusMessage(
            "Your submission is currently under review. Please wait for an administrator to process your documents.",
            Icons.hourglass_top,
            Colors.blue,
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: null,
              icon: const Icon(Icons.security),
              label: Text("Verification Submitted", style: GoogleFonts.lato(fontWeight: FontWeight.w700)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.grey.shade400,
                disabledForegroundColor: Colors.white70,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ]);
      case VerificationStatus.rejected:
        return Column(children: [
          _buildStatusMessage(
            "Your submission was not approved. Reason: $_rejectionReason",
            Icons.cancel,
            Colors.red,
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _handleResubmit,
              icon: const Icon(Icons.refresh),
              label: Text("Resubmit Application", style: GoogleFonts.lato(fontWeight: FontWeight.w700)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange.shade700,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ]);
      case VerificationStatus.notSubmitted:
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            "Verify your identity to access all services.",
            style: GoogleFonts.lato(fontSize: 14, color: Colors.black87),
          ),
          const SizedBox(height: 12),
          _verificationSteps(),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _openVerificationFullScreen(context),
              icon: const Icon(Icons.security),
              label: Text("Verify Now", style: GoogleFonts.lato(fontWeight: FontWeight.w700)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurple,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ]);
    }
  }

  Future<void> _handleResubmit() async {
    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Resubmit Application"),
        content: const Text(
          "This will delete your previous submission and allow you to start a new one. Are you sure?",
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text("Continue")),
        ],
      ),
    );
    if (confirm == true) {
      try {
        await _firebaseService.deleteMyVerificationSubmission(widget.uid, widget.token);
        _openVerificationFullScreen(context);
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Error: $error"), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  Widget _buildStatusMessage(String message, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(children: [
        Icon(icon, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            message,
            style: GoogleFonts.lato(fontSize: 14, color: color, fontWeight: FontWeight.w600),
          ),
        ),
      ]),
    );
  }

  Widget _verificationSteps() {
    Widget step(IconData icon, String title, String subtitle) {
      return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: Colors.deepPurple, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                title,
                style: GoogleFonts.lato(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.black87),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: GoogleFonts.lato(fontSize: 13, color: Colors.black54, height: 1.4),
              ),
            ]),
          ),
        ),
      ]);
    }

    return Column(children: [
      step(Icons.credit_card, "Upload your ID", "Provide a clear photo of a valid government-issued ID."),
      step(Icons.camera_alt, "Upload a Selfie", "Take a selfie to match with your ID."),
      step(Icons.check_circle_outline, "Submit for Review", "We'll notify you once verification is complete."),
    ]);
  }

  void _openEditProfileBottomSheet() {
    final profileData = widget.profileData;
    final formKey = GlobalKey<FormState>();
    final titleController = TextEditingController(text: _getValueOrDash(profileData['title'], dash: ''));
    final firstNameController = TextEditingController(text: _getValueOrDash(profileData['firstName'], dash: ''));
    final middleNameController = TextEditingController(text: _getValueOrDash(profileData['middleName'], dash: ''));
    final lastNameController = TextEditingController(text: _getValueOrDash(profileData['lastName'], dash: ''));
    final usernameController = TextEditingController(text: _getValueOrDash(profileData['username'], dash: ''));
    final streetController = TextEditingController(text: _getValueOrDash(profileData['address'], dash: ''));
    final provinceController = TextEditingController(text: _getValueOrDash(profileData['province'], dash: ''));
    final municipalityController = TextEditingController(text: _getValueOrDash(profileData['municipality'], dash: ''));
    final barangayController = TextEditingController(text: _getValueOrDash(profileData['barangay'], dash: ''));
    final birthdateController = TextEditingController(text: _getValueOrDash(profileData['birthdate'], dash: ''));
    String sex = _titleCaseOrEmpty(profileData['sex']);

    Future<void> pickDate() async {
      final now = DateTime.now();
      final pickedDate = await showDatePicker(
        context: context,
        initialDate: DateTime.tryParse(birthdateController.text) ?? DateTime(now.year - 20, 1, 1),
        firstDate: DateTime(1900),
        lastDate: now,
      );
      if (pickedDate != null) {
        birthdateController.text = pickedDate.toIso8601String().split('T').first;
      }
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (modalContext) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(modalContext).viewInsets.bottom),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Form(
            key: formKey,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Text("Edit Profile", style: GoogleFonts.lato(fontSize: 18, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    controller: titleController,
                    decoration: const InputDecoration(labelText: "Title (e.g., Mr., Ms.)"),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 4,
                  child: TextFormField(
                    controller: firstNameController,
                    decoration: const InputDecoration(labelText: "First Name"),
                    validator: (value) => (value == null || value.trim().isEmpty) ? "Required" : null,
                  ),
                ),
              ]),
              const SizedBox(height: 8),
              TextFormField(
                controller: middleNameController,
                decoration: const InputDecoration(labelText: "Middle Name"),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: lastNameController,
                decoration: const InputDecoration(labelText: "Last Name"),
                validator: (value) => (value == null || value.trim().isEmpty) ? "Required" : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: usernameController,
                decoration: const InputDecoration(labelText: "Username"),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: streetController,
                decoration: const InputDecoration(labelText: "Street / House No."),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: barangayController,
                decoration: const InputDecoration(labelText: "Barangay"),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: municipalityController,
                decoration: const InputDecoration(labelText: "Municipality / City"),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: provinceController,
                decoration: const InputDecoration(labelText: "Province"),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: TextFormField(
                    controller: birthdateController,
                    readOnly: true,
                    decoration: InputDecoration(
                      labelText: "Birthdate (YYYY-MM-DD)",
                      suffixIcon: IconButton(icon: const Icon(Icons.date_range), onPressed: pickDate),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: sex.isNotEmpty ? sex : null,
                    items: const [
                      DropdownMenuItem(value: 'Male', child: Text('Male')),
                      DropdownMenuItem(value: 'Female', child: Text('Female')),
                    ],
                    onChanged: (value) => sex = value ?? '',
                    decoration: const InputDecoration(labelText: "Sex"),
                  ),
                ),
              ]),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(modalContext),
                    child: const Text("Cancel"),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () async {
                      if (!formKey.currentState!.validate()) return;
                      final Map<String, dynamic> fields = {
                        'title': titleController.text.trim(),
                        'firstName': firstNameController.text.trim(),
                        'middleName': middleNameController.text.trim(),
                        'lastName': lastNameController.text.trim(),
                        'username': usernameController.text.trim(),
                        'address': streetController.text.trim(),
                        'barangay': barangayController.text.trim(),
                        'municipality': municipalityController.text.trim(),
                        'province': provinceController.text.trim(),
                        'birthdate': birthdateController.text.trim(),
                        'sex': sex.trim(),
                      };
                      fields.removeWhere((key, value) => (value is String && value.trim().isEmpty));
                      try {
                        await widget.onUpdateProfile(fields);
                        if (mounted) Navigator.pop(modalContext);
                      } catch (error) {
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text("Save failed: $error")),
                        );
                      }
                    },
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple),
                    child: const Text("Save", style: TextStyle(color: Colors.white)),
                  ),
                ),
              ]),
            ]),
          ),
        ),
      ),
    );
  }

  Future<void> _openVerificationFullScreen(BuildContext context) async {
    final result = await Navigator.of(context).push<VerificationData>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const FullScreenVerificationPage(),
      ),
    );
    if (result != null) {
      widget.onVerify(result);
      setState(() => _verificationStatus = VerificationStatus.pending);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.grey.shade100,
      child: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: _fetchVerificationStatus,
          color: Colors.deepPurple,
          child: CustomScrollView(
            // FIX: Attached controller here
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(child: _buildHeader()),
              const SliverToBoxAdapter(child: SizedBox(height: 12)),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    if (_isUploading)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(16.0),
                          child: CircularProgressIndicator(),
                        ),
                      ),
                    _buildDetailsCard(),
                    const SizedBox(height: 12),
                    _buildMoreInfoCard(),
                    const SizedBox(height: 12),
                    _buildVerificationCard(),
                    const SizedBox(height: 24),
                  ]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}