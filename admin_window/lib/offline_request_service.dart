import 'package:hive_flutter/hive_flutter.dart';
import 'offline_request.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class OfflineRequestService {
  static const String requestBoxName = 'offline_requests';
  static const String transactionBoxName = 'offline_transactions';
  static const String logBoxName = 'offline_logs';

  // --- INITIALIZATION ---
  static Future<void> init() async {
    await Hive.initFlutter();
    await Hive.openBox(requestBoxName);
    await Hive.openBox(transactionBoxName);
    await Hive.openBox(logBoxName);
  }

  // --- REQUESTS ---
  static Future<Box> openRequestBox() async => Hive.openBox(requestBoxName);

  static Future<void> saveRequest(OfflineRequest request) async {
    final box = await openRequestBox();
    await box.put(request.id, request.toMap());
  }

  static Future<List<OfflineRequest>> getAllRequests() async {
    final box = await openRequestBox();
    return box.values
        .map((e) => OfflineRequest.fromMap(Map<String, dynamic>.from(e)))
        .toList();
  }

  static Future<void> deleteRequest(String id) async {
    final box = await openRequestBox();
    await box.delete(id);
  }

  // --- TRANSACTIONS (BILLING) ---
  static Future<Box> getTransactionBox() async => Hive.openBox(transactionBoxName);

  static Future<void> saveTransaction({
    required String requestId,
    required String fullName,
    required double amount,
    required String documentType,
  }) async {
    final box = await getTransactionBox();
    final transaction = {
      'requestId': requestId,
      'fullName': fullName,
      'amount': amount,
      'documentType': documentType,
      'timestamp': DateTime.now().toIso8601String(),
      'synced': false,
    };
    // Save using requestId as key
    await box.put(requestId, transaction);
  }

  // --- LOGS ---
  static Future<Box> getLogBox() async => Hive.openBox(logBoxName);

  static Future<void> saveLog(String message, String userEmail) async {
    final box = await getLogBox();
    final log = {
      'message': message,
      'user': userEmail,
      'timestamp': DateTime.now().toIso8601String(),
      'synced': false,
    };
    await box.add(log);
  }

  // --- SYNC FUNCTION (Requests Only) ---
  // Note: The UI page (SecretaryOfflineRequestListPage) handles syncing transactions/logs.
  // This helper handles the complex Request mapping.
  static Future<int> syncRequestsOnly(String firebaseToken, String userId) async {
    final box = await openRequestBox();
    final List<OfflineRequest> requests = box.values
        .map((e) => OfflineRequest.fromMap(Map<String, dynamic>.from(e)))
        .where((req) => !req.synced)
        .toList();

    int failed = 0;

    for (final req in requests) {
      try {
        final url = 'https://mabskie-47c24-default-rtdb.firebaseio.com/users/$userId/requests.json?auth=$firebaseToken';

        final data = req.toMap();
        data.remove('id');
        data.remove('synced');

        // 1. Business Clearance Nested Map
        if (req.documentType == 'Barangay Business Clearance') {
          data['businessDetails'] = {
            'businessName': req.businessName,
            'businessAddress': req.businessAddress,
            'operator': req.operatorName,
            'operatorAddress': req.operatorAddress,
          };
          data.remove('businessName'); data.remove('businessAddress');
          data.remove('operatorName'); data.remove('operatorAddress');
        }

        // 2. Birth Certificate Nested Map
        if (req.documentType.contains('Birth') || req.documentType.contains('Late Registration')) {
          data['birthDetails'] = {
            'birthDate': req.birthDate,
            'placeOfBirth': req.placeOfBirth,
            'fatherName': req.fatherName,
            'motherName': req.motherName,
            'controlNumber': req.controlNumber,
          };
          data.remove('birthDate'); data.remove('placeOfBirth');
          data.remove('fatherName'); data.remove('motherName');
          data.remove('controlNumber');
        }

        // 3. Cohabitation Nested Map
        if (req.documentType.contains('Cohabitation')) {
           data['cohabitationDetails'] = {
             'partnerName': req.partnerName,
             'partnerBirthDate': req.partnerBirthDate,
             'cohabitationStartDate': req.cohabitationStartDate,
           };
           data.remove('partnerName'); data.remove('partnerBirthDate');
           data.remove('cohabitationStartDate');
        }

        // 4. Seaweeds Nested Map
        if (req.documentType.contains('Seaweeds')) {
           data['seaweedsDetails'] = {
             'buyerName': req.buyerName,
             'quantity': req.quantity,
             'amountWords': req.amountWords,
             'amountFigures': req.amountFigures,
           };
           data.remove('buyerName'); data.remove('quantity');
           data.remove('amountWords'); data.remove('amountFigures');
        }

        final response = await http.post(Uri.parse(url), body: json.encode(data));
        if (response.statusCode == 200 || response.statusCode == 201) {
          await box.delete(req.id);
        } else {
          failed++;
          print('Failed to sync request: ${response.body}');
        }
      } catch (e) {
        failed++;
        print('Error syncing request: $e');
      }
    }
    return failed;
  }
}