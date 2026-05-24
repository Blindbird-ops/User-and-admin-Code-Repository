import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:showcaseview/showcaseview.dart';
import 'firebase_service.dart'; // Assuming this contains your submit logic
import 'utils/string_extensions.dart';

class ComplaintScreen extends StatefulWidget {
  final String token;
  final String uid;
  final String email;
  final String fullName;

  const ComplaintScreen({
    super.key,
    required this.token,
    required this.uid,
    required this.email,
    required this.fullName,
  });

  @override
  _ComplaintScreenState createState() => _ComplaintScreenState();
}

class _ComplaintScreenState extends State<ComplaintScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firebaseService = FirebaseService();
  
  // --- STATE MANAGEMENT VARIABLES ---
  bool _isLoading = true;
  bool _isBlocked = false;
  Map<String, dynamic>? _lastComplaint;
  bool _isSubmitting = false;
  
  // --- TUTORIAL KEYS ---
  final GlobalKey _againstKey = GlobalKey();
  final GlobalKey _subjectKey = GlobalKey();
  final GlobalKey _detailsKey = GlobalKey();
  final GlobalKey _submitKey = GlobalKey();

  // --- FORM CONTROLLERS ---
  TextEditingController? _complainantNameController;
  final _complaintAgainstController = TextEditingController();
  final _subjectController = TextEditingController();
  final _complaintDetailsController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _complainantNameController = TextEditingController(text: widget.fullName.toTitleCase());
    _checkComplaintStatus();
  }

  @override
  void dispose() {
    _complainantNameController?.dispose();
    _complaintAgainstController.dispose();
    _subjectController.dispose();
    _complaintDetailsController.dispose();
    super.dispose();
  }

  // --- LOGIC: CHECK FOR COMPLAINTS ON SCREEN LOAD ---
  Future<void> _checkComplaintStatus() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
    });

    try {
      final url =
          'https://mabskie-47c24-default-rtdb.firebaseio.com/users/${widget.uid}/requests.json?auth=${widget.token}';
      final response = await http.get(Uri.parse(url));

      if (response.statusCode != 200 || !mounted) {
         if (mounted) setState(() => _isLoading = false);
        return;
      }

      final dynamic decodedData = json.decode(response.body);
      if (decodedData == null || decodedData is! Map<String, dynamic>) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      final Map<String, dynamic> requests = decodedData;
      Map<String, dynamic>? mostRecentComplaint;
      int latestTimestamp = 0;

      requests.forEach((key, value) {
        if (value is Map<String, dynamic>) {
          final String docType = (value['documentType'] as String? ?? '').toLowerCase();
          
          if (docType.contains('complaint')) {
            // Firebase's ServerValue.timestamp can be a complex object before being resolved.
            // We handle both int and Map types to be safe.
            final timestampValue = value['timestamp'];
            int timestamp = 0;
            if (timestampValue is int) {
              timestamp = timestampValue;
            }
            
            if (timestamp > latestTimestamp) {
              latestTimestamp = timestamp;
              mostRecentComplaint = value;
            }
          }
        }
      });

      if (mostRecentComplaint != null) {
        final complaintDate = DateTime.fromMillisecondsSinceEpoch(latestTimestamp);
        final now = DateTime.now();

        // Check if the complaint was made on the same calendar day
        if (complaintDate.year == now.year &&
            complaintDate.month == now.month &&
            complaintDate.day == now.day) {
          
          if (mounted) {
            setState(() {
              _isBlocked = true;
              _lastComplaint = mostRecentComplaint;
            });
          }
        }
      }
    } catch (e) {
      debugPrint("Error checking complaint status: $e");
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // --- LOGIC: TUTORIAL ---
  Future<void> _checkAndStartTutorial(BuildContext showcaseContext) async {
    if (_isBlocked || _isLoading) return;

    final prefs = await SharedPreferences.getInstance();
    bool hasSeen = prefs.getBool('complaint_tutorial') ?? false;

    if (hasSeen) return;

    await Future.delayed(const Duration(milliseconds: 500));
    
    if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;

    await prefs.setBool('complaint_tutorial', true);

    ShowCaseWidget.of(showcaseContext).startShowCase([
      _againstKey,
      _subjectKey,
      _detailsKey,
      _submitKey,
    ]);
  }

  // --- LOGIC: SUBMISSION FLOW ---
  Future<void> _submitComplaint() async {
    setState(() { _isSubmitting = true; });

    // Prepare data for the optimistic UI update
    final Map<String, dynamic> submittedComplaintData = {
      'subject': _subjectController.text,
      'timestamp': DateTime.now().millisecondsSinceEpoch, // Use local time for instant feedback
    };

    try {
      await _firebaseService.submitComplaint(
        token: widget.token,
        uid: widget.uid,
        email: widget.email,
        complainantName: _complainantNameController!.text, 
        complaintAgainst: _complaintAgainstController.text,
        subject: _subjectController.text,
        complaintDetails: _complaintDetailsController.text,
      );

      if (!mounted) return;
      
      // Wait for the user to close the success dialog
      await _showSuccessDialog();

      // THE FIX: Optimistically update the UI to block the form
      // We assume the submission was successful and immediately change the state
      // without needing to re-fetch data from the server.
      if (mounted) {
        setState(() {
          _isBlocked = true;
          _lastComplaint = submittedComplaintData;
          _isSubmitting = false;
        });
      }

    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to submit: $e"), backgroundColor: Colors.red),
      );
      // Ensure the submitting state is turned off on failure
      if(mounted) setState(() { _isSubmitting = false; });
    }
  }

  // --- UI: DIALOGS ---
  Future<void> _showConfirmationDialog() async {
    if (_formKey.currentState?.validate() != true) return;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          elevation: 16,
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: LinearGradient(
                colors: [Colors.white, Colors.grey.shade50],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.deepPurple.shade50,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.report_problem, color: Colors.deepPurple, size: 40),
                ),
                const SizedBox(height: 16),
                Text("Confirm Complaint", style: GoogleFonts.lato(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.deepPurple)),
                const SizedBox(height: 8),
                Text("Please review your complaint details before submitting.", textAlign: TextAlign.center, style: GoogleFonts.lato(fontSize: 14, color: Colors.grey.shade700)),
                const SizedBox(height: 20),
                
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildSummaryRow("Complainant", _complainantNameController!.text),
                        _buildSummaryRow("Against", _complaintAgainstController.text),
                        _buildSummaryRow("Subject", _subjectController.text),
                        _buildSummaryRow("Details", _complaintDetailsController.text, isMultiline: true),
                      ],
                    ),
                  ),
                ),
                
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: Text("Cancel", style: GoogleFonts.lato(color: Colors.grey.shade700, fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.of(context).pop(true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.deepPurple,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        child: Text("Submit", style: GoogleFonts.lato(color: Colors.white, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );

    if (confirmed == true) {
      await _submitComplaint();
    }
  }

  Future<void> _showSuccessDialog() async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          elevation: 0,
          backgroundColor: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              shape: BoxShape.rectangle,
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 10))],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(15),
                  decoration: BoxDecoration(color: Colors.green.shade50, shape: BoxShape.circle),
                  child: const Icon(Icons.check_circle, color: Colors.green, size: 50),
                ),
                const SizedBox(height: 20),
                Text("Success!", style: GoogleFonts.lato(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.deepPurple)),
                const SizedBox(height: 10),
                Text("Your complaint has been submitted securely.", textAlign: TextAlign.center, style: GoogleFonts.lato(fontSize: 14, color: Colors.grey)),
                const SizedBox(height: 25),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).pop(); // Correct: Only close the dialog.
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepPurple,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: Text("OK", style: GoogleFonts.lato(color: Colors.white, fontSize: 16)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // --- UI: WIDGET BUILDERS ---

  Widget _buildSummaryRow(String label, String value, {bool isMultiline = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text("$label:", style: GoogleFonts.lato(fontWeight: FontWeight.bold, color: Colors.grey.shade800, fontSize: 13)),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.lato(color: Colors.black87, fontSize: 13),
              maxLines: isMultiline ? 3 : 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBlockedInfoCard() {
    final subject = _lastComplaint?['subject'] ?? 'N/A';
    final timestamp = _lastComplaint?['timestamp'] ?? 0;
    final submittedTime = timestamp > 0
        ? DateFormat('hh:mm a').format(DateTime.fromMillisecondsSinceEpoch(timestamp))
        : 'N/A';
        
    return Center(
      child: Card(
        elevation: 4,
        margin: const EdgeInsets.all(24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.timer_off_outlined, color: Colors.deepPurple, size: 50),
              const SizedBox(height: 16),
              Text(
                'Daily Limit Reached',
                style: GoogleFonts.lato(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.deepPurple),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'You can only submit one complaint per day. Please try again tomorrow.',
                textAlign: TextAlign.center,
                style: GoogleFonts.lato(color: Colors.black54, fontSize: 15),
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.deepPurple.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.deepPurple.withOpacity(0.2))
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Last Complaint Details', style: GoogleFonts.lato(fontWeight: FontWeight.bold, color: Colors.deepPurple)),
                    const Divider(height: 16),
                    Text('Subject: $subject', style: GoogleFonts.lato(fontSize: 14)),
                    const SizedBox(height: 8),
                    Text('Time: $submittedTime', style: GoogleFonts.lato(fontSize: 14)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildComplaintForm(BuildContext showcaseContext) {
    return Form(
      key: _formKey,
      child: ListView(
        children: [
          Text("We Value Your Feedback", style: GoogleFonts.lato(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.deepPurple), textAlign: TextAlign.center),
          const SizedBox(height: 16),
          
          TextFormField(
            controller: _complainantNameController!,
            readOnly: true,
            decoration: InputDecoration(
              labelText: "Complainant Name",
              labelStyle: GoogleFonts.lato(),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
              fillColor: Colors.grey.shade200,
            ),
          ),
          const SizedBox(height: 16),

          Showcase(
            key: _againstKey,
            title: 'Complaint Against',
            description: 'Enter the name of the person or entity involved.',
            enableAutoScroll: true,
            child: TextFormField(
              controller: _complaintAgainstController,
              decoration: InputDecoration(
                labelText: "Name of Person/Entity Being Complained About",
                labelStyle: GoogleFonts.lato(),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              validator: (value) => (value == null || value.isEmpty) ? "Please enter the name" : null,
            ),
          ),
          const SizedBox(height: 16),

          Showcase(
            key: _subjectKey,
            title: 'Subject',
            description: 'Provide a short title or subject for your complaint.',
            enableAutoScroll: true,
            child: TextFormField(
              controller: _subjectController,
              decoration: InputDecoration(
                labelText: "Subject",
                labelStyle: GoogleFonts.lato(),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              validator: (value) => (value == null || value.isEmpty) ? "Please enter the subject" : null,
            ),
          ),
          const SizedBox(height: 16),

          Showcase(
            key: _detailsKey,
            title: 'Details',
            description: 'Describe the incident in detail.',
            enableAutoScroll: true,
            child: TextFormField(
              controller: _complaintDetailsController,
              decoration: InputDecoration(
                labelText: "Complaint Details",
                labelStyle: GoogleFonts.lato(),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              maxLines: 5,
              validator: (value) => (value == null || value.isEmpty) ? "Please describe your complaint" : null,
            ),
          ),
          const SizedBox(height: 24),

          Showcase(
            key: _submitKey,
            title: 'Submit',
            description: 'Tap here to send your complaint securely.',
            enableAutoScroll: true,
            child: ElevatedButton(
              onPressed: _isSubmitting ? null : _showConfirmationDialog,
              style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              child: _isSubmitting
                  ? const CircularProgressIndicator(color: Colors.white)
                  : Text("Submit Complaint", style: GoogleFonts.lato(fontSize: 18)),
            ),
          ),
        ],
      ),
    );
  }

  // --- UI: MAIN BUILD METHOD ---
  @override
  Widget build(BuildContext context) {
    return ShowCaseWidget(
      builder: (showcaseContext) {
        if (!_isLoading && !_isBlocked) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _checkAndStartTutorial(showcaseContext);
          });
        }

        return Scaffold(
          appBar: AppBar(
            title: Text(
              "Barangay Complaint",
              style: GoogleFonts.lato(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            backgroundColor: Colors.deepPurple,
            elevation: 0,
            iconTheme: const IconThemeData(color: Colors.white),
          ),
          body: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [Colors.deepPurple.shade100, Colors.deepPurple.shade50], begin: Alignment.topCenter, end: Alignment.bottomCenter),
            ),
            padding: const EdgeInsets.all(24.0),
            child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _isBlocked
                ? _buildBlockedInfoCard()
                : _buildComplaintForm(showcaseContext),
          ),
        );
      },
    );
  }
}