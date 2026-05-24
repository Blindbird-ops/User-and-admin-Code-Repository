import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:showcaseview/showcaseview.dart';
import 'psgc_api_service.dart'; 
// Ensure you import the package
import 'package:dropdown_search/dropdown_search.dart'; 

// --- 1. UPDATED ICON LOGIC ---
Widget getDocumentIcon(String documentType, {double size = 48, Color? color}) {
  String? assetPath;
  switch (documentType) {
    case 'Barangay Business Clearance':
      assetPath = 'assets/icons/business_clearance.png';
      break;
    case 'Barangay Indigent':
      assetPath = 'assets/icons/barangay_indigent.png';
      break;
    case 'Certification (Late) Registration':
      assetPath = 'assets/icons/certification_late_registration.png';
      break;
    case 'Barangay Clearance':
      assetPath = 'assets/icons/clearance.png';
      break;
    case 'Barangay Certification':
      assetPath = 'assets/icons/certification.png';
      break;
    // NEW ICON CASE
    case 'Certificate of Cohabitation':
      assetPath = 'assets/icons/cohabitation.png'; // Make sure to add this icon asset or it will fallback
      break;

    case 'Certificate of Seaweeds':
      assetPath = 'assets/icons/seaweeds.png'; // Ensure you have this icon asset
      break;
  }

  if (assetPath != null) {
    return Image.asset(
      assetPath,
      width: size,
      height: size,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stack) =>
          Icon(Icons.description, size: size, color: color ?? Colors.deepPurple),
    );
  }
  return Icon(Icons.description, size: size, color: color ?? Colors.deepPurple);
}

class TitleCaseTextFormatter extends TextInputFormatter {
  String _applyTitleCase(String input) {
    if (input.isEmpty) return input;
    final buffer = StringBuffer();
    bool capitalizeNext = true;

    for (var i = 0; i < input.length; i++) {
      final char = input[i];
      final isLetter = RegExp(r'[A-Za-z]').hasMatch(char);
      if (isLetter) {
        buffer.write(capitalizeNext ? char.toUpperCase() : char.toLowerCase());
        capitalizeNext = false;
      } else {
        buffer.write(char);
        capitalizeNext = (char == ' ' || char == '-' || char == '\'' || char == '/' || char == '\t' || char == '.');
      }
    }
    return buffer.toString();
  }

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final cased = _applyTitleCase(newValue.text);
    return TextEditingValue(
      text: cased,
      selection: newValue.selection,
      composing: TextRange.empty,
    );
  }
}

class RequestDocumentPage extends StatefulWidget {
  final String token;
  final String uid;
  final String email;

  const RequestDocumentPage({
    super.key,
    required this.token,
    required this.uid,
    required this.email,
  });

  @override
  State<RequestDocumentPage> createState() => _RequestDocumentPageState();
}

String convertToCurrencyWords(double amount) {
  if (amount == 0) return "Zero Pesos Only";
  
  final units = ["", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine"];
  final teens = ["Ten", "Eleven", "Twelve", "Thirteen", "Fourteen", "Fifteen", "Sixteen", "Seventeen", "Eighteen", "Nineteen"];
  final tens = ["", "", "Twenty", "Thirty", "Forty", "Fifty", "Sixty", "Seventy", "Eighty", "Ninety"];
  
  String numToWords(int n) {
    if (n < 10) return units[n];
    if (n < 20) return teens[n - 10];
    if (n < 100) return "${tens[n ~/ 10]} ${units[n % 10]}".trim();
    if (n < 1000) return "${units[n ~/ 100]} Hundred ${numToWords(n % 100)}".trim();
    if (n < 1000000) return "${numToWords(n ~/ 1000)} Thousand ${numToWords(n % 1000)}".trim();
    return "$n"; // Fallback for very large numbers
  }

  int whole = amount.floor();
  int cents = ((amount - whole) * 100).round();
  
  String words = numToWords(whole) + " Pesos";
  if (cents > 0) {
    words += " and $cents/100";
  }
  
  return "$words Only";
}

class _RequestDocumentPageState extends State<RequestDocumentPage> {
  final GlobalKey _firstDocKey = GlobalKey();
  bool _hasCheckedTutorial = false;

  // --- 2. ADDED NEW DOCUMENT TYPE TO LIST ---
  final List<String> _documentTypes = const [
    'Barangay Clearance',
    'Barangay Certification',
    'Barangay Indigent',
    'Barangay Business Clearance',
    'Certification (Late) Registration',
    'Certificate of Cohabitation', // <--- NEW OPTION
    'Certificate of Seaweeds', // <--- MAKE SURE THIS IS HERE
  ];

  Future<void> _checkAndStartTutorial(BuildContext showcaseContext) async {
    if (_hasCheckedTutorial) return;
    _hasCheckedTutorial = true;

    final prefs = await SharedPreferences.getInstance();
    bool hasSeen = prefs.getBool('request_doc_page_tutorial') ?? false;

    if (hasSeen) return;

    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;
    if (ModalRoute.of(context)?.isCurrent != true) return;

    await prefs.setBool('request_doc_page_tutorial', true);
    
    ShowCaseWidget.of(showcaseContext).startShowCase([_firstDocKey]);
  }

  void _openRequestForm(String documentType) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: ShowCaseWidget(
            builder: (context) => DocumentRequestForm(
              token: widget.token,
              uid: widget.uid,
              email: widget.email,
              documentType: documentType,
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final purple = Colors.deepPurple;
    return ShowCaseWidget(
      builder: (showcaseContext) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _checkAndStartTutorial(showcaseContext);
        });

        return Scaffold(
          appBar: AppBar(
            title: const Text("Request Document"),
            backgroundColor: purple,
            foregroundColor: Colors.white,
          ),
          body: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [purple.shade400, purple.shade200],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
            child: Column(
              children: [
                const SizedBox(height: 16),
                const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text(
                    "Select a Document",
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white, shadows: [
                      Shadow(blurRadius: 4, color: Colors.black26, offset: Offset(2, 2)),
                    ]),
                  ),
                ),
                Expanded(
                  child: GridView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2, crossAxisSpacing: 16, mainAxisSpacing: 16, childAspectRatio: 1.0,
                    ),
                    itemCount: _documentTypes.length,
                    itemBuilder: (context, index) {
                      final docType = _documentTypes[index];
                      Widget gridItem = GestureDetector(
                        onTap: () => _openRequestForm(docType),
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            gradient: LinearGradient(
                              colors: [Colors.white, Colors.grey.shade200],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(2, 2))],
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              getDocumentIcon(docType, size: 48, color: purple),
                              const SizedBox(height: 12),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                                child: Text(
                                  docType,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: purple.shade900),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );

                      if (index == 0) {
                        return Showcase(
                          key: _firstDocKey,
                          title: 'Select Document',
                          description: 'Tap on a card to start filling out the request form.',
                          targetBorderRadius: BorderRadius.circular(16),
                          child: gridItem,
                        );
                      }
                      return gridItem;
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}


class DocumentRequestForm extends StatefulWidget {
  final String token;
  final String uid;
  final String email;
  final String documentType;

  const DocumentRequestForm({
    super.key,
    required this.token,
    required this.uid,
    required this.email,
    required this.documentType,
  });

  @override
  State<DocumentRequestForm> createState() => _DocumentRequestFormState();
}

class _DocumentRequestFormState extends State<DocumentRequestForm> {
  final _formKey = GlobalKey<FormState>();

  // --- TUTORIAL KEYS ---
  final GlobalKey _termsKey = GlobalKey();
  final GlobalKey _submitKey = GlobalKey();

  // Profile data
  String? _userTitle;
  String? _userFirstName;
  String? _userMiddleName;
  String? _userLastName;
  String? _userBirthDate; 

  // Flags
  bool _isLoadingProfile = true;
  bool _isSubmitting = false;
  bool _profileLoadFailed = false;
  bool _useManualAddress = false;
  bool _isAgreementChecked = false;

  // Controllers (Business)
  final TextEditingController _businessNameController = TextEditingController();
  final TextEditingController _operatorController = TextEditingController();
  final TextEditingController _operatorAddressController = TextEditingController();
  final TextEditingController _streetAddressController = TextEditingController();

  // Manual address
  final TextEditingController _manualProvinceController = TextEditingController();
  final TextEditingController _manualMunicipalityController = TextEditingController();
  final TextEditingController _manualBarangayController = TextEditingController();

  // Controllers (Late Reg)
  final TextEditingController _birthDateController = TextEditingController();
  final TextEditingController _placeOfBirthController = TextEditingController();
  final TextEditingController _fatherNameController = TextEditingController();
  final TextEditingController _motherNameController = TextEditingController();

  // Controllers (Cohabitation)
  final TextEditingController _partnerNameController = TextEditingController();
  final TextEditingController _partnerBirthDateController = TextEditingController();
  final TextEditingController _cohabitationStartDateController = TextEditingController();
  final TextEditingController _requesterBirthDateController = TextEditingController();

  // Controllers (Seaweeds)
  final TextEditingController _seaweedsBuyerController = TextEditingController();
  final TextEditingController _seaweedsQuantityController = TextEditingController();
  final TextEditingController _seaweedsAmountFiguresController = TextEditingController();
  final TextEditingController _seaweedsAmountWordsController = TextEditingController(); // Not used directly in UI but kept for logic
  String? _selectedSeaweedsUnit;

  // PSGC
  final PsgcApiService _psgcApiService = PsgcApiService();
  List<Province> _provinces = [];
  List<Municipality> _municipalities = [];
  List<Barangay> _barangays = [];
  Province? _selectedProvince;
  Municipality? _selectedMunicipality;
  Barangay? _selectedBarangay;
  bool _isProvincesLoading = false;
  bool _isMunicipalitiesLoading = false;
  bool _isBarangaysLoading = false;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  // --- TUTORIAL LOGIC ---
  Future<void> _checkAndStartFormTutorial() async {
    final prefs = await SharedPreferences.getInstance();
    bool hasSeen = prefs.getBool('doc_form_tutorial') ?? false;

    if (hasSeen) return;

    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;

    await prefs.setBool('doc_form_tutorial', true);

    ShowCaseWidget.of(context).startShowCase([_termsKey, _submitKey]);
  }

  @override
  void dispose() {
    _businessNameController.dispose();
    _operatorController.dispose();
    _operatorAddressController.dispose();
    _streetAddressController.dispose();
    _manualProvinceController.dispose();
    _manualMunicipalityController.dispose();
    _manualBarangayController.dispose();
    _birthDateController.dispose();
    _placeOfBirthController.dispose();
    _fatherNameController.dispose();
    _motherNameController.dispose();
    _partnerNameController.dispose();
    _partnerBirthDateController.dispose();
    _cohabitationStartDateController.dispose();
    _requesterBirthDateController.dispose();
    _seaweedsBuyerController.dispose();
    _seaweedsQuantityController.dispose();
    _seaweedsAmountFiguresController.dispose();
    _seaweedsAmountWordsController.dispose();
    super.dispose();
  }

  // ... (Helper methods kept same) ...
  String _toTitleCase(String? text) {
    if (text == null || text.isEmpty) return '';
    final normalized = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return normalized.split(' ').map((w) => w.isEmpty ? '' : w[0].toUpperCase() + w.substring(1).toLowerCase()).join(' ');
  }

  String _getFullNameWithoutTitle() {
    final parts = <String>[];
    if ((_userFirstName ?? '').isNotEmpty) parts.add(_toTitleCase(_userFirstName));
    if ((_userMiddleName ?? '').isNotEmpty) parts.add(_toTitleCase(_userMiddleName));
    if ((_userLastName ?? '').isNotEmpty) parts.add(_toTitleCase(_userLastName));
    return parts.join(' ');
  }

  String _formatCertDate(DateTime date) {
    const months = ['JANUARY','FEBRUARY','MARCH','APRIL','MAY','JUNE','JULY','AUGUST','SEPTEMBER','OCTOBER','NOVEMBER','DECEMBER'];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  String _formatFromIsoOrRaw(String? raw) {
    if (raw == null || raw.trim().isEmpty) return '';
    final dt = DateTime.tryParse(raw);
    if (dt != null) return _formatCertDate(dt);
    return raw;
  }

  String _composePlaceOfBirthFromProfile(Map<String, dynamic>? data) {
    if (data == null) return '';
    final parts = [
      (data['barangay'] ?? '').toString().trim(),
      (data['municipality'] ?? '').toString().trim(),
      (data['province'] ?? '').toString().trim(),
    ].where((e) => e.isNotEmpty).map(_toTitleCase).toList();
    return parts.join(', ');
  }

  String _getFormattedBusinessAddress() {
    if (_useManualAddress) {
      final street = _streetAddressController.text.trim();
      final brgy = _manualBarangayController.text.trim();
      final muni = _manualMunicipalityController.text.trim();
      final prov = _manualProvinceController.text.trim();
      return [street, brgy, muni, prov].where((e) => e.isNotEmpty).join(', ');
    }
    final street = _streetAddressController.text.trim();
    final brgy = _selectedBarangay?.name ?? '';
    final muni = _selectedMunicipality?.name ?? '';
    final prov = _selectedProvince?.name ?? '';
    return [street, brgy, muni, prov].where((e) => e.isNotEmpty).join(', ');
  }

  // --- Dynamic Decoration for Dropdowns ---
  InputDecoration _getDropdownDecoration(String label, IconData icon, bool isEnabled, bool isLoading) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: isEnabled ? Colors.blue.shade700 : Colors.grey),
      suffixIcon: isLoading
          ? const Padding(
              padding: EdgeInsets.all(10.0),
              child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.0)),
            )
          : null,
      filled: true,
      fillColor: isEnabled ? Colors.blue.shade50 : Colors.grey.shade100,
      labelStyle: TextStyle(
        color: isEnabled ? Colors.blue.shade900 : Colors.grey.shade600,
        fontWeight: isEnabled ? FontWeight.bold : FontWeight.normal,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(
          color: isEnabled ? Colors.blue.shade200 : Colors.grey.shade300,
          width: 1.5,
        ),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Colors.grey.shade200, width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Colors.blue, width: 2),
      ),
    );
  }

  Future<void> _loadInitialData() async {
    if (mounted) {
      setState(() {
        _isLoadingProfile = true;
        _profileLoadFailed = false; 
      });
    }

    final url = 'https://mabskie-47c24-default-rtdb.firebaseio.com/users/${widget.uid}.json?auth=${widget.token}';

    try {
      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 12));
      if (!mounted) return;

      if (response.statusCode == 200 && response.body.isNotEmpty && response.body != 'null') {
        final data = json.decode(response.body) as Map<String, dynamic>?;

        _userTitle = data?['title']?.toString() ?? '';
        _userFirstName = data?['firstName']?.toString() ?? '';
        _userMiddleName = data?['middleName']?.toString() ?? '';
        _userLastName = data?['lastName']?.toString() ?? '';
        
        // Load User Birthdate
        _userBirthDate = data?['birthdate']?.toString();
        if (_userBirthDate != null) {
          final formatted = _formatFromIsoOrRaw(_userBirthDate);
          _birthDateController.text = formatted; 
          _requesterBirthDateController.text = formatted; 
        }

        if (widget.documentType == 'Barangay Business Clearance') {
          final businessProfile = (data?['savedBusinessProfile'] as Map?)?.cast<String, dynamic>();
          final businessAddress = (businessProfile?['businessAddress'] as Map?)?.cast<String, dynamic>();

          _businessNameController.text = (businessProfile?['businessName'] ?? '').toString();
          _operatorController.text = (businessProfile?['operator'] ?? '').toString();
          _operatorAddressController.text = (businessProfile?['operatorAddress'] ?? '').toString();
          _streetAddressController.text = (businessAddress?['street'] ?? '').toString();

          if (businessAddress != null) {
            await _loadProvincesAndPreselect(
              provinceCode: businessAddress['provinceCode']?.toString(),
              municipalityCode: businessAddress['municipalityCode']?.toString(),
              barangayCode: businessAddress['barangayCode']?.toString(),
            );
          } else {
            await _loadProvincesAndPreselect();
          }
        }

        if (widget.documentType == 'Certification (Late) Registration') {
          final pob = _composePlaceOfBirthFromProfile(data);
          if (pob.isNotEmpty) _placeOfBirthController.text = pob;

          final parents = (data?['savedParentsInfo'] as Map?)?.cast<String, dynamic>();
          final father = parents?['fatherName'] ?? data?['fatherName'];
          final mother = parents?['motherName'] ?? data?['motherName'];
          _fatherNameController.text = _toTitleCase((father ?? '').toString());
          _motherNameController.text = _toTitleCase((mother ?? '').toString());
        }

        if (widget.documentType == 'Certificate of Cohabitation') {
           final savedCohab = (data?['savedCohabitationDetails'] as Map?)?.cast<String, dynamic>();
           
           if (savedCohab != null) {
             _partnerNameController.text = savedCohab['partnerName'] ?? '';
             _partnerBirthDateController.text = savedCohab['partnerBirthDate'] ?? '';
             _cohabitationStartDateController.text = savedCohab['cohabitationStartDate'] ?? '';
             
             final addr = (savedCohab['cohabitationAddress'] as Map?)?.cast<String, dynamic>();
             if (addr != null) {
               _streetAddressController.text = addr['street'] ?? '';
               await _loadProvincesAndPreselect(
                 provinceCode: addr['provinceCode'],
                 provinceName: addr['province'],
                 municipalityCode: addr['municipalityCode'],
                 municipalityName: addr['municipality'],
                 barangayCode: addr['barangayCode'],
                 barangayName: addr['barangay']
               );
             } else {
               await _loadProvincesAndPreselect();
             }
           } else {
             // No fallback to user address for Cohabitation as per your request
             await _loadProvincesAndPreselect();
           }
        }
        
        // --- SEAWEEDS: LOAD SAVED DATA ---
        if (widget.documentType == 'Certificate of Seaweeds') {
           final savedSeaweeds = (data?['savedSeaweedsDetails'] as Map?)?.cast<String, dynamic>();
           
           if (savedSeaweeds != null) {
             _seaweedsBuyerController.text = savedSeaweeds['buyerName'] ?? '';
             
             // Try to split quantity back into number and unit if possible
             String rawQty = savedSeaweeds['quantity'] ?? '';
             List<String> parts = rawQty.split(' ');
             if (parts.isNotEmpty) {
               // Assuming format "2.5 Rolls" or "1 Roll"
               // Very basic parsing: first part is number, rest is unit
               if (double.tryParse(parts[0]) != null) {
                 _seaweedsQuantityController.text = parts[0];
                 // Try to match unit
                 String possibleUnit = parts.sublist(1).join(' ');
                 // Handle singular/plural restoration
                 if (!possibleUnit.endsWith('s')) possibleUnit += 's'; 
                 if (["Rolls", "Kgs", "Tons", "Sacks", "Bundles"].contains(possibleUnit)) {
                   _selectedSeaweedsUnit = possibleUnit;
                 }
               }
             }
             
             // Clean up formatting for amount (remove commas/currency for edit mode)
             String rawAmt = savedSeaweeds['amountFigures'] ?? '';
             _seaweedsAmountFiguresController.text = rawAmt.replaceAll(',', '');
           }
           
           await _loadProvincesAndPreselect();
        }

      } else {
        _profileLoadFailed = true;
        // Load provinces anyway so they can at least use dropdowns
        await _loadProvincesAndPreselect();
      }
    } catch (e) {
      _profileLoadFailed = true;
      if (mounted) {
        await _loadProvincesAndPreselect();
      }
    } finally {
      if (mounted) {
        setState(() => _isLoadingProfile = false);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _checkAndStartFormTutorial();
        });
      }
    }
  }

  // --- ADDRESS LOADERS ---
  Future<void> _loadProvincesAndPreselect({
    String? provinceCode, String? provinceName,
    String? municipalityCode, String? municipalityName,
    String? barangayCode, String? barangayName
  }) async {
    setState(() {
      _isProvincesLoading = true;
      _isMunicipalitiesLoading = false;
      _isBarangaysLoading = false;
    });

    try {
      _provinces = await _psgcApiService.fetchProvinces().timeout(const Duration(seconds: 10));
      if (!mounted) return;

      // Match Province
      if (provinceCode != null) {
        try {
          _selectedProvince = _provinces.firstWhere((p) => p.code == provinceCode);
        } catch (_) {}
      } 
      if (_selectedProvince == null && provinceName != null) {
        try {
          _selectedProvince = _provinces.firstWhere((p) => p.name.toLowerCase() == provinceName.toLowerCase());
        } catch (_) {}
      }
      
      setState(() => _isProvincesLoading = false);

      if (_selectedProvince != null) {
        setState(() => _isMunicipalitiesLoading = true);
        _municipalities = await _psgcApiService.fetchMunicipalities(_selectedProvince!.code).timeout(const Duration(seconds: 10));
        if (!mounted) return;

        // Match Municipality
        if (municipalityCode != null) {
          try {
            _selectedMunicipality = _municipalities.firstWhere((m) => m.code == municipalityCode);
          } catch (_) {}
        }
        if (_selectedMunicipality == null && municipalityName != null) {
          try {
            _selectedMunicipality = _municipalities.firstWhere((m) => m.name.toLowerCase() == municipalityName.toLowerCase());
          } catch (_) {}
        }
        
        setState(() => _isMunicipalitiesLoading = false);
      }

      if (_selectedMunicipality != null) {
        setState(() => _isBarangaysLoading = true);
        _barangays = await _psgcApiService.fetchBarangays(_selectedMunicipality!.code).timeout(const Duration(seconds: 10));
        if (!mounted) return;

        // Match Barangay
        if (barangayCode != null) {
          try {
            _selectedBarangay = _barangays.firstWhere((b) => b.code == barangayCode);
          } catch (_) {}
        }
        if (_selectedBarangay == null && barangayName != null) {
          try {
            _selectedBarangay = _barangays.firstWhere((b) => b.name.toLowerCase() == barangayName.toLowerCase());
          } catch (_) {}
        }
        
        setState(() => _isBarangaysLoading = false);
      }
    } catch (e) {
      _useManualAddress = true;
      if (mounted) {
        setState(() {
          _isProvincesLoading = _isMunicipalitiesLoading = _isBarangaysLoading = false;
        });
      }
    }
    if (mounted) setState(() {});
  }

  // ... (onChanged handlers - same) ...
  void _onProvinceChanged(Province? newValue) {
    if (newValue == null) return;
    setState(() {
      _selectedProvince = newValue;
      _selectedMunicipality = null;
      _municipalities = [];
      _selectedBarangay = null;
      _barangays = [];
      _isMunicipalitiesLoading = true;
    });
    _psgcApiService.fetchMunicipalities(newValue.code).then((municipalities) {
      if (mounted) {
        setState(() {
          _municipalities = municipalities;
          _isMunicipalitiesLoading = false;
        });
      }
    }).catchError((e) {
      if (mounted) {
        setState(() {
          _isMunicipalitiesLoading = false;
          _useManualAddress = true;
        });
      }
    });
  }

  void _onMunicipalityChanged(Municipality? newValue) {
    if (newValue == null) return;
    setState(() {
      _selectedMunicipality = newValue;
      _selectedBarangay = null;
      _barangays = [];
      _isBarangaysLoading = true;
    });
    _psgcApiService.fetchBarangays(newValue.code).then((barangays) {
      if (mounted) {
        setState(() {
          _barangays = barangays;
          _isBarangaysLoading = false;
        });
      }
    }).catchError((e) {
      if (mounted) {
        setState(() {
          _isBarangaysLoading = false;
          _useManualAddress = true;
        });
      }
    });
  }

  // ... (Dialogs - same) ...
  void _showAgreementDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text("Terms and Conditions"),
          content: const SingleChildScrollView(
            child: Text(
              "By submitting this document request, you acknowledge and agree to the following terms:\n\n"
              "1. All information provided is true and correct to the best of your knowledge.\n\n"
              "2. Upon successful processing and completion of your document ('Successful' status), you are required to pay the corresponding fee at the barangay hall upon pickup.\n\n"
              "3. The barangay office reserves the right to verify the information you have submitted and may reject the request if any discrepancies are found.\n\n"
              "4. You will be notified via the application regarding the status of your request.",
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text("Close"),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _showSuccessDialog() async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext ctx) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          elevation: 10,
          backgroundColor: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(15),
                  decoration: BoxDecoration(color: Colors.green.shade50, shape: BoxShape.circle),
                  child: Icon(Icons.check_circle_rounded, color: Colors.green.shade600, size: 60),
                ),
                const SizedBox(height: 20),
                Text("Request Submitted!", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.grey.shade800)),
                const SizedBox(height: 10),
                Text(
                  "Your request for ${widget.documentType} has been successfully sent to the barangay office.",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: Colors.grey.shade600, height: 1.5),
                ),
                const SizedBox(height: 10),
                Text("You will be notified once it is ready.", textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Colors.grey.shade500, fontStyle: FontStyle.italic)),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(ctx).pop(); 
                      Navigator.of(context).pop(); 
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepPurple,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text("OK, GOT IT", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // --- SUBMIT LOGIC ---
  Future<void> _submitRequest() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Error: You are not signed in."),
          backgroundColor: Colors.red,
        ));
      }
      return;
    }

    setState(() => _isSubmitting = true);
    
    try {
      final completeName =
          "${(_userTitle ?? '').isNotEmpty ? '${_toTitleCase(_userTitle)} ' : ''}${_getFullNameWithoutTitle()}".trim();
    
      final safeDocumentType = (widget.documentType.isEmpty) ? "Unknown Request" : widget.documentType;

      final int timestamp = DateTime.now().millisecondsSinceEpoch;
      
      final Map<String, dynamic> baseRequestData = {
        'documentType': safeDocumentType,
        'title': safeDocumentType, 
        'status': 'Pending',
        'timestamp': ServerValue.timestamp,
        'statusHistory': {
          timestamp.toString(): {
            'stage': 'Pending',
            'remarks': 'Request submitted successfully',
            'timestamp': ServerValue.timestamp,
          }
        }
      };
    
      Map<String, dynamic>? businessDetailsPayload;
      Map<String, dynamic>? parentsInfoPayload;
      Map<String, dynamic>? cohabitationPayload;
      Map<String, dynamic>? seaweedsPayload;
      Map<String, dynamic> profilePatchPayload = {};
    
      if (widget.documentType == 'Barangay Business Clearance') {
        final address = _useManualAddress
            ? {
                'street': _streetAddressController.text.trim(),
                'barangay': _manualBarangayController.text.trim(),
                'municipality': _manualMunicipalityController.text.trim(),
                'province': _manualProvinceController.text.trim(),
              }
            : {
                'street': _streetAddressController.text.trim(),
                'barangay': _selectedBarangay?.name,
                'barangayCode': _selectedBarangay?.code,
                'municipality': _selectedMunicipality?.name,
                'municipalityCode': _selectedMunicipality?.code,
                'province': _selectedProvince?.name,
                'provinceCode': _selectedProvince?.code,
              };
    
        businessDetailsPayload = {
          'businessName': _businessNameController.text.trim(),
          'operator': _operatorController.text.trim(),
          'operatorAddress': _operatorAddressController.text.trim(),
          'businessAddress': address,
        };
        baseRequestData['businessDetails'] = businessDetailsPayload;
        profilePatchPayload['savedBusinessProfile'] = businessDetailsPayload;
      }
    
      if (widget.documentType == 'Certification (Late) Registration') {
        final fatherName = _toTitleCase(_fatherNameController.text.trim());
        final motherName = _toTitleCase(_motherNameController.text.trim());
    
        baseRequestData['birthDate'] = _birthDateController.text.trim();
        baseRequestData['placeOfBirth'] = _placeOfBirthController.text.trim();
        baseRequestData['fatherName'] = fatherName;
        baseRequestData['motherName'] = motherName;
    
        parentsInfoPayload = {'fatherName': fatherName, 'motherName': motherName};
        profilePatchPayload['savedParentsInfo'] = parentsInfoPayload;
      }

      if (widget.documentType == 'Certificate of Cohabitation') {
        final address = _useManualAddress
            ? {
                'street': _streetAddressController.text.trim(),
                'barangay': _manualBarangayController.text.trim(),
                'municipality': _manualMunicipalityController.text.trim(),
                'province': _manualProvinceController.text.trim(),
              }
            : {
                'street': _streetAddressController.text.trim(),
                'barangay': _selectedBarangay?.name,
                'barangayCode': _selectedBarangay?.code,
                'municipality': _selectedMunicipality?.name,
                'municipalityCode': _selectedMunicipality?.code,
                'province': _selectedProvince?.name,
                'provinceCode': _selectedProvince?.code,
              };

        baseRequestData['birthDate'] = _requesterBirthDateController.text.trim();
        baseRequestData['partnerName'] = _toTitleCase(_partnerNameController.text.trim());
        baseRequestData['partnerBirthDate'] = _partnerBirthDateController.text.trim();
        baseRequestData['cohabitationStartDate'] = _cohabitationStartDateController.text.trim();

        cohabitationPayload = {
          'partnerName': _toTitleCase(_partnerNameController.text.trim()),
          'partnerBirthDate': _partnerBirthDateController.text.trim(),
          'cohabitationStartDate': _cohabitationStartDateController.text.trim(),
          'cohabitationAddress': address,
        };
        
        baseRequestData['cohabitationDetails'] = cohabitationPayload;
        profilePatchPayload['savedCohabitationDetails'] = cohabitationPayload;
      }

      // --- SEAWEEDS SUBMIT LOGIC (WITH SAVING) ---
      if (widget.documentType == 'Certificate of Seaweeds') {
        double amount = double.tryParse(_seaweedsAmountFiguresController.text.replaceAll(',', '')) ?? 0.0;
        String amountInWords = convertToCurrencyWords(amount);
        String amountInFigures = NumberFormat("#,##0.00", "en_US").format(amount);

        String quantityStr = _seaweedsQuantityController.text.trim();
        double quantityVal = double.tryParse(quantityStr) ?? 0;
        String unit = _selectedSeaweedsUnit ?? "";

        if (quantityVal == 1.0) {
          if (unit.endsWith('s')) {
            unit = unit.substring(0, unit.length - 1); 
          }
        }

        String fullQuantity = "$quantityStr $unit";

        seaweedsPayload = {
          'buyerName': _toTitleCase(_seaweedsBuyerController.text.trim()),
          'quantity': fullQuantity, 
          'amountWords': amountInWords,
          'amountFigures': amountInFigures,
        };
        
        baseRequestData['seaweedsDetails'] = seaweedsPayload;
        // --- NEW: Save to profile ---
        profilePatchPayload['savedSeaweedsDetails'] = seaweedsPayload;
      }
    
      final dbRef = FirebaseDatabase.instance.ref();
      final requestId = dbRef.child('all_requests').push().key!;
    
      final Map<String, dynamic> allRequestsPayload = {
        ...baseRequestData,
        'userId': widget.uid,
        'userEmail': widget.email,
        'fullName': completeName,
      };
        
      final Map<String, dynamic> multiPathUpdate = {
        'all_requests/$requestId': allRequestsPayload,
        'users/${widget.uid}/requests/$requestId': baseRequestData,
      };
    
      await dbRef.update(multiPathUpdate);
    
      if (profilePatchPayload.isNotEmpty) {
        await dbRef.child('users/${widget.uid}').update(profilePatchPayload);
      }
        
      if (!mounted) return;
      
      setState(() => _isSubmitting = false);
      await _showSuccessDialog();
    
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error submitting request: $e"), backgroundColor: Colors.red));
    }
  }

  // ... (validation and confirmation dialog - same as before) ...
  Future<void> _validateAndConfirm() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          elevation: 16,
          child: Container(
            width: MediaQuery.of(context).size.width * 0.9,
            constraints: BoxConstraints(
              maxWidth: 400,
              maxHeight: MediaQuery.of(context).size.height * 0.8,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: LinearGradient(colors: [Colors.white, Colors.grey.shade50]),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.deepPurple.shade400, Colors.deepPurple.shade600],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    ),
                    borderRadius: const BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20)),
                  ),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), shape: BoxShape.circle),
                        child: getDocumentIcon(widget.documentType, size: 32, color: Colors.white),
                      ),
                      const SizedBox(height: 12),
                      const Text("Confirm Request",
                          style: TextStyle(fontSize: 22, color: Colors.white, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text("Please review your document request",
                          style: TextStyle(fontSize: 14, color: Colors.white.withOpacity(0.9))),
                    ],
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildDetailRowWithWidgetIcon(
                          icon: getDocumentIcon(widget.documentType, size: 20, color: Colors.deepPurple),
                          label: "Document Type",
                          value: widget.documentType,
                          color: Colors.deepPurple,
                        ),
                        const SizedBox(height: 16),
                        _buildSectionHeader("Personal Information"),
                        const SizedBox(height: 12),
                        if ((_userTitle ?? '').isNotEmpty) ...[
                          _buildDetailRow(
                            icon: Icons.person_outline,
                            label: "Title",
                            value: _toTitleCase(_userTitle),
                            color: Colors.blue,
                          ),
                          const SizedBox(height: 12),
                        ],
                        _buildDetailRow(
                          icon: Icons.account_circle,
                          label: "Full Name",
                          value: _getFullNameWithoutTitle(),
                          color: Colors.green,
                        ),
                        
                        // --- 6. ADDED CONFIRMATION FOR SEAWEEDS ---
                        if (widget.documentType == 'Certificate of Seaweeds') ...[
                          const SizedBox(height: 20),
                          _buildSectionHeader("Seaweeds Sale Details"),
                          const SizedBox(height: 12),
                          _buildDetailRow(
                            icon: Icons.person_search,
                            label: "Buyer's Name",
                            value: _seaweedsBuyerController.text.trim(),
                            color: Colors.orange,
                          ),
                          const SizedBox(height: 12),
                          
                          // --- FIXED: SHOW UNIT IN CONFIRMATION ---
                          Builder(
                            builder: (context) {
                              String qtyStr = _seaweedsQuantityController.text.trim();
                              double qtyVal = double.tryParse(qtyStr) ?? 0;
                              String unit = _selectedSeaweedsUnit ?? "";
                              
                              // Logic: Remove 's' if quantity is 1
                              if (qtyVal == 1.0 && unit.endsWith('s')) {
                                unit = unit.substring(0, unit.length - 1);
                              }
                              
                              return _buildDetailRow(
                                icon: Icons.shopping_bag,
                                label: "Quantity",
                                value: "$qtyStr $unit", 
                                color: Colors.teal,
                              );
                            }
                          ),
                          
                          const SizedBox(height: 12),
                          _buildDetailRowWithWidgetIcon(
                            icon: const Text("₱", style: TextStyle(fontSize: 20, color: Colors.green, fontWeight: FontWeight.bold)), 
                            label: "Amount (to be printed)",
                            value: "${convertToCurrencyWords(double.tryParse(_seaweedsAmountFiguresController.text.replaceAll(',', '')) ?? 0)} (₱${_seaweedsAmountFiguresController.text})",
                            color: Colors.green,
                          ),
                        ],

                        if (widget.documentType == 'Barangay Business Clearance') ...[
                          const SizedBox(height: 20),
                          _buildSectionHeader("Business Information"),
                          const SizedBox(height: 12),
                          _buildDetailRow(
                            icon: Icons.business,
                            label: "Business Name",
                            value: _businessNameController.text.trim(),
                            color: Colors.orange,
                          ),
                          const SizedBox(height: 12),
                          _buildDetailRow(
                            icon: Icons.location_on,
                            label: "Business Address",
                            value: _getFormattedBusinessAddress(),
                            color: Colors.red,
                          ),
                          const SizedBox(height: 12),
                          _buildDetailRow(
                            icon: Icons.supervised_user_circle,
                            label: "Operator/Manager",
                            value: _operatorController.text.trim(),
                            color: Colors.teal,
                          ),
                          const SizedBox(height: 12),
                          _buildDetailRow(
                            icon: Icons.location_city,
                            label: "Operator Address",
                            value: _operatorAddressController.text.trim(),
                            color: Colors.indigo,
                          ),
                        ],
                        if (widget.documentType == 'Certificate of Cohabitation') ...[
                          const SizedBox(height: 20),
                          _buildSectionHeader("Cohabitation Details"),
                          // --- SHOW REQUESTER BIRTHDATE IN CONFIRMATION ---
                          const SizedBox(height: 12),
                          _buildDetailRow(
                            icon: Icons.cake,
                            label: "My Birth Date",
                            value: _requesterBirthDateController.text.trim(),
                            color: Colors.blue,
                          ),
                          const SizedBox(height: 12),
                          _buildDetailRow(
                            icon: Icons.people_outline,
                            label: "Partner's Name",
                            value: _partnerNameController.text.trim(),
                            color: Colors.pink,
                          ),
                          const SizedBox(height: 12),
                          _buildDetailRow(
                            icon: Icons.cake,
                            label: "Partner's Birthdate",
                            value: _partnerBirthDateController.text.trim(),
                            color: Colors.purple,
                          ),
                          const SizedBox(height: 12),
                          _buildDetailRow(
                            icon: Icons.date_range,
                            label: "Living Together Since",
                            value: _cohabitationStartDateController.text.trim(),
                            color: Colors.teal,
                          ),
                          const SizedBox(height: 12),
                          _buildDetailRow(
                            icon: Icons.maps_home_work,
                            label: "Shared Address",
                            value: _getFormattedBusinessAddress(), 
                            color: Colors.brown,
                          ),
                        ],
                        if (widget.documentType == 'Certification (Late) Registration') ...[
                          const SizedBox(height: 20),
                          _buildSectionHeader("Birth Information"),
                          const SizedBox(height: 12),
                          _buildDetailRow(
                            icon: Icons.cake,
                            label: "Birth Date",
                            value: _birthDateController.text.trim(),
                            color: Colors.pink,
                          ),
                          const SizedBox(height: 12),
                          _buildDetailRow(
                            icon: Icons.location_on,
                            label: "Place of Birth",
                            value: _placeOfBirthController.text.trim(),
                            color: Colors.amber,
                          ),
                          const SizedBox(height: 12),
                          _buildDetailRow(
                            icon: Icons.male,
                            label: "Father's Name",
                            value: _fatherNameController.text.trim(),
                            color: Colors.blue,
                          ),
                          const SizedBox(height: 12),
                          _buildDetailRow(
                            icon: Icons.female,
                            label: "Mother's Name",
                            value: _motherNameController.text.trim(),
                            color: Colors.purple,
                          ),
                        ],
                        const SizedBox(height: 20),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.blue.shade200),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.info_outline, color: Colors.blue.shade600, size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  "Your document request will be saved and processed by the barangay office. You will be notified once it's ready for pickup.",
                                  style: TextStyle(color: Colors.blue.shade700, fontSize: 12),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius:
                        const BorderRadius.only(bottomLeft: Radius.circular(20), bottomRight: Radius.circular(20)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                              side: BorderSide(color: Colors.grey.shade400),
                            ),
                          ),
                          child: Text("Cancel",
                              style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.w600, fontSize: 16)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => Navigator.of(context).pop(true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.deepPurple,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            elevation: 2,
                          ),
                          child: const Text("Confirm",
                              style: TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    
    if (confirmed == true) {
      _submitRequest();
    }
  }

  Widget _buildSectionHeader(String title) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        children: [
          Icon(Icons.folder_outlined, size: 16, color: Colors.grey.shade600),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title, 
              style: TextStyle(
                fontSize: 14, 
                fontWeight: FontWeight.bold, 
                color: Colors.grey.shade700
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- ROBUST DETAIL ROW (PREVENTS OVERFLOW) ---
  Widget _buildDetailRow({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min, // Important for layout
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              // Expanded forces the label to wrap if it gets too long
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 14, 
                    fontWeight: FontWeight.w600, 
                    color: color
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 28),
            // Text simply placed here will wrap automatically because it's in a Column
            child: Text(
              value.isEmpty ? "N/A" : value,
              style: TextStyle(
                fontSize: 15, 
                color: Colors.grey.shade800, 
                fontWeight: FontWeight.w500,
                height: 1.3, // Adds a little line spacing for readability
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRowWithWidgetIcon({
    required Widget icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start, // Align top
            children: [
              icon, 
              const SizedBox(width: 8), 
              // --- FIX: Wrapped in Expanded to prevent overflow ---
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 14, 
                    fontWeight: FontWeight.w600, 
                    color: color
                  ),
                ),
              ),
            ]
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 28),
            child: Text(
              value.isEmpty ? "N/A" : value,
              style: TextStyle(
                fontSize: 15, 
                color: Colors.grey.shade800, 
                fontWeight: FontWeight.w500
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isBusiness = widget.documentType == 'Barangay Business Clearance';
    final isLateReg = widget.documentType == 'Certification (Late) Registration';
    final isCohabitation = widget.documentType == 'Certificate of Cohabitation';
    final isSeaweeds = widget.documentType == 'Certificate of Seaweeds';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 8,
        margin: const EdgeInsets.all(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              
              // --- HEADER ---
              Align(
                alignment: Alignment.topLeft,
                child: IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.black87),
                  onPressed: () => Navigator.pop(context),
                  tooltip: 'Go Back',
                ),
              ),
              const SizedBox(height: 4),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.deepPurple.shade300, Colors.deepPurple.shade600],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Request ${widget.documentType}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 20, color: Colors.white, fontWeight: FontWeight.bold,
                    shadows: [Shadow(blurRadius: 2, color: Colors.black26, offset: Offset(1, 1))],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              if (_isLoadingProfile) const Center(child: CircularProgressIndicator()),

              if (!_isLoadingProfile && _profileLoadFailed)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.withOpacity(0.3)),
                  ),
                  child: InkWell(
                    onTap: () => _loadInitialData(), // Retry logic
                    child: const Text(
                      "We couldn’t load your profile. Tap here to retry or check your internet.",
                      style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),

              if (!_isLoadingProfile) ...[
                TextFormField(
                  initialValue: _toTitleCase(_userTitle),
                  decoration: const InputDecoration(labelText: 'Title', prefixIcon: Icon(Icons.person_outline)),
                  readOnly: true,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  initialValue: _getFullNameWithoutTitle(),
                  decoration: const InputDecoration(labelText: 'Full Name', prefixIcon: Icon(Icons.text_fields)),
                  readOnly: true,
                ),
                const SizedBox(height: 16),
              ],

              // --- ADDRESS FIELDS ---
              if (isBusiness || isCohabitation) ...[
                // --- NOTE ---
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.withOpacity(0.3)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.info, color: Colors.blue, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          isCohabitation
                              ? "Note: Please enter the address where you and your partner are currently living together (Cohabitation Address)."
                              : "Note: Please enter the specific location where your business is operating.",
                          style: const TextStyle(color: Colors.blue, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),

                if (!_useManualAddress) ...[
                  // 1. Province Dropdown
                  DropdownSearch<Province>(
                    popupProps: PopupProps.modalBottomSheet(
                      showSearchBox: true,
                      title: Container(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                        child: Text("Select Province", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.deepPurple.shade700)),
                      ),
                      searchFieldProps: TextFieldProps(
                        decoration: InputDecoration(
                          hintText: "Search Province...",
                          prefixIcon: const Icon(Icons.search, color: Colors.blue),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                        ),
                      ),
                    ),
                    items: (filter, loadProps) {
                      if (filter.isEmpty) return _provinces;
                      return _provinces.where((p) => p.name.toLowerCase().contains(filter.toLowerCase())).toList();
                    },
                    itemAsString: (Province p) => p.name,
                    selectedItem: _selectedProvince,
                    compareFn: (item, selectedItem) => item.code == selectedItem.code,
                    decoratorProps: DropDownDecoratorProps(
                      decoration: _getDropdownDecoration('Province', Icons.map_outlined, true, _isProvincesLoading),
                    ),
                    onChanged: _onProvinceChanged,
                    validator: (v) => v == null ? 'Province is required' : null,
                  ),
                  const SizedBox(height: 16),
                  
                  // 2. Municipality Dropdown
                  DropdownSearch<Municipality>(
                    enabled: _selectedProvince != null,
                    popupProps: PopupProps.modalBottomSheet(
                      showSearchBox: true,
                      title: Container(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                        child: Text("Select Municipality/City", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.deepPurple.shade700)),
                      ),
                      searchFieldProps: TextFieldProps(
                        decoration: InputDecoration(
                          hintText: "Search Municipality...",
                          prefixIcon: const Icon(Icons.search, color: Colors.blue),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                        ),
                      ),
                    ),
                    items: (filter, loadProps) {
                      if (filter.isEmpty) return _municipalities;
                      return _municipalities.where((m) => m.name.toLowerCase().contains(filter.toLowerCase())).toList();
                    },
                    itemAsString: (Municipality m) => m.name,
                    selectedItem: _selectedMunicipality,
                    compareFn: (item, selectedItem) => item.code == selectedItem.code,
                    decoratorProps: DropDownDecoratorProps(
                      decoration: _getDropdownDecoration('Municipality/City', Icons.location_city, _selectedProvince != null, _isMunicipalitiesLoading),
                    ),
                    onChanged: _onMunicipalityChanged,
                    validator: (v) => v == null ? 'Municipality is required' : null,
                  ),
                  const SizedBox(height: 16),
                  
                  // 3. Barangay Dropdown
                  DropdownSearch<Barangay>(
                    enabled: _selectedMunicipality != null,
                    popupProps: PopupProps.modalBottomSheet(
                      showSearchBox: true,
                      title: Container(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                        child: Text("Select Barangay", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.deepPurple.shade700)),
                      ),
                      searchFieldProps: TextFieldProps(
                        decoration: InputDecoration(
                          hintText: "Search Barangay...",
                          prefixIcon: const Icon(Icons.search, color: Colors.blue),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                        ),
                      ),
                    ),
                    items: (filter, loadProps) {
                      if (filter.isEmpty) return _barangays;
                      return _barangays.where((b) => b.name.toLowerCase().contains(filter.toLowerCase())).toList();
                    },
                    itemAsString: (Barangay b) => b.name,
                    selectedItem: _selectedBarangay,
                    compareFn: (item, selectedItem) => item.code == selectedItem.code,
                    decoratorProps: DropDownDecoratorProps(
                      decoration: _getDropdownDecoration('Barangay', Icons.holiday_village_outlined, _selectedMunicipality != null, _isBarangaysLoading),
                    ),
                    onChanged: (newValue) => setState(() => _selectedBarangay = newValue),
                    validator: (v) => v == null ? 'Barangay is required' : null,
                  ),
                ] else ...[
                  // Manual Fields
                  TextFormField(
                    controller: _manualProvinceController,
                    decoration: const InputDecoration(labelText: 'Province (Manual)', prefixIcon: Icon(Icons.map_outlined)),
                    validator: (v) => (v == null || v.isEmpty) ? 'Province is required' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _manualMunicipalityController,
                    decoration:
                        const InputDecoration(labelText: 'Municipality/City (Manual)', prefixIcon: Icon(Icons.location_city)),
                    validator: (v) => (v == null || v.isEmpty) ? 'Municipality is required' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _manualBarangayController,
                    decoration:
                        const InputDecoration(labelText: 'Barangay (Manual)', prefixIcon: Icon(Icons.holiday_village_outlined)),
                    validator: (v) => (v == null || v.isEmpty) ? 'Barangay is required' : null,
                  ),
                ],
                const SizedBox(height: 16),

                // -- UPDATED LABEL --
                TextFormField(
                  controller: _streetAddressController,
                  decoration: const InputDecoration(labelText: "Purok (e.g., Purok 1, Zone 2)", prefixIcon: Icon(Icons.location_on)),
                  validator: (value) => value == null || value.isEmpty ? "Purok details required" : null,
                ),
                const SizedBox(height: 16),
              ],

              // --- BUSINESS SPECIFIC FIELDS ---
              if (isBusiness) ...[
                TextFormField(
                  controller: _businessNameController,
                  decoration: const InputDecoration(
                    labelText: "Business Name/Trade Activity",
                    prefixIcon: Icon(Icons.business),
                  ),
                  validator: (v) => (v == null || v.isEmpty) ? "Business name required" : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _operatorController,
                  decoration: const InputDecoration(labelText: "Operator/Manager", prefixIcon: Icon(Icons.supervised_user_circle)),
                  validator: (v) => (v == null || v.isEmpty) ? "Operator/Manager required" : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _operatorAddressController,
                  decoration:
                      const InputDecoration(labelText: "Operator/Manager Address", prefixIcon: Icon(Icons.location_city)),
                  validator: (v) => (v == null || v.isEmpty) ? "Operator address required" : null,
                ),
                const SizedBox(height: 16),
              ],

              // --- COHABITATION SPECIFIC FIELDS ---
              if (isCohabitation) ...[
                // --- REQUESTER BIRTHDATE (READ ONLY) ---
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: Colors.deepPurple.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.deepPurple.withOpacity(0.2)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, color: Colors.deepPurple),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _profileLoadFailed
                              ? "We couldn’t load your profile. Please enter your birth date manually."
                              : "Your Birth Date (from Profile).",
                          style: TextStyle(color: Colors.deepPurple.shade800, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
                TextFormField(
                  controller: _requesterBirthDateController,
                  readOnly: !_profileLoadFailed,
                  onTap: !_profileLoadFailed
                      ? null
                      : () async {
                          final now = DateTime.now();
                          final first = DateTime(1900);
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: DateTime(now.year - 20),
                            firstDate: first,
                            lastDate: now,
                          );
                          if (picked != null) {
                            _requesterBirthDateController.text = _formatCertDate(picked);
                          }
                        },
                  decoration: const InputDecoration(
                    labelText: "My Birth Date",
                    prefixIcon: Icon(Icons.cake),
                  ),
                  validator: (v) => (v == null || v.isEmpty) ? "Your birth date is required." : null,
                ),
                const SizedBox(height: 16),

                TextFormField(
                  controller: _partnerNameController,
                  decoration: const InputDecoration(
                    labelText: "Partner's Full Name",
                    prefixIcon: Icon(Icons.people_outline),
                  ),
                  textCapitalization: TextCapitalization.words,
                  inputFormatters: [TitleCaseTextFormatter()],
                  validator: (v) => (v == null || v.isEmpty) ? "Partner's name required" : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _partnerBirthDateController,
                  readOnly: true,
                  decoration: const InputDecoration(
                    labelText: "Partner's Birth Date", 
                    prefixIcon: Icon(Icons.cake)
                  ),
                  onTap: () async {
                    final now = DateTime.now();
                    final first = DateTime(1900);
                    final picked = await showDatePicker(context: context, initialDate: DateTime(now.year - 20), firstDate: first, lastDate: now);
                    if(picked != null) {
                      _partnerBirthDateController.text = _formatCertDate(picked);
                    }
                  },
                  validator: (v) => (v == null || v.isEmpty) ? "Partner's birthdate required" : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _cohabitationStartDateController,
                  readOnly: true,
                  decoration: const InputDecoration(
                    labelText: "Living Together Since", 
                    prefixIcon: Icon(Icons.date_range)
                  ),
                  onTap: () async {
                    final now = DateTime.now();
                    final first = DateTime(1950);
                    final picked = await showDatePicker(context: context, initialDate: now, firstDate: first, lastDate: now);
                    if(picked != null) {
                      _cohabitationStartDateController.text = _formatCertDate(picked);
                    }
                  },
                  validator: (v) => (v == null || v.isEmpty) ? "Start date required" : null,
                ),
                const SizedBox(height: 16),
              ],

              // --- 5. NEW: SEAWEEDS FIELDS (IMPROVED) ---
              if (isSeaweeds) ...[
                TextFormField(
                  controller: _seaweedsBuyerController,
                  decoration: const InputDecoration(
                    labelText: "Buyer's Full Name",
                    hintText: "Who bought the seaweeds?",
                    prefixIcon: Icon(Icons.person_search),
                  ),
                  textCapitalization: TextCapitalization.words,
                  inputFormatters: [TitleCaseTextFormatter()],
                  validator: (v) => (v == null || v.isEmpty) ? "Buyer's name required" : null,
                ),
                const SizedBox(height: 16),
                
                // --- SPLIT QUANTITY & UNIT (FIXED LAYOUT) ---
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Quantity Number (40% width)
                    Expanded(
                      flex: 4,
                      child: TextFormField(
                        controller: _seaweedsQuantityController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                          labelText: "Qty",
                          hintText: "2.5",
                          prefixIcon: Icon(Icons.scale),
                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                        ),
                        validator: (v) => (v == null || v.isEmpty) ? "Req." : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    
                    // Unit Dropdown (60% width)
                    Expanded(
                      flex: 6,
                      child: DropdownButtonFormField<String>(
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: "Unit",
                          prefixIcon: Icon(Icons.shopping_bag_outlined),
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                        ),
                        value: _selectedSeaweedsUnit,
                        items: ["Rolls", "Kgs", "Tons", "Sacks", "Bundles"]
                            .map((unit) => DropdownMenuItem(
                                  value: unit,
                                  child: Text(
                                    unit, 
                                    overflow: TextOverflow.ellipsis, // Safety for long text
                                    style: const TextStyle(fontSize: 14),
                                  ),
                                ))
                            .toList(),
                        onChanged: (val) => setState(() => _selectedSeaweedsUnit = val),
                        validator: (v) => v == null ? "Required" : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                
                // Amount Field (Figures Only)
                TextFormField(
                  controller: _seaweedsAmountFiguresController,
                  decoration: InputDecoration(
                    labelText: "Total Amount Sold",
                    hintText: "e.g. 10000",
                    // --- FIX: USE TEXT AS ICON ---
                    prefixIcon: Container(
                      width: 48,
                      alignment: Alignment.center,
                      child: const Text("₱", 
                        style: TextStyle(fontSize: 20, color: Colors.grey, fontWeight: FontWeight.bold)
                      ),
                    ),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
                  ],
                  validator: (v) => (v == null || v.isEmpty) ? "Amount required" : null,
                ),
                const SizedBox(height: 8),
                const Padding(
                  padding: EdgeInsets.only(left: 12.0),
                  child: Text(
                    "We will automatically convert this amount into words.",
                    style: TextStyle(fontSize: 12, color: Colors.grey, fontStyle: FontStyle.italic),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              if (isLateReg) ...[
                // ... (Late reg code kept same) ...
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: Colors.deepPurple.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.deepPurple.withOpacity(0.2)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, color: Colors.deepPurple),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _profileLoadFailed
                              ? "We couldn’t load your profile. Please enter birth details manually."
                              : "Birth Date and Place of Birth are from your profile.",
                          style: TextStyle(color: Colors.deepPurple.shade800, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
                TextFormField(
                  controller: _birthDateController,
                  readOnly: !_profileLoadFailed, 
                  decoration: const InputDecoration(labelText: "Birth Date", prefixIcon: Icon(Icons.cake)),
                  onTap: !_profileLoadFailed
                      ? null
                      : () async {
                          final now = DateTime.now();
                          final first = DateTime(now.year - 120, 1, 1);
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: DateTime(now.year - 20, 1, 1),
                            firstDate: first,
                            lastDate: now,
                          );
                          if (picked != null) {
                            _birthDateController.text = _formatCertDate(picked);
                          }
                        },
                  validator: (v) => (v == null || v.isEmpty) ? "Birth date is required." : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _placeOfBirthController,
                  readOnly: !_profileLoadFailed,
                  decoration: const InputDecoration(labelText: "Place of Birth", prefixIcon: Icon(Icons.location_on)),
                  validator: (v) => (v == null || v.isEmpty) ? "Place of birth is required." : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _fatherNameController,
                  decoration: const InputDecoration(labelText: "Father's Name", prefixIcon: Icon(Icons.male)),
                  keyboardType: TextInputType.name,
                  textCapitalization: TextCapitalization.words,
                  inputFormatters: [TitleCaseTextFormatter()],
                  validator: (v) => (v == null || v.isEmpty) ? "Father's name required" : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _motherNameController,
                  decoration: const InputDecoration(labelText: "Mother's Name", prefixIcon: Icon(Icons.female)),
                  keyboardType: TextInputType.name,
                  textCapitalization: TextCapitalization.words,
                  inputFormatters: [TitleCaseTextFormatter()],
                  validator: (v) => (v == null || v.isEmpty) ? "Mother's name required" : null,
                ),
                const SizedBox(height: 16),
              ],

              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Showcase(
                      key: _termsKey,
                      title: 'Terms & Conditions',
                      description: 'You must agree to the terms before submitting.',
                      enableAutoScroll: true,
                      child: Checkbox(
                        value: _isAgreementChecked,
                        onChanged: (bool? value) {
                          setState(() {
                            _isAgreementChecked = value ?? false;
                          });
                        },
                      ),
                    ),
                    Expanded(
                      child: GestureDetector(
                        onTap: _showAgreementDialog,
                        child: RichText(
                          text: TextSpan(
                            style: DefaultTextStyle.of(context).style.copyWith(fontSize: 12),
                            children: [
                              const TextSpan(text: 'I agree to the '),
                              TextSpan(
                                text: 'Terms and Conditions.',
                                style: TextStyle(
                                  color: Theme.of(context).primaryColor,
                                  decoration: TextDecoration.underline,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              _isSubmitting
                  ? const CircularProgressIndicator()
                  : AnimatedScale(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOutBack,
                      scale: _isAgreementChecked ? 1.0 : 0.95,
                      child: SizedBox(
                        width: double.infinity,
                        child: Showcase(
                          key: _submitKey,
                          title: 'Submit Request',
                          description: 'Review your details and tap here to send your request.',
                          enableAutoScroll: true,
                          child: ElevatedButton(
                            onPressed: _isAgreementChecked
                                ? () { _validateAndConfirm(); }
                                : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _isAgreementChecked ? Colors.deepPurple : Colors.grey.shade300,
                              foregroundColor: Colors.white,
                              elevation: _isAgreementChecked ? 8 : 0,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: const Text(
                              "Submit Request",
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1),
                            ),
                          ),
                        ),
                      ),
                    ),
            ]),
          ),
        ),
      ),
    );
  }
}