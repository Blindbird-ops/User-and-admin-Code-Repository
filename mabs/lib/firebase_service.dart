import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:firebase_database/firebase_database.dart';
import 'package:http/http.dart' as http;
import 'package:cloudinary_public/cloudinary_public.dart';
// --- NEW IMPORTS ---
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart' as auth_sdk; // Alias to avoid conflicts

// Custom Exception Classes
class AuthException implements Exception {
  final String message;
  AuthException(this.message);
  @override
  String toString() => message;
}

class EmailNotFoundException extends AuthException {
  EmailNotFoundException() : super('No account found with this email address.');
}

class WrongPasswordException extends AuthException {
  WrongPasswordException() : super('Incorrect password. Please try again.');
}

class InvalidEmailException extends AuthException {
  InvalidEmailException() : super('The email address is not valid.');
}

class UserDisabledException extends AuthException {
  UserDisabledException() : super('This account has been disabled.');
}

class TooManyAttemptsException extends AuthException {
  TooManyAttemptsException() : super('Too many failed login attempts. Please try again later.');
}

class NetworkException extends AuthException {
  NetworkException() : super('Network error. Please check your connection and try again.');
}

class SignUpResult {
  final String token;
  final String uid;
  SignUpResult(this.token, this.uid);
}

class AuthSession {
  final String idToken;
  final String refreshToken;
  final int expiresIn;
  final String uid;
  final String email;

  AuthSession({
    required this.idToken,
    required this.refreshToken,
    required this.expiresIn,
    required this.uid,
    required this.email,
  });
}

class FirebaseService {
  final String apiKey = "AIzaSyAi5DWMZtLbC9XA218_2RdS1jZjF13kUoo";
  final String databaseUrl = "https://mabskie-47c24-default-rtdb.firebaseio.com/";
  final String continueUrl = "https://blindbird-ops.github.io/pularaquen";
  
  final CloudinaryPublic cloudinary = CloudinaryPublic(
    'dnufyw3my',
    'cloudinary',
    cache: false,
  );

  // --- NEW: Cloud Functions & Auth Instance ---
  final FirebaseFunctions functions = FirebaseFunctions.instance;
  final auth_sdk.FirebaseAuth _authSdk = auth_sdk.FirebaseAuth.instance;

  // ==========================================
  // 1. NEW: EMAIL OTP LOGIC (Talks to your new Backend)
  // ==========================================

  // --- ADD YOUR CLOUD FUNCTION URLs HERE ---
  final String sendOtpUrl = "https://sendemailotp-wxghgf7viq-uc.a.run.app";
  final String verifyOtpUrl = "https://verifyemailotp-wxghgf7viq-uc.a.run.app";

  Future<void> sendEmailOTP(String email, String username) async {
    if (email.isEmpty) throw AuthException("Cannot send OTP: Email is empty.");
    
    try {
      // USING THE ADMIN HTTP LOGIC
      final response = await http.post(
        Uri.parse(sendOtpUrl),
        headers: {"Content-Type": "application/json"},
        body: json.encode({
          "data": {
            "email": email.trim().toLowerCase(), // Force clean email
            "username": username,
          }
        }),
      );

      final responseData = json.decode(response.body);

      // Check for errors returned by the Cloud Function
      if (response.statusCode != 200 || responseData['error'] != null) {
         String msg = responseData['error']?['message'] ?? "Unknown error occurred.";
         print("Warning: Cloud function reported failure: $msg");
         throw AuthException(msg);
      }
    } catch (e) {
      if (e is AuthException) rethrow;
      throw AuthException('An unexpected error occurred sending OTP: $e');
    }
  }

  
  Future<void> verifyEmailOTP(String email, String code, String? uid) async {
    try {
      // USING THE ADMIN HTTP LOGIC
      final response = await http.post(
        Uri.parse(verifyOtpUrl),
        headers: {"Content-Type": "application/json"},
        body: json.encode({
          "data": {
            "email": email.trim().toLowerCase(), // Force clean email
            "code": code,
            "uid": uid, // Automatically passes null if it's a password reset
          }
        }),
      );

      final responseData = json.decode(response.body);

      // If successful, error will be null
      if (response.statusCode == 200 && responseData['error'] == null) {
        return; // Success!
      } else {
        String msg = responseData['error']?['message'] ?? "Invalid Code";
        throw AuthException(msg); // This throws the exact error to your UI
      }
    } catch (e) {
      if (e is AuthException) rethrow;
      throw AuthException('An unexpected error occurred verifying OTP: $e');
    }
  }
  
  // NEW: Call the Password Reset Cloud Function
  Future<void> resetPasswordWithOtp(String email, String code, String newPassword) async {
    try {
      final HttpsCallable callable = functions.httpsCallable('resetPasswordWithOtp');
      await callable.call(<String, dynamic>{
        'email': email,
        'code': code,
        'newPassword': newPassword,
      });
    } on FirebaseFunctionsException catch (e) {
      throw AuthException(e.message ?? 'Failed to reset password.');
    } catch (e) {
      throw AuthException('An unexpected error occurred: $e');
    }
  }

    // NEW: Validate OTP without resetting yet
  Future<void> validateOtp(String email, String code) async {
    try {
      final HttpsCallable callable = functions.httpsCallable('validateOtp');
      await callable.call(<String, dynamic>{'email': email, 'code': code});
    } on FirebaseFunctionsException catch (e) {
      throw AuthException(e.message ?? 'Invalid Code');
    } catch (e) {
      throw AuthException('Error validating OTP: $e');
    }
  }

    // NEW: Check phone existence via Cloud Function
  Future<bool> checkPhoneExists(String phoneNumber) async {
    try {
      final HttpsCallable callable = functions.httpsCallable('checkPhoneNumberExists');
      final result = await callable.call(<String, dynamic>{'phoneNumber': phoneNumber});
      return result.data['exists'] == true;
    } catch (e) {
      // If error (e.g. network), assume false to be safe, or rethrow
      print("Check Phone Error: $e");
      return false;
    }
  }
  // ==========================================
  // 2. NEW: PHONE AUTH SAVE LOGIC
  // ==========================================
  Future<SignUpResult> savePhoneUser({
    required String uid,
    required String phoneNumber,
    required String username,
    required String title,
    required String firstName,
    required String middleName,
    required String lastName,
    required String street,
    required String role,
    String? birthdate,
    String? sex,
    String? province,
    String? municipality,
    String? barangay,
  }) async {
    try {
      final token = await _authSdk.currentUser?.getIdToken();
      if (token == null) throw AuthException("Authentication failed");

      await storeUserData(
        uid: uid,
        email: "", // Empty for phone users
        username: username,
        title: title,
        firstName: firstName,
        middleName: middleName,
        lastName: lastName,
        address: street,
        role: role,
        token: token,
        birthdate: birthdate,
        sex: sex,
        province: province,
        municipality: municipality,
        barangay: barangay,
        verified: false, // Phone is auto-verified via SMS
        phoneNumber: phoneNumber,
      );

      return SignUpResult(token, uid);
    } catch (e) {
      throw AuthException("Failed to save phone user: $e");
    }
  }

  // ==========================================
  // 3. UPDATED: SIGN UP (Uses Email OTP now)
  // ==========================================
  Future<SignUpResult?> signUp({
    required String email,
    required String username,
    required String title,
    required String firstName,
    String? middleName,
    required String lastName,
    required String street,
    required String password,
    required String role,
    String? birthdate,
    String? sex,
    String? province,
    String? municipality,
    String? barangay,
  }) async {
    const signUpUrl = "https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=";
    final url = "$signUpUrl$apiKey";
    try {
      final response = await http.post(
        Uri.parse(url),
        headers: {"Content-Type": "application/json"},
        body: json.encode({
          "email": email,
          "password": password,
          "returnSecureToken": true,
        }),
      );
      final data = json.decode(response.body);
      if (response.statusCode != 200) {
        final errorMessage = data['error']?['message'] ?? 'Unknown error';
        _throwAppropriateException(errorMessage);
      }
      final token = data['idToken'] as String;
      final uid = data['localId'] as String;

      // Store data (Verified = false initially)
      await storeUserData(
        uid: uid,
        email: email,
        username: username,
        title: title,
        firstName: firstName,
        middleName: middleName,
        lastName: lastName,
        address: street,
        role: role,
        token: token,
        birthdate: birthdate,
        sex: sex,
        province: province,
        municipality: municipality,
        barangay: barangay,
        verified: false, 
      );



      return SignUpResult(token, uid);
    } on SocketException {
      throw NetworkException();
    } on AuthException {
      rethrow;
    } catch (e) {
      throw AuthException('SignUp failed: $e');
    }
  }

  // ==========================================
  // 4. UPDATED: STORE USER DATA (Added phoneNumber support)
  // ==========================================
  Future<void> storeUserData({
    required String uid,
    required String email,
    required String username,
    required String title,
    required String firstName,
    String? middleName,
    required String lastName,
    required String address,
    required String role,
    required String token,
    String? birthdate,
    String? sex,
    String? province,
    String? municipality,
    String? barangay,
    bool verified = false,
    String? phoneNumber, // Added
  }) async {
    final url = "$databaseUrl/users/$uid.json?auth=$token";
    final fullName = [
      title,
      firstName,
      if (middleName?.isNotEmpty == true) middleName!,
      lastName,
    ].join(' ');
    try {
      final response = await http.put(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'email':      email,
          'phoneNumber': phoneNumber, // Added
          'username':   username,
          'title':      title,
          'firstName':  firstName,
          'middleName': middleName,
          'lastName':   lastName,
          'fullName':   fullName,
          'address':    address,
          'role':       role,
          if (birthdate   != null) 'birthdate':   birthdate,
          if (sex         != null) 'sex':         sex,
          if (province    != null) 'province':    province,
          if (municipality!= null) 'municipality':municipality,
          if (barangay    != null) 'barangay':    barangay,
          'isVerified':   verified,
          'createdAt':  DateTime.now().toIso8601String(),
        }),
      );
      if (response.statusCode != 200) {
        throw AuthException('Failed to store user data');
      }
    } on SocketException {
      throw NetworkException();
    } catch (e) {
      if (e is AuthException) rethrow;
      throw AuthException('Failed to store user data: $e');
    }
  }

  // --- EXISTING METHODS (Kept exactly as you had them) ---

  Future<Map<String, dynamic>?> fetchMyVerificationSubmission(String userId, String token) async {
    final url = "${databaseUrl}verificationSubmissions/$userId.json?auth=$token";
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode >= 400) return null;
      if (response.body == 'null') return null;
      return json.decode(response.body) as Map<String, dynamic>;
    } on SocketException {
      throw NetworkException();
    } catch (e) {
      throw AuthException('Error fetching submission status: $e');
    }
  }

  Future<void> deleteMyVerificationSubmission(String userId, String token) async {
    final url = "${databaseUrl}verificationSubmissions/$userId.json?auth=$token";
    try {
      await http.delete(Uri.parse(url));
    } catch (e) {
      // Ignore errors for delete
    }
  }

  // --- THIS IS THE CORRECTED FUNCTION ---
  Future<void> submitComplaint({
    required String token,
    required String uid,
    required String email,
    required String complainantName,
    required String complaintAgainst,
    required String subject,
    required String complaintDetails,
  }) async {
    final dbRef = FirebaseDatabase.instance.ref();
    
    // 1. Generate a unique ID for the complaint under the 'complaints' node
    final requestId = dbRef.child('complaints').push().key;

    if (requestId == null) {
      throw AuthException("Could not generate a unique ID for the complaint.");
    }

    final int clientTimestampMs = DateTime.now().millisecondsSinceEpoch;
    final String isoTimestamp = DateTime.now().toIso8601String();

    // 2. Create the data payload.
    // Notice we include BOTH 'fullName' and 'complainantName' 
    // so it doesn't break your User History OR your Admin Panel.
    final Map<String, dynamic> complaintData = {
      'userId': uid,
      'userEmail': email,
      'requestId': requestId,
      'fullName': complainantName,        // Expected by User Requests JSON
      'complainantName': complainantName, // Expected by Complaints JSON
      'complaintAgainst': complaintAgainst,
      'subject': subject,
      'message': complaintDetails, 
      'documentType': 'Complaint', 
      'title': 'Complaint',      
      'status': 'Pending',
      'timestamp': clientTimestampMs, // Using Integer timestamp for better sorting
      'statusHistory': {
        clientTimestampMs.toString(): {
          'stage': 'Pending',
          'remarks': 'Complaint submitted by resident.',
          'timestamp': isoTimestamp,
        }
      }
    };

    try {
      // 3. THE FIX: Update BOTH locations simultaneously.
      // Now it goes to 'complaints' for admins, and 'users/uid/requests' for the daily limit check!
      final Map<String, dynamic> multiPathUpdate = {
        'complaints/$requestId': complaintData,
        'users/$uid/requests/$requestId': complaintData,
      };

      await dbRef.update(multiPathUpdate);
      
    } on SocketException {
      throw NetworkException();
    } catch (e) {
      throw AuthException('An unexpected error occurred while submitting the complaint: $e');
    }
  }
  
  Future<AuthSession> signInWithTokens(String email, String password) async {
    final url = "https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=$apiKey";
    try {
      final response = await http.post(
        Uri.parse(url),
        headers: {"Content-Type": "application/json"},
        body: json.encode({
          'email': email,
          'password': password,
          'returnSecureToken': true,
        }),
      );
      final data = json.decode(response.body);
      if (response.statusCode != 200) {
        final errorMessage = data['error']?['message'] ?? 'Unknown error';
        _throwAppropriateException(errorMessage);
      }
      return AuthSession(
        idToken: data['idToken'],
        refreshToken: data['refreshToken'],
        expiresIn: int.tryParse(data['expiresIn']?.toString() ?? '3600') ?? 3600,
        uid: data['localId'],
        email: data['email'] ?? email,
      );
    } on SocketException {
      throw NetworkException();
    } on AuthException {
      rethrow;
    } catch (e) {
      throw AuthException('SignIn failed: $e');
    }
  }

  Future<AuthSession> refreshIdTokenFull(String refreshToken) async {
    final url = "https://securetoken.googleapis.com/v1/token?key=$apiKey";
    try {
      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'grant_type': 'refresh_token',
          'refresh_token': refreshToken,
        }),
      );
      final data = json.decode(response.body);
      if (response.statusCode != 200) throw AuthException('Failed to refresh token');
      return AuthSession(
        idToken: data['id_token'],
        refreshToken: data['refresh_token'],
        expiresIn: int.tryParse(data['expires_in']?.toString() ?? '3600') ?? 3600,
        uid: data['user_id'] ?? '',
        email: '',
      );
    } catch (e) {
      throw AuthException('Failed to refresh token: $e');
    }
  }

  Future<void> updateUserProfileFields({
    required String uid,
    required String token,
    required Map<String, dynamic> fields,
  }) async {
    final url = "$databaseUrl/users/$uid.json?auth=$token";
    await http.patch(
      Uri.parse(url),
      headers: {'Content-Type': 'application/json'},
      body: json.encode(fields),
    );
  }

  Future<void> saveVerificationData({
    required String token,
    required String uid,
    required String? idType,
    required Map<String, dynamic> fields,
    required String? idImageUrl,
    required String? selfieImageUrl,
    List<String> supportingDocUrls = const [],
  }) async {
    final submissionData = {
      'idType': idType,
      'fields': fields,
      'idImageUrl': idImageUrl ?? 'not_provided',
      'selfieImageUrl': selfieImageUrl ?? 'not_provided',
      if (supportingDocUrls.isNotEmpty) 'supportingDocUrls': supportingDocUrls,
      'status': 'pending',
      'submittedAt': DateTime.now().toIso8601String(),
      'userId': uid,
    };
    final url = "$databaseUrl/verificationSubmissions/$uid.json?auth=$token";
    await http.put(
      Uri.parse(url),
      headers: {'Content-Type': 'application/json'},
      body: json.encode(submissionData),
    );
  }

  Future<void> updateUserProfilePicture({
    required String uid,
    required String token,
    required String imageUrl,
  }) async {
    final url = "$databaseUrl/users/$uid.json?auth=$token";
    await http.patch(
      Uri.parse(url),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'profilePictureUrl': imageUrl}),
    );
  }

  Future<void> updateUserVerificationStatus(String uid, String token) async {
    final url = "$databaseUrl/users/$uid.json?auth=$token";
    await http.patch(
      Uri.parse(url),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'isVerified': true,
        'verifiedAt': DateTime.now().toIso8601String(),
      }),
    );
  }

  Future<String?> signIn(String email, String password) async {
    final url = "https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=$apiKey";
    try {
      final response = await http.post(
        Uri.parse(url),
        headers: {"Content-Type": "application/json"},
        body: json.encode({
          'email': email,
          'password': password,
          'returnSecureToken': true,
        }),
      );
      final data = json.decode(response.body);
      if (response.statusCode == 200 && data['idToken'] != null) {
        return data['idToken'] as String;
      }
      return null;
    } catch (e) {
      throw AuthException('SignIn failed: $e');
    }
  }

  void _throwAppropriateException(String errorMessage) {
    switch (errorMessage) {
      case 'EMAIL_NOT_FOUND': throw EmailNotFoundException();
      case 'INVALID_PASSWORD': throw WrongPasswordException();
      case 'INVALID_LOGIN_CREDENTIALS': throw AuthException('Invalid email or password.');
      case 'USER_DISABLED': throw UserDisabledException();
      case 'TOO_MANY_ATTEMPTS_TRY_LATER': throw TooManyAttemptsException();
      case 'INVALID_EMAIL': throw InvalidEmailException();
      case 'EMAIL_EXISTS': throw AuthException('An account with this email already exists.');
      default: throw AuthException(errorMessage);
    }
  }

  Future<Map<String, dynamic>?> fetchUserData(String token) async {
    const lookupUrl = "https://identitytoolkit.googleapis.com/v1/accounts:lookup?key=";
    final url = "$lookupUrl$apiKey";
    
    // Simple retry mechanism (3 attempts)
    for (int i = 0; i < 3; i++) {
      try {
        final resp = await http.post(
          Uri.parse(url),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({'idToken': token}),
        ).timeout(const Duration(seconds: 10)); // Added timeout

        if (resp.statusCode != 200) {
           // If token is expired, don't retry, just fail
           if (resp.body.contains("INVALID_ID_TOKEN")) return null;
           continue; // Retry other errors
        }

        final lookup = json.decode(resp.body);
        if (lookup['users'] != null && lookup['users'].isNotEmpty) {
          final uid = lookup['users'][0]['localId'] as String;
          
          // Now fetch profile from RTDB
          final userUrl = "$databaseUrl/users/$uid.json?auth=$token";
          final userResp = await http.get(Uri.parse(userUrl)).timeout(const Duration(seconds: 10));
          
          if (userResp.statusCode == 200 && userResp.body != 'null') {
            final profile = json.decode(userResp.body) as Map<String, dynamic>;
            profile['uid'] = uid; // Ensure UID is attached
            return profile;
          }
        }
        return null; // User not found
      } on SocketException {
        // Network error, wait and retry
        await Future.delayed(const Duration(seconds: 1));
      } on TimeoutException {
        // Timeout, wait and retry
        await Future.delayed(const Duration(seconds: 1));
      } catch (e) {
        // Unknown error, fail immediately to avoid loop
        print("Fetch User Data Error: $e");
        return null; 
      }
    }
    // If all retries fail
    throw NetworkException(); 
  }

  Future<void> recordLog(String token, String message, {String role = 'user'}) async {
    final url = "$databaseUrl/logs.json?auth=$token";
    final timestamp = DateTime.now().toIso8601String();
    await http.post(
      Uri.parse(url),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'timestamp': timestamp, 'message': message, 'role': role}),
    );
  }

  Future<void> cleanOldLogs(String token) async {
    // Keep logic
  }

  Future<void> sendPasswordResetEmail(String email) async {
    final url = "https://identitytoolkit.googleapis.com/v1/accounts:sendOobCode?key=$apiKey";
    await http.post(
      Uri.parse(url),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'requestType': 'PASSWORD_RESET', 'email': email}),
    );
  }

  // NOTE: _sendEmailVerification is removed because we use OTP now.
  // We keep the isEmailVerified helper, but verify against the DB in OTP logic.
  Future<bool> isEmailVerified(String idToken) async {
    final lookupUrl = 'https://identitytoolkit.googleapis.com/v1/accounts:lookup?key=$apiKey';
    try {
      final resp = await http.post(
        Uri.parse(lookupUrl),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'idToken': idToken}),
      );
      if (resp.statusCode != 200) return false;
      final data = json.decode(resp.body);
      final users = data['users'] as List<dynamic>?;
      return users != null && users.first['emailVerified'] == true;
    } catch (e) {
      return false;
    }
  }

  Future<void> resendVerification(String idToken) async {
    // Replaced by sendEmailOTP in UI
  }

  // Add this inside FirebaseService class
  Future<void> deleteUnverifiedAccount(String uid, String token) async {
    try {
      // 1. Delete from Realtime Database
      final dbUrl = "$databaseUrl/users/$uid.json?auth=$token";
      await http.delete(Uri.parse(dbUrl));

      // 2. Delete from Firebase Authentication
      final authUrl = "https://identitytoolkit.googleapis.com/v1/accounts:delete?key=$apiKey";
      await http.post(
        Uri.parse(authUrl),
        headers: {"Content-Type": "application/json"},
        body: json.encode({"idToken": token}),
      );
    } catch (e) {
      print("Failed to delete unverified account: $e");
    }
  }

  Future<String?> refreshToken(String refreshToken) async {
    final url = "https://securetoken.googleapis.com/v1/token?key=$apiKey";
    final response = await http.post(
      Uri.parse(url),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'grant_type': 'refresh_token', 'refresh_token': refreshToken}),
    );
    if (response.statusCode == 200) {
      return json.decode(response.body)['id_token'];
    }
    return null;
  }
}