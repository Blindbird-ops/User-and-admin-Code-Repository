// lib/tables/logs_table.dart
import 'package:flutter/material.dart';
// Import the service we just created
import '/services/report_generator.dart'; 

class LogsTable extends StatefulWidget {
  final bool loading;
  final List<Map<String, dynamic>> logs;

  const LogsTable({
    super.key,
    required this.loading,
    required this.logs,
  });

  @override
  State<LogsTable> createState() => _LogsTableState();
}

class _LogsTableState extends State<LogsTable> {
  bool isGeneratingReport = false;

  Future<void> _handleGenerateReport() async {
    setState(() => isGeneratingReport = true);
    
    // Call our service
    await ReportGenerator.printReport(widget.logs);
    
    if (mounted) {
      setState(() => isGeneratingReport = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.loading) return const Center(child: CircularProgressIndicator());
    if (widget.logs.isEmpty) {
      return const Center(child: Text("No logs found", style: TextStyle(fontSize: 18)));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // --- Header with Report Button ---
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              ElevatedButton.icon(
                onPressed: isGeneratingReport ? null : _handleGenerateReport,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                ),
                icon: isGeneratingReport 
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) 
                  : const Icon(Icons.picture_as_pdf),
                label: Text(isGeneratingReport ? "Analyzing..." : "Download AI Report"),
              ),
            ],
          ),
        ),

        // --- Your Existing Table (Wrapped in Expanded) ---
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.vertical,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: 1000, 
                child: DataTable(
                  headingRowColor: WidgetStateProperty.all(Colors.blue[100]),
                  columnSpacing: 20,
                  columns: const [
                    DataColumn(label: Text("Timestamp", style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(label: Text("Action By", style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(label: Text("Message", style: TextStyle(fontWeight: FontWeight.bold))),
                  ],
                  rows: widget.logs.map((log) {
                    Widget actorCellWidget;
                    final actor = log['actor'] as String?;
                    final role = log['role'] as String?;

                    if (actor != null && role == 'admin') {
                      actorCellWidget = RichText(
                        text: TextSpan(
                          style: DefaultTextStyle.of(context).style,
                          children: [
                            TextSpan(text: '$actor '),
                            const TextSpan(
                              text: '(Admin)',
                              style: TextStyle(
                                color: Colors.deepPurple,
                                fontWeight: FontWeight.bold,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ],
                        ),
                      );
                    } else {
                      actorCellWidget = Text(actor ?? 'System');
                    }

                    return DataRow(
                      cells: [
                        DataCell(Text(log['timestamp'] ?? 'N/A')),
                        DataCell(actorCellWidget),
                        DataCell(
                          SizedBox(
                            width: 450, 
                            child: Text(
                              log['message'] ?? '',
                              softWrap: true, 
                            ),
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}