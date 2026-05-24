import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
// 1. IMPORT FIREBASE AUTH
import 'package:firebase_auth/firebase_auth.dart';

class DataService {
  static const String _base = 'https://mabskie-47c24-default-rtdb.firebaseio.com';
  static const String _authBase = 'https://identitytoolkit.googleapis.com/v1';
  static const String _apiKey = "AIzaSyAi5DWMZtLbC9XA218_2RdS1jZjF13kUoo";

  // REMOVED: final String token; 
  late final IOClient _client;

  // UPDATED CONSTRUCTOR: No token argument needed
  DataService() {
    final httpClient = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10)
      ..idleTimeout = const Duration(seconds: 10)
      ..maxConnectionsPerHost = 8; // be conservative on Windows
    _client = IOClient(httpClient);
  }

  void close() {
    _client.close();
  }

  // Check if user is logged in via Firebase Auth instance
  bool get isAuthenticated => FirebaseAuth.instance.currentUser != null;

  // --- NEW: Helper to get a fresh token automatically ---
  Future<String> _getFreshToken() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception("User is not authenticated (No Firebase User found).");
    }
    // forceRefresh: false -> Checks cache first, auto-refreshes if >1 hour old
    final token = await user.getIdToken(false);
    if (token == null) throw Exception("Failed to retrieve ID Token.");
    return token;
  }

  // Updated _buildUri to accept the token as an argument
  Uri _buildUri(String path, String token, {Map<String, String>? params}) {
    final clean = path.replaceAll(RegExp(r'^/+|/+$'), '');
    final qp = <String, String>{'auth': token, if (params != null) ...params};
    return Uri.parse('$_base/$clean.json').replace(queryParameters: qp);
  }

  // Updated _buildRootUri to accept the token as an argument
  Uri _buildRootUri(String token, {Map<String, String>? params}) {
    final qp = <String, String>{'auth': token, if (params != null) ...params};
    return Uri.parse('$_base/.json').replace(queryParameters: qp);
  }

  // Retry wrapper
  Future<T> _retry<T>(Future<T> Function() action, {int retries = 3}) async {
    int attempt = 0;
    var delay = const Duration(milliseconds: 500);
    while (true) {
      try {
        return await action();
      } on SocketException catch (_) {
        attempt++;
        if (attempt > retries) rethrow;
        await Future.delayed(delay);
        delay *= 2;
      } on TimeoutException catch (_) {
        attempt++;
        if (attempt > retries) rethrow;
        await Future.delayed(delay);
        delay *= 2;
      } on http.ClientException catch (_) {
        attempt++;
        if (attempt > retries) rethrow;
        await Future.delayed(delay);
        delay *= 2;
      } catch (e) {
        // Retry on token expiration errors if caught here
        if (e.toString().contains("Permission denied")) {
           // If we hit permission denied, it might be a weird edge case, 
           // but normally _getFreshToken handles it. We let it fail so the UI shows it.
           rethrow;
        }
        rethrow;
      }
    }
  }

  bool _permissionDeniedInResponse(http.Response r) {
    try {
      final body = r.body.trim();
      final lower = body.toLowerCase();

      if ((r.statusCode == 401 || r.statusCode == 403) && lower.contains('permission denied')) {
        return true;
      }

      if (r.statusCode == 200 && body.isNotEmpty && body != 'null') {
        final decoded = json.decode(body);
        if (decoded is Map &&
            decoded['error'] != null &&
            decoded['error'].toString().toLowerCase().contains('permission denied')) {
          return true;
        }
      }
    } catch (_) {}
    return false;
  }

  Map<String, String> get _jsonHeaders => const {
        'Content-Type': 'application/json',
        'Connection': 'close', 
      };

  Map<String, String> get _plainHeaders => const {
        'Connection': 'close',
      };

  // --- GET DATA ---
  Future<Map<String, dynamic>?> getData(String path, {Map<String, String>? params}) async {
    // 1. Get Token
    final token = await _getFreshToken();

    return _retry(() async {
      // 2. Pass Token to Builder
      final r = await _client
          .get(_buildUri(path, token, params: params), headers: _plainHeaders)
          .timeout(const Duration(seconds: 12));

      if (_permissionDeniedInResponse(r)) {
        throw Exception("Permission denied for $path");
      }

      if (r.statusCode == 200) {
        final body = r.body.trim();
        if (body == 'null' || body.isEmpty) return null;
        final decoded = json.decode(body);
        if (decoded is Map<String, dynamic>) return decoded;
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
        throw Exception("Expected Map at $path but got ${decoded.runtimeType}");
      } else {
        throw http.ClientException('HTTP ${r.statusCode}: ${r.body}');
      }
    });
  }

  // --- GET VALUE (Any Type) ---
  Future<Object?> getValue(String path, {Map<String, String>? params}) async {
    final token = await _getFreshToken();

    return _retry(() async {
      final r = await _client
          .get(_buildUri(path, token, params: params), headers: _plainHeaders)
          .timeout(const Duration(seconds: 12));

      if (_permissionDeniedInResponse(r)) {
        throw Exception("Permission denied for $path");
      }

      if (r.statusCode == 200) {
        final body = r.body.trim();
        if (body == 'null' || body.isEmpty) return null;
        return json.decode(body) as Object?;
      } else {
        throw http.ClientException('HTTP ${r.statusCode}: ${r.body}');
      }
    });
  }

  // --- UPDATE DATA ---
  Future<void> updateData(String path, Map<String, dynamic> data) async {
    final token = await _getFreshToken();

    await _retry(() async {
      final r = await _client
          .patch(_buildUri(path, token), headers: _jsonHeaders, body: json.encode(data))
          .timeout(const Duration(seconds: 12));

      if (_permissionDeniedInResponse(r)) {
        throw Exception("Permission denied for $path");
      }

      if (r.statusCode >= 200 && r.statusCode < 300) return;
      throw http.ClientException('HTTP ${r.statusCode}: ${r.body}');
    });
  }

  // --- ADD DATA (POST) ---
  Future<void> addData(String path, Map<String, dynamic> data) async {
    final token = await _getFreshToken();

    await _retry(() async {
      final r = await _client
          .post(_buildUri(path, token), headers: _jsonHeaders, body: json.encode(data))
          .timeout(const Duration(seconds: 12));

      if (_permissionDeniedInResponse(r)) {
        throw Exception("Permission denied for POST at $path");
      }

      if (r.statusCode >= 200 && r.statusCode < 300) return;
      throw http.ClientException('HTTP ${r.statusCode}: ${r.body}');
    });
  }

  // --- MULTI UPDATE ---
  Future<void> updateMulti(Map<String, dynamic> updates) async {
    final token = await _getFreshToken();

    await _retry(() async {
      final r = await _client
          .patch(_buildRootUri(token), headers: _jsonHeaders, body: json.encode(updates))
          .timeout(const Duration(seconds: 12));

      if (_permissionDeniedInResponse(r)) {
        throw Exception("Permission denied for root multi-update");
      }

      if (r.statusCode >= 200 && r.statusCode < 300) return;
      throw http.ClientException('HTTP ${r.statusCode}: ${r.body}');
    });
  }

  // --- DELETE DATA ---
  Future<void> deleteData(String path) async {
    final token = await _getFreshToken();

    await _retry(() async {
      final r = await _client
          .delete(_buildUri(path, token), headers: _plainHeaders)
          .timeout(const Duration(seconds: 12));

      if (_permissionDeniedInResponse(r)) {
        throw Exception("Permission denied for $path");
      }

      if (r.statusCode >= 200 && r.statusCode < 300) return;
      throw http.ClientException('HTTP ${r.statusCode}: ${r.body}');
    });
  }

  Future<void> updateUserRole(String userId, String newRole) async {
    final token = await _getFreshToken();

    await _retry(() async {
      final r = await _client
          .patch(
            _buildUri("users/$userId", token),
            headers: _jsonHeaders,
            body: json.encode({'role': newRole}),
          )
          .timeout(const Duration(seconds: 12));

      if (_permissionDeniedInResponse(r)) {
        throw Exception("Permission denied updating role for $userId");
      }

      if (r.statusCode >= 200 && r.statusCode < 300) return;
      throw http.ClientException('HTTP ${r.statusCode}: ${r.body}');
    });
  }

  // ==========================================================
  // AUTH HELPERS
  // ==========================================================
  
  Future<String?> getCurrentUserEmail() async {
    // Also use fresh token here to lookup account details
    final token = await _getFreshToken();
    final uri = Uri.parse('$_authBase/accounts:lookup?key=$_apiKey');
    
    return _retry(() async {
      final response = await _client.post(
        uri,
        headers: _jsonHeaders,
        body: json.encode({'idToken': token}),
      ).timeout(const Duration(seconds: 12));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final users = data['users'] as List?;
        if (users != null && users.isNotEmpty) {
          return users[0]['email'] as String?;
        }
      }
      throw http.ClientException('Failed to look up user data: HTTP ${response.statusCode}');
    });
  }

  Future<bool> verifyAdminPassword(String email, String password) async {
    final uri = Uri.parse('$_authBase/accounts:signInWithPassword?key=$_apiKey');
    try {
      final response = await _client.post(
        uri,
        headers: _jsonHeaders,
        body: json.encode({
          'email': email.trim(),
          'password': password,
          'returnSecureToken': false,
        }),
      ).timeout(const Duration(seconds: 12));

      if (response.statusCode == 200) return true;
      if (response.statusCode >= 400 && response.statusCode < 500) return false;
      throw http.ClientException('Password verification failed: HTTP ${response.statusCode}');

    } on Exception {
      return false;
    }
  }
}