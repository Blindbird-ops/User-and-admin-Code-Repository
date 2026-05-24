import 'package:admin_window/admin_screen.dart';
import 'package:admin_window/services/python_service.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'secretary_offline_form_page.dart';
import 'secretary_offline_request_list_page.dart';

class SecretaryOfflinePage extends StatefulWidget {
  final String? firebaseToken;
  final String? userId;

  const SecretaryOfflinePage({
    super.key,
    this.firebaseToken,
    this.userId,
  });

  @override
  _SecretaryOfflinePageState createState() => _SecretaryOfflinePageState();
}

class _DocumentTile {
  final String id;
  final String title;
  final String description;
  final IconData icon;

  const _DocumentTile(this.id, this.title, this.description, this.icon);
}

class _DocumentCard extends StatelessWidget {
  final _DocumentTile tile;
  final VoidCallback onTap;

  const _DocumentCard({required this.tile, required this.onTap});

  @override
  Widget build(BuildContext context) {
    // --- IMAGE MAPPING ---
    final Map<String, String> assetImages = {
      'business': 'assets/business_clearance.png',
      'indigent': 'assets/barangay_indigent.png',
      'certification': 'assets/certification.png',
      'clearance': 'assets/clearance.png',
      'Certificate': 'assets/certification_late_registration.png',
      'cohabitation': 'assets/cohabitation.png',
      'seaweeds': 'assets/seaweeds.png',
    };

    final String? imagePath = assetImages[tile.id];

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 6,
        color: Colors.white,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 12.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // --- ICON / IMAGE CONTAINER ---
              CircleAvatar(
                radius: 65,
                backgroundColor: imagePath != null
                    ? Colors.transparent
                    : Colors.deepPurple.shade50,
                backgroundImage: imagePath != null
                    ? AssetImage(imagePath)
                    : null,
                child: imagePath != null
                    ? null
                    : Icon(tile.icon, color: Colors.deepPurple, size: 80),
              ),
              const SizedBox(height: 12),
              // --- TITLE ---
              Text(
                tile.title,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: Colors.deepPurple,
                ),
              ),
              const SizedBox(height: 4),
              // --- DESCRIPTION ---
              Text(
                tile.description,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: Colors.grey[700]),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SecretaryOfflinePageState extends State<SecretaryOfflinePage> {
  final List<_DocumentTile> _tiles = const [
    _DocumentTile('indigent', 'Barangay Indigent', 'Certificate for indigent status', Icons.info_outline),
    _DocumentTile('business', 'Barangay Business Clearance', 'Business clearance for permits', Icons.business),
    _DocumentTile('certification', 'Barangay Certification', 'Certification document', Icons.verified),
    _DocumentTile('clearance', 'Barangay Clearance', 'General clearance', Icons.card_membership),
    _DocumentTile('Certificate', 'Certification for Late Registration', 'Late Registration document', Icons.cake_outlined),
    _DocumentTile('cohabitation', 'Certificate of Cohabitation', 'Live-in partner certificate', Icons.favorite),
    _DocumentTile('seaweeds', 'Certificate of Seaweeds', 'Seaweed transaction record', Icons.grass),
  ];

  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  bool _online = true;

  @override
  void initState() {
    super.initState();
    _ensurePythonRunning();
    _checkConnectivity();
    _searchController.addListener(() {
      setState(() {
        _query = _searchController.text;
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _checkConnectivity() async {
    final result = await Connectivity().checkConnectivity();
    final bool online = result != ConnectivityResult.none;
    if (mounted) {
      setState(() => _online = online);
    }
  }
  Future<void> _ensurePythonRunning() async {
    if (!PythonBackendService.isRunning) {
      print('🚀 Offline Mode: Starting Python backend...');
      await PythonBackendService.start();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Document generator ready (Offline Mode)"),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }
  // --- UPDATED NAVIGATION FUNCTION ---
  // --- UPDATED: LARGE DESKTOP NAVIGATION FUNCTION ---
  Future<void> _goToOnlineDashboard() async {
    // 1. Check Connectivity first
    final result = await Connectivity().checkConnectivity();

    if (result == ConnectivityResult.none) {
      if (!mounted) return;
      
      // --- A. SHOW LARGE ERROR DIALOG (NO INTERNET) ---
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
          elevation: 0,
          backgroundColor: Colors.transparent,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.topCenter,
            children: [
              Container(
                width: 600, // Wide for Desktop
                padding: const EdgeInsets.only(top: 90, left: 40, right: 40, bottom: 40),
                margin: const EdgeInsets.only(top: 70),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(25),
                  boxShadow: const [
                    BoxShadow(color: Colors.black26, blurRadius: 15.0, offset: Offset(0.0, 15.0)),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      "Connection Error",
                      style: TextStyle(
                        fontSize: 28, 
                        fontWeight: FontWeight.bold, 
                        color: Colors.redAccent
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      "Cannot Switch to Online Mode",
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      "We cannot detect an active internet connection.\nPlease check your WiFi or LAN cable and try again.",
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 16, color: Colors.black54, height: 1.5),
                    ),
                    const SizedBox(height: 30),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 18),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: const Text("Okay, I'll Check"),
                    ),
                  ],
                ),
              ),
              Positioned(
                top: 0,
                child: CircleAvatar(
                  backgroundColor: Colors.redAccent,
                  radius: 65,
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 5),
                    ),
                    child: const Center(
                      child: Icon(Icons.wifi_off_rounded, size: 70, color: Colors.white),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    } else {
      if (!mounted) return;
      
      // --- B. SHOW LARGE CONFIRMATION DIALOG (SWITCH ONLINE) ---
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
          elevation: 0,
          backgroundColor: Colors.transparent,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.topCenter,
            children: [
              Container(
                width: 650, // Wide for Desktop
                padding: const EdgeInsets.only(top: 100, left: 50, right: 50, bottom: 50),
                margin: const EdgeInsets.only(top: 80),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(25),
                  boxShadow: const [
                    BoxShadow(color: Colors.black26, blurRadius: 15.0, offset: Offset(0.0, 15.0)),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      "Return to Online Mode",
                      style: TextStyle(
                        fontSize: 32, 
                        fontWeight: FontWeight.bold, 
                        color: Colors.deepPurple,
                        letterSpacing: 1.1,
                      ),
                    ),
                    const SizedBox(height: 25),
                    const Text(
                      "Are you sure you want to leave Offline Mode?",
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: Colors.black87),
                    ),
                    const SizedBox(height: 15),
                    const Text(
                      "You will return to the main dashboard. Don't forget to sync any offline requests you may have saved.",
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 18, color: Colors.black54, height: 1.5),
                    ),
                    const SizedBox(height: 45),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.of(ctx).pop(),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.grey[700],
                            padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 20),
                            textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          child: const Text("Stay Offline"),
                        ),
                        const SizedBox(width: 20),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.deepPurple,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 22),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            elevation: 8,
                            textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
onPressed: () {
  Navigator.of(ctx).pop(); // Close the confirmation dialog
  
  if (Navigator.canPop(context)) {
    // Normal case: Go back to existing AdminScreen
    Navigator.pop(context);
  } else {
    // BUG FIX: We came from LoginScreen via pushReplacement
    // Navigate to AdminScreen and remove the offline page
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => AdminScreen(
          token: widget.firebaseToken!,
          userId: widget.userId!,
          email: 'Secretary', // Or get from SharedPreferences if you stored it
        ),
      ),
    );
  }
},
                          icon: const Icon(Icons.wifi_rounded, size: 28),
                          label: const Text("Yes, Go Online"),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Positioned(
                top: 0,
                child: CircleAvatar(
                  backgroundColor: Colors.deepPurple,
                  radius: 75,
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 6),
                    ),
                    child: const Center(
                      child: Icon(Icons.cloud_queue_rounded, size: 80, color: Colors.white),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
  }
  
  
  void _openOfflineForm(String docTitle) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SecretaryOfflineFormPage(documentType: docTitle),
      ),
    );
  }

  void _openOfflineRequests() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SecretaryOfflineRequestListPage(
          firebaseToken: widget.firebaseToken,
          userId: widget.userId,
        ),
      ),
    );
  }

  bool get hasToken => widget.firebaseToken != null && widget.firebaseToken!.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final filtered = _tiles
        .where((t) => t.title.toLowerCase().contains(_query.toLowerCase()))
        .toList();

    final isWide = MediaQuery.of(context).size.width > 900;
    final crossCount = isWide ? 3 : 2;

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        backgroundColor: Colors.deepPurple,
        automaticallyImplyLeading: false, 
        
        // --- TITLE ---
        title: const Text("Offline Mode", style: TextStyle(color: Colors.white)),
        
        actions: [
          // --- SWITCH TO ONLINE BUTTON ---
          TextButton.icon(
            onPressed: _goToOnlineDashboard,
            icon: const Icon(Icons.wifi, color: Colors.white),
            label: const Text(
              "Go Online", 
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)
            ),
            style: TextButton.styleFrom(
              backgroundColor: Colors.white.withOpacity(0.2),
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
          ),
          
          const SizedBox(width: 8),

          // --- OFFLINE REQUESTS BUTTON ---
          IconButton(
            icon: const Icon(Icons.list, color: Colors.white),
            tooltip: 'Offline Requests',
            onPressed: _openOfflineRequests,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          if (!hasToken)
            Container(
              width: double.infinity,
              color: _online ? Colors.green.shade50 : Colors.amber.shade100,
              padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 12.0),
              child: Text(
                _online ? 'Offline ready: working with cached data' : 'Offline mode active',
                textAlign: TextAlign.center,
              ),
            ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 24.0),
            child: const Text(
              "Offline Documents",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.deepPurple),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Filter documents',
                border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(8))),
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: GridView.builder(
                padding: EdgeInsets.zero,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossCount,
                  crossAxisSpacing: 20,
                  mainAxisSpacing: 20,
                  childAspectRatio: 0.75,
                ),
                itemCount: filtered.length,
                itemBuilder: (context, index) {
                  final tile = filtered[index];
                  return _DocumentCard(
                    tile: tile,
                    onTap: () => _openOfflineForm(tile.title),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}