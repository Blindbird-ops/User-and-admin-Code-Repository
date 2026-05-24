// lib/users/verified_user.dart
class VerifiedUser {
  final String id;
  final String fullName;
  final String email;
  final String? phoneNumber; // <--- NEW
  final String? username;
  
  // Address components
  final String? street;
  final String? barangay;
  final String? municipality;
  final String? province;
  final String? createdAt;

  VerifiedUser({
    required this.id,
    required this.fullName,
    required this.email,
    this.phoneNumber, // <--- NEW
    this.username,
    this.street,
    this.barangay,
    this.municipality,
    this.province,
    this.createdAt,
  });

  factory VerifiedUser.fromJson(String id, Map<String, dynamic> json) {
    return VerifiedUser(
      id: id,
      fullName: json['fullName'] as String? ?? 'N/A',
      email: json['email'] as String? ?? '', // Empty string to check easily
      phoneNumber: json['phoneNumber'] as String?, // <--- NEW
      username: json['username'] as String?,
      street: json['address'] as String?,
      barangay: json['barangay'] as String?,
      municipality: json['municipality'] as String?,
      province: json['province'] as String?,
      createdAt: json['createdAt'] as String?,
    );
  }

  String get fullAddress {
    final parts = [street, barangay, municipality, province]
        .where((part) => part != null && part.isNotEmpty)
        .toList();
    return parts.isEmpty ? 'N/A' : parts.join(', ');
  }
}