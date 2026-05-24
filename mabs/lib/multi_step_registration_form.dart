// lib/multi_step_registration_form.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

// Ensure you have this package in pubspec.yaml
import 'package:dropdown_search/dropdown_search.dart'; 
import 'package:mabs/firebase_service.dart'; 
import 'package:mabs/login_screen.dart'; 
import 'package:mabs/psgc_api_service.dart'; 
import 'package:mabs/otp_verification_screen.dart'; 

class TitleCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) return newValue;
    String newText = newValue.text.split(' ').map((word) {
      if (word.isEmpty) return '';
      return word[0].toUpperCase() + word.substring(1).toLowerCase();
    }).join(' ');

    return newValue.copyWith(
      text: newText,
      selection: newValue.selection,
    );
  }
}

class MultiStepRegistrationForm extends StatefulWidget {
  const MultiStepRegistrationForm({super.key});

  @override
  _MultiStepRegistrationFormState createState() => _MultiStepRegistrationFormState();
}

class _MultiStepRegistrationFormState extends State<MultiStepRegistrationForm> {
  final PageController _pageController = PageController();
  final GlobalKey<FormState> _formKeyStep1 = GlobalKey<FormState>();
  final GlobalKey<FormState> _formKeyStep2 = GlobalKey<FormState>();
  final GlobalKey<FormState> _formKeyStep3 = GlobalKey<FormState>();

  final ValueNotifier<bool> _isStep1Complete = ValueNotifier(false);
  final ValueNotifier<bool> _isStep2Complete = ValueNotifier(false);
  final ValueNotifier<bool> _isStep3Complete = ValueNotifier(false);

  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  bool _isEmailRegistration = true; 
  int _currentPage = 0;
  bool isLoading = false;


  final TextEditingController emailController = TextEditingController();
  final TextEditingController phoneNumberController = TextEditingController(); 
  final TextEditingController usernameController = TextEditingController();
  final TextEditingController firstNameController = TextEditingController();
  final TextEditingController middleNameController = TextEditingController();
  final TextEditingController lastNameController = TextEditingController();
  final TextEditingController addressController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController confirmPasswordController = TextEditingController();
  final TextEditingController birthdateController = TextEditingController();

  String? _selectedTitle;
  String? _selectedSex;
  DateTime? _selectedBirthDate;

  // --- UPDATED ADDRESS VARIABLES (Using Objects instead of just Strings) ---
  final PsgcApiService _psgcApiService = PsgcApiService();
  List<Province> _provinces = [];
  List<Municipality> _municipalities = [];
  List<Barangay> _barangays = [];

  Province? _selectedProvince;
  Municipality? _selectedMunicipality;
  Barangay? _selectedBarangay;

  // Loading states for dropdowns
  bool _isProvincesLoading = false;
  bool _isMunicipalitiesLoading = false;
  bool _isBarangaysLoading = false;

  final RegExp _nameCharactersRegex = RegExp(r"^[a-zA-Z\s]+$");
  final ValueNotifier<String?> _passwordErrorNotifier = ValueNotifier<String?>(null);
  final String _passwordDetailedError =
      "Your password must be at least 6 characters long. For stronger security, it is recommended to include a mix of uppercase letters, lowercase letters, numbers, and symbols.";

  @override
  void initState() {
    super.initState();
    _loadProvinces(); // Load data on start


    firstNameController.addListener(_checkStep1Completion);
    lastNameController.addListener(_checkStep1Completion);
    

    // Account listeners
    emailController.addListener(_checkStep3Completion);
    phoneNumberController.addListener(_checkStep3Completion); 
    usernameController.addListener(_checkStep3Completion);
    passwordController.addListener(_checkStep3Completion);
    confirmPasswordController.addListener(_checkStep3Completion);
  }

  void _checkStep1Completion() {
    final isComplete = firstNameController.text.trim().isNotEmpty &&
        lastNameController.text.trim().isNotEmpty &&
        _selectedTitle != null &&
        _selectedSex != null &&
        _selectedBirthDate != null;
    _isStep1Complete.value = isComplete;
  }

  void _checkStep2Completion() {
    // Notice that addressController is COMPLETELY GONE from here
    final isComplete = _selectedProvince != null &&
        _selectedMunicipality != null &&
        _selectedBarangay != null;
        
    _isStep2Complete.value = isComplete;
  }

  void _checkStep3Completion() {
    bool isIdentifierValid;
    if (_isEmailRegistration) {
      isIdentifierValid = emailController.text.trim().isNotEmpty;
    } else {
      isIdentifierValid = phoneNumberController.text.trim().length == 9; 
    }
    
    final bool passwordValid = _isEmailRegistration 
      ? (passwordController.text.trim().isNotEmpty && confirmPasswordController.text.trim().isNotEmpty)
      : true;

    final isComplete = isIdentifierValid &&
        usernameController.text.trim().isNotEmpty &&
        passwordValid;
        
    _isStep3Complete.value = isComplete;
  }

  // --- DATA LOADING FUNCTIONS ---

  Future<void> _loadProvinces() async {
    setState(() => _isProvincesLoading = true);
    try {
      final data = await _psgcApiService.fetchProvinces();
      if (mounted) {
        setState(() {
          _provinces = data;
          _isProvincesLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isProvincesLoading = false);
    }
  }

  void _onProvinceChanged(Province? p) async {
    if (p == null) return;
    setState(() {
      _selectedProvince = p;
      // Reset children
      _selectedMunicipality = null;
      _selectedBarangay = null;
      _municipalities = [];
      _barangays = [];
      _isMunicipalitiesLoading = true;
      _checkStep2Completion();
    });

    try {
      final data = await _psgcApiService.fetchMunicipalities(p.code);
      if (mounted) {
        setState(() {
          _municipalities = data;
          _isMunicipalitiesLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isMunicipalitiesLoading = false);
    }
  }

  void _onMunicipalityChanged(Municipality? m) async {
    if (m == null) return;
    setState(() {
      _selectedMunicipality = m;
      // Reset child
      _selectedBarangay = null;
      _barangays = [];
      _isBarangaysLoading = true;
      _checkStep2Completion();
    });

    try {
      final data = await _psgcApiService.fetchBarangays(m.code);
      if (mounted) {
        setState(() {
          _barangays = data;
          _isBarangaysLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isBarangaysLoading = false);
    }
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context, 
      initialDate: _selectedBirthDate ?? DateTime(2000), 
      firstDate: DateTime(1900), 
      lastDate: DateTime.now(), 
      helpText: 'Select Birth Date'
    );
    if (picked != null && picked != _selectedBirthDate) {
      setState(() {
        _selectedBirthDate = picked;
        birthdateController.text = DateFormat('MM/dd/yyyy').format(picked);
        _checkStep1Completion();
      });
    }
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) return "Password is required.";
    if (value.length < 6) return "Password must be at least 6 characters.";
    return null;
  }

  void _nextPage() {
    FocusScope.of(context).unfocus();
    bool isValid = _currentPage == 0 ? _formKeyStep1.currentState!.validate() : _formKeyStep2.currentState!.validate();
    if (!isValid) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please fix the errors before proceeding.")));
      return;
    }
    if (_currentPage < 2) {
      _pageController.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeIn);
      setState(() => _currentPage++);
    }
  }

  void _previousPage() {
    FocusScope.of(context).unfocus();
    if (_currentPage > 0) {
      _pageController.previousPage(duration: const Duration(milliseconds: 300), curve: Curves.easeIn);
      setState(() => _currentPage--);
    }
  }

  void _signUp() async {
    FocusScope.of(context).unfocus();
    if (!_formKeyStep3.currentState!.validate()) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please fix the errors before proceeding.")));
      return;
    }
    
    if (_isEmailRegistration) {
      // 1. Email Flow
      setState(() => isLoading = true);
      try {
        final result = await FirebaseService().signUp(
          email: emailController.text.trim(),
          username: usernameController.text.trim(),
          title: _selectedTitle!.trim(),
          firstName: firstNameController.text.trim(),
          middleName: middleNameController.text.trim(),
          lastName: lastNameController.text.trim(),
          street: addressController.text.trim(),
          password: passwordController.text.trim(),
          role: 'user',
          birthdate: _selectedBirthDate?.toIso8601String(),
          sex: _selectedSex,
          // Extract names from objects
          province: _selectedProvince?.name,
          municipality: _selectedMunicipality?.name,
          barangay: _selectedBarangay?.name,
        );
        
        setState(() => isLoading = false);
        
        if (result != null) {
          Navigator.push(context, MaterialPageRoute(builder: (_) => OtpVerificationScreen(
            identifier: emailController.text.trim(),
            isEmail: true,
            uid: result.uid,
            token: result.token, // <--- ADD THIS LINE HERE
            username: usernameController.text.trim(),
          )));
        }
      } catch (e) {
        setState(() => isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Sign Up Failed: $e")));
      }
    } else {
      // 2. Phone Flow
      String fullPhoneNumber = "09${phoneNumberController.text.trim()}"; 
      final pendingData = {
        'username': usernameController.text.trim(),
        'title': _selectedTitle!.trim(),
        'firstName': firstNameController.text.trim(),
        'middleName': middleNameController.text.trim(),
        'lastName': lastNameController.text.trim(),
        'street': addressController.text.trim(),
        'birthdate': _selectedBirthDate?.toIso8601String(),
        'sex': _selectedSex,
        'province': _selectedProvince?.name,
        'municipality': _selectedMunicipality?.name,
        'barangay': _selectedBarangay?.name,
      };

      Navigator.push(context, MaterialPageRoute(builder: (_) => OtpVerificationScreen(
          identifier: fullPhoneNumber,
         isEmail: false,
         pendingUserData: pendingData,
      )));
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    firstNameController.removeListener(_checkStep1Completion);
    lastNameController.removeListener(_checkStep1Completion);
    addressController.removeListener(_checkStep2Completion);
    emailController.removeListener(_checkStep3Completion);
    phoneNumberController.removeListener(_checkStep3Completion);
    usernameController.removeListener(_checkStep3Completion);
    passwordController.removeListener(_checkStep3Completion);
    confirmPasswordController.removeListener(_checkStep3Completion);
    
    emailController.dispose();
    phoneNumberController.dispose();
    usernameController.dispose();
    firstNameController.dispose();
    middleNameController.dispose();
    lastNameController.dispose();
    addressController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();
    birthdateController.dispose();
    _passwordErrorNotifier.dispose();
    _isStep1Complete.dispose();
    _isStep2Complete.dispose();
    _isStep3Complete.dispose();
    super.dispose();
  }

  // --- HELPER: Dropdown Decoration ---
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Register"), backgroundColor: Colors.deepPurple, foregroundColor: Colors.white),
      body: Stack(
        children: [
          Container(
            decoration: BoxDecoration(gradient: LinearGradient(colors: [Colors.deepPurple.shade400, Colors.deepPurple.shade200], begin: Alignment.topCenter, end: Alignment.bottomCenter)),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(3, (index) => Container(
                      margin: const EdgeInsets.symmetric(horizontal: 4.0),
                      width: 12.0,
                      height: 12.0,
                      decoration: BoxDecoration(shape: BoxShape.circle, 
                      color: _currentPage == index ? const Color.fromARGB(255, 253, 229, 13) : Colors.deepPurple.shade100, 
                      border: Border.all(color: const Color.fromARGB(255, 253, 229, 13))),
                    )),
                  ),
                ),
                Expanded(
                  child: PageView(
                    controller: _pageController,
                    physics: const NeverScrollableScrollPhysics(),
                    onPageChanged: (index) => setState(() => _currentPage = index),
                    children: [_buildStep1(), _buildStep2(), _buildStep3()],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      if (_currentPage > 0) ElevatedButton(onPressed: _previousPage, child: const Text("Previous")),
                      const Spacer(),
                      if (_currentPage == 0) ValueListenableBuilder<bool>(valueListenable: _isStep1Complete, builder: (context, isComplete, child) => ElevatedButton(onPressed: isComplete ? _nextPage : null, child: child), child: const Text("Next")),
                      if (_currentPage == 1) ValueListenableBuilder<bool>(valueListenable: _isStep2Complete, builder: (context, isComplete, child) => ElevatedButton(onPressed: isComplete ? _nextPage : null, child: child), child: const Text("Next")),
                      if (_currentPage == 2) ValueListenableBuilder<bool>(valueListenable: _isStep3Complete, builder: (context, isComplete, child) {
                        if (isLoading) return const CircularProgressIndicator();
                        return ElevatedButton(onPressed: isComplete ? _signUp : null, child: child);
                      }, child: const Text("Register")),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const LoginScreen())),
                  child: const Text("Already have an account? Login", style: TextStyle(color: Colors.white)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStep1() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Center(
        child: Card(
          elevation: 8.0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          margin: const EdgeInsets.symmetric(horizontal: 16.0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 450, maxWidth: 600),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: Form(
                key: _formKeyStep1,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Personal Information', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.deepPurple)),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      decoration: const InputDecoration(labelText: "Title", prefixIcon: Icon(Icons.person_outline), border: OutlineInputBorder()),
                      initialValue: _selectedTitle,
                      hint: const Text("Select Title"),
                      onChanged: (String? newValue) {
                        setState(() {
                          _selectedTitle = newValue;
                          _checkStep1Completion();
                        });
                      },
                      validator: (value) => value == null || value.isEmpty ? "Please select a title." : null,
                      items: <String>['Mr.', 'Ms.', 'Mrs.'].map((String value) => DropdownMenuItem<String>(value: value, child: Text(value))).toList(),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: firstNameController,
                      decoration: const InputDecoration(labelText: "First Name", prefixIcon: Icon(Icons.person)),
                      textCapitalization: TextCapitalization.words,
                      inputFormatters: [TitleCaseTextFormatter()],
                      validator: (value) {
                        if (value == null || value.isEmpty) return "First name is required.";
                        if (!_nameCharactersRegex.hasMatch(value)) return "First name can only contain letters and spaces.";
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: middleNameController,
                      decoration: const InputDecoration(labelText: "Middle Name (Optional)", prefixIcon: Icon(Icons.person)),
                      textCapitalization: TextCapitalization.words,
                      inputFormatters: [TitleCaseTextFormatter()],
                      validator: (value) {
                        if (value != null && value.isNotEmpty && !_nameCharactersRegex.hasMatch(value)) return "Middle name can only contain letters and spaces.";
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: lastNameController,
                      decoration: const InputDecoration(labelText: "Last Name", prefixIcon: Icon(Icons.person)),
                      textCapitalization: TextCapitalization.words,
                      inputFormatters: [TitleCaseTextFormatter()],
                      validator: (value) {
                        if (value == null || value.isEmpty) return "Last name is required.";
                        if (!_nameCharactersRegex.hasMatch(value)) return "Last name can only contain letters and spaces.";
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      decoration: const InputDecoration(labelText: "Sex", prefixIcon: Icon(Icons.wc), border: OutlineInputBorder()),
                      initialValue: _selectedSex,
                      hint: const Text("Select Sex"),
                      onChanged: (String? newValue) {
                        setState(() {
                          _selectedSex = newValue;
                          _checkStep1Completion();
                        });
                      },
                      validator: (value) => value == null || value.isEmpty ? "Please select your sex." : null,
                      items: <String>['Male', 'Female'].map((String value) => DropdownMenuItem<String>(value: value, child: Text(value))).toList(),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: birthdateController,
                      readOnly: true,
                      onTap: () => _selectDate(context),
                      decoration: const InputDecoration(labelText: "Birthdate", prefixIcon: Icon(Icons.calendar_today), border: OutlineInputBorder()),
                      validator: (value) => value == null || value.isEmpty ? "Birthdate is required." : null,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // --- FIXED STEP 2: ADDRESS WITH DROPDOWN SEARCH ---
// --- FIXED STEP 2: ADDRESS WITH DROPDOWN SEARCH ---
  Widget _buildStep2() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Center(
        child: Card(
          elevation: 8.0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          margin: const EdgeInsets.symmetric(horizontal: 16.0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 450, maxWidth: 600),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: Form(
                key: _formKeyStep2,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // ===== EYE-CATCHING TITLE WITH ICON =====
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.child_friendly, color: Colors.deepPurple, size: 28),
                        const SizedBox(width: 8),
                        Flexible(
                          child: const Text(
                            'Birth Place', 
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.deepPurple,
                            ),
                            textAlign: TextAlign.center, 
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // ===== SECONDARY HINT (BLUE TIP) =====
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.lightbulb_outline, color: Colors.blue.shade700, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              "Tip: Check your birth certificate for your birthplace.",
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.blue.shade700,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // 1. PROVINCE DROPDOWN
                    DropdownSearch<Province>(
                      // Disable if provinces are still loading on startup
                      enabled: !_isProvincesLoading, 
                      popupProps: PopupProps.modalBottomSheet(
                        showSearchBox: true,
                        title: Container(
                          padding: const EdgeInsets.all(16),
                          child: const Text("Select Province (Birthplace)", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        ),
                        searchFieldProps: const TextFieldProps(
                          decoration: InputDecoration(
                            hintText: "Search Province...",
                            prefixIcon: Icon(Icons.search),
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(horizontal: 12),
                          ),
                        ),
                        // Added to handle empty search results nicely
                        emptyBuilder: (context, searchEntry) => const Center(child: Text("No province found", style: TextStyle(color: Colors.grey))),
                      ),
                      items: (filter, loadProps) {
                        if (filter.isEmpty) return _provinces;
                        return _provinces.where((p) => p.name.toLowerCase().contains(filter.toLowerCase())).toList();
                      },
                      itemAsString: (Province p) => p.name,
                      selectedItem: _selectedProvince,
                      compareFn: (item, selectedItem) => item.code == selectedItem.code,
                      decoratorProps: DropDownDecoratorProps(
                        decoration: _getDropdownDecoration('Province (Birth)', Icons.map_outlined, !_isProvincesLoading, _isProvincesLoading),
                      ),
                      onChanged: _onProvinceChanged,
                      validator: (v) => v == null ? 'Province is required' : null,
                    ),
                    const SizedBox(height: 16),

                    // 2. MUNICIPALITY DROPDOWN
                    DropdownSearch<Municipality>(
                      // --- FIX: Only enable if province is selected AND it is NOT loading ---
                      enabled: _selectedProvince != null && !_isMunicipalitiesLoading,
                      popupProps: PopupProps.modalBottomSheet(
                        showSearchBox: true,
                        title: Container(
                          padding: const EdgeInsets.all(16),
                          child: const Text("Select Municipality/City (Birthplace)", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        ),
                        searchFieldProps: const TextFieldProps(
                          decoration: InputDecoration(
                            hintText: "Search Municipality...",
                            prefixIcon: Icon(Icons.search),
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(horizontal: 12),
                          ),
                        ),
                        emptyBuilder: (context, searchEntry) => const Center(child: Text("No municipality found", style: TextStyle(color: Colors.grey))),
                      ),
                      items: (filter, loadProps) {
                        if (filter.isEmpty) return _municipalities;
                        return _municipalities.where((m) => m.name.toLowerCase().contains(filter.toLowerCase())).toList();
                      },
                      itemAsString: (Municipality m) => m.name,
                      selectedItem: _selectedMunicipality,
                      compareFn: (item, selectedItem) => item.code == selectedItem.code,
                      decoratorProps: DropDownDecoratorProps(
                        decoration: _getDropdownDecoration(
                          'Municipality/City (Birth)', 
                          Icons.location_city, 
                          // visually disabled while loading
                          _selectedProvince != null && !_isMunicipalitiesLoading, 
                          _isMunicipalitiesLoading
                        ),
                      ),
                      onChanged: _onMunicipalityChanged,
                      validator: (v) => v == null ? 'Municipality is required' : null,
                    ),
                    const SizedBox(height: 16),

                    // 3. BARANGAY DROPDOWN
                    DropdownSearch<Barangay>(
                      // --- FIX: Only enable if municipality is selected AND it is NOT loading ---
                      enabled: _selectedMunicipality != null && !_isBarangaysLoading,
                      popupProps: PopupProps.modalBottomSheet(
                        showSearchBox: true,
                        title: Container(
                          padding: const EdgeInsets.all(16),
                          child: const Text("Select Barangay (Birthplace)", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        ),
                        searchFieldProps: const TextFieldProps(
                          decoration: InputDecoration(
                            hintText: "Search Barangay...",
                            prefixIcon: Icon(Icons.search),
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(horizontal: 12),
                          ),
                        ),
                        emptyBuilder: (context, searchEntry) => const Center(child: Text("No barangay found", style: TextStyle(color: Colors.grey))),
                      ),
                      items: (filter, loadProps) {
                        if (filter.isEmpty) return _barangays;
                        return _barangays.where((b) => b.name.toLowerCase().contains(filter.toLowerCase())).toList();
                      },
                      itemAsString: (Barangay b) => b.name,
                      selectedItem: _selectedBarangay,
                      compareFn: (item, selectedItem) => item.code == selectedItem.code,
                      decoratorProps: DropDownDecoratorProps(
                        decoration: _getDropdownDecoration(
                          'Barangay (Birth)', 
                          Icons.holiday_village_outlined, 
                          // visually disabled while loading
                          _selectedMunicipality != null && !_isBarangaysLoading, 
                          _isBarangaysLoading
                        ),
                      ),
                      onChanged: (newValue) {
                        setState(() {
                          _selectedBarangay = newValue;
                          _checkStep2Completion();
                        });
                      },
                      validator: (v) => v == null ? 'Barangay is required' : null,
                    ),
                    const SizedBox(height: 16),

                    // 4. PUROK FIELD (OPTIONAL)
                    TextFormField(
                      controller: addressController,
                      decoration: const InputDecoration(
                        labelText: "Purok/Sitio (Optional)", 
                        hintText: "e.g., Purok 1, Sitio 2",
                        prefixIcon: Icon(Icons.home),
                      ),
                      validator: (value) => null, 
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
  
  Widget _buildStep3() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Center(
        child: Card(
          elevation: 8.0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          margin: const EdgeInsets.symmetric(horizontal: 16.0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 450, maxWidth: 600),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: Form(
                key: _formKeyStep3,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Account Information', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.deepPurple)),
                    const SizedBox(height: 16),

                    // --- NEW TOGGLE BUTTONS ---
                    Center(
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        margin: const EdgeInsets.only(bottom: 20),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            GestureDetector(
                              onTap: () => setState(() { _isEmailRegistration = true; _checkStep3Completion(); }),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
                                decoration: BoxDecoration(
                                  color: _isEmailRegistration ? Colors.white : Colors.transparent,
                                  borderRadius: BorderRadius.circular(10),
                                  boxShadow: _isEmailRegistration ? [const BoxShadow(color: Colors.black12, blurRadius: 4)] : [],
                                ),
                                child: const Text("Email", style: TextStyle(fontWeight: FontWeight.bold)),
                              ),
                            ),
                            GestureDetector(
                              onTap: () => setState(() { _isEmailRegistration = false; _checkStep3Completion(); }),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
                                decoration: BoxDecoration(
                                  color: !_isEmailRegistration ? Colors.white : Colors.transparent,
                                  borderRadius: BorderRadius.circular(10),
                                  boxShadow: !_isEmailRegistration ? [const BoxShadow(color: Colors.black12, blurRadius: 4)] : [],
                                ),
                                child: const Text("Phone", style: TextStyle(fontWeight: FontWeight.bold)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    if (_isEmailRegistration) ...[
                      // --- EMAIL INPUT ---
                      TextFormField(
                        controller: emailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(labelText: "Email", prefixIcon: Icon(Icons.email)),
                        validator: (value) {
                          if (value == null || value.isEmpty) return "Email is required.";
                          if (!RegExp(r'\S+@\S+\.\S+').hasMatch(value)) return "Please enter a valid email address.";
                          return null;
                        },
                      ),
                    ] else ...[
                      // --- PHONE INPUT ---
// --- PHONE INPUT ---
TextFormField(
  controller: phoneNumberController,
  keyboardType: TextInputType.phone,
  // 1. Force digits only, max 9 digits (since 09 is fixed)
  inputFormatters: [
    FilteringTextInputFormatter.digitsOnly,
    LengthLimitingTextInputFormatter(9), 
  ],
  decoration: const InputDecoration(
    labelText: "Mobile Number",
    // 2. This makes "09" appear fixed at the start
    prefixText: "09", 
    prefixStyle: TextStyle(color: Colors.black, fontSize: 16),
    hintText: "xxxxxxxxx", 
    prefixIcon: Icon(Icons.phone),
  ),
  validator: (value) {
      if (value == null || value.isEmpty) return "Mobile number is required.";
      // 3. Check for 9 digits (user input)
      if (value.length != 9) return "Enter the remaining 9 digits."; 
      return null;
  },
),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(8)
                        ),
                        child: const Text("We will send a 6-digit code to this number. No password required.", style: TextStyle(fontSize: 12, color: Colors.blue)),
                      )
                    ],
                    
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: usernameController,
                      decoration: const InputDecoration(labelText: "Username", prefixIcon: Icon(Icons.person)),
                      validator: (value) => value == null || value.isEmpty ? "Username is required." : null,
                    ),
                    const SizedBox(height: 16),
                    
                    // --- PASSWORD FIELDS (Only for Email) ---
                    if (_isEmailRegistration) ...[
                      ValueListenableBuilder<String?>(
                        valueListenable: _passwordErrorNotifier,
                        builder: (context, errorText, child) {
                          return TextFormField(
                            controller: passwordController,
                            obscureText: _obscurePassword,
                            decoration: InputDecoration(
                              labelText: "Password",
                              prefixIcon: const Icon(Icons.lock),
                              errorText: errorText,
                              suffixIcon: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (errorText != null)
                                    IconButton(
                                      icon: const Icon(Icons.info_outline, color: Colors.red),
                                      onPressed: () {
                                        showDialog(context: context, builder: (_) => AlertDialog(
                                          title: const Text("Password Requirements"),
                                          content: Text(_passwordDetailedError),
                                          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("OK"))],
                                        ));
                                      },
                                    ),
                                  IconButton(
                                    icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                                    onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                                  ),
                                ],
                              ),
                            ),
                            onChanged: (value) {
                              _passwordErrorNotifier.value = _validatePassword(value);
                              _checkStep3Completion();
                            },
                            validator: (value) => _validatePassword(value),
                          );
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: confirmPasswordController,
                        obscureText: _obscureConfirmPassword,
                        decoration: InputDecoration(
                          labelText: "Confirm Password",
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            icon: Icon(_obscureConfirmPassword ? Icons.visibility_off : Icons.visibility),
                            onPressed: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) return "Please confirm your password.";
                          if (value != passwordController.text) return "Passwords do not match.";
                          return null;
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}