// lib/map_page.dart

import 'dart:convert';
import 'dart:math' as math;
import 'package:admin_window/services/report_generator.dart';
import 'package:flutter/material.dart';
import 'package:webview_windows/webview_windows.dart';
import 'package:http/http.dart' as http;
import 'package:fl_chart/fl_chart.dart';
import 'package:firebase_auth/firebase_auth.dart';

class MapPage extends StatefulWidget {
  const MapPage({super.key});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  final _controller = WebviewController();
  bool _isWebviewInitialized = false;
  final List<Map<String, dynamic>> _households = [];
  bool _isLoadingData = true;
  String _debugInfo = '';
  String? _authToken;

  // Duplicate tracking
  final Map<String, List<Map<String, dynamic>>> _duplicateGroups = {};
  final Map<String, String> _duplicateReasons = {};

  // --- DEMOGRAPHIC DATA ---
  int _totalPopulation = 0;
  int _validHouseholds = 0;
  int _maleCount = 0;
  int _femaleCount = 0;
  Map<String, int> _ageGroups = {
    '0-14': 0,
    '15-24': 0,
    '25-54': 0,
    '55-64': 0,
    '65+': 0
  };
  Map<String, int> _purokPopulation = {};
  double _averageIncome = 0.0;

  // REPLACE WITH YOUR GOOGLE MAPS API KEY
  final String apiKey = "AIzaSyBNfHUkGzoxETQbBSc9yfQ7LkuzzYpFrQw";
  double centerLat = 10.9650;
  double centerLng = 119.5100;
  int mapZoom = 13;

  @override
  void initState() {
    super.initState();
    print("🚀 MapPage initialized");
    _loadHouseholdData();
  }

  Future<void> _loadHouseholdData() async {
    print("📡 Starting data load...");

    try {
      // Get Firebase Auth Token
      final User? currentUser = FirebaseAuth.instance.currentUser;

      if (currentUser == null) {
        print("❌ No user logged in!");
        setState(() {
          _debugInfo = 'User not logged in';
          _isLoadingData = false;
        });
        return;
      }

      print("👤 Current user: ${currentUser.email} (${currentUser.uid})");

      // Get fresh ID token
      _authToken = await currentUser.getIdToken();
      print("🔑 Got auth token: ${_authToken?.substring(0, 20)}...");

      final url =
          'https://mabskie-47c24-default-rtdb.firebaseio.com/household_surveys.json?auth=$_authToken';
      print("🔗 Request URL: ${url.substring(0, 80)}...");

      final response = await http.get(Uri.parse(url));
      print("📥 Response status: ${response.statusCode}");

      if (response.statusCode == 200) {
        print("✅ Response body length: ${response.body.length} characters");

        final data = json.decode(response.body) as Map<String, dynamic>?;

        if (data != null && data.isNotEmpty) {
          print("📊 Root level keys found: ${data.keys.toList()}");

          _households.clear();
          _findSurveys("root", data);

          print("🏠 Total households found: ${_households.length}");
          _debugInfo = 'Loaded ${_households.length} households';

          for (var h in _households) {
            print(
                "  - ${h['headOfFamily']} (${h['latitude']}, ${h['longitude']}) - Members: ${h['memberCount']}");
          }

          _flagDuplicatesWithReasons();
          _calculateDemographics();
          _calculateMapCenter();
        } else {
          print("⚠️ Data is null or empty!");
          _debugInfo = 'No data received from Firebase';
        }
      } else {
        print("❌ HTTP Error: ${response.statusCode} - ${response.body}");
        _debugInfo = 'HTTP Error: ${response.statusCode}';
      }
    } catch (e, stackTrace) {
      print("💥 CRITICAL ERROR loading household data: $e");
      print("Stack trace: $stackTrace");
      _debugInfo = 'Error: $e';
    } finally {
      if (mounted) {
        setState(() => _isLoadingData = false);
      }
      await _initWebview();
    }
  }

  void _calculateMapCenter() {
    if (_households.isEmpty) return;

    double minLat = double.infinity;
    double maxLat = double.negativeInfinity;
    double minLng = double.infinity;
    double maxLng = double.negativeInfinity;

    for (var h in _households) {
      double lat = h['latitude'];
      double lng = h['longitude'];

      if (lat != 0 && lng != 0) {
        minLat = math.min(minLat, lat);
        maxLat = math.max(maxLat, lat);
        minLng = math.min(minLng, lng);
        maxLng = math.max(maxLng, lng);
      }
    }

    centerLat = (minLat + maxLat) / 2;
    centerLng = (minLng + maxLng) / 2;

    double latDiff = maxLat - minLat;
    double lngDiff = maxLng - minLng;
    double maxDiff = math.max(latDiff, lngDiff);

    if (maxDiff < 0.01) {
      mapZoom = 15;
    } else if (maxDiff < 0.05)
      mapZoom = 13;
    else if (maxDiff < 0.1)
      mapZoom = 12;
    else
      mapZoom = 11;

    print(
        "🗺️ Map center adjusted to: ($centerLat, $centerLng) zoom: $mapZoom");
    print("   Bounds: Lat[$minLat to $maxLat] Lng[$minLng to $maxLng]");
  }

  void _findSurveys(String currentKey, dynamic dynamicNode) {
    if (dynamicNode is! Map) {
      print("⚠️ Skipping non-Map node: $currentKey");
      return;
    }

    if (dynamicNode.containsKey('headOfFamily')) {
      print("✅ Found survey: $currentKey");
      _parseAndAddHousehold(currentKey, dynamicNode);
    } else {
      print(
          "📁 Exploring folder: $currentKey (${dynamicNode.keys.length} sub-items)");
      dynamicNode.forEach((key, value) {
        if (value is Map) {
          _findSurveys(key.toString(), value);
        }
      });
    }
  }

  void _parseAndAddHousehold(String id, Map dynamicData) {
    try {
      final Map<String, dynamic> household =
          Map<String, dynamic>.from(dynamicData);

      List<dynamic> membersList = [];
      if (household['members'] is List) {
        membersList = List<dynamic>.from(household['members']);
      } else if (household['members'] is Map) {
        membersList = (household['members'] as Map).values.toList();
      }

      double lat =
          double.tryParse(household['latitude']?.toString() ?? '0') ?? 0.0;
      double lng =
          double.tryParse(household['longitude']?.toString() ?? '0') ?? 0.0;

      if (lat == 0 || lng == 0) {
        print("⚠️ Warning: Survey $id has invalid coordinates ($lat, $lng)");
      }

      _households.add({
        'id': id,
        'headOfFamily': household['headOfFamily']?.toString() ?? 'Unknown',
        'purok': household['purok']?.toString() ?? 'Unknown',
        'sitio': household['sitio']?.toString() ?? 'Unknown',
        'monthlyIncome': household['monthlyIncome']?.toString() ?? '0',
        'memberCount': int.tryParse(
                household['householdMemberCount']?.toString() ?? '0') ??
            membersList.length,
        'latitude': lat,
        'longitude': lng,
        'members': membersList,
        'isDuplicate': false,
        'duplicateGroupId': null,
      });

      print("   Added: ${household['headOfFamily']} at ($lat, $lng)");
    } catch (e) {
      print("❌ Failed to parse household $id: $e");
    }
  }

  void _flagDuplicatesWithReasons() {
    _duplicateGroups.clear();
    _duplicateReasons.clear();

    for (int i = 0; i < _households.length; i++) {
      if (_households[i]['isDuplicate'] == true) continue;

      final membersI = (_households[i]['members'] as List)
          .map((m) => (m['name']?.toString() ?? '').trim().toLowerCase())
          .where((name) => name.isNotEmpty)
          .toSet();

      List<Map<String, dynamic>> duplicateGroup = [_households[i]];
      List<String> commonMembers = [];

      for (int j = i + 1; j < _households.length; j++) {
        if (_households[j]['isDuplicate'] == true) continue;

        final membersJ = (_households[j]['members'] as List)
            .map((m) => (m['name']?.toString() ?? '').trim().toLowerCase())
            .where((name) => name.isNotEmpty)
            .toSet();

        final matchingMembers = membersI.intersection(membersJ);
        if (matchingMembers.length >= 2) {
          duplicateGroup.add(_households[j]);
          commonMembers.addAll(matchingMembers);
          _households[j]['isDuplicate'] = true;
        }
      }

      if (duplicateGroup.length > 1) {
        _households[i]['isDuplicate'] = true;
        final groupId = 'group_${_duplicateGroups.length}';
        
        for (var household in duplicateGroup) {
          household['duplicateGroupId'] = groupId;
        }

        _duplicateGroups[groupId] = duplicateGroup;
        
        final uniqueCommonMembers = commonMembers.toSet().toList();
        _duplicateReasons[groupId] = 
            'Households share ${uniqueCommonMembers.length} common member(s): ${uniqueCommonMembers.join(", ")}';

        print("⚠️ Duplicate group $groupId: ${duplicateGroup.map((h) => h['headOfFamily']).join(' ↔ ')}");
        print("   Reason: ${_duplicateReasons[groupId]}");
      }
    }
  }

  void _showDuplicateDetails(String groupId) {
    final group = _duplicateGroups[groupId];
    final reason = _duplicateReasons[groupId];
    
    if (group == null) return;

    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600, maxHeight: 700),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.orange.shade700, Colors.orange.shade500],
                  ),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 28),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Duplicate Households Detected',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              
              // Scrollable Content
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Reason Box
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.orange.shade300, width: 2),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.info_outline, color: Colors.orange.shade800, size: 20),
                                const SizedBox(width: 8),
                                Text(
                                  'Duplicate Reason:',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.orange.shade800,
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              reason ?? 'Unknown reason',
                              style: TextStyle(
                                color: Colors.orange.shade900,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                      
                      const SizedBox(height: 20),
                      
                      // Affected Households Header
                      Row(
                        children: [
                          Icon(Icons.home, color: Colors.blue.shade700),
                          const SizedBox(width: 8),
                          Text(
                            'Affected Households (${group.length})',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          ),
                        ],
                      ),
                      
                      const SizedBox(height: 12),
                      
                      // Household Cards
                      ...group.asMap().entries.map((entry) {
                        final index = entry.key;
                        final household = entry.value;
                        
                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          elevation: 2,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(color: Colors.orange.shade200, width: 1),
                          ),
                          child: ExpansionTile(
                            leading: CircleAvatar(
                              backgroundColor: Colors.orange.shade700,
                              foregroundColor: Colors.white,
                              child: Text('${index + 1}'),
                            ),
                            title: Text(
                              household['headOfFamily'],
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                'Purok: ${household['purok']}, Sitio: ${household['sitio']}',
                                style: TextStyle(color: Colors.grey.shade600),
                              ),
                            ),
                            children: [
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade50,
                                  borderRadius: const BorderRadius.vertical(
                                    bottom: Radius.circular(12),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _buildDetailRow('ID', household['id'].toString()),
                                    _buildDetailRow('Members', '${household['memberCount']} persons'),
                                    _buildDetailRow('Income', '₱${household['monthlyIncome']}'),
                                    _buildDetailRow(
                                      'Coordinates',
                                      '${household['latitude']}, ${household['longitude']}',
                                    ),
                                    
                                    const Divider(height: 20),
                                    
                                    Row(
                                      children: [
                                        Icon(Icons.people, size: 16, color: Colors.blue.shade700),
                                        const SizedBox(width: 6),
                                        const Text(
                                          'Family Members:',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    
                                    ...(household['members'] as List).map((member) => 
                                      Padding(
                                        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                                        child: Row(
                                          children: [
                                            Container(
                                              width: 6,
                                              height: 6,
                                              decoration: BoxDecoration(
                                                color: Colors.blue.shade400,
                                                shape: BoxShape.circle,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                '${member['name']} (${member['age']} yo, ${member['sex']})',
                                                style: const TextStyle(fontSize: 13),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ),
              
              // Footer Actions
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton.icon(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                      label: const Text('Close'),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.grey.shade700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade700,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  void _calculateDemographics() {
    _totalPopulation = 0;
    _validHouseholds = 0;
    _maleCount = 0;
    _femaleCount = 0;
    _ageGroups = {
      '0-14': 0,
      '15-24': 0,
      '25-54': 0,
      '55-64': 0,
      '65+': 0
    };
    _purokPopulation = {};
    _averageIncome = 0.0;

    int totalIncomeSum = 0;
    int householdsWithIncome = 0;

    for (var h in _households) {
      if (h['isDuplicate'] == true) continue;

      _validHouseholds++;
      String purok = h['purok'].toString();
      _purokPopulation[purok] =
          (_purokPopulation[purok] ?? 0) + (h['memberCount'] as int);

      String incomeStr =
          h['monthlyIncome'].toString().replaceAll(RegExp(r'[^0-9]'), '');
      int income = int.tryParse(incomeStr) ?? 0;
      if (income > 0) {
        totalIncomeSum += income;
        householdsWithIncome++;
      }

      List members = h['members'];
      for (var m in members) {
        if (m is! Map) continue;

        _totalPopulation++;

        if (m['sex'] == 'Male') {
          _maleCount++;
        } else if (m['sex'] == 'Female') _femaleCount++;

        int age = m['age'] is int
            ? m['age']
            : int.tryParse(m['age'].toString()) ?? 0;
        if (age <= 14) {
          _ageGroups['0-14'] = _ageGroups['0-14']! + 1;
        } else if (age <= 24)
          _ageGroups['15-24'] = _ageGroups['15-24']! + 1;
        else if (age <= 54)
          _ageGroups['25-54'] = _ageGroups['25-54']! + 1;
        else if (age <= 64)
          _ageGroups['55-64'] = _ageGroups['55-64']! + 1;
        else
          _ageGroups['65+'] = _ageGroups['65+']! + 1;
      }
    }

    if (householdsWithIncome > 0) {
      _averageIncome = totalIncomeSum / householdsWithIncome;
    }

    print(
        "📊 Demographics: Pop=$_totalPopulation, Households=$_validHouseholds, M/F=$_maleCount/$_femaleCount");
  }

  Future<void> _initWebview() async {
    try {
      print("🌐 Initializing webview...");
      await _controller.initialize();
      _controller.loadingState.listen((event) {
        if (event == LoadingState.navigationCompleted) {
          print("✅ Webview loaded successfully");
          if (mounted) {
            setState(() => _isWebviewInitialized = true);
          }
        }
      });

      final htmlContent = _getHtmlContent();
      print("📄 Generated HTML with ${_households.length} markers");
      await _controller.loadStringContent(htmlContent);
    } catch (e) {
      print("❌ Error initializing webview: $e");
    }
  }

// At the top of map_page.dart, add this import:

// Replace the _printReport() method with this:
void _printReport() async {
  // Show loading dialog
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) => Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 60,
              height: 60,
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.blue.shade600),
                strokeWidth: 4,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              "Generating Census Report...",
              style: TextStyle(
                color: Colors.blue.shade700,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              "AI is analyzing demographic data\nThis may take a few seconds...",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.grey,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    ),
  );

  try {
    await ReportGenerator.printCensusReport(
      totalPopulation: _totalPopulation,
      validHouseholds: _validHouseholds,
      maleCount: _maleCount,
      femaleCount: _femaleCount,
      ageGroups: _ageGroups,
      purokPopulation: _purokPopulation,
      averageIncome: _averageIncome,
      households: _households,
      duplicateGroups: _duplicateGroups,
      duplicateReasons: _duplicateReasons,
    );

    // Close loading dialog
    if (mounted) Navigator.pop(context);

    // Show success message
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Report Generated Successfully!',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const Text(
                      'PDF is ready to print or share',
                      style: TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          backgroundColor: Colors.green.shade600,
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    }
  } catch (e) {
    // Close loading dialog
    if (mounted) Navigator.pop(context);

    // Show error message
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error_outline, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(
                child: Text('Error generating report: $e'),
              ),
            ],
          ),
          backgroundColor: Colors.red.shade600,
          duration: const Duration(seconds: 6),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    }
  }
}

// Remove the old _generatePrintableReport() method - it's no longer needed

  @override
  Widget build(BuildContext context) {
    if (_isLoadingData) {
      return Scaffold(
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.blue.shade50, Colors.white],
            ),
          ),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.blue.shade100,
                        blurRadius: 30,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      SizedBox(
                        width: 60,
                        height: 60,
                        child: CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.blue.shade600),
                          strokeWidth: 4,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        "Loading Census Data...",
                        style: TextStyle(
                          color: Colors.blue.shade700,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "Please wait while we fetch household information",
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return DefaultTabController(
      length: 3,
      child: Scaffold(
appBar: AppBar(
  elevation: 2,
  toolbarHeight: 70,
  iconTheme: const IconThemeData(
    color: Colors.amber, // Back button color
    size: 28,
  ),
  flexibleSpace: Container(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [Colors.blue.shade800, Colors.blue.shade600],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
    ),
  ),
  title: Row(
    children: [
      Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.amber.withOpacity(0.2),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: Colors.amber.withOpacity(0.4),
            width: 2,
          ),
        ),
        child: const Icon(
          Icons.map, 
          size: 28,
          color: Colors.amber, // Map icon color
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              "Brgy. Pularaquen GIS",
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 2),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.25),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _debugInfo,
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    ],
  ),
  actions: [
    if (_households.isNotEmpty)
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: ElevatedButton.icon(
          onPressed: _printReport,
          icon: const Icon(Icons.print, size: 20),
          label: const Text("Print Report"),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: Colors.blue.shade700,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ),
    const SizedBox(width: 8),
  ],
  bottom: PreferredSize(
    preferredSize: const Size.fromHeight(50),
    child: Container(
      decoration: BoxDecoration(
        color: Colors.blue.shade900,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: const TabBar(
        labelColor: Colors.white,
        unselectedLabelColor: Colors.white60,
        indicatorColor: Colors.amber,
        indicatorWeight: 3,
        indicatorPadding: EdgeInsets.symmetric(horizontal: 16),
        tabs: [
          Tab(
            icon: Icon(Icons.map_outlined),
            text: "Interactive Map",
            height: 50,
          ),
          Tab(
            icon: Icon(Icons.analytics_outlined),
            text: "Demographics",
            height: 50,
          ),
          Tab(
            icon: Icon(Icons.table_view_outlined),
            text: "Household Data",
            height: 50,
          ),
        ],
      ),
    ),
  ),
),
        body: _households.isEmpty
            ? _buildEmptyState()
            : TabBarView(
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _buildMapTab(),
                  _buildDashboardTab(),
                  _buildTableTab(),
                ],
              ),
      ),
    );
  }

  Widget _buildMapTab() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.blue.shade50, Colors.white],
        ),
      ),
      child: _isWebviewInitialized
          ? Column(
              children: [
                if (_duplicateGroups.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.all(12),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.orange.shade100, Colors.orange.shade50],
                      ),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.orange.shade400, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.orange.shade200,
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.warning_amber_rounded, color: Colors.orange.shade700, size: 28),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Data Quality Alert',
                                style: TextStyle(
                                  color: Colors.orange.shade900,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${_duplicateGroups.length} duplicate household group(s) detected. Click on red markers for details.',
                                style: TextStyle(
                                  color: Colors.orange.shade800,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                Expanded(child: Webview(_controller)),
              ],
            )
          : Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.blue.shade600),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    "Loading Map...",
                    style: TextStyle(
                      color: Colors.blue.shade700,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.red.shade50, Colors.white],
        ),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Card(
            elevation: 8,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade100,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.error_outline,
                      size: 48,
                      color: Colors.orange.shade700,
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    "No Survey Data Found",
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _debugInfo,
                    style: TextStyle(color: Colors.grey[600], fontSize: 16),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: () {
                      setState(() => _isLoadingData = true);
                      _loadHouseholdData();
                    },
                    icon: const Icon(Icons.refresh),
                    label: const Text("Retry"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue.shade600,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDashboardTab() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.blue.shade50, Colors.white],
        ),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.analytics, color: Colors.blue.shade700, size: 32),
                const SizedBox(width: 12),
                const Text(
                  "Census Analytics Dashboard",
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1565C0),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            
            // Summary Cards
            Row(
              children: [
                _buildSummaryCard(
                  "Total Population",
                  _totalPopulation.toString(),
                  Icons.groups,
                  Colors.blue,
                  "Total residents surveyed",
                ),
                _buildSummaryCard(
                  "Valid Households",
                  _validHouseholds.toString(),
                  Icons.house,
                  Colors.green,
                  "Households (excluding duplicates)",
                ),
                _buildSummaryCard(
                  "Avg Family Size",
                  (_totalPopulation / (_validHouseholds == 0 ? 1 : _validHouseholds)).toStringAsFixed(1),
                  Icons.family_restroom,
                  Colors.orange,
                  "People per household",
                ),
                _buildSummaryCard(
                  "Monthly Income",
                  "₱${_averageIncome.toStringAsFixed(0)}",
                  Icons.payments,
                  Colors.teal,
                  "Average household income",
                ),
              ],
            ),
            
            const SizedBox(height: 24),
            
            // Warning for duplicates
            if (_duplicateGroups.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(bottom: 24),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange.shade300),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: Colors.orange.shade700, size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Data Quality Alert",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.orange.shade800,
                              fontSize: 16,
                            ),
                          ),
                          Text(
                            "${_duplicateGroups.length} duplicate household group(s) detected. Review the data table for details.",
                            style: TextStyle(color: Colors.orange.shade700),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            
            // Charts Row
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 1,
                  child: _buildGenderChart(),
                ),
                const SizedBox(width: 24),
                Expanded(
                  flex: 2,
                  child: _buildAgeChart(),
                ),
              ],
            ),
            
            const SizedBox(height: 24),
            
            // Purok Distribution
            _buildPurokDistribution(),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCard(String title, String value, IconData icon, Color color, String subtitle) {
    return Expanded(
      child: Card(
        elevation: 6,
        margin: const EdgeInsets.symmetric(horizontal: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Colors.white, color.withOpacity(0.05)],
            ),
          ),
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: color, size: 28),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          value,
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: color.shade700,
                          ),
                        ),
                        Text(
                          title,
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                subtitle,
                style: TextStyle(
                  color: Colors.grey.shade500,
                  fontSize: 12,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGenderChart() {
    return Card(
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.white, Colors.blue.shade50],
          ),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Row(
              children: [
                Icon(Icons.pie_chart, color: Colors.blue.shade600),
                const SizedBox(width: 8),
                const Text(
                  "Gender Distribution",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 200,
              child: PieChart(
                PieChartData(
                  sectionsSpace: 3,
                  centerSpaceRadius: 50,
                  sections: [
                    PieChartSectionData(
                      color: Colors.blue.shade400,
                      value: _maleCount.toDouble(),
                      title: 'Male\n$_maleCount\n(${(_maleCount / _totalPopulation * 100).toStringAsFixed(1)}%)',
                      radius: 70,
                      titleStyle: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                    PieChartSectionData(
                      color: Colors.pink.shade300,
                      value: _femaleCount.toDouble(),
                      title: 'Female\n$_femaleCount\n(${(_femaleCount / _totalPopulation * 100).toStringAsFixed(1)}%)',
                      radius: 70,
                      titleStyle: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

Widget _buildAgeChart() {
  return Card(
    elevation: 6,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    child: Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.white, Colors.purple.shade50],
        ),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.bar_chart, color: Colors.purple.shade600),
              const SizedBox(width: 8),
              const Text(
                "Age Demographics",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 200,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                barTouchData: BarTouchData(
                  enabled: true,
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipColor: (group) => Colors.black87,
                    tooltipPadding: const EdgeInsets.all(8),
                    tooltipMargin: 8,
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      final ageGroup = ['0-14', '15-24', '25-54', '55-64', '65+'][group.x.toInt()];
                      final count = rod.toY.toInt();
                      final percentage = (count / _totalPopulation * 100).toStringAsFixed(1);
                      return BarTooltipItem(
                        '$ageGroup\n$count people\n($percentage%)',
                        const TextStyle(color: Colors.white, fontSize: 12),
                      );
                    },
                  ),
                ),
                titlesData: FlTitlesData(
                  show: true,
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        const titles = ['0-14', '15-24', '25-54', '55-64', '65+'];
                        return Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Text(
                            titles[value.toInt()],
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                borderData: FlBorderData(show: false),
                gridData: const FlGridData(show: false),
                barGroups: _ageGroups.entries.toList().asMap().entries.map((entry) {
                  return BarChartGroupData(
                    x: entry.key,
                    barRods: [
                      BarChartRodData(
                        toY: entry.value.value.toDouble(),
                        color: Colors.purple.shade400,
                        width: 24,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(6),
                        ),
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [
                            Colors.purple.shade300,
                            Colors.purple.shade600,
                          ],
                        ),
                      )
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}


  Widget _buildPurokDistribution() {
    return Card(
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.white, Colors.green.shade50],
          ),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.location_city, color: Colors.green.shade600),
                const SizedBox(width: 8),
                const Text(
                  "Population by Purok",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ..._purokPopulation.entries.map((entry) {
              final percentage = (entry.value / _totalPopulation * 100);
              return Container(
                margin: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          entry.key,
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                        Text(
                          '${entry.value} (${percentage.toStringAsFixed(1)}%)',
                          style: TextStyle(color: Colors.green.shade700),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    LinearProgressIndicator(
                      value: percentage / 100,
                      backgroundColor: Colors.green.shade100,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.green.shade400),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildTableTab() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.grey.shade50, Colors.white],
        ),
      ),
      padding: const EdgeInsets.all(24),
      child: Card(
        elevation: 8,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.blue.shade700,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.table_view, color: Colors.white),
                  const SizedBox(width: 12),
                  const Text(
                    "Household Survey Data",
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      "${_households.length} Total Records",
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.vertical,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    headingRowColor: WidgetStateProperty.all(Colors.blue.shade50),
                    dataRowMaxHeight: 60,
                    columns: const [
                      DataColumn(
                        label: Text('Status', style: TextStyle(fontWeight: FontWeight.bold)),
                        tooltip: 'Data validation status',
                      ),
                      DataColumn(
                        label: Text('ID', style: TextStyle(fontWeight: FontWeight.bold)),
                        tooltip: 'Household ID',
                      ),
                      DataColumn(
                        label: Text('Head of Family', style: TextStyle(fontWeight: FontWeight.bold)),
                        tooltip: 'Household head name',
                      ),
                      DataColumn(
                        label: Text('Purok', style: TextStyle(fontWeight: FontWeight.bold)),
                        tooltip: 'Purok location',
                      ),
                      DataColumn(
                        label: Text('Sitio', style: TextStyle(fontWeight: FontWeight.bold)),
                        tooltip: 'Sitio location',
                      ),
                      DataColumn(
                        label: Text('Members', style: TextStyle(fontWeight: FontWeight.bold)),
                        numeric: true,
                        tooltip: 'Number of household members',
                      ),
                      DataColumn(
                        label: Text('Coordinates', style: TextStyle(fontWeight: FontWeight.bold)),
                        tooltip: 'GPS coordinates',
                      ),
                      DataColumn(
                        label: Text('Income', style: TextStyle(fontWeight: FontWeight.bold)),
                        tooltip: 'Monthly household income',
                      ),
                      DataColumn(
                        label: Text('Actions', style: TextStyle(fontWeight: FontWeight.bold)),
                        tooltip: 'Available actions',
                      ),
                    ],
                    rows: _households.map((h) {
                      final isDup = h['isDuplicate'] == true;
                      final groupId = h['duplicateGroupId'];
                      
                      return DataRow(
                        color: isDup
                            ? WidgetStateProperty.all(Colors.red.shade50)
                            : WidgetStateProperty.all(Colors.white),
                        cells: [
                          DataCell(
                            isDup
                                ? Tooltip(
                                    message: "Potential Duplicate - Click for details",
                                    child: Icon(Icons.warning, color: Colors.red.shade600),
                                  )
                                : Tooltip(
                                    message: "Valid record",
                                    child: Icon(Icons.check_circle, color: Colors.green.shade600),
                                  ),
                          ),
                          DataCell(
                            Text(
                              h['id'].toString().length > 12
                                  ? '${h['id'].toString().substring(0, 12)}...'
                                  : h['id'].toString(),
                              style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                            ),
                          ),
                          DataCell(Text(h['headOfFamily'])),
                          DataCell(
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade100,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                h['purok'],
                                style: TextStyle(color: Colors.blue.shade700, fontSize: 12),
                              ),
                            ),
                          ),
                          DataCell(Text(h['sitio'])),
                          DataCell(
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.green.shade100,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                h['memberCount'].toString(),
                                style: TextStyle(
                                  color: Colors.green.shade700,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                          DataCell(
                            Text(
                              '${h['latitude'].toStringAsFixed(4)}, ${h['longitude'].toStringAsFixed(4)}',
                              style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                            ),
                          ),
                          DataCell(
                            Text(
                              '₱${h['monthlyIncome']}',
                              style: TextStyle(color: Colors.teal.shade600),
                            ),
                          ),
                          DataCell(
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (isDup && groupId != null)
                                  IconButton(
                                    icon: Icon(Icons.info_outline, color: Colors.red.shade600),
                                    tooltip: 'View duplicate details',
                                    onPressed: () => _showDuplicateDetails(groupId),
                                  ),
                                IconButton(
                                  icon: Icon(Icons.visibility, color: Colors.blue.shade600),
                                  tooltip: 'View details',
                                  onPressed: () => _showHouseholdDetails(h),
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                    }).toList(),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showHouseholdDetails(Map<String, dynamic> household) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500, maxHeight: 600),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.blue.shade700, Colors.blue.shade500],
                  ),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.home, color: Colors.white, size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Household Details',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          Text(
                            household['headOfFamily'],
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              
              // Content
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildDetailRow('ID', household['id'].toString()),
                      _buildDetailRow('Location', '${household['purok']}, ${household['sitio']}'),
                      _buildDetailRow(
                        'Coordinates',
                        '${household['latitude']}, ${household['longitude']}',
                      ),
                      _buildDetailRow('Monthly Income', '₱${household['monthlyIncome']}'),
                      
                      const Divider(height: 30),
                      
                      Row(
                        children: [
                          Icon(Icons.people, color: Colors.blue.shade700, size: 20),
                          const SizedBox(width: 8),
                          const Text(
                            'Family Members',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                      
                      const SizedBox(height: 12),
                      
                      ...(household['members'] as List).asMap().entries.map((entry) {
                        final index = entry.key;
                        final member = entry.value;
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: Colors.blue.shade100,
                              foregroundColor: Colors.blue.shade700,
                              child: Text('${index + 1}'),
                            ),
                            title: Text(member['name'] ?? 'Unknown'),
                            subtitle: Text('Age: ${member['age']}, Sex: ${member['sex']}'),
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ),
              
              // Footer
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton.icon(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                      label: const Text('Close'),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.grey.shade700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getHtmlContent() {
    final markersJs = _households.map((h) {
      final members = (h['members'] as List)
          .map((m) => '${m['name']} (${m['age']}yo, ${m['sex']})')
          .join('<br>');
      final bool isDuplicate = h['isDuplicate'] == true;
      final String fillColor = isDuplicate ? "#E53935" : "#1976D2";
      final String groupId = h['duplicateGroupId'] ?? '';
      final String duplicateWarningHtml = isDuplicate
          ? '<div style="background: #ffebee; color: #c62828; padding: 8px; margin-bottom: 12px; border-radius: 6px; font-weight: bold; font-size: 13px; border-left: 4px solid #f44336;">⚠️ POTENTIAL DUPLICATE<br><small>${_duplicateReasons[groupId] ?? 'Unknown reason'}</small></div>'
          : '';

      return '''
        new google.maps.Marker({
          position: { lat: ${h['latitude']}, lng: ${h['longitude']} },
          map: map,
          title: "${h['headOfFamily']}",
          icon: {
            path: google.maps.SymbolPath.CIRCLE,
            scale: ${isDuplicate ? 14 : 12},
            fillColor: "$fillColor",
            fillOpacity: 0.9,
            strokeColor: "#FFFFFF",
            strokeWeight: 3
          },
          label: { 
            text: "${h['memberCount']}", 
            color: "white", 
            fontSize: "13px", 
            fontWeight: "bold" 
          }
        }).addListener('click', function() {
          new google.maps.InfoWindow({
            content: `
              <div style="padding: 12px; max-width: 300px; font-family: Arial, sans-serif;">
                $duplicateWarningHtml
                <h3 style="margin: 0 0 12px 0; color: #1976D2; font-size: 16px;">${h['headOfFamily']}</h3>
                <div style="background: #f5f5f5; padding: 8px; border-radius: 6px; margin-bottom: 10px;">
                  <p style="margin: 3px 0; font-size: 13px;"><strong>ID:</strong> ${h['id']}</p>
                  <p style="margin: 3px 0; font-size: 13px;"><strong>Location:</strong> ${h['purok']}, ${h['sitio']}</p>
                  <p style="margin: 3px 0; font-size: 13px;"><strong>Coordinates:</strong> ${h['latitude'].toStringAsFixed(6)}, ${h['longitude'].toStringAsFixed(6)}</p>
                  <p style="margin: 3px 0; font-size: 13px;"><strong>Income:</strong> ₱${h['monthlyIncome']}</p>
                </div>
                <p style="margin: 8px 0 6px 0; font-weight: bold; color: #1976D2;">Household Members (${h['memberCount']}):</p>
                <div style="font-size: 12px; max-height: 120px; overflow-y: auto; background: white; padding: 8px; border-radius: 4px; border: 1px solid #ddd;">
                  $members
                </div>
              </div>
            `
          }).open(map, this);
        });
      ''';
    }).join('\n');

    return '''
      <!DOCTYPE html>
      <html>
        <head>
          <style>
            html, body { height: 100%; margin: 0; padding: 0; font-family: Arial, sans-serif; }
            #map { height: 100%; width: 100%; }
            .map-label { 
              text-shadow: 2px 2px 4px rgba(0,0,0,0.7); 
              font-weight: bold;
            }
          </style>
          <script>
            let map;

            function initMap() {
              const center = { lat: $centerLat, lng: $centerLng };

              const ALLOWED_BOUNDS = {
                north: 11.1000, 
                south: 10.8000, 
                west: 119.4000, 
                east: 119.6000, 
              };

              map = new google.maps.Map(document.getElementById("map"), {
                zoom: $mapZoom,
                center: center,
                mapTypeId: 'hybrid', 
                mapTypeControl: true, 
                streetViewControl: false,
                fullscreenControl: false,
                minZoom: 11, 
                maxZoom: 20,
                restriction: {
                  latLngBounds: ALLOWED_BOUNDS,
                  strictBounds: false 
                },
                styles: [
                  {
                    featureType: "all",
                    elementType: "labels",
                    stylers: [{ visibility: "on" }]
                  }
                ]
              });

              const lineSymbol = {
                path: 'M 0,-1 0,1',
                strokeOpacity: 1,
                scale: 4 
              };

              const myLines = [
                [
                  { lng: 119.497199, lat: 10.995486 },
                  { lng: 119.486728, lat: 11.003044 },
                  { lng: 119.473419, lat: 11.009137 },
                  { lng: 119.471693, lat: 11.009732 },
                  { lng: 119.470145, lat: 11.010170 },
                  { lng: 119.447934, lat: 10.942081 },
                  { lng: 119.479279, lat: 10.931058 },
                  { lng: 119.481247, lat: 10.929108 },
                  { lng: 119.483873, lat: 10.929937 },
                  { lng: 119.489145, lat: 10.927547 },
                  { lng: 119.491345, lat: 10.928613 },
                  { lng: 119.496185, lat: 10.927961 }
                ],
                [
                  { lng: 119.494873, lat: 10.994751 },
                  { lng: 119.496218, lat: 10.995702 },
                  { lng: 119.497175, lat: 10.995456 }
                ],
                [
                  { lng: 119.494873, lat: 10.994746 },
                  { lng: 119.494009, lat: 10.993798 },
                  { lng: 119.494103, lat: 10.992767 },
                  { lng: 119.493590, lat: 10.991619 },
                  { lng: 119.493250, lat: 10.991100 },
                  { lng: 119.492766, lat: 10.990819 },
                  { lng: 119.492456, lat: 10.990712 },
                  { lng: 119.492651, lat: 10.989869 },
                  { lng: 119.492775, lat: 10.989002 },
                  { lng: 119.492874, lat: 10.987943 },
                  { lng: 119.492657, lat: 10.986166 },
                  { lng: 119.493812, lat: 10.984087 },
                  { lng: 119.493812, lat: 10.981537 },
                  { lng: 119.493236, lat: 10.980026 },
                  { lng: 119.492931, lat: 10.978987 }
                ],
                [
                  { lng: 119.492931, lat: 10.978975 },
                  { lng: 119.493331, lat: 10.978724 },
                  { lng: 119.493283, lat: 10.978221 },
                  { lng: 119.493026, lat: 10.976902 },
                  { lng: 119.492448, lat: 10.975489 },
                  { lng: 119.492351, lat: 10.974357 },
                  { lng: 119.491197, lat: 10.974262 },
                  { lng: 119.491004, lat: 10.972940 },
                  { lng: 119.491390, lat: 10.971428 },
                  { lng: 119.492256, lat: 10.969538 },
                  { lng: 119.493699, lat: 10.970200 },
                  { lng: 119.494853, lat: 10.970295 },
                  { lng: 119.495334, lat: 10.968783 },
                  { lng: 119.496585, lat: 10.968311 },
                  { lng: 119.494661, lat: 10.967555 },
                  { lng: 119.494853, lat: 10.965383 },
                  { lng: 119.493025, lat: 10.963966 },
                  { lng: 119.491005, lat: 10.964155 },
                  { lng: 119.489370, lat: 10.964344 },
                  { lng: 119.488118, lat: 10.962738 },
                  { lng: 119.488022, lat: 10.961132 },
                  { lng: 119.488503, lat: 10.958298 },
                  { lng: 119.489946, lat: 10.957164 },
                  { lng: 119.491678, lat: 10.955559 },
                  { lng: 119.493121, lat: 10.954236 },
                  { lng: 119.493795, lat: 10.952160 },
                  { lng: 119.494180, lat: 10.949231 },
                  { lng: 119.495527, lat: 10.944885 },
                  { lng: 119.494664, lat: 10.942535 },
                  { lng: 119.494664, lat: 10.937906 },
                  { lng: 119.496011, lat: 10.935167 },
                  { lng: 119.497551, lat: 10.931765 },
                  { lng: 119.497357, lat: 10.928648 },
                  { lng: 119.496298, lat: 10.928176 }
                ],
                [
                  { lng: 119.529230, lat: 10.972703 },
                  { lng: 119.528411, lat: 10.972777 },
                  { lng: 119.527742, lat: 10.972852 },
                  { lng: 119.527889, lat: 10.973726 },
                  { lng: 119.528633, lat: 10.973724 },
                  { lng: 119.529903, lat: 10.973730 },
                  { lng: 119.530949, lat: 10.973441 },
                  { lng: 119.531771, lat: 10.973005 },
                  { lng: 119.532590, lat: 10.973005 },
                  { lng: 119.534081, lat: 10.972785 },
                  { lng: 119.535125, lat: 10.972419 },
                  { lng: 119.536541, lat: 10.972639 },
                  { lng: 119.536764, lat: 10.971907 },
                  { lng: 119.536466, lat: 10.971176 },
                  { lng: 119.535572, lat: 10.971688 },
                  { lng: 119.534826, lat: 10.971541 },
                  { lng: 119.534081, lat: 10.971541 },
                  { lng: 119.533336, lat: 10.972054 },
                  { lng: 119.533187, lat: 10.972712 },
                  { lng: 119.532143, lat: 10.972493 },
                  { lng: 119.531398, lat: 10.972493 },
                  { lng: 119.530575, lat: 10.972928 },
                  { lng: 119.529230, lat: 10.972849 }
                ]
              ];

              myLines.forEach((pathCoordinates) => {
                new google.maps.Polyline({
                  path: pathCoordinates,
                  strokeOpacity: 0, 
                  icons: [{
                    icon: lineSymbol,
                    offset: '0',
                    repeat: '20px' 
                  }],
                  strokeColor: "#FF0000",
                  map: map
                });
              });

              new google.maps.Marker({
                position: center,
                label: {
                  text: "BRGY. PULARAQUEN",
                  color: "white",
                  fontSize: "18px",
                  fontWeight: "bold",
                  className: "map-label"
                },
                icon: { path: google.maps.SymbolPath.CIRCLE, scale: 0 },
                map: map
              });
              
              new google.maps.Marker({
                position: { lat: 10.9728, lng: 119.5320 },
                label: {
                  text: "ISLAND AREA",
                  color: "white",
                  fontSize: "14px",
                  fontWeight: "bold",
                  className: "map-label"
                },
                icon: { path: google.maps.SymbolPath.CIRCLE, scale: 0 },
                map: map
              });

              $markersJs
              
              console.log("Map initialized with ${_households.length} markers");
            }
          </script>
          <script async defer
            src="https://maps.googleapis.com/maps/api/js?key=$apiKey&callback=initMap">
          </script>
        </head>
        <body>
          <div id="map"></div>
        </body>
      </html>
    ''';
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

extension on Color {
  Color? get shade700 => null;
}