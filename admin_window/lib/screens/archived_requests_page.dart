import 'package:flutter/material.dart';
import 'package:admin_window/services/data_service.dart';
import 'package:intl/intl.dart';

class ArchivedRequestsPage extends StatefulWidget {
  final DataService dataService;
  
  const ArchivedRequestsPage({super.key, required this.dataService});

  @override
  _ArchivedRequestsPageState createState() => _ArchivedRequestsPageState();
}

class _ArchivedRequestsPageState extends State<ArchivedRequestsPage> {
  // We use the service passed from the parent widget
  List<Map<String, dynamic>> _allArchivedItems = [];
  List<Map<String, dynamic>> _filteredItems = [];
  bool _isLoading = true;
  final TextEditingController _searchController = TextEditingController();

  // Desktop Color Palette
  final Color _bgColor = const Color(0xFFF1F5F9); // Slate-100
  final Color _cardColor = Colors.white;
  final Color _primaryColor = const Color(0xFF0F172A); // Slate-900
  final Color _accentGreen = const Color(0xFF10B981); // Emerald-500

  @override
  void initState() {
    super.initState();
    _fetchArchives();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _filterData(String query) {
    if (query.isEmpty) {
      setState(() => _filteredItems = _allArchivedItems);
    } else {
      setState(() {
        _filteredItems = _allArchivedItems.where((item) {
          // --- UPDATED FILTER LOGIC ---
          // Requests have 'documentType', Complaints have 'subject'
          final typeOrSubject = (item['documentType'] ?? item['subject'] ?? 'Unknown').toString().toLowerCase();
          final email = (item['userEmail'] ?? item['complainantEmail'] ?? '').toString().toLowerCase();
          final name = (item['fullName'] ?? item['complainantName'] ?? '').toString().toLowerCase();
          
          return typeOrSubject.contains(query.toLowerCase()) || 
                 email.contains(query.toLowerCase()) ||
                 name.contains(query.toLowerCase());
        }).toList();
      });
    }
  }

  Future<void> _fetchArchives() async {
    setState(() => _isLoading = true);
    try {
      // 1. Fetch Requests
      final requestData = await widget.dataService.getData("archived_requests");
      // 2. Fetch Complaints
      final complaintData = await widget.dataService.getData("archived_complaints");
      
      final List<Map<String, dynamic>> loaded = [];

      // Process Requests
      if (requestData != null) {
        requestData.forEach((key, value) {
          final item = Map<String, dynamic>.from(value);
          item['key'] = key;
          item['type'] = 'request'; // Tag it
          loaded.add(item);
        });
      }

      // Process Complaints
      if (complaintData != null) {
        complaintData.forEach((key, value) {
          final item = Map<String, dynamic>.from(value);
          item['key'] = key;
          item['type'] = 'complaint'; // Tag it
          loaded.add(item);
        });
      }

      // Sort by archivedAt (descending)
      loaded.sort((a, b) => (b['archivedAt'] ?? '').compareTo(a['archivedAt'] ?? ''));
      
      if (mounted) {
        setState(() {
          _allArchivedItems = loaded;
          _filteredItems = loaded;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _restoreItem(Map<String, dynamic> item) async {
    final id = item['key'];
    final type = item['type'];

    final restoredItem = Map<String, dynamic>.from(item);
    restoredItem.remove('archivedAt');
    restoredItem.remove('archivedBy');
    restoredItem.remove('key');
    restoredItem.remove('type');

    try {
      final Map<String, dynamic> updates = {};

      if (type == 'request') {
        final userId = item['userId'];
        updates['all_requests/$id'] = restoredItem;
        if (userId != null) {
           updates['users/$userId/requests/$id'] = restoredItem;
        }
        updates['archived_requests/$id'] = null;
      } else if (type == 'complaint') {
        updates['complaints/$id'] = restoredItem;
        // If the complaint was linked to a user, restore that link
        final userId = item['userId'];
        if (userId != null && userId.toString().isNotEmpty) {
           // We need to construct the minimal user request object or restore full data
           // For simplicity, we assume the restoredItem has all fields needed for user view
           updates['users/$userId/requests/$id'] = restoredItem;
        }
        updates['archived_complaints/$id'] = null;
      }

      await widget.dataService.updateMulti(updates);
      
      _fetchArchives();
      if (mounted) _showSnack("${type == 'request' ? 'Request' : 'Complaint'} restored successfully", false);
    } catch (e) {
      _showSnack("Error: $e", true);
    }
  }


  void _showSnack(String msg, bool isError) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? Colors.red[700] : Colors.green[700],
      behavior: SnackBarBehavior.floating,
      width: 400,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    
    // Responsive Grid Logic
    int crossAxisCount = 1;
    if (screenWidth > 1300) {
      crossAxisCount = 4;
    } else if (screenWidth > 1000) crossAxisCount = 3;
    else if (screenWidth > 700) crossAxisCount = 2;

    return Scaffold(
      backgroundColor: _bgColor,
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(context),
            const SizedBox(height: 24),
            Expanded(
              child: _isLoading 
                ? const Center(child: CircularProgressIndicator())
                : _filteredItems.isEmpty 
                  ? _buildEmptyState()
                  : GridView.builder(
                      itemCount: _filteredItems.length,
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossAxisCount,
                        childAspectRatio: 1.4,
                        crossAxisSpacing: 16,
                        mainAxisSpacing: 16,
                      ),
                      itemBuilder: (ctx, index) => _buildDesktopCard(_filteredItems[index]),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
      children: [
        Container(
          margin: const EdgeInsets.only(right: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey[300]!),
          ),
          child: IconButton(
            icon: const Icon(Icons.arrow_back),
            color: _primaryColor,
            tooltip: "Go Back",
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Archive",
              style: TextStyle(
                fontSize: 28, 
                fontWeight: FontWeight.bold, 
                color: _primaryColor,
                letterSpacing: -0.5
              ),
            ),
            const SizedBox(height: 4),
            Text(
              "Manage, restore, or delete requests and complaints.",
              style: TextStyle(color: Colors.grey[600], fontSize: 14),
            ),
          ],
        ),
        const Spacer(),
        SizedBox(
          width: 300,
          child: TextField(
            controller: _searchController,
            onChanged: _filterData,
            decoration: InputDecoration(
              hintText: "Search records...",
              prefixIcon: const Icon(Icons.search, size: 20),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
            ),
          ),
        ),
        const SizedBox(width: 16),
        IconButton(
          onPressed: _fetchArchives,
          icon: const Icon(Icons.refresh),
          tooltip: "Refresh List",
          style: IconButton.styleFrom(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
      ],
    );
  }

  Widget _buildDesktopCard(Map<String, dynamic> item) {
    final bool isComplaint = item['type'] == 'complaint';
    
    // Determine Title and Subtitle based on Type
    String title = isComplaint ? (item['subject'] ?? 'Complaint') : (item['documentType'] ?? 'Document');
    String subtitle = isComplaint 
        ? (item['complainantName'] ?? item['complainantEmail'] ?? 'Unknown Complainant')
        : (item['fullName'] ?? item['userEmail'] ?? 'Unknown User');

    // Icon
    IconData icon = isComplaint ? Icons.report_problem_outlined : Icons.description_outlined;
    Color iconColor = isComplaint ? Colors.orange[700]! : Colors.blue[700]!;
    Color iconBg = isComplaint ? Colors.orange[50]! : Colors.blue[50]!;

    return Container(
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(8)),
                  child: Icon(icon, color: iconColor),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        subtitle,
                        style: TextStyle(color: Colors.grey[500], fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          
          const Divider(height: 1),
          
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                   _buildDetailRow(Icons.calendar_today, "Archived: ${_formatDate(item['archivedAt'])}"),
                   const SizedBox(height: 8),
                   _buildDetailRow(Icons.person_outline, "By: ${item['archivedBy'] ?? 'Unknown'}"),
                ],
              ),
            ),
          ),
          
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _restoreItem(item),
                    icon: Icon(Icons.replay, size: 16, color: _accentGreen),
                    label: Text("Restore", style: TextStyle(color: Colors.grey[800])),
                    style: OutlinedButton.styleFrom(
                      backgroundColor: Colors.white,
                      side: BorderSide(color: Colors.grey[300]!),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),

              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 14, color: Colors.grey[400]),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: TextStyle(color: Colors.grey[600], fontSize: 13), overflow: TextOverflow.ellipsis)),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text("No archived records found", style: TextStyle(fontSize: 18, color: Colors.grey[500])),
        ],
      ),
    );
  }

  String _formatDate(String? date) {
    if (date == null) return "N/A";
    try {
      return DateFormat.yMMMd().format(DateTime.parse(date));
    } catch (_) { return date; }
  }
}