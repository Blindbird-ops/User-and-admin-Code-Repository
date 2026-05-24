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
import 'package:dropdown_search/dropdown_search.dart';

import 'psgc_api_service.dart'; 
import 'request_utils.dart'; 

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

  final GlobalKey _termsKey = GlobalKey();
  final GlobalKey _submitKey = GlobalKey();

  // Profile data
  String? _userTitle;
  String? _userFirstName;
  String? _userMiddleName;
  String? _userLastName;
  String? _userBirthDate; 

  bool _isLoadingProfile = true;
  bool _isSubmitting = false;
  bool _profileLoadFailed = false;
  bool _useManualAddress = false;
  bool _isAgreementChecked = false;

  // --- CONTROLLERS ---
  
  // Business
  final TextEditingController _businessNameController = TextEditingController();
  // Split Operator
  final TextEditingController _operatorFirstNameController = TextEditingController();
  final TextEditingController _operatorMiddleNameController = TextEditingController();
  final TextEditingController _operatorLastNameController = TextEditingController();
  final TextEditingController _operatorAddressController = TextEditingController();
  final TextEditingController _streetAddressController = TextEditingController();

  // Manual address
  final TextEditingController _manualProvinceController = TextEditingController();
  final TextEditingController _manualMunicipalityController = TextEditingController();
  final TextEditingController _manualBarangayController = TextEditingController();

  // Late Reg
  final TextEditingController _birthDateController = TextEditingController();
  final TextEditingController _placeOfBirthController = TextEditingController();
  // Split Father
  final TextEditingController _fatherFirstNameController = TextEditingController();
  final TextEditingController _fatherMiddleNameController = TextEditingController();
  final TextEditingController _fatherLastNameController = TextEditingController();
  // Split Mother
  final TextEditingController _motherFirstNameController = TextEditingController();
  final TextEditingController _motherMiddleNameController = TextEditingController();
  final TextEditingController _motherLastNameController = TextEditingController();

  // Cohabitation
  // Split Partner
  final TextEditingController _partnerFirstNameController = TextEditingController();
  final TextEditingController _partnerMiddleNameController = TextEditingController();
  final TextEditingController _partnerLastNameController = TextEditingController();
  final TextEditingController _partnerBirthDateController = TextEditingController();
  final TextEditingController _cohabitationStartDateController = TextEditingController();
  final TextEditingController _requesterBirthDateController = TextEditingController();

  // Seaweeds
  // Split Buyer
  final TextEditingController _seaweedsBuyerFirstNameController = TextEditingController();
  final TextEditingController _seaweedsBuyerMiddleNameController = TextEditingController();
  final TextEditingController _seaweedsBuyerLastNameController = TextEditingController();
  final TextEditingController _seaweedsQuantityController = TextEditingController();
  final TextEditingController _seaweedsAmountFiguresController = TextEditingController();
  final TextEditingController _seaweedsAmountWordsController = TextEditingController(); 
  String? _selectedSeaweedsUnit;

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
    _operatorFirstNameController.dispose();
    _operatorMiddleNameController.dispose();
    _operatorLastNameController.dispose();
    _operatorAddressController.dispose();
    _streetAddressController.dispose();
    _manualProvinceController.dispose();
    _manualMunicipalityController.dispose();
    _manualBarangayController.dispose();
    _birthDateController.dispose();
    _placeOfBirthController.dispose();
    _fatherFirstNameController.dispose();
    _fatherMiddleNameController.dispose();
    _fatherLastNameController.dispose();
    _motherFirstNameController.dispose();
    _motherMiddleNameController.dispose();
    _motherLastNameController.dispose();
    _partnerFirstNameController.dispose();
    _partnerMiddleNameController.dispose();
    _partnerLastNameController.dispose();
    _partnerBirthDateController.dispose();
    _cohabitationStartDateController.dispose();
    _requesterBirthDateController.dispose();
    _seaweedsBuyerFirstNameController.dispose();
    _seaweedsBuyerMiddleNameController.dispose();
    _seaweedsBuyerLastNameController.dispose();
    _seaweedsQuantityController.dispose();
    _seaweedsAmountFiguresController.dispose();
    _seaweedsAmountWordsController.dispose();
    super.dispose();
  }

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

  String _joinName(String f, String m, String l) {
    List<String> parts = [];
    if (f.isNotEmpty) parts.add(f);
    if (m.isNotEmpty) parts.add(m);
    if (l.isNotEmpty) parts.add(l);
    return parts.join(' ');
  }

  void _splitAndFill(String fullName, TextEditingController f, TextEditingController m, TextEditingController l) {
    if (fullName.isEmpty) return;
    List<String> parts = fullName.trim().split(' ');
    if (parts.isNotEmpty) f.text = parts.first;
    if (parts.length > 2) {
      m.text = parts.sublist(1, parts.length - 1).join(' '); 
      l.text = parts.last;
    } else if (parts.length == 2) {
      l.text = parts.last;
    }
  }

  // --- Dynamic Decoration for Dropdowns ---
  InputDecoration _getDropdownDecoration(String label, IconData icon, bool isEnabled, bool isLoading) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: isEnabled ? Colors.blue.shade700 : Colors.grey),
      suffixIcon: isLoading ? const Padding(padding: EdgeInsets.all(10.0), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.0))) : null,
      filled: true,
      fillColor: isEnabled ? Colors.blue.shade50 : Colors.grey.shade100,
      labelStyle: TextStyle(color: isEnabled ? Colors.blue.shade900 : Colors.grey.shade600, fontWeight: isEnabled ? FontWeight.bold : FontWeight.normal),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: isEnabled ? Colors.blue.shade200 : Colors.grey.shade300, width: 1.5)),
      disabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade200, width: 1)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Colors.blue, width: 2)),
    );
  }

  Future<void> _loadInitialData() async {
    if (mounted) setState(() { _isLoadingProfile = true; _profileLoadFailed = false; });

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
          
          String opFirst = businessProfile?['operatorFirstName'] ?? '';
          if (opFirst.isEmpty) {
             _splitAndFill(businessProfile?['operator'] ?? '', _operatorFirstNameController, _operatorMiddleNameController, _operatorLastNameController);
          } else {
             _operatorFirstNameController.text = opFirst;
             _operatorMiddleNameController.text = businessProfile?['operatorMiddleName'] ?? '';
             _operatorLastNameController.text = businessProfile?['operatorLastName'] ?? '';
          }

          _operatorAddressController.text = (businessProfile?['operatorAddress'] ?? '').toString();
          _streetAddressController.text = (businessAddress?['street'] ?? '').toString();

          if (businessAddress != null) {
            await _loadProvincesAndPreselect(
              provinceCode: businessAddress['provinceCode']?.toString(), municipalityCode: businessAddress['municipalityCode']?.toString(), barangayCode: businessAddress['barangayCode']?.toString()
            );
          } else {
            await _loadProvincesAndPreselect();
          }
        }

        if (widget.documentType == 'Certification (Late) Registration') {
          final pob = _composePlaceOfBirthFromProfile(data);
          if (pob.isNotEmpty) _placeOfBirthController.text = pob;

          final parents = (data?['savedParentsInfo'] as Map?)?.cast<String, dynamic>();
          
          String fFirst = parents?['fatherFirstName'] ?? '';
          if (fFirst.isEmpty) {
             _splitAndFill(parents?['fatherName'] ?? data?['fatherName'] ?? '', _fatherFirstNameController, _fatherMiddleNameController, _fatherLastNameController);
          } else {
             _fatherFirstNameController.text = fFirst;
             _fatherMiddleNameController.text = parents?['fatherMiddleName'] ?? '';
             _fatherLastNameController.text = parents?['fatherLastName'] ?? '';
          }

          String mFirst = parents?['motherFirstName'] ?? '';
          if (mFirst.isEmpty) {
             _splitAndFill(parents?['motherName'] ?? data?['motherName'] ?? '', _motherFirstNameController, _motherMiddleNameController, _motherLastNameController);
          } else {
             _motherFirstNameController.text = mFirst;
             _motherMiddleNameController.text = parents?['motherMiddleName'] ?? '';
             _motherLastNameController.text = parents?['motherLastName'] ?? '';
          }
        }

        if (widget.documentType == 'Certificate of Cohabitation') {
           final savedCohab = (data?['savedCohabitationDetails'] as Map?)?.cast<String, dynamic>();
           
           if (savedCohab != null) {
             String pFirst = savedCohab['partnerFirstName'] ?? '';
             if (pFirst.isEmpty) {
                _splitAndFill(savedCohab['partnerName'] ?? '', _partnerFirstNameController, _partnerMiddleNameController, _partnerLastNameController);
             } else {
                _partnerFirstNameController.text = pFirst;
                _partnerMiddleNameController.text = savedCohab['partnerMiddleName'] ?? '';
                _partnerLastNameController.text = savedCohab['partnerLastName'] ?? '';
             }

             _partnerBirthDateController.text = savedCohab['partnerBirthDate'] ?? '';
             _cohabitationStartDateController.text = savedCohab['cohabitationStartDate'] ?? '';
             
             final addr = (savedCohab['cohabitationAddress'] as Map?)?.cast<String, dynamic>();
             if (addr != null) {
               _streetAddressController.text = addr['street'] ?? '';
               await _loadProvincesAndPreselect(
                 provinceCode: addr['provinceCode'], municipalityCode: addr['municipalityCode'], barangayCode: addr['barangayCode']
               );
             } else {
               await _loadProvincesAndPreselect();
             }
           } else {
             await _loadProvincesAndPreselect();
           }
        }
        
        if (widget.documentType == 'Certificate of Seaweeds') {
           final savedSeaweeds = (data?['savedSeaweedsDetails'] as Map?)?.cast<String, dynamic>();
           
           if (savedSeaweeds != null) {
             String bFirst = savedSeaweeds['buyerFirstName'] ?? '';
             if (bFirst.isEmpty) {
                _splitAndFill(savedSeaweeds['buyerName'] ?? '', _seaweedsBuyerFirstNameController, _seaweedsBuyerMiddleNameController, _seaweedsBuyerLastNameController);
             } else {
                _seaweedsBuyerFirstNameController.text = bFirst;
                _seaweedsBuyerMiddleNameController.text = savedSeaweeds['buyerMiddleName'] ?? '';
                _seaweedsBuyerLastNameController.text = savedSeaweeds['buyerLastName'] ?? '';
             }
             
             String rawQty = savedSeaweeds['quantity'] ?? '';
             List<String> parts = rawQty.split(' ');
             if (parts.isNotEmpty) {
               if (double.tryParse(parts[0]) != null) {
                 _seaweedsQuantityController.text = parts[0];
                 String possibleUnit = parts.sublist(1).join(' ');
                 if (!possibleUnit.endsWith('s')) possibleUnit += 's'; 
                 if (["Rolls", "Kgs", "Tons", "Sacks", "Bundles"].contains(possibleUnit)) {
                   _selectedSeaweedsUnit = possibleUnit;
                 }
               }
             }
             _seaweedsAmountFiguresController.text = (savedSeaweeds['amountFigures'] ?? '').toString().replaceAll(',', '');
           }
           await _loadProvincesAndPreselect();
        }

      } else {
        _profileLoadFailed = true;
        await _loadProvincesAndPreselect();
      }
    } catch (e) {
      _profileLoadFailed = true;
      if (mounted) await _loadProvincesAndPreselect();
    } finally {
      if (mounted) {
        setState(() => _isLoadingProfile = false);
        WidgetsBinding.instance.addPostFrameCallback((_) { _checkAndStartFormTutorial(); });
      }
    }
  }

  Future<void> _loadProvincesAndPreselect({String? provinceCode, String? provinceName, String? municipalityCode, String? municipalityName, String? barangayCode, String? barangayName}) async {
    setState(() { _isProvincesLoading = true; _isMunicipalitiesLoading = false; _isBarangaysLoading = false; });
    try {
      _provinces = await _psgcApiService.fetchProvinces().timeout(const Duration(seconds: 10));
      if (!mounted) return;
      if (provinceCode != null) { try { _selectedProvince = _provinces.firstWhere((p) => p.code == provinceCode); } catch (_) {} } 
      else if (provinceName != null) { try { _selectedProvince = _provinces.firstWhere((p) => p.name.toLowerCase() == provinceName.toLowerCase()); } catch (_) {} }
      setState(() => _isProvincesLoading = false);
      if (_selectedProvince != null) {
        setState(() => _isMunicipalitiesLoading = true);
        _municipalities = await _psgcApiService.fetchMunicipalities(_selectedProvince!.code).timeout(const Duration(seconds: 10));
        if (!mounted) return;
        if (municipalityCode != null) { try { _selectedMunicipality = _municipalities.firstWhere((m) => m.code == municipalityCode); } catch (_) {} }
        else if (municipalityName != null) { try { _selectedMunicipality = _municipalities.firstWhere((m) => m.name.toLowerCase() == municipalityName.toLowerCase()); } catch (_) {} }
        setState(() => _isMunicipalitiesLoading = false);
      }
      if (_selectedMunicipality != null) {
        setState(() => _isBarangaysLoading = true);
        _barangays = await _psgcApiService.fetchBarangays(_selectedMunicipality!.code).timeout(const Duration(seconds: 10));
        if (!mounted) return;
        if (barangayCode != null) { try { _selectedBarangay = _barangays.firstWhere((b) => b.code == barangayCode); } catch (_) {} }
        else if (barangayName != null) { try { _selectedBarangay = _barangays.firstWhere((b) => b.name.toLowerCase() == barangayName.toLowerCase()); } catch (_) {} }
        setState(() => _isBarangaysLoading = false);
      }
    } catch (e) {
      _useManualAddress = true;
      if (mounted) setState(() { _isProvincesLoading = _isMunicipalitiesLoading = _isBarangaysLoading = false; });
    }
    if (mounted) setState(() {});
  }
  
  void _onProvinceChanged(Province? newValue) {
    if (newValue == null) return;
    setState(() { _selectedProvince = newValue; _selectedMunicipality = null; _municipalities = []; _selectedBarangay = null; _barangays = []; _isMunicipalitiesLoading = true; });
    _psgcApiService.fetchMunicipalities(newValue.code).then((m) { if (mounted) setState(() { _municipalities = m; _isMunicipalitiesLoading = false; }); }).catchError((e) { if (mounted) setState(() { _isMunicipalitiesLoading = false; _useManualAddress = true; }); });
  }
  
  void _onMunicipalityChanged(Municipality? newValue) {
    if (newValue == null) return;
    setState(() { _selectedMunicipality = newValue; _selectedBarangay = null; _barangays = []; _isBarangaysLoading = true; });
    _psgcApiService.fetchBarangays(newValue.code).then((b) { if (mounted) setState(() { _barangays = b; _isBarangaysLoading = false; }); }).catchError((e) { if (mounted) setState(() { _isBarangaysLoading = false; _useManualAddress = true; }); });
  }

  Future<void> _submitRequest() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) { return; }
    setState(() => _isSubmitting = true);
    
    try {
      final completeName = "${(_userTitle ?? '').isNotEmpty ? '${_toTitleCase(_userTitle)} ' : ''}${_getFullNameWithoutTitle()}".trim();
      final safeDocumentType = (widget.documentType.isEmpty) ? "Unknown Request" : widget.documentType;
      final int timestamp = DateTime.now().millisecondsSinceEpoch;
      
      final Map<String, dynamic> baseRequestData = {
        'documentType': safeDocumentType,
        'title': safeDocumentType, 
        'status': 'Pending',
        'timestamp': ServerValue.timestamp,
        'statusHistory': {
          timestamp.toString(): { 'stage': 'Pending', 'remarks': 'Request submitted', 'timestamp': ServerValue.timestamp }
        }
      };
    
      Map<String, dynamic>? businessDetailsPayload;
      Map<String, dynamic>? parentsInfoPayload;
      Map<String, dynamic>? cohabitationPayload;
      Map<String, dynamic>? seaweedsPayload;
      Map<String, dynamic> profilePatchPayload = {};
    
      if (widget.documentType == 'Barangay Business Clearance') {
        final address = _useManualAddress
            ? { 'street': _streetAddressController.text.trim(), 'barangay': _manualBarangayController.text.trim(), 'municipality': _manualMunicipalityController.text.trim(), 'province': _manualProvinceController.text.trim() }
            : { 'street': _streetAddressController.text.trim(), 'barangay': _selectedBarangay?.name, 'barangayCode': _selectedBarangay?.code, 'municipality': _selectedMunicipality?.name, 'municipalityCode': _selectedMunicipality?.code, 'province': _selectedProvince?.name, 'provinceCode': _selectedProvince?.code };
    
        final opFull = _joinName(_operatorFirstNameController.text.trim(), _operatorMiddleNameController.text.trim(), _operatorLastNameController.text.trim());

        businessDetailsPayload = {
          'businessName': _businessNameController.text.trim(),
          'operator': opFull, 
          'operatorFirstName': _operatorFirstNameController.text.trim(),
          'operatorMiddleName': _operatorMiddleNameController.text.trim(),
          'operatorLastName': _operatorLastNameController.text.trim(),
          'operatorAddress': _operatorAddressController.text.trim(),
          'businessAddress': address,
        };
        baseRequestData['businessDetails'] = businessDetailsPayload;
        profilePatchPayload['savedBusinessProfile'] = businessDetailsPayload;
      }
    
      if (widget.documentType == 'Certification (Late) Registration') {
        final fatherFull = _joinName(_fatherFirstNameController.text.trim(), _fatherMiddleNameController.text.trim(), _fatherLastNameController.text.trim());
        final motherFull = _joinName(_motherFirstNameController.text.trim(), _motherMiddleNameController.text.trim(), _motherLastNameController.text.trim());
    
        baseRequestData['birthDate'] = _birthDateController.text.trim();
        baseRequestData['placeOfBirth'] = _placeOfBirthController.text.trim();
        baseRequestData['fatherName'] = fatherFull;
        baseRequestData['motherName'] = motherFull;
    
        parentsInfoPayload = {
          'fatherName': fatherFull,
          'fatherFirstName': _fatherFirstNameController.text.trim(),
          'fatherMiddleName': _fatherMiddleNameController.text.trim(),
          'fatherLastName': _fatherLastNameController.text.trim(),
          'motherName': motherFull,
          'motherFirstName': _motherFirstNameController.text.trim(),
          'motherMiddleName': _motherMiddleNameController.text.trim(),
          'motherLastName': _motherLastNameController.text.trim(),
        };
        profilePatchPayload['savedParentsInfo'] = parentsInfoPayload;
      }

      if (widget.documentType == 'Certificate of Cohabitation') {
        final address = _useManualAddress
            ? { 'street': _streetAddressController.text.trim(), 'barangay': _manualBarangayController.text.trim(), 'municipality': _manualMunicipalityController.text.trim(), 'province': _manualProvinceController.text.trim() }
            : { 'street': _streetAddressController.text.trim(), 'barangay': _selectedBarangay?.name, 'barangayCode': _selectedBarangay?.code, 'municipality': _selectedMunicipality?.name, 'municipalityCode': _selectedMunicipality?.code, 'province': _selectedProvince?.name, 'provinceCode': _selectedProvince?.code };

        final partnerFull = _joinName(_partnerFirstNameController.text.trim(), _partnerMiddleNameController.text.trim(), _partnerLastNameController.text.trim());

        baseRequestData['birthDate'] = _requesterBirthDateController.text.trim();
        baseRequestData['partnerName'] = partnerFull;
        baseRequestData['partnerBirthDate'] = _partnerBirthDateController.text.trim();
        baseRequestData['cohabitationStartDate'] = _cohabitationStartDateController.text.trim();

        cohabitationPayload = {
          'partnerName': partnerFull,
          'partnerFirstName': _partnerFirstNameController.text.trim(),
          'partnerMiddleName': _partnerMiddleNameController.text.trim(),
          'partnerLastName': _partnerLastNameController.text.trim(),
          'partnerBirthDate': _partnerBirthDateController.text.trim(),
          'cohabitationStartDate': _cohabitationStartDateController.text.trim(),
          'cohabitationAddress': address,
        };
        baseRequestData['cohabitationDetails'] = cohabitationPayload;
        profilePatchPayload['savedCohabitationDetails'] = cohabitationPayload;
      }

      if (widget.documentType == 'Certificate of Seaweeds') {
        double amount = double.tryParse(_seaweedsAmountFiguresController.text.replaceAll(',', '')) ?? 0.0;
        String amountInWords = convertToCurrencyWords(amount);
        String amountInFigures = NumberFormat("#,##0.00", "en_US").format(amount);

        String quantityStr = _seaweedsQuantityController.text.trim();
        double quantityVal = double.tryParse(quantityStr) ?? 0;
        String unit = _selectedSeaweedsUnit ?? "";
        if (quantityVal == 1.0 && unit.endsWith('s')) unit = unit.substring(0, unit.length - 1); 
        String fullQuantity = "$quantityStr $unit";

        final buyerFull = _joinName(_seaweedsBuyerFirstNameController.text.trim(), _seaweedsBuyerMiddleNameController.text.trim(), _seaweedsBuyerLastNameController.text.trim());

        seaweedsPayload = {
          'buyerName': buyerFull,
          'buyerFirstName': _seaweedsBuyerFirstNameController.text.trim(),
          'buyerMiddleName': _seaweedsBuyerMiddleNameController.text.trim(),
          'buyerLastName': _seaweedsBuyerLastNameController.text.trim(),
          'quantity': fullQuantity, 
          'amountWords': amountInWords,
          'amountFigures': amountInFigures,
        };
        baseRequestData['seaweedsDetails'] = seaweedsPayload;
        profilePatchPayload['savedSeaweedsDetails'] = seaweedsPayload;
      }
    
      final dbRef = FirebaseDatabase.instance.ref();
      final requestId = dbRef.child('all_requests').push().key!;
      final Map<String, dynamic> allRequestsPayload = { ...baseRequestData, 'userId': widget.uid, 'userEmail': widget.email, 'fullName': completeName };
      final Map<String, dynamic> multiPathUpdate = { 'all_requests/$requestId': allRequestsPayload, 'users/${widget.uid}/requests/$requestId': baseRequestData };
    
      await dbRef.update(multiPathUpdate);
      if (profilePatchPayload.isNotEmpty) { await dbRef.child('users/${widget.uid}').update(profilePatchPayload); }
        
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      await _showSuccessDialog();
    
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error submitting request: $e"), backgroundColor: Colors.red));
    }
  }

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
            // ---------------------------------------------------------
            // FIX: Wrap the Column in a SingleChildScrollView
            // ---------------------------------------------------------
            child: SingleChildScrollView( 
              physics: const BouncingScrollPhysics(),
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
          ),
        );
      },
    );
  }
  Future<void> _validateAndConfirm() async {
    // 1. Close the keyboard
    FocusScope.of(context).unfocus();
   // Wait 300ms for the keyboard animation to finish and the screen to stabilize
    await Future.delayed(const Duration(milliseconds: 300)); 
    // 2. Validate form
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        // 4. Use SafeArea to ensure we don't draw under system bars
        return SafeArea(
          child: Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            elevation: 16,
            insetPadding: const EdgeInsets.all(16), // Gives space from screen edges
            child: ConstrainedBox(
              constraints: BoxConstraints(
                // Max height 85% of screen
                maxHeight: MediaQuery.of(context).size.height * 0.85, 
                maxWidth: 400,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min, // Wrap content height
                children: [
                  // --- HEADER ---
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.deepPurple.shade400, Colors.deepPurple.shade600],
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      ),
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(20), 
                        topRight: Radius.circular(20)
                      ),
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
                  
                  // --- BODY (Flexible allows scrolling) ---
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
                            _buildDetailRow(icon: Icons.person_outline, label: "Title", value: _toTitleCase(_userTitle), color: Colors.blue),
                            const SizedBox(height: 12),
                          ],
                          _buildDetailRow(icon: Icons.account_circle, label: "Full Name", value: _getFullNameWithoutTitle(), color: Colors.green),
                          
                          // --- SEAWEEDS ---
                          if (widget.documentType == 'Certificate of Seaweeds') ...[
                            const SizedBox(height: 20),
                            _buildSectionHeader("Seaweeds Sale Details"),
                            const SizedBox(height: 12),
                            _buildDetailRow(icon: Icons.person_search, label: "Buyer's Name", value: _joinName(_seaweedsBuyerFirstNameController.text.trim(), _seaweedsBuyerMiddleNameController.text.trim(), _seaweedsBuyerLastNameController.text.trim()), color: Colors.orange),
                            const SizedBox(height: 12),
                            Builder(builder: (context) {
                              String qtyStr = _seaweedsQuantityController.text.trim();
                              double qtyVal = double.tryParse(qtyStr) ?? 0;
                              String unit = _selectedSeaweedsUnit ?? "";
                              if (qtyVal == 1.0 && unit.endsWith('s')) unit = unit.substring(0, unit.length - 1);
                              return _buildDetailRow(icon: Icons.shopping_bag, label: "Quantity", value: "$qtyStr $unit", color: Colors.teal);
                            }),
                            const SizedBox(height: 12),
                            _buildDetailRowWithWidgetIcon(
                              icon: const Text("₱", style: TextStyle(fontSize: 20, color: Colors.green, fontWeight: FontWeight.bold)), 
                              label: "Amount (to be printed)",
                              value: "${convertToCurrencyWords(double.tryParse(_seaweedsAmountFiguresController.text.replaceAll(',', '')) ?? 0)} (₱${_seaweedsAmountFiguresController.text})",
                              color: Colors.green,
                            ),
                          ],

                          // --- BUSINESS ---
                          if (widget.documentType == 'Barangay Business Clearance') ...[
                            const SizedBox(height: 20),
                            _buildSectionHeader("Business Information"),
                            const SizedBox(height: 12),
                            _buildDetailRow(icon: Icons.business, label: "Business Name", value: _businessNameController.text.trim(), color: Colors.orange),
                            const SizedBox(height: 12),
                            _buildDetailRow(icon: Icons.location_on, label: "Business Address", value: _getFormattedBusinessAddress(), color: Colors.red),
                            const SizedBox(height: 12),
                            _buildDetailRow(icon: Icons.supervised_user_circle, label: "Operator/Manager", value: _joinName(_operatorFirstNameController.text.trim(), _operatorMiddleNameController.text.trim(), _operatorLastNameController.text.trim()), color: Colors.teal),
                            const SizedBox(height: 12),
                            _buildDetailRow(icon: Icons.location_city, label: "Operator Address", value: _operatorAddressController.text.trim(), color: Colors.indigo),
                          ],

                          // --- COHABITATION ---
                          if (widget.documentType == 'Certificate of Cohabitation') ...[
                            const SizedBox(height: 20),
                            _buildSectionHeader("Cohabitation Details"),
                            const SizedBox(height: 12),
                            _buildDetailRow(icon: Icons.cake, label: "My Birth Date", value: _requesterBirthDateController.text.trim(), color: Colors.blue),
                            const SizedBox(height: 12),
                            _buildDetailRow(icon: Icons.people_outline, label: "Partner's Name", value: _joinName(_partnerFirstNameController.text.trim(), _partnerMiddleNameController.text.trim(), _partnerLastNameController.text.trim()), color: Colors.pink),
                            const SizedBox(height: 12),
                            _buildDetailRow(icon: Icons.cake, label: "Partner's Birthdate", value: _partnerBirthDateController.text.trim(), color: Colors.purple),
                            const SizedBox(height: 12),
                            _buildDetailRow(icon: Icons.date_range, label: "Living Together Since", value: _cohabitationStartDateController.text.trim(), color: Colors.teal),
                            const SizedBox(height: 12),
                            _buildDetailRow(icon: Icons.maps_home_work, label: "Shared Address", value: _getFormattedBusinessAddress(), color: Colors.brown),
                          ],

                          // --- LATE REG ---
                          if (widget.documentType == 'Certification (Late) Registration') ...[
                            const SizedBox(height: 20),
                            _buildSectionHeader("Birth Information"),
                            const SizedBox(height: 12),
                            _buildDetailRow(icon: Icons.cake, label: "Birth Date", value: _birthDateController.text.trim(), color: Colors.pink),
                            const SizedBox(height: 12),
                            _buildDetailRow(icon: Icons.location_on, label: "Place of Birth", value: _placeOfBirthController.text.trim(), color: Colors.amber),
                            const SizedBox(height: 12),
                            _buildDetailRow(icon: Icons.male, label: "Father's Name", value: _joinName(_fatherFirstNameController.text.trim(), _fatherMiddleNameController.text.trim(), _fatherLastNameController.text.trim()), color: Colors.blue),
                            const SizedBox(height: 12),
                            _buildDetailRow(icon: Icons.female, label: "Mother's Name", value: _joinName(_motherFirstNameController.text.trim(), _motherMiddleNameController.text.trim(), _motherLastNameController.text.trim()), color: Colors.purple),
                          ],
                          const SizedBox(height: 20),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.blue.shade200)),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(Icons.info_outline, color: Colors.blue.shade600, size: 20),
                                const SizedBox(width: 8),
                                Expanded(child: Text("Your document request will be saved and processed by the barangay office. You will be notified once it's ready for pickup.", style: TextStyle(color: Colors.blue.shade700, fontSize: 12))),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  
                  // --- BUTTONS ---
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(20), bottomRight: Radius.circular(20)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: () => Navigator.of(context).pop(false),
                            style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: Colors.grey.shade400))),
                            child: Text("Cancel", style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.w600, fontSize: 16)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () => Navigator.of(context).pop(true),
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple, padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)), elevation: 2),
                            child: const Text("Confirm", style: TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.bold)),
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
      },
    );
    
    if (confirmed == true) {
      _submitRequest();
    }
  }
  
    // --- UI HELPER METHODS ---

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
        mainAxisSize: MainAxisSize.min, 
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
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
            child: Text(
              value.isEmpty ? "N/A" : value,
              style: TextStyle(
                fontSize: 15, 
                color: Colors.grey.shade800, 
                fontWeight: FontWeight.w500,
                height: 1.3,
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
            crossAxisAlignment: CrossAxisAlignment.start, 
            children: [
              icon, 
              const SizedBox(width: 8), 
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
  // --- REUSABLE WIDGET FOR SPLIT NAME ---
  // --- REUSABLE NAME GROUP WIDGET (With Required Icons) ---
  Widget _buildNameGroup(String labelPrefix, TextEditingController f, TextEditingController m, TextEditingController l) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(labelPrefix, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 8),
        // FIRST NAME
        TextFormField(
          controller: f,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            labelText: "First Name",
            prefixIcon: const Icon(Icons.person),
            suffixIcon: const Icon(Icons.star, color: Colors.red, size: 10), // Required Icon
          ),
          validator: (v) => (v == null || v.trim().isEmpty) ? "First name required" : null,
        ),
        const SizedBox(height: 12),
        // MIDDLE NAME
        TextFormField(
          controller: m,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: "Middle Name (Optional)",
            prefixIcon: Icon(Icons.person_outline),
          ),
        ),
        const SizedBox(height: 12),
        // LAST NAME
        TextFormField(
          controller: l,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            labelText: "Last Name",
            prefixIcon: const Icon(Icons.person),
            suffixIcon: const Icon(Icons.star, color: Colors.red, size: 10), // Required Icon
          ),
          validator: (v) => (v == null || v.trim().isEmpty) ? "Last name required" : null,
        ),
      ],
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
                  decoration: const InputDecoration(labelText: "Purok (e.g., Purok or Sitio)", prefixIcon: Icon(Icons.location_on)),
                  validator: (value) => value == null || value.isEmpty ? "Purok or Sitio is required" : null,
                ),
                const SizedBox(height: 16),
              ],

              // --- BUSINESS SPECIFIC FIELDS ---
              if (isBusiness) ...[
                TextFormField(
                  controller: _businessNameController,
                  decoration: InputDecoration(
                    labelText: "Business Name/Trade Activity",
                    prefixIcon: const Icon(Icons.business),
                    suffixIcon: const Icon(Icons.star, color: Colors.red, size: 10), // Required
                  ),
                  validator: (v) => (v == null || v.isEmpty) ? "Business name required" : null,
                ),
                const SizedBox(height: 16),
                
                // SPLIT OPERATOR NAME
                _buildNameGroup("Operator/Manager", _operatorFirstNameController, _operatorMiddleNameController, _operatorLastNameController),
                const SizedBox(height: 16),

                TextFormField(
                  controller: _operatorAddressController,
                  decoration: InputDecoration(labelText: "Operator/Manager Address", prefixIcon: const Icon(Icons.location_city), suffixIcon: const Icon(Icons.star, color: Colors.red, size: 10)),
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

                // SPLIT PARTNER NAME
                _buildNameGroup("Partner's Full Name", _partnerFirstNameController, _partnerMiddleNameController, _partnerLastNameController),
                const SizedBox(height: 16),

                TextFormField(
                  controller: _partnerBirthDateController,
                  readOnly: true,
                  decoration: InputDecoration(labelText: "Partner's Birth Date", prefixIcon: const Icon(Icons.cake), suffixIcon: const Icon(Icons.star, color: Colors.red, size: 10)),
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
                  decoration: InputDecoration(labelText: "Living Together Since", prefixIcon: const Icon(Icons.date_range), suffixIcon: const Icon(Icons.star, color: Colors.red, size: 10)),
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
                // SPLIT BUYER NAME
                _buildNameGroup("Buyer's Full Name", _seaweedsBuyerFirstNameController, _seaweedsBuyerMiddleNameController, _seaweedsBuyerLastNameController),
                const SizedBox(height: 16),
                
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
                    prefixIcon: Container(
                      width: 48,
                      alignment: Alignment.center,
                      child: const Text("₱", 
                        style: TextStyle(fontSize: 20, color: Colors.grey, fontWeight: FontWeight.bold)
                      ),
                    ),
                    suffixIcon: const Icon(Icons.star, color: Colors.red, size: 10),
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

              // --- LATE REG FIELDS ---
              if (isLateReg) ...[
                // Info Banner
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

                // Birth Date Field
                TextFormField(
                  controller: _birthDateController,
                  readOnly: !_profileLoadFailed, 
                  decoration: const InputDecoration(
                    labelText: "Birth Date", 
                    prefixIcon: Icon(Icons.cake)
                  ),
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

                // Place of Birth Field
                TextFormField(
                  controller: _placeOfBirthController,
                  readOnly: !_profileLoadFailed,
                  decoration: const InputDecoration(
                    labelText: "Place of Birth", 
                    prefixIcon: Icon(Icons.location_on)
                  ),
                  validator: (v) => (v == null || v.isEmpty) ? "Place of birth is required." : null,
                ),
                const SizedBox(height: 16),
                
                // SPLIT FATHER NAME (First, Middle, Last)
                _buildNameGroup(
                  "Father's Name", 
                  _fatherFirstNameController, 
                  _fatherMiddleNameController, 
                  _fatherLastNameController
                ),
                const SizedBox(height: 16),
                
                // SPLIT MOTHER NAME (First, Middle, Last)
                _buildNameGroup(
                  "Mother's Name", 
                  _motherFirstNameController, 
                  _motherMiddleNameController, 
                  _motherLastNameController
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