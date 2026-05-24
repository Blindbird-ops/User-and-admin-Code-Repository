// lib/tables/user_table.dart
import 'package:admin_window/models/complaint.dart';
import 'package:flutter/material.dart';
import 'package:admin_window/models/string_extensions.dart';
import 'package:intl/intl.dart';

class UsersTable extends StatefulWidget {
  final bool loading;
  final List<Map<String, dynamic>> users;
  final List<Map<String, dynamic>> requests;
  final List<Complaint> complaints;
  final void Function(BuildContext context, Map<String, dynamic> user)? onUserComplaint;
  final Future<void> Function(String userId, String requestId, Map<String, dynamic> updatedData)? onUpdateUserRequest;
  final void Function(BuildContext context, String documentType, Map<String, dynamic> request)? onGenerateUserDocument;

  const UsersTable({
    super.key,
    required this.loading,
    required this.users,
    required this.requests,
    required this.complaints,
    this.onUserComplaint,
    this.onUpdateUserRequest,
    this.onGenerateUserDocument,
  });

  @override
  _UsersTableState createState() => _UsersTableState();
}

class _UsersTableState extends State<UsersTable> {
  
  // Logic for generating the role text
  String _getDisplayRole(Map<String, dynamic> user) {
    final role = (user['role'] ?? '').toString().toLowerCase();
    final isVerified = user['isVerified'] == true;

    if (role == 'admin') {
      return 'Admin';
    } else if (role == 'user') {
      return isVerified ? 'Resident' : 'Not Verified';
    } else {
      return 'N/A';
    }
  }

  // Dialog to show full user info (Triggered by clicking name)
  void _showUserInfoDialog(Map<String, dynamic> user) {
    final fullAddress = [
      user['address'],
      user['barangay'],
      user['municipality'],
      user['province'],
    ].where((part) => part != null && part.isNotEmpty).join(', ');

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('User Information'),
          content: SingleChildScrollView(
            child: ListBody(
              children: <Widget>[
                _buildInfoRow('ID:', user['id'] ?? 'N/A'),
                _buildInfoRow('Full Name:', (user['fullName'] ?? 'N/A').toString().toTitleCase()),
                _buildInfoRow('Role:', _getDisplayRole(user)),
                _buildInfoRow('Email:', user['email'] ?? 'N/A'),
                _buildInfoRow('Username:', (user['username'] ?? 'N/A').toString().toTitleCase()),
                _buildInfoRow('Full Address:', fullAddress.isEmpty ? 'N/A' : fullAddress.toTitleCase()),
                _buildInfoRow('Birthdate:', user['birthdate'] ?? 'N/A'),
                _buildInfoRow('Sex:', (user['sex'] ?? 'N/A').toString().toTitleCase()),
                _buildInfoRow('Verified:', (user['isVerified'] ?? false).toString()),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Close'),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        );
      },
    );
  }

  // Helper widget for the Info Dialog
  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: RichText(
        text: TextSpan(
          style: DefaultTextStyle.of(context).style,
          children: [
            TextSpan(text: '$label ', style: const TextStyle(fontWeight: FontWeight.bold)),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }

  // NOTE: These dialog methods (_showUserRequestsDialog, _showUserComplaintsDialog) 
  // are preserved here in the code logic, but are no longer triggered by the UI 
  // since the 3-dot menu was removed.
  void _showUserRequestsDialog(BuildContext context, Map<String, dynamic> user, String filterType) {
    final userId = user['id'];
    List<Map<String, dynamic>> requests = widget.requests.where((req) => req['userId'] == userId).toList();

    if (filterType == "appointment") {
      requests = requests.where((req) {
        String docType = req['documentType']?.toString().toLowerCase() ?? "";
        return docType.contains("appointment") || docType.contains("meeting");
      }).toList();
    } else if (filterType == "document") {
      requests = requests.where((req) {
        String docType = req['documentType']?.toString().toLowerCase() ?? "";
        return !docType.contains("appointment") && !docType.contains("meeting");
      }).toList();
    }

    if (requests.isEmpty) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text("No ${filterType.toTitleCase()} Requests Found"),
          content: Text("There are no ${filterType.toLowerCase()} requests available for ${user['fullName'] ?? 'N/A'}."),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("OK")),
          ],
        ),
      );
      return;
    }

    List<String> dropdownOptions = filterType == "appointment"
        ? ["Pending", "Approved", "Disapproved", "Rescheduled"]
        : ["Pending", "Processing", "Rejected", "Successful"];

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("${filterType.toTitleCase()} Requests for ${user['fullName'] ?? 'User'}"),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500, minWidth: 400),
          child: SingleChildScrollView(
            child: DataTable(
              columnSpacing: 20,
              columns: const [
                DataColumn(label: Text("Request Type", style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text("Status", style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text("Actions", style: TextStyle(fontWeight: FontWeight.bold))),
              ],
              rows: requests.map((req) {
                String currentStatus = (req['status'] ?? "Pending").toString();

                if (!dropdownOptions.contains(currentStatus)) {
                  if (currentStatus.toLowerCase() == 'new') {
                    currentStatus = 'Pending';
                  }
                  if (!dropdownOptions.contains(currentStatus)) {
                    currentStatus = "Pending";
                  }
                }

                return DataRow(cells: [
                  DataCell(Text(req['documentType'] ?? "N/A")),
                  DataCell(
                    DropdownButton<String>(
                      value: currentStatus,
                      onChanged: (String? newStatus) async {
                        if (newStatus == null || newStatus == currentStatus) return;
                        if (widget.onUpdateUserRequest != null) {
                          await widget.onUpdateUserRequest!(user['id'] ?? "", req['requestId'] ?? "", {'status': newStatus});
                           Navigator.pop(context); 
                        }
                      },
                      items: dropdownOptions.map((value) => DropdownMenuItem<String>(value: value, child: Text(value))).toList(),
                    ),
                  ),
                  DataCell(
                    (filterType == 'document' && widget.onGenerateUserDocument != null)
                      ? IconButton(
                          icon: const Icon(Icons.picture_as_pdf, color: Colors.green),
                          tooltip: "Generate Document",
                          onPressed: () {
                            widget.onGenerateUserDocument!(context, req['documentType'] ?? "N/A", req);
                          },
                        )
                      : const SizedBox.shrink(), 
                  ),
                ]);
              }).toList(),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Close")),
        ],
      ),
    );
  }

  void _showUserComplaintsDialog(BuildContext context, Map<String, dynamic> user) {
    final userEmail = (user['email'] ?? '').toString().toLowerCase();
    if (userEmail.isEmpty) return;

    final userComplaints = widget.complaints.where((c) => c.complainantEmail.toLowerCase() == userEmail).toList();

    if (userComplaints.isEmpty) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text("No Complaints Found"),
          content: Text("This user has not filed any complaints."),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("OK")),
          ],
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Complaints by ${user['fullName'] ?? 'User'}"),
        content: SizedBox(
          width: 600,
          child: SingleChildScrollView(
            child: DataTable(
              columns: const [
                DataColumn(label: Text('Date')),
                DataColumn(label: Text('Subject')),
                DataColumn(label: Text('Status')),
              ],
              rows: userComplaints.map((complaint) {
                return DataRow(
                  cells: [
                    DataCell(Text(DateFormat.yMd().format(complaint.timestamp))),
                    DataCell(Text(complaint.subject)),
                    DataCell(Chip(
                      label: Text(
                        complaint.status.isEmpty ? 'New' : complaint.status,
                        style: const TextStyle(color: Colors.white),
                      ),
                      backgroundColor: complaint.status.toLowerCase() == 'resolved'
                          ? Colors.green
                          : complaint.status.toLowerCase() == 'in progress'
                              ? Colors.orange
                              : Colors.red,
                    )),
                  ],
                );
              }).toList(),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Close")),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.loading) return const Center(child: CircularProgressIndicator());

    // Filter to hide ghost users
    final List<Map<String, dynamic>> visibleUsers = widget.users.where((user) {
      final fullName = user['fullName'];
      return fullName != null && fullName.toString().trim().isNotEmpty;
    }).toList();

    if (visibleUsers.isEmpty) {
      return const Center(child: Text("No users found", style: TextStyle(fontSize: 18)));
    }

    return SingleChildScrollView(
      scrollDirection: Axis.vertical, 
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal, 
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minWidth: MediaQuery.of(context).size.width,
          ),
          child: DataTable(
            headingRowColor: WidgetStateProperty.all(Colors.blue[100]),
            columnSpacing: 20,
            columns: const [
              DataColumn(label: Text("Full Name", style: TextStyle(fontWeight: FontWeight.bold))),
              DataColumn(label: Text("Role", style: TextStyle(fontWeight: FontWeight.bold))),
            ],
            rows: visibleUsers.map((user) {
              return DataRow(
                cells: [
                  // Cell 1: Name (Clickable)
                  DataCell(
                    InkWell(
                      onTap: () {
                        _showUserInfoDialog(user);
                      },
                      child: Text((user['fullName'] ?? "N/A").toString().toTitleCase()),
                    ),
                  ),
                  // Cell 2: Role (Text Only - 3 Dots Removed)
                  DataCell(
                    Text(_getDisplayRole(user)),
                  ),
                ],
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}