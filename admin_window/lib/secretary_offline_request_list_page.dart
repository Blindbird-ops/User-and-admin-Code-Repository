import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:open_file/open_file.dart'; 

import 'offline_request.dart';
import 'offline_request_service.dart';
import 'login_screen.dart';

Future<bool> isOnline() async {
  var result = await Connectivity().checkConnectivity();
  return result != ConnectivityResult.none;
}

String safeStr(String? s) => s ?? '';

class SecretaryOfflineRequestListPage extends StatefulWidget {
  final String? firebaseToken;
  final String? userId; // THIS IS THE SECRETARY'S ID

  const SecretaryOfflineRequestListPage({
    super.key,
    this.firebaseToken,
    this.userId,
  });

  @override
  _SecretaryOfflineRequestListPageState createState() =>
      _SecretaryOfflineRequestListPageState();
}

class _SecretaryOfflineRequestListPageState
    extends State<SecretaryOfflineRequestListPage> {
  List<OfflineRequest> _requests = [];
  bool _isSyncing = false;
  bool _isGenerating = false; 

  @override
  void initState() {
    super.initState();
    _loadRequests();
  }

  Future<void> _loadRequests() async {
    final requests = await OfflineRequestService.getAllRequests();
    // Sort by newest first
    requests.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    setState(() {
      _requests = requests;
    });
  }

  // --- 1. MARK AS PAID FUNCTION ---
  // REPLACE THE OLD _markAsPaid FUNCTION WITH THIS NEW ONE
  Future<void> _markAsReleased(OfflineRequest req) async {
    final amountController = TextEditingController();
    
    final double? amount = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Release Document & Collect Payment"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // EXPLANATION: Updated text to say Released
            Text("Mark ${req.documentType} as RELEASED."),
            const SizedBox(height: 16),
            TextField(
              controller: amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              autofocus: true,
              decoration: const InputDecoration(labelText: "Amount Collected (₱)", border: OutlineInputBorder(), prefixText: "₱ "),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
            onPressed: () {
              final val = double.tryParse(amountController.text);
              if (val != null) Navigator.pop(ctx, val);
            },
            child: const Text("Confirm & Release"),
          )
        ],
      ),
    );

    if (amount == null) return;

    // Update Request Status in Hive
    final updatedReq = OfflineRequest(
      id: req.id,
      fullName: req.fullName,
      title: req.title,
      documentType: req.documentType,
      status: "Released",  // <--- KEY CHANGE: Sets status to Released
      businessName: req.businessName,
      businessAddress: req.businessAddress,
      operatorName: req.operatorName,
      operatorAddress: req.operatorAddress,
      amountPaid: amount,
      createdAt: req.createdAt,
      synced: false,
      birthDate: req.birthDate,
      placeOfBirth: req.placeOfBirth,
      fatherName: req.fatherName,
      motherName: req.motherName,
      controlNumber: req.controlNumber,
      partnerName: req.partnerName,
      partnerBirthDate: req.partnerBirthDate,
      cohabitationStartDate: req.cohabitationStartDate,
      buyerName: req.buyerName,
      quantity: req.quantity,
      amountWords: req.amountWords,
      amountFigures: req.amountFigures,
    );

    await OfflineRequestService.saveRequest(updatedReq);

    // Save Transaction
    await OfflineRequestService.saveTransaction(
      requestId: req.id,
      fullName: req.fullName,
      amount: amount,
      documentType: req.documentType,
    );

    // Log the action
    await OfflineRequestService.saveLog(
      "Updated ${req.documentType} to Released (Offline). Collected ₱$amount", 
      "Secretary (Offline)"
    );

    _loadRequests(); 
    if(mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Document Released!"), backgroundColor: Colors.green));
    }
  }
  
  void _showLoginRequiredDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Login required'),
        content: const Text('Missing authentication info. Please log in first.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => const LoginScreen()),
              );
            },
            child: const Text('Log in'),
          ),
        ],
      ),
    );
  }

  // --- UPDATED SYNC FUNCTION ---
  Future<void> _syncOfflineRequests() async {
    setState(() => _isSyncing = true);
    
    // Guard token/id
    final String secretaryId = safeStr(widget.userId);
    final String tokenVal = safeStr(widget.firebaseToken);

    if (secretaryId.isEmpty || tokenVal.isEmpty) {
      setState(() => _isSyncing = false);
      _loadRequests();
      _showLoginRequiredDialog();
      return;
    }

    // ✅ CORRECT URL (From your error message)
    const String baseUrl = 'https://mabskie-47c24-default-rtdb.firebaseio.com';

    // 1. SYNC REQUESTS
    final box = await OfflineRequestService.openRequestBox();
    final List<OfflineRequest> requests = box.values
        .map((e) => OfflineRequest.fromMap(Map<String, dynamic>.from(e)))
        .where((req) => !req.synced)
        .toList();

    int failed = 0;

    for (final req in requests) {
      try {
        // ✅ SYNC TO SECRETARY'S FOLDER: users/[SECRETARY_ID]/requests
        final url = '$baseUrl/users/$secretaryId/requests.json?auth=$tokenVal';
        
        final data = req.toMap();
        data.remove('id');
        data.remove('synced');
        
        // 🔹 Inject Secretary ID so it appears in their profile
        data['userId'] = secretaryId;
        data['userRole'] = "admin"; // Or "secretary"
        data['source'] = "offline_sync";

        // Handle nested maps
        if (req.documentType == 'Barangay Business Clearance') {
          data['businessDetails'] = {
            'businessName': safeStr(req.businessName),
            'businessAddress': safeStr(req.businessAddress),
            'operator': safeStr(req.operatorName),
            'operatorAddress': safeStr(req.operatorAddress),
          };
          data.remove('businessName'); data.remove('businessAddress');
          data.remove('operatorName'); data.remove('operatorAddress');
        }
        if (req.documentType.contains('Birth') || req.documentType.contains('Late Registration')) {
           data['birthDetails'] = {
            'birthDate': safeStr(req.birthDate),
            'placeOfBirth': safeStr(req.placeOfBirth),
            'fatherName': safeStr(req.fatherName),
            'motherName': safeStr(req.motherName),
            'controlNumber': safeStr(req.controlNumber),
          };
        }
        if (req.documentType.contains('Cohabitation')) {
           data['cohabitationDetails'] = {
             'partnerName': safeStr(req.partnerName),
             'partnerBirthDate': safeStr(req.partnerBirthDate),
             'cohabitationStartDate': safeStr(req.cohabitationStartDate),
           };
        }
        if (req.documentType.contains('Seaweeds')) {
           data['seaweedsDetails'] = {
             'buyerName': safeStr(req.buyerName),
             'quantity': safeStr(req.quantity),
             'amountWords': safeStr(req.amountWords),
             'amountFigures': safeStr(req.amountFigures),
           };
        }

        final response = await http.post(Uri.parse(url), body: json.encode(data));
        if (response.statusCode == 200 || response.statusCode == 201) {
          await box.delete(req.id);
        } else {
          print("Sync Request Failed: ${response.statusCode}");
          failed++;
        }
      } catch (e) {
        failed++;
      }
    }

    // 2. SYNC TRANSACTIONS
    final transBox = await OfflineRequestService.getTransactionBox();
    final transactions = transBox.values.toList();
    for (var t in transactions) {
       try {
         final tMap = Map<String, dynamic>.from(t);
         tMap.remove('synced');
         
         // 🔹 CRITICAL: Inject SECRETARY ID into the transaction
         // This ensures the transaction appears in the Secretary's billing history
         tMap['userId'] = secretaryId; 
         tMap['userEmail'] = "Secretary (Offline)"; 
         tMap['processedBy'] = "Secretary (Offline)"; 

         final url = '$baseUrl/transactions.json?auth=$tokenVal';
         await http.post(Uri.parse(url), body: jsonEncode(tMap));
       } catch (e) { print("Trans Sync Error: $e"); }
    }
    await transBox.clear(); 

    // 3. SYNC LOGS
    final logBox = await OfflineRequestService.getLogBox();
    final logs = logBox.values.toList();
    for (var l in logs) {
       try {
         final lMap = Map<String, dynamic>.from(l);
         lMap.remove('synced');
         // Inject role info into log
         lMap['role'] = "admin"; 
         lMap['actor'] = "Secretary (Offline)";

         final url = '$baseUrl/logs.json?auth=$tokenVal';
         await http.post(Uri.parse(url), body: jsonEncode(lMap));
       } catch (e) { print("Log Sync Error: $e"); }
    }
    await logBox.clear();

    setState(() => _isSyncing = false);
    _loadRequests();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(failed == 0 ? "Sync Complete!" : "Sync finished with $failed errors.")),
      );
    }
  }

  // --- RE-PRINT / GENERATE ---
  void _openPrintPage(BuildContext context, OfflineRequest req) async {
    setState(() => _isGenerating = true);
    
    try {
      final pythonUrl = Uri.parse('http://127.0.0.1:5000/generate_offline');
      
      Map<String, dynamic> data = req.toMap();
      
      if (req.documentType == 'Barangay Business Clearance') {
          data['businessDetails'] = {
            'businessName': safeStr(req.businessName),
            'businessAddress': safeStr(req.businessAddress),
            'operator': safeStr(req.operatorName),
            'operatorAddress': safeStr(req.operatorAddress),
          };
      }
      if (req.documentType.contains('Cohabitation')) {
           data['cohabitationDetails'] = {
             'partnerName': safeStr(req.partnerName),
             'partnerBirthDate': safeStr(req.partnerBirthDate),
             'cohabitationStartDate': safeStr(req.cohabitationStartDate),
           };
      }
      if (req.documentType.contains('Seaweeds')) {
           data['seaweedsDetails'] = {
             'buyerName': safeStr(req.buyerName),
             'quantity': safeStr(req.quantity),
             'amountWords': safeStr(req.amountWords),
             'amountFigures': safeStr(req.amountFigures),
           };
      }
      
      final response = await http.post(
        pythonUrl,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(data),
      );

      if (response.statusCode == 200) {
        final jsonResponse = jsonDecode(response.body);
        final String path = jsonResponse['path'];
        await OpenFile.open(path);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Python Error: ${response.body}"), backgroundColor: Colors.red)
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Connection Failed. Is generate_barangay.exe running? Error: $e"), backgroundColor: Colors.red)
        );
      }
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width > 900;
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: const Text("Saved Offline Requests",style: TextStyle(color: Colors.white),),
        backgroundColor: Colors.deepPurple,
       iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          _isSyncing
              ? const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                )
              : IconButton(
                  icon: const Icon(Icons.cloud_upload),
                  tooltip: "Sync to Firebase",
                  onPressed: () async {
                    if (!await isOnline()) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("No internet connection."), backgroundColor: Colors.red));
                      return;
                    }
                    await _syncOfflineRequests();
                  },
                ),
        ],
      ),
      body: Stack(
        children: [
          Center(
            child: Container(
              constraints: BoxConstraints(maxWidth: isWide ? 900 : 600),
              child: _requests.isEmpty
                  ? const Center(child: Text("No offline requests saved."))
                  :               // REPLACE THE ListView.builder IN YOUR BUILD METHOD
              ListView.builder(
                      itemCount: _requests.length,
                      itemBuilder: (context, index) {
                        final req = _requests[index];
                        
                        // EXPLANATION: Check if status is "Released" (not Successful)
                        final isReleased = req.status == 'Released';

                        return Card(
                          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          elevation: 6,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                            title: Text(
                              safeStr(req.documentType),
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: Colors.deepPurple.shade900),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(safeStr(req.fullName), style: const TextStyle(fontSize: 15)),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        // EXPLANATION: Green if Released, Orange if anything else
                                        color: isReleased ? Colors.green : Colors.orange,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(req.status, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                                    ),
                                    const SizedBox(width: 8),
                                    // EXPLANATION: Show Paid Amount only if Released
                                    if (isReleased) Text("Paid: ₱${req.amountPaid}", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.green)),
                                  ],
                                ),
                              ],
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // EXPLANATION: Button to Mark as Released (Hidden if already Released)
                                if (!isReleased)
                                  IconButton(
                                    icon: const Icon(Icons.monetization_on, color: Colors.green),
                                    tooltip: "Mark as Released (Paid)",
                                    onPressed: () => _markAsReleased(req), // Calls new function
                                  ),

                                IconButton(
                                  icon: const Icon(Icons.print),
                                  tooltip: "Reprint Document",
                                  onPressed: () => _openPrintPage(context, req),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ),
          if (_isGenerating)
            Container(
              color: Colors.black54,
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Colors.white),
                    SizedBox(height: 16),
                    Text("Generating Document...", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold))
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}