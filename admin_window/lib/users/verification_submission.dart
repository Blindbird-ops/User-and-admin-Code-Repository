// lib/users/verification_submission.dart

class VerificationSubmission {
  final String id;                    // Usually the user's UID in your current setup
  final String status;                // pending, approved, rejected, etc.
  final String? idType;
  final String? idImageUrl;
  final String? selfieImageUrl;
  final String? rejectionReason;
  final Map<String, dynamic> fields;  // dynamic fields (Passport Number, Expiration Date, etc.)
  final List<String> supportingDocUrls;
  final String? submittedAt;          // ISO string (optional, but useful)

  const VerificationSubmission({
    required this.id,
    required this.status,
    this.idType,
    this.idImageUrl,
    this.selfieImageUrl,
    this.rejectionReason,
    this.fields = const {},
    this.supportingDocUrls = const [],
    this.submittedAt,
  });

  factory VerificationSubmission.fromJson(String id, Map<String, dynamic> json) {
    // 1) Preferred: nested 'fields' map (new structure)
    Map<String, dynamic> parsedFields = {};
    final dynamic nestedFields = json['fields'];
    if (nestedFields is Map) {
      parsedFields = nestedFields.map((k, v) => MapEntry(k.toString(), v));
    } else {
      // 2) Backward-compat: flattening fallback (old structure)
      //    Take all keys except the known ones
      final remaining = Map<String, dynamic>.from(json);
      final knownKeys = <String>{
        'status',
        'idType',
        'idImageUrl',
        'selfieImageUrl',
        'rejectionReason',
        'submittedAt',
        'userId',
        'fields',              // ignore container key if present
        'supportingDocUrls',   // ignore list holder
      };
      remaining.removeWhere((k, _) => knownKeys.contains(k));
      parsedFields = remaining;
    }

    // supportingDocUrls list
    final List<String> docs = [];
    final sd = json['supportingDocUrls'];
    if (sd is List) {
      for (final e in sd) {
        if (e is String && e.isNotEmpty) docs.add(e);
      }
    }

    return VerificationSubmission(
      id: id,
      status: (json['status'] ?? 'unknown').toString(),
      idType: json['idType'] as String?,
      idImageUrl: json['idImageUrl'] as String?,
      selfieImageUrl: json['selfieImageUrl'] as String?,
      rejectionReason: json['rejectionReason'] as String?,
      fields: parsedFields,
      supportingDocUrls: docs,
      submittedAt: json['submittedAt'] as String?,
    );
  }
}