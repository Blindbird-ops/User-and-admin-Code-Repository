// lib/admin_screen.dart

import 'dart:async';
import 'dart:convert';
import 'package:admin_window/screens/map_page.dart'; // Adjust path if needed
import 'package:admin_window/screens/template_manager_page.dart';
import 'package:showcaseview/showcaseview.dart'; // Import this
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:admin_window/firebase_service.dart';
import 'package:admin_window/models/complaint.dart';
import 'package:admin_window/register_screen.dart';
import 'package:admin_window/secretary_offline_page.dart';
import 'package:admin_window/widget/settings_dialog.dart';
import 'package:flutter/material.dart';
import 'package:admin_window/screens/profile_billing_page.dart';
import 'package:admin_window/users/non_verified_users_page.dart';
import 'package:admin_window/users/verified_users_page.dart';
import 'package:admin_window/screens/submitted_requests_page.dart';
import 'services/python_service.dart';
import 'widget/side_menu.dart';
import 'widget/top_navigation_bar.dart';
import 'certification/generated_barangay_clearance_page.dart';
import 'certification/generated_barangay_business_clearance_page.dart';
import 'certification/generated_barangay_certification_page.dart';
import 'certification/generated_barangay_indigent_page.dart';
import 'certification/generated_birth_certificate_page.dart';
import 'login_screen.dart';
import 'package:admin_window/tables/user_table.dart';
import 'package:admin_window/tables/logs_table.dart';
import 'package:admin_window/tables/request_table_wrapper.dart';
import 'package:admin_window/dashboard/dashboard_view.dart';
import 'package:admin_window/services/data_service.dart';
import 'package:admin_window/screens/complaints_page.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:audioplayers/audioplayers.dart';

extension StringCasingExtension on String {
  String toTitleCase() {
    if (isEmpty) return this;
    return split(' ')
        .map((word) => word.isNotEmpty
            ? '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}'
            : '')
        .join(' ');
  }
}

class AdminScreen extends StatefulWidget {
  final String token;
  final String userId;
  final String email;
  const AdminScreen({super.key, required this.token, required this.userId, required this.email,});

  @override
  _AdminScreenState createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  // Data lists
  final List<Map<String, dynamic>> _users = [];
  final List<Map<String, dynamic>> _logs = [];
  final List<Map<String, dynamic>> _requests = [];
  final List<Complaint> _allComplaints = [];
  
  // Notification History List
  final List<Map<String, dynamic>> _notificationHistory = []; 

  String _adminFullName = 'Admin';
  String? _adminProfileImageUrl;
  
  // Tutorial Keys
// Side Menu
// Notification Bell
  final GlobalKey _three = GlobalKey(); // Dashboard / Main Workspace
  final GlobalKey _keyProfile = GlobalKey();
  final GlobalKey _keyProfileBilling = GlobalKey(); // <--- ADD THIS
  final GlobalKey _keyManageAnnounce = GlobalKey(); // <--- ADD THIS
  final GlobalKey _keyPostAnnounce = GlobalKey();
  final GlobalKey _keyOrgChart = GlobalKey();
  final GlobalKey _keySideMap = GlobalKey(); // <--- MAP KEY (MOVED TO SIDE MENU)

  final GlobalKey _keySubRequests = GlobalKey();
  final GlobalKey _keyNonVerifUsers = GlobalKey(); // <--- ADD THIS LINE
  final GlobalKey _keyVerifUsers = GlobalKey();

  // Top Navigation Keys
  final GlobalKey _keyNotif = GlobalKey(); // Existing one
  final GlobalKey _keyTabDashboard = GlobalKey();
  final GlobalKey _keyTabUsers = GlobalKey();
  final GlobalKey _keyTabLogs = GlobalKey();
  final GlobalKey _keyTabRequests = GlobalKey();
  final GlobalKey _keyTabComplaints = GlobalKey();
  final GlobalKey _keySettings = GlobalKey();
  final GlobalKey _keyTabTemplates = GlobalKey(); // <--- ADD THIS


  // Flag to ensure tutorial only checks once per session
  bool _hasCheckedTutorial = false;
  bool _isOfflineMenuOpen = true; 


  // Notification State
  OverlayEntry? _overlayEntry; 
  Timer? _toastTimer;

  // --- AUDIO & TRACKING VARIABLES ---
  final AudioPlayer _audioPlayer = AudioPlayer();
  
  // 1. Requests
  final Set<String> _knownRequestIds = {}; 
  bool _isFirstRequestLoad = true;

  // 2. Complaints
  final Set<String> _knownComplaintIds = {};
  bool _isFirstComplaintLoad = true;

  // 3. Submissions
  final Set<String> _knownSubmissionIds = {};
  bool _isFirstSubmissionLoad = true;
  
  // Connectivity 
  late final Connectivity _connectivity;
  late final Stream<ConnectivityResult> _connectivityStream;
  bool _isOffline = false;

  // Loading and error states
  bool _loadingUsers = true;
  bool _loadingLogs = true;
  bool _loadingRequests = true;
  
  String errorMessage = '';

  // UI state
  Set<String> _selectedRequests = {};
  bool _skipConfirmation = false;
  Timer? _timer;
  int _selectedIndex = 0;

  ThemeMode _themeMode = ThemeMode.light;
  VisualDensity _visualDensity = VisualDensity.standard;

  late DataService _dataService;
  final FirebaseService _firebaseService = FirebaseService();

  // Counts for UI
  int _verifiedUsersCount = 0;
  int _nonVerifiedUsersCount = 0;
  int _pendingSubmissionsCount = 0;
  int _approvedSubmissionsCount = 0; // NEW
  int _rejectedSubmissionsCount = 0; // NEW

  // Cache state
  bool _logsOffline = false;
  bool _logsUsingCache = false;
  String _logsError = '';
  DateTime? _logsLastSync;
  final String _logsCacheKeyData = 'cached_admin_logs';
  final String _logsCacheKeySyncedAt = 'cached_admin_logs_syncedAt';
  final String _usersCacheKey = 'cached_admin_users';
  final String _requestsCacheKey = 'cached_admin_requests';

  @override
  void initState() {
    super.initState();
    _connectivity = Connectivity();
    _connectivityStream = _connectivity.onConnectivityChanged;
_connectivityStream.listen((ConnectivityResult result) async {
  final offline = result == ConnectivityResult.none;
  if (offline != _isOffline) {
    setState(() => _isOffline = offline);
    
    if (offline) {
      _showOfflineDialog();
    } else {
      // Internet is back - check if Python died and restart it
      print('🌐 Internet restored. Checking Python status...');
      
      // Small delay to let network stabilize
      await Future.delayed(const Duration(seconds: 2));
      
      if (!PythonBackendService.isRunning) {
        print('🔄 Python was dead, restarting...');
        await PythonBackendService.start();
        if (mounted) {
          _showSnackBar("Python Backend Restarted (Connection Restored)");
        }
      }
      
      _fetchAllData();
    }
  }
});
    _dataService = DataService(); 
    _loadCachedLogs().then((_) {
      _fetchAllData();
      _timer = Timer.periodic(const Duration(seconds: 25), (_) => _fetchAllData());
    });
  }
  // --- NEW FUNCTION: Manual Switch to Offline ---
  // --- UPDATED: Manual Switch to Offline WITH CONFIRMATION ---
  // --- NEW: Manual Switch to Offline WITH CUSTOM DESIGN ---
  // --- UPDATED: LARGE DESKTOP CONFIRMATION DIALOG ---
  Future<void> _switchToOfflineMode() async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(25),
          ),
          elevation: 0,
          backgroundColor: Colors.transparent,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.topCenter,
            children: [
              // --- 1. THE MAIN CONTENT CARD (BIGGER) ---
              Container(
                width: 650, // Increased width for Desktop
                padding: const EdgeInsets.only(
                  top: 100, // More space for the bigger icon
                  left: 50,
                  right: 50,
                  bottom: 50,
                ),
                margin: const EdgeInsets.only(top: 80), // Push down further
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(25),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 15.0,
                      offset: Offset(0.0, 15.0),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // --- TITLE (LARGER) ---
                    const Text(
                      "Enter Offline Mode",
                      style: TextStyle(
                        fontSize: 32, // Much bigger font
                        fontWeight: FontWeight.bold,
                        color: Colors.deepPurple,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 25),
                    
                    // --- BODY TEXT (LARGER) ---
                    const Text(
                      "Are you sure you want to switch to Offline Mode?",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 20, 
                        fontWeight: FontWeight.w600,
                        color: Colors.black87
                      ),
                    ),
                    const SizedBox(height: 15),
                    const Text(
                      "This mode allows you to create requests, manage data, and generate documents without an active internet connection.\n\n"
                      "All changes will be saved locally and can be synced to the database once you are back online.",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 18, // Readable desktop font size
                        color: Color.fromARGB(190, 0, 0, 0),
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 45),
                    
                    // --- BUTTONS (BIGGER) ---
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Cancel Button
                        TextButton(
                          onPressed: () => Navigator.of(ctx).pop(false),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.grey[700],
                            padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 20),
                            textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          child: const Text("Cancel"),
                        ),
                        const SizedBox(width: 20),
                        
                        // Confirm Button
                        ElevatedButton.icon(
                          onPressed: () => Navigator.of(ctx).pop(true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.deepPurple,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 22),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 8,
                            textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          icon: const Icon(Icons.wifi_off_rounded, size: 28),
                          label: const Text("Yes, Go Offline"),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // --- 2. THE FLOATING ICON (BIGGER) ---
              Positioned(
                top: 0,
                child: CircleAvatar(
                  backgroundColor: Colors.deepPurple,
                  radius: 75, // Radius 75 = 150px Diameter
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 6),
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.cloud_off_rounded,
                        size: 80, // Huge icon
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );

    // Navigation Logic
    if (confirm == true && mounted) {
      // Navigate and WAIT for return
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SecretaryOfflinePage(
            firebaseToken: widget.token,
            userId: widget.userId,
          ),
        ),
      );
      
      // 🔄 THIS RUNS WHEN YOU RETURN FROM OFFLINE MODE
      print("🔄 Returned from Offline Mode - Checking Python...");
      if (!PythonBackendService.isRunning) {
        await PythonBackendService.start();
        _showSnackBar("Python Backend Restarted");
      }
      // Refresh data in case offline requests were synced
      _fetchAllData();
    }
  }
  // --- UPDATED TUTORIAL LOGIC ---
  Future<void> _checkAndStartTutorial(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    // await prefs.setBool('has_seen_tutorial', false); // Keep commented unless testing
    bool hasSeen = prefs.getBool('has_seen_tutorial') ?? false;

    if (!hasSeen && mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext dialogContext) {
          return AlertDialog(
            title: const Text("Welcome Secretary!"),
            content: const Text("Would you like a tour of the new features?"),
            actions: [
              TextButton(
                onPressed: () async {
                  await prefs.setBool('has_seen_tutorial', true);
                  Navigator.pop(dialogContext);
                },
                child: const Text("No"),
              ),
              ElevatedButton(
                onPressed: () async {
                  await prefs.setBool('has_seen_tutorial', true);
                  Navigator.pop(dialogContext);
                  
                  // START THE SEQUENCE HERE
                  // START THE SEQUENCE HERE
                  ShowCaseWidget.of(context).startShowCase([
                    _keyProfile,       // 1. Profile
                    _keyProfileBilling,// 2. Billing (ADDED)
                    
                    _keyPostAnnounce,  // 3. Post Announcement
                    _keyManageAnnounce,// 4. Manage Announcements (ADDED)
                    
                    _keyOrgChart,      // 5. Org Chart
                    _keySideMap,       // 6. Map (MOVED HERE) <--- Add this

                    _keySubRequests,   // 6. Submitted Requests
                    _keyNonVerifUsers, // 7. Non-Verified Users
                    _keyVerifUsers,    // 8. Verified Users
                    
                    _keyTabDashboard,  // 9. Dashboard Tab
                    _keyTabUsers,      // 10. Users Tab
                    _keyTabLogs,       // 11. Logs Tab (ADDED - was missing from list)
                    _keyTabRequests,   // 12. Requests Tab
                    _keyTabComplaints, // 13. Complaints Tab
                    
                    _keyNotif,         // 14. Notifications
                    _keySettings,      // 15. Settings
                    _three,            // 16. Main Workspace
                  ]);
                },
                child: const Text("Yes, Start Tour"),
              ),
            ],
          );
        },
      );
    }
  }
  // --- SHOW CUSTOM NOTIFICATION ---
  Future<void> _showCustomNotification(String message, int targetIndex) async {
    // 1. Play Notification Sound
// Inside _showCustomNotification function

    // 1. Play Notification Sound (Safely)
    try {
      // Ensure the path matches what is inside your 'assets' folder
      // If your file is at assets/sounds/notification.mp3, use this:
      await _audioPlayer.play(AssetSource('sounds/notification.mp3'));
    } catch (e) { 
      // This prevents the app from crashing if the file is missing
      print("Error playing sound: $e"); 
    }

    // 2. Add to History List
    setState(() {
      _notificationHistory.insert(0, {
        'message': message,
        'targetIndex': targetIndex,
        'timestamp': DateTime.now(),
      });
    });

    // 3. Remove any existing visual toast immediately
    if (_overlayEntry != null) {
      _overlayEntry!.remove();
      _overlayEntry = null;
    }
    _toastTimer?.cancel();

    // 4. Create the new Overlay Entry
    _overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        top: 60, 
        left: 16, 
        child: Material(
          color: Colors.transparent,
          elevation: 10,
          child: InkWell(
            onTap: () => _onOverlayClick(targetIndex),
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: 350,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.green.shade600,
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 10, offset: const Offset(0, 4))
                ],
              ),
              child: Row(
                children: [
                  const Icon(Icons.notifications_active, color: Colors.white),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text("New Activity", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                        Text(message, style: const TextStyle(color: Colors.white, fontSize: 12), maxLines: 2, overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white, size: 18),
                    onPressed: () {
                      _overlayEntry?.remove();
                      _overlayEntry = null;
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    // 5. Insert it into the screen
    Overlay.of(context).insert(_overlayEntry!);

    // 6. Auto-remove after 8 seconds
    _toastTimer = Timer(const Duration(seconds: 8), () {
      _overlayEntry?.remove();
      _overlayEntry = null;
    });
  }

  bool get hasNewRequests => _requests.any((request) {
    final status = (request['status'] ?? '').toString().toLowerCase();
    final docType = (request['documentType'] ?? request['title'] ?? '').toString().toLowerCase();
    return status == 'pending' && !docType.contains('complaint');
  });

  bool get hasNewComplaints => _allComplaints.any((complaint) {
    final s = complaint.status.toLowerCase();
    return s == 'new' || s == 'pending';
  });

  // --- 1. CHECK FOR DOCUMENTS ---
  void _checkForNewPendingRequests(List<Map<String, dynamic>> incomingRequests) {
    final pendingRequests = incomingRequests.where((r) {
      final status = (r['status'] ?? '').toString().toLowerCase();
      final type = (r['documentType'] ?? r['title'] ?? '').toString().toLowerCase();
      return status == 'pending' && !type.contains('complaint');
    }).toList();

    bool hasNewItem = false;
    String specificType = "Document"; 

    for (var request in pendingRequests) {
      final id = request['requestId'].toString();
      if (!_knownRequestIds.contains(id)) {
        if (!_isFirstRequestLoad) {
          hasNewItem = true;
          specificType = request['documentType'] ?? "Document";
        }
        _knownRequestIds.add(id);
      }
    }

    if (hasNewItem) {
      _showCustomNotification("New $specificType Request Received!", 3);
    }

    if (_isFirstRequestLoad) _isFirstRequestLoad = false;
  }
  
  // --- UPDATED: Click Logic ---
  void _onOverlayClick(int targetIndex) async {
    // 1. Wait 250ms for ripple effect
    await Future.delayed(const Duration(milliseconds: 250));

    // 2. Remove the toast
    _overlayEntry?.remove();
    _overlayEntry = null;

    // 3. Close VerifiedUsersPage if open
    if (mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }

    // 4. Navigate
    if (targetIndex == 99) {
      // Use a custom PageRoute for smooth sliding animation
      Navigator.push(
        context, 
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) => SubmittedRequestsPage(token: widget.token),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            const begin = Offset(1.0, 0.0); // Slide from right
            const end = Offset.zero;
            const curve = Curves.easeInOut;
            var tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
            return SlideTransition(position: animation.drive(tween), child: child);
          },
        )
      );
    } else {
      setState(() {
        _selectedIndex = targetIndex;
      });
    }
  }

  Future<void> _handleProfileImageUpdate() async {
    // ... (Your Cloudinary Logic remains same) ...
     const String cloudName = 'dnufyw3my';
    const String uploadPreset = 'cloudinary';

    final picker = ImagePicker();
    try {
      final XFile? pickedFile = await picker.pickImage(source: ImageSource.gallery);
      if (pickedFile == null) return; 

      if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Uploading profile picture...')));

      final url = Uri.parse('https://api.cloudinary.com/v1_1/$cloudName/image/upload');
      final request = http.MultipartRequest('POST', url)
        ..fields['upload_preset'] = uploadPreset
        ..files.add(await http.MultipartFile.fromPath('file', pickedFile.path));

      final response = await request.send();
      
      if (response.statusCode == 200) {
        final responseData = await response.stream.bytesToString();
        final jsonData = json.decode(responseData);
        final String downloadUrl = jsonData['secure_url'];

        await _dataService.updateData('users/${widget.userId}', {'profileImageUrl': downloadUrl});

        if (mounted) {
          setState(() {
            _adminProfileImageUrl = downloadUrl;
          });
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile picture updated!'), backgroundColor: Colors.green));
        }
      } else {
        final errorData = await response.stream.bytesToString();
        throw Exception('Cloudinary upload failed: ${response.statusCode} - $errorData');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to upload image: $e'), backgroundColor: Colors.red));
      }
    }
  }

  void _updateThemeMode(ThemeMode newMode) {
    setState(() {
      _themeMode = newMode;
    });
  }

  void _updateVisualDensity(VisualDensity newDensity) {
    setState(() {
      _visualDensity = newDensity;
    });
  }

  void _showOfflineDialog() async {
    bool? proceed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text("Offline Mode"),
        content: const Text("You are offline. Do you want to proceed in offline mode?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text("Proceed Offline")),
        ],
      ),
    );
    if (proceed == true) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => SecretaryOfflinePage(firebaseToken: widget.token, userId: widget.userId)));
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _audioPlayer.dispose();
    _dataService.close();
    super.dispose();
  }

  // ... (Your Cache Functions _loadCachedLogs, _saveCachedLogs, etc. remain the same) ...
  Future<void> _loadCachedLogs() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final jsonString = preferences.getString(_logsCacheKeyData);
      final syncedAtString = preferences.getString(_logsCacheKeySyncedAt);
      if (syncedAtString != null) _logsLastSync = DateTime.tryParse(syncedAtString);
      if (jsonString != null) {
        final decodedData = json.decode(jsonString);
        if (decodedData is List) {
          final logList = decodedData.map<Map<String, dynamic>>((element) => Map<String, dynamic>.from(element)).toList();
          logList.sort((a, b) => _parseTimestamp(b['timestamp']).compareTo(_parseTimestamp(a['timestamp'])));
          setState(() => _logs..clear()..addAll(logList));
        }
      }
    } catch (_) {}
  }

  Future<void> _saveCachedLogs(List<Map<String, dynamic>> logs) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(_logsCacheKeyData, json.encode(logs));
      final now = DateTime.now();
      await preferences.setString(_logsCacheKeySyncedAt, now.toIso8601String());
      setState(() => _logsLastSync = now);
    } catch (_) {}
  }

  Future<void> _saveCachedUsers(List<Map<String, dynamic>> users) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(_usersCacheKey, json.encode(users));
    } catch (_) {}
  }

  Future<void> _moveToArchive(String userId, String requestId) async {
    try {
      final requestData = _requests.firstWhere(
        (r) => r['requestId'] == requestId,
        orElse: () => <String, dynamic>{},
      );

      if (requestData.isEmpty) return;

      final archiveItem = {
        ...requestData,
        'archivedAt': DateTime.now().toIso8601String(),
        'archivedBy': widget.email,
      };

      final Map<String, dynamic> multiPathUpdate = {
        'archived_requests/$requestId': archiveItem, 
        'all_requests/$requestId': null,
        'users/$userId/requests/$requestId': null 
      };

      await _dataService.updateMulti(multiPathUpdate);

      setState(() {
        _requests.removeWhere((r) => r['requestId'] == requestId);
        _selectedRequests.remove("$userId|$requestId");
      });
      
    } catch (error) {
      print("Error archiving: $error");
      rethrow;
    }
  }

  Future<void> _deleteSelectedRequests() async {
    if (_selectedRequests.isEmpty) {
      _showSnackBar("No items selected");
      return;
    }

    if (await _showConfirmationDialog("Confirm Archive", "Are you sure you want to archive the selected item(s)?")) {
      
      int successCount = 0;
      List<String> archivedDetails = []; // Store details for the log

      for (final key in _selectedRequests.toList()) {
        final parts = key.split("|");
        if (parts.length == 2) {
          final userId = parts[0];
          final requestId = parts[1];

          // 1. FIND THE REQUEST DETAILS BEFORE DELETING
          final request = _requests.firstWhere(
            (r) => r['requestId'] == requestId, 
            orElse: () => <String, dynamic>{}
          );

          if (request.isNotEmpty) {
            final String docType = request['documentType'] ?? request['title'] ?? 'Document';
            final String name = request['fullName'] ?? 'Unknown User';
            archivedDetails.add("$docType for $name");
          }

          try {
            await _moveToArchive(userId, requestId); 
            successCount++;
          } catch (_) {}
        }
      }

      // 2. CREATE A DETAILED LOG
      if (successCount > 0) {
        String logMessage;
        if (successCount == 1) {
          // Single item: "Archived Barangay Clearance for Juan Cruz"
          logMessage = "Archived ${archivedDetails.first}.";
        } else {
          // Multiple items: "Archived 3 items: Doc A for User A, Doc B for User B..."
          logMessage = "Archived $successCount requests: ${archivedDetails.join(', ')}.";
        }
        
        await _logAdminAction(logMessage); 
      }

      setState(() => _selectedRequests.clear());
      _showSnackBar("$successCount item(s) archived successfully");
    }
  }


  Future<void> _loadCachedUsers() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final jsonString = preferences.getString(_usersCacheKey);
      if (jsonString != null) {
        final decodedData = json.decode(jsonString);
        if (decodedData is List) {
          final userList = decodedData.map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e)).toList();
          int verifiedCount = 0;
          int nonVerifiedCount = 0;
          for (final user in userList) {
            if (user['role'] == 'user') {
              ((user['isVerified'] as bool?) ?? false) ? verifiedCount++ : nonVerifiedCount++;
            }
          }
          setState(() {
            _users..clear()..addAll(userList);
            _verifiedUsersCount = verifiedCount;
            _nonVerifiedUsersCount = nonVerifiedCount;
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _saveCachedRequests(List<Map<String, dynamic>> requests) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(_requestsCacheKey, json.encode(requests));
    } catch (_) {}
  }

  Future<void> _loadCachedRequests() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final jsonString = preferences.getString(_requestsCacheKey);
      if (jsonString != null) {
        final decodedData = json.decode(jsonString);
        if (decodedData is List) {
          final requestList = decodedData.map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e)).toList();
          setState(() => _requests..clear()..addAll(requestList));
          for(var req in requestList) {
             final id = req['requestId']?.toString();
             if(id != null) _knownRequestIds.add(id);
          }
        }
      }
    } catch (_) {}
  }

  DateTime _parseTimestamp(dynamic value) {
    try {
      if (value == null) return DateTime.fromMillisecondsSinceEpoch(0);
      if (value is int) return value < 2000000000 ? DateTime.fromMillisecondsSinceEpoch(value * 1000) : DateTime.fromMillisecondsSinceEpoch(value);
      if (value is double) {
        final intValue = value.toInt();
        return intValue < 2000000000 ? DateTime.fromMillisecondsSinceEpoch(intValue * 1000) : DateTime.fromMillisecondsSinceEpoch(intValue);
      }
      final stringValue = value.toString();
      final numericValue = int.tryParse(stringValue);
      if (numericValue != null) return numericValue < 2000000000 ? DateTime.fromMillisecondsSinceEpoch(numericValue * 1000) : DateTime.fromMillisecondsSinceEpoch(numericValue);
      return DateTime.parse(stringValue);
    } catch (_) {
      return DateTime.fromMillisecondsSinceEpoch(0);
    }
  }

  String _createFullName(Map<String, dynamic> userData) {
    final firstName = (userData['firstName'] ?? '').toString().trim();
    final middleName = (userData['middleName'] ?? '').toString().trim();
    final lastName = (userData['lastName'] ?? '').toString().trim();
    if (firstName.isEmpty && lastName.isEmpty) return (userData['username'] ?? 'N/A').toString();
    
    final nameParts = [firstName];
    if (middleName.isNotEmpty) {
      nameParts.add('${middleName[0].toUpperCase()}.'); 
    }
    nameParts.add(lastName);
    
    return nameParts.where((part) => part.isNotEmpty).join(' ').toTitleCase();
  }

  // --- FETCH FUNCTIONS ---
  void _fetchAllData() async {
    if (!mounted) return; // <--- ADD THIS
    if (!await isOnline()) return;
    _fetchUsers();
    _fetchLogs();
    _fetchRequests();
    _fetchSubmissionsCount(); 
    _fetchComplaints();       
  }

  Future<bool> isOnline() async {
    var result = await Connectivity().checkConnectivity();
    return result != ConnectivityResult.none;
  }

  Future<void> _fetchComplaints() async {
    if (!mounted) return; // <--- ADD THIS

    try {
      final data = await _dataService.getData("complaints");
      if (!mounted) return; // <--- ADD THIS
      if (mounted && data != null) {
        final List<Complaint> complaints = [];
        data.forEach((id, complaintData) => complaints.add(Complaint.fromJson(id, complaintData)));
        complaints.sort((a, b) => b.timestamp.compareTo(a.timestamp));
        setState(() { _allComplaints..clear()..addAll(complaints); });

        bool hasNewComplaint = false;
        for (var c in complaints) {
          if (!_knownComplaintIds.contains(c.id)) {
            final s = c.status.toLowerCase();
            if (s == 'new' || s == 'pending') {
              if (!_isFirstComplaintLoad) hasNewComplaint = true;
            }
            _knownComplaintIds.add(c.id);
          }
        }
        if (hasNewComplaint) {
          _showCustomNotification("New Complaint Received!", 4);
        }
        if (_isFirstComplaintLoad) _isFirstComplaintLoad = false;
      } else if (mounted) {
        setState(() => _allComplaints.clear());
      }
    } catch (error) {}
  }

  bool _hasSubmissionContent(Map<String, dynamic> submissionData) {
    return (submissionData['idImageUrl'] as String?)?.isNotEmpty == true ||
           (submissionData['selfieImageUrl'] as String?)?.isNotEmpty == true ||
           ((submissionData['supportingDocUrls'] is List) && (submissionData['supportingDocUrls'] as List).isNotEmpty) ||
           (submissionData['fields'] is Map && (submissionData['fields'] as Map).isNotEmpty) ||
           (submissionData['submittedAt'] as String?)?.isNotEmpty == true ||
           submissionData.keys.any((key) => !{'status','rejectionReason','approvalNote','approvedAt','approvedBy','revokedAt','revokedBy','userId','idType','idImageUrl','selfieImageUrl','supportingDocUrls','fields','submittedAt'}.contains(key));
  }

  Future<void> _fetchSubmissionsCount() async {
    if (!mounted) return;

    try {
      final submissions = await _dataService.getData("verificationSubmissions");
      if (!mounted) return;

      final users = await _dataService.getData("users");
      if (!mounted) return;

      int pending = 0;
      int approved = 0;
      int rejected = 0;
      bool hasNewSubmission = false;

      if (submissions != null) {
        submissions.forEach((userId, submissionData) {
          if (submissionData is Map) {
            final status = (submissionData['status'] as String?)?.toLowerCase() ?? '';
            final userExists = (users?.containsKey(userId) ?? false);
            
            // Check content validity (same logic as SubmittedRequestsPage)
            final hasContent = _hasSubmissionContent(Map<String, dynamic>.from(submissionData));

            if (userExists && hasContent) {
              if (status == 'pending') {
                pending++;
                // Check for notification
                if (!_knownSubmissionIds.contains(userId)) {
                  if (!_isFirstSubmissionLoad) hasNewSubmission = true;
                  _knownSubmissionIds.add(userId);
                }
              } else if (status == 'approved') {
                approved++;
              } else if (status == 'rejected') {
                rejected++;
              }
            }
          }
        });
      }

      if (hasNewSubmission) {
        _showCustomNotification("New Verification Request Submitted!", 99);
      }
      if (_isFirstSubmissionLoad) _isFirstSubmissionLoad = false;

      setState(() {
        _pendingSubmissionsCount = pending;
        _approvedSubmissionsCount = approved;
        _rejectedSubmissionsCount = rejected;
      });
    } catch (error) {}
  }

  Future<void> _fetchUsers() async {
    if (!mounted) return; // <--- ADD THIS
    try {
      final data = await _dataService.getData("users");
      if (!mounted) return; // <--- ADD THIS

      if (data != null && mounted) {
        final List<Map<String, dynamic>> processedUserList = [];
        int verifiedCount = 0;
        int nonVerifiedCount = 0;
        String foundAdminName = 'Admin';
        String? foundAdminImageUrl; 

        data.forEach((userId, userData) {
          final userMap = userData as Map<String, dynamic>;
          final String fullName = _createFullName(userMap);
          if (userId == widget.userId) {
            foundAdminName = fullName;
            foundAdminImageUrl = userMap['profileImageUrl'] as String?;
          }
          if (userMap['role'] == 'user') {
            (userMap['isVerified'] as bool? ?? false) ? verifiedCount++ : nonVerifiedCount++;
          }
          processedUserList.add({'id': userId, 'fullName': fullName, ...userMap});
        });

        setState(() {
          _users..clear()..addAll(processedUserList);
          _verifiedUsersCount = verifiedCount;
          _nonVerifiedUsersCount = nonVerifiedCount;
          _adminFullName = foundAdminName;
          _adminProfileImageUrl = foundAdminImageUrl; 
          _loadingUsers = false;
        });
        await _saveCachedUsers(processedUserList);
      } else if (mounted) {
        setState(() => _loadingUsers = false);
        await _loadCachedUsers();
      }
    } catch (e) {
      await _loadCachedUsers();
      if (mounted && _users.isNotEmpty) setState(() => _loadingUsers = false);
    }
  }

  Future<void> _fetchLogs() async {
    if (!mounted) return; // <--- ADD THIS

    if (!await isOnline()) {
      await _loadCachedLogs();
      setState(() { _loadingLogs = false; _logsOffline = true; _logsError = _logs.isEmpty ? "You're offline. Please try again." : ''; _logsUsingCache = _logs.isNotEmpty; });
      return;
    }
    setState(() { _logsOffline = false; _logsUsingCache = false; _logsError = ''; });
    try {
      final data = await _dataService.getData("logs");
      if (!mounted) return;
      if (data == null) {
        setState(() { _logs.clear(); _loadingLogs = false; _logsError = ''; });
        await _saveCachedLogs([]);
        return;
      }
      final List<Map<String, dynamic>> loadedLogs = [];
      data.forEach((key, value) {
        final logEntry = Map<String, dynamic>.from(value ?? {});
        logEntry['id'] = key;
        loadedLogs.add(logEntry);
      });
      loadedLogs.sort((a, b) => _parseTimestamp(b['timestamp']).compareTo(_parseTimestamp(a['timestamp'])));
      setState(() { _logs..clear()..addAll(loadedLogs); _loadingLogs = false; _logsError = ''; });
      await _saveCachedLogs(loadedLogs);
    } catch (error) {
      await _loadCachedLogs();
      setState(() { _loadingLogs = false; _logsUsingCache = _logs.isNotEmpty; });
    }
  }

  Future<void> _fetchRequests() async {
    if (!mounted) return; // <--- ADD THIS
    try {
      Map<String, dynamic>? onlineRequestsData;
      try { onlineRequestsData = await _dataService.getData("all_requests"); } catch (e) {}
      if (!mounted) return; // <--- ADD THIS

      Map<String, dynamic>? offlineRequestsData;
      try { offlineRequestsData = await _dataService.getData("offline_synced_requests"); } catch (e) {}
      Map<String, dynamic>? usersData;
      try { usersData = await _dataService.getData("users"); } catch (e) {}

      final Map<String, Map<String, dynamic>> requestsById = {}; 
      if (usersData != null) {
        usersData.forEach((userId, userData) {
          if (userData is Map) {
            final userMap = Map<String, dynamic>.from(userData);
            final userEmail = userMap['email'] ?? 'N/A';
            final userRole = userMap['role'] ?? 'user';
            final fullName = userMap['fullName'] ?? _createFullName(userMap);
            if (userMap['requests'] is Map) {
              final nestedRequests = Map<String, dynamic>.from(userMap['requests']);
              nestedRequests.forEach((requestId, requestData) {
                if (requestData is Map) {
                  requestsById[requestId] = {
                    'requestId': requestId,
                    'userId': userId,
                    'userEmail': userEmail,
                    'userRole': userRole,
                    'fullName': fullName,
                    'source': 'users', 
                    ...Map<String, dynamic>.from(requestData), 
                  };
                }
              });
            }
          }
        });
      }

      if (onlineRequestsData != null) {
        onlineRequestsData.forEach((requestId, requestData) {
          if (requestData is Map) {
            if (requestsById.containsKey(requestId)) {
              requestsById[requestId] = {
                ...requestsById[requestId]!, 
                ...Map<String, dynamic>.from(requestData),               
                'source': 'synced',          
              };
            } else {
              final requestMap = Map<String, dynamic>.from(requestData);
              requestsById[requestId] = {
                'requestId': requestId,
                'userId': requestMap['userId'] ?? 'N/A',
                'userEmail': requestMap['userEmail'] ?? 'N/A',
                'userRole': requestMap['userRole'] ?? 'user',
                'fullName': requestMap['fullName'] ?? 'N/A',
                'documentType': requestMap['documentType'] ?? 'N/A',
                'source': 'all_requests',
                ...requestMap,
              };
            }
          }
        });
      }

      if (offlineRequestsData != null) {
        offlineRequestsData.forEach((requestId, requestData) {
          if (requestData is Map && !requestsById.containsKey(requestId)) {
             requestsById[requestId] = {
              'requestId': requestId,
              'source': 'offline',
              ...Map<String, dynamic>.from(requestData),
            };
          }
        });
      }

      final loadedRequests = requestsById.values.toList();
      _checkForNewPendingRequests(loadedRequests);

      if (mounted) {
        setState(() {
          _requests..clear()..addAll(loadedRequests);
          _loadingRequests = false;
        });
      }
      await _saveCachedRequests(loadedRequests);
    } catch (error) {
      if (mounted) setState(() => _loadingRequests = false);
      await _loadCachedRequests();
    }
  }

  Future<void> _logAdminAction(String message) async {
    try {
      await _firebaseService.recordAdminLog(widget.token, message, widget.email);
      _fetchLogs();
    } catch (e) {
      if (mounted) _showSnackBar("Error: Could not save log entry.");
    }
  }

  Future<void> _updateRequest(String userId, String requestId, Map<String, dynamic> updatedData) async {
    try {
      final existingRequest = _requests.firstWhere((r) => r['requestId'] == requestId, orElse: () => <String, dynamic>{});
      final completeData = { ...existingRequest, ...updatedData };
      completeData.remove('source');
      completeData.remove('requestId'); 
      final Map<String, dynamic> multiPathUpdate = {
        'all_requests/$requestId': completeData,        
        'users/$userId/requests/$requestId': updatedData, 
      };
      await _dataService.updateMulti(multiPathUpdate);
      setState(() {
        final index = _requests.indexWhere((r) => r['requestId'] == requestId);
        if (index != -1) {
          _requests[index] = { 'requestId': requestId, ...completeData };
        }
      });
    } catch (error) {
      _showSnackBar("Error updating request: $error");
      rethrow; 
    }
  }

  Future<bool> _showConfirmationDialog(String title, String content) async {
    bool dontShowAgain = false;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(builder: (context, setStateDialog) {
        return AlertDialog(
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(content),
            const SizedBox(height: 16),
            Row(children: [
              Checkbox(value: dontShowAgain, onChanged: (value) => setStateDialog(() => dontShowAgain = value ?? false)),
              const Expanded(child: Text("Don't show confirmation again", style: TextStyle(fontSize: 14))),
            ]),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text("Cancel")),
            ElevatedButton(onPressed: () => Navigator.of(context).pop(true), child: const Text("Confirm")),
          ],
        );
      }),
    ) ?? false;
    if (confirmed && dontShowAgain) setState(() => _skipConfirmation = true);
    return confirmed;
  }

  Future<void> _rescheduleAppointment(String userId, String requestId) async {
    DateTime? newDate;
    TimeOfDay? newTime;
    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(builder: (context, setStateDialog) {
        return AlertDialog(
          title: const Text("Reschedule Appointment"),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text("Select new date and time:"),
            const SizedBox(height: 8),
            ElevatedButton(
              child: Text(newDate == null ? "Select Date" : "Date: ${newDate!.toLocal().toIso8601String().substring(0, 10)}"),
              onPressed: () async {
                DateTime now = DateTime.now();
                DateTime? picked = await showDatePicker(context: context, initialDate: now, firstDate: now, lastDate: DateTime(now.year + 1));
                setStateDialog(() => newDate = picked);
              },
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              child: Text(newTime == null ? "Select Time" : "Time: ${newTime!.format(context)}"),
              onPressed: () async {
                TimeOfDay? picked = await showTimePicker(context: context, initialTime: TimeOfDay.now());
                if (picked != null) setStateDialog(() => newTime = picked);
              },
            ),
          ]),
          actions: [
            TextButton(child: const Text("Cancel"), onPressed: () => Navigator.of(context).pop()),
            TextButton(
              child: const Text("Submit", style: TextStyle(color: Colors.red)),
              onPressed: () {
                if (newDate != null && newTime != null) {
                  Navigator.of(context).pop();
                } else {
                  _showSnackBar("Please select both date and time");
                }
              },
            ),
          ],
        );
      }),
    );
    if (newDate != null && newTime != null) {
      final rescheduledDateTime = DateTime(newDate!.year, newDate!.month, newDate!.day, newTime!.hour, newTime!.minute);
      await _updateRequest(userId, requestId, {'status': 'Rescheduled', 'appointmentDateTime': rescheduledDateTime.toIso8601String()});
      _showSnackBar("Appointment rescheduled");
    }
  }

  Future<void> _approveAppointment(String userId, String requestId) async {
    if (await _confirmStatusChange("Approved")) {
      await _updateRequest(userId, requestId, {'status': 'Approved', 'appointmentDateTime': DateTime.now().toIso8601String()});
      _showSnackBar("Appointment approved");
    }
  }

  Future<void> _disapproveAppointment(String userId, String requestId) async {
    if (await _confirmStatusChange("Disapproved")) {
      await _updateRequest(userId, requestId, {'status': 'Disapproved', 'appointmentDateTime': DateTime.now().toIso8601String()});
      _showSnackBar("Appointment disapproved");
    }
  }

  Future<bool> _confirmStatusChange(String newStatus) async {
    if (_skipConfirmation) return true;
    return await _showConfirmationDialog("Confirm Status Change", 'Are you sure you want to change the status to "$newStatus"?');
  }

  void _showSnackBar(String message) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<bool> _recordPayment(Map<String, dynamic> request, double amount) async {
    final String logMessage = "Recorded payment of ₱$amount for ${request['userEmail']}'s request (${request['documentType']}).";
    await _logAdminAction(logMessage);
    final transactionData = {'amount': amount, 'timestamp': DateTime.now().toIso8601String(), 'documentType': request['documentType'] ?? 'Unknown', 'userId': request['userId'], 'requestId': request['requestId'], 'userEmail': request['userEmail'] ?? 'N/A', 'processedBy': widget.email};
    try {
      await _dataService.addData('transactions', transactionData);
      return true;
    } catch (e) {
      _showSnackBar("Error: Could not save transaction to the billing ledger.");
      return false;
    }
  }

  Future<void> _logout() async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Confirm Logout"),
        content: const Text("Are you sure you want to log out?"),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text("Cancel")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text("Logout"),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      if (mounted) Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const LoginScreen()));
    }
  }
  

  void _onSettings() {
    showDialog(
      context: context,
      builder: (_) => SettingsDialog(
        dataService: _dataService,
        currentThemeMode: _themeMode,
        currentVisualDensity: _visualDensity,
        onThemeChanged: _updateThemeMode,
        onDensityChanged: _updateVisualDensity,
      ),
    );
  }

  Widget _buildLogsBanner() {
    if (!_logsOffline && !_logsUsingCache && _logsError.isEmpty) return const SizedBox.shrink();
    final lines = <String>[];
    if (_logsOffline) lines.add("You’re offline. Please try again.");
    if (_logsUsingCache) {
      final lastSyncTime = _logsLastSync != null ? DateFormat("MMM dd, yyyy h:mm a").format(_logsLastSync!.toLocal()) : "unknown";
      lines.add("Showing last saved logs • Updated: $lastSyncTime");
    }
    if (_logsError.isNotEmpty) lines.add(_logsError);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.amber.withOpacity(0.15), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.amber.withOpacity(0.4))),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: Colors.amber),
          const SizedBox(width: 8),
          Expanded(child: Text(lines.join('\n'), style: const TextStyle(color: Colors.black87))),
          TextButton(
            onPressed: () async {
              if (await isOnline()) {
                setState(() { _logsOffline = false; _logsUsingCache = false; _logsError = ''; _loadingLogs = true; });
                _fetchLogs();
              } else {
                setState(() { _logsOffline = true; _logsError = "You’re offline. Please try again."; });
              }
            },
            child: const Text("Retry"),
          ),
        ],
      ),
    );
  }

  Widget _buildMainContent() {
    if (errorMessage.isNotEmpty) return Center(child: Text(errorMessage, style: const TextStyle(fontSize: 18)));
    switch (_selectedIndex) {
      case 0: // Dashboard
        
        // --- 1. CALCULATE REQUEST STATS ---
        int pendingCount = _requests.where((r) {
          final status = (r['status'] ?? '').toString();
          final type = (r['documentType'] ?? r['title'] ?? '').toString().toLowerCase();
          return status == 'Pending' && !type.contains('complaint');
        }).length;

        int processingCount = _requests.where((r) => (r['status'] ?? '').toString() == 'Processing').length;
        int forSigningCount = _requests.where((r) => (r['status'] ?? '').toString() == 'For Signing').length;
        int readyCount = _requests.where((r) => (r['status'] ?? '').toString() == 'Successful').length;
        int releasedCount = _requests.where((r) => (r['status'] ?? '').toString() == 'Released').length;

        // Group Rejections for Requests
        int rejectedCount = _requests.where((r) {
          final s = (r['status'] ?? '').toString().toLowerCase();
          return s == 'rejected' || s == 'disapproved' || s == 'cancelled' || s == 'denied';
        }).length;

        // --- 2. CALCULATE COMPLAINT STATS (NEW) ---
        int pendingComplaints = _allComplaints.where((c) {
          final s = c.status.toLowerCase();
          return s == 'new' || s == 'pending';
        }).length;

        int processingComplaints = _allComplaints.where((c) {
          final s = c.status.toLowerCase();
          return s == 'processing' || s == 'in progress';
        }).length;

        int resolvedComplaints = _allComplaints.where((c) {
          return c.status.toLowerCase() == 'resolved';
        }).length;

        int rejectedComplaints = _allComplaints.where((c) {
          return c.status.toLowerCase() == 'rejected';
        }).length;


        // --- 3. PASS TO DASHBOARD ---
        // ... previous calculations for requests and complaints ...

        // --- 3. PASS TO DASHBOARD ---
        return DashboardView(
          // User Stats
          totalUsers: _users.length,
          verifiedUsers: _verifiedUsersCount,
          nonVerifiedUsers: _nonVerifiedUsersCount,
          
          // Request Stats
          totalRequests: _requests.length,
          pendingRequests: pendingCount,
          processingRequests: processingCount,
          forSigningRequests: forSigningCount,
          readyRequests: readyCount,
          releasedRequests: releasedCount,
          rejectedRequests: rejectedCount,
          
          // Complaint Stats
          totalComplaints: _allComplaints.length,
          pendingComplaints: pendingComplaints,
          processingComplaints: processingComplaints,
          resolvedComplaints: resolvedComplaints,
          rejectedComplaintsDesc: rejectedComplaints,

          // Verification Stats (NEW)
          pendingVerifications: _pendingSubmissionsCount,
          approvedVerifications: _approvedSubmissionsCount,
          rejectedVerifications: _rejectedSubmissionsCount,

          // System Stats
          logCount: _logs.length,
          isLoading: _loadingUsers || _loadingLogs || _loadingRequests,
          onPendingReviewsTap: () async {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => SubmittedRequestsPage(token: widget.token),
        ),
      );
      // Refresh data when returning
      if (mounted) _fetchAllData();
      },
        );

      case 1: // Users
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 16.0),
              child: ElevatedButton.icon(
                icon: const Icon(Icons.add_moderator),
                label: const Text("Create New Admin Account"),
                onPressed: () {
                  Navigator.push(context, MaterialPageRoute(builder: (context) => RegisterScreen(adminToken: widget.token))).then((_) { _fetchUsers(); });
                },
                style: ElevatedButton.styleFrom(backgroundColor: const Color.fromARGB(255, 90, 152, 247), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12)),
              ),
            ),
            Expanded(
              child: UsersTable(loading: _loadingUsers, users: _users, requests: _requests, complaints: _allComplaints),
            ),
          ],
        );
      case 2: // Logs
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _buildLogsBanner(),
          Expanded(child: LogsTable(loading: _loadingLogs, logs: _logs)),
        ]);
    case 3: // Requests
      return RequestTableWrapper( 
        loading: _loadingRequests,
        allRequests: _requests,
        selectedRequests: _selectedRequests,
        onSelectedRequestsChanged: (newSelection) => setState(() => _selectedRequests = newSelection),
        onUpdateRequest: _updateRequest,
        onRescheduleAppointment: _rescheduleAppointment,
        onApproveAppointment: _approveAppointment,
        onDisapproveAppointment: _disapproveAppointment,
        onConfirmStatusChange: _confirmStatusChange,
        onDeleteSelectedRequests: _deleteSelectedRequests,
        onGenerateDocument: (context, documentType, request) {
          if (documentType == 'Barangay Clearance') {
            Navigator.push(context, MaterialPageRoute(builder: (_) => GeneratedBarangayClearancePage(initialFullName: request['fullName']?.toString() ?? "N/A")));
          } else if (documentType == 'Barangay Business Clearance') {
            final businessDetails = request['businessDetails'] as Map<String, dynamic>? ?? {};
            String initialBusinessAddress;
            final addressField = businessDetails['businessAddress'];
            if (addressField is String) {
              initialBusinessAddress = addressField;
            } else if (addressField is Map) {
              final street = addressField['street']?.toString() ?? '';
              final barangay = addressField['barangay']?.toString() ?? '';
              final municipality = addressField['municipality']?.toString() ?? '';
              final province = addressField['province']?.toString() ?? '';
              initialBusinessAddress = [street, barangay, municipality, province].where((p) => p.isNotEmpty).join(', ');
              if (initialBusinessAddress.isEmpty) initialBusinessAddress = "_________________________";
            } else initialBusinessAddress = "_________________________";
            Navigator.push(context, MaterialPageRoute(builder: (_) => GeneratedBarangayBusinessClearancePage(initialBusinessName: businessDetails['businessName']?.toString() ?? "N/A", initialBusinessAddress: initialBusinessAddress, initialOperatorName: businessDetails['operator']?.toString() ?? "_________________________", initialOperatorAddress: businessDetails['operatorAddress']?.toString() ?? "_________________________")));
          } else if (documentType == 'Barangay Certification') Navigator.push(context, MaterialPageRoute(builder: (_) => GeneratedBarangayCertificationPage(initialFullName: request['fullName']?.toString() ?? "N/A")));
          else if (documentType == 'Barangay Indigent') Navigator.push(context, MaterialPageRoute(builder: (_) => GeneratedBarangayIndigentPage(initialFullName: request['fullName']?.toString() ?? "N/A")));
          else if (documentType == 'Birth Certificate') Navigator.push(context, MaterialPageRoute(builder: (_) => GeneratedBirthCertificatePage(initialFullName: request['fullName']?.toString() ?? "N/A", initialBirthDate: request['birthDate']?.toString() ?? "", initialPlaceOfBirth: request['placeOfBirth']?.toString() ?? "", initialFatherName: request['fatherName']?.toString() ?? "", initialMotherName: request['motherName']?.toString() ?? "", initialControlNumber: request['controlNumber']?.toString() ?? "")));
        },
        onLogAction: _logAdminAction,
        onRecordPayment: _recordPayment,
      );
    case 4: // Complaints
      return ComplaintsPage(token: widget.token, complaints: _allComplaints, onRefresh: _fetchComplaints);
    case 5: // Templates
      return const TemplateManagerPage(); 


    case 10: // Verified Users Page
      return VerifiedUsersPage(token: widget.token);
    default:
      return const Center(child: Text("Select a menu option."));
  }
}

  Future<void> _handleSideMenuItemSelected(int index) async {
    if (index == 2) {
      await Navigator.push(context, MaterialPageRoute(builder: (context) => NonVerifiedUsersPage(token: widget.token)));
    } else if (index == 3) {
      await Navigator.push(context, MaterialPageRoute(builder: (context) => VerifiedUsersPage(token: widget.token)));
    } else if (index == 4) {
      await Navigator.push(context, MaterialPageRoute(builder: (context) => SubmittedRequestsPage(token: widget.token)));
    } else if (index == 5) {
      await Navigator.push(context, MaterialPageRoute(builder: (context) => ProfileBillingPage(token: widget.token)));
    } else if (index == 6) {
      // NEW: Open Map Page from side menu
      await Navigator.push(context, MaterialPageRoute(builder: (context) => const MapPage()));
    }
    
    if (mounted) _fetchAllData();
  }

  Widget _buildPythonStatusBanner() {
    final isRunning = PythonBackendService.isRunning;
    final pid = PythonBackendService.pid;
    final uptime = PythonBackendService.uptimeMinutes;
    final docCount = PythonBackendService.documentCount;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isRunning ? Colors.green.withOpacity(0.05) : Colors.orange.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: isRunning ? Colors.green.withOpacity(0.2) : Colors.orange.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Tooltip(
            richMessage: TextSpan(
              style: const TextStyle(color: Colors.white, fontSize: 12),
              children: [
                TextSpan(text: isRunning ? 'Python Backend: ACTIVE ✓\n\n' : 'Python Backend: STOPPED ⚠\n\n', style: TextStyle(fontWeight: FontWeight.bold, color: isRunning ? Colors.greenAccent : Colors.orangeAccent)),
                if (isRunning) ...[
                  TextSpan(text: '📊 Process ID: ${pid ?? "N/A"}\n'),
                  TextSpan(text: '⏱️ Uptime: ${uptime > 60 ? "${(uptime / 60).toStringAsFixed(1)} hours" : "$uptime minutes"}\n'),
                  TextSpan(text: '📄 Documents Generated: $docCount\n'),
                  const TextSpan(text: '🔍 Monitoring: all_requests/\n'),
                  const TextSpan(text: '🎯 Trigger: status = "Processing"\n'),
                  const TextSpan(text: '📝 Output: Word + PDF files\n'),
                ] else ...[
                  const TextSpan(text: '⚠️ Auto-generation disabled\n'),
                  const TextSpan(text: '💡 Click "Start Backend" to enable\n'),
                ],
              ],
            ),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(8)),
            child: MouseRegion(
              cursor: SystemMouseCursors.help,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: isRunning ? Colors.green : Colors.orange,
                  shape: BoxShape.circle,
                  boxShadow: isRunning ? [BoxShadow(color: Colors.green.withOpacity(0.4), blurRadius: 8, spreadRadius: 1)] : [],
                ),
                child: Icon(isRunning ? Icons.check_circle : Icons.warning_amber_rounded, color: Colors.white, size: 16),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: 'Python Generator: ', style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
                TextSpan(text: isRunning ? 'Active' : 'Offline', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: isRunning ? Colors.green.shade700 : Colors.orange.shade700)),
                if (isRunning) TextSpan(text: ' • $docCount docs generated', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              ]),
            ),
          ),
          if (!isRunning) ...[
            const SizedBox(width: 12),
            TextButton.icon(
              onPressed: () async {
                setState(() {});
                await PythonBackendService.start();
                await Future.delayed(const Duration(seconds: 1));
                setState(() {});
                if (PythonBackendService.isRunning) _showSnackBar('Python backend started');
              },
              icon: const Icon(Icons.play_arrow, size: 16),
              label: const Text('Start Backend'),
              style: TextButton.styleFrom(foregroundColor: Colors.green, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ShowCaseWidget(
      builder: (innerContext) {
        if (!_hasCheckedTutorial) {
          _hasCheckedTutorial = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _checkAndStartTutorial(innerContext);
          });
        }

        return Theme(
          data: Theme.of(context).copyWith(visualDensity: _visualDensity),
          child: Scaffold(
            // NOTE: Removed standard floatingActionButton to use custom animated one below
            
            body: Stack(
              children: [
                // --- 1. MAIN CONTENT (LAYER BEHIND) ---
                Row(
                  children: [
                    SideMenu(
                      token: widget.token,
                      userId: widget.userId,
                      adminFullName: _adminFullName,
                      adminProfileImageUrl: _adminProfileImageUrl,
                      onProfileImageTap: _handleProfileImageUpdate,
                      onSelectItem: _handleSideMenuItemSelected,
                      selectedIndex: _selectedIndex,
                      onLogout: _logout,
                      pendingSubmissionsCount: _pendingSubmissionsCount,
                      
                      keyProfile: _keyProfile,
                      keyProfileBilling: _keyProfileBilling,
                      keyPostAnnounce: _keyPostAnnounce,
                      keyManageAnnounce: _keyManageAnnounce,

                      keyOrgChart: _keyOrgChart,
                      keySideMap: _keySideMap, // <--- MAP KEY ADDED HERE
                      keySubRequests: _keySubRequests,
                      keyNonVerifUsers: _keyNonVerifUsers,
                      keyVerifUsers: _keyVerifUsers,
                    ),
                    
                    Expanded(
                      child: Column(
                        children: [
                          TopNavigationBar(
                            tutorialKey: _keyNotif,
                            keySettings: _keySettings,
                            // 1. ADD THE KEY HERE
                            tabKeys: [ _keyTabDashboard, _keyTabUsers, _keyTabLogs, _keyTabRequests, _keyTabComplaints, _keyTabTemplates, ],
                            
                            selectedIndex: _selectedIndex,
                            onTabSelected: (index) => setState(() => _selectedIndex = index),
                            notificationHistory: _notificationHistory,
                            onNotificationItemClick: (targetIndex) => _onOverlayClick(targetIndex),
                            onClearNotifications: () => setState(() => _notificationHistory.clear()),
                            onSettings: _onSettings,
                            onLogout: _logout,
                            // 2. ADD THE TAB TEXT HERE
                            tabs: const [Tab(text: 'Dashboard'), Tab(text: 'Users'), Tab(text: 'Logs'), Tab(text: 'Requests'), Tab(text: 'Complaints'), Tab(text: 'Templates'),],
                            hasNewComplaints: hasNewComplaints,
                            hasNewRequests: hasNewRequests,
                          ),

                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _buildPythonStatusBanner(),
                                  if (_selectedIndex == 2) _buildLogsBanner(),
                                  Expanded(
                                    child: Showcase(
                                      key: _three,
                                      title: 'Main Workspace',
                                      description: 'This is where your tables, charts, and document data will appear.',
                                      child: AnimatedSwitcher(
                                        duration: const Duration(milliseconds: 300),
                                        switchInCurve: Curves.easeIn,
                                        switchOutCurve: Curves.easeOut,
                                        transitionBuilder: (Widget child, Animation<double> animation) {
                                          return FadeTransition(opacity: animation, child: child);
                                        },
                                        child: KeyedSubtree(
                                          key: ValueKey<int>(_selectedIndex),
                                          child: _buildMainContent(),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                // --- 2. SLIDING OFFLINE BUTTON (LAYER ON TOP) ---
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 400),
                  curve: Curves.easeInOutBack, // Bouncy animation
                  bottom: 30,
                  // Logic: If open, show fully (right: 20). 
                  // If closed, move off-screen (right: -190) leaving only the arrow.
                  right: _isOfflineMenuOpen ? 20 : -190, 
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                    decoration: BoxDecoration(
                      color: Colors.grey[900], // Dark background container
                      borderRadius: BorderRadius.circular(30),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.3),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        )
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // --- A. TOGGLE ARROW BUTTON ---
                        InkWell(
                          onTap: () {
                            setState(() {
                              _isOfflineMenuOpen = !_isOfflineMenuOpen;
                            });
                          },
                          borderRadius: BorderRadius.circular(20),
                          child: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: Colors.deepPurpleAccent, // Distinct color for the arrow
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              // Change icon based on state
                              _isOfflineMenuOpen 
                                ? Icons.arrow_forward_ios_rounded // Point Right (Hide)
                                : Icons.arrow_back_ios_new_rounded, // Point Left (Show)
                              color: Colors.white,
                              size: 18,
                            ),
                          ),
                        ),
                        
                        const SizedBox(width: 12),

                        // --- B. THE MAIN OFFLINE BUTTON ---
                        InkWell(
                          onTap: _switchToOfflineMode, // Your existing function
                          borderRadius: BorderRadius.circular(20),
                          child: Padding(
                            padding: const EdgeInsets.only(right: 12.0, top: 8, bottom: 8),
                            child: Row(
                              children: const [
                                Icon(Icons.wifi_off, color: Colors.white),
                                SizedBox(width: 8),
                                Text(
                                  "Offline Mode",
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
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
              ],
            ),
          ),
        );
      },
    );
  }
}