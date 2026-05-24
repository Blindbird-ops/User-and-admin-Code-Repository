import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:admin_window/firebase_service.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cached_network_image/cached_network_image.dart'; // <--- IMPORT THIS

class OrgChartPage extends StatefulWidget {
  final String token; 
  const OrgChartPage({super.key, this.token = ''}); 

  @override
  State<OrgChartPage> createState() => _OrgChartPageState();
}

class _OrgChartPageState extends State<OrgChartPage> {
  final FirebaseService _firebaseService = FirebaseService();
  bool _isLoading = true;

Map<String, String> logos = {
  'left': '',
  'right': '',
};

  Map<String, Map<String, String>> officials = {
    'capt': {'name': '', 'pos': 'Punong Barangay', 'img': ''},
    'dev': {'name': '', 'pos': 'Developer', 'img': ''},
    'treas': {'name': '', 'pos': 'Barangay Treasurer', 'img': ''},
    'sec': {'name': '', 'pos': 'Barangay Secretary', 'img': ''},
    'admin': {'name': '', 'pos': 'Barangay Admin', 'img': ''},
    'clerk': {'name': '', 'pos': 'Barangay Clerk', 'img': ''},
    'acct': {'name': '', 'pos': 'Barangay Accountant\nClerk', 'img': ''},
    'kgd_women': {'name': '', 'pos': 'Committee on Women\n& Children', 'img': ''},
    'kgd_approp': {'name': '', 'pos': 'Committee on\nAppropriation', 'img': ''},
    'kgd_health': {'name': '', 'pos': 'Committee on Health', 'img': ''},
    'kgd_peace': {'name': '', 'pos': 'Committee on Peace\n& Order', 'img': ''},
    'kgd_sports': {'name': '', 'pos': 'Committee on Sports', 'img': ''},
    'kgd_educ': {'name': '', 'pos': 'Committee on Education', 'img': ''},
    'kgd_agri': {'name': '', 'pos': 'Committee on\nAgriculture', 'img': ''},
    'sk': {'name': '', 'pos': 'SK Chairman', 'img': ''},
  };

  @override
  void initState() {
    super.initState();
    _loadData();
  }

Future<void> _loadData() async {
  if (widget.token.isEmpty) {
    setState(() => _isLoading = false);
    return;
  }

  try {
    // Load logos first
    final logosData = await _firebaseService.fetchOrgChartLogos(widget.token);
    if (logosData != null && mounted) {
      setState(() {
        logos['left'] = logosData['left']?.toString() ?? '';
        logos['right'] = logosData['right']?.toString() ?? '';
      });
    }

    // Then load officials
    final data = await _firebaseService.fetchOrgChart(widget.token);
    if (data.isNotEmpty && mounted) {
      setState(() {
        data.forEach((key, value) {
          if (officials.containsKey(key)) {
            officials[key]!['name'] = value['name'] ?? '';
            officials[key]!['pos'] = value['pos'] ?? officials[key]!['pos']!;
            if (value['img'] != null) {
              officials[key]!['img'] = value['img'];
            }
          }
        });
      });
    }
  } catch (e) {
    print("Error loading org chart: $e");
  } finally {
    if (mounted) setState(() => _isLoading = false);
  }
}

  Future<String?> _uploadImageToFirebase(XFile imageFile, String officialId) async {
    try {
      final String fileName = '${officialId}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final Reference ref = FirebaseStorage.instance.ref().child('org_chart').child(fileName);
      await ref.putFile(File(imageFile.path));
      return await ref.getDownloadURL();
    } catch (e) {
      print("Firebase Storage Upload Error: $e");
      return null;
    }
  }
// Add UI for logos (put this in your build method, perhaps at the top):

  void _showEditDialog(String id) {
    final nameController = TextEditingController(text: officials[id]!['name']);
    final positionController = TextEditingController(text: officials[id]!['pos']);
    
    XFile? pickedImage;
    bool isUploading = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            
            ImageProvider? imageProvider;
            if (pickedImage != null) {
              imageProvider = FileImage(File(pickedImage!.path));
            } else if (officials[id]!['img']!.isNotEmpty) {
              // --- CACHED IMAGE PROVIDER ---
              imageProvider = CachedNetworkImageProvider(officials[id]!['img']!);
            }

            return AlertDialog(
              title: const Text("Edit Official Details"),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    onTap: () async {
                      final ImagePicker picker = ImagePicker();
                      final XFile? image = await picker.pickImage(source: ImageSource.gallery);
                      if (image != null) {
                        setStateDialog(() {
                          pickedImage = image;
                        });
                      }
                    },
                    child: CircleAvatar(
                      radius: 40,
                      backgroundColor: Colors.grey.shade300,
                      backgroundImage: imageProvider,
                      child: imageProvider == null 
                          ? const Icon(Icons.person, size: 50, color: Colors.white) 
                          : const Icon(Icons.camera_alt, size: 30, color: Colors.white70),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text("Tap image to change", style: TextStyle(fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 15),
                  
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(labelText: "Full Name", border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: positionController,
                    decoration: const InputDecoration(labelText: "Position", border: OutlineInputBorder()),
                  ),
                  if (isUploading) ...[
                    const SizedBox(height: 15),
                    const CircularProgressIndicator(),
                    const SizedBox(height: 5),
                    const Text("Uploading image..."),
                  ]
                ],
              ),
              actions: [
                if (!isUploading)
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text("Cancel"),
                  ),
                if (!isUploading)
                  ElevatedButton(
                    onPressed: () async {
                      setStateDialog(() => isUploading = true);

                      String currentImg = officials[id]!['img']!;
                      
                      if (pickedImage != null) {
                        String? downloadUrl = await _uploadImageToFirebase(pickedImage!, id);
                        if (downloadUrl != null) {
                          currentImg = downloadUrl;
                        } else {
                          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Failed to upload image. Please try again.")));
                          setStateDialog(() => isUploading = false);
                          return;
                        }
                      }

                      try {
                        if (widget.token.isNotEmpty) {
                          await _firebaseService.updateOrgChartOfficial(widget.token, id, {
                            'name': nameController.text,
                            'pos': positionController.text,
                            'img': currentImg,
                          });
                        }

                        setState(() {
                          officials[id]!['name'] = nameController.text;
                          officials[id]!['pos'] = positionController.text;
                          officials[id]!['img'] = currentImg;
                        });

                        if (mounted) Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Saved successfully!")));
                      } catch (e) {
                        setStateDialog(() => isUploading = false);
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error saving: $e")));
                      }
                    },
                    child: const Text("Save Changes"),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    const double canvasWidth = 1800;
    const double canvasHeight = 1300;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Organizational Chart"),
        backgroundColor: Colors.blue.shade900,
        foregroundColor: Colors.white,
        // REMOVED: Settings button - no longer needed
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.blue.shade50, Colors.white],
              ),
            ),
            child: Column(
              children: [
                _buildOfficialHeader(), // Direct tap to change logos
                const Divider(height: 1, color: Colors.grey),
                Expanded(
                  child: InteractiveViewer(
                    boundaryMargin: const EdgeInsets.all(100),
                    minScale: 0.1,
                    maxScale: 4.0,
                    constrained: false,
                    child: SizedBox(
                      width: canvasWidth,
                      height: canvasHeight,
                      child: Stack(
                        children: [
                          CustomPaint(
                            size: const Size(canvasWidth, canvasHeight),
                            painter: OrgChartLinePainter(),
                          ),
                      
                      _posCard('dev', 300, 50, color: Colors.grey),
                      _posCard('capt', 600, 50, isBig: true),

                      _posCard('admin', 50, 250),
                      _posCard('treas', 300, 250, color: Colors.blue),
                      _posCard('sec', 850, 250, color: Colors.blue),
                      
                      _posCard('clerk', 1350, 250), 
                      _posCard('acct', 1350, 450), 

                      _posCard('kgd_approp', 300, 450, color: Colors.teal),
                      _posCard('kgd_women', 600, 450, color: Colors.teal), 
                      _posCard('kgd_health', 900, 450, color: Colors.teal),

                      _posCard('kgd_sports', 300, 700, color: Colors.teal),
                      _posCard('kgd_peace', 600, 700, color: Colors.teal), 
                      _posCard('kgd_educ', 900, 700, color: Colors.teal),

                      _posCard('kgd_agri', 300, 950, color: Colors.teal),
                      _posCard('sk', 850, 950, color: Colors.teal),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.pop(context),
        label: const Text("Back"),
        icon: const Icon(Icons.arrow_back),
        backgroundColor: Colors.blue.shade900,
        foregroundColor: Colors.white,
      ),
    );
  }

  // NEW: Dialog for logo settings
  // SIMPLIFIED: Direct upload when tapping logo
  Future<void> _pickAndUploadLogo(String key) async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    
    if (image != null) {
      // Show loading indicator
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );
      
      String? downloadUrl = await _uploadImageToFirebase(image, 'logo_$key');
      
      // Remove loading indicator
      Navigator.pop(context);
      
      if (downloadUrl != null) {
        await _firebaseService.updateOrgChartLogo(widget.token, key, downloadUrl);
        setState(() => logos[key] = downloadUrl);
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("${key == 'left' ? 'Left' : 'Right'} logo updated successfully!"),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Failed to upload image. Please try again."),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // UPDATED: Header with direct tap action
  Widget _buildOfficialHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 15),
      color: Colors.white,
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // LEFT LOGO - Tap directly to change
              _buildEditableLogo(
                imageUrl: logos['left']!,
                onTap: () => _pickAndUploadLogo('left'),
                label: 'Left',
              ),
              
              const SizedBox(width: 15),
              
              // Center Text
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("REPUBLIC OF THE PHILIPPINES", 
                      style: TextStyle(fontSize: 11, letterSpacing: 1.2, color: Colors.grey.shade800)),
                  Text("BARANGAY PULARAQUEN", 
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.blue.shade900)),
                  const SizedBox(height: 2),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    color: Colors.amber.shade700,
                    child: const Text("ORGANIZATIONAL CHART", 
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white)),
                  ),
                ],
              ),
              
              const SizedBox(width: 15),
              
              // RIGHT LOGO - Tap directly to change
              _buildEditableLogo(
                imageUrl: logos['right']!,
                onTap: () => _pickAndUploadLogo('right'),
                label: 'Right',
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Simple hint text
          Text(
            "Tap logo to change",
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontStyle: FontStyle.italic),
          ),
        ],
      ),
    );
  }

  // NEW: Reusable widget for editable logos with visual cue
  // REUSABLE: Logo widget with edit indicator
  Widget _buildEditableLogo({
    required String imageUrl,
    required VoidCallback onTap,
    required String label,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // The Logo Image
            Container(
              height: 70,
              width: 70,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300, width: 1),
                borderRadius: BorderRadius.circular(8),
                color: Colors.grey.shade50,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: imageUrl.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: imageUrl,
                        fit: BoxFit.contain,
                        placeholder: (c, u) => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                        errorWidget: (c, u, e) => const Icon(Icons.shield, size: 50, color: Colors.grey),
                      )
                    : const Icon(Icons.shield, size: 50, color: Colors.grey),
              ),
            ),
            
            // Edit Badge (pen icon)
            Positioned(
              bottom: 0,
              right: 0,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.deepPurple,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(4),
                child: const Icon(
                  Icons.edit,
                  size: 16,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _posCard(String id, double left, double top, {Color? color, bool isBig = false}) {
    double w = 220;
    double h = 120;
    if (isBig) { w = 240; h = 140; }

    return Positioned(
      left: left,
      top: top,
      child: _buildCardWidget(id, w, h, color ?? Colors.grey.shade700, isBig),
    );
  }

  Widget _buildCardWidget(String id, double w, double h, Color color, bool isBig) {
    final data = officials[id]!;
    bool hasImage = data['img'] != null && data['img']!.isNotEmpty;
    
    return Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color, width: isBig ? 2.5 : 1),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 5, offset: Offset(0, 3))
        ],
      ),
      child: Stack(
        children: [
          Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 6),
                color: color.withOpacity(0.1),
                child: Text(
                  data['pos']!.toUpperCase(),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color),
                ),
              ),
              const Spacer(),
              CircleAvatar(
                radius: 22,
                backgroundColor: Colors.grey.shade200,
                // --- USE CACHED IMAGE PROVIDER ---
                backgroundImage: hasImage 
                    ? CachedNetworkImageProvider(data['img']!) 
                    : null,
                child: hasImage ? null : const Icon(Icons.person, size: 30, color: Colors.grey),
              ),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  data['name']!.isEmpty ? "(VACANT)" : data['name']!,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: data['name']!.isEmpty ? Colors.grey : Colors.black87,
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
          Positioned(
            right: 0,
            top: 0,
            child: IconButton(
              icon: const Icon(Icons.edit, size: 16, color: Colors.grey),
              onPressed: () => _showEditDialog(id),
            ),
          )
        ],
      ),
    );
  }

  // ... (OrgChartLinePainter and _buildOfficialHeader remain same) ...
}

class OrgChartLinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black87
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    _drawDottedLine(canvas, const Offset(520, 110), const Offset(600, 110));
    canvas.drawLine(const Offset(720, 190), const Offset(720, 450), paint);
    canvas.drawLine(const Offset(520, 310), const Offset(850, 310), paint);
    canvas.drawLine(const Offset(270, 310), const Offset(300, 310), paint);
    canvas.drawLine(const Offset(1070, 310), const Offset(1350, 310), paint);
    canvas.drawLine(const Offset(1460, 370), const Offset(1460, 450), paint);
    canvas.drawLine(const Offset(520, 510), const Offset(600, 510), paint);
    canvas.drawLine(const Offset(820, 510), const Offset(900, 510), paint);
    canvas.drawLine(const Offset(710, 570), const Offset(710, 700), paint);
    canvas.drawLine(const Offset(520, 760), const Offset(600, 760), paint);
    canvas.drawLine(const Offset(820, 760), const Offset(900, 760), paint);
    canvas.drawLine(const Offset(710, 820), const Offset(710, 900), paint);
    canvas.drawLine(const Offset(410, 900), const Offset(960, 900), paint);
    canvas.drawLine(const Offset(410, 900), const Offset(410, 950), paint);
    canvas.drawLine(const Offset(960, 900), const Offset(960, 950), paint);
  }

  void _drawDottedLine(Canvas canvas, Offset p1, Offset p2) {
    final paint = Paint()
      ..color = Colors.black54
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    
    double dashWidth = 5, dashSpace = 5;
    double startX = p1.dx;
    while (startX < p2.dx) {
      canvas.drawLine(Offset(startX, p1.dy), Offset(startX + dashWidth, p1.dy), paint);
      startX += dashWidth + dashSpace;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}