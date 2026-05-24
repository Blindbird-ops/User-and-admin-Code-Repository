import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart'; // Required for logic
import 'package:shared_preferences/shared_preferences.dart';
import 'package:showcaseview/showcaseview.dart';

// IMPORTS FROM YOUR OTHER FILES
import 'document_request_form.dart'; 
import 'request_utils.dart'; 

class RequestDocumentPage extends StatefulWidget {
  final String token;
  final String uid;
  final String email;

  const RequestDocumentPage({
    super.key,
    required this.token,
    required this.uid,
    required this.email,
  });

  @override
  State<RequestDocumentPage> createState() => _RequestDocumentPageState();
}

class _RequestDocumentPageState extends State<RequestDocumentPage> {
  final GlobalKey _firstDocKey = GlobalKey();
  
  // Real-time listener subscription
  StreamSubscription<DatabaseEvent>? _requestsSubscription;
  
  Set<String> _activePendingDocuments = {}; 
  bool _isLoadingData = true;
  bool _hasCheckedTutorial = false;

  final List<String> _documentTypes = const [
    'Barangay Clearance',
    'Barangay Certification',
    'Barangay Indigent',
    'Barangay Business Clearance',
    'Certification (Late) Registration',
    'Certificate of Cohabitation', 
    'Certificate of Seaweeds',
  ];

  @override
  void initState() {
    super.initState();
    _startRealtimeListener();
  }

  @override
  void dispose() {
    _requestsSubscription?.cancel();
    super.dispose();
  }

  // ==============================================================================
  // 🚀 LOGIC: REAL-TIME LISTENER & STATUS CHECKING
  // ==============================================================================

  void _startRealtimeListener() {
    final ref = FirebaseDatabase.instance.ref('users/${widget.uid}/requests');
    
    _requestsSubscription = ref.onValue.listen((event) {
      if (!mounted) return;
      _processSnapshot(event.snapshot);
    }, onError: (error) {
      print("Error listening to requests: $error");
      if (mounted) setState(() => _isLoadingData = false);
    });
  }

  void _processSnapshot(DataSnapshot snapshot) {
    if (!snapshot.exists || snapshot.value == null) {
      if (mounted) setState(() { _activePendingDocuments = {}; _isLoadingData = false; });
      return;
    }

    final data = Map<String, dynamic>.from(snapshot.value as Map);
    Map<String, Map<String, dynamic>> latestRequestPerType = {};

    // 1. Find the LATEST request for each document type
    data.forEach((key, value) {
      if (value is Map) {
        final req = Map<String, dynamic>.from(value);
        String docType = req['documentType'] ?? '';
        if (docType.isEmpty) return;

        if (!latestRequestPerType.containsKey(docType)) {
          latestRequestPerType[docType] = req;
        } else {
          DateTime existingTime = _parseTs(latestRequestPerType[docType]!['timestamp']);
          DateTime newTime = _parseTs(req['timestamp']);
          if (newTime.isAfter(existingTime)) {
            latestRequestPerType[docType] = req;
          }
        }
      }
    });

    // 2. Check if the latest request is "Finished" or still "Pending"
    Set<String> blockedDocs = {};
    
    // Statuses that are considered COMPLETE/DONE (Allow a NEW request)
    // NOTE: 'successful' is NOT here because it means "Ready for Pickup" (Active)
    List<String> finishedStatuses = [
      'released',   // Resident picked up document
      'cancelled',  // Resident didn't pick up / Admin cancelled
      'rejected', 
      'disapproved', 
      'denied'
    ];

    latestRequestPerType.forEach((docType, req) {
      String realStatus = _deriveRealStatus(req).toLowerCase().trim();
      
      // If status is NOT in finished list, it is ACTIVE/PENDING/SUCCESSFUL -> Block It
      if (!finishedStatuses.contains(realStatus)) {
        blockedDocs.add(docType);
      }
    });

    if (mounted) {
      setState(() {
        _activePendingDocuments = blockedDocs;
        _isLoadingData = false;
      });
    }
  
  }
  // Helper: Get real status from history (Matches your Status Page logic)
  String _deriveRealStatus(Map<String, dynamic> req) {
    var rawHistory = req['statusHistory'];
    final list = <Map<String, dynamic>>[];
    
    if (rawHistory is List) {
      for (final e in rawHistory) if (e is Map) list.add(Map<String, dynamic>.from(e));
    } else if (rawHistory is Map) {
      rawHistory.forEach((k, v) { if (v is Map) list.add(Map<String, dynamic>.from(v)); });
    }

    list.sort((a, b) => _parseTs(a['timestamp']).compareTo(_parseTs(b['timestamp'])));

    if (list.isNotEmpty) {
      final last = list.last;
      return (last['stage'] ?? last['status'] ?? last['state'] ?? req['status'] ?? 'Pending').toString();
    }
    return (req['status'] ?? 'Pending').toString();
  }

  DateTime _parseTs(dynamic v) {
    try {
      if (v is int) return DateTime.fromMillisecondsSinceEpoch(v < 2000000000 ? v * 1000 : v);
      return DateTime.parse(v.toString());
    } catch (_) { return DateTime.fromMillisecondsSinceEpoch(0); }
  }

  // ==============================================================================
  // UI LOGIC
  // ==============================================================================

  Future<void> _checkAndStartTutorial(BuildContext showcaseContext) async {
    if (_hasCheckedTutorial) return;
    _hasCheckedTutorial = true;
    final prefs = await SharedPreferences.getInstance();
    bool hasSeen = prefs.getBool('request_doc_page_tutorial') ?? false;
    if (hasSeen) return;
    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;
    if (ModalRoute.of(context)?.isCurrent != true) return;
    await prefs.setBool('request_doc_page_tutorial', true);
    ShowCaseWidget.of(showcaseContext).startShowCase([_firstDocKey]);
  }

  void _openRequestForm(String documentType) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: ShowCaseWidget(
            builder: (context) => DocumentRequestForm(
              token: widget.token,
              uid: widget.uid,
              email: widget.email,
              documentType: documentType,
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final purple = Colors.deepPurple;
    return ShowCaseWidget(
      builder: (showcaseContext) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _checkAndStartTutorial(showcaseContext);
        });

        return Scaffold(
          appBar: AppBar(
            title: const Text("Request Document"),
            backgroundColor: purple,
            foregroundColor: Colors.white,
          ),
          body: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [purple.shade400, purple.shade200],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
            child: _isLoadingData 
            ? const Center(child: CircularProgressIndicator(color: Colors.white))
            : Column(
              children: [
                const SizedBox(height: 16),
                const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text(
                    "Select a Document",
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white, shadows: [
                      Shadow(blurRadius: 4, color: Colors.black26, offset: Offset(2, 2)),
                    ]),
                  ),
                ),
                Expanded(
                  child: GridView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2, 
                      crossAxisSpacing: 16, 
                      mainAxisSpacing: 16, 
                      childAspectRatio: 1.0, // <-- KEPT ORIGINAL ASPECT RATIO 
                    ),
                    itemCount: _documentTypes.length,
                    itemBuilder: (context, index) {
                      final docType = _documentTypes[index];
                      final bool isBlocked = _activePendingDocuments.contains(docType);

                      Widget gridItem = GestureDetector(
                        onTap: () {
                          if (isBlocked) {
                            ScaffoldMessenger.of(context).clearSnackBars();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text("Active request for $docType in progress.\nPlease wait for it to be completed."),
                                backgroundColor: Colors.orange.shade800,
                                behavior: SnackBarBehavior.floating,
                              )
                            );
                          } else {
                            _openRequestForm(docType);
                          }
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          // WE REMOVED EXTRA PADDING HERE to ensure text fits exactly like old code
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            // GRAY GRADIENT IF BLOCKED
                            gradient: isBlocked 
                              ? LinearGradient(colors: [Colors.grey.shade300, Colors.grey.shade400])
                              : LinearGradient(
                                  colors: [Colors.white, Colors.grey.shade200],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                            boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(2, 2))],
                          ),
                          child: Stack(
                            children: [
                              // ORIGINAL LAYOUT (Center Column)
                              Center(
                                child: Opacity(
                                  // Fade content slightly if blocked
                                  opacity: isBlocked ? 0.6 : 1.0,
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      getDocumentIcon(docType, size: 48, color: isBlocked ? Colors.grey[700] : purple),
                                      const SizedBox(height: 12),
                                      Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 8.0),
                                        child: Text(
                                          docType,
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            fontSize: 16, 
                                            fontWeight: FontWeight.bold, 
                                            // Text turns dark grey if blocked
                                            color: isBlocked ? Colors.grey[800] : purple.shade900
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),

                              // TICKING CLOCK (Overlay - Top Right)
                              // Does not affect the text layout below it
                              if (isBlocked)
                                Positioned(
                                  top: 10,
                                  right: 10,
                                  child: TickingClock(
                                    size: 24, 
                                    color: Colors.orange.shade800
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );

                      if (index == 0) {
                        return Showcase(
                          key: _firstDocKey,
                          title: 'Select Document',
                          description: 'Tap on a card to start filling out the request form.',
                          targetBorderRadius: BorderRadius.circular(16),
                          child: gridItem,
                        );
                      }
                      return gridItem;
                    },
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

// --- ANIMATED TICKING CLOCK WIDGET ---
class TickingClock extends StatefulWidget {
  final double size;
  final Color color;

  const TickingClock({super.key, required this.size, required this.color});

  @override
  State<TickingClock> createState() => _TickingClockState();
}

class _TickingClockState extends State<TickingClock> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(duration: const Duration(seconds: 2), vsync: this)..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(Icons.access_time, size: widget.size, color: widget.color),
          RotationTransition(
            turns: _controller,
            child: Container(
              width: widget.size,
              height: widget.size,
              alignment: Alignment.topCenter,
              child: Container(
                margin: EdgeInsets.only(top: widget.size * 0.15),
                width: 2, 
                height: widget.size * 0.35, 
                decoration: BoxDecoration(color: widget.color, borderRadius: BorderRadius.circular(2)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}