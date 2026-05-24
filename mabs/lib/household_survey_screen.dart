// lib/household_survey_screen.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';

class HouseholdMember {
  String name;
  int age;
  String sex;
  String relationship;

  HouseholdMember({
    required this.name,
    required this.age,
    required this.sex,
    required this.relationship,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'age': age,
    'sex': sex,
    'relationship': relationship,
  };
}

class HouseholdSurveyScreen extends StatefulWidget {
  final String token;
  final String uid;
  final String fullName;

  const HouseholdSurveyScreen({
    Key? key,
    required this.token,
    required this.uid,
    required this.fullName,
  }) : super(key: key);

  @override
  _HouseholdSurveyScreenState createState() => _HouseholdSurveyScreenState();
}

class _HouseholdSurveyScreenState extends State<HouseholdSurveyScreen> {
  final _formKey = GlobalKey<FormState>();
  
  // Form Data
  String? _selectedPurok;
  String? _selectedSitio;
  final TextEditingController _headOfFamilyController = TextEditingController();
  final TextEditingController _headOfFamilyAgeController = TextEditingController(); 
  String _headOfFamilySex = 'Male'; 
  
  final TextEditingController _contactController = TextEditingController();
  final TextEditingController _incomeController = TextEditingController();
  
  // Household Members List
  List<HouseholdMember> _householdMembers = [];
  
  // Location Data
  double? _latitude;
  double? _longitude;
  bool _isGettingLocation = false;
  bool _isSubmitting = false;
  bool _hasUnsavedChanges = false;

  final List<String> puroks = ['Purok 1', 'Purok 2', 'Purok 3', 'Purok 4', 'Purok 5'];
  final List<String> sitios = ['Mainland', 'Island Area', 'Coastal'];
  final List<String> sexOptions = ['Male', 'Female'];
  final List<String> relationshipOptions = [
    'Head',
    'Spouse',
    'Son',
    'Daughter',
    'Father',
    'Mother',
    'Brother',
    'Sister',
    'Grandchild',
    'Other Relative'
  ];

  @override
  void initState() {
    super.initState();
    _headOfFamilyController.text = widget.fullName;
    
    // Add head of family as first member (Age is 0 initially until they type it)
    _householdMembers.add(HouseholdMember(
      name: widget.fullName,
      age: 0, 
      sex: _headOfFamilySex,
      relationship: 'Head',
    ));
    _addChangeListeners();
  }

  @override
  void dispose() {
    _headOfFamilyController.dispose();
    _headOfFamilyAgeController.dispose();
    _contactController.dispose();
    _incomeController.dispose();
    super.dispose();
  }

  void _addChangeListeners() {
    _headOfFamilyController.addListener(() => _setUnsavedChanges());
    _headOfFamilyAgeController.addListener(() => _setUnsavedChanges());
    _contactController.addListener(() => _setUnsavedChanges());
    _incomeController.addListener(() => _setUnsavedChanges());
  }

  void _setUnsavedChanges() {
    if (!_hasUnsavedChanges) {
      setState(() => _hasUnsavedChanges = true);
    }
  }

  // Sync Head of Family fields with the first item in the members list
  void _syncHeadOfFamily() {
    if (_householdMembers.isNotEmpty) {
      setState(() {
        _householdMembers[0].name = _headOfFamilyController.text.trim();
        _householdMembers[0].age = int.tryParse(_headOfFamilyAgeController.text) ?? 0;
        _householdMembers[0].sex = _headOfFamilySex;
      });
    }
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: GoogleFonts.lato(fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.lato(fontSize: 13, color: Colors.grey.shade700),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _getLocation() async {
    setState(() => _isGettingLocation = true);
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw Exception("Location permissions denied.");
        }
      }
      
      if (permission == LocationPermission.deniedForever) {
        throw Exception("Location permissions are permanently denied. Please enable in settings.");
      }

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 15),
      );
      
      setState(() {
        _latitude = position.latitude;
        _longitude = position.longitude;
        _setUnsavedChanges();
      });

    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString()),
          backgroundColor: Colors.red,
          action: SnackBarAction(
            label: 'Retry',
            textColor: Colors.white,
            onPressed: _getLocation,
          ),
        ),
      );
    } finally {
      setState(() => _isGettingLocation = false);
    }
  }

  Future<void> _submitSurvey() async {
    FocusScope.of(context).unfocus();

    if (!_formKey.currentState!.validate()) {
      _showErrorSnackBar("Please fill in all required fields.");
      return;
    }

    if (_householdMembers.isEmpty) {
      _showErrorSnackBar("Please add at least one household member.");
      return;
    }

    for (var member in _householdMembers) {
      if (member.name.trim().isEmpty || member.age < 0) { // Allow age 0 for babies
        _showErrorSnackBar("Please complete all member information, including valid ages.");
        return;
      }
    }
    
    if (_latitude == null || _longitude == null) {
      _showErrorSnackBar("Please capture your GPS location first!");
      return;
    }

    final confirmed = await _showConfirmationDialog();
    if (!confirmed) return;

    await _proceedWithSubmission();
  }

  Future<void> _proceedWithSubmission() async {
    setState(() => _isSubmitting = true);

    // Ensure the main list object has the latest from the controllers just in case
    _syncHeadOfFamily();

    final Map<String, dynamic> surveyData = {
      'headOfFamily': _headOfFamilyController.text.trim(),
      'province': 'Palawan',
      'municipality': 'Taytay',
      'barangay': 'Pularaquen',
      'purok': _selectedPurok,
      'sitio': _selectedSitio,
      'contactNumber': _contactController.text.trim(),
      'monthlyIncome': _incomeController.text.trim(),
      'householdMemberCount': _householdMembers.length,
      'members': _householdMembers.map((m) => m.toJson()).toList(),
      'latitude': _latitude,
      'longitude': _longitude,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'submittedBy': widget.uid, // Keep track of the surveyor
      'lastUpdated': DateTime.now().toIso8601String(),
    };

    try {
// NEW CODE: Insert ${widget.uid} into the path
final String surveyId = DateTime.now().millisecondsSinceEpoch.toString();
final url = 'https://mabskie-47c24-default-rtdb.firebaseio.com/household_surveys/${widget.uid}/$surveyId.json?auth=${widget.token}';
      final response = await http.put(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(surveyData),
      ).timeout(
        const Duration(seconds: 15),
        onTimeout: () => throw Exception('Connection timeout. Please check your internet connection.'),
      );

      if (response.statusCode == 200) {
        setState(() => _hasUnsavedChanges = false);
        if (!mounted) return;
        _showSuccessDialog();
      } else {
        throw Exception("Server error: ${response.statusCode}");
      }
    } catch (e) {
      if (!mounted) return;
      _showErrorSnackBar("Error: ${e.toString()}");
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  void _addHouseholdMember() {
    showDialog(
      context: context,
      builder: (context) => _AddMemberDialog(
        onAdd: (member) {
          setState(() {
            _householdMembers.add(member);
            _setUnsavedChanges();
          });
        },
        existingNames: _householdMembers.map((m) => m.name).toList(),
        sexOptions: sexOptions,
        relationshipOptions: relationshipOptions,
      ),
    );
  }

  void _editHouseholdMember(int index) {
    showDialog(
      context: context,
      builder: (context) => _EditMemberDialog(
        member: _householdMembers[index],
        onUpdate: (member) {
          setState(() {
            _householdMembers[index] = member;
            if (index == 0) {
              // Update the main form controllers if Head is edited via dialog
              _headOfFamilyController.text = member.name;
              _headOfFamilyAgeController.text = member.age.toString();
              _headOfFamilySex = member.sex;
            }
            _setUnsavedChanges();
          });
        },
        onDelete: index == 0 ? null : () {
          setState(() {
            _householdMembers.removeAt(index);
            _setUnsavedChanges();
          });
        },
        sexOptions: sexOptions,
        relationshipOptions: relationshipOptions,
        isHead: index == 0,
      ),
    );
  }

  Future<bool> _showConfirmationDialog() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Submit Survey?', style: GoogleFonts.lato(fontWeight: FontWeight.bold)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Please verify your information:', style: GoogleFonts.lato(fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              _buildInfoRow('Head of Family', _headOfFamilyController.text),
              _buildInfoRow('Location', '${_selectedPurok ?? ''}, ${_selectedSitio ?? ''}\nBrgy. Pularaquen, Taytay, Palawan'),
              _buildInfoRow('Total Members', '${_householdMembers.length} persons'),
              _buildInfoRow('Coordinates', 'Lat: ${_latitude?.toStringAsFixed(6)}, Lng: ${_longitude?.toStringAsFixed(6)}'),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.deepPurple.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Household Members:',
                      style: GoogleFonts.lato(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    ..._householdMembers.asMap().entries.map(
                      (entry) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          '${entry.key + 1}. ${entry.value.name} (${entry.value.age}yo, ${entry.value.sex})',
                          style: GoogleFonts.lato(fontSize: 12),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Edit'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple),
            child: const Text('Submit', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle, color: Colors.green, size: 80),
            const SizedBox(height: 16),
            Text(
              "Success!",
              style: GoogleFonts.lato(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.green),
            ),
            const SizedBox(height: 8),
            Text(
              "Household data for ${_householdMembers.length} members has been successfully mapped.",
              textAlign: TextAlign.center,
              style: GoogleFonts.lato(fontSize: 16),
            ),
          ],
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.pop(context, true);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text("Done", style: TextStyle(color: Colors.white, fontSize: 16)),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildLabel(String text, {bool isRequired = true}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0, left: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Flexible(
            child: Text(
              text,
              style: GoogleFonts.lato(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.deepPurple.shade900,
              ),
            ),
          ),
          if (isRequired)
            Padding(
              padding: const EdgeInsets.only(left: 4.0),
              child: Text(
                "*",
                style: TextStyle(
                  color: Colors.red.shade700,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_hasUnsavedChanges,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        
        final shouldPop = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Text('Discard Changes?', style: GoogleFonts.lato(fontWeight: FontWeight.bold)),
            content: const Text('You have unsaved changes. Are you sure you want to leave?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                child: const Text('Discard', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        );
        
        if (shouldPop == true && context.mounted) {
          Navigator.pop(context);
        }
      },
      child: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: Scaffold(
          appBar: AppBar(
            title: Text(
              "Household Survey",
              style: GoogleFonts.lato(fontWeight: FontWeight.bold, color: Colors.white),
            ),
            backgroundColor: Colors.deepPurple,
            iconTheme: const IconThemeData(color: Colors.white),
          ),
          body: _isSubmitting 
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 16),
                      Text(
                        'Submitting survey...',
                        style: GoogleFonts.lato(fontSize: 16, color: Colors.grey),
                      ),
                    ],
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Instructions
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.deepPurple.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.deepPurple.shade200),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.info_outline, color: Colors.deepPurple.shade900, size: 24),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  "Fill out this form AT YOUR HOUSE. Add all household members to ensure accurate mapping.",
                                  style: GoogleFonts.lato(color: Colors.deepPurple.shade900, fontSize: 14),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Head of Family Info Group
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.deepPurple.shade100, width: 2),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Head of Family Details",
                                style: GoogleFonts.lato(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.deepPurple),
                              ),
                              const SizedBox(height: 16),
                              
                              _buildLabel("Full Name"),
                              TextFormField(
                                controller: _headOfFamilyController,
                                validator: (value) {
                                  if (value == null || value.trim().isEmpty) return "Please enter a name";
                                  return null;
                                },
                                onChanged: (value) => _syncHeadOfFamily(),
                                decoration: InputDecoration(
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                  filled: true,
                                  fillColor: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 16),
                              
                              Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        _buildLabel("Age"),
                                        TextFormField(
                                          controller: _headOfFamilyAgeController,
                                          keyboardType: TextInputType.number,
                                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                          validator: (value) {
                                            if (value == null || value.isEmpty) return "Required";
                                            if (int.tryParse(value) == null || int.parse(value) <= 0) return "Invalid";
                                            return null;
                                          },
                                          onChanged: (value) => _syncHeadOfFamily(),
                                          decoration: InputDecoration(
                                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                            filled: true,
                                            fillColor: Colors.white,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        _buildLabel("Sex"),
                                        DropdownButtonFormField<String>(
                                          isExpanded: true,
                                          value: _headOfFamilySex,
                                          items: sexOptions.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                                          onChanged: (v) {
                                            setState(() => _headOfFamilySex = v!);
                                            _syncHeadOfFamily();
                                            _setUnsavedChanges();
                                          },
                                          decoration: InputDecoration(
                                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                            filled: true,
                                            fillColor: Colors.white,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Complete Address Header
                        _buildLabel("Household Address"),
                        
                        // Read-Only Fixed Location
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.location_city, color: Colors.grey.shade600, size: 20),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  "Brgy. Pularaquen, Taytay, Palawan",
                                  style: GoogleFonts.lato(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.grey.shade800,
                                  ),
                                ),
                              ),
                              Icon(Icons.lock, color: Colors.grey.shade400, size: 16),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Purok & Sitio
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildLabel("Purok"),
                                  DropdownButtonFormField<String>(
                                    isExpanded: true,
                                    value: _selectedPurok,
                                    items: puroks.map((p) => DropdownMenuItem(value: p, child: Text(p))).toList(),
                                    onChanged: (v) {
                                      setState(() => _selectedPurok = v);
                                      _setUnsavedChanges();
                                    },
                                    validator: (v) => v == null ? "Required" : null,
                                    decoration: InputDecoration(
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                      filled: true,
                                      fillColor: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildLabel("Sitio"),
                                  DropdownButtonFormField<String>(
                                    isExpanded: true,
                                    value: _selectedSitio,
                                    items: sitios.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                                    onChanged: (v) {
                                      setState(() => _selectedSitio = v);
                                      _setUnsavedChanges();
                                    },
                                    validator: (v) => v == null ? "Required" : null,
                                    decoration: InputDecoration(
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                      filled: true,
                                      fillColor: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),

                        // Contact Number
                        _buildLabel("Contact Number", isRequired: false),
                        TextFormField(
                          controller: _contactController,
                          keyboardType: TextInputType.phone,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(11),
                          ],
                          decoration: InputDecoration(
                            hintText: "09XXXXXXXXX (Optional)",
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            filled: true,
                            fillColor: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Income
                        _buildLabel("Estimated Monthly Income (₱)", isRequired: false),
                        TextFormField(
                          controller: _incomeController,
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          decoration: InputDecoration(
                            hintText: "Optional",
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            filled: true,
                            fillColor: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 32),

                        // HOUSEHOLD MEMBERS SECTION
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded( 
                              child: Text(
                                "Household Members (${_householdMembers.length})",
                                style: GoogleFonts.lato(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.deepPurple.shade900,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8), 
                            ElevatedButton.icon(
                              onPressed: _addHouseholdMember,
                              icon: const Icon(Icons.person_add, size: 20),
                              label: const Text("Add Member"),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // Members List
                        Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: _householdMembers.isEmpty
                              ? Padding(
                                  padding: const EdgeInsets.all(32),
                                  child: Center(
                                    child: Text(
                                      "No members added yet",
                                      style: GoogleFonts.lato(color: Colors.grey),
                                    ),
                                  ),
                                )
                              : ListView.separated(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  itemCount: _householdMembers.length,
                                  separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey.shade300),
                                  itemBuilder: (context, index) {
                                    final member = _householdMembers[index];
                                    return ListTile(
                                      leading: CircleAvatar(
                                        backgroundColor: index == 0 ? Colors.deepPurple : Colors.blue,
                                        child: Text(
                                          '${index + 1}',
                                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                      title: Text(
                                        member.name,
                                        style: GoogleFonts.lato(fontWeight: FontWeight.bold),
                                      ),
                                      subtitle: Text(
                                        '${member.age} years old • ${member.sex} • ${member.relationship}',
                                        style: GoogleFonts.lato(fontSize: 12),
                                      ),
                                      trailing: IconButton(
                                        icon: const Icon(Icons.edit, color: Colors.deepPurple),
                                        onPressed: () => _editHouseholdMember(index),
                                      ),
                                    );
                                  },
                                ),
                        ),
                        const SizedBox(height: 32),

                        // GPS LOCATION
                        _buildLabel("House GPS Location"),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: _latitude == null ? Colors.red.shade300 : Colors.green.shade400,
                              width: 2,
                            ),
                            borderRadius: BorderRadius.circular(12),
                            color: _latitude == null ? Colors.red.shade50 : Colors.green.shade50,
                          ),
                          child: Column(
                            children: [
                              Icon(
                                _latitude == null ? Icons.location_off : Icons.location_on,
                                size: 48,
                                color: _latitude == null ? Colors.red : Colors.green,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                _latitude == null ? "Location not captured yet" : "Location Captured Successfully",
                                textAlign: TextAlign.center,
                                style: GoogleFonts.lato(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: _latitude == null ? Colors.red.shade800 : Colors.green.shade800,
                                ),
                              ),
                              if (_latitude != null) ...[
                                const SizedBox(height: 8),
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Column(
                                    children: [
                                      Text(
                                        "Lat: ${_latitude!.toStringAsFixed(6)}\nLng: ${_longitude!.toStringAsFixed(6)}",
                                        textAlign: TextAlign.center,
                                        style: GoogleFonts.robotoMono(fontSize: 12, color: Colors.grey.shade800),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              const SizedBox(height: 16),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  onPressed: _isGettingLocation ? null : _getLocation,
                                  icon: _isGettingLocation
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                        )
                                      : Icon(_latitude == null ? Icons.my_location : Icons.refresh),
                                  label: Text(
                                    _isGettingLocation
                                        ? "Getting Location..."
                                        : _latitude == null
                                            ? "Capture My Location"
                                            : "Update Location",
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.deepPurple,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 40),

                        // Submit Button
                        SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: ElevatedButton.icon(
                            onPressed: _submitSurvey,
                            icon: const Icon(Icons.send, color: Colors.white),
                            label: Text(
                              "Submit Survey Data",
                              style: GoogleFonts.lato(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.deepPurple,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              elevation: 4,
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}

// Add Member Dialog
class _AddMemberDialog extends StatefulWidget {
  final Function(HouseholdMember) onAdd;
  final List<String> existingNames;
  final List<String> sexOptions;
  final List<String> relationshipOptions;

  const _AddMemberDialog({
    required this.onAdd,
    required this.existingNames,
    required this.sexOptions,
    required this.relationshipOptions,
  });

  @override
  State<_AddMemberDialog> createState() => _AddMemberDialogState();
}

class _AddMemberDialogState extends State<_AddMemberDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _ageController = TextEditingController();
  String _selectedSex = 'Male';
  String _selectedRelationship = 'Son';

  @override
  void dispose() {
    _nameController.dispose();
    _ageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text('Add Household Member', style: GoogleFonts.lato(fontWeight: FontWeight.bold)),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Full Name',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter a name';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _ageController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'Age',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter age';
                  }
                  final age = int.tryParse(value);
                  // Fixed validation to allow age 0
                  if (age == null || age < 0 || age > 120) {
                    return 'Please enter valid age';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _selectedSex,
                decoration: const InputDecoration(
                  labelText: 'Sex',
                  border: OutlineInputBorder(),
                ),
                items: widget.sexOptions.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                onChanged: (v) => setState(() => _selectedSex = v!),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _selectedRelationship,
                decoration: const InputDecoration(
                  labelText: 'Relationship to Head',
                  border: OutlineInputBorder(),
                ),
                items: widget.relationshipOptions.map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
                onChanged: (v) => setState(() => _selectedRelationship = v!),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              final member = HouseholdMember(
                name: _nameController.text.trim(),
                age: int.parse(_ageController.text),
                sex: _selectedSex,
                relationship: _selectedRelationship,
              );
              widget.onAdd(member);
              Navigator.pop(context);
            }
          },
          style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
          child: const Text('Add Member', style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
}

// Edit Member Dialog
class _EditMemberDialog extends StatefulWidget {
  final HouseholdMember member;
  final Function(HouseholdMember) onUpdate;
  final VoidCallback? onDelete;
  final List<String> sexOptions;
  final List<String> relationshipOptions;
  final bool isHead;

  const _EditMemberDialog({
    required this.member,
    required this.onUpdate,
    this.onDelete,
    required this.sexOptions,
    required this.relationshipOptions,
    this.isHead = false,
  });

  @override
  State<_EditMemberDialog> createState() => _EditMemberDialogState();
}

class _EditMemberDialogState extends State<_EditMemberDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _ageController;
  late String _selectedSex;
  late String _selectedRelationship;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.member.name);
    _ageController = TextEditingController(text: widget.member.age.toString());
    _selectedSex = widget.member.sex;
    _selectedRelationship = widget.member.relationship;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _ageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(
        widget.isHead ? 'Edit Head of Family' : 'Edit Member',
        style: GoogleFonts.lato(fontWeight: FontWeight.bold),
      ),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Full Name',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter a name';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _ageController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'Age',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter age';
                  }
                  final age = int.tryParse(value);
                  // Fixed validation to allow age 0
                  if (age == null || age < 0 || age > 120) {
                    return 'Please enter valid age';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _selectedSex,
                decoration: const InputDecoration(
                  labelText: 'Sex',
                  border: OutlineInputBorder(),
                ),
                items: widget.sexOptions.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                onChanged: (v) => setState(() => _selectedSex = v!),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _selectedRelationship,
                decoration: const InputDecoration(
                  labelText: 'Relationship to Head',
                  border: OutlineInputBorder(),
                ),
                items: widget.relationshipOptions.map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
                onChanged: widget.isHead ? null : (v) => setState(() => _selectedRelationship = v!),
              ),
            ],
          ),
        ),
      ),
      actions: [
        if (widget.onDelete != null)
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              widget.onDelete!();
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              final member = HouseholdMember(
                name: _nameController.text.trim(),
                age: int.parse(_ageController.text),
                sex: _selectedSex,
                relationship: _selectedRelationship,
              );
              widget.onUpdate(member);
              Navigator.pop(context);
            }
          },
          style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple),
          child: const Text('Update', style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
}