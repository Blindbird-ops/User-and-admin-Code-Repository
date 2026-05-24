// lib/screens/complaints_page.dart
import 'dart:io'; 
import 'dart:convert';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import 'package:admin_window/models/complaint.dart';
import 'package:admin_window/services/data_service.dart';
import 'package:admin_window/firebase_service.dart';

const Color themePrimaryColor = Color(0xFF5E35B1);
const Color themeAccentColor = Color(0xFFF3E5F5);
const Color cardBackgroundColor = Colors.white;
const Color pageBackgroundColor = Color(0xFFF5F5F7);

class ComplaintsPage extends StatefulWidget {
  final String token;
  final List<Complaint> complaints;
  final Future<void> Function()? onRefresh;

  const ComplaintsPage({
    super.key,
    required this.token,
    required this.complaints,
    this.onRefresh,
  });

  @override
  _ComplaintsPageState createState() => _ComplaintsPageState();
}

class _ComplaintsPageState extends State<ComplaintsPage> {
  // --- STATE VARIABLES ---
  List<Complaint> _allComplaints = [];
  
  // 1. ADD THIS HERE (Class Level Variable)
  final Set<String> _selectedComplaints = {}; 
  
  bool _isLoading = true;
  bool _isOffline = false; 
  String? _errorMessage;
  late final DataService _dataService;
  Timer? _refreshTimer;
  
  final FirebaseService _firebaseService = FirebaseService();
  String? _adminEmail;

  @override
  void initState() {
    super.initState();
    _dataService = DataService(); 

    _fetchAdminEmail();
    _loadCacheAndInit();

    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      _fetchComplaints(silent: true);
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  // --- OFFLINE / CACHING LOGIC ---
  Future<void> _loadCacheAndInit() async {
    await _loadFromSharedPreferences();
    await _fetchComplaints(showLoading: _allComplaints.isEmpty);
  }

  Future<void> _loadFromSharedPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? cachedData = prefs.getString('cached_complaints');
      
      if (cachedData != null) {
        final Map<String, dynamic> decodedMap = json.decode(cachedData);
        _processData(decodedMap); 
      }
    } catch (e) {
      print("Cache load error: $e");
    }
  }

  Future<void> _saveToSharedPreferences(Map<String, dynamic> data) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('cached_complaints', json.encode(data));
    } catch (e) {
      print("Cache save error: $e");
    }
  }

  Future<bool> _checkInternet() async {
    var connectivityResult = await (Connectivity().checkConnectivity());
    return connectivityResult != ConnectivityResult.none;
  }

  Future<void> _fetchAdminEmail() async {
    try {
      final email = await _dataService.getCurrentUserEmail();
      if (mounted) setState(() => _adminEmail = email);
    } catch (_) {}
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

  // --- DATA PROCESSING ---
  void _processData(Map<dynamic, dynamic> data) {
    final List<Complaint> complaints = [];
    data.forEach((id, complaintData) {
      try {
        complaints.add(Complaint.fromJson(id.toString(), complaintData));
      } catch (e) {
        print("Error parsing complaint $id: $e");
      }
    });
    complaints.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    
    if (mounted) {
      setState(() {
        _allComplaints = complaints;
        _isLoading = false;
        _errorMessage = null; 
      });
    }
  }

  Future<void> _fetchComplaints({bool showLoading = false, bool silent = false}) async {
    if (showLoading) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final data = await _dataService.getData("complaints");
      
      if (!mounted) return;

      if (data != null) {
        _processData(data);
        _saveToSharedPreferences(data);
        _backfillMirrors(_allComplaints);

        if (_isOffline) setState(() => _isOffline = false);
      } else {
        setState(() {
          _allComplaints = [];
          _isLoading = false;
          // Note: _selectedComplaints is cleared in UI state, no need to re-declare
        });
      }
    } catch (e) {
      print("Fetch error: $e");
      
      if (mounted) {
        if (e.toString().contains("SocketException") || e.toString().contains("Failed host lookup")) {
           setState(() {
             _isOffline = true;
             _isLoading = false; 
           });
        } else if (!silent) {
           setState(() => _errorMessage = 'Failed to fetch: ${e.toString()}');
        }
      }
    }
  }

  // --- ARCHIVE LOGIC ---
   Future<void> _archiveSelectedComplaints() async {
    // 1. Basic Checks
    if (_selectedComplaints.isEmpty) {
      print("DEBUG: No complaints selected.");
      return;
    }

    if (!await _checkInternet()) {
      _showResultDialog("Offline", "You cannot archive records while offline.", isSuccess: false);
      return;
    }

    // 2. Confirmation
    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Confirm Archive"),
        content: Text("Are you sure you want to archive ${_selectedComplaints.length} complaint(s)?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Archive"),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);

    try {
      final updates = <String, dynamic>{};
      final List<String> archivedDetails = [];

      // 3. Loop through selected items
      for (String id in _selectedComplaints) {
        print("DEBUG: Processing ID: $id");

        // A. Find local details for the log
        final Complaint c = _allComplaints.firstWhere(
          (element) => element.id == id, 
          orElse: () => _allComplaints.first
        );
        archivedDetails.add("${c.subject} by ${c.complainantName ?? 'Unknown'}");

        // B. Fetch the raw data from Firebase
        // We use the ID directly to fetch the specific node
        final rawResult = await _dataService.getData("complaints/$id");

        if (rawResult == null) {
          print("DEBUG: Could not find data in Firebase for ID: $id");
          continue; // Skip this one if data is missing
        }

        // C. Prepare the Move operation
        // 1. Add to 'archived_complaints'
        final Map<String, dynamic> dataToArchive = Map<String, dynamic>.from(rawResult as Map);
        dataToArchive['archivedAt'] = DateTime.now().toIso8601String();
        dataToArchive['archivedBy'] = _adminEmail;
        
        updates['archived_complaints/$id'] = dataToArchive;

        // 2. Delete from 'complaints'
        updates['complaints/$id'] = null;

        // 3. Delete from 'users' (if applicable)
        final uid = await _resolveUid(c);
        if (uid != null) {
          updates['users/$uid/requests/$id'] = null;
        }
      }

      // 4. Check if we actually have updates to send
      if (updates.isEmpty) {
        print("DEBUG: Updates map is empty. Nothing to send to Firebase.");
        _showResultDialog("Error", "Could not find data to archive.", isSuccess: false);
        return;
      }

      print("DEBUG: Sending ${updates.length} updates to Firebase...");
      
      // 5. Send Updates
      await _dataService.updateMulti(updates);
      
      print("DEBUG: Update successful.");

      // 6. Log and Clean up
      String logMessage;
      
      if (archivedDetails.length == 1) {
        // Single Item: Keep it specific
        // Example: "Archived Complaint: Noise Complaint by Juan Cruz"
        logMessage = "Archived Complaint: ${archivedDetails.first}";
      
      } else if (archivedDetails.length <= 3) {
        // Few Items (2 or 3): List just the subjects (remove "by Name" to save space)
        // Example: "Archived 2 complaints: Noise Complaint, Illegal Parking"
        final subjects = archivedDetails.map((d) => d.split(' by ')[0]).join(", ");
        logMessage = "Archived ${archivedDetails.length} complaints: $subjects";
      
      } else {
        // Many Items (>3): Use a summary
        // Example: "Bulk Archive: Moved 12 complaints to archive."
        logMessage = "Bulk Archive: Moved ${archivedDetails.length} complaints to archive.";
      }

      await _logAction(logMessage);

      await _logAction(logMessage);

      setState(() {
        _selectedComplaints.clear();
      });
      await _fetchComplaints(); // Refresh UI

      _showResultDialog("Success", "${archivedDetails.length} item(s) archived successfully.");

    } catch (e) {
      print("DEBUG ERROR: $e"); // CHECK THIS IN YOUR CONSOLE
      _showResultDialog("Error", "Failed to archive: $e", isSuccess: false);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
  // --- STATUS UPDATE LOGIC ---
  Future<void> _updateComplaintStatus(Complaint complaint, String newStatus, {String? remarks}) async {
    if (!await _checkInternet()) {
      _showResultDialog("Offline", "You cannot update status while offline.", isSuccess: false);
      return;
    }

    try {
      final String? uid = await _resolveUid(complaint);
      final String eventId = DateTime.now().millisecondsSinceEpoch.toString(); 

      final updates = <String, dynamic>{
        'complaints/${complaint.id}/status': newStatus,
        'complaints/${complaint.id}/updatedAt': {'.sv': 'timestamp'},
        'complaints/${complaint.id}/statusHistory/$eventId/timestamp': {'.sv': 'timestamp'},
        'complaints/${complaint.id}/statusHistory/$eventId/stage': newStatus,
        if ((remarks ?? '').isNotEmpty)
          'complaints/${complaint.id}/statusHistory/$eventId/remarks': remarks,
      };

      if (uid != null && uid.isNotEmpty) {
        updates.addAll({
          'users/$uid/requests/${complaint.id}/id': complaint.id,
          'users/$uid/requests/${complaint.id}/controlNumber': complaint.id,
          'users/$uid/requests/${complaint.id}/documentType': 'Complaint: ${complaint.subject}',
          'users/$uid/requests/${complaint.id}/title': 'Complaint: ${complaint.subject}',
          'users/$uid/requests/${complaint.id}/status': newStatus,
          'users/$uid/requests/${complaint.id}/timestamp': {'.sv': 'timestamp'},
          'users/$uid/requests/${complaint.id}/fullName': complaint.complainantName ?? '',
          'users/$uid/requests/${complaint.id}/message': complaint.complaintDetails ?? complaint.message,
          'users/$uid/requests/${complaint.id}/complaintAgainst': complaint.complaintAgainst ?? '',
          'users/$uid/requests/${complaint.id}/statusHistory/$eventId/timestamp': {'.sv': 'timestamp'},
          'users/$uid/requests/${complaint.id}/statusHistory/$eventId/stage': newStatus,
          if ((remarks ?? '').isNotEmpty)
            'users/$uid/requests/${complaint.id}/statusHistory/$eventId/remarks': remarks,
        });

        if ((complaint.userId ?? '').isNotEmpty && complaint.userId != uid) {
          updates['users/${complaint.userId}/requests/${complaint.id}'] = null;
        }
      }

      await _dataService.updateMulti(updates);

      String logMsg = "Updated complaint '${complaint.subject}' to '$newStatus'.";
      if (remarks != null && remarks.isNotEmpty) logMsg += " Remarks: $remarks";
      await _logAction(logMsg);

      if (!mounted) return;
      await _showResultDialog("Status Updated", "The complaint has been marked as '$newStatus'.");
      _fetchComplaints();
    } catch (e) {
      if (!mounted) return;
      _showResultDialog("Update Failed", "Error: $e", isSuccess: false);
    }
  }

  // --- HELPER METHODS ---
  Future<void> _backfillMirrors(List<Complaint> complaints) async {
    try {
      if (!await _checkInternet()) return;

      for (final c in complaints) {
        final String? uid = await _resolveUid(c);
        if (uid == null || uid.isEmpty) continue;
        final Object? exists = await _dataService.getValue('users/$uid/requests/${c.id}');
        if (exists != null) continue; 

        final int ts = c.timestamp.millisecondsSinceEpoch;
        final String stage = (c.status.isNotEmpty) ? c.status : 'New';

        final updates = <String, dynamic>{
          'users/$uid/requests/${c.id}/id': c.id,
          'users/$uid/requests/${c.id}/controlNumber': c.id,
          'users/$uid/requests/${c.id}/documentType': 'Complaint: ${c.subject}',
          'users/$uid/requests/${c.id}/title': 'Complaint: ${c.subject}',
          'users/$uid/requests/${c.id}/status': stage,
          'users/$uid/requests/${c.id}/timestamp': ts,
          'users/$uid/requests/${c.id}/fullName': c.complainantName ?? '',
          'users/$uid/requests/${c.id}/message': c.complaintDetails ?? c.message,
          'users/$uid/requests/${c.id}/complaintAgainst': c.complaintAgainst ?? '',
          'users/$uid/requests/${c.id}/statusHistory/$ts/timestamp': ts,
          'users/$uid/requests/${c.id}/statusHistory/$ts/stage': stage,
        };
        await _dataService.updateMulti(updates);
      }
    } catch (_) {}
  }

  Future<String?> _resolveUid(Complaint complaint) async {
    try {
      if ((complaint.userId ?? '').isNotEmpty) return complaint.userId;
      final email = complaint.complainantEmail;
      if (email.isNotEmpty && email != 'Unknown Email') {
        final byEmail = await _findUidByEmail(email);
        if ((byEmail ?? '').isNotEmpty) return byEmail;
      }
    } catch (_) {}
    return null;
  }

  Future<String?> _findUidByEmail(String email) async {
    try {
      final users = await _dataService.getData('users');
      if (users == null) return null;
      final target = email.trim().toLowerCase();
      for (final entry in users.entries) {
        final val = entry.value;
        if (val is Map && val['email'] is String) {
          if ((val['email'] as String).trim().toLowerCase() == target) return entry.key.toString();
        }
      }
    } catch (_) {}
    return null;
  }

  Future<void> _showResultDialog(String title, String message, {bool isSuccess = true}) async {
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(isSuccess ? Icons.check_circle : Icons.error, color: isSuccess ? Colors.green : Colors.red, size: 28),
            const SizedBox(width: 12),
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 400),
          child: Text(message, style: const TextStyle(fontSize: 16)),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            style: ElevatedButton.styleFrom(backgroundColor: isSuccess ? themePrimaryColor : Colors.grey),
            child: const Text("OK", style: TextStyle(color: Colors.white)),
          )
        ],
      ),
    );
  }
  
  void _openFile(String path) {
    try {
      if (Platform.isWindows) {
        Process.run('explorer', [path]);
      } else if (Platform.isMacOS) {
        Process.run('open', [path]);
      }
    } catch (e) {
      _showResultDialog("Error", "Could not open file: $e", isSuccess: false);
    }
  }

  Future<String?> _promptForRemarks(String title) async {
    final controller = TextEditingController();
    return await showDialog<String?>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'Remarks (optional)', hintText: 'Enter a short note...'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(null), child: const Text('Cancel', style: TextStyle(color: Colors.red))),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(""),
            child: const Text('Skip Remark', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(onPressed: () => Navigator.of(ctx).pop(controller.text.trim()), child: const Text('Save')),
        ],
      ),
    );
  }

  void _showComplaintDetailsDialog(Complaint complaint) {
    bool hasPdf = false;
    if (complaint.documentPdfPath != null) {
      hasPdf = File(complaint.documentPdfPath!).existsSync();
    }
    bool isNewOrPending = ['new', 'pending'].contains(complaint.status.toLowerCase());

    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 850, minWidth: 650),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
                decoration: const BoxDecoration(
                  color: themePrimaryColor,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.report_problem, color: Colors.white, size: 32),
                    const SizedBox(width: 16),
                    const Expanded(
                      child: Text('Complaint Details', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 22)),
                    ),
                    _buildStatusWidget(complaint),
                  ],
                ),
              ),
              
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                child: Column(
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildInfoRow('Complainant Name', complaint.complainantName ?? 'N/A'),
                              _buildInfoRow('Complainant Email', complaint.complainantEmail),
                              _buildInfoRow('Against', complaint.complaintAgainst ?? 'N/A'),
                            ],
                          ),
                        ),
                        const SizedBox(width: 32),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildInfoRow('Date', DateFormat.yMMMMd().add_jm().format(complaint.timestamp)),
                              _buildInfoRow('Subject', complaint.subject),
                              if (complaint.generationStatus != null)
                                _buildInfoRow('Doc Status', complaint.generationStatus!.toUpperCase()),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    const Divider(),
                    const Align(alignment: Alignment.centerLeft, child: Text('Complaint Details:', style: TextStyle(color: Colors.grey, fontSize: 13))),
                    const SizedBox(height: 8),
                    Container(
                      constraints: const BoxConstraints(maxHeight: 200),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)),
                      child: SingleChildScrollView(
                        child: SelectableText(complaint.complaintDetails ?? complaint.message, style: const TextStyle(fontSize: 16, height: 1.5)),
                      ),
                    ),
                  ],
                ),
              ),
              
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: Row(
                  children: [
                    TextButton(
                      child: const Text('Close', style: TextStyle(fontSize: 16)),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    const Spacer(),

                    // Re-calculate generating state for buttons
                    Builder(builder: (context) {
                      bool isGenerating = (complaint.status.toLowerCase() == 'processing' || 
                                           complaint.status.toLowerCase() == 'in progress') 
                                           && complaint.generationStatus != 'completed';

                      // IF GENERATING: Show a sleek loading banner instead of buttons
                      if (isGenerating) {
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.grey.shade300)
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const SizedBox(
                                width: 16, height: 16, 
                                child: CircularProgressIndicator(strokeWidth: 2, color: themePrimaryColor)
                              ),
                              const SizedBox(width: 12),
                              Text(
                                "Generating case documents. Please wait...", 
                                style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.w600, fontStyle: FontStyle.italic)
                              ),
                            ],
                          ),
                        );
                      }

                      // IF NOT GENERATING: Show standard buttons
                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (complaint.documentWordPath != null && File(complaint.documentWordPath!).existsSync())
                            ElevatedButton.icon(
                              icon: const Icon(Icons.description, color: Colors.white, size: 18),
                              label: const Text("Open Word"),
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade800, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12)),
                              onPressed: () => _openFile(complaint.documentWordPath!),
                            ),
                          
                          const SizedBox(width: 8),

                          if (hasPdf)
                            ElevatedButton.icon(
                              icon: const Icon(Icons.picture_as_pdf, size: 18),
                              label: const Text("Open PDF"),
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12)),
                              onPressed: () => _openFile(complaint.documentPdfPath!),
                            ),
                          
                          const SizedBox(width: 12),

                          // RESOLVED BUTTON
                          if ((complaint.status).toLowerCase() != 'resolved')
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green, 
                                disabledBackgroundColor: Colors.grey.shade300, 
                                disabledForegroundColor: Colors.grey.shade600, 
                                foregroundColor: Colors.white, 
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12)
                              ),
                              onPressed: isNewOrPending ? null : () async {
                                final remarks = await _promptForRemarks('Mark as Resolved');
                                if (remarks == null) return;
                                if (context.mounted) {
                                  Navigator.of(context).pop();
                                  await _updateComplaintStatus(complaint, 'Resolved', remarks: remarks);
                                }
                              },
                              child: const Text('Resolved', style: TextStyle(fontWeight: FontWeight.bold)),
                            ),
                          
                          const SizedBox(width: 12),
                          
                          // PROCESSING BUTTON
                          if ((complaint.status).toLowerCase() != 'processing' && (complaint.status).toLowerCase() != 'in progress')
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(backgroundColor: themePrimaryColor, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12)),
                              child: const Text('Mark In Progress', style: TextStyle(fontWeight: FontWeight.bold)),
                              onPressed: () async {
                                final confirm = await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: const Text("Start Processing?"),
                                    content: const Text("This will mark the complaint as Processing and automatically generate the necessary documents."),
                                    actions: [
                                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
                                      ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Confirm")),
                                    ],
                                  ),
                                );
                                if (confirm != true) return;
                                final remarks = await _promptForRemarks('Add Remarks (Optional)');
                                if (remarks == null) return; 
                                if (context.mounted) {
                                  Navigator.of(context).pop();
                                  await _updateComplaintStatus(complaint, 'Processing', remarks: remarks.isEmpty ? 'Processing started' : remarks);
                                }
                              },
                            ),

                          const SizedBox(width: 8),

                          // REJECT BUTTON
                          if ((complaint.status).toLowerCase() != 'rejected')
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12)),
                              child: const Text('Reject', style: TextStyle(fontWeight: FontWeight.bold)),
                              onPressed: () async {
                                final remarks = await _promptForRemarks('Reason for Rejection');
                                if (remarks == null) return; 
                                if (context.mounted) {
                                  Navigator.of(context).pop();
                                  await _updateComplaintStatus(complaint, 'Rejected', remarks: remarks);
                                }
                              },
                            ),
                        ],
                      );
                    }),
                  ],
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
          Text(label.toUpperCase(), style: const TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          SelectableText(value, style: const TextStyle(fontSize: 16)),
        ],
      ),
    );
  }

  Widget _buildStatusWidget(Complaint complaint) {
    final String currentStatus = complaint.status.toLowerCase();
    
    // Check if it's processing AND the documents are not yet generated
    final bool isGenerating = (currentStatus == 'processing' || currentStatus == 'in progress') 
        && complaint.generationStatus != 'completed';

    if (isGenerating) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.blue.shade50,
          borderRadius: BorderRadius.circular(20), // Matches standard Chip shape
          border: Border.all(color: Colors.blue.shade400, width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.blue.withOpacity(0.15),
              blurRadius: 4,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            SizedBox(
              width: 14, 
              height: 14, 
              child: CircularProgressIndicator(
                strokeWidth: 2.5, 
                valueColor: AlwaysStoppedAnimation<Color>(Colors.blueAccent)
              )
            ),
            SizedBox(width: 8),
            Text(
              "Generating...",
              style: TextStyle(
                color: Colors.blueAccent, 
                fontWeight: FontWeight.w800, 
                fontSize: 11,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      );
    }

    // Normal Status Chip (When not generating)
    Color chipColor;
    String label = complaint.status.isEmpty ? 'New' : complaint.status;
    
    switch (currentStatus) {
      case 'resolved': chipColor = Colors.green; break;
      case 'in progress': chipColor = Colors.orange; break;
      case 'processing': chipColor = Colors.blue; break;
      case 'rejected': chipColor = Colors.red; break;
      default: chipColor = const Color.fromARGB(255, 228, 5, 5); label = 'New';
    }
    
    return Chip(
      label: Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
      backgroundColor: chipColor,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      visualDensity: VisualDensity.compact,
      side: BorderSide.none,
      elevation: 1,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: pageBackgroundColor,
      appBar: AppBar(
        title: const Text('Complaints Inbox'),
        backgroundColor: cardBackgroundColor,
        foregroundColor: Colors.black87,
        elevation: 1,
        actions: [
          // --- 1. SHOW ARCHIVE BUTTON IF ITEMS SELECTED ---
          if (_selectedComplaints.isNotEmpty)
            TextButton.icon(
              onPressed: _archiveSelectedComplaints,
              icon: const Icon(Icons.delete, color: Colors.red),
              label: Text("Archive (${_selectedComplaints.length})", style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
            ),
            
          // Show Offline Indicator
          if (_isOffline)
             const Padding(
               padding: EdgeInsets.only(right: 16.0),
               child: Center(child: Text("OFFLINE", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold))),
             ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: () => _fetchComplaints(showLoading: true), tooltip: 'Refresh'),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(child: Text(_errorMessage!))
              : _allComplaints.isEmpty
                  ? const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.inbox, size: 60, color: Colors.grey), SizedBox(height: 16), Text('The complaints inbox is empty.', style: TextStyle(fontSize: 18, color: Colors.grey))]))
                  : SingleChildScrollView(
                      scrollDirection: Axis.vertical,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          children: [
                            if (_isOffline)
                               Container(
                                 width: double.infinity,
                                 color: Colors.amber.shade100,
                                 padding: const EdgeInsets.all(8),
                                 margin: const EdgeInsets.only(bottom: 10),
                                 child: const Text("You are currently offline. Showing cached data.", textAlign: TextAlign.center),
                               ),
                            Card(
                              elevation: 1,
                              clipBehavior: Clip.antiAlias,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              child: DataTable(
                                headingRowColor: WidgetStateProperty.all(themeAccentColor),
                                headingTextStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: themePrimaryColor),
                                // --- 2. ADD SELECT ALL LOGIC ---
                                onSelectAll: (bool? isSelected) {
                                  setState(() {
                                    if (isSelected == true) {
                                      _selectedComplaints.addAll(_allComplaints.map((c) => c.id));
                                    } else {
                                      _selectedComplaints.clear();
                                    }
                                  });
                                },
                                columns: const [
                                  // The first column is automatically the checkbox column when we use DataRow(selected: ...)
                                  DataColumn(label: Text('Date')),
                                  DataColumn(label: Text('Complainant')),
                                  DataColumn(label: Text('Against')),
                                  DataColumn(label: Text('Subject')),
                                  DataColumn(label: Text('Status')),
                                  DataColumn(label: Text('Actions')),
                                ],
                                rows: _allComplaints.map((complaint) {
                                  // --- 3. DETERMINE SELECTION STATE ---
                                  final isSelected = _selectedComplaints.contains(complaint.id);
                                  
                                  return DataRow(
                                    selected: isSelected,
                                    onSelectChanged: (bool? selected) {
                                      setState(() {
                                        if (selected == true) {
                                          _selectedComplaints.add(complaint.id);
                                        } else {
                                          _selectedComplaints.remove(complaint.id);
                                        }
                                      });
                                    },
                                    cells: [
                                      DataCell(Text(DateFormat.yMd().format(complaint.timestamp))),
                                      DataCell(Text(complaint.complainantName ?? complaint.complainantEmail)),
                                      DataCell(Text(complaint.complaintAgainst ?? 'N/A')),
                                      DataCell(Text(complaint.subject, overflow: TextOverflow.ellipsis)),
                                      DataCell(_buildStatusWidget(complaint)),
                                      DataCell(
                                        ElevatedButton(
                                          child: const Text('View'),
                                          onPressed: () => _showComplaintDetailsDialog(complaint),
                                        ),
                                      ),
                                    ],
                                  );
                                }).toList(),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
    );
  }
}