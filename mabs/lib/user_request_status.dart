import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_database/firebase_database.dart';

class UserRequestStatusPage extends StatefulWidget {
  final String token;
  final String uid;
  final String email;
  final String? highlightRequestId; // <--- NEW PARAMETER

  const UserRequestStatusPage({
    super.key,
    required this.token,
    required this.uid,
    required this.email,
    this.highlightRequestId, // <--- ADD THIS
  });

  @override
  _UserRequestStatusPageState createState() => _UserRequestStatusPageState();
}

class _UserRequestStatusPageState extends State<UserRequestStatusPage> {
  List<Map<String, dynamic>> _userRequests = [];
  bool _loading = true;
   bool _isInitialJumpPending = false;
   bool _hasHandledInitialJump = false;
  String errorMessage = '';

  // Offline/caching flags
  bool _isOffline = false;
  bool _usingCache = false;
  DateTime? _lastSync;

  // Display preference for the dialog timeline
  final bool _newestFirst = true;   

  String get _cacheKeyData => 'cached_requests_${widget.uid}';
  String get _cacheKeySyncedAt => 'cached_requests_syncedAt_${widget.uid}';

  @override
  void initState() {
    super.initState();
    if (widget.highlightRequestId != null) {
      _isInitialJumpPending = true;
    }
    _loadFromCache().then((_) => _fetchRequests(showSpinnerIfEmpty: true));
  }

  void _checkAndOpenHighlightedRequest() {
    // 1. ADD CHECK: && !_hasHandledInitialJump
    if (widget.highlightRequestId != null && !_hasHandledInitialJump && _userRequests.isNotEmpty) {
      try {
        final targetReq = _userRequests.firstWhere(
          (r) => r['id'] == widget.highlightRequestId || 
                 (r['requestId'] != null && r['requestId'] == widget.highlightRequestId)
        );
        
        // 2. MARK AS HANDLED IMMEDIATELY
        _hasHandledInitialJump = true; 

        WidgetsBinding.instance.addPostFrameCallback((_) async {
          // Push the Detail Screen
          await _showRequestDetails(targetReq); 
          
          // When they come BACK, show the list
          if (mounted) {
            setState(() {
              _isInitialJumpPending = false;
            });
          }
        });
        return; 
      } catch (_) {
        // ID not found
      }
    }
    
    // If we couldn't find it, or it was ALREADY handled, ensure the list is visible
    if (mounted && _isInitialJumpPending) {
      setState(() => _isInitialJumpPending = false);
    }
  }
  Future<void> _loadFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_cacheKeyData);
      final syncedAtStr = prefs.getString(_cacheKeySyncedAt);

      if (syncedAtStr != null) {
        _lastSync = DateTime.tryParse(syncedAtStr);
      }

      if (jsonStr != null) {
        final decoded = json.decode(jsonStr);
        if (decoded is List) {
          final list = decoded
              .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e))
              .toList();
          setState(() {
            _userRequests = _keepOnlyLatestPerRequest(list);
            _usingCache = true;
            _loading = false; // show cached immediately
          });
        
        }
      }
    } catch (_) {
      // Ignore cache read errors
    }
  }

  Future<void> _saveToCache(List<Map<String, dynamic>> data) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKeyData, json.encode(data));
      final now = DateTime.now();
      await prefs.setString(_cacheKeySyncedAt, now.toIso8601String());
      setState(() {
        _lastSync = now;
      });
    } catch (_) {
      // Ignore cache write errors
    }
  }

  Future<void> _fetchRequests({bool showSpinnerIfEmpty = false}) async {
    if (showSpinnerIfEmpty && _userRequests.isEmpty) {
      setState(() => _loading = true);
    }
    setState(() {
      errorMessage = '';
      _isOffline = false;
    });

    try {
      // Use the SDK to get the data. It handles auth and offline caching automatically.
      final ref = FirebaseDatabase.instance.ref('users/${widget.uid}/requests');
      final snapshot = await ref.get();

      if (!mounted) return;

      if (!snapshot.exists || snapshot.value == null) {
        setState(() {
          _userRequests = [];
          _loading = false;
          _usingCache = false;
          errorMessage = '';
        });
        await _saveToCache([]); 
        return;
      }

      final data = Map<String, dynamic>.from(snapshot.value as Map);
      final List<Map<String, dynamic>> loadedRequests = [];
      
      data.forEach((id, requestData) {
        if (requestData is Map) {
          final requestMap = Map<String, dynamic>.from(requestData);
          // Add the id to the map for easier reference
          loadedRequests.add({'id': id, ...requestMap});
        }
      });

      final cleaned = _keepOnlyLatestPerRequest(loadedRequests);

      setState(() {
        _userRequests = cleaned;
        _loading = false;
        _usingCache = false; // Data is fresh from the server
        errorMessage = '';
      });
      _checkAndOpenHighlightedRequest();

      await _saveToCache(loadedRequests);

    } catch (e) {
      if (!mounted) return;
      print("❌ Error fetching user requests: $e");
      setState(() {
        errorMessage = "Failed to fetch requests. Please check your connection.";
        _loading = false;
        _isOffline = true; 
        _usingCache = _userRequests.isNotEmpty;
      });
    }
  }

  // --- HELPER: Smart Title Logic ---
  String _getRequestTitle(Map<String, dynamic> req) {
    // 1. Try standard documentType
    if (req['documentType'] != null && req['documentType'].toString().trim().isNotEmpty) {
      return req['documentType'].toString();
    }
    // 2. Try subject (Often used in complaints)
    if (req['subject'] != null && req['subject'].toString().trim().isNotEmpty) {
      return req['subject'].toString();
    }
    // 3. Try generic 'type' or 'purpose'
    if (req['type'] != null && req['type'].toString().trim().isNotEmpty) {
      return req['type'].toString();
    }
    if (req['purpose'] != null && req['purpose'].toString().trim().isNotEmpty) {
      return req['purpose'].toString();
    }
    // 4. Fallback
    return "Untitled Request";
  }
  // --------------------------------

  DateTime _parseTs(dynamic v) {
    try {
      if (v == null) return DateTime.fromMillisecondsSinceEpoch(0);
      if (v is int) {
        return v < 2000000000
            ? DateTime.fromMillisecondsSinceEpoch(v * 1000)
            : DateTime.fromMillisecondsSinceEpoch(v);
      }
      if (v is double) {
        final iv = v.toInt();
        return iv < 2000000000
            ? DateTime.fromMillisecondsSinceEpoch(iv * 1000)
            : DateTime.fromMillisecondsSinceEpoch(iv);
      }
      final s = v.toString();
      final n = int.tryParse(s);
      if (n != null) {
        return n < 2000000000
            ? DateTime.fromMillisecondsSinceEpoch(n * 1000)
            : DateTime.fromMillisecondsSinceEpoch(n);
      }
      return DateTime.parse(s);
    } catch (_) {
      return DateTime.fromMillisecondsSinceEpoch(0);
    }
  }

  DateTime _effectiveTimestamp(Map<String, dynamic> req) {
    var best = _parseTs(req['timestamp']);
    for (final e in _extractHistoryList(req['statusHistory'])) {
      final t = _parseTs(e['timestamp']);
      if (t.isAfter(best)) best = t;
    }
    return best;
  }

  List<Map<String, dynamic>> _keepOnlyLatestPerRequest(List<Map<String, dynamic>> reqs) {
    final map = <String, Map<String, dynamic>>{};
    for (final r in reqs) {
      String key = (r['controlNumber'] ?? r['id'] ?? '').toString();
      if (key.trim().isEmpty) key = r['id']?.toString() ?? '';
      final current = map[key];
      if (current == null || _effectiveTimestamp(r).isAfter(_effectiveTimestamp(current))) {
        map[key] = r;
      }
    }
    final list = map.values.toList();
    list.sort((a, b) => _effectiveTimestamp(b).compareTo(_effectiveTimestamp(a)));
    return list;
  }

  Widget _highlightBox(String text, Color color) {
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
    );
  }

  Color getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'released': // Final Success
      case 'completed':
      case 'issued':
        return Colors.green;
      case 'successful': // Ready for Pickup (Teal)
        return Colors.teal;
      case 'approved':
        return Colors.green;
      case 'rejected':
      case 'disapproved':
      case 'denied':
      case 'cancelled':
      case 'canceled':
        return Colors.red;
      case 'rescheduled':
        return Colors.blue;
      case 'in progress':
      case 'processing':
        return Colors.indigo;
      case 'pending':
      case 'for signing':
      default:
        return Colors.orange;
    }
  }


  IconData getStatusIcon(String value) {
    final s = (value).toString().toLowerCase();
    if (s.contains('release') || s.contains('complete')) {
      return Icons.handshake_rounded; // Released/Picked Up
    }
    if (s.contains('success')) {
      return Icons.check_circle_outline; // Ready for pickup
    }
    if (s.contains('approve')) {
      return Icons.check_circle_rounded;
    }
    if (s.contains('reject') || s.contains('disapprove') || s.contains('denied') || s.contains('cancel')) {
      return Icons.cancel_rounded;
    }
    if (s.contains('resched') || s.contains('re-sched') || s.contains('postpon')) {
      return Icons.update_rounded;
    }
    if (s.contains('review') || s.contains('process') || s.contains('progress') || s.contains('verify')) {
      return Icons.pending_actions_rounded;
    }
    if (s.contains('pending') || s.contains('submit') || s.contains('new') || s.contains('signing')) {
      return Icons.hourglass_top_rounded;
    }
    return Icons.info_rounded;
  }


  String formatDateTime(dynamic value) {
    if (value == null) return "";
    try {
      DateTime dt;
      if (value is int) {
        final v = value;
        dt = v < 2000000000
            ? DateTime.fromMillisecondsSinceEpoch(v * 1000)
            : DateTime.fromMillisecondsSinceEpoch(v);
      } else if (value is double) {
        final v = value.toInt();
        dt = v < 2000000000
            ? DateTime.fromMillisecondsSinceEpoch(v * 1000)
            : DateTime.fromMillisecondsSinceEpoch(v);
      } else {
        final s = value.toString();
        final n = int.tryParse(s);
        if (n != null) {
          dt = n < 2000000000
              ? DateTime.fromMillisecondsSinceEpoch(n * 1000)
              : DateTime.fromMillisecondsSinceEpoch(n);
        } else {
          dt = DateTime.parse(s);
        }
      }
      final local = dt.toLocal();
      final formatter = DateFormat("MMM dd, yyyy 'at' h:mm a");
      return formatter.format(local);
    } catch (_) {
      return value.toString();
    }
  }

  List<Map<String, dynamic>> _extractHistoryList(dynamic rawHistory) {
    final list = <Map<String, dynamic>>[];
    if (rawHistory is List) {
      for (final e in rawHistory) {
        if (e is Map) list.add(Map<String, dynamic>.from(e));
      }
    } else if (rawHistory is Map) {
      rawHistory.forEach((key, value) {
        if (value is Map) list.add(Map<String, dynamic>.from(value));
      });
    }
    return list;
  }

  List<Map<String, dynamic>> _sortHistory(List<Map<String, dynamic>> list) {
    DateTime parseTs(dynamic v) {
      try {
        if (v is int) {
          return v < 2000000000
              ? DateTime.fromMillisecondsSinceEpoch(v * 1000)
              : DateTime.fromMillisecondsSinceEpoch(v);
        } else if (v is double) {
          final iv = v.toInt();
          return iv < 2000000000
              ? DateTime.fromMillisecondsSinceEpoch(iv * 1000)
              : DateTime.fromMillisecondsSinceEpoch(iv);
        }
        final s = v?.toString() ?? '';
        final n = int.tryParse(s);
        if (n != null) {
          return n < 2000000000
              ? DateTime.fromMillisecondsSinceEpoch(n * 1000)
              : DateTime.fromMillisecondsSinceEpoch(n);
        }
        return DateTime.parse(s);
      } catch (_) {
        return DateTime.fromMillisecondsSinceEpoch(0);
      }
    }

    list.sort((a, b) {
      final aTs = parseTs(a['timestamp']);
      final bTs = parseTs(b['timestamp']);
      return aTs.compareTo(bTs);
    });
    return list;
  }

  // --- NEW: Calculate Days between Successful and Cancelled ---
  int? _calculateUnclaimedDays(List<Map<String, dynamic>> history) {
    DateTime? successfulDate;
    DateTime? cancelledDate;

    // Sort history oldest to newest to find timeline
    history.sort((a, b) => _parseTs(a['timestamp']).compareTo(_parseTs(b['timestamp'])));

    for (var entry in history) {
      String stage = (entry['stage'] ?? entry['status'] ?? '').toString().toLowerCase();
      if (stage == 'successful') {
        successfulDate = _parseTs(entry['timestamp']);
      } else if (stage == 'cancelled') {
        cancelledDate = _parseTs(entry['timestamp']);
      }
    }

    if (successfulDate != null && cancelledDate != null) {
      return cancelledDate.difference(successfulDate).inDays;
    }
    return null; 
  }

  Map<String, dynamic> _deriveLatest(Map<String, dynamic> req) {
    final history = _sortHistory(_extractHistoryList(req['statusHistory']));
    if (history.isNotEmpty) {
      final last = history.last;
      final latestStatus = (last['stage'] ?? last['status'] ?? last['state'] ?? req['status'] ?? 'Pending').toString();
      final latestRemarks = (last['remarks'] ?? '').toString();
      final latestReason = (last['rejectionReason'] ?? last['reason'] ?? '').toString();
      final latestTimestamp = last['timestamp'];

      final isReschedStage = latestStatus.toLowerCase().contains('resched');
      final latestReschedRaw =
          last['rescheduledDate'] ?? last['rescheduledTo'] ?? (isReschedStage ? req['appointmentDateTime'] : null);
      final latestResched = (latestReschedRaw ?? '').toString();

      return {
        'status': latestStatus,
        'remarks': latestRemarks,
        'rejectionReason': latestReason,
        'timestamp': latestTimestamp,
        'rescheduledTo': latestResched,
        'history': history,
      };
    }

    return {
      'status': (req['status'] ?? 'Pending').toString(),
      'remarks': (req['remarks'] ?? '').toString(),
      'rejectionReason': (req['rejectionReason'] ?? req['reason'] ?? '').toString(),
      'timestamp': req['timestamp'],
      'rescheduledTo': (req['rescheduledDate'] ?? req['rescheduledTo'] ?? '').toString(),
      'history': history,
    };
  }

  Widget _timelineTile({
    required bool isFirst,
    required bool isLast,
    required Color statusColor,
    required IconData icon,
    required String header,
    String? remarks,
    String? reason,
    String? rescheduledTo,
    bool isNegative = false,
    double gap = 12.0,
  }) {
    const lineColor = Colors.deepPurple;
    final connectorColor = lineColor.withOpacity(0.35);

    const double indicatorW = 28;
    const double dotD = 22;
    const double sideGap = 8;

    final double baseFont = DefaultTextStyle.of(context).style.fontSize ?? 14.0;
    final double dotCenterFromTop = baseFont * 0.25;
    final double topSegmentHeight =
        (dotCenterFromTop - (dotD / 2)).clamp(0, 1000);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: indicatorW,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (topSegmentHeight > 0)
                  SizedBox(
                    height: topSegmentHeight,
                    child: Center(
                      child: Container(
                        width: 2,
                        color: isFirst ? Colors.transparent : connectorColor,
                      ),
                    ),
                  ),
                Container(
                  width: dotD,
                  height: dotD,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(color: statusColor, width: 2),
                  ),
                  child: Center(
                    child: Icon(icon, size: 14, color: statusColor),
                  ),
                ),
                Expanded(
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: Container(
                      width: 2,
                      color: isLast ? Colors.transparent : connectorColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: sideGap),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  header,
                  style: TextStyle(
                    color: isNegative ? Colors.red : Colors.black87,
                    fontWeight: isNegative ? FontWeight.bold : FontWeight.w500,
                  ),
                ),
                if (remarks != null && remarks.isNotEmpty)
                  _highlightBox("📝 Remarks: $remarks", Colors.amber.shade800),
                if (reason != null && reason.isNotEmpty)
                  _highlightBox("❗ Reason: $reason", Colors.red.shade700),
                if (rescheduledTo != null && rescheduledTo.isNotEmpty)
                  _highlightBox("📅 Rescheduled to: ${formatDateTime(rescheduledTo)}", Colors.blue.shade700),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Container(width: 8, height: 2, color: connectorColor),
                    Expanded(child: Container(height: 2, color: connectorColor)),
                  ],
                ),
                if (!isLast) SizedBox(height: gap),
              ],
            ),
          ),
        ],
      ),
    );
  }

Future<void> _showRequestDetails(Map<String, dynamic> request) async {
    final List<Map<String, dynamic>> history = _sortHistory(_extractHistoryList(request['statusHistory']));
    final displayHistory = _newestFirst ? history.reversed.toList() : history;
    final requestedAt = formatDateTime(request['timestamp']);

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(
            title: const Text("Request Details"), // Updated to Generic Title
            backgroundColor: Colors.deepPurple,
            foregroundColor: Colors.white,
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // --- HEADER INFO (Control #, Message) ---
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if ((request['controlNumber'] ?? "").toString().isNotEmpty)
                        Text("Control #: ${request['controlNumber']}", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      if ((request['message'] ?? "").toString().isNotEmpty) ...[
                        const SizedBox(height: 8),
                        const Text("Message:", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                        Text("${request['message']}", style: const TextStyle(fontSize: 15)),
                      ],
                      if (requestedAt.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        const Divider(),
                        Text("Requested on: $requestedAt", style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                      ]
                    ],
                  ),
                ),
                
                const SizedBox(height: 24),

                // --- NEW TITLE PLACEMENT ---
                Text(
                  _getRequestTitle(request), // Moved from AppBar to here
                  style: const TextStyle(
                    fontSize: 24, 
                    fontWeight: FontWeight.bold, 
                    color: Colors.black87
                  ),
                ),
                const SizedBox(height: 4),
                const Text("📌 Request Progress", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.deepPurple)),
                const SizedBox(height: 16),

                // --- TIMELINE ---
                if (displayHistory.isNotEmpty)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: List.generate(displayHistory.length, (i) {
                      final entry = displayHistory[i];
                      final stage = (entry['stage'] ?? entry['status'] ?? entry['state'] ?? 'Unknown').toString();
                      final formatted = formatDateTime(entry['timestamp']);
                      
                      // --- SYSTEM REMARKS LOGIC ---
                      String remarks = (entry['remarks'] ?? '').toString();
                      final rejection = (entry['rejectionReason'] ?? entry['reason'] ?? '').toString();
                      
                      if (remarks.isEmpty) {
                        if (stage.toLowerCase() == 'successful') {
                          remarks = "Document is ready. Please proceed to payment/pickup.";
                        } else if (stage.toLowerCase() == 'released') {
                          remarks = "Document claimed & paid.";
                        } else if (stage.toLowerCase() == 'cancelled') {
                           final days = _calculateUnclaimedDays(history);
                           if (days != null && days > 0) {
                             remarks = "Cancelled: Unclaimed for $days days.";
                           } else {
                             remarks = "Request cancelled (Unclaimed).";
                           }
                        }
                      }
                      // ----------------------------

                      final resched = (entry['rescheduledDate'] ?? '').toString();
                      final isNegative = RegExp(r'(reject|disapprov|deni|cancel)', caseSensitive: false).hasMatch(stage);

                      return _timelineTile(
                        isFirst: i == 0,
                        isLast: i == displayHistory.length - 1,
                        statusColor: getStatusColor(stage),
                        icon: getStatusIcon(stage),
                        header: "$stage (${formatted.isNotEmpty ? formatted : 'n/a'})",
                        remarks: remarks,
                        reason: rejection,
                        rescheduledTo: resched,
                        isNegative: isNegative,
                        gap: 20, 
                      );
                    }),
                  )
                else
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(20.0),
                      child: Text("No timeline available yet.", style: TextStyle(color: Colors.grey)),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }


  Widget _buildInfoBanner() {
    if (!_isOffline && !_usingCache) return const SizedBox.shrink();
    final msgs = <String>[];
    if (_isOffline) msgs.add("You’re offline. Please try again.");
    if (_usingCache) {
      final last = _lastSync != null ? DateFormat("MMM dd, yyyy h:mm a").format(_lastSync!.toLocal()) : "unknown";
      msgs.add("Showing last saved data • Updated: $last");
    }
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.amber.withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.amber.withOpacity(0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: Colors.amber),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              msgs.join('\n'),
              style: const TextStyle(color: Colors.black87),
            ),
          ),
          TextButton(
            onPressed: () => _fetchRequests(showSpinnerIfEmpty: false),
            child: const Text("Retry"),
          ),
        ],
      ),
    );
  }

  Widget _buildBodyList() {
    final children = <Widget>[];

    final banner = _buildInfoBanner();
    if (banner is! SizedBox) children.add(banner);

    if (_loading) {
      children.add(const SizedBox(height: 120));
      children.add(const Center(child: CircularProgressIndicator()));
    } else if (errorMessage.isNotEmpty && _userRequests.isEmpty) {
      children.add(
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              Text(errorMessage, style: const TextStyle(fontSize: 16, color: Colors.white)),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: () => _fetchRequests(showSpinnerIfEmpty: true),
                icon: const Icon(Icons.refresh),
                label: const Text("Try again"),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple),
              ),
            ],
          ),
        ),
      );
    } else if (_userRequests.isEmpty) {
      children.add(const SizedBox(height: 120));
      children.add(const Center(
        child: Text("No requests found.", style: TextStyle(fontSize: 18, color: Colors.white)),
      ));
    } else {
      children.addAll([
        const SizedBox(height: 8),
        ..._userRequests.map((req) {
          final derived = _deriveLatest(req);
          final displayStatus = (derived['status'] ?? 'Pending').toString();
          final latestRemarks = (derived['remarks'] ?? '').toString();
          final latestReason = (derived['rejectionReason'] ?? '').toString();
          final updatedAt = formatDateTime(derived['timestamp']);
          final historyList = _extractHistoryList(req['statusHistory']); // Get history for calculation

          final stColor = getStatusColor(displayStatus);
          final stIcon = getStatusIcon(displayStatus);

          // --- LOGIC FOR INFO MESSAGES ---
          String? infoBoxText;
          Color? infoBoxColor;

          // 1. Successful (Ready for Pickup)
          if (displayStatus.toLowerCase() == 'successful') {
            infoBoxText = "✅ Your document is ready! Please proceed to the Barangay Hall to pay and claim it.";
            infoBoxColor = Colors.teal.shade800;
          } 
          // 2. Released (Claimed)
          else if (displayStatus.toLowerCase() == 'released') {
             infoBoxText = "🎉 Transaction Complete. Document has been claimed.";
             infoBoxColor = Colors.green.shade800;
          } 
          // 3. Cancelled (Did not pick up)
          else if (displayStatus.toLowerCase() == 'cancelled') {
            final days = _calculateUnclaimedDays(historyList);
            if (days != null && days > 0) {
              infoBoxText = "❌ Cancelled: Document was unclaimed for $days days.";
            } else {
               infoBoxText = "❌ Request Cancelled: Document was not picked up.";
            }
            infoBoxColor = Colors.red.shade900;
          } 
          // 4. Remarks/Reasons
          else if (latestReason.isNotEmpty) {
            infoBoxText = "❗ Reason: $latestReason";
            infoBoxColor = Colors.red.shade700;
          } else if (latestRemarks.isNotEmpty) {
            infoBoxText = "📝 Remarks: $latestRemarks";
            infoBoxColor = Colors.amber.shade800;
          }

          // --- APPOINTMENT/RESCHEDULE LOGIC ---
          final latestReschedTo = (derived['rescheduledTo'] ?? '').toString();
          final isRescheduled = displayStatus.toLowerCase().contains('resched');
          final showReschedHighlight = isRescheduled || latestReschedTo.isNotEmpty;
          final reschedTargetRaw = latestReschedTo.isNotEmpty
              ? latestReschedTo
              : (isRescheduled ? (req['appointmentDateTime']?.toString() ?? '') : '');
          final reschedTarget = reschedTargetRaw.isNotEmpty ? formatDateTime(reschedTargetRaw) : '';

          String appointmentInfo = "";
          String docTypeLower = (req['documentType'] ?? "").toString().toLowerCase();
          
          if (!showReschedHighlight && docTypeLower.isNotEmpty && (docTypeLower.contains("appointment") || docTypeLower.contains("meeting"))) {
            if (req['appointmentDateTime'] != null && req['appointmentDateTime'].toString().isNotEmpty) {
              final formattedDateTime = formatDateTime(req['appointmentDateTime']);
              final st = displayStatus.toLowerCase();
              if (st.contains("approve")) {
                appointmentInfo = "Appointment Approved: $formattedDateTime";
              } else if (st.contains("disapprove") || st.contains("reject") || st.contains("deny")) {
                appointmentInfo = "Appointment Disapproved: $formattedDateTime";
              } else {
                appointmentInfo = "Requested Appointment: $formattedDateTime";
              }
            }
          }

          return Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            elevation: 4.0,
            margin: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 8.0),
            child: ListTile(
              onTap: () => _showRequestDetails(req),
              leading: CircleAvatar(
                backgroundColor: stColor.withOpacity(0.15),
                child: Icon(stIcon, color: stColor),
              ),
              title: Text(
                _getRequestTitle(req),
                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Text("Status: ", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black87)),
                      Text(displayStatus, style: TextStyle(color: stColor, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  
                  // Appointment Specific Text
                  if (showReschedHighlight && reschedTarget.isNotEmpty)
                    _highlightBox("📅 Rescheduled to: $reschedTarget", Colors.blue.shade700),
                  if (!showReschedHighlight && appointmentInfo.isNotEmpty)
                    Text(appointmentInfo, style: const TextStyle(color: Colors.black87)),

                  if (updatedAt.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2.0),
                      child: Text("Updated: $updatedAt", style: const TextStyle(fontSize: 12, color: Colors.black54)),
                    ),

                  // THE INFO BOX (Successful, Released, Cancelled, Reason, Remarks)
                  if (infoBoxText != null) ...[
                    const SizedBox(height: 8),
                    _highlightBox(infoBoxText, infoBoxColor!),
                  ],
                ],
              ),
              trailing: const Icon(Icons.arrow_forward_ios, color: Colors.black54, size: 18),
            ),
          );
        }),     
        
        const SizedBox(height: 24),
      ]);
    }

    return RefreshIndicator(
      onRefresh: () => _fetchRequests(showSpinnerIfEmpty: false),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(0),
        children: children,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isInitialJumpPending) {
      return Scaffold(
        body: Container(
          width: double.infinity,
          height: double.infinity,
          // 1. Use your App's Gradient Background
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.deepPurple.shade700, Colors.deepPurple.shade400],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 2. Bouncing Icon Animation
              TweenAnimationBuilder(
                tween: Tween<double>(begin: 0.0, end: 1.0),
                duration: const Duration(milliseconds: 800),
                curve: Curves.elasticOut,
                builder: (context, double value, child) {
                  return Transform.scale(
                    scale: value,
                    child: child,
                  );
                },
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.find_in_page_rounded, // Search Icon
                    size: 60,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 40),
              
              // 3. Sleek Loading Bar
              SizedBox(
                width: 150,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: const LinearProgressIndicator(
                    minHeight: 6,
                    backgroundColor: Colors.black12,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                "Opening details...",
                style: TextStyle(
                  color: Colors.white70, 
                  fontSize: 14, 
                  fontWeight: FontWeight.w500,
                  letterSpacing: 1.0,
                ),
              ),
            ],
          ),
        ),
      );
    }
    final purple = Colors.deepPurple;
    return Scaffold(
      appBar: AppBar(
        // 1. Set Title Color to White
        title: const Text("My Request Status", style: TextStyle(color: Colors.white)),
        backgroundColor: purple,
        elevation: 4.0,
        // 2. Set Back Arrow Color to White
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            // 3. Set Refresh Icon to White
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: () => _fetchRequests(showSpinnerIfEmpty: true),
            tooltip: "Refresh",
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [purple.shade400, purple.shade200],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: _buildBodyList(),
      ),
      floatingActionButton: (_isOffline || errorMessage.isNotEmpty)
          ? FloatingActionButton.extended(
              onPressed: () => _fetchRequests(showSpinnerIfEmpty: true),
              backgroundColor: purple,
              icon: const Icon(Icons.wifi_tethering_off),
              label: const Text("Try again"),
            )
          : null,
    );
  }

}

