// lib/tables/request_table_wrapper.dart

import 'package:flutter/material.dart';
import 'request_table.dart'; // Make sure this path is correct

// Enum for clarity
enum RequestTypeFilter { all, appointments, documents }
enum SortOrder { newestFirst, oldestFirst }

class RequestTableWrapper extends StatefulWidget {
  // Pass all the original properties needed by RequestTable through this wrapper
  final bool loading;
  final List<Map<String, dynamic>> allRequests; // This will hold the master list
  final Set<String> selectedRequests;
  final ValueChanged<Set<String>> onSelectedRequestsChanged;
  final Future<void> Function(String userId, String requestId, Map<String, dynamic> updatedData) onUpdateRequest;
  final Future<void> Function(String userId, String requestId) onRescheduleAppointment;
  final Future<void> Function(String userId, String requestId) onApproveAppointment;
  final Future<void> Function(String userId, String requestId) onDisapproveAppointment;
  final Future<bool> Function(String newStatus) onConfirmStatusChange;
  final VoidCallback onDeleteSelectedRequests;
  final void Function(BuildContext context, String documentType, Map<String, dynamic> request) onGenerateDocument;
  final Future<void> Function(String message) onLogAction;
  final Future<bool> Function(Map<String, dynamic> request, double amount) onRecordPayment;

  const RequestTableWrapper({
    super.key,
    required this.loading,
    required this.allRequests, // Changed from 'requests' to 'allRequests'
    required this.selectedRequests,
    required this.onSelectedRequestsChanged,
    required this.onUpdateRequest,
    required this.onRescheduleAppointment,
    required this.onApproveAppointment,
    required this.onDisapproveAppointment,
    required this.onConfirmStatusChange,
    required this.onDeleteSelectedRequests,
    required this.onGenerateDocument,
    required this.onLogAction,
    required this.onRecordPayment,
  });

  @override
  State<RequestTableWrapper> createState() => _RequestTableWrapperState();
}

class _RequestTableWrapperState extends State<RequestTableWrapper> {
  // State variables to hold the user's choices
  RequestTypeFilter _currentFilter = RequestTypeFilter.all;
  SortOrder _currentSort = SortOrder.newestFirst; // Default to newest first

  // A helper function to safely parse timestamps from various data types
  DateTime _parseTimestamp(dynamic value) {
    if (value == null) return DateTime.fromMillisecondsSinceEpoch(0);
    try {
      if (value is int) {
        // Handle both seconds and milliseconds
        return value < 2000000000
            ? DateTime.fromMillisecondsSinceEpoch(value * 1000)
            : DateTime.fromMillisecondsSinceEpoch(value);
      } else if (value is String) {
        return DateTime.parse(value);
      }
      // Add other types if necessary, like Firebase Timestamp
    } catch (e) {
      // Fallback for parsing errors
      return DateTime.fromMillisecondsSinceEpoch(0);
    }
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  // This is the core logic function
  List<Map<String, dynamic>> _getProcessedRequests() {
    List<Map<String, dynamic>> processedList = List.from(widget.allRequests);

    // --- 1. SORTING ---
    processedList.sort((a, b) {
      // Use the 'timestamp' field for sorting. Adjust if your field is named differently.
      final aDate = _parseTimestamp(a['timestamp']);
      final bDate = _parseTimestamp(b['timestamp']);

      if (_currentSort == SortOrder.newestFirst) {
        return bDate.compareTo(aDate); // Newest first
      } else {
        return aDate.compareTo(bDate); // Oldest first
      }
    });

    // --- 2. FILTERING ---
    if (_currentFilter != RequestTypeFilter.all) {
      processedList = processedList.where((request) {
        final docType = (request['documentType'] ?? '').toString().toLowerCase();
        final isAppointment = docType.contains('appointment') || docType.contains('meeting');

        if (_currentFilter == RequestTypeFilter.appointments) {
          return isAppointment;
        } else { // documents
          return !isAppointment;
        }
      }).toList();
    }
    
    return processedList;
  }

  @override
  Widget build(BuildContext context) {
    // Get the sorted and filtered list on every build
    final displayedRequests = _getProcessedRequests();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // --- UI CONTROLS FOR SORTING AND FILTERING ---
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Wrap(
            spacing: 16.0,
            runSpacing: 8.0,
            alignment: WrapAlignment.start,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              // Filter Dropdown
              _buildFilterDropdown(),
              // Sort Dropdown
              _buildSortDropdown(),
            ],
          ),
        ),
        const Divider(height: 1),
        // --- THE ORIGINAL REQUEST TABLE ---
        Expanded(
          child: RequestTable(
            // Pass the processed list, not the original one
            requests: displayedRequests,
            
            // Pass all other properties through
            loading: widget.loading,
            selectedRequests: widget.selectedRequests,
            onSelectedRequestsChanged: widget.onSelectedRequestsChanged,
            onUpdateRequest: widget.onUpdateRequest,
            onRescheduleAppointment: widget.onRescheduleAppointment,
            onApproveAppointment: widget.onApproveAppointment,
            onDisapproveAppointment: widget.onDisapproveAppointment,
            onConfirmStatusChange: widget.onConfirmStatusChange,
            onDeleteSelectedRequests: widget.onDeleteSelectedRequests,
            onGenerateDocument: widget.onGenerateDocument,
            onLogAction: widget.onLogAction,
            onRecordPayment: widget.onRecordPayment,
          ),
        ),
      ],
    );
  }

  // Helper widget for the filter dropdown for cleaner build method
  Widget _buildFilterDropdown() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.filter_list, color: Colors.black54, size: 20),
        const SizedBox(width: 8),
        const Text('Show:', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(width: 8),
        DropdownButton<RequestTypeFilter>(
          value: _currentFilter,
          onChanged: (RequestTypeFilter? newValue) {
            if (newValue != null) {
              setState(() {
                _currentFilter = newValue;
              });
            }
          },
          items: const [
            DropdownMenuItem(
              value: RequestTypeFilter.all,
              child: Text('All Requests'),
            ),
            DropdownMenuItem(
              value: RequestTypeFilter.appointments,
              child: Text('Appointments Only'),
            ),
            DropdownMenuItem(
              value: RequestTypeFilter.documents,
              child: Text('Documents Only'),
            ),
          ],
        ),
      ],
    );
  }

  // Helper widget for the sort dropdown
  Widget _buildSortDropdown() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.sort, color: Colors.black54, size: 20),
        const SizedBox(width: 8),
        const Text('Sort by:', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(width: 8),
        DropdownButton<SortOrder>(
          value: _currentSort,
          onChanged: (SortOrder? newValue) {
            if (newValue != null) {
              setState(() {
                _currentSort = newValue;
              });
            }
          },
          items: const [
            DropdownMenuItem(
              value: SortOrder.newestFirst,
              child: Text('Newest First'),
            ),
            DropdownMenuItem(
              value: SortOrder.oldestFirst,
              child: Text('Oldest First'),
            ),
          ],
        ),
      ],
    );
  }
}