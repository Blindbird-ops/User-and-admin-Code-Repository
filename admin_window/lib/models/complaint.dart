// admin_window/models/complaint.dart

class Complaint {
  final String id;
  final String subject;
  final String message; 
  final String complainantEmail;
  final String? complainantName;
  final String? complaintAgainst;
  final String? complaintDetails;
  final String status;
  final DateTime timestamp;
  final String? userId; // Important for mirroring back to the user
  
  // --- NEW FIELDS FOR DOCUMENT GENERATION ---
  final String? generationStatus;
  final String? documentPdfPath;
  final String? documentWordPath;

  Complaint({
    required this.id,
    required this.subject,
    required this.message,
    required this.complainantEmail,
    this.complainantName,
    this.complaintAgainst,
    this.complaintDetails,
    required this.status,
    required this.timestamp,
    this.userId,
    // --- Initialize new fields ---
    this.generationStatus,
    this.documentPdfPath,
    this.documentWordPath,
  });

  factory Complaint.fromJson(String id, Map<dynamic, dynamic> json) {
    // Robust timestamp parser
    DateTime parseTs(dynamic v) {
      try {
        if (v == null) return DateTime.now();
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
        return DateTime.tryParse(s) ?? DateTime.now();
      } catch (_) {
        return DateTime.now();
      }
    }

    return Complaint(
      id: id,
      subject: json['subject'] ?? 'No Subject',
      // Map 'message' (from user app) or fallback
      message: json['message'] ?? json['complaintDetails'] ?? 'No message body.',
      // UPDATED: Look for 'userEmail' first (new format), then others
      complainantEmail: json['userEmail'] ?? json['email'] ?? json['complainantEmail'] ?? 'Unknown Email',
      complainantName: json['complainantName'] ?? json['fullName'],
      complaintAgainst: json['complaintAgainst'],
      complaintDetails: json['complaintDetails'],
      status: json['status'] ?? 'New',
      timestamp: parseTs(json['timestamp']),
      userId: json['userId'],
      
      // --- Map new fields from Firebase ---
      generationStatus: json['generationStatus'] as String?,
      documentPdfPath: json['documentPdfPath'] as String?,
      documentWordPath: json['documentWordPath'] as String?,
    );
  }
}