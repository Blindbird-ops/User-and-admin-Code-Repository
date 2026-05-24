// lib/screens/admin_profile_page.dart 

import 'package:flutter/material.dart';
import 'package:admin_window/services/data_service.dart';

class AdminProfilePage extends StatefulWidget {
  final String token;
  final String userId;

  const AdminProfilePage({
    super.key,
    required this.token,
    required this.userId,
  });

  @override
  State<AdminProfilePage> createState() => _AdminProfilePageState();
}

class _AdminProfilePageState extends State<AdminProfilePage> {
  late final DataService _dataService;
  final _formKey = GlobalKey<FormState>();

  // Controllers for the form fields
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _middleNameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _addressController = TextEditingController();
  final _emailController = TextEditingController(); 

  bool _isLoading = true;
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    
    // --- FIX IS HERE: Use empty constructor ---
    // OLD: _dataService = DataService(widget.token);
    _dataService = DataService(); 
    // ------------------------------------------

    _fetchAdminProfile();
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _middleNameController.dispose();
    _usernameController.dispose();
    _addressController.dispose();
    _emailController.dispose();
    _dataService.close();
    super.dispose();
  }

  Future<void> _fetchAdminProfile() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      // Fetch the specific user data for the currently logged-in admin
      final adminData = await _dataService.getData('users/${widget.userId}');
      if (mounted && adminData != null) {
        // Populate the text fields with the fetched data
        _firstNameController.text = adminData['firstName'] ?? '';
        _lastNameController.text = adminData['lastName'] ?? '';
        _middleNameController.text = adminData['middleName'] ?? '';
        _usernameController.text = adminData['username'] ?? '';
        _addressController.text = adminData['address'] ?? '';
        _emailController.text = adminData['email'] ?? 'No Email Found';
      }
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = 'Failed to load profile: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isSaving = true);

    try {
      final Map<String, dynamic> updatedData = {
        'firstName': _firstNameController.text.trim(),
        'lastName': _lastNameController.text.trim(),
        'middleName': _middleNameController.text.trim(),
        'username': _usernameController.text.trim(),
        'address': _addressController.text.trim(),
      };

      await _dataService.updateData('users/${widget.userId}', updatedData);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile updated successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save profile: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Profile'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(child: Text(_errorMessage!, style: const TextStyle(color: Colors.red)))
              : Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 600),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24.0),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Edit Your Information',
                              style: Theme.of(context).textTheme.headlineSmall,
                            ),
                            const SizedBox(height: 24),
                            // Email is not editable
                            TextFormField(
                              controller: _emailController,
                              readOnly: true,
                              decoration: const InputDecoration(
                                labelText: 'Email (Cannot be changed)',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.email_outlined),
                              ),
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _firstNameController,
                              decoration: const InputDecoration(
                                labelText: 'First Name',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.person_outline),
                              ),
                              validator: (value) => value!.isEmpty ? 'First name is required' : null,
                            ),
                            const SizedBox(height: 16),
                             TextFormField(
                              controller: _middleNameController,
                              decoration: const InputDecoration(
                                labelText: 'Middle Name (Optional)',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.person_outline),
                              ),
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _lastNameController,
                              decoration: const InputDecoration(
                                labelText: 'Last Name',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.person_outline),
                              ),
                               validator: (value) => value!.isEmpty ? 'Last name is required' : null,
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _usernameController,
                              decoration: const InputDecoration(
                                labelText: 'Username',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.account_circle_outlined),
                              ),
                               validator: (value) => value!.isEmpty ? 'Username is required' : null,
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _addressController,
                              decoration: const InputDecoration(
                                labelText: 'Address',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.location_on_outlined),
                              ),
                               validator: (value) => value!.isEmpty ? 'Address is required' : null,
                            ),
                            const SizedBox(height: 24),
                            ElevatedButton.icon(
                              icon: _isSaving
                                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                  : const Icon(Icons.save),
                              label: Text(_isSaving ? 'Saving...' : 'Save Changes'),
                              onPressed: _isSaving ? null : _saveProfile,
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 16),
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
}