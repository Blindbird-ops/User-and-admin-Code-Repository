import 'dart:convert';

import 'package:http/http.dart' as http;

class FirebaseService {
  // --- CORRECTED API KEY ---
  final String apiKey = "AIzaSyBEXIpHtv3PgYCy0FTV_eY79oCioBkecsQ"; 
  // --- END CORRECTION ---
  
  final String databaseUrl = "https://mabskie-47c24-default-rtdb.firebaseio.com";

  // =======================================================================
  // AUTHENTICATION AND REGISTRATION
  // =======================================================================

  /// Signs up a new user (admin) and sends a verification email.
  Future<String?> signUp({
    required String email,
    required String username,
    required String firstName,
    String? middleName,
    required String lastName,
    required String address,
    required String password,
    required String role,
    String? adminToken, // Add this optional parameter
  }) async {
    final url = "https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=$apiKey";
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

      final responseData = json.decode(response.body);
      if (response.statusCode == 200) {
        String? idToken = responseData["idToken"];
        String userId = responseData["localId"];
        final String tokenForDbWrite = adminToken ?? idToken!;
        
        // This will now throw a specific error if storing data fails.
        await storeUserData(
          userId,
          email,
          username: username,
          firstName: firstName,
          middleName: middleName,
          lastName: lastName,
          address: address,
          role: role,
          token: tokenForDbWrite, // Use the correct token here
        );



        return idToken;
      } else {
        throw Exception("Auth Signup failed: ${responseData['error']['message']}");
      }
    } catch (e) {
      throw Exception("Sign Up failed: $e");
    }
  }

  /// (Private) Sends an email verification link to the newly created user.

  /// Signs in an admin user.
  Future<String?> signIn(String email, String password) async {
    final url = "https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=$apiKey";
    try {
      final response = await http.post(
        Uri.parse(url),
        headers: {"Content-Type": "application/json"},
        body: json.encode({
          "email": email.trim(),
          "password": password.trim(),
          "returnSecureToken": true,
        }),
      );
      final responseData = json.decode(response.body);
      if (response.statusCode == 200) {
        return responseData["idToken"];
      } else {
        throw Exception("Login failed: ${responseData['error']['message']}");
      }
    } catch (e) {
      throw Exception("Login failed: $e");
    }
  }

  // =======================================================================
  // DATABASE METHODS
  // =======================================================================

  /// Stores user data in the Realtime Database.
  Future<void> storeUserData(
    String userId,
    String email, {
    required String username,
    required String firstName,
    required String lastName,
    String? middleName,
    required String address,
    String role = 'user',
    required String token,
  }) async {
    final url = "$databaseUrl/users/$userId.json?auth=$token";
    final userData = {
      "email": email,
      "username": username,
      "firstName": firstName,
      "lastName": lastName,
      if (middleName != null && middleName.isNotEmpty) "middleName": middleName,
      "address": address,
      "role": role,
      "isVerified": role == 'admin', // Admins are auto-verified
      "createdAt": DateTime.now().toIso8601String(),
    };
    
    try {
      final response = await http.put(
        Uri.parse(url),
        headers: {"Content-Type": "application/json"},
        body: json.encode(userData)
      );

      if (response.statusCode != 200) {
        final responseData = json.decode(response.body);
        throw Exception("Failed to store user data in database: ${responseData['error']}");
      }
    } catch (e) {
      throw Exception(e.toString());
    }
  }

  /// Fetches a user's complete profile data from the database.
  Future<Map<String, dynamic>?> fetchUserData(String token) async {
    final url = "https://identitytoolkit.googleapis.com/v1/accounts:lookup?key=$apiKey";
    try {
      final response = await http.post(
        Uri.parse(url),
        headers: {"Content-Type": "application/json"},
        body: json.encode({"idToken": token}),
      );
      final responseData = json.decode(response.body);
      if (response.statusCode == 200) {
        String userId = responseData['users'][0]['localId'];
        final userDataUrl = "$databaseUrl/users/$userId.json?auth=$token";
        final userResponse = await http.get(Uri.parse(userDataUrl));
        
        if (userResponse.statusCode != 200 || userResponse.body == 'null') {
            return null;
        }

        Map<String, dynamic>? userData = json.decode(userResponse.body);
        if (userData != null) {
          userData["uid"] = userId;
        }
        return userData;
      }
      return null;
    } catch (e) {
      print("Failed to fetch user data: $e");
      return null;
    }
  }


  // ... inside FirebaseService class ...

  // =======================================================================
  // ORG CHART METHODS
  // =======================================================================

  /// Fetches the organizational chart data
  Future<Map<String, dynamic>> fetchOrgChart(String token) async {
    final url = "$databaseUrl/org_chart.json?auth=$token";
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200 && response.body != 'null') {
        return json.decode(response.body);
      }
      return {};
    } catch (e) {
      print("Error fetching org chart: $e");
      return {};
    }
  }

  /// Updates a specific official's data in the org chart
  Future<void> updateOrgChartOfficial(String token, String id, Map<String, String> data) async {
    final url = "$databaseUrl/org_chart/$id.json?auth=$token";
    print("DEBUG: Writing to $url"); // <--- ADD THIS
    print("DEBUG: Data: $data");     // <--- ADD THIS
    
    try {
      final response = await http.patch(
        Uri.parse(url),
        headers: {"Content-Type": "application/json"},
        body: json.encode(data),
      );
      print("DEBUG: Response Code: ${response.statusCode}"); // <--- ADD THIS
      print("DEBUG: Response Body: ${response.body}");       // <--- ADD THIS
    } catch (e) {
      throw Exception("Failed to update official: $e");
    }
  }

 Future<Map<String, dynamic>?> fetchOrgChartLogos(String token) async {
    final url = "$databaseUrl/org_chart/logos.json?auth=$token";
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200 && response.body != 'null') {
        return json.decode(response.body);
      }
    } catch (e) {
      print("Error fetching logos: $e");
    }
    return null;
  }

  /// Updates a specific logo (left or right) in the org chart
  Future<void> updateOrgChartLogo(String token, String key, String imageUrl) async {
    final url = "$databaseUrl/org_chart/logos.json?auth=$token";
    try {
      await http.patch(
        Uri.parse(url),
        headers: {"Content-Type": "application/json"},
        body: json.encode({key: imageUrl}),
      );
    } catch (e) {
      print("Error updating logo: $e");
      rethrow;
    }
  }
  // =======================================================================
  // LOGGING AND OTHER ADMIN METHODS
  // =======================================================================

  Future<void> recordLog(String token, String message, {String role = 'user'}) async {
    final url = "$databaseUrl/logs.json?auth=$token";
    final timestamp = DateTime.now().toIso8601String();
    try {
      await http.post(
        Uri.parse(url),
        headers: {"Content-Type": "application/json"},
        body: json.encode({"timestamp": timestamp, "message": message, "role": role}),
      );
    } catch (e) {
      print("Failed to record log: $e");
    }
  }

  Future<void> recordAdminLog(String token, String message, String actorEmail) async {
    final url = "$databaseUrl/logs.json?auth=$token";
    final timestamp = DateTime.now().toIso8601String();
    
    final logData = {
      "timestamp": timestamp,
      "message": message,
      "actor": actorEmail,
      "role": "admin"
    };

    try {
      await http.post(
        Uri.parse(url),
        headers: {"Content-Type": "application/json"},
        body: json.encode(logData),
      );
    } catch (e) {
      print("An error occurred while recording admin log: $e");
    }
  }

  Future<void> cleanOldLogs(String token) async {
    // Intentionally left blank to keep all logs permanently.
  }
  Future<Map<String, dynamic>?> fetchVerificationSubmissions(String token) async {
    final url = "$databaseUrl/verificationSubmissions.json?auth=$token";
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        if (response.body == 'null') return {};
        return json.decode(response.body);
      } else {
        throw Exception('Could not fetch verification submissions.');
      }
    } catch (e) {
      throw Exception("An error occurred while fetching submissions: $e");
    }
  }

  Future<void> processVerification(String token, String userId, bool isApproved) async {
    final updates = {
      "users/$userId/isVerified": isApproved,
      "verificationSubmissions/$userId/status": isApproved ? 'approved' : 'rejected',
      "verificationSubmissions/$userId/processedAt": DateTime.now().toIso8601String(),
    };
    final url = "$databaseUrl/.json?auth=$token";
    try {
      final response = await http.patch(Uri.parse(url), body: json.encode(updates));
      if (response.statusCode != 200) {
        throw Exception('Failed to process verification.');
      }
    } catch (e) {
      throw Exception("An error occurred while processing verification: $e");
    }
  }
}