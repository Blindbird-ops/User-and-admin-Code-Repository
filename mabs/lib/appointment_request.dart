import 'dart:convert';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:showcaseview/showcaseview.dart';
import 'package:intl/intl.dart'; // For date formatting

// Your main app entry point can remain as it was
void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  final String token = 'your_token_here'; // Example data
  final String uid = 'your_uid_here'; // Example data
  final String email = 'your_email_here'; // Example data

  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Appointment Request',
      theme: ThemeData(
        primarySwatch: Colors.deepPurple,
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12.0),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12.0),
            borderSide: const BorderSide(color: Colors.deepPurple, width: 2),
          ),
        ),
      ),
      home: AppointmentRequestPage(
        token: token,
        uid: uid,
        email: email,
      ),
    );
  }
}


class AppointmentRequestPage extends StatefulWidget {
  final String token;
  final String uid;
  final String email;

  const AppointmentRequestPage({
    super.key,
    required this.token,
    required this.uid,
    required this.email,
  });

  @override
  _AppointmentRequestPageState createState() => _AppointmentRequestPageState();
}

class _AppointmentRequestPageState extends State<AppointmentRequestPage> {
  final _formKey = GlobalKey<FormState>();

  // --- TUTORIAL KEYS ---
  final GlobalKey _appointmentTypeKey = GlobalKey();
  final GlobalKey _dateKey = GlobalKey();
  final GlobalKey _timeKey = GlobalKey();
  final GlobalKey _purposeKey = GlobalKey();
  final GlobalKey _submitKey = GlobalKey();

  // --- STATE MANAGEMENT FOR REQUEST LIMITING ---
  bool _isLoadingState = true; // Covers both profile and request checks
  bool _hasActiveRequest = false;
  Map<String, dynamic>? _activeRequestDetails;
  Map<String, dynamic>? _disapprovedRequestInfo;
  bool _showDisapprovedWarning = true;

  // User profile data
  String? _userTitle;
  String? _userFirstName;
  String? _userMiddleName;
  String? _userLastName;

  // Appointment form data
  String _appointmentType = 'Cedula Appointment';
  final List<String> _appointmentTypes = [
    'Cedula Appointment',
    'I.D Appointment',
    'Meeting with Barangay Captain',
    'Meeting with Secretary',
  ];

  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;
  final TextEditingController _messageController = TextEditingController();
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  // --- Main function to load all necessary data and check state ---
  Future<void> _loadInitialData() async {
    if (!mounted) return;
    setState(() {
      _isLoadingState = true;
    });

    try {
      await _fetchUserProfile();
      await _checkExistingAppointments();
    } catch (e) {
      debugPrint("Error loading initial data: $e");
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingState = false;
        });
      }
    }
  }

  // --- Function to check for active or disapproved appointments ---
  // --- MODIFIED FUNCTION WITH CRASH FIX ---
  // --- MODIFIED FUNCTION: NO MORE INNER TRY-CATCH ---
  // Any error here will now be caught by _loadInitialData
  Future<void> _checkExistingAppointments() async {
    final url =
        'https://mabskie-47c24-default-rtdb.firebaseio.com/users/${widget.uid}/requests.json?auth=${widget.token}';

    final response = await http.get(Uri.parse(url));
    if (response.statusCode != 200 || !mounted) {
      return;
    }

    final dynamic decodedData = json.decode(response.body);

    // If the entire path is null, Firebase returns `null`, not a map.
    if (decodedData == null) {
      return;
    }

    // Explicitly check the type before casting to be extra safe.
    if (decodedData is! Map<String, dynamic>) {
        // This can happen if the data is malformed (e.g., it's a List)
        debugPrint("Warning: Expected a Map for user requests, but got ${decodedData.runtimeType}");
        return;
    }

    final Map<String, dynamic> data = decodedData;

    if (data.isEmpty) {
      return;
    }

    Map<String, dynamic>? foundActiveRequest;
    Map<String, dynamic>? foundDisapprovedRequest;

    for (var entry in data.entries) {
      final requestObject = entry.value;

      if (requestObject == null || requestObject is! Map<String, dynamic>) {
        continue;
      }

      final requestData = requestObject;

      final String docType = (requestData['documentType'] as String? ?? '').toLowerCase();
      final bool isAnAppointment = docType.contains('appointment') || docType.contains('meeting');

      if (!isAnAppointment) {
        continue;
      }
      
      final status = (requestData['status'] as String?)?.toLowerCase() ?? '';

      if (status == 'pending' ||
          status == 'approved' ||
          status == 'rescheduled') {
        foundActiveRequest = requestData;
        break;
      }
      
      if (status == 'disapproved') {
        foundDisapprovedRequest = requestData;
      }
    }

    // This setState is safe because it's only called after successful processing.
    if (mounted) {
       setState(() {
        if (foundActiveRequest != null) {
          _hasActiveRequest = true;
          _activeRequestDetails = foundActiveRequest;
        } else if (foundDisapprovedRequest != null) {
          _disapprovedRequestInfo = foundDisapprovedRequest;
        }
      });
    }
  }

  // --- TUTORIAL LOGIC ---
  Future<void> _checkAndStartTutorial(BuildContext showcaseContext) async {
    if (_hasActiveRequest) return;

    final prefs = await SharedPreferences.getInstance();
    bool hasSeen = prefs.getBool('appointment_tutorial') ?? false;

    if (hasSeen) return;

    await Future.delayed(const Duration(milliseconds: 500));
    
    if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;

    await prefs.setBool('appointment_tutorial', true);

    ShowCaseWidget.of(showcaseContext).startShowCase([
      _appointmentTypeKey, _dateKey, _timeKey, _purposeKey, _submitKey,
    ]);
  }

  // --- HELPER METHODS ---
  String _toTitleCase(String? text) {
    if (text == null || text.isEmpty) return '';
    return text.split(' ').map((word) => word.isEmpty ? '' : word[0].toUpperCase() + word.substring(1).toLowerCase()).join(' ');
  }

  Future<void> _fetchUserProfile() async {
    final url =
        'https://mabskie-47c24-default-rtdb.firebaseio.com/users/${widget.uid}.json?auth=${widget.token}';
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200 && mounted) {
        final data = json.decode(response.body) as Map<String, dynamic>?;
        setState(() {
          _userTitle = data?['title'] as String? ?? '';
          _userFirstName = data?['firstName'] as String? ?? '';
          _userMiddleName = data?['middleName'] as String? ?? '';
          _userLastName = data?['lastName'] as String? ?? '';
        });
      }
    } catch (e) {
      debugPrint("Error fetching user profile: $e");
    }
  }

  String _getFullName() {
    List<String> nameParts = [];
    if (_userTitle != null && _userTitle!.isNotEmpty) nameParts.add(_toTitleCase(_userTitle!));
    if (_userFirstName != null && _userFirstName!.isNotEmpty) nameParts.add(_toTitleCase(_userFirstName!));
    if (_userMiddleName != null && _userMiddleName!.isNotEmpty) nameParts.add(_toTitleCase(_userMiddleName!));
    if (_userLastName != null && _userLastName!.isNotEmpty) nameParts.add(_toTitleCase(_userLastName!));
    return nameParts.join(' ');
  }

  IconData getIconForAppointment(String appointmentType) {
    switch (appointmentType) {
      case 'Cedula Appointment': return Icons.assignment;
      case 'I.D Appointment': return Icons.credit_card;
      case 'Meeting with Barangay Captain': return Icons.supervisor_account;
      case 'Meeting with Secretary': return Icons.person;
      default: return Icons.event;
    }
  }

  // --- UI INTERACTION METHODS ---
  Future<void> _pickDate() async {
    DateTime now = DateTime.now();
    final DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now,
      lastDate: DateTime(now.year + 1),
    );
    if (pickedDate != null) {
      setState(() {
        _selectedDate = pickedDate;
      });
    }
  }

  Future<void> _pickTime() async {
    final TimeOfDay? pickedTime = await showTimePicker(
      context: context, 
      initialTime: TimeOfDay.now(),
    );
    if (pickedTime != null) {
      setState(() {
        _selectedTime = pickedTime;
      });
    }
  }

  Future<void> _showSuccessDialog() async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          elevation: 0,
          backgroundColor: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              shape: BoxShape.rectangle,
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: const [
                BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 10)),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(15),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check_circle, color: Colors.green, size: 50),
                ),
                const SizedBox(height: 20),
                const Text(
                  "Success!",
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.deepPurple),
                ),
                const SizedBox(height: 10),
                const Text(
                  "Your appointment request has been submitted successfully.",
                  style: TextStyle(fontSize: 14, color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 25),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepPurple,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text("OK", style: TextStyle(color: Colors.white, fontSize: 16)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showConfirmationDialog() async {
    final isFormValid = _formKey.currentState!.validate();
    
    if (!isFormValid || _selectedDate == null || _selectedTime == null) {
      setState(() {}); // Re-run validation to show error messages
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          elevation: 16,
          child: Container(
            width: MediaQuery.of(context).size.width * 0.9,
            constraints: BoxConstraints(
              maxWidth: 400,
              maxHeight: MediaQuery.of(context).size.height * 0.85, 
            ),
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
                  width: double.infinity,
                  padding: const EdgeInsets.all(16), 
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.deepPurple.shade400, Colors.deepPurple.shade600],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    ),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(20),
                      topRight: Radius.circular(20),
                    ),
                  ),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8), 
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.event_note, color: Colors.white, size: 28),
                      ),
                      const SizedBox(height: 8), 
                      const Text("Confirm Appointment", style: TextStyle(fontSize: 20, color: Colors.white, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 2), 
                      Text("Please review your appointment details", style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.9))),
                    ],
                  ),
                ),
                
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16), 
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildCompactDetailRow(
                          icon: getIconForAppointment(_appointmentType),
                          label: "Appointment Type",
                          value: _appointmentType,
                          color: Colors.deepPurple,
                        ),
                        const SizedBox(height: 12), 
                        _buildCompactDetailRow(
                          icon: Icons.person,
                          label: "Requested by",
                          value: _getFullName(),
                          color: Colors.blue,
                        ),
                        const SizedBox(height: 12), 
                        Row(
                          children: [
                            Expanded(
                              child: _buildCompactDetailRow(
                                icon: Icons.calendar_today,
                                label: "Date",
                                value: _selectedDate!.toLocal().toString().split(' ')[0],
                                color: Colors.green,
                                isCompact: true,
                              ),
                            ),
                            const SizedBox(width: 8), 
                            Expanded(
                              child: _buildCompactDetailRow(
                                icon: Icons.access_time,
                                label: "Time",
                                value: _selectedTime!.format(context),
                                color: Colors.orange,
                                isCompact: true,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12), 
                        _buildCompactDetailRow(
                          icon: Icons.description,
                          label: "Purpose",
                          value: _messageController.text.trim(),
                          color: Colors.purple,
                          isMultiline: true,
                        ),
                        const SizedBox(height: 16), 
                        Container(
                          padding: const EdgeInsets.all(10), 
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.blue.shade200),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.info_outline, color: Colors.blue.shade600, size: 18),
                              const SizedBox(width: 6), 
                              const Expanded(
                                child: Text(
                                  "Your appointment request will be reviewed by the barangay staff. You will receive a confirmation once approved.",
                                  style: TextStyle(color: Colors.blue, fontSize: 11),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                
                Container(
                  padding: const EdgeInsets.all(16), 
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(20),
                      bottomRight: Radius.circular(20),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 10), 
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                              side: BorderSide(color: Colors.grey.shade400),
                            ),
                          ),
                          child: Text("Cancel", style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.w600, fontSize: 15)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => Navigator.of(context).pop(true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.deepPurple,
                            padding: const EdgeInsets.symmetric(vertical: 10), 
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            elevation: 2,
                          ),
                          child: const Text("Confirm", style: TextStyle(fontSize: 15, color: Colors.white, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (confirmed == true) {
      await _submitAppointmentRequest();
    }
  }

  Widget _buildCompactDetailRow({
    required IconData icon,
    required String label,
    required String value,
    required MaterialColor color,
    bool isCompact = false,
    bool isMultiline = false,
  }) {
    return Container(
      padding: EdgeInsets.all(isCompact ? 6 : 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6), 
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: isCompact ? 14 : 16),
          const SizedBox(width: 6), 
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(fontSize: isCompact ? 10 : 11, fontWeight: FontWeight.w600, color: color.shade700),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(fontSize: isCompact ? 12 : 13, color: Colors.grey.shade800, fontWeight: FontWeight.w500),
                  maxLines: isMultiline ? null : 2,
                  overflow: isMultiline ? null : TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- DATA SUBMISSION ---
  Future<void> _submitAppointmentRequest() async {
    setState(() {
      _submitting = true;
    });

    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        throw Exception("User not signed in. Please log in again.");
      }
      
      final appointmentDateTime = DateTime(
        _selectedDate!.year,
        _selectedDate!.month,
        _selectedDate!.day,
        _selectedTime!.hour,
        _selectedTime!.minute,
      );

      final Map<String, dynamic> baseAppointmentData = {
        'documentType': _appointmentType, 
        'status': 'Pending',
        'timestamp': ServerValue.timestamp,
        'appointmentDateTime': appointmentDateTime.toIso8601String(),
        'message': _messageController.text.trim(),
        'statusHistory': { // Initialize history
          '0': {
            'stage': 'Pending',
            'timestamp': ServerValue.timestamp,
          }
        },
      };

      final dbRef = FirebaseDatabase.instance.ref();
      final requestId = dbRef.child('all_requests').push().key!;

      final Map<String, dynamic> allRequestsPayload = {
        ...baseAppointmentData,
        'userId': widget.uid,
        'userEmail': widget.email,
        'fullName': _getFullName(),
        'requestId': requestId,
      };

      final Map<String, dynamic> userRequestPayload = baseAppointmentData;
      
      final Map<String, dynamic> multiPathUpdate = {
        'all_requests/$requestId': allRequestsPayload,
        'users/${widget.uid}/requests/$requestId': userRequestPayload,
      };

      await dbRef.update(multiPathUpdate);

      if (!mounted) return;

      await _showSuccessDialog();

      // Reset form and state after success
      setState(() {
        _selectedDate = null;
        _selectedTime = null;
        _messageController.clear();
        _appointmentType = 'Cedula Appointment';
        _submitting = false;
        // Trigger a re-check to show the new active request card
        _loadInitialData();
      });

    } catch (error) {
      if (!mounted) return;
      
      setState(() {
        _submitting = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Error submitting request: $error"),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  // --- WIDGET BUILDERS FOR UI STATES ---
  Widget _buildActiveRequestInfoCard() {
    final type = _activeRequestDetails?['documentType'] ?? 'Unknown Request';
    final status = _activeRequestDetails?['status'] ?? 'Unknown';
    final dateStr = _activeRequestDetails?['appointmentDateTime'] as String?;
    String formattedDate = 'Not set';

    if (dateStr != null) {
      try {
        final date = DateTime.parse(dateStr);
        formattedDate = DateFormat('MMMM dd, yyyy @ hh:mm a').format(date);
      } catch (e) {/* Ignore formatting errors */}
    }
    
    return Center(
      child: Card(
        elevation: 4,
        margin: const EdgeInsets.all(24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.info_rounded, color: Colors.deepPurple, size: 48),
              const SizedBox(height: 16),
              const Text(
                'Active Appointment Found',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.deepPurple),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'You already have an appointment in progress. You can request another one once this is Completed or Disapproved.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.black54, fontSize: 14),
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.deepPurple.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.deepPurple.withOpacity(0.2))
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Type: $type', style: const TextStyle(fontWeight: FontWeight.w500)),
                    const SizedBox(height: 4),
                    Text('Status: $status', style: const TextStyle(fontWeight: FontWeight.w500)),
                    const SizedBox(height: 4),
                    Text('Date: $formattedDate', style: const TextStyle(fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDisapprovedWarning() {
    final reason = _disapprovedRequestInfo?['rejectionReason'] ?? 'No reason provided.';
    final type = _disapprovedRequestInfo?['documentType'] ?? 'a previous request';

    return Material(
      color: Colors.amber.shade50,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Reason for disapproval: $reason'),
              duration: const Duration(seconds: 6),
              action: SnackBarAction(label: 'OK', onPressed: () {}),
            ),
          );
        },
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.amber.shade300)
          ),
          child: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.amber.shade800),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  "Note: You have a disapproved request for '$type'. Tap for details.",
                  style: TextStyle(color: Colors.amber.shade900, fontWeight: FontWeight.w500),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: () => setState(() => _showDisapprovedWarning = false),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRequestForm(BuildContext showcaseContext) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Card(
        elevation: 8,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: _submitting
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text("Submitting your appointment request...", style: TextStyle(fontSize: 16, color: Colors.deepPurple)),
                    ],
                  ),
                )
              : Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_disapprovedRequestInfo != null && _showDisapprovedWarning) ...[
                        _buildDisapprovedWarning(),
                        const SizedBox(height: 24),
                      ],
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Colors.deepPurple.shade300, Colors.deepPurple.shade600],
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text('Schedule an Appointment', textAlign: TextAlign.center, style: TextStyle(fontSize: 20, color: Colors.white, fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(height: 24),

                      if (_getFullName().isNotEmpty) ...[
                        TextFormField(
                          initialValue: _getFullName(),
                          decoration: InputDecoration(
                            labelText: 'Requested by',
                            prefixIcon: const Icon(Icons.person, color: Colors.deepPurple),
                            filled: true,
                            fillColor: Colors.grey.shade100,
                          ),
                          readOnly: true,
                        ),
                        const SizedBox(height: 16),
                      ],

                      Text("Select Appointment Type", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.deepPurple.shade700)),
                      const SizedBox(height: 8),
                      
                      Showcase(
                        key: _appointmentTypeKey,
                        title: 'Select Type',
                        description: 'Tap on an option to choose the type of appointment.',
                        enableAutoScroll: true,
                        child: Column(
                          children: _appointmentTypes.map((type) {
                            return Container(
                              width: double.infinity,
                              margin: const EdgeInsets.only(bottom: 8),
                              child: InkWell(
                                onTap: () {
                                  setState(() {
                                    _appointmentType = type;
                                  });
                                },
                                borderRadius: BorderRadius.circular(12),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                                  decoration: BoxDecoration(
                                    color: _appointmentType == type ? Colors.deepPurple : Colors.grey.shade100,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: _appointmentType == type ? Colors.deepPurple : Colors.grey.shade300,
                                      width: 2,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(getIconForAppointment(type), color: _appointmentType == type ? Colors.white : Colors.deepPurple, size: 24),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          type,
                                          style: TextStyle(
                                            color: _appointmentType == type ? Colors.white : Colors.deepPurple,
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                      if (_appointmentType == type) const Icon(Icons.check_circle, color: Colors.white, size: 20),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                      const SizedBox(height: 20),

                      Showcase(
                        key: _dateKey,
                        title: 'Select Date',
                        description: 'Tap here to pick your preferred date.',
                        enableAutoScroll: true,
                        child: TextFormField(
                          readOnly: true,
                          decoration: InputDecoration(
                            labelText: _selectedDate == null ? 'Select Appointment Date' : 'Date: ${_selectedDate!.toLocal().toString().split(' ')[0]}',
                            prefixIcon: const Icon(Icons.calendar_today, color: Colors.deepPurple),
                          ),
                          onTap: _pickDate,
                          validator: (value) {
                            if (_selectedDate == null) return 'Please select a date';
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(height: 16),

                      Showcase(
                        key: _timeKey,
                        title: 'Select Time',
                        description: 'Tap here to pick your preferred time.',
                        enableAutoScroll: true,
                        child: TextFormField(
                          readOnly: true,
                          decoration: InputDecoration(
                            labelText: _selectedTime == null ? 'Select Appointment Time' : 'Time: ${_selectedTime!.format(context)}',
                            prefixIcon: const Icon(Icons.access_time, color: Colors.deepPurple),
                          ),
                          onTap: _pickTime,
                          validator: (value) {
                            if (_selectedTime == null) return 'Please select a time';
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(height: 16),

                      Showcase(
                        key: _purposeKey,
                        title: 'Purpose',
                        description: 'Briefly describe why you need this appointment.',
                        enableAutoScroll: true,
                        child: TextFormField(
                          controller: _messageController,
                          decoration: const InputDecoration(
                            labelText: 'Appointment Purpose',
                            hintText: 'Enter the purpose of your appointment...',
                            prefixIcon: Icon(Icons.description, color: Colors.deepPurple),
                          ),
                          maxLines: 3,
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) return 'Please enter the purpose';
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(height: 32),

                      SizedBox(
                        width: double.infinity,
                        child: Showcase(
                          key: _submitKey,
                          title: 'Submit',
                          description: 'Review your details and tap here to send.',
                          enableAutoScroll: true,
                          child: ElevatedButton(
                            onPressed: _showConfirmationDialog,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.deepPurple,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: const Text(
                              "Submit Appointment Request",
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  // --- MAIN BUILD METHOD ---
  @override
  Widget build(BuildContext context) {
    return ShowCaseWidget(
      builder: (showcaseContext) {
        if (!_isLoadingState) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _checkAndStartTutorial(showcaseContext);
          });
        }

        return Scaffold(
          appBar: AppBar(
            title: const Text("New Appointment Request", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            backgroundColor: Colors.deepPurple,
            elevation: 0,
            iconTheme: const IconThemeData(color: Colors.white),
          ),
          body: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.deepPurple.shade300, Colors.deepPurple.shade100],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
            child: _isLoadingState
                ? const Center(child: CircularProgressIndicator(color: Colors.white))
                : _hasActiveRequest
                    ? _buildActiveRequestInfoCard()
                    : _buildRequestForm(showcaseContext),
          ),
        );
      },
    );
  }
}