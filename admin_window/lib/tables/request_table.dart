import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:open_file/open_file.dart';

class RequestTable extends StatelessWidget {
  final bool loading;
  final List<Map<String, dynamic>> requests;
  final Set<String> selectedRequests;
  final ValueChanged<Set<String>> onSelectedRequestsChanged;
  final Future<void> Function(
      String userId, String requestId, Map<String, dynamic> updatedData)
      onUpdateRequest;
  final Future<void> Function(String userId, String requestId)
      onRescheduleAppointment;
  final Future<void> Function(String userId, String requestId)
      onApproveAppointment;
  final Future<void> Function(String userId, String requestId)
      onDisapproveAppointment;
  final Future<bool> Function(String newStatus) onConfirmStatusChange;
  final VoidCallback onDeleteSelectedRequests;
  final void Function(BuildContext context, String documentType,
      Map<String, dynamic> request) onGenerateDocument;
  final Future<void> Function(String message) onLogAction;
  final Future<bool> Function(Map<String, dynamic> request, double amount)
      onRecordPayment;

  const RequestTable({
    super.key,
    required this.loading,
    required this.requests,
    required this.selectedRequests,
    required this.onSelectedRequestsChanged,
    required this.onUpdateRequest,
    required this.onRescheduleAppointment,
    required this.onApproveAppointment,
    required this.onDisapproveAppointment,
    required this.onConfirmStatusChange,
    required this.onDeleteSelectedRequests,
    required this.onGenerateDocument,
    required this.onLogAction,
    required this.onRecordPayment,
  });

  static const bool _showComplaintsInThisTable = false;

  // --- HELPER: Parse Timestamp for Sorting ---
  DateTime _parseTimestamp(dynamic value) {
    if (value == null) return DateTime.fromMillisecondsSinceEpoch(0);
    try {
      if (value is int) {
        return value < 2000000000
            ? DateTime.fromMillisecondsSinceEpoch(value * 1000)
            : DateTime.fromMillisecondsSinceEpoch(value);
      } else if (value is double) {
        final iv = value.toInt();
        return iv < 2000000000
            ? DateTime.fromMillisecondsSinceEpoch(iv * 1000)
            : DateTime.fromMillisecondsSinceEpoch(iv);
      } else {
        final s = value.toString();
        // Try parsing ISO string
        DateTime? dt = DateTime.tryParse(s);
        if (dt != null) return dt;
        
        final n = int.tryParse(s);
        if (n != null) {
          return n < 2000000000
              ? DateTime.fromMillisecondsSinceEpoch(n * 1000)
              : DateTime.fromMillisecondsSinceEpoch(n);
        }
      }
    } catch (_) {
      return DateTime.fromMillisecondsSinceEpoch(0);
    }
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  String _formatResidentName(String? fullName) {
    if (fullName == null || fullName.trim().isEmpty) return "N/A";
    
    List<String> parts = fullName.trim().split(RegExp(r'\s+'));
    final titles = ['mr.', 'ms.', 'mrs.', 'dr.', 'atty.', 'prof.', 'hon.'];
    
    // Remove title (e.g. Mr.)
    if (parts.isNotEmpty && titles.contains(parts[0].toLowerCase())) {
      parts.removeAt(0);
    }

    if (parts.isEmpty) return fullName;
    if (parts.length == 1) return parts[0];
    if (parts.length == 2) return "${parts[0]} ${parts[1]}";

    String first = parts.first;
    String middleInitial;
    
    // Check if the 2nd part is already an initial (e.g. "P.") from your Offline Form
    if (parts[1].endsWith('.') && parts[1].length <= 3) {
      middleInitial = parts[1]; // Use existing initial
    } else {
      middleInitial = "${parts[1][0].toUpperCase()}."; // Create initial
    }

    // --- FIX: Join ALL remaining parts to keep Last Name AND Suffix ---
    // Start from index 2 (after First Name and Middle Name)
    String remainder = parts.sublist(2).join(" "); 
    
    return "$first $middleInitial $remainder";
  }

  String _getRequestTitle(Map<String, dynamic> req) {
    if (req['documentType'] != null &&
        req['documentType'].toString().trim().isNotEmpty) {
      return req['documentType'].toString();
    }
    if (req['title'] != null && req['title'].toString().trim().isNotEmpty) {
      return req['title'].toString();
    }
    if (req['subject'] != null && req['subject'].toString().trim().isNotEmpty) {
      return req['subject'].toString();
    }
    if (req['purpose'] != null && req['purpose'].toString().trim().isNotEmpty) {
      return req['purpose'].toString();
    }
    return "Unknown Request";
  }

  bool _isComplaint(Map<String, dynamic> r) {
    final docType = (r['documentType'] ?? '').toString().toLowerCase();
    return docType.contains('complaint');
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'released':
      case 'completed': // A completed appointment is a success state
        return Colors.green;
      case 'successful': 
        return Colors.teal;
      case 'rejected':
      case 'disapproved':
      case 'denied':
      case 'cancelled':
        return Colors.red;
      case 'rescheduled': // Rescheduled is an action, but the state is effectively "Approved"
      case 'approved':
        return Colors.blue;
      case 'for signing':
        return Colors.orange;
      case 'processing':
        return Colors.indigo;
      case 'pending':
      default:
        return Colors.orange;
    }
  }

  IconData _getStatusIcon(String value) {
    final s = value.toString().toLowerCase();
    if (s.contains('release') || s.contains('complete')) {
      return Icons.task_alt_rounded; // A clear "Done" icon
    }
    if (s.contains('success')) {
      return Icons.check_circle_outline; // Ready for pickup
    }
    if (s.contains('reject') ||
        s.contains('disapprove') ||
        s.contains('denied') ||
        s.contains('cancel')) {
      return Icons.cancel_rounded;
    }
    if (s.contains('signing')) {
      return Icons.edit_rounded;
    }
    if (s.contains('resched') || s.contains('approved')) {
      return Icons.thumb_up_alt_rounded;
    }
    if (s.contains('process') ||
        s.contains('review') ||
        s.contains('verify')) {
      return Icons.pending_actions_rounded;
    }
    if (s.contains('pending') || s.contains('new') || s.contains('submit')) {
      return Icons.hourglass_top_rounded;
    }
    return Icons.info_rounded;
  }


  String _formatDateTime(dynamic value) {
    DateTime dt = _parseTimestamp(value);
    if (dt.millisecondsSinceEpoch == 0) return '';
    return DateFormat('MM/dd/yyyy hh:mm a').format(dt.toLocal());
  }

  Widget _highlightBox(String text, Color color) {
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
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
    list.sort((a, b) {
      final aTs = _parseTimestamp(a['timestamp']);
      final bTs = _parseTimestamp(b['timestamp']);
      return aTs.compareTo(bTs);
    });
    return list;
  }

  Future<Map<String, String>> _getExtraDetailsForStatus(
      BuildContext context, String newStatus) async {
    final TextEditingController remarksController = TextEditingController();
    final TextEditingController reasonController = TextEditingController();

    // --- NEW: CANCELLED LOGIC ---
    if (newStatus == "Cancelled") {
      final result = await showDialog<Map<String, String>>(
        context: context,
        builder: (ctx) => AlertDialog(
          scrollable: true,
          title: const Text("Cancel Request"),
          content: Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text("Why is this request being cancelled?", style: TextStyle(color: Colors.grey)),
                const SizedBox(height: 10),
                TextField(
                  controller: reasonController,
                  decoration: const InputDecoration(
                    labelText: "Reason (e.g. Did not pick up)",
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(null),
              child: const Text("Back"),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
              onPressed: () {
                Navigator.of(ctx).pop(<String, String>{
                  "rejectionReason": reasonController.text.trim().isEmpty ? "Did not pick up document" : reasonController.text.trim(),
                });
              },
              child: const Text("Confirm Cancel"),
            ),
          ],
        ),
      );
      return result ?? {};
    }
    // ---------------------------

    if (newStatus == "Disapproved") {
      final result = await showDialog<Map<String, String>>(
        context: context,
        builder: (ctx) => AlertDialog(
          scrollable: true,
          title: const Text("Provide Disapproval Reason"),
          content: Padding(
            padding:
                EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: TextField(
              controller: reasonController,
              decoration: const InputDecoration(
                labelText: "Reason for disapproval",
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(null),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(ctx).pop(<String, String>{
                  "rejectionReason": reasonController.text.trim(),
                });
              },
              child: const Text("Save"),
            ),
          ],
        ),
      );
      return result ?? {};
    } else if (newStatus == "Rescheduled") {
      DateTime? selectedDate;
      TimeOfDay? selectedTime;

      final result = await showDialog<Map<String, String>>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            scrollable: true,
            title: const Text("Reschedule Appointment"),
            content: Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    title: Text(selectedDate == null
                        ? "Select Date"
                        : "Date: ${selectedDate!.day}/${selectedDate!.month}/${selectedDate!.year}"),
                    leading: const Icon(Icons.calendar_today),
                    onTap: () async {
                      final now = DateTime.now();
                      final date = await showDatePicker(
                        context: context,
                        initialDate: now,
                        firstDate: now,
                        lastDate: now.add(const Duration(days: 365)),
                      );
                      if (date != null) {
                        setState(() => selectedDate = date);
                      }
                    },
                  ),
                  ListTile(
                    title: Text(selectedTime == null
                        ? "Select Time"
                        : "Time: ${selectedTime!.format(context)}"),
                    leading: const Icon(Icons.access_time),
                    onTap: () async {
                      final time = await showTimePicker(
                        context: context,
                        initialTime: TimeOfDay.now(),
                      );
                      if (time != null) {
                        setState(() => selectedTime = time);
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: remarksController,
                    decoration: const InputDecoration(
                      labelText: "Remarks (optional)",
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 2,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(null),
                child: const Text("Cancel"),
              ),
              ElevatedButton(
                onPressed: selectedDate != null && selectedTime != null
                    ? () {
                        final DateTime scheduledDateTime = DateTime(
                          selectedDate!.year,
                          selectedDate!.month,
                          selectedDate!.day,
                          selectedTime!.hour,
                          selectedTime!.minute,
                        );
                        Navigator.of(ctx).pop(<String, String>{
                          "rescheduledDate":
                              scheduledDateTime.toIso8601String(),
                          "remarks": remarksController.text.trim(),
                        });
                      }
                    : null,
                child: const Text("Save"),
              ),
            ],
          ),
        ),
      );
      return result ?? {};
    } else if (newStatus == "Rejected") {
      final result = await showDialog<Map<String, String>>(
        context: context,
        builder: (ctx) => AlertDialog(
          scrollable: true,
          title: const Text("Provide Rejection Reason"),
          content: Padding(
            padding:
                EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: TextField(
              controller: reasonController,
              decoration: const InputDecoration(
                labelText: "Reason for rejection",
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(null),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(ctx).pop(<String, String>{
                  "rejectionReason": reasonController.text.trim(),
                });
              },
              child: const Text("Save"),
            ),
          ],
        ),
      );
      return result ?? {};
    } else if (newStatus == "Processing" || newStatus == "Successful") {
      // Allow optional remarks for Processing and Successful
      final result = await showDialog<Map<String, String>>(
        context: context,
        builder: (ctx) => AlertDialog(
          scrollable: true,
          title: Text(newStatus == "Successful" ? "Ready for Pickup?" : "Start Processing"),
          content: Padding(
            padding:
                EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (newStatus == "Successful")
                  const Padding(
                    padding: EdgeInsets.only(bottom: 10.0),
                    child: Text("Marking as 'Successful' means the document is printed and ready for the resident to pick up.", style: TextStyle(fontSize: 13, color: Colors.grey)),
                  ),
                TextField(
                  controller: remarksController,
                  decoration: const InputDecoration(
                    labelText: "Remarks (optional)",
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(null),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(ctx).pop(<String, String>{
                  "remarks": remarksController.text.trim(),
                });
              },
              child: Text(newStatus == "Successful" ? "Confirm Ready" : "Start"),
            ),
          ],
        ),
      );
      return result ?? {};
    }

    return {};
  }


  Future<double?> _promptForPayment(BuildContext context) async {
    final amountController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    return showDialog<double>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Record Payment & Release'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("The resident has picked up the document. Please enter the payment amount received.", style: TextStyle(fontSize: 13, color: Colors.grey)),
              const SizedBox(height: 15),
              TextFormField(
                controller: amountController,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Amount Paid',
                  prefixText: '₱ ',
                  border: OutlineInputBorder(),
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
                ],
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter an amount.';
                  }
                  if (double.tryParse(value) == null) {
                    return 'Please enter a valid number.';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
            onPressed: () {
              if (formKey.currentState!.validate()) {
                final amount = double.tryParse(amountController.text) ?? 0.0;
                Navigator.of(ctx).pop(amount);
              }
            },
            child: const Text('Confirm & Release'),
          ),
        ],
      ),
    );
  }

  String _formatAddress(Map<String, dynamic>? addr) {
    if (addr == null) return "N/A";
    List<String> parts = [
      addr['street'],
      addr['barangay'],
      addr['municipality'],
      addr['province']
    ].where((s) => s != null && s.toString().isNotEmpty).cast<String>().toList();
    return parts.join(', ');
  }

  // +++ NEW HELPER: Determines valid next statuses for an appointment. +++
  List<String> _getAppointmentStatusOptions(String currentStatus) {
    switch (currentStatus) {
      case "Pending":
        // From Pending, we can Approve, Disapprove, or Reschedule.
        return ["Pending", "Approved", "Disapproved", "Rescheduled"];
      
      case "Approved":
      case "Rescheduled": // A "Rescheduled" appointment is essentially an approved one.
        // From Approved, the appointment can be marked as Completed or Disapproved.
        return [currentStatus, "Completed", "Disapproved"];

      case "Disapproved":
      case "Completed":
        // These are terminal states. No further status changes are allowed.
        return [currentStatus]; 

      default:
        // Fallback for any other state, allows it to stay as is.
        return [currentStatus];
    }
  }

  Future<void> _showRequestViewDialog(
      BuildContext outerContext, Map<String, dynamic> request) async {
    final String userId = request['userId'] ?? "";
    final String requestId = request['requestId'] ?? "";
    final String residentName = _formatResidentName(request['fullName']); 

    final String safeTitle = _getRequestTitle(request);

    final docType = safeTitle.toLowerCase();
    final bool isAppointment =
        docType.contains('appointment') || docType.contains('meeting');
    
    // --- STATUS LOGIC IS NOW HANDLED DYNAMICALLY BELOW ---

    String currentStatus = request['status'] ?? "Pending";
    Color currentColor = _getStatusColor(currentStatus);
    IconData currentIcon = _getStatusIcon(currentStatus);

    List<Map<String, dynamic>> history =
        _sortHistory(_extractHistoryList(request['statusHistory']));
    history = history.reversed.toList();

    await showDialog(
      context: outerContext,
      builder: (ctx) {
        String selectedStatus = currentStatus;
        bool saving = false;

        return StatefulBuilder(
          builder: (context, setState) {

            // +++ NEW: DYNAMICALLY GET STATUS OPTIONS FOR APPOINTMENTS +++
            final List<String> statusOptions = isAppointment 
                ? _getAppointmentStatusOptions(currentStatus) 
                : [];
            final bool canChangeStatus = statusOptions.length > 1;

            // --- APPOINTMENT STATUS CHANGE LOGIC (Only runs for appointments) ---
            Future<void> applyStatusChange() async {
              if (selectedStatus == currentStatus) {
                Navigator.of(context).pop();
                return;
              }

              if (!await onConfirmStatusChange(selectedStatus)) return;

              final extra =
                  await _getExtraDetailsForStatus(context, selectedStatus);

              bool cancelled = false;
              if (selectedStatus == "Rescheduled") {
                cancelled = extra.isEmpty ||
                    (extra["rescheduledDate"] == null ||
                        (extra["rescheduledDate"] as String).isEmpty);
              } else if (selectedStatus == "Disapproved") {
                // For disapproval, a reason is not strictly required but good practice.
                // We'll proceed even if the reason is empty, but the dialog prompts for it.
                 cancelled = extra.isEmpty; // This was your original logic, keeping it.
              }

              if (cancelled) {
                setState(() => selectedStatus = currentStatus);
                ScaffoldMessenger.of(outerContext).showSnackBar(
                  const SnackBar(
                    content: Text("Update cancelled"),
                    backgroundColor: Colors.grey,
                  ),
                );
                return;
              }

              setState(() => saving = true);

              // +++ NEW: Smart status logic for Reschedule -> Approved +++
              final String finalStatusToSave = (selectedStatus == "Rescheduled") ? "Approved" : selectedStatus;
              final String historyStageLog = selectedStatus; // Log the actual action taken

              final Map<String, dynamic> updatedData = {
                'status': finalStatusToSave, // Save the final status
                'updatedAt': DateTime.now().toIso8601String(),
                'documentType': request['documentType'],
                'title': request['title'],
                'subject': request['subject'],
                'purpose': request['purpose'],
                'controlNumber': request['controlNumber'],
              };

              if (extra.containsKey("remarks")) {
                updatedData['remarks'] = extra["remarks"];
              }
              if (extra.containsKey("rejectionReason")) {
                updatedData['rejectionReason'] = extra["rejectionReason"];
              }
              if (extra.containsKey("rescheduledDate")) {
                updatedData['appointmentDateTime'] = extra["rescheduledDate"];
              }

              final List<dynamic> prevHistoryDyn =
                  request['statusHistory'] is List
                      ? List<dynamic>.from(request['statusHistory'])
                      : request['statusHistory'] is Map
                          ? (request['statusHistory'] as Map).values.toList()
                          : <dynamic>[];

              updatedData['statusHistory'] = [
                ...prevHistoryDyn,
                {
                  "stage": historyStageLog, // Log the action (e.g., "Rescheduled")
                  "timestamp": DateTime.now().toIso8601String(),
                  "remarks": extra["remarks"] ?? '',
                  "rejectionReason": extra["rejectionReason"] ?? '',
                  "rescheduledDate": (historyStageLog == "Rescheduled") ? extra["rescheduledDate"] ?? '' : '',
                }
              ];

              try {
                await onUpdateRequest(userId, requestId, updatedData);

                final String logMessage =
                    "Updated status for $residentName's request ($safeTitle) to '$historyStageLog'.";
                await onLogAction(logMessage);

                setState(() {
                  // Update the dialog UI to reflect the new state
                  currentStatus = finalStatusToSave;
                  currentColor = _getStatusColor(currentStatus);
                  currentIcon = _getStatusIcon(currentStatus);

                  history.insert(0, {
                    "stage": historyStageLog,
                    "timestamp": DateTime.now().toIso8601String(),
                    "remarks": extra["remarks"] ?? '',
                    "rejectionReason": extra["rejectionReason"] ?? '',
                    "rescheduledDate": (historyStageLog == "Rescheduled") ? extra["rescheduledDate"] ?? '' : '',
                  });

                  saving = false;
                });

                await showDialog(
                  context: context, 
                  builder: (alertCtx) => AlertDialog(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    title: const Row(
                      children: [
                        Icon(Icons.check_circle, color: Colors.green, size: 28),
                        SizedBox(width: 10),
                        Text("Status Updated"),
                      ],
                    ),
                    content: Text("The appointment status is now '$finalStatusToSave'."),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(alertCtx).pop(),
                        child: const Text("OK"),
                      ),
                    ],
                  ),
                );

              } catch (e) {
                setState(() => saving = false);
                ScaffoldMessenger.of(outerContext).showSnackBar(
                  SnackBar(content: Text("Failed to update: $e"), backgroundColor: Colors.red),
                );
              }
            }

            final String apptDate =
                _formatDateTime(request['appointmentDateTime']);
            final String createdAt = _formatDateTime(request['timestamp']);

            return AlertDialog(
              scrollable: true,
              contentPadding: EdgeInsets.zero,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              titlePadding: EdgeInsets.zero,
              title: Container(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                decoration: BoxDecoration(
                  color: currentColor.withOpacity(0.1),
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(14)),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: currentColor.withOpacity(0.15),
                      child: Icon(currentIcon, color: currentColor, size: 18),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        safeTitle,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                    Chip(
                      label: Text(currentStatus,
                          style: TextStyle(color: currentColor)),
                      avatar: Icon(currentIcon, color: currentColor, size: 18),
                      backgroundColor: currentColor.withOpacity(0.12),
                      shape: StadiumBorder(
                        side: BorderSide(color: currentColor.withOpacity(0.3)),
                      ),
                    ),
                  ],
                ),
              ),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 580),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start, // Align left
                    children: [
                      // --- 1. BASIC USER INFO ---
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _detailTile(
                              icon: Icons.person,
                              label: "User",
                              value: request['userEmail'] ?? "N/A",
                              color: Colors.blue,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _detailTile(
                              icon: Icons.badge,
                              label: "Name",
                              value: (request['fullName'] ?? '').toString().isEmpty
                                  ? "N/A"
                                  : request['fullName'],
                              color: Colors.teal,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),

                      // --- 2. PHONE NUMBER (NEW) ---
                      if (request['phoneNumber'] != null) ...[
                         _detailTile(
                            icon: Icons.phone,
                            label: "Phone Number",
                            value: request['phoneNumber'],
                            color: Colors.green,
                         ),
                         const SizedBox(height: 10),
                      ],

                      // --- 3. DYNAMIC FORM DATA (NEW) ---
                      if (docType.contains('business')) ...[
                        const Text("Business Details", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange)),
                        const SizedBox(height: 4),
                        _detailTile(icon: Icons.store, label: "Business Name", value: request['businessDetails']?['businessName'] ?? 'N/A', color: Colors.orange),
                        const SizedBox(height: 4),
                        _detailTile(icon: Icons.person_pin, label: "Operator", value: request['businessDetails']?['operator'] ?? 'N/A', color: Colors.orange),
                        const SizedBox(height: 4),
                        _detailTile(icon: Icons.location_on, label: "Address", value: _formatAddress(request['businessDetails']?['businessAddress']), color: Colors.orange),
                        const SizedBox(height: 10),
                      ],

                      if (docType.contains('late') || docType.contains('birth')) ...[
                        const Text("Birth Details", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.purple)),
                        const SizedBox(height: 4),
                        _detailTile(icon: Icons.cake, label: "Birth Date", value: request['birthDate'] ?? 'N/A', color: Colors.purple),
                        const SizedBox(height: 4),
                        _detailTile(icon: Icons.location_city, label: "Place of Birth", value: request['placeOfBirth'] ?? 'N/A', color: Colors.purple),
                        const SizedBox(height: 4),
                        _detailTile(icon: Icons.male, label: "Father", value: request['fatherName'] ?? 'N/A', color: Colors.purple),
                        const SizedBox(height: 4),
                        _detailTile(icon: Icons.female, label: "Mother", value: request['motherName'] ?? 'N/A', color: Colors.purple),
                        const SizedBox(height: 10),
                      ],

                      if (docType.contains('cohabitation')) ...[
                        const Text("Cohabitation Details", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.pink)),
                        const SizedBox(height: 4),
                        _detailTile(icon: Icons.favorite, label: "Partner", value: request['cohabitationDetails']?['partnerName'] ?? 'N/A', color: Colors.pink),
                        const SizedBox(height: 4),
                        _detailTile(icon: Icons.cake, label: "Partner Birthdate", value: request['cohabitationDetails']?['partnerBirthDate'] ?? 'N/A', color: Colors.pink),
                        const SizedBox(height: 4),
                        _detailTile(icon: Icons.date_range, label: "Living Since", value: request['cohabitationDetails']?['cohabitationStartDate'] ?? 'N/A', color: Colors.pink),
                        const SizedBox(height: 10),
                      ],

                      if (docType.contains('seaweeds')) ...[
                        const Text("Seaweeds Details", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.brown)),
                        const SizedBox(height: 4),
                        _detailTile(icon: Icons.shopping_cart, label: "Buyer", value: request['seaweedsDetails']?['buyerName'] ?? 'N/A', color: Colors.brown),
                        const SizedBox(height: 4),
                        _detailTile(icon: Icons.scale, label: "Quantity", value: request['seaweedsDetails']?['quantity'] ?? 'N/A', color: Colors.brown),
                        const SizedBox(height: 4),
                        _detailTile(icon: Icons.payments, label: "Amount", value: "₱${request['seaweedsDetails']?['amountFigures'] ?? '0'}", color: Colors.brown),
                        const SizedBox(height: 10),
                      ],

                      // --- 4. STANDARD DETAILS (Appointment, etc) ---
                      const SizedBox(height: 10),
                      if (apptDate.isNotEmpty || isAppointment) ...[
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: _detailTile(
                                icon: Icons.event,
                                label: "Appointment",
                                value: apptDate.isNotEmpty ? apptDate : "Not set",
                                color: Colors.deepPurple,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _detailTile(
                                icon: Icons.info_outline,
                                label: "Purpose/Message",
                                value: (request['message'] ?? '').toString().isNotEmpty
                                    ? request['message']
                                    : "N/A",
                                color: Colors.orange,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                      ],
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _detailTile(
                              icon: Icons.access_time,
                              label: "Requested",
                              value: createdAt.isNotEmpty ? createdAt : "N/A",
                              color: Colors.grey,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _detailTile(
                              icon: Icons.confirmation_num,
                              label: "Control No.",
                              value: (request['controlNumber'] ?? '').toString().isNotEmpty
                                  ? request['controlNumber']
                                  : "N/A",
                              color: Colors.purple,
                            ),
                          ),
                        ],
                      ),
                      
                      const SizedBox(height: 16),
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text("Timeline", style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(height: 8),
                      
                      // --- TIMELINE BUILDER ---
                      Builder(
                        builder: (context) {
                          final list = history;
                          if (list.isEmpty) {
                            return const Align(
                              alignment: Alignment.centerLeft,
                              child: Text("No updates yet."),
                            );
                          }
                          return Column(
                            children: list.map((entry) {
                              final stage = (entry['stage'] ?? 'Unknown').toString();
                              final time = _formatDateTime(entry['timestamp']);
                              final remarks = (entry['remarks'] ?? '').toString();
                              final reason = (entry['rejectionReason'] ?? '').toString();
                              final resched = (entry['rescheduledDate'] ?? '').toString();
                              final stageColor = _getStatusColor(stage);
                              final stageIcon = _getStatusIcon(stage);
                              final isNegative = ['rejected', 'disapproved', 'denied', 'cancelled'].contains(stage.toLowerCase());

                              return Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      margin: const EdgeInsets.only(right: 8, top: 2),
                                      child: CircleAvatar(
                                        radius: 12,
                                        backgroundColor: stageColor.withOpacity(0.12),
                                        child: Icon(stageIcon, size: 16, color: stageColor),
                                      ),
                                    ),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            "$stage (${time.isNotEmpty ? time : 'n/a'})",
                                            style: TextStyle(
                                              color: isNegative ? Colors.red : Colors.black87,
                                              fontWeight: isNegative ? FontWeight.bold : FontWeight.w500,
                                            ),
                                          ),
                                          if (remarks.isNotEmpty)
                                            _highlightBox("📝 Remarks: $remarks", Colors.amber),
                                          if (reason.isNotEmpty)
                                            _highlightBox("❗ Reason: $reason", Colors.red),
                                          if (resched.isNotEmpty)
                                            _highlightBox("📅 Rescheduled to: ${_formatDateTime(resched)}", Colors.blue),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                          );
                        },
                      ),
                      const SizedBox(height: 14),

                      // +++ UPDATED: CONDITIONAL CHANGE STATUS BOX (ONLY FOR APPOINTMENTS) +++
                      if (isAppointment && canChangeStatus) 
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text("Change Appointment Status",
                                style: TextStyle(fontWeight: FontWeight.bold)),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: DropdownButtonFormField<String>(
                                    // Make sure the initial value is in the list
                                    initialValue: statusOptions.contains(selectedStatus) ? selectedStatus : statusOptions.first,
                                    hint: const Text("Select Status"),
                                    decoration: const InputDecoration(
                                      border: OutlineInputBorder(),
                                      contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                                    ),
                                    items: statusOptions // Use dynamic list
                                        .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                                        .toList(),
                                    onChanged: saving ? null : (val) {
                                      if (val == null) return;
                                      setState(() => selectedStatus = val);
                                    },
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Flexible(
                                  child: ElevatedButton.icon(
                                    onPressed: saving ? null : applyStatusChange,
                                    icon: saving
                                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                        : const Icon(Icons.save),
                                    label: Text(saving ? "..." : "Update"),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.deepPurple,
                                      foregroundColor: Colors.white,
                                    ),
                                  ),
                                )
                              ],
                            ),
                          ],
                        ),
                      ),
                      // -------------------------------------------------------------
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text("Close"),
                ),
              ],
            );
          },
        );
      },
    );
  }
 
 Widget _detailTile({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: color,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Colors.black87,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());

    // 1. FILTER LIST (Remove complaints)
    final visibleRequests = _showComplaintsInThisTable
        ? List<Map<String, dynamic>>.from(requests)
        : requests.where((r) => !_isComplaint(r)).toList();

    // 2. SORTING LOGIC: Newest First
    visibleRequests.sort((a, b) {
      final tA = a['timestamp'] ?? a['createdAt'];
      final tB = b['timestamp'] ?? b['createdAt'];
      final dtA = _parseTimestamp(tA);
      final dtB = _parseTimestamp(tB);
      return dtB.compareTo(dtA); 
    });

    if (visibleRequests.isEmpty) {
      return const Center(
        child: Text("No document requests found",
            style: TextStyle(fontSize: 18)),
      );
    }

    return Column(
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: onDeleteSelectedRequests,
            icon: const Icon(Icons.delete_forever, color: Colors.red),
            label: const Text("Archive", style: TextStyle(color: Colors.red)),
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                scrollDirection: Axis.vertical,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: constraints.maxWidth,
                    child: DataTable(
                      headingRowColor: WidgetStateProperty.all(
                        const Color.fromARGB(255, 200, 226, 247),
                      ),
                      columnSpacing: 20,
                      columns: const [
                        DataColumn(
                            label: Text("Select",
                                style: TextStyle(fontWeight: FontWeight.bold))),
                        DataColumn(
                            label: Text("Resident Name",
                                style: TextStyle(fontWeight: FontWeight.bold))),
                        DataColumn(
                            label: Text("Request Type",
                                style: TextStyle(fontWeight: FontWeight.bold))),
                        DataColumn(
                            label: Text("Status",
                                style: TextStyle(fontWeight: FontWeight.bold))),
                        DataColumn(label: Text("Actions")),
                      ],
                      rows: visibleRequests.map((request) {
                        final String userId = request['userId'] ?? "";
                        final String requestId = request['requestId'] ?? "";
                        final String key = "$userId|$requestId";

                        final String safeTitle = _getRequestTitle(request);
                        final String docTypeLc = safeTitle.toLowerCase().trim();

                        final bool isAppointment =
                            docTypeLc.contains('appointment') ||
                                docTypeLc.contains('meeting');

                        String currentStatus = request['status'] ?? "Pending";
                        final color = _getStatusColor(currentStatus);
                        final icon = _getStatusIcon(currentStatus);


                        Widget statusCell;
                        if (currentStatus == "Processing") {
                          statusCell = Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.indigo.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.indigo.withOpacity(0.3)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: const [
                                SizedBox(
                                  width: 12, 
                                  height: 12, 
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.indigo)
                                ),
                                SizedBox(width: 8),
                                Text(
                                  "GENERATING...",
                                  style: TextStyle(
                                    color: Colors.indigo, 
                                    fontWeight: FontWeight.bold, 
                                    fontSize: 11
                                  ),
                                ),
                              ],
                            ),
                          );
                        } 

                        else if (!isAppointment) {
                          List<String> dropdownOptions = [];
                          
                          if (currentStatus == "Pending") {
                            dropdownOptions = ["Pending", "Processing", "Rejected"];
                          } else if (currentStatus == "Processing") {
                            dropdownOptions = ["Processing", "For Signing", "Rejected"];
                          } else if (currentStatus == "For Signing") {
                            dropdownOptions = ["For Signing", "Successful", "Rejected"];
                          } else if (currentStatus == "Successful") {
                            dropdownOptions = ["Successful", "Released", "Cancelled"];
                          } else if (currentStatus == "Released" || currentStatus == "Cancelled" || currentStatus == "Rejected") {
                             dropdownOptions = [currentStatus];
                          } else {
                            dropdownOptions = ["Pending", "Processing", "Rejected"];
                          }

                          statusCell = Row(
                            children: [
                              DropdownButton<String>(
                                value: currentStatus,
                                onChanged: (String? newStatus) async {
                                  if (newStatus == null ||
                                      newStatus == currentStatus) {
                                    return;
                                  }

                                  if (await onConfirmStatusChange(newStatus)) {
                                    double? paymentAmount;
                                    
                                    if (newStatus == "Released") {
                                      paymentAmount = await _promptForPayment(context);
                                      if (paymentAmount == null) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          const SnackBar(
                                            content:
                                                Text("Status update cancelled. Payment not recorded."),
                                            backgroundColor: Colors.grey,
                                          ),
                                        );
                                        return;
                                      }
                                    }

                                    if (paymentAmount != null) {
                                      final bool paymentSucceeded =
                                          await onRecordPayment(
                                              request, paymentAmount);
                                      if (!paymentSucceeded) {
                                        return;
                                      }
                                    }

                                    final extra =
                                        await _getExtraDetailsForStatus(
                                            context, newStatus);

                                    if ((newStatus == "Rejected" ||
                                            newStatus == "Processing" || newStatus == "Cancelled") &&
                                        extra.isEmpty) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        const SnackBar(
                                          content: Text("Update cancelled"),
                                          backgroundColor: Colors.grey,
                                        ),
                                      );
                                      return;
                                    }

                                    final Map<String, dynamic> updatedData = {
                                      'status': newStatus,
                                      'updatedAt':
                                          DateTime.now().toIso8601String(),
                                      'documentType': request['documentType'],
                                      'title': request['title'],
                                      'subject': request['subject'],
                                      'purpose': request['purpose'],
                                      'controlNumber': request['controlNumber'],
                                    };

                                    if (paymentAmount != null) {
                                      updatedData['paymentAmount'] =
                                          paymentAmount;
                                      updatedData['paymentTimestamp'] =
                                          DateTime.now().toIso8601String();
                                    }

                                    if (extra.containsKey("remarks")) {
                                      updatedData['remarks'] = extra["remarks"];
                                    }
                                    if (extra.containsKey("rejectionReason")) {
                                      updatedData['rejectionReason'] =
                                          extra["rejectionReason"];
                                    }

                                    final List<dynamic> prevHistoryDyn =
                                        request['statusHistory'] is List
                                            ? List<dynamic>.from(
                                                request['statusHistory'])
                                            : request['statusHistory'] is Map
                                                ? (request['statusHistory']
                                                        as Map)
                                                    .values
                                                    .toList()
                                                : <dynamic>[];

                                    updatedData['statusHistory'] = [
                                      ...prevHistoryDyn,
                                      {
                                        "stage": newStatus,
                                        "timestamp":
                                            DateTime.now().toIso8601String(),
                                        "remarks": extra["remarks"] ?? '',
                                        "rejectionReason":
                                            extra["rejectionReason"] ?? '',
                                        "rescheduledDate": '',
                                      }
                                    ];

                                    await onUpdateRequest(
                                        userId, requestId, updatedData);

                                    final String nameForLog = _formatResidentName(request['fullName']);
                                    
                                    final String logMessage =
                                        "Updated status for $nameForLog's request ($safeTitle) to '$newStatus'.";
                                    await onLogAction(logMessage);

                                    if (paymentAmount != null) {
                                      final currencyFormatter =
                                          NumberFormat.currency(
                                              locale: 'en_PH', symbol: '₱');
                                      
                                      await showDialog(
                                        context: context,
                                        builder: (ctx) => AlertDialog(
                                          shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(16)),
                                          title: const Row(
                                            children: [
                                              Icon(Icons.check_circle, 
                                                   color: Colors.green, size: 30),
                                              SizedBox(width: 10),
                                              Text("Payment Recorded"),
                                            ],
                                          ),
                                          content: ConstrainedBox(
                                            constraints: const BoxConstraints(
                                              minWidth: 450,
                                              minHeight: 180,
                                            ),
                                            child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              children: [
                                                const Text(
                                                  "Payment recorded successfully!",
                                                  style: TextStyle(fontSize: 18, color: Colors.grey),
                                                ),
                                                const SizedBox(height: 15),
                                                Text(
                                                  currencyFormatter.format(paymentAmount),
                                                  style: const TextStyle(
                                                    fontSize: 40, 
                                                    fontWeight: FontWeight.bold, 
                                                    color: Colors.green
                                                  ),
                                                ),
                                                const SizedBox(height: 15),
                                                const Text(
                                                  "The status is now 'Released'.",
                                                  style: TextStyle(fontSize: 14),
                                                ),
                                              ],
                                            ),
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed: () => Navigator.of(ctx).pop(),
                                              child: const Text("CLOSE", style: TextStyle(fontSize: 16)),
                                            ),
                                          ],
                                        ),
                                      );
                                    }
                                  }
                                },
                                items: dropdownOptions
                                    .map<DropdownMenuItem<String>>(
                                        (String value) {
                                  return DropdownMenuItem<String>(
                                    value: value,
                                    child: Text(value),
                                  );
                                }).toList(),
                              ),
                              if (currentStatus.toLowerCase() ==
                                      'for signing' &&
                                  request['documentWordPath'] != null)
                                Padding(
                                  padding: const EdgeInsets.only(left: 8.0),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.orange,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: const [
                                        Icon(Icons.print,
                                            color: Colors.white, size: 14),
                                        SizedBox(width: 4),
                                        Text(
                                          'READY TO PRINT',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              if (currentStatus.toLowerCase() == 'successful')
                                Padding(
                                  padding: const EdgeInsets.only(left: 8.0),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.teal,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Text(
                                      'WAITING PICKUP',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                              if (currentStatus.toLowerCase() == 'pending')
                                Padding(
                                  padding: const EdgeInsets.only(left: 8.0),
                                  child: Container(
                                    width: 10,
                                    height: 10,
                                    decoration: const BoxDecoration(
                                      color: Colors.red,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                ),
                            ],
                          );
                        } else {
                          // This is for appointments in the main table view
                          statusCell = Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Chip(
                                label: Text(
                                  currentStatus,
                                  style: TextStyle(
                                      color: color,
                                      fontWeight: FontWeight.w600),
                                ),
                                avatar: Icon(icon, color: color, size: 18),
                                backgroundColor: color.withOpacity(0.12),
                                shape: StadiumBorder(
                                  side:
                                      BorderSide(color: color.withOpacity(0.3)),
                                ),
                              ),
                              if (currentStatus.toLowerCase() == 'pending')
                                Padding(
                                  padding: const EdgeInsets.only(left: 6.0),
                                  child: Container(
                                    width: 10,
                                    height: 10,
                                    decoration: const BoxDecoration(
                                      color: Colors.red,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                ),
                            ],
                          );
                        }

                        Widget actionsCell;
                        List<Widget> buttons = [];
                        buttons.add(
                          Tooltip(
                            message: 'View Request Details',
                            child: IconButton(
                              icon: const Icon(Icons.visibility, color: Colors.deepPurple),
                              onPressed: () => _showRequestViewDialog(context, request),
                            ),
                          ),
                        );

                        if (request['documentWordPath'] != null) {
                          buttons.add(
                            Tooltip(
                              message: 'Open Word Document',
                              child: IconButton(
                                icon: const Icon(Icons.description, color: Colors.blue),
                                onPressed: () async {
                                  try {
                                    await OpenFile.open(request['documentWordPath']);
                                  } catch (e) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('Error opening Word: $e')),
                                    );
                                  }
                                },
                              ),
                            ),
                          );
                        }

                        if (request['documentPdfPath'] != null) {
                          buttons.add(
                            Tooltip(
                              message: 'Open PDF Document',
                              child: IconButton(
                                icon: const Icon(Icons.picture_as_pdf, color: Colors.red),
                                onPressed: () async {
                                  try {
                                    await OpenFile.open(request['documentPdfPath']);
                                  } catch (e) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('Error opening PDF: $e')),
                                    );
                                  }
                                },
                              ),
                            ),
                          );
                        }

                        actionsCell = Row(
                          mainAxisSize: MainAxisSize.min,
                          children: buttons,
                        );

                        return DataRow(
                          cells: [
                            DataCell(
                              Checkbox(
                                value: selectedRequests.contains(key),
                                onChanged: (bool? value) {
                                  final newSelected =
                                      Set<String>.from(selectedRequests);
                                  if (value == true) {
                                    newSelected.add(key);
                                  } else {
                                    newSelected.remove(key);
                                  }
                                  onSelectedRequestsChanged(newSelected);
                                },
                              ),
                            ),
                            DataCell(
                              Builder(builder: (context) {
                                final String rawName = request['fullName'] ?? "N/A";
                                final String formattedName = _formatResidentName(rawName);
                                final String userRole = request['userRole'] ?? "user";
                                
                                final bool isOffline = userRole == 'admin' || request['source'] == 'offline';

                                if (isOffline) {
                                  return RichText(
                                    text: TextSpan(
                                      style: DefaultTextStyle.of(context).style,
                                      children: [
                                        TextSpan(text: '$formattedName '),
                                        const TextSpan(
                                          text: '(Offline)',
                                          style: TextStyle(
                                            color: Colors.blue,
                                            fontWeight: FontWeight.bold,
                                            fontStyle: FontStyle.italic,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                } else {
                                  return Text(formattedName, style: const TextStyle(fontWeight: FontWeight.w500));
                                }
                              }),
                            ),
                            DataCell(Text(safeTitle)),
                            DataCell(statusCell),
                            DataCell(actionsCell),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}