import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class AnnouncementManagementPage extends StatefulWidget {
  final String token;

  const AnnouncementManagementPage({super.key, required this.token});

  @override
  _AnnouncementManagementPageState createState() => _AnnouncementManagementPageState();
}

class _AnnouncementManagementPageState extends State<AnnouncementManagementPage> {
  List<Map<String, dynamic>> _announcements = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadAnnouncements();
  }

  Future<void> _loadAnnouncements() async {
    final url = "https://mabskie-47c24-default-rtdb.firebaseio.com/announcements.json?auth=${widget.token}";
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>?;
        List<Map<String, dynamic>> loaded = [];
        if (data != null) {
          data.forEach((id, value) {
            Map<String, dynamic> ann = Map<String, dynamic>.from(value);
            ann['id'] = id;
            loaded.add(ann);
          });
          // Sort announcements by timestamp descending
          loaded.sort((a, b) {
            DateTime t1 = DateTime.tryParse(a['timestamp'] ?? "") ?? DateTime(1970);
            DateTime t2 = DateTime.tryParse(b['timestamp'] ?? "") ?? DateTime(1970);
            return t2.compareTo(t1);
          });
        }
        setState(() {
          _announcements = loaded;
          _loading = false;
        });
      }
    } catch (e) {
      print("Error loading announcements: $e");
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _deleteAnnouncement(String id) async {
    final url = "https://mabskie-47c24-default-rtdb.firebaseio.com/announcements/$id.json?auth=${widget.token}";
    try {
      final response = await http.delete(Uri.parse(url));
      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Announcement deleted")));
        _loadAnnouncements();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Failed to delete announcement")));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error deleting announcement: $e")));
    }
  }

// ... inside _AnnouncementManagementPageState ...

  Widget _buildAnnouncementItem(Map<String, dynamic> ann) {
    String imageUrl = ann['imageUrl'] ?? "";
    bool hasImage = imageUrl.isNotEmpty;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          // 1. IMAGE SECTION (If exists)
          if (hasImage)
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              child: SizedBox(
                height: 200,
                width: double.infinity,
                child: Image.network(
                  imageUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (ctx, err, stack) => Container(
                    color: Colors.grey.shade200,
                    child: const Icon(Icons.broken_image, size: 50, color: Colors.grey),
                  ),
                ),
              ),
            ),

          // 2. CONTENT SECTION
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        ann['title'] ?? "No Title", 
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.black87),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete, color: Colors.redAccent),
                      onPressed: () => _deleteAnnouncement(ann['id']),
                    ),
                  ],
                ),
                
                // When and Where Info Row
                Container(
                  margin: const EdgeInsets.only(top: 8, bottom: 8),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_today, size: 16, color: Colors.blue),
                      const SizedBox(width: 4),
                      Text(ann['when'] ?? "N/A", style: const TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(width: 16),
                      const Icon(Icons.location_on, size: 16, color: Colors.red),
                      const SizedBox(width: 4),
                      Text(ann['where'] ?? "N/A", style: const TextStyle(fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),

                const Divider(),

                Text(
                  ann['message'] ?? "", 
                  style: const TextStyle(color: Colors.black87, fontSize: 15, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Manage Announcements"),
        backgroundColor: Colors.blueGrey,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.blueGrey.shade50, Colors.blueGrey.shade100],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: _loading
            ? Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _loadAnnouncements,
                child: Container(
                  alignment: Alignment.center,
                  padding: EdgeInsets.all(16),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: 800),
                    child: Column(
                      children: [
                        Expanded(
                          child: _announcements.isEmpty
                              ? Center(child: Text("No announcements found", 
                                  style: TextStyle(fontSize: 18, color: Colors.black87)))
                              : ListView.builder(
                                  itemCount: _announcements.length,
                                  itemBuilder: (context, index) {
                                    return _buildAnnouncementItem(_announcements[index]);
                                  },
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