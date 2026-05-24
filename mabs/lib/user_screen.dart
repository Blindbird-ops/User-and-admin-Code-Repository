// lib/user_screen.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:mabs/models/verification_models.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloudinary_public/cloudinary_public.dart';
import 'package:image_picker/image_picker.dart';
import 'package:showcaseview/showcaseview.dart'; 
import 'household_survey_screen.dart'; // Add this at the top of user_screen.dart
import 'settings_page.dart';
import 'login_screen.dart';
import 'request_document_page.dart';
import 'user_request_status.dart';
import 'appointment_request.dart';
import 'complaint_screen.dart';
import 'profile_page.dart';
import 'firebase_service.dart';
import 'notification_service.dart'; 

class UserScreen extends StatefulWidget {
  final String token;
  final String uid;
  final String email;
  final bool isVerified;

  const UserScreen({
    super.key,
    required this.token,
    required this.uid,
    required this.email,
    required this.isVerified,
  });

  @override
  _UserScreenState createState() => _UserScreenState();
}

class _UserScreenState extends State<UserScreen> {
  int _currentIndex = 0;
  
  // 1. ADD SCROLL CONTROLLER FOR HOME PAGE
  final ScrollController _homeScrollController = ScrollController();

  // Data State
  List<Map<String, dynamic>> _announcements = [];
  List<Map<String, dynamic>> _mergedNotifications = []; // <--- ADD THIS
  Set<String> _viewedAnnouncementIds = {};
    Set<String> _viewedRequestKeys = {}; // Stores "ID_STATUS" to track unread updates

  bool _hasUnreadAnnouncement = false;
  bool _isSurveyCompleted = false;
  bool _isLoadingSurveyStatus = true;
  Timer? _timer;
  Set<String> _selectedNotificationIds = {};
  
  // User Profile State
  Map<String, dynamic>? userProfile;
  String? username;
  String? fullName;
  String? address;
  String? _revocationReason; 
  String? _verificationStatus; // <--- This was missing before
  bool? isUserVerified;
  String? profilePictureUrl;
  bool _showJustVerifiedBanner = false;
  bool? _previousVerifiedStatus; 
  
  // Notification Logic State

  final FirebaseService firebaseService = FirebaseService();
  final cloudinary = CloudinaryPublic('dnufyw3my', 'cloudinary', cache: false);

  // --- SHOWCASE KEYS ---
  final GlobalKey _profileIconKey = GlobalKey(); // Unverified Key
  
  // KEYS FOR VERIFIED FEATURES
  final GlobalKey _reqDocKey = GlobalKey();
  final GlobalKey _reqStatusKey = GlobalKey();
  final GlobalKey _apptKey = GlobalKey();
  final GlobalKey _complaintKey = GlobalKey();

  BuildContext? _showCaseContext;

  @override
  void initState() {
    super.initState();
    isUserVerified = widget.isVerified;
    _previousVerifiedStatus = isUserVerified;
    _loadCachedVerificationStatus(); 

    _loadViewedStatusKeys();
    // Load data
    _loadViewedAnnouncementIds().then((_) => _loadAllNotifications()); 
    _loadUserDetails();

    // Setup Listeners
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      NotificationService.checkPermissions(context);
      _checkAndStartTutorial();
      
      // 1. Handle Terminated State (App Killed)
      _checkForInitialMessage();

      // 2. Handle Background State (App Minimized) <--- ADDED THIS
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        print("Notification clicked from background!");
        _handleNotificationPayload(message.data);
      });

      // Save Token
      String? token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        await NotificationService.saveTokenToDatabase(token);
      }
    });

    _timer = Timer.periodic(const Duration(seconds: 10), (_) {
      _loadAllNotifications(); 
      _checkRequestStatusUpdates();
      _checkVerificationStatus();
    });
    
    _checkRequestStatusUpdates();
  }


  int _getUnreadNotificationCount() {
    int count = 0;
    for (var notification in _mergedNotifications) {
      // Reconstruct the unique key used in markStatusAsViewed
      String status = (notification['status'] ?? '').toString();
      String uniqueKey = "${notification['id']}_$status";
      
      // If we haven't saved this key yet, it's unread
      if (!_viewedRequestKeys.contains(uniqueKey)) {
        count++;
      }
    }
    return count;
  }
  // 2. ADD THIS HELPER METHOD INSIDE THE CLASS
  Future<void> _loadCachedVerificationStatus() async {
    final prefs = await SharedPreferences.getInstance();
    // If widget.isVerified passed as false (e.g. from login error), check the cache!
    if (isUserVerified == false) {
      bool cachedStatus = prefs.getBool('cached_is_verified') ?? false;
      if (cachedStatus) {
        setState(() {
          isUserVerified = true;
        });
      }
    }
  }
  Future<void> _loadViewedStatusKeys() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getStringList('viewed_status_${widget.uid}');
    if (keys != null && mounted) {
      setState(() => _viewedRequestKeys = keys.toSet());
    }
  }

    Future<void> _markStatusAsViewed(String requestId, String status) async {
    final key = "${requestId}_${status}";
    if (!_viewedRequestKeys.contains(key)) {
      setState(() {
        _viewedRequestKeys.add(key);
      });
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('viewed_status_${widget.uid}', _viewedRequestKeys.toList());
    }
  }
  // --- NEW METHOD TO HANDLE LAUNCH FROM NOTIFICATION ---
  Future<void> _checkForInitialMessage() async {
    // 1. Check if app was launched by FCM (Background/Terminated)
    RemoteMessage? initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) {
      print("App launched via FCM Message");
      _handleNotificationPayload(initialMessage.data);
    }

    // 2. Check if app was launched by Awesome Notifications (Terminated)
    ReceivedAction? receivedAction = await AwesomeNotifications().getInitialNotificationAction(removeFromActionEvents: true);
    if (receivedAction != null && receivedAction.payload != null) {
      print("App launched via Awesome Notification");
      _handleNotificationPayload(Map<String, dynamic>.from(receivedAction.payload!));
    }
  }

  // Inside UserScreen state class

  void _handleNotificationPayload(Map<String, dynamic> data) {
    // 1. Safety check
    if (!mounted) return;

    String? navigate = data['navigate']?.toString();
    String? type = data['type']?.toString();

    // --- CASE A: Document Updates (Open Status Page) ---
    if (navigate == 'true' && (type == 'document' || type == 'request_update')) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => UserRequestStatusPage(
            token: widget.token,
            uid: widget.uid,
            email: widget.email,
          ),
        ),
      );
    }
    
    // --- CASE B: Profile Verified (Switch to Profile Tab) ---
    else if (navigate == 'true' && type == 'profile') {
      setState(() {
        _currentIndex = 1; // Switch to Profile Tab
      });
    }

    // --- CASE C: Announcement (Switch to Notification Tab) ---
    // This assumes your backend sends data: { "type": "announcement" }
    else if (type == 'announcement' || data.containsKey('announcement_id')) {
      setState(() {
        _currentIndex = 2; // Switch to Notification Tab
      });
      
      // Optional: Refresh list to make sure the new announcement appears
      _loadAllNotifications(); // <--- FIXED
    }
  }
 
  // --- UPDATED TUTORIAL LOGIC WITH FIX ---
  Future<void> _checkAndStartTutorial() async {
    final prefs = await SharedPreferences.getInstance();
    
    if (_showCaseContext == null) return;
    if (!mounted) return;

    if (isUserVerified == false) {
      // --- Scenario A: User is NOT verified ---
      bool hasSeenProfileTutorial = prefs.getBool('tutorial_profile_shown_${widget.uid}') ?? false;
      if (!hasSeenProfileTutorial) {
        ShowCaseWidget.of(_showCaseContext!).startShowCase([_profileIconKey]);
        await prefs.setBool('tutorial_profile_shown_${widget.uid}', true);
      }
    } else {
      // --- Scenario B: User IS verified ---
      bool hasSeenFeaturesTutorial = prefs.getBool('tutorial_features_shown_${widget.uid}') ?? false;
      
      if (!hasSeenFeaturesTutorial && _currentIndex == 0) {
        
        // Wait for widgets to paint
        await Future.delayed(const Duration(milliseconds: 800));
        
        if (!mounted) return;

        // *** FIX: Check if UserScreen is still the top screen ***
        // If user clicked "Request Document" during the 800ms delay, this will be false.
        if (ModalRoute.of(context)?.isCurrent != true) {
          return; 
        }

        // Reset scroll to top before starting
        if (_homeScrollController.hasClients) {
          _homeScrollController.jumpTo(0);
        }

        ShowCaseWidget.of(_showCaseContext!).startShowCase([
          _reqDocKey,
          _reqStatusKey,
          _apptKey,
          _complaintKey,
        ]);
        await prefs.setBool('tutorial_features_shown_${widget.uid}', true);
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    // 2. DISPOSE CONTROLLER
    _homeScrollController.dispose();
    super.dispose();
  }

  String _sanitizeKey(String key) {
    String sanitized = key.replaceAll(RegExp(r'[.#$[\]/]'), ' ').toLowerCase();
    List<String> parts = sanitized.split(' ').where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return 'invalidKey${DateTime.now().millisecondsSinceEpoch}';
    
    String camelCaseKey = parts.first;
    for (int i = 1; i < parts.length; i++) {
      camelCaseKey += parts[i][0].toUpperCase() + parts[i].substring(1);
    }
    return camelCaseKey;
  }

  Future<void> _checkVerificationStatus() async {
    if (_previousVerifiedStatus == true) return; 

    Map<String, dynamic>? data;
    try {
      // Fetch safely
      data = await firebaseService.fetchUserData(widget.token);
    } catch (e) {
      // Silently ignore background network errors so we don't spam the user
      print("Background verification check failed: $e");
      return; 
    }

    if (data != null) {
      bool isNowVerified = data['isVerified'] ?? false;

      if (_previousVerifiedStatus == false && isNowVerified == true) {
        NotificationService.showVerificationNotification();
        
        setState(() {
          isUserVerified = true;
          _showJustVerifiedBanner = true;
          _currentIndex = 0; // Force switch to Home
        });

        WidgetsBinding.instance.addPostFrameCallback((_) {
          _checkAndStartTutorial();
        });
      }
      _previousVerifiedStatus = isNowVerified;
    }
  }

  // --- NEW: Upload to Firebase Storage ---
  Future<String> _uploadFileToFirebase(File file, String destinationPath) async {
    try {
      final ref = FirebaseStorage.instance.ref(destinationPath);
      final uploadTask = ref.putFile(file);
      final snapshot = await uploadTask;
      return await snapshot.ref.getDownloadURL();
    } catch (e) {
      throw Exception("Failed to upload file to Storage: $e");
    }
  }
  void _showVerificationStatusTopDialog() {
    // 1. Default Setup (Unverified = Golden)
    String title = "Account Not Verified";
    String description = "Your account is not verified yet. Please go to the Profile section to complete verification and unlock all features.";
    IconData statusIcon = Icons.shield_outlined;
    
    // Default Colors (Amber/Golden)
    Color colorLight = Colors.amber.shade300;
    Color colorDark = Colors.amber.shade600;
    Color shadowColor = Colors.amber.shade700;
    Color borderColor = Colors.amber.shade200;

    // 2. Change Text and Colors based on Status
    if (_verificationStatus == 'revoked') {
      // REVOKED = Red Theme
      statusIcon = Icons.gavel_rounded;
      title = "Verification Revoked";
      description = "${_revocationReason ?? 'Your verification was revoked.'}\n\nPlease visit the Barangay Hall for further assistance.";
      colorLight = Colors.red.shade400;
      colorDark = Colors.red.shade700;
      shadowColor = Colors.red.shade900;
      borderColor = Colors.red.shade300;
      
    } else if (_verificationStatus == 'rejected') {
      // REJECTED = Deep Orange Theme
      statusIcon = Icons.assignment_return_rounded;
      title = "Verification Rejected";
      description = "${_revocationReason ?? 'Your submission was rejected.'}\n\nPlease review the feedback and submit your documents again.";
      colorLight = Colors.orange.shade400;
      colorDark = Colors.orange.shade700;
      shadowColor = Colors.orange.shade900;
      borderColor = Colors.orange.shade300;
    }

    // 3. Beautiful Custom Animated Dialog
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: "Dismiss",
      barrierColor: Colors.black.withOpacity(0.4), 
      transitionDuration: const Duration(milliseconds: 350), 
      pageBuilder: (context, animation, secondaryAnimation) {
        
        // --- ADDED MASTER GESTURE DETECTOR HERE ---
        return GestureDetector(
          onTap: () => Navigator.pop(context),
          // HitTestBehavior.opaque forces it to detect taps even on transparent areas!
          behavior: HitTestBehavior.opaque, 
          
          child: Align(
            alignment: Alignment.topCenter,
            child: Material(
              color: Colors.transparent,
              child: Container(
                margin: const EdgeInsets.only(top: kToolbarHeight + 40, left: 20, right: 20),
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [colorLight, colorDark],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: shadowColor.withOpacity(0.4),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                  border: Border.all(color: borderColor, width: 1.5),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min, 
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.25),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(statusIcon, size: 40, color: Colors.white),
                    ),
                    const SizedBox(height: 16),
                    
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.lato(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        shadows: [
                          const Shadow(color: Colors.black26, blurRadius: 2, offset: Offset(0, 1))
                        ]
                      ),
                    ),
                    const SizedBox(height: 12),
                    
                    Text(
                      description,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.lato(
                        fontSize: 15,
                        color: Colors.white.withOpacity(0.95),
                        height: 1.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    
                    const SizedBox(height: 20),
                    
                    Text(
                      "Tap anywhere to close",
                      style: GoogleFonts.lato(
                        fontSize: 12,
                        color: Colors.white.withOpacity(0.6),
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return ScaleTransition(
          scale: CurvedAnimation(parent: animation, curve: Curves.easeOutBack),
          alignment: Alignment.topRight, 
          child: FadeTransition(
            opacity: animation,
            child: child,
          ),
        );
      },
    );
  }
  Widget _buildUnverifiedIcon() {
    // Determine the icon color based on the status
    Color iconColor = Colors.amber.shade400; // Default Unverified
    
    if (_verificationStatus == 'revoked') {
      iconColor = Colors.redAccent;
    } else if (_verificationStatus == 'rejected') {
      iconColor = Colors.orangeAccent;
    }

    return IconButton(
      icon: Icon(Icons.info_outline, color: iconColor, size: 28),
      tooltip: "Verification Status",
      onPressed: _showVerificationStatusTopDialog, 
    );
  }
  Future<void> _checkRequestStatusUpdates() async {
    final url = "https://mabskie-47c24-default-rtdb.firebaseio.com/users/${widget.uid}/requests.json?auth=${widget.token}";
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data == null || data is! Map) return;

        Map<String, String> currentStatuses = {};

        data.forEach((key, value) {
          if (value is Map) {
            String status = value['status'] ?? 'Pending';
            currentStatuses[key] = status;

            // --- DELETED THE NOTIFICATION LOGIC HERE ---
            // We removed the "if (oldStatus != status)" block
            // because your Cloud Function now handles the notification.
            // -------------------------------------------
          }
        });
      }
    } catch (_) { }
  }

  Future<void> _loadAllNotifications() async {
    // 1. Fetch Announcements
    final annUrl = "https://mabskie-47c24-default-rtdb.firebaseio.com/announcements.json?auth=${widget.token}";
    List<Map<String, dynamic>> tempAnnouncements = [];
    
    try {
      final response = await http.get(Uri.parse(annUrl));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data != null && data is Map) {
          data.forEach((key, value) {
            final ann = Map<String, dynamic>.from(value);
            ann['id'] = key;
            ann['notificationType'] = 'announcement'; 
            tempAnnouncements.add(ann);
          });
        }
      }
    } catch (_) {}

    // 2. Fetch User Requests
    final reqUrl = "https://mabskie-47c24-default-rtdb.firebaseio.com/users/${widget.uid}/requests.json?auth=${widget.token}";
    List<Map<String, dynamic>> tempRequests = [];

    try {
      final response = await http.get(Uri.parse(reqUrl));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data != null && data is Map) {
          data.forEach((key, value) {
            if (value is Map) {
              final req = Map<String, dynamic>.from(value);
              
              String status = req['status']?.toString() ?? 'Pending';
              
              // --- FILTER: HIDE PENDING ---
              if (status.toLowerCase() == 'pending') {
                return; // Skip this iteration, don't add to list
              }

              String docType = req['documentType']?.toString() ?? 'Document Request';

              // --- UPDATED TIMESTAMP LOGIC ---
              // We want the time of the LAST UPDATE, not the creation time.
              dynamic sortTimestamp = req['timestamp']; 

              if (req['statusHistory'] != null) {
                try {
                  if (req['statusHistory'] is Map) {
                    // Map keys in Firebase are usually timestamps or IDs. 
                    // We need to find the one with the latest timestamp value.
                    Map history = req['statusHistory'];
                    var sortedKeys = history.keys.toList()..sort(); // Sort keys (assuming keys are timestamps)
                    var lastEntry = history[sortedKeys.last];
                    sortTimestamp = lastEntry['timestamp'];
                  } else if (req['statusHistory'] is List) {
                    List list = req['statusHistory'];
                    if (list.isNotEmpty) {
                      sortTimestamp = list.last['timestamp'];
                    }
                  }
                } catch (_) {
                  // Fallback to existing timestamp if history parsing fails
                }
              }

              tempRequests.add({
                'id': key,
                'notificationType': 'document',
                'title': docType,
                'status': status,
                'timestamp': sortTimestamp?.toString() ?? '', 
                'message': 'Your request is currently: $status',
                'rawData': req, 
              });
            }
          });
        }
      }
    } catch (_) {}

    // 3. SORTING (Newest First)
    tempRequests.sort((a, b) {
      return _compareTimestamps(b['timestamp'], a['timestamp']);
    });
    
    // Sort announcements too
    tempAnnouncements.sort((a, b) {
      return _compareTimestamps(b['timestamp'], a['timestamp']);
    });

    if (mounted) {
      setState(() {
        _announcements = tempAnnouncements; 
        _mergedNotifications = tempRequests; 
        // Logic for announcements red dot
        _hasUnreadAnnouncement = _announcements.any((ann) => !_viewedAnnouncementIds.contains(ann['id']));
      });
    }
  }
  // Helper for sorting safely
  int _compareTimestamps(String? t1, String? t2) {
    if (t1 == null || t1.isEmpty) return -1;
    if (t2 == null || t2.isEmpty) return 1;
    
    // Try to parse numbers (milliseconds)
    if (RegExp(r'^\d+$').hasMatch(t1) && RegExp(r'^\d+$').hasMatch(t2)) {
      return int.parse(t1).compareTo(int.parse(t2));
    }
    
    // Fallback to string date parsing
    DateTime dt1 = DateTime.tryParse(t1) ?? DateTime(1970);
    DateTime dt2 = DateTime.tryParse(t2) ?? DateTime(1970);
    return dt1.compareTo(dt2);
  }

  Future<void> logout(BuildContext context) async {
    try {
      await FirebaseAuth.instance.signOut(); 
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear(); 
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()), 
        (route) => false
      );
    } catch (e) {
      print("Logout error: $e");
    }
  }

  Future<void> _loadUserDetails() async {
    final bool wasVerifiedBeforeLoad = isUserVerified ?? false;
    
    // 1. Fetch User Data SAFELY with try-catch
    Map<String, dynamic>? data;
    try {
      data = await firebaseService.fetchUserData(widget.token);
    } catch (e) {
      print("Error loading user details: $e");
      if (mounted) {
        // Show the error nicely to the user
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString()), 
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          )
        );
      }
      return; // Stop running the rest of the function so it doesn't crash
    }
    
    if (data != null && mounted) {
      final bool isNowVerified = data['isVerified'] ?? false;
      String? reason;
      String? statusType; 

      // 2. IMPORTANT: If unverified, fetch the reason IMMEDIATELY
      if (!isNowVerified) {
        try {
          final url = 'https://mabskie-47c24-default-rtdb.firebaseio.com/verificationSubmissions/${widget.uid}.json?auth=${widget.token}';
          final response = await http.get(Uri.parse(url));
          
          if (response.statusCode == 200 && response.body != 'null') {
            final subData = json.decode(response.body);
            final rawStatus = subData['status']?.toString().toLowerCase();

            if (rawStatus == 'revoked') {
              statusType = 'revoked';
              reason = subData['revocationReason'] ?? subData['rejectionReason'];
            } else if (rawStatus == 'rejected') {
              statusType = 'rejected';
              reason = subData['rejectionReason'];
            }
          }
        } catch (e) {
          print("Error fetching reason: $e");
        }
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('cached_is_verified', isNowVerified);

      if (isNowVerified && !wasVerifiedBeforeLoad) {
        final bool hasShownBanner = prefs.getBool('verified_banner_shown_${widget.uid}') ?? false;
        setState(() {
           if (!hasShownBanner) _showJustVerifiedBanner = true;
           _currentIndex = 0; 
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _checkAndStartTutorial();
        });
      }
      
      // 3. UPDATE STATE TO TRIGGER REBUILD (This makes the banner appear)
      setState(() {
        userProfile = data;
        username = data!['username'] ?? '';
        fullName = data['fullName'] ?? '';
        address = data['address'] ?? '';
        isUserVerified = isNowVerified;
        profilePictureUrl = data['profilePictureUrl'];
        
        // CRITICAL: Update these so the banner knows what to show
        _revocationReason = reason; 
        _verificationStatus = statusType; 
      });
      // ADD THIS RIGHT HERE
      if (isNowVerified) {
        _checkIfSurveyCompleted(); 
      } else {
        setState(() {
          _isLoadingSurveyStatus = false; // Stop loading spinner state
        });
      }
    }
  }
 
    // --- SURVEY POP-UP LOGIC ---
  // --- NEW SURVEY BUTTON & POP-UP LOGIC ---
  Future<void> _checkIfSurveyCompleted() async {
    try {
      final url = 'https://mabskie-47c24-default-rtdb.firebaseio.com/household_surveys/${widget.uid}.json?auth=${widget.token}';
      final response = await http.get(Uri.parse(url));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (mounted) {
          setState(() {
            _isSurveyCompleted = (data != null); // True if data exists, False if null
            _isLoadingSurveyStatus = false;      // Done loading
          });
        }
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingSurveyStatus = false);
      print("Error checking survey: $e");
    }
  }

  void _showSurveyPromptDialog() {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: "Dismiss",
      barrierColor: Colors.black.withOpacity(0.6),
      transitionDuration: const Duration(milliseconds: 400),
      pageBuilder: (context, animation, secondaryAnimation) {
        return Align(
          alignment: Alignment.center,
          child: Material(
            color: Colors.transparent,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 24),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(color: Colors.deepPurple.withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 10))
                ]
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: Colors.amber.shade100, shape: BoxShape.circle),
                    child: Icon(Icons.maps_home_work_outlined, size: 50, color: Colors.amber.shade800),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    "Barangay Mapping Survey",
                    textAlign: TextAlign.center,
                    style: GoogleFonts.lato(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.deepPurple.shade900),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    "We are mapping households in Brgy. Pularaquen. Please help us by submitting your demographic data and house location.",
                    textAlign: TextAlign.center,
                    style: GoogleFonts.lato(fontSize: 15, color: Colors.grey.shade700, height: 1.5),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context); // Close dialog
                        
                        // Open the Survey Screen and wait for it to return
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => HouseholdSurveyScreen(
                              token: widget.token,
                              uid: widget.uid,
                              fullName: fullName ?? username ?? "",
                            )
                          )
                        ).then((surveyCompleted) {
                          // If they finished the survey, hide the button!
                          if (surveyCompleted == true) {
                            setState(() {
                              _isSurveyCompleted = true;
                            });
                          }
                        });
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepPurple,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
                      ),
                      child: const Text("Fill up Survey Now", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text("Maybe Later", style: TextStyle(color: Colors.grey)),
                  )
                ],
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, anim, secondaryAnim, child) {
        return ScaleTransition(
          scale: CurvedAnimation(parent: anim, curve: Curves.easeOutBack),
          child: FadeTransition(opacity: anim, child: child),
        );
      },
    );
  }

  // THE SIDE BUTTON UI
  // THE SIDE BUTTON UI (SMALL ICON VERSION)
  Widget _buildSideSurveyButton() {
    return Positioned(
      right: 0,
      top: MediaQuery.of(context).size.height * 0.45, // Slightly lower, middle right
      child: GestureDetector(
        onTap: _showSurveyPromptDialog, 
        child: Container(
          decoration: BoxDecoration(
            color: Colors.amber.shade500,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(30),
              bottomLeft: Radius.circular(30),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 6,
                offset: const Offset(-2, 2)
              )
            ],
            border: Border.all(color: Colors.white, width: 2) // Clean white border
          ),
          padding: const EdgeInsets.only(left: 12, right: 8, top: 12, bottom: 12),
          child: Icon(Icons.assignment_outlined, color: Colors.deepPurple.shade900, size: 28),
        ),
      ),
    );
  }

  Future<void> _loadViewedAnnouncementIds() async {
    final prefs = await SharedPreferences.getInstance();
    final ids = prefs.getStringList('viewed_${widget.uid}');
    if (ids != null && mounted) setState(() => _viewedAnnouncementIds = ids.toSet());
  }

  Future<void> _saveViewedAnnouncementIds() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('viewed_${widget.uid}', _viewedAnnouncementIds.toList());
  }

  void _markAnnouncementAsViewed(String id) {
    setState(() {
      _viewedAnnouncementIds.add(id);
      _hasUnreadAnnouncement = _announcements.any((ann) => !_viewedAnnouncementIds.contains(ann['id']));
    });
    _saveViewedAnnouncementIds();
  }

  Future<void> _deleteAnnouncement(String id) async {
    final url = "https://mabskie-47c24-default-rtdb.firebaseio.com/announcements/$id.json?auth=${widget.token}";
    try {
      final response = await http.delete(Uri.parse(url));
      if (response.statusCode == 200) {
        setState(() {
          _announcements.removeWhere((ann) => ann['id'] == id);
          _viewedAnnouncementIds.remove(id);
          _selectedNotificationIds.remove(id);
          _hasUnreadAnnouncement = _announcements.any((ann) => !_viewedAnnouncementIds.contains(ann['id']));
        });
      }
    } catch (_) { }
  }

  Future<void> _deleteSelectedAnnouncements() async {
    for (final id in _selectedNotificationIds.toList()) {
      await _deleteAnnouncement(id);
    }
    setState(() => _selectedNotificationIds.clear());
  }

  void _navigateToComplaint(BuildContext context) {
    if (fullName != null) {
      Navigator.push(context, MaterialPageRoute(builder: (context) => ComplaintScreen(token: widget.token, uid: widget.uid, email: widget.email, fullName: fullName!)));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("User details are still loading, please wait a moment.")));
    }
  }

  void _navigateToRequestDocument(BuildContext context) {
    Navigator.push(context, PageRouteBuilder(pageBuilder: (_, animation, __) => RequestDocumentPage(token: widget.token, uid: widget.uid, email: widget.email), transitionsBuilder: (_, animation, __, child) => SlideTransition(position: Tween<Offset>(begin: const Offset(1.0, 0.0), end: Offset.zero).animate(animation), child: child)));
  }

  void _navigateToRequestStatus(BuildContext context) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => UserRequestStatusPage(token: widget.token, uid: widget.uid, email: widget.email)));
  }
  Future<void> _showVerificationSuccessDialog() async {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          elevation: 0,
          backgroundColor: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Success Icon
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.check_circle_rounded,
                    size: 60,
                    color: Colors.green.shade600,
                  ),
                ),
                const SizedBox(height: 24),
                
                // Title
                Text(
                  "Submission Successful!",
                  textAlign: TextAlign.center,
                  style: GoogleFonts.lato(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: Colors.deepPurple.shade700,
                  ),
                ),
                const SizedBox(height: 12),
                
                // Description
                Text(
                  "Your verification documents have been uploaded. We will review them and notify you shortly.",
                  textAlign: TextAlign.center,
                  style: GoogleFonts.lato(
                    fontSize: 14,
                    color: Colors.black54,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 30),
                
                // Done Button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(dialogContext).pop(); // Just close the dialog
                      // We don't pop the screen here because we are on UserScreen
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepPurple,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      "Done",
                      style: GoogleFonts.lato(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }


  void _navigateToAppointmentRequest(BuildContext context) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => AppointmentRequestPage(token: widget.token, uid: widget.uid, email: widget.email)));
  }

  // --- UI WIDGETS ---

  Widget _buildHomePage() {
    final bool isVerified = isUserVerified ?? false;
    // 3. ATTACH THE CONTROLLER HERE
    return SingleChildScrollView(
      controller: _homeScrollController,
      padding: const EdgeInsets.all(24.0),
      child: Column(
        children: [
          if (isVerified) _buildAnnouncementBanner(),
          const SizedBox(height: 16),
          _buildProfileHeader(),
          const SizedBox(height: 40),
          _buildActionCard(context),
        ],
      ),
    );
  }

  Widget _buildProfilePage() {
    if (userProfile == null) return const Center(child: CircularProgressIndicator());
    bool isProfileActive = _currentIndex == 1; 
    
    return ProfilePage(
      isActive: isProfileActive, 
      showcaseContext: _showCaseContext,
      uid: widget.uid,
      token: widget.token,
      email: widget.email,
      username: username ?? '',
      fullName: fullName ?? '',
      address: address ?? '',
      isVerified: isUserVerified ?? false,
      profileImageUrl: profilePictureUrl,
      profileData: userProfile!,
      
      // ===============================================
      // CORRECTED VERIFICATION FLOW IS HERE
      // ===============================================
      onVerify: (VerificationData data) async {
        // 1. SHOW LOADING DIALOG
        showDialog(
          context: context, 
          barrierDismissible: false, 
          builder: (_) => const AlertDialog(
            content: Column(
              mainAxisSize: MainAxisSize.min, 
              children: [
                CircularProgressIndicator(), 
                SizedBox(height: 20), 
                Text("Uploading documents...")
              ]
            )
          )
        );

        try {
          // --- VALIDATION ---
          if (data.idImageFile == null) throw Exception("ID image is missing.");
          if (data.selfieImageFile == null) throw Exception("Selfie is missing.");

          // --- UPLOAD PROCESS ---
          final ts = DateTime.now().millisecondsSinceEpoch.toString();
          
          // Upload ID
          final idPath = 'verification_files/${widget.uid}/$ts/id_image.jpg';
          final idImageUrl = await _uploadFileToFirebase(data.idImageFile!, idPath);

          // Upload Selfie
          final selfiePath = 'verification_files/${widget.uid}/$ts/selfie.jpg';
          final selfieImageUrl = await _uploadFileToFirebase(data.selfieImageFile!, selfiePath);

          // Upload Supporting Docs
          final List<String> supportingDocUrls = [];
          for (int i = 0; i < data.supportingDocs.length; i++) {
            final docPath = 'verification_files/${widget.uid}/$ts/doc_$i.jpg';
            final url = await _uploadFileToFirebase(data.supportingDocs[i], docPath);
            supportingDocUrls.add(url);
          }

          // Save to Database
          final Map<String, dynamic> fields = {
            for (final e in data.fieldControllers.entries) _sanitizeKey(e.key): e.value.text.trim(),
          };

          await firebaseService.saveVerificationData(
            token: widget.token, 
            uid: widget.uid, 
            idType: data.idType, 
            fields: fields, 
            idImageUrl: idImageUrl, 
            selfieImageUrl: selfieImageUrl, 
            supportingDocUrls: supportingDocUrls
          );

          // 2. CLOSE LOADING DIALOG
          if (!mounted) return;
          Navigator.of(context).pop();

          // 3. REFRESH USER DATA (Background)
          _loadUserDetails();

          // 4. SHOW SUCCESS DIALOG
          await _showVerificationSuccessDialog();

        } catch (error) {
          // If Error: Close Loading, Show Error Snackbar
          if (!mounted) return;
          Navigator.of(context).pop(); 
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Submission Failed: $error"), 
              backgroundColor: Colors.red
            )
          );
        }
      },

      // --- 2. UPDATE PROFILE LOGIC ---
      onUpdateProfile: (Map<String, dynamic> fields) async {
        showDialog(context: context, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator()));
        try {
          final current = Map<String, dynamic>.from(userProfile!);
          final updated = {...current, ...fields};
          String t = (updated['title'] ?? '').toString().trim();
          String f = (updated['firstName'] ?? '').toString().trim();
          String m = (updated['middleName'] ?? '').toString().trim();
          String l = (updated['lastName'] ?? '').toString().trim();
          String newFullName = [if (t.isNotEmpty) t, if (f.isNotEmpty) f, if (m.isNotEmpty) m, if (l.isNotEmpty) l].join(' ');
          
          final patch = {...fields};
          if (newFullName.isNotEmpty) patch['fullName'] = newFullName;

          await firebaseService.updateUserProfileFields(uid: widget.uid, token: widget.token, fields: patch);
          
          if (!mounted) return;
          Navigator.of(context).pop();
          
          setState(() {
            userProfile = updated..addAll({'fullName': newFullName.isNotEmpty ? newFullName : updated['fullName']});
            username = userProfile!['username'] ?? username;
            fullName = userProfile!['fullName'] ?? fullName;
            address = userProfile!['address'] ?? address;
          });

          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Profile updated")));
        } catch (e) {
          if (!mounted) return;
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Update failed: $e")));
        }
      },

      // --- 3. CHANGE PHOTO LOGIC ---
      onChangePhoto: () async {
        final picker = ImagePicker();
        final XFile? picked = await picker.pickImage(source: ImageSource.gallery);
        if (picked == null) return;
        
        showDialog(context: context, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator()));
        
        try {
          final path = 'profiles/${widget.uid}/profile.jpg';
          final url = await _uploadFileToFirebase(File(picked.path), path);
          final cacheBustedUrl = "$url&v=${DateTime.now().millisecondsSinceEpoch}";

          await firebaseService.updateUserProfilePicture(uid: widget.uid, token: widget.token, imageUrl: cacheBustedUrl);
          
          if (!mounted) return;
          setState(() => profilePictureUrl = cacheBustedUrl);
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Profile photo updated")));
        } catch (e) {
          if (!mounted) return;
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Upload failed: $e")));
        }
      },
    );
  }

  
  Widget _buildLockedFeaturePage(String featureName, String reason) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.lock_outline_rounded, size: 80, color: Colors.grey.shade500),
            const SizedBox(height: 24),
            Text('$featureName Locked', textAlign: TextAlign.center, style: GoogleFonts.lato(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.black54)),
            const SizedBox(height: 12),
            Text(reason, textAlign: TextAlign.center, style: GoogleFonts.lato(fontSize: 16, color: Colors.grey.shade600)),
          ],
        ),
      ),
    );
  }

  Widget _buildNotificationsPage() {
    final bool isVerified = isUserVerified ?? false;
    if (!isVerified) {
      return _buildLockedFeaturePage("Notifications", "You must verify your account to view notifications.");
    }
    
    return Padding(
      padding: const EdgeInsets.all(16),
      child: _mergedNotifications.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.notifications_off_outlined, size: 60, color: Colors.grey.shade400),
                  const SizedBox(height: 16),
                  Text("No status updates yet", style: GoogleFonts.lato(fontSize: 18, color: Colors.grey)),
                  const SizedBox(height: 8),
                  const Text("Pending requests are hidden until updated.", style: TextStyle(color: Colors.grey, fontSize: 12)),
                ],
              ),
            )
          : ListView.separated(
              itemCount: _mergedNotifications.length,
              separatorBuilder: (_, __) => const Divider(),
              itemBuilder: (context, index) {
                final notification = _mergedNotifications[index];
                
                String title = "📄 ${notification['title']}";
                String status = (notification['status'] ?? '').toString();
                String subtitle = "Status: $status";
                
                // Construct the unique key for this specific update
                String uniqueKey = "${notification['id']}_$status";
                bool isNew = !_viewedRequestKeys.contains(uniqueKey);

                IconData icon;
                Color iconColor;

                // Status Logic
                String lowerStatus = status.toLowerCase();
                if (lowerStatus.contains('success') || lowerStatus.contains('release') || lowerStatus.contains('approv')) {
                  icon = Icons.check_circle;
                  iconColor = Colors.green;
                } else if (lowerStatus.contains('reject') || lowerStatus.contains('cancel') || lowerStatus.contains('denied') || lowerStatus.contains('disapprov')) {
                  icon = Icons.cancel;
                  iconColor = Colors.red;
                } else if (lowerStatus.contains('process')) {
                  icon = Icons.sync;
                  iconColor = Colors.blue;
                } else if (lowerStatus.contains('sign')) {
                  icon = Icons.edit_document;
                  iconColor = Colors.orange;
                } else {
                  icon = Icons.info;
                  iconColor = Colors.grey;
                }

                return Container(
                  color: isNew ? Colors.blue.withOpacity(0.05) : Colors.transparent, // Highlight background if new
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    leading: Stack(
                      children: [
                        CircleAvatar(
                          backgroundColor: iconColor.withOpacity(0.1),
                          child: Icon(icon, color: iconColor),
                        ),
                        if (isNew)
                          Positioned(
                            right: 0,
                            top: 0,
                            child: Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                color: Colors.red,
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 2),
                              ),
                            ),
                          ),
                      ],
                    ),
                    title: Row(
                      children: [
                        Expanded(
                          child: Text(
                            title, 
                            style: GoogleFonts.lato(
                              fontWeight: isNew ? FontWeight.w900 : FontWeight.bold, 
                              fontSize: 16,
                              color: isNew ? Colors.black : Colors.black87
                            )
                          ),
                        ),
                        if (isNew)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            margin: const EdgeInsets.only(left: 8),
                            decoration: BoxDecoration(
                              color: Colors.red,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              "NEW",
                              style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                          ),
                      ],
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 4),
                        Text(subtitle, style: TextStyle(fontWeight: isNew ? FontWeight.bold : FontWeight.normal, color: Colors.black87)),
                        const SizedBox(height: 4),
                        Text(
                          _formatTimestamp(notification['timestamp']), 
                          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                        ),
                      ],
                    ),
                    onTap: () {
                      _markStatusAsViewed(notification['id'], status);

                      Navigator.push(
                        context, 
                        MaterialPageRoute(
                          builder: (_) => UserRequestStatusPage(
                            token: widget.token, 
                            uid: widget.uid, 
                            email: widget.email,
                            highlightRequestId: notification['id'], // <--- PASS THE ID HERE
                          )
                        )
                      ).then((_) {
                        setState(() {});
                      });
                    },
                  ),
                );
              },
            ),
    );
  }
  // Helper to format date cleanly
  String _formatTimestamp(dynamic timestamp) {
    if (timestamp == null || timestamp.toString().isEmpty) return "Just now";
    try {
      String str = timestamp.toString();
      DateTime dt;

      // Handle numeric timestamps (int or double)
      // Removes decimal point if present (e.g. "12345.0" -> "12345")
      if (RegExp(r'^\d+(\.\d+)?$').hasMatch(str)) {
        double val = double.parse(str);
        int millis = val.toInt();
        // Adjust for seconds vs milliseconds
        if (millis < 10000000000) millis *= 1000; 
        dt = DateTime.fromMillisecondsSinceEpoch(millis);
      } else {
        dt = DateTime.parse(str);
      }
      return "${dt.month}/${dt.day}/${dt.year}";
    } catch (_) {
      return "Just now";
    }
  }

Widget _buildAnnouncementBanner() {
  if (_announcements.isEmpty || !_hasUnreadAnnouncement) {
    return const SizedBox.shrink();
  }

  final unreadAnnouncement = _announcements.firstWhere(
    (ann) => !_viewedAnnouncementIds.contains(ann['id']),
    orElse: () => _announcements.first,
  );

  return GestureDetector(
    onTap: () {
      _markAnnouncementAsViewed(unreadAnnouncement['id']);
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              FullScreenAnnouncementPage(announcement: unreadAnnouncement),
        ),
      );
    },
    child: Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          colors: [
            Colors.amber.shade600,
            Colors.amber.shade400,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color.fromARGB(255, 223, 3, 204).withOpacity(0.35),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Decorative background circle
          Positioned(
            right: -20,
            top: -20,
            child: Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.15),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                // Icon container
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.25),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.campaign_rounded,
                      color: Color.fromARGB(255, 0, 0, 0), size: 28),
                ),
                const SizedBox(width: 16),
                // Text content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'NEW ANNOUNCEMENT',
                        style: TextStyle(
                          color: const Color.fromARGB(255, 0, 0, 0).withOpacity(0.7),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        unreadAnnouncement['title'] ?? 'Announcement',
                        style: GoogleFonts.lato(
                          fontSize: 16,
                          color: Colors.black87,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Arrow button
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.25),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.arrow_forward,
                      color: const Color.fromARGB(255, 0, 0, 0), size: 18),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
  
  Widget _buildVerifiedBanner() {
    return Container(
      color: Colors.green.shade600,
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          const Icon(Icons.check_circle, color: Colors.white),
          const SizedBox(width: 12),
          const Expanded(child: Text("Congratulations! Your account is now verified.", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16), textAlign: TextAlign.center)),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: () async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setBool('verified_banner_shown_${widget.uid}', true);
              setState(() => _showJustVerifiedBanner = false);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildProfileHeader() {
    // Get phone number or email safely
    String contactInfo = userProfile?['email'] ?? "";


    return Column(
      children: [
        Container(padding: const EdgeInsets.all(0)),
        const SizedBox(height: 5),
        Text("Welcome", style: GoogleFonts.lato(fontSize: 28, fontWeight: FontWeight.w600, color: Colors.deepPurple.shade900)),
        const SizedBox(height: 4),
        Text(
          (userProfile != null && userProfile!['username'] != null && userProfile!['username'].toString().trim().isNotEmpty ? userProfile!['username'] : 'User'),
          style: GoogleFonts.lato(fontSize: 18, fontWeight: FontWeight.w500, color: Colors.deepPurple.shade700),
          textAlign: TextAlign.center,
        ),
        // --- ADD PHONE NUMBER DISPLAY ---
        const SizedBox(height: 4),
        Text(
          contactInfo,
          style: GoogleFonts.lato(fontSize: 14, color: Colors.grey.shade600),
        ),
        // --------------------------------
      ],
    );
  }
  Widget _buildActionCard(BuildContext context) {
    final bool isVerified = isUserVerified ?? false;
    return Card(
      elevation: 16,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      shadowColor: Colors.deepPurple.withOpacity(0.2),
      child: Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(24), gradient: LinearGradient(colors: [Colors.white, Colors.deepPurple.shade50], begin: Alignment.topLeft, end: Alignment.bottomRight)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 4. ADD ENABLE AUTO SCROLL TO ENSURE VISIBILITY
            Showcase(
              key: _reqDocKey,
              title: 'Request Documents',
              description: 'Tap here to request official barangay documents like clearances or permits.',
              enableAutoScroll: true, // <--- ADD THIS
              child: _buildActionButton(context: context, icon: Icons.description_rounded, label: "Request Document", color: Colors.deepPurple, isEnabled: isVerified, onPressed: () => _navigateToRequestDocument(context)),
            ),
            const SizedBox(height: 24),
            
            Showcase(
              key: _reqStatusKey,
              title: 'Check Status',
              description: 'Track the progress of your document requests here.',
              enableAutoScroll: true, // <--- ADD THIS
              child: _buildActionButton(context: context, icon: Icons.visibility_rounded, label: "View Request Status", color: Colors.teal, isEnabled: isVerified, onPressed: () => _navigateToRequestStatus(context)),
            ),
            const SizedBox(height: 24),
            
            Showcase(
              key: _apptKey,
              title: 'Appointments',
              description: 'Schedule an appointment with barangay officials here.',
              enableAutoScroll: true, // <--- ADD THIS
              child: _buildActionButton(context: context, icon: Icons.calendar_today, label: "Request Appointment", color: Colors.blueAccent, isEnabled: isVerified, onPressed: () => _navigateToAppointmentRequest(context)),
            ),
            const SizedBox(height: 24),
            
            Showcase(
              key: _complaintKey,
              title: 'File Complaints',
              description: 'Report issues or file complaints directly to the barangay office.',
              enableAutoScroll: true, // <--- ADD THIS
              child: _buildActionButton(context: context, icon: Icons.report_problem, label: "Complaint", color: Colors.orange, isEnabled: isVerified, onPressed: () => _navigateToComplaint(context)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required BuildContext context,
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onPressed,
    required bool isEnabled
  }) {
    final VoidCallback effectiveOnPressed = isEnabled ? onPressed : () {
      ScaffoldMessenger.of(context).clearSnackBars(); 
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.error_outline, color: Colors.white),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  "Your account has not been verified yet.",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          backgroundColor: Colors.red.shade700, 
          behavior: SnackBarBehavior.floating, 
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          margin: const EdgeInsets.all(16),
          duration: const Duration(seconds: 2),
        )
      );
    };

    return ElevatedButton.icon(
      icon: Icon(icon, size: 28),
      label: Align(alignment: Alignment.centerLeft, child: Text(label, style: GoogleFonts.lato(fontSize: 18, fontWeight: FontWeight.w600))),
      onPressed: effectiveOnPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: isEnabled ? color : Colors.grey.shade400,
        foregroundColor: Colors.white,
        elevation: isEnabled ? 4 : 0,
        shadowColor: color.withOpacity(0.3),
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 28),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        minimumSize: const Size(double.infinity, 56),
      ),
    );
  }

Widget _buildAnnouncementIcon() {
  int unreadCount = _announcements
      .where((ann) => !_viewedAnnouncementIds.contains(ann['id']))
      .length;

  return Stack(
    children: [
      IconButton(
        icon: const Icon(Icons.campaign_rounded, color: Colors.white, size: 28),
        tooltip: 'Announcements',
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => BarangayAnnouncementsPage(
                announcements: _announcements,
                viewedIds: _viewedAnnouncementIds,
                onAnnouncementViewed: _markAnnouncementAsViewed,
              ),
            ),
          ).then((_) => setState(() {}));
        },
      ),
      if (unreadCount > 0)
        Positioned(
          right: 4,
          top: 4,
          child: Container(
            padding: const EdgeInsets.all(4),
            constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
            decoration: BoxDecoration(
              color: Colors.red,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.deepPurple.shade700, width: 2),
            ),
            child: Text(
              unreadCount > 9 ? '9+' : '$unreadCount',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
    ],
  );
}

  Widget _buildBottomNavigationBar() {
    int unreadCount = _getUnreadNotificationCount();

    return BottomNavigationBar(
      currentIndex: _currentIndex,
      onTap: (index) {
        setState(() {
          _currentIndex = index;
          if (index != 2) _selectedNotificationIds.clear();
        });
        
        if (index == 0 && isUserVerified == true) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _checkAndStartTutorial());
        }
      },
      items: [
        const BottomNavigationBarItem(icon: Icon(Icons.home), label: "Home"),
        
        BottomNavigationBarItem(
          icon: Showcase(
            key: _profileIconKey,
            title: 'Verify Your Account',
            description: 'Tap here to verify your profile to unlock all features.',
            targetBorderRadius: BorderRadius.circular(50), 
            child: const Icon(Icons.person),
          ),
          label: "Profile",
        ),
        
        // --- FIXED NOTIFICATION ITEM ---
        BottomNavigationBarItem(
          label: "Notifications",
          icon: SizedBox( // 1. Force a specific size so it doesn't disappear
            width: 24, 
            height: 24, 
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // 2. The Main Icon (Make sure this line is here!)
                const Center(child: Icon(Icons.notifications)), 
                
                // 3. The Red Badge
                if (unreadCount > 0)
                  Positioned(
                    right: -6, // Adjusted to hang slightly off the edge
                    top: -6,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 1.5),
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 16,
                        minHeight: 16,
                      ),
                      child: Center(
                        child: Text(
                          unreadCount > 9 ? '9+' : '$unreadCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 7,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
      selectedItemColor: Colors.deepPurple,
      unselectedItemColor: Colors.grey,
      backgroundColor: Colors.white,
    );
  }

  Widget _buildAppDrawer() {
    // 1. Get data safely from profile or widget params
    String displayEmail = (userProfile?['email'] ?? widget.email).toString().trim();
    String displayPhone = (userProfile?['phoneNumber'] ?? '').toString().trim();

    // Cleanup: sometimes 'N/A' might be saved string, treat as empty
    if (displayEmail == 'N/A') displayEmail = '';
    if (displayPhone == 'N/A') displayPhone = '';

    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: <Widget>[
          UserAccountsDrawerHeader(
            accountName: Text(
              username ?? "User",
              style: GoogleFonts.lato(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            // 2. Logic to display available contact info
            accountEmail: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min, // Shrink to fit content
              children: [
                // A. Show Email if available
                if (displayEmail.isNotEmpty)
                  Text(displayEmail, style: GoogleFonts.lato(fontSize: 14)),

                // B. Show Phone if available
                if (displayPhone.isNotEmpty)
                  Padding(
                    // Add small padding top only if email is also showing
                    padding: EdgeInsets.only(top: displayEmail.isNotEmpty ? 4.0 : 0),
                    child: Text(
                      displayPhone,
                      style: GoogleFonts.lato(
                        fontSize: 14,
                        // If email exists, make phone slightly dimmer (secondary info)
                        // If email is empty (Phone Login), make phone bright white (primary info)
                        color: displayEmail.isNotEmpty ? const Color.fromARGB(179, 155, 154, 154) : const Color.fromARGB(255, 214, 213, 213),
                      ),
                    ),
                  ),
                
                // C. Fallback
                if (displayEmail.isEmpty && displayPhone.isEmpty)
                   Text("No contact info", style: GoogleFonts.lato(fontSize: 14, fontStyle: FontStyle.italic)),
              ],
            ),
            currentAccountPicture: CircleAvatar(
              backgroundColor: Colors.white,
              backgroundImage: profilePictureUrl != null ? NetworkImage(profilePictureUrl!) : null,
              child: profilePictureUrl == null
                  ? Icon(Icons.person, size: 48, color: Colors.deepPurple.shade700)
                  : null,
            ),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.deepPurple.shade700, Colors.deepPurple.shade400],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.settings),
            title: Text('Settings', style: GoogleFonts.lato()),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (context) => const SettingsPage()));
            },
          ),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: Text('About', style: GoogleFonts.lato()),
            onTap: () {
              Navigator.pop(context);
              showAboutDialog(context: context, applicationName: "BaSe App", applicationVersion: "1.0", applicationLegalese: "© Barangay Services(BaSe)");
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.redAccent),
            title: Text('Logout', style: GoogleFonts.lato(color: Colors.redAccent, fontWeight: FontWeight.bold)),
            onTap: () async {
              Navigator.pop(context);
              final bool? confirmLogout = await showDialog(
                context: context,
                builder: (BuildContext context) {
                  return AlertDialog(
                    title: Text('Confirm Logout', style: GoogleFonts.lato()),
                    content: Text('Are you sure you want to log out?', style: GoogleFonts.lato()),
                    actions: <Widget>[
                      TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text('Cancel', style: GoogleFonts.lato())),
                      TextButton(onPressed: () => Navigator.of(context).pop(true), child: Text('Logout', style: GoogleFonts.lato(color: Colors.red))),
                    ],
                  );
                },
              );
              if (confirmLogout == true) await logout(context);
            },
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    String title = "";
    List<Widget> actions = [];
    final bool isVerified = isUserVerified ?? false;

    if (_currentIndex == 2) {
      if (_selectedNotificationIds.isNotEmpty) {
        title = "Select Notifications (${_selectedNotificationIds.length})";
        actions.add(TextButton(onPressed: () => setState(() => _selectedNotificationIds = _announcements.map((ann) => ann['id'] as String).toSet()), child: Text("Select All", style: GoogleFonts.lato(color: Colors.white))));
        actions.add(IconButton(
          onPressed: () async {
            final confirmed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
              title: Text("Delete Selected", style: GoogleFonts.lato()),
              content: Text("Are you sure you want to delete all selected notifications?", style: GoogleFonts.lato()),
              actions: [
                TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text("Cancel", style: GoogleFonts.lato())),
                TextButton(onPressed: () => Navigator.of(context).pop(true), child: Text("Delete", style: GoogleFonts.lato(color: Colors.red))),
              ],
            ));
            if (confirmed == true) await _deleteSelectedAnnouncements();
          },
          icon: const Icon(Icons.delete, color: Colors.white),
        ));
        actions.add(IconButton(onPressed: () => setState(() => _selectedNotificationIds.clear()), icon: const Icon(Icons.cancel, color: Colors.white)));
      } else {
        title = "Notifications";
        if (isVerified) actions.add(_buildAnnouncementIcon());
        else actions.add(_buildUnverifiedIcon()); // <-- Added Info Icon
      }
    } else if (_currentIndex == 0) {
      title = "Dashboard";
      if (isVerified) actions.add(_buildAnnouncementIcon());
      else actions.add(_buildUnverifiedIcon()); // <-- Added Info Icon
    } else if (_currentIndex == 1) {
      title = "Profile";
      if (!isVerified) actions.add(_buildUnverifiedIcon()); // <-- Added Info Icon
    } else {
      title = "App";
    }
    
    return AppBar(
      iconTheme: const IconThemeData(color: Colors.white),
      title: Text(title, style: GoogleFonts.lato(fontSize: 24, fontWeight: FontWeight.w700, color: Colors.white)),
      centerTitle: true,
      flexibleSpace: Container(decoration: BoxDecoration(gradient: LinearGradient(colors: [Colors.deepPurple.shade700, Colors.deepPurple.shade400], begin: Alignment.topLeft, end: Alignment.bottomRight))),
      actions: actions,
    );
  }
  
  @override
  Widget build(BuildContext context) {
    return ShowCaseWidget(
      builder: (context) {
        _showCaseContext = context; 
        final pages = [_buildHomePage(), _buildProfilePage(), _buildNotificationsPage()];
        return Scaffold(
          backgroundColor: const Color.fromARGB(255, 208, 150, 231),
          appBar: _buildAppBar(),
          drawer: _buildAppDrawer(),
          body: RefreshIndicator(
            onRefresh: _loadUserDetails,
            child: Stack(
              children: [
                IndexedStack(index: _currentIndex, children: pages),
                
                if (_showJustVerifiedBanner)
                  Positioned(top: 0, left: 0, right: 0, child: _buildVerifiedBanner()),

                // ---> ADD THE NEW SIDE BUTTON HERE <---
                if (isUserVerified == true && !_isLoadingSurveyStatus && !_isSurveyCompleted && _currentIndex == 0)
                  _buildSideSurveyButton(),
              ],
            ),
          ),
          bottomNavigationBar: _buildBottomNavigationBar(),
        );
      },
    );
  }
}

class FullScreenAnnouncementPage extends StatelessWidget {
  final Map<String, dynamic> announcement;
  const FullScreenAnnouncementPage({super.key, required this.announcement});

  String _formatDate(dynamic timestamp) {
    if (timestamp == null || timestamp.toString().isEmpty) return '';
    try {
      final str = timestamp.toString();
      DateTime dt;
      if (RegExp(r'^\d+(\.\d+)?$').hasMatch(str)) {
        int ms = double.parse(str).toInt();
        if (ms < 10000000000) ms *= 1000;
        dt = DateTime.fromMillisecondsSinceEpoch(ms);
      } else {
        dt = DateTime.parse(str);
      }
      const months = [
        'January', 'February', 'March', 'April', 'May', 'June',
        'July', 'August', 'September', 'October', 'November', 'December'
      ];
      return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final imageUrl = (announcement['imageUrl'] ?? '').toString();
    final whenText = (announcement['when'] ?? '').toString();
    final whereText = (announcement['where'] ?? '').toString();
    final dateText = _formatDate(announcement['timestamp']);
    final hasImage = imageUrl.isNotEmpty;
    final hasDetails = whenText.isNotEmpty || whereText.isNotEmpty;

    return Scaffold(
      backgroundColor: Colors.white,
      body: CustomScrollView(
        slivers: [
          // ── Collapsing header with image ──
SliverAppBar(
  expandedHeight: hasImage ? 300 : 120,
  pinned: true,
  backgroundColor: Colors.deepPurple.shade700,
  foregroundColor: Colors.white,
  // ── ADD THIS: Back button with visible background ──
  leading: Padding(
    padding: const EdgeInsets.all(8.0),
    child: GestureDetector(
      onTap: () => Navigator.pop(context),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.45),
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.arrow_back, color: Colors.white, size: 22),
      ),
    ),
  ),
  flexibleSpace: FlexibleSpaceBar(
    background: hasImage
        ? GestureDetector(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    AnnouncementImageViewer(imageUrl: imageUrl),
              ),
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Hero(
                  tag: imageUrl,
                  child: Image.network(
                    imageUrl,
                    fit: BoxFit.cover,
                    loadingBuilder: (_, c, p) {
                      if (p == null) return c;
                      return Container(
                          color: Colors.deepPurple.shade50,
                          child: const Center(
                              child: CircularProgressIndicator()));
                    },
                    errorBuilder: (_, __, ___) => Container(
                      color: Colors.deepPurple.shade100,
                      child: const Icon(Icons.broken_image,
                          size: 50, color: Colors.white54),
                    ),
                  ),
                ),
                // ── TOP gradient so back button area is always visible ──
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.center,
                      colors: [Colors.black45, Colors.transparent],
                    ),
                  ),
                ),
                // Bottom gradient for readability
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.center,
                      colors: [Colors.black54, Colors.transparent],
                    ),
                  ),
                ),
                Positioned(
                  bottom: 16,
                  right: 16,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.zoom_in,
                            color: Colors.white, size: 16),
                        SizedBox(width: 4),
                        Text('Tap to zoom',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 12)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          )
        : Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.deepPurple.shade700,
                  Colors.deepPurple.shade400
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
  ),
),
          // ── Content ──
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // label
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.deepPurple.shade50,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text('📢  Barangay Announcement',
                        style: GoogleFonts.lato(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.deepPurple)),
                  ),
                  const SizedBox(height: 16),

                  // title
                  Text(
                    announcement['title'] ?? 'No Title',
                    style: GoogleFonts.lato(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                        height: 1.3),
                  ),

                  // posted date
                  if (dateText.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text('Posted $dateText',
                        style: GoogleFonts.lato(
                            fontSize: 14, color: Colors.grey.shade500)),
                  ],

                  const SizedBox(height: 20),

                  // when / where card
                  if (hasDetails)
                    Container(
                      padding: const EdgeInsets.all(20),
                      margin: const EdgeInsets.only(bottom: 24),
                      decoration: BoxDecoration(
                        color: Colors.deepPurple.shade50,
                        borderRadius: BorderRadius.circular(16),
                        border:
                            Border.all(color: Colors.deepPurple.shade100),
                      ),
                      child: Column(
                        children: [
                          if (whenText.isNotEmpty)
                            _detailRow(Icons.calendar_today_rounded,
                                'When', whenText, Colors.deepPurple),
                          if (whenText.isNotEmpty && whereText.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                  vertical: 12),
                              child: Divider(
                                  color: Colors.deepPurple.shade100,
                                  height: 1),
                            ),
                          if (whereText.isNotEmpty)
                            _detailRow(Icons.location_on_rounded, 'Where',
                                whereText, Colors.redAccent),
                        ],
                      ),
                    ),

                  Divider(color: Colors.grey.shade200, height: 1),
                  const SizedBox(height: 24),

                  // message body
                  Text(
                    announcement['message'] ?? '',
                    style: GoogleFonts.lato(
                        fontSize: 16,
                        height: 1.8,
                        color: Colors.black87),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(
      IconData icon, String label, String value, Color color) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: GoogleFonts.lato(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w500)),
              const SizedBox(height: 2),
              Text(value,
                  style: GoogleFonts.lato(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87)),
            ],
          ),
        ),
      ],
    );
  }
}

class AnnouncementImageViewer extends StatelessWidget {
  final String imageUrl;
  const AnnouncementImageViewer({super.key, required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      extendBodyBehindAppBar: true,
      body: Center(
        child: Hero(
          tag: imageUrl,
          child: InteractiveViewer(
            panEnabled: true,
            boundaryMargin: const EdgeInsets.all(20),
            minScale: 0.5,
            maxScale: 4.0,
            child: Image.network(
              imageUrl,
              loadingBuilder: (_, child, progress) {
                if (progress == null) return child;
                return const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
class BarangayAnnouncementsPage extends StatefulWidget {
  final List<Map<String, dynamic>> announcements;
  final Set<String> viewedIds;
  final Function(String) onAnnouncementViewed;

  const BarangayAnnouncementsPage({
    super.key,
    required this.announcements,
    required this.viewedIds,
    required this.onAnnouncementViewed,
  });

  @override
  State<BarangayAnnouncementsPage> createState() =>
      _BarangayAnnouncementsPageState();
}

class _BarangayAnnouncementsPageState extends State<BarangayAnnouncementsPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  // ── Helpers ──────────────────────────────────────────────

  List<Map<String, dynamic>> _filter(List<Map<String, dynamic>> list) {
    if (_searchQuery.isEmpty) return list;
    final q = _searchQuery.toLowerCase();
    return list.where((a) {
      final t = (a['title'] ?? '').toString().toLowerCase();
      final m = (a['message'] ?? '').toString().toLowerCase();
      return t.contains(q) || m.contains(q);
    }).toList();
  }

  String _relativeTime(dynamic timestamp) {
    if (timestamp == null || timestamp.toString().isEmpty) return '';
    try {
      final str = timestamp.toString();
      DateTime dt;
      if (RegExp(r'^\d+(\.\d+)?$').hasMatch(str)) {
        int ms = double.parse(str).toInt();
        if (ms < 10000000000) ms *= 1000;
        dt = DateTime.fromMillisecondsSinceEpoch(ms);
      } else {
        dt = DateTime.parse(str);
      }
      final diff = DateTime.now().difference(dt);
      if (diff.inMinutes < 1) return 'Just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      if (diff.inDays < 7) return '${diff.inDays}d ago';
      const m = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ];
      return '${m[dt.month - 1]} ${dt.day}, ${dt.year}';
    } catch (_) {
      return '';
    }
  }

  void _openAnnouncement(Map<String, dynamic> ann) {
    widget.onAnnouncementViewed(ann['id']);
    setState(() {});
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FullScreenAnnouncementPage(announcement: ann),
      ),
    );
  }

  // ── Build ────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final all = _filter(widget.announcements);
    final unread =
        all.where((a) => !widget.viewedIds.contains(a['id'])).toList();
    final totalUnread = widget.announcements
        .where((a) => !widget.viewedIds.contains(a['id']))
        .length;

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.deepPurple.shade700,
        foregroundColor: Colors.white,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.deepPurple.shade700,
                Colors.deepPurple.shade400
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                style: const TextStyle(color: Colors.white, fontSize: 18),
                decoration: InputDecoration(
                  hintText: 'Search announcements…',
                  hintStyle: TextStyle(color: Colors.white.withOpacity(0.6)),
                  border: InputBorder.none,
                ),
                onChanged: (v) => setState(() => _searchQuery = v),
              )
            : Text('Announcements',
                style:
                    GoogleFonts.lato(fontWeight: FontWeight.bold, fontSize: 22)),
        actions: [
          IconButton(
            icon: Icon(_isSearching ? Icons.close : Icons.search),
            onPressed: () => setState(() {
              _isSearching = !_isSearching;
              if (!_isSearching) {
                _searchQuery = '';
                _searchController.clear();
              }
            }),
          ),
        ],
bottom: TabBar(
  controller: _tabController,
  indicatorColor: Colors.amber.shade400,        // Gold indicator line
  indicatorWeight: 3,
  labelColor: Colors.amber.shade300,             // Selected tab = gold
  unselectedLabelColor: const Color.fromARGB(255, 255, 255, 255),          // Unselected tab = faded white
  labelStyle:
      GoogleFonts.lato(fontWeight: FontWeight.bold, fontSize: 15),
  unselectedLabelStyle: GoogleFonts.lato(fontSize: 14),
  tabs: [
    const Tab(text: 'All'),
    Tab(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Unread'),
          if (totalUnread > 0) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.amber.shade500,    // Gold badge background
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text('$totalUnread',
                  style: const TextStyle(
                      color: Colors.black87,     // Dark text on gold badge
                      fontSize: 12,
                      fontWeight: FontWeight.bold)),
            ),
          ],
        ],
      ),
    ),
  ],
),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildList(all, emptyIsSearch: _searchQuery.isNotEmpty),
          _buildList(unread, isUnreadTab: true),
        ],
      ),
    );
  }

  // ── List builder ─────────────────────────────────────────

  Widget _buildList(
    List<Map<String, dynamic>> items, {
    bool isUnreadTab = false,
    bool emptyIsSearch = false,
  }) {
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isUnreadTab
                  ? Icons.mark_email_read_outlined
                  : (emptyIsSearch
                      ? Icons.search_off_rounded
                      : Icons.campaign_outlined),
              size: 80,
              color: Colors.grey.shade300,
            ),
            const SizedBox(height: 20),
            Text(
              isUnreadTab
                  ? 'All caught up!'
                  : (emptyIsSearch
                      ? 'No results found'
                      : 'No announcements yet'),
              style: GoogleFonts.lato(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade500),
            ),
            const SizedBox(height: 8),
            Text(
              isUnreadTab
                  ? "You've read every announcement"
                  : (emptyIsSearch
                      ? 'Try a different keyword'
                      : 'Check back later for updates'),
              style: GoogleFonts.lato(
                  fontSize: 14, color: Colors.grey.shade400),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: items.length,
      itemBuilder: (_, i) {
        final ann = items[i];
        final isUnread = !widget.viewedIds.contains(ann['id']);
        final imageUrl = (ann['imageUrl'] ?? '').toString();
        final hasImage = imageUrl.isNotEmpty;
        final when = (ann['when'] ?? '').toString();
        final where = (ann['where'] ?? '').toString();
        final time = _relativeTime(ann['timestamp']);

        // First unread item with an image → featured card
        if (i == 0 && isUnread && hasImage) {
          return _featuredCard(ann, time, when, where);
        }
        return _regularCard(ann, isUnread, hasImage, imageUrl, time, when);
      },
    );
  }

  // ── Featured card ────────────────────────────────────────

  Widget _featuredCard(
    Map<String, dynamic> ann,
    String time,
    String when,
    String where,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: GestureDetector(
        onTap: () => _openAnnouncement(ann),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                  color: Colors.deepPurple.withOpacity(0.15),
                  blurRadius: 20,
                  offset: const Offset(0, 8)),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── image area ──
              ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(20)),
                child: Stack(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      height: 200,
                      child: Image.network(
                        ann['imageUrl'] ?? '',
                        fit: BoxFit.cover,
                        loadingBuilder: (_, child, p) {
                          if (p == null) return child;
                          return Container(
                              color: Colors.deepPurple.shade50,
                              child: const Center(
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2)));
                        },
                        errorBuilder: (_, __, ___) => Container(
                            color: Colors.deepPurple.shade50,
                            child: Icon(Icons.campaign,
                                size: 60,
                                color: Colors.deepPurple.shade200)),
                      ),
                    ),
                    // gradient overlay
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black.withOpacity(0.35)
                            ],
                          ),
                        ),
                      ),
                    ),
                    // NEW badge
                    Positioned(
                      top: 12,
                      left: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                            color: Colors.deepPurple,
                            borderRadius: BorderRadius.circular(20)),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.fiber_new,
                                color: Colors.white, size: 16),
                            const SizedBox(width: 4),
                            Text('NEW',
                                style: GoogleFonts.lato(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12)),
                          ],
                        ),
                      ),
                    ),
                    // time badge
                    if (time.isNotEmpty)
                      Positioned(
                        top: 12,
                        right: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.5),
                              borderRadius: BorderRadius.circular(20)),
                          child: Text(time,
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 12)),
                        ),
                      ),
                  ],
                ),
              ),

              // ── text area ──
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ann['title'] ?? 'Announcement',
                      style: GoogleFonts.lato(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.deepPurple.shade900),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      ann['message'] ?? '',
                      style: GoogleFonts.lato(
                          fontSize: 14,
                          color: Colors.grey.shade600,
                          height: 1.4),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (when.isNotEmpty || where.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        children: [
                          if (when.isNotEmpty)
                            _infoChip(Icons.event, when, Colors.deepPurple),
                          if (where.isNotEmpty)
                            _infoChip(
                                Icons.place, where, Colors.redAccent),
                        ],
                      ),
                    ],
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text('Read more →',
                          style: GoogleFonts.lato(
                              color: Colors.deepPurple,
                              fontWeight: FontWeight.w600,
                              fontSize: 14)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Regular card ─────────────────────────────────────────

  Widget _regularCard(
    Map<String, dynamic> ann,
    bool isUnread,
    bool hasImage,
    String imageUrl,
    String time,
    String when,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        onTap: () => _openAnnouncement(ann),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: Colors.white,
            border: isUnread
                ? Border.all(color: Colors.deepPurple.shade200, width: 1.5)
                : null,
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4)),
            ],
          ),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // thumbnail
                if (hasImage)
                  ClipRRect(
                    borderRadius: const BorderRadius.horizontal(
                        left: Radius.circular(16)),
                    child: SizedBox(
                      width: 110,
                      child: Image.network(
                        imageUrl,
                        fit: BoxFit.cover,
                        loadingBuilder: (_, c, p) {
                          if (p == null) return c;
                          return Container(
                              color: Colors.deepPurple.shade50,
                              child: const Center(
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2)));
                        },
                        errorBuilder: (_, __, ___) => Container(
                            color: Colors.deepPurple.shade50,
                            child: Icon(Icons.campaign,
                                color: Colors.deepPurple.shade200)),
                      ),
                    ),
                  ),
                // text content
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            if (isUnread)
                              Container(
                                width: 8,
                                height: 8,
                                margin: const EdgeInsets.only(right: 8),
                                decoration: const BoxDecoration(
                                    color: Colors.deepPurple,
                                    shape: BoxShape.circle),
                              ),
                            if (!hasImage)
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: Icon(Icons.campaign_rounded,
                                    size: 20,
                                    color: isUnread
                                        ? Colors.deepPurple
                                        : Colors.grey),
                              ),
                            Expanded(
                              child: Text(
                                ann['title'] ?? 'Announcement',
                                style: GoogleFonts.lato(
                                  fontSize: 16,
                                  fontWeight: isUnread
                                      ? FontWeight.bold
                                      : FontWeight.w600,
                                  color: isUnread
                                      ? Colors.deepPurple.shade900
                                      : Colors.black87,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          ann['message'] ?? '',
                          style: GoogleFonts.lato(
                              fontSize: 13,
                              color: Colors.grey.shade600,
                              height: 1.3),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            if (when.isNotEmpty) ...[
                              Icon(Icons.event,
                                  size: 14, color: Colors.grey.shade500),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(when,
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade500),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                              ),
                              const SizedBox(width: 12),
                            ],
                            const Spacer(),
                            Text(time,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isUnread
                                      ? Colors.deepPurple
                                      : Colors.grey.shade500,
                                  fontWeight: isUnread
                                      ? FontWeight.w600
                                      : FontWeight.normal,
                                )),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                // chevron
                Center(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child:
                        Icon(Icons.chevron_right, color: Colors.grey.shade400),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Info chip ────────────────────────────────────────────

  Widget _infoChip(IconData icon, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Flexible(
            child: Text(text,
                style: GoogleFonts.lato(
                    fontSize: 12, color: color, fontWeight: FontWeight.w600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}

