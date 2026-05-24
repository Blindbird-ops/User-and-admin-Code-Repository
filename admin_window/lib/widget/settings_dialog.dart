import 'dart:convert';
import 'dart:typed_data';
import 'package:admin_window/screens/archived_requests_page.dart';
import 'package:flutter/material.dart';
import 'package:file_saver/file_saver.dart';
import 'package:intl/intl.dart';
import 'package:admin_window/services/data_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:encrypt/encrypt.dart' as encrypt; // For encryption

class SettingsDialog extends StatefulWidget {
  final DataService dataService;
  final ThemeMode currentThemeMode;
  final VisualDensity currentVisualDensity;
  final ValueChanged<ThemeMode> onThemeChanged;
  final ValueChanged<VisualDensity> onDensityChanged;

  const SettingsDialog({
    super.key,
    required this.dataService,
    required this.currentThemeMode,
    required this.currentVisualDensity,
    required this.onThemeChanged,
    required this.onDensityChanged,
  });

  @override
  _SettingsDialogState createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  bool _isBackingUp = false;
  bool _isClearingCache = false;

  late ThemeMode _selectedThemeMode;
  late VisualDensity _selectedVisualDensity;

  @override
  void initState() {
    super.initState();
    _selectedThemeMode = widget.currentThemeMode;
    _selectedVisualDensity = widget.currentVisualDensity;
  }

  /// Prompts the user to enter a password for encrypting the backup.
  /// Returns the password string if confirmed, or null if cancelled.
  Future<String?> _promptForPassword(BuildContext context) async {
    final passwordController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Set Backup Password'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('This password will be required to decrypt the backup file. Please store it in a safe place.'),
              const SizedBox(height: 16),
              TextFormField(
                controller: passwordController,
                autofocus: true,
                obscureText: true, // Hides the password
                decoration: const InputDecoration(
                  labelText: 'Enter Password',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.lock),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Password cannot be empty.';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.of(ctx).pop(passwordController.text);
              }
            },
            child: const Text('Encrypt & Save'),
          ),
        ],
      ),
    );
  }

  /// Fetches all data, prompts for a password, encrypts the data, and saves it to a file.
  Future<void> _backupData() async {
    // 1. Prompt for password first.
    final password = await _promptForPassword(context);
    if (password == null || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Backup cancelled."), backgroundColor: Colors.grey),
      );
      return; // User cancelled the password dialog.
    }

    setState(() => _isBackingUp = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Fetching and encrypting data... This may take a moment.")),
    );

    try {
      // 2. Fetch all data from the database.
      final results = await Future.wait([
        widget.dataService.getValue('users'),
        widget.dataService.getValue('requests'),
        widget.dataService.getValue('complaints'),
        widget.dataService.getValue('logs'),
        widget.dataService.getValue('transactions'),
        widget.dataService.getValue('verificationSubmissions'),
      ]);

      final backupData = {
        'backupDate': DateTime.now().toIso8601String(),
        'data': {
          'users': results[0], 'requests': results[1], 'complaints': results[2],
          'logs': results[3], 'transactions': results[4], 'verificationSubmissions': results[5],
        }
      };

      const jsonEncoder = JsonEncoder.withIndent('  ');
      final jsonString = jsonEncoder.convert(backupData);

      // 3. Encrypt the JSON data.
      final key = encrypt.Key.fromUtf8(password.padRight(32)); // Use a 32-byte key for AES-256
      final iv = encrypt.IV.fromSecureRandom(16); // Initialization Vector for security
      final encrypter = encrypt.Encrypter(encrypt.AES(key, mode: encrypt.AESMode.cbc));
      final encryptedData = encrypter.encrypt(jsonString, iv: iv);

      // 4. Combine the IV and the encrypted data for storage.
      // The IV is necessary for decryption and is stored at the beginning of the file.
      final bytes = iv.bytes + encryptedData.bytes;

      // 5. Save the encrypted binary file.
      final timestamp = DateFormat('yyyy-MM-dd_HH-mm-ss').format(DateTime.now());
      final fileNameWithExt = 'barangay_backup_$timestamp.json.enc';

      await FileSaver.instance.saveFile(
        name: fileNameWithExt,
        bytes: Uint8List.fromList(bytes),
        mimeType: MimeType.other, // Use a generic binary type
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Encrypted backup saved as $fileNameWithExt"), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Backup failed: $e"), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isBackingUp = false);
    }
  }

  /// Prompts the user and clears all locally cached data from SharedPreferences.
  Future<void> _clearCache() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Clear Cache'),
        content: const Text('Are you sure you want to delete all locally cached data? This may help resolve display issues but will require an internet connection to reload.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Clear Cache', style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isClearingCache = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Local cache cleared successfully! The app will now reload data from the server."), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to clear cache: $e"), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isClearingCache = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: const [
          Icon(Icons.settings),
          SizedBox(width: 8),
          Text('Settings'),
        ],
      ),
      content: SingleChildScrollView(
        child: SizedBox(
          width: 400, // Give the dialog a consistent width
          child: ListBody(
            children: <Widget>[
              _buildSectionHeader("Appearance"),
              SwitchListTile(
                title: const Text('Dark Mode'),
                value: _selectedThemeMode == ThemeMode.dark,
                secondary: const Icon(Icons.brightness_6),
                onChanged: (isDark) {
                  final newMode = isDark ? ThemeMode.dark : ThemeMode.light;
                  setState(() => _selectedThemeMode = newMode);
                  widget.onThemeChanged(newMode);
                },
              ),
              ListTile(
                leading: const Icon(Icons.view_quilt),
                title: const Text('UI Density'),
                trailing: DropdownButton<VisualDensity>(
                  value: _selectedVisualDensity,
                  items: const [
                    DropdownMenuItem(value: VisualDensity.compact, child: Text('Compact')),
                    DropdownMenuItem(value: VisualDensity.standard, child: Text('Standard')),
                    DropdownMenuItem(value: VisualDensity.comfortable, child: Text('Comfortable')),
                  ],
                  onChanged: (density) {
                    if (density == null) return;
                    setState(() => _selectedVisualDensity = density);
                    widget.onDensityChanged(density);
                  },
                ),
              ),
              const Divider(height: 32),
              _buildSectionHeader("Data Management"),
              ListTile(
                leading: _isBackingUp ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 3)) : const Icon(Icons.cloud_download),
                title: const Text('Backup All Data (Encrypted)'),
                subtitle: const Text('Save a password-protected file of all data.'),
                onTap: _isBackingUp ? null : _backupData,
              ),
              ListTile(
                leading: _isClearingCache ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 3)) : const Icon(Icons.delete_sweep, color: Colors.red),
                title: const Text('Clear Local Cache', style: TextStyle(color: Colors.red)),
                subtitle: const Text('Force reload all data from the server.'),
                onTap: _isClearingCache ? null : _clearCache,
              ),
              ListTile(
                leading: const Icon(Icons.archive, color: Colors.blueGrey),
                title: const Text('View Archived Requests'),
                subtitle: const Text('Restore or permanently delete items.'),
                onTap: () {
                  Navigator.pop(context); // Close dialog
                  Navigator.push(
                    context, 
                    MaterialPageRoute(builder: (_) => ArchivedRequestsPage(dataService: widget.dataService))
                  );
                },
              ),
              const Divider(height: 32),
              _buildSectionHeader("Help"),
              ListTile(
                leading: const Icon(Icons.help_outline, color: Colors.indigo),
                title: const Text('Reset Tutorial'),
                subtitle: const Text('Enable the welcome guide for the next login.'),
                onTap: () async {
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setBool('has_seen_tutorial', false);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("Tutorial reset! It will appear when you restart the app or screen."), backgroundColor: Colors.green),
                    );
                  }
                },
              ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          child: const Text('Close'),
          onPressed: () {
            Navigator.of(context).pop();
          },
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0, top: 16.0),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          color: Theme.of(context).primaryColor,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.1,
        ),
      ),
    );
  }
}