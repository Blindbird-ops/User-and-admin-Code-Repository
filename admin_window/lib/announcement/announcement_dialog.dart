import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart'; // Import intl for formatting

class AnnouncementDialog extends StatefulWidget {
  final Future<void> Function(
    String title, 
    String message, 
    String when, 
    String where, 
    String imageUrl
  ) onPost;

  const AnnouncementDialog({super.key, required this.onPost});

  @override
  _AnnouncementDialogState createState() => _AnnouncementDialogState();
}

class _AnnouncementDialogState extends State<AnnouncementDialog> {
  // Controllers
  final _titleController = TextEditingController();
  final _messageController = TextEditingController();
  final _whenController = TextEditingController();
  final _whereController = TextEditingController();
  
  // Image State
  XFile? _selectedImage;
  bool _isUploading = false;
  final ImagePicker _picker = ImagePicker();

  // Cloudinary Config
  final String cloudName = 'dnufyw3my';
  final String uploadPreset = 'cloudinary';

  @override
  void dispose() {
    _titleController.dispose();
    _messageController.dispose();
    _whenController.dispose();
    _whereController.dispose();
    super.dispose();
  }

  // --- NEW: DATE & TIME PICKER LOGIC ---
  Future<void> _pickDateTime() async {
    final now = DateTime.now();
    
    // 1. Pick Date
    final DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now, // Cannot pick past dates
      lastDate: DateTime(now.year + 2), // Allow up to 2 years in future
    );

    if (pickedDate == null) return; // User cancelled

    if (!mounted) return;

    // 2. Pick Time
    final TimeOfDay? pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );

    if (pickedTime == null) return; // User cancelled

    // 3. Combine and Format
    final DateTime finalDateTime = DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      pickedTime.hour,
      pickedTime.minute,
    );

    // Format: "January 18, 2026 2:30 PM"
    final String formatted = DateFormat('MMMM d, yyyy h:mm a').format(finalDateTime);

    setState(() {
      _whenController.text = formatted;
    });
  }
  // -------------------------------------

  Future<void> _pickImage() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      setState(() {
        _selectedImage = image;
      });
    }
  }

  Future<String?> _uploadImageToCloudinary() async {
    if (_selectedImage == null) return ""; 

    try {
      final url = Uri.parse('https://api.cloudinary.com/v1_1/$cloudName/image/upload');
      final request = http.MultipartRequest('POST', url)
        ..fields['upload_preset'] = uploadPreset
        ..files.add(await http.MultipartFile.fromPath('file', _selectedImage!.path));

      final response = await request.send();

      if (response.statusCode == 200) {
        final responseData = await response.stream.bytesToString();
        final jsonData = json.decode(responseData);
        return jsonData['secure_url'];
      } else {
        print('Cloudinary Error: ${response.statusCode}');
        return null; 
      }
    } catch (e) {
      print('Upload Error: $e');
      return null;
    }
  }

  Future<void> _handleSubmit() async {
    if (_titleController.text.trim().isEmpty || 
        _messageController.text.trim().isEmpty ||
        _whenController.text.trim().isEmpty ||
        _whereController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please fill in all text fields")),
      );
      return;
    }

    setState(() => _isUploading = true);

    String? imageUrl = "";
    if (_selectedImage != null) {
      imageUrl = await _uploadImageToCloudinary();
      if (imageUrl == null) {
        setState(() => _isUploading = false);
        if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Failed to upload image")));
        return;
      }
    }

    await widget.onPost(
      _titleController.text,
      _messageController.text,
      _whenController.text,
      _whereController.text,
      imageUrl,
    );

    if (mounted) {
      setState(() => _isUploading = false);
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.0)),
      child: Container(
        width: 600, 
        padding: const EdgeInsets.all(24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: const [
                  Icon(Icons.campaign, color: Colors.blueAccent, size: 28),
                  SizedBox(width: 12),
                  Text("Post Announcement", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 24),

              // 1. WHAT
              TextField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: "What (Title)",
                  prefixIcon: Icon(Icons.title),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),

              // 2. WHEN & WHERE ROW
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _whenController,
                      readOnly: true, // Prevents typing manually
                      onTap: _pickDateTime, // Opens the picker
                      decoration: const InputDecoration(
                        labelText: "When (Date/Time)",
                        prefixIcon: Icon(Icons.calendar_month), // Changed icon
                        border: OutlineInputBorder(),
                        hintText: "Select Date & Time"
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextField(
                      controller: _whereController,
                      decoration: const InputDecoration(
                        labelText: "Where (Location)",
                        prefixIcon: Icon(Icons.location_on),
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // 3. MESSAGE
              TextField(
                controller: _messageController,
                decoration: const InputDecoration(
                  labelText: "Message / Description",
                  prefixIcon: Icon(Icons.description),
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
                maxLines: 4,
              ),
              const SizedBox(height: 16),

              // 4. IMAGE PICKER
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade400),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  children: [
                    ElevatedButton.icon(
                      onPressed: _pickImage,
                      icon: const Icon(Icons.image),
                      label: const Text("Attach Image"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.grey.shade200,
                        foregroundColor: Colors.black,
                      ),
                    ),
                    const SizedBox(width: 16),
                    if (_selectedImage != null)
                      Expanded(
                        child: Row(
                          children: [
                            const Icon(Icons.check_circle, color: Colors.green, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _selectedImage!.name, 
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                            SizedBox(
                              height: 40,
                              width: 40,
                              child: Image.file(File(_selectedImage!.path), fit: BoxFit.cover),
                            )
                          ],
                        ),
                      )
                    else
                      const Text("No image selected (Optional)", style: TextStyle(color: Colors.grey)),
                  ],
                ),
              ),
              
              const SizedBox(height: 24),

              // ACTIONS
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _isUploading ? null : () => Navigator.of(context).pop(),
                    child: const Text("Cancel", style: TextStyle(fontSize: 16)),
                  ),
                  const SizedBox(width: 16),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      backgroundColor: Colors.blueAccent,
                    ),
                    onPressed: _isUploading ? null : _handleSubmit,
                    child: _isUploading 
                      ? const SizedBox(
                          width: 20, 
                          height: 20, 
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
                        )
                      : const Text("Post Announcement", style: TextStyle(fontSize: 16, color: Colors.white)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}