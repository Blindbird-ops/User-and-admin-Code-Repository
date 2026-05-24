// lib/users/non_verified_user.dart
class NonVerifiedUser {
  final String id;
  final String fullName;
  final String email;
  final String? phoneNumber; // <--- NEW FIELD
  final String? username;
  
  // Address components
  final String? street;
  final String? barangay;
  final String? municipality;
  final String? province;

  // Additional user fields
  final String? title;
  final String? firstName;
  final String? middleName;
  final String? lastName;
  final String? role;
  final String? birthdate;
  final String? sex;
  final String? createdAt;

  NonVerifiedUser({
    required this.id,
    required this.fullName,
    required this.email,
    this.phoneNumber, // <--- Add to Constructor
    this.username,
    this.street,
    this.barangay,
    this.municipality,
    this.province,
    this.title,
    this.firstName,
    this.middleName,
    this.lastName,
    this.role,
    this.birthdate,
    this.sex,
    this.createdAt,
  });

  factory NonVerifiedUser.fromJson(String id, Map<String, dynamic> json) {
    return NonVerifiedUser(
      id: id,
      fullName: json['fullName'] as String? ?? 'N/A',
      email: json['email'] as String? ?? '', // Changed default to empty string so we can check isEmpty
      phoneNumber: json['phoneNumber'] as String?, // <--- Load from JSON
      username: json['username'] as String?,
      
      // Address components
      street: json['address'] as String?, 
      barangay: json['barangay'] as String?,
      municipality: json['municipality'] as String?,
      province: json['province'] as String?,
      
      // Additional fields
      title: json['title'] as String?,
      firstName: json['firstName'] as String?,
      middleName: json['middleName'] as String?,
      lastName: json['lastName'] as String?,
      role: json['role'] as String?,
      birthdate: json['birthdate'] as String?,
      sex: json['sex'] as String?,
      createdAt: json['createdAt'] as String?,
    );
  }

  String get fullAddress {
    final parts = [
      street,
      barangay,
      municipality,
      province,
    ].where((part) => part != null && part.isNotEmpty).toList();

    if (parts.isEmpty) {
      return 'N/A';
    }
    
    return parts.join(', ');
  }
}