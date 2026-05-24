import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:showcaseview/showcaseview.dart';
import '../models/verification_models.dart'; 

class FullScreenVerificationPage extends StatefulWidget {
  const FullScreenVerificationPage({super.key});

  @override
  State<FullScreenVerificationPage> createState() => _FullScreenVerificationPageState();
}

class _FullScreenVerificationPageState extends State<FullScreenVerificationPage> {
  final Color primaryColor = Colors.deepPurple;
  final Color primaryLightColor = Colors.deepPurple.shade100;
  final Color primaryDarkColor = Colors.deepPurple.shade700;
  // --- TUTORIAL KEYS ---
  // Step 1 Keys
  final GlobalKey _stepIndicatorKey = GlobalKey();
  final GlobalKey _idTypeKey = GlobalKey();
  final GlobalKey _nextButtonKey = GlobalKey();
  
  // Step 2 Keys (Photos)
  final GlobalKey _idPhotoKey = GlobalKey();
  final GlobalKey _selfiePhotoKey = GlobalKey();

  // Tutorial State
  bool _hasCheckedTutorialStep1 = false;
  bool _hasCheckedTutorialStep2 = false;
  
  // We store the context provided by ShowCaseWidget here so we can call it later in _goToNextStep
  BuildContext? _myShowcaseContext;

  final Map<String, List<String>> idRequirements = const {
    'Passport': ['Passport Number', 'Expiration Date'],
    'Driver\'s License': ['License Number', 'Expiration Date'],
    'National ID (PhilSys)': ['ID Number'],
    'Barangay ID': ['ID Number', 'Barangay', 'Municipality/City', 'Province'],
    'Voter\'s ID': ['ID Number', 'Municipality/City'],
    'Postal ID': ['ID Number'],
    'SSS ID': ['SSS Number'],
    'GSIS ID': ['GSIS Number'],
    'UMID': ['CRN / ID Number'],
    'PhilHealth ID': ['PhilHealth PIN'],
    'TIN ID (BIR)': ['TIN'],
    'PRC ID': ['PRC License Number'],
    'Senior Citizen ID': ['ID Number', 'Municipality/City'],
    'PWD ID': ['ID Number', 'Municipality/City'],
    'Student ID': ['Student Number', 'School Name'],
    'Company ID': ['Employee ID', 'Company Name'],
    'ACR I-Card': ['ACR Number', 'Expiration Date'],
    'Firearm License ID': ['License Number', 'Expiration Date'],
    'Seafarer\'s ID (SIRB)': ['SIRB Number', 'Expiration Date'],
    'OWWA/OFW ID': ['ID Number'],
    'DFA/Consular ID': ['ID Number'],
    'NBI Clearance': ['Control/Reference Number'],
    'Police Clearance': ['Reference Number', 'Issuing Station/City'],
    'Voter\'s Certificate': ['Reference Number', 'Issuing COMELEC Office'],
    'Birth Certificate': ['Registration Number'],
    'Marriage Certificate': ['Registration Number'],
    'Barangay Clearance': ['Reference Number', 'Barangay', 'Municipality/City'],
    'Other (Document)': ['Document Type', 'Issuing Authority'],
  };

  late final Set<String> documentTypes = {
    'NBI Clearance',
    'Police Clearance',
    'Voter\'s Certificate',
    'Birth Certificate',
    'Marriage Certificate',
    'Barangay Clearance',
    'Other (Document)',
  };

  int currentStep = 0;
  String? selectedIdType;
  final Map<String, TextEditingController> fieldControllers = {};
  File? idImageFile;
  File? selfieImageFile;
  final List<File> supportingDocs = [];
  final ImagePicker _imagePicker = ImagePicker();
  final PageController _pageController = PageController();

  List<String> get _fieldsForSelectedType => selectedIdType == null ? [] : (idRequirements[selectedIdType] ?? []);
  bool get _isSelectedTypeDocument => selectedIdType != null && documentTypes.contains(selectedIdType);
  bool get _areDetailsValid =>
      selectedIdType != null &&
      _fieldsForSelectedType.every((field) => fieldControllers[field]?.text.trim().isNotEmpty ?? false);
  bool get _canSubmit => _areDetailsValid && idImageFile != null && selfieImageFile != null;

  // --- TUTORIAL LOGIC STEP 1 ---
  Future<void> _checkAndStartTutorialStep1(BuildContext showcaseContext) async {
    if (_hasCheckedTutorialStep1) return;
    _hasCheckedTutorialStep1 = true;

    final prefs = await SharedPreferences.getInstance();
    bool hasSeen = prefs.getBool('verification_tutorial_step1') ?? false;

    if (hasSeen) return;

    await Future.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;
    if (ModalRoute.of(context)?.isCurrent != true) return;

    await prefs.setBool('verification_tutorial_step1', true);
    
    ShowCaseWidget.of(showcaseContext).startShowCase([
      _stepIndicatorKey,
      _idTypeKey,
      _nextButtonKey,
    ]);
  }

  // --- TUTORIAL LOGIC STEP 2 (Called when clicking Next) ---
  Future<void> _checkAndStartTutorialStep2() async {
    if (_hasCheckedTutorialStep2 || _myShowcaseContext == null) return;
    
    final prefs = await SharedPreferences.getInstance();
    bool hasSeen = prefs.getBool('verification_tutorial_step2') ?? false;

    if (hasSeen) return;

    _hasCheckedTutorialStep2 = true;
    await prefs.setBool('verification_tutorial_step2', true);

    // Wait for the PageView animation to finish so the widgets are visible
    await Future.delayed(const Duration(milliseconds: 500));
    
    if (!mounted) return;

    ShowCaseWidget.of(_myShowcaseContext!).startShowCase([
      _idPhotoKey,
      _selfiePhotoKey,
    ]);
  }

  Future<ImageSource?> _chooseImageSource() {
    return showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(14))),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: primaryColor.withOpacity(0.06),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
              ),
              child: Row(children: [
                Icon(Icons.photo_camera_back, color: primaryColor),
                const SizedBox(width: 8),
                Text("Choose source", style: GoogleFonts.lato(fontWeight: FontWeight.w700, color: primaryColor)),
              ]),
            ),
            ListTile(
              leading: Icon(Icons.camera_alt, color: primaryDarkColor),
              title: const Text('Camera'),
              onTap: () => Navigator.pop(sheetContext, ImageSource.camera),
            ),
            ListTile(
              leading: Icon(Icons.photo_library, color: primaryDarkColor),
              title: const Text('Gallery'),
              onTap: () => Navigator.pop(sheetContext, ImageSource.gallery),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }



  Future<File?> _pickImage() async {
    final source = await _chooseImageSource();
    if (source == null) return null;
    final XFile? pickedFile = await _imagePicker.pickImage(
      source: source,
      imageQuality: 90,
      maxWidth: 2048,
      maxHeight: 2048,
    );
    return pickedFile != null ? File(pickedFile.path) : null;
  }

  void _previewImage(File imageFile) {
    showDialog(
      context: context,
      builder: (previewContext) => Dialog(
        insetPadding: const EdgeInsets.all(12),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Stack(
          children: [
            Positioned.fill(
              child: InteractiveViewer(
                minScale: 0.8,
                maxScale: 5,
                child: Image.file(imageFile, fit: BoxFit.contain),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: Material(
                color: Colors.black54,
                shape: const CircleBorder(),
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.pop(previewContext),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressHeader() {
    Widget buildDot(int index, String label) {
      final bool isActive = currentStep + 1 >= index;
      final bool isCurrent = currentStep + 1 == index;
      final Color backgroundColor = isActive ? primaryColor : Colors.white;
      final Color outlineColor = isCurrent && !isActive ? primaryColor : (isActive ? primaryColor : Colors.grey.shade300);
      return Expanded(
        child: Column(
          children: [
            Row(children: [
              if (index != 1)
                Expanded(
                  child: Container(
                    height: 2,
                    color: (currentStep + 1) >= (index - 1) ? primaryColor : Colors.grey.shade300,
                  ),
                ),
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: backgroundColor,
                  border: Border.all(color: outlineColor, width: 2),
                  shape: BoxShape.circle,
                  boxShadow: [
                    if (isActive)
                      BoxShadow(
                        color: primaryColor.withOpacity(0.25),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                  ],
                ),
                child: Center(
                  child: isActive
                      ? const Icon(Icons.check, color: Colors.white, size: 16)
                      : Text('$index', style: GoogleFonts.lato(color: outlineColor, fontWeight: FontWeight.w800)),
                ),
              ),
              if (index != 3)
                Expanded(
                  child: Container(
                    height: 2,
                    color: (currentStep + 1) >= index ? primaryColor : Colors.grey.shade300,
                  ),
                ),
            ]),
            const SizedBox(height: 6),
            Text(
              label,
              style: GoogleFonts.lato(fontSize: 11.5, color: isCurrent || isActive ? primaryDarkColor : Colors.black54),
            ),
          ],
        ),
      );
    }

    return Showcase(
      key: _stepIndicatorKey,
      title: 'Progress Tracker',
      description: 'Follow these 3 steps to complete your verification.',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          buildDot(1, "Type & Details"),
          const SizedBox(width: 6),
          buildDot(2, "Photos"),
          const SizedBox(width: 6),
          buildDot(3, "Review"),
        ]),
      ),
    );
  }

  Widget _buildSectionCard({
    required IconData icon,
    required String title,
    String? subtitle,
    required Widget child,
  }) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: primaryColor.withOpacity(0.03),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                decoration: BoxDecoration(
                  color: primaryColor.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.all(8),
                child: Icon(icon, color: primaryDarkColor, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    title,
                    style: GoogleFonts.lato(fontSize: 15, fontWeight: FontWeight.w800, color: primaryDarkColor),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle, style: GoogleFonts.lato(fontSize: 12.5, color: Colors.black54)),
                  ],
                ]),
              ),
            ]),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }

  List<Widget> _buildDynamicTextFields() {
    if (selectedIdType == null) return [];
    return _fieldsForSelectedType.map((field) {
      fieldControllers.putIfAbsent(field, () => TextEditingController());
      return Padding(
        padding: const EdgeInsets.only(bottom: 12.0),
        child: TextField(
          controller: fieldControllers[field],
          decoration: InputDecoration(
            labelText: field,
            prefixIcon: Icon(Icons.edit_note, color: primaryDarkColor),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            focusedBorder: OutlineInputBorder(
              borderSide: BorderSide(color: primaryColor),
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          onChanged: (_) => setState(() {}),
        ),
      );
    }).toList();
  }

  Widget _buildTypeDetailsStep() {
    final screenHeight = MediaQuery.of(context).size.height;
    final double menuHeight = math.min(720, math.max(360, screenHeight * 0.8));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: primaryColor.withOpacity(0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: primaryColor.withOpacity(0.15)),
          ),
          child: Row(children: [
            Icon(Icons.info_outline, color: primaryDarkColor),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                "Select the ID/document and provide its details.",
                style: GoogleFonts.lato(fontSize: 13, color: primaryDarkColor),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        _buildSectionCard(
          icon: Icons.credit_card,
          title: "Type & Details",
          subtitle: "Choose a type and fill the required fields",
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Showcase(
                key: _idTypeKey,
                title: 'Select ID',
                description: 'Tap here to choose which ID you want to submit.',
                child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  menuMaxHeight: menuHeight,
                  decoration: InputDecoration(
                    labelText: "ID / Document",
                    prefixIcon: Icon(Icons.badge_outlined, color: primaryDarkColor),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: primaryColor),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  ),
                  items: idRequirements.keys
                      .map((idType) => DropdownMenuItem<String>(
                            value: idType,
                            alignment: AlignmentDirectional.centerStart,
                            child: Text(idType, maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.lato()),
                          ))
                      .toList(),
                  selectedItemBuilder: (context) => idRequirements.keys
                      .map((idType) => Align(
                            alignment: Alignment.centerLeft,
                            child: Text(idType, maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.lato()),
                          ))
                      .toList(),
                  onChanged: (value) {
                    if (value == selectedIdType) return;
  
                    for (var controller in fieldControllers.values) {
                      controller.dispose();
                    }
                    fieldControllers.clear();
  
                    setState(() => selectedIdType = value);
                  },
                  value: selectedIdType,
                  hint: const Text("Choose ID / Document"),
                ),
              ),
              const SizedBox(height: 12),
              if (selectedIdType != null) ..._buildDynamicTextFields(),
            ],
          ),
        ),
      ],
    );
  }

  // UPDATED: Added keys for tutorial support
  Widget _buildImageField({
    required String title,
    required String hint,
    required File? imageFile,
    required void Function(File file) onImagePicked,
    required VoidCallback onImageRemoved,
    GlobalKey? tutorialKey, // NEW
    String? tutorialTitle, // NEW
    String? tutorialDesc, // NEW
  }) {
    Widget content = imageFile == null
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              OutlinedButton(
                onPressed: () async {
                  final file = await _pickImage();
                  if (file != null) onImagePicked(file);
                },
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: primaryLightColor),
                  foregroundColor: primaryDarkColor,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.file_upload, color: primaryDarkColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      style: GoogleFonts.lato(color: primaryDarkColor, fontWeight: FontWeight.w700),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 6),
              Text(hint, style: GoogleFonts.lato(fontSize: 12, color: Colors.black54)),
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              GestureDetector(
                onTap: () => _previewImage(imageFile),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: AspectRatio(
                    aspectRatio: title.contains('Selfie') ? 3 / 4 : 16 / 10,
                    child: Stack(
                      children: [
                        Positioned.fill(child: Image.file(imageFile, fit: BoxFit.cover)),
                        Positioned(
                          bottom: 0,
                          left: 0,
                          right: 0,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.bottomCenter,
                                end: Alignment.topCenter,
                                colors: [Colors.black54, Colors.transparent],
                              ),
                            ),
                            child: Row(children: [
                              const Icon(Icons.zoom_in, color: Colors.white70, size: 18),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  'Tap to preview',
                                  style: GoogleFonts.lato(color: Colors.white, fontSize: 12),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  p.basename(imageFile.path),
                                  style: GoogleFonts.lato(color: Colors.white70, fontSize: 12),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.right,
                                ),
                              ),
                            ]),
                          ),
                        ),
                        Positioned(
                          top: 8,
                          right: 8,
                          child: Row(children: [
                            Material(
                              color: primaryColor.withOpacity(0.8),
                              borderRadius: BorderRadius.circular(8),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(8),
                                onTap: () async {
                                  final file = await _pickImage();
                                  if (file != null) onImagePicked(file);
                                },
                                child: const Padding(
                                  padding: EdgeInsets.all(6),
                                  child: Icon(Icons.refresh, color: Colors.white, size: 18),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Material(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(8),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(8),
                                onTap: onImageRemoved,
                                child: const Padding(
                                  padding: EdgeInsets.all(6),
                                  child: Icon(Icons.delete, color: Colors.white, size: 18),
                                ),
                              ),
                            ),
                          ]),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(hint, style: GoogleFonts.lato(fontSize: 12, color: Colors.black54)),
            ],
          );
    
    // Wrap with Showcase if key provided
    if (tutorialKey != null) {
      return Showcase(
        key: tutorialKey,
        title: tutorialTitle!,
        description: tutorialDesc!,
        child: content,
      );
    }
    return content;
  }

  Widget _buildSupportingDocsField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        OutlinedButton.icon(
          onPressed: () async {
            final file = await _pickImage();
            if (file != null) setState(() => supportingDocs.add(file));
          },
          icon: Icon(Icons.add_photo_alternate, color: primaryDarkColor),
          label: Text(
            "Add Supporting Document",
            style: GoogleFonts.lato(color: primaryDarkColor, fontWeight: FontWeight.w700),
          ),
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: primaryLightColor),
            foregroundColor: primaryDarkColor,
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
        if (supportingDocs.isNotEmpty) ...[
          const SizedBox(height: 8),
          SizedBox(
            height: 110,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: supportingDocs.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (_, index) {
                final file = supportingDocs[index];
                return SizedBox(
                  width: 160,
                  child: Stack(children: [
                    Positioned.fill(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.file(file, fit: BoxFit.cover),
                      ),
                    ),
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Material(
                        color: Colors.black54,
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: () => setState(() => supportingDocs.removeAt(index)),
                          child: const Padding(
                            padding: EdgeInsets.all(6),
                            child: Icon(Icons.close, size: 16, color: Colors.white),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [Colors.black54, Colors.transparent],
                          ),
                        ),
                        child: Text(
                          p.basename(file.path),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ),
                    ),
                  ]),
                );
              },
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildPhotosStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionCard(
          icon: Icons.camera_enhance,
          title: _isSelectedTypeDocument ? "Document Photo & Selfie" : "ID Photo & Selfie",
          subtitle: _isSelectedTypeDocument
              ? "Upload a clear document photo and your selfie."
              : "Upload a clear ID photo and your selfie.",
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildImageField(
                title: _isSelectedTypeDocument ? "Document Photo" : "ID Photo",
                hint: _isSelectedTypeDocument
                    ? "Full page visible · No blur/glare · Text readable"
                    : "All corners visible · No glare · Text readable",
                imageFile: idImageFile,
                onImagePicked: (file) => setState(() => idImageFile = file),
                onImageRemoved: () => setState(() => idImageFile = null),
                // Tutorial Step 2: Key 1
                tutorialKey: _idPhotoKey,
                tutorialTitle: 'Upload ID/Document',
                tutorialDesc: 'Tap here to capture or upload a photo of your valid ID.',
              ),
              const SizedBox(height: 16),
              _buildImageField(
                title: "Resident Selfie (with ID/Document)",
                hint: "Good lighting · Face centered · No mask or sunglasses · Holding your ID/Document",
                imageFile: selfieImageFile,
                onImagePicked: (file) => setState(() => selfieImageFile = file),
                onImageRemoved: () => setState(() => selfieImageFile = null),
                // Tutorial Step 2: Key 2
                tutorialKey: _selfiePhotoKey,
                tutorialTitle: 'Upload Selfie',
                tutorialDesc: 'Tap here to upload a selfie holding your ID for verification.',
              ),
              if (_isSelectedTypeDocument) ...[
                const SizedBox(height: 16),
                _buildSupportingDocsField(),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildReviewStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionCard(
          icon: Icons.fact_check,
          title: "Review",
          subtitle: "Double-check before submitting",
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!_areDetailsValid || idImageFile == null || selfieImageFile == null)
                Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange.shade200),
                  ),
                  child: Row(children: [
                    Icon(Icons.warning_amber_outlined, color: Colors.orange.shade800),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        "Some required items are missing. Please complete them before submitting.",
                        style: GoogleFonts.lato(color: Colors.orange.shade800),
                      ),
                    ),
                  ]),
                ),
              Wrap(spacing: 8, runSpacing: 8, children: [
                if (selectedIdType != null)
                  Chip(
                    label: Text("Type: $selectedIdType"),
                    avatar: const Icon(Icons.badge, color: Colors.white, size: 18),
                    backgroundColor: primaryColor,
                    labelStyle: const TextStyle(color: Colors.white),
                  ),
                ..._fieldsForSelectedType.map((field) {
                  final value = fieldControllers[field]?.text ?? '';
                  return Chip(
                    label: Text("$field: $value"),
                    backgroundColor: primaryColor.withOpacity(0.08),
                  );
                }),
                if (_isSelectedTypeDocument && supportingDocs.isNotEmpty)
                  Chip(
                    label: Text("${supportingDocs.length} supporting doc(s)"),
                    backgroundColor: primaryColor.withOpacity(0.08),
                  ),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: AspectRatio(
                      aspectRatio: 16 / 10,
                      child: idImageFile != null
                          ? Image.file(idImageFile!, fit: BoxFit.cover)
                          : Container(color: Colors.grey.shade200),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: AspectRatio(
                      aspectRatio: 3 / 4,
                      child: selfieImageFile != null
                          ? Image.file(selfieImageFile!, fit: BoxFit.cover)
                          : Container(color: Colors.grey.shade200),
                    ),
                  ),
                ),
              ]),
            ],
          ),
        ),
      ],
    );
  }

  void _goToNextStep() {
    if (currentStep == 0 && !_areDetailsValid) return;
    if (currentStep < 2) {
      setState(() => currentStep++);
      _pageController.nextPage(duration: const Duration(milliseconds: 240), curve: Curves.easeOutCubic);
      
      // If we moved to step 1 (Photos), start the specific tutorial for it
      if (currentStep == 1) {
        _checkAndStartTutorialStep2();
      }
    }
  }

  void _goToPreviousStep() {
    if (currentStep > 0) {
      setState(() => currentStep--);
      _pageController.previousPage(duration: const Duration(milliseconds: 240), curve: Curves.easeOutCubic);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool canGoToNextStep = (currentStep == 0 && _areDetailsValid) || (currentStep == 1);
    
    // --- WRAP WITH SHOWCASE WIDGET ---
    return ShowCaseWidget(
      builder: (showcaseContext) {
        // Capture context for Step 2 tutorial usage
        _myShowcaseContext = showcaseContext;
        
        // Trigger Step 1 tutorial immediately
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _checkAndStartTutorialStep1(showcaseContext);
        });

        return Scaffold(
          appBar: AppBar(
            title: Text(
              'Identity Verification',
              style: GoogleFonts.lato(color: Colors.white, fontWeight: FontWeight.w800),
            ),
            centerTitle: true,
            elevation: 0,
            iconTheme: const IconThemeData(color: Colors.white),
            flexibleSpace: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [primaryDarkColor, primaryColor],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),
            backgroundColor: primaryColor,
            leading: IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.pop(context),
              tooltip: 'Close',
            ),
          ),
          body: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: _buildProgressHeader(),
                ),
                Expanded(
                  child: PageView(
                    controller: _pageController,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        child: _buildTypeDetailsStep(),
                      ),
                      SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        child: _buildPhotosStep(),
                      ),
                      SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
                        child: _buildReviewStep(),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          bottomNavigationBar: SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.white, primaryColor.withOpacity(0.04)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 8,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  if (currentStep > 0)
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _goToPreviousStep,
                        icon: const Icon(Icons.arrow_back),
                        label: const Text("Back"),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          side: BorderSide(color: primaryLightColor),
                          foregroundColor: primaryDarkColor,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                  if (currentStep > 0) const SizedBox(width: 12),
                  Expanded(
                    child: Showcase(
                      key: _nextButtonKey,
                      title: 'Navigate',
                      description: 'Tap Next to proceed to uploading photos.',
                      child: ElevatedButton.icon(
                        onPressed: currentStep < 2
                            ? (canGoToNextStep ? _goToNextStep : null)
// ... inside bottomNavigationBar ...
// NEW CODE (Paste this)
: (_canSubmit
    ? () {
        // 1. Create the data object
        final verificationResult = VerificationData(
          idType: selectedIdType,
          fieldControllers: fieldControllers,
          idImageFile: idImageFile,
          selfieImageFile: selfieImageFile,
          supportingDocs: List<File>.from(supportingDocs),
        );
        
        // 2. Just close this screen and pass the data back to UserScreen.
        // UserScreen will handle the Loading and Success dialogs now.
        Navigator.pop(context, verificationResult);
      }
    : null),
                        icon: Icon(currentStep < 2 ? Icons.arrow_forward : Icons.verified_user),
                        label: Text(
                          currentStep < 2 ? "Next" : "Submit",
                          style: GoogleFonts.lato(fontWeight: FontWeight.w700),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    for (var controller in fieldControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }
}