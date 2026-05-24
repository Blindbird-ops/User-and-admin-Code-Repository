// lib/screens/template_manager_page.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;

class TemplateManagerPage extends StatefulWidget {
  const TemplateManagerPage({super.key});

  @override
  State<TemplateManagerPage> createState() => _TemplateManagerPageState();
}

class _TemplateManagerPageState extends State<TemplateManagerPage> {
  // CONFIGURATION
  // Replace with your actual Python Backend URL
  final String baseUrl = "http://127.0.0.1:5000"; 

  // STATE VARIABLES
  bool _isLoading = true;
  
  // This will store the data fetched from the backend
  // Structure: { "Barangay Clearance": [ {id, name, filename, isActive}, ... ] }
  Map<String, List<Map<String, dynamic>>> _categorizedTemplates = {};

  // HARDCODED CATEGORIES (To ensure dropdown has options even if backend is empty)
  final List<String> _docTypes = [
    "Barangay Clearance",
    "Certificate of Indigency",
    "Business Clearance",
    "Certificate of Cohabitation",
    "Certificate of Late Registration",
    "Seaweeds Certification",
    "Barangay Certification",
    "Complaint",
  ];

  @override
  void initState() {
    super.initState();
    _fetchTemplates();
  }

  // --- API: FETCH TEMPLATES ---
  Future<void> _fetchTemplates() async {
    setState(() => _isLoading = true);
    try {
      // Endpoint expectation: GET /api/templates
      // Should return JSON: { "Barangay Clearance": [...], "Indigency": [...] }
      final response = await http.get(Uri.parse('$baseUrl/api/templates'));

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        
        // Convert dynamic map to specific type
        Map<String, List<Map<String, dynamic>>> parsedData = {};
        
        data.forEach((key, value) {
          if (value is List) {
            parsedData[key] = List<Map<String, dynamic>>.from(value);
          }
        });

        setState(() {
          _categorizedTemplates = parsedData;
          _isLoading = false;
        });
      } else {
        throw Exception("Failed to load templates");
      }
    } catch (e) {
      print("Error fetching templates: $e");
      setState(() => _isLoading = false);
      // In a real app, you might show a "Retry" button here
    }
  }

  // --- API: SET ACTIVE TEMPLATE ---
  Future<void> _setActiveTemplate(String category, String templateId, String templateName) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/set_active_template'),
        headers: {"Content-Type": "application/json"},
        body: json.encode({
          "category": category,
          "template_id": templateId,
        }),
      );

      if (response.statusCode == 200) {
        _fetchTemplates(); // Refresh UI
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("'$templateName' is now active!"), backgroundColor: Colors.green),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error setting active: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  // --- API: DELETE TEMPLATE ---
  Future<void> _deleteTemplate(String templateId) async {
    try {
      final response = await http.delete(Uri.parse('$baseUrl/api/delete_template/$templateId'));
      if (response.statusCode == 200) {
        _fetchTemplates(); // Refresh UI
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Template deleted"), backgroundColor: Colors.grey),
          );
        }
      }
    } catch (e) {
      print(e);
    }
  }

  // --- UPLOAD DIALOG ---
  // --- UPLOAD DIALOG (Fixed: Scrollable to prevent overflow) ---
  void _showUploadDialog() {
    // Default to the first item, or a fallback if list is empty
    String selectedDocType = _docTypes.isNotEmpty ? _docTypes.first : "Barangay Clearance";
    TextEditingController nameController = TextEditingController();
    PlatformFile? selectedFile;
    bool isUploading = false;

    showDialog(
      context: context,
      barrierDismissible: false, // Force user to use buttons
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              titlePadding: const EdgeInsets.all(24),
              title: const Row(
                children: [
                  Icon(Icons.cloud_upload_outlined, color: Colors.deepPurple, size: 32),
                  SizedBox(width: 12),
                  Text("Upload Document Template", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 24)),
                ],
              ),
              
              // --- FIX: WRAP CONTENT IN SCROLL VIEW ---
              content: SingleChildScrollView(
                child: SizedBox(
                  width: 600, // Wide for Desktop
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 1. SELECT TYPE
                      const Text("1. Select Document Type", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        initialValue: selectedDocType,
                        decoration: InputDecoration(
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          filled: true,
                          fillColor: Colors.grey.shade50,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                        ),
                        isExpanded: true, // Prevents overflow text in dropdown
                        items: _docTypes.map((String type) {
                          return DropdownMenuItem(value: type, child: Text(type));
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setStateDialog(() => selectedDocType = val);
                          }
                        },
                      ),
                      const SizedBox(height: 24),
                      
                      // 2. ENTER NAME
                      const Text("2. Template Display Name", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      const SizedBox(height: 8),
                      TextField(
                        controller: nameController,
                        decoration: InputDecoration(
                          hintText: "e.g., Special Format 2024",
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          filled: true,
                          fillColor: Colors.grey.shade50,
                        ),
                      ),
                      const SizedBox(height: 24),

                      // 3. PICK FILE
                      const Text("3. Select Word File (.docx)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      const SizedBox(height: 8),
                      
                      InkWell(
                        onTap: () async {
                          try {
                            FilePickerResult? result = await FilePicker.platform.pickFiles(
                              type: FileType.custom,
                              allowedExtensions: ['docx'],
                              withData: true, // Important for Web/Desktop sometimes
                            );

                            if (result != null) {
                              setStateDialog(() {
                                selectedFile = result.files.first;
                              });
                            }
                          } catch (e) {
                            print("File picker error: $e");
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text("Error picking file: $e"), backgroundColor: Colors.red),
                            );
                          }
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 40),
                          decoration: BoxDecoration(
                            color: selectedFile != null ? Colors.green.shade50 : Colors.deepPurple.shade50,
                            border: Border.all(
                              color: selectedFile != null ? Colors.green : Colors.deepPurple.shade300, 
                              width: 2
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            children: [
                              Icon(
                                selectedFile != null ? Icons.check_circle : Icons.description_outlined, 
                                size: 48, 
                                color: selectedFile != null ? Colors.green : Colors.deepPurple.shade300
                              ),
                              const SizedBox(height: 12),
                              Text(
                                selectedFile != null ? selectedFile!.name : "Click here to browse for a .docx file",
                                style: TextStyle(
                                  fontSize: 16, 
                                  color: selectedFile != null ? Colors.green.shade800 : Colors.deepPurple, 
                                  fontWeight: FontWeight.w600
                                ),
                              ),
                              if (selectedFile == null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4.0),
                                  child: Text(
                                    "Only Microsoft Word documents are supported.",
                                    style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                                  ),
                                )
                            ],
                          ),
                        ),
                      ),
                      
                      // PROGRESS INDICATOR
                      if (isUploading)
                        const Padding(
                          padding: EdgeInsets.only(top: 24.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text("Uploading...", style: TextStyle(fontWeight: FontWeight.bold)),
                              SizedBox(height: 8),
                              LinearProgressIndicator(minHeight: 6),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              
              actionsPadding: const EdgeInsets.all(24),
              actions: [
                TextButton(
                  onPressed: isUploading ? null : () => Navigator.pop(context),
                  style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16)),
                  child: const Text("Cancel", style: TextStyle(fontSize: 16)),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurple,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: (isUploading || selectedFile == null || nameController.text.trim().isEmpty) 
                    ? null 
                    : () async {
                        setStateDialog(() => isUploading = true);
                        
                        // --- ACTUAL UPLOAD LOGIC ---
                        try {
                          var request = http.MultipartRequest('POST', Uri.parse('$baseUrl/api/upload_template'));
                          
                          // Add Fields
                          request.fields['category'] = selectedDocType;
                          request.fields['name'] = nameController.text.trim();
                          
                          // Add File
                          if (selectedFile!.path != null) {
                             // Desktop / Mobile
                             request.files.add(await http.MultipartFile.fromPath('file', selectedFile!.path!));
                          } else if (selectedFile!.bytes != null) {
                             // Web fallback (just in case)
                             request.files.add(http.MultipartFile.fromBytes(
                               'file', 
                               selectedFile!.bytes!, 
                               filename: selectedFile!.name
                             ));
                          }

                          var res = await request.send();
                          
                          if (res.statusCode == 200) {
                            if (mounted) {
                              Navigator.pop(context); // Close Dialog
                              _fetchTemplates(); // Refresh List
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text("Template Uploaded Successfully!"), backgroundColor: Colors.green)
                              );
                            }
                          } else {
                            throw Exception("Server rejected upload (Status: ${res.statusCode})");
                          }
                        } catch (e) {
                          print("Upload error: $e");
                          setStateDialog(() => isUploading = false);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text("Upload Failed: $e"), backgroundColor: Colors.red)
                            );
                          }
                        }
                    },
                  icon: const Icon(Icons.upload),
                  label: const Text("Upload Template", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ],
            );
          }
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // --- HEADER ---
        Padding(
          padding: const EdgeInsets.only(bottom: 16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "Document Templates",
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.deepPurple),
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.upload_file),
                label: const Text("Upload New Template"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                ),
                onPressed: _showUploadDialog,
              ),
            ],
          ),
        ),
        
        // --- INFO BANNER ---
        Container(
          margin: const EdgeInsets.only(bottom: 24),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.blue.shade200),
          ),
          child: const Row(
            children: [
              Icon(Icons.info_outline, color: Colors.blue),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  "Organize multiple templates for each document type. The template marked as 'Active' is the one the system will use when generating a user's request.",
                  style: TextStyle(color: Colors.black87),
                ),
              ),
            ],
          ),
        ),

        // --- MAIN CONTENT ---
        Expanded(
          child: _isLoading 
            ? const Center(child: CircularProgressIndicator())
            : _categorizedTemplates.isEmpty 
              ? const Center(child: Text("No templates uploaded yet."))
              : ListView.builder(
                  itemCount: _categorizedTemplates.keys.length,
                  itemBuilder: (context, index) {
                    String categoryName = _categorizedTemplates.keys.elementAt(index);
                    List<Map<String, dynamic>> templates = _categorizedTemplates[categoryName]!;

                    if (templates.isEmpty) return const SizedBox.shrink();

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 32.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // CATEGORY HEADER
                          Row(
                            children: [
                              const Icon(Icons.folder_copy_outlined, color: Colors.deepPurple, size: 24),
                              const SizedBox(width: 8),
                              Text(
                                categoryName,
                                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
                              ),
                            ],
                          ),
                          const Divider(),
                          const SizedBox(height: 12),

                          // LIST OF CARDS
                          Wrap(
                            spacing: 16,
                            runSpacing: 16,
                            children: templates.map((template) {
                              // Safely handle dynamic types
                              bool isActive = template['isActive'] == true || template['isActive'] == 1;
                              String tId = template['id'].toString();
                              String tName = template['name'] ?? "Unknown";
                              String tFile = template['filename'] ?? "file.docx";

                              return Container(
                                width: 320,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: isActive ? Colors.green : Colors.grey.shade300,
                                    width: isActive ? 2 : 1,
                                  ),
                                  boxShadow: [
                                    BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 4))
                                  ],
                                ),
                                child: Stack(
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.all(16.0),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          // Header of Card (Icon + Menu)
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              Container(
                                                padding: const EdgeInsets.all(10),
                                                decoration: BoxDecoration(
                                                  color: Colors.blue.shade50,
                                                  borderRadius: BorderRadius.circular(8),
                                                ),
                                                child: const Icon(Icons.description, color: Colors.blue, size: 28),
                                              ),
                                              PopupMenuButton<String>(
                                                onSelected: (value) {
                                                  if (value == 'active') {
                                                    _setActiveTemplate(categoryName, tId, tName);
                                                  } else if (value == 'delete') {
                                                    _deleteTemplate(tId);
                                                  }
                                                },
                                                itemBuilder: (context) => [
                                                  if (!isActive)
                                                    const PopupMenuItem(value: 'active', child: Text("Set as Active")),
                                                  const PopupMenuItem(value: 'delete', child: Text("Delete Template", style: TextStyle(color: Colors.red))),
                                                ],
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 16),
                                          
                                          // Template Details
                                          Text(
                                            tName,
                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                            maxLines: 1, overflow: TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            tFile,
                                            style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                                          ),
                                        ],
                                      ),
                                    ),
                                    
                                    // ACTIVE BADGE
                                    if (isActive)
                                      Positioned(
                                        top: 12,
                                        left: 60,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: Colors.green,
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: const Row(
                                            children: [
                                              Icon(Icons.check_circle, color: Colors.white, size: 12),
                                              SizedBox(width: 4),
                                              Text("ACTIVE", style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                                            ],
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}