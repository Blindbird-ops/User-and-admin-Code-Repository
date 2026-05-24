// lib/services/report_generator.dart
import 'dart:convert';
import 'dart:typed_data';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';

class ReportGenerator {
  // ⚠️ KEEP YOUR API KEY HERE
  static const String _apiKey = 'AIzaSyDYsyCGNvPEeOM-wP2x-S67kjDgioFsY3o';

  // ==========================================
  // 1. SYSTEM LOGS REPORT
  // ==========================================

  static Future<String> getLogAnalysis(List<Map<String, dynamic>> logs) async {
    try {
      final model = GenerativeModel(model: 'gemini-flash-latest', apiKey: _apiKey);
      String logsString = jsonEncode(logs);
      if (logs.length > 40) logsString = jsonEncode(logs.sublist(logs.length - 40));

      final prompt = "You are a professional System Administrator. "
          "Analyze the following JSON system logs. "
          "Write a formal 'Executive Summary' (max 2 paragraphs). "
          "Focus ONLY on critical errors, security warnings, and suspicious patterns. "
          "LOG DATA: $logsString";

      final response = await model.generateContent([Content.text(prompt)]);
      return response.text ?? "No analysis generated.";
    } catch (e) {
      return "AI Summary Unavailable: $e";
    }
  }

  static Future<void> printReport(List<Map<String, dynamic>> logs) async {
    final pdf = pw.Document();
    final aiSummary = await getLogAnalysis(logs);
    final font = await PdfGoogleFonts.notoSansRegular();
    final fontBold = await PdfGoogleFonts.notoSansBold();

    pdf.addPage(
      pw.MultiPage(
        theme: pw.ThemeData.withFont(base: font, bold: fontBold),
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return [
            _buildHeader("System Activity Report"),
            pw.SizedBox(height: 20),
            _buildAISummary("Executive Summary (System Admin)", aiSummary),
            pw.SizedBox(height: 30),
            pw.Table.fromTextArray(
              headers: ['Timestamp', 'Action By', 'Message'],
              data: logs.map((log) => [
                log['timestamp'] ?? 'N/A',
                log['role'] == 'admin' ? "${log['actor']} (Admin)" : (log['actor'] ?? 'System'),
                log['message'] ?? '',
              ]).toList(),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.blue700),
              headerStyle: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold),
              cellStyle: const pw.TextStyle(fontSize: 10),
            ),
          ];
        },
      ),
    );
    await _saveAndShare(pdf, 'system_logs');
  }

  // ==========================================
  // 2. FINANCIAL REPORT
  // ==========================================

  static Future<String> getFinancialAnalysis(double total, double avg, Map<String, double> breakdown) async {
    try {
      final model = GenerativeModel(model: 'gemini-flash-latest', apiKey: _apiKey);
      
      final prompt = "You are a Chief Financial Officer (CFO). "
          "Analyze this financial summary: "
          "Total Revenue: ₱$total. Average Transaction: ₱$avg. "
          "Income Breakdown: $breakdown. "
          "Write a formal 'Financial Executive Summary' (max 2 paragraphs). "
          "Discuss the revenue distribution and identify the top income source. "
          "Use professional tone.";

      final response = await model.generateContent([Content.text(prompt)]);
      return response.text ?? "No analysis generated.";
    } catch (e) {
      return "AI Financial Analysis Unavailable: $e";
    }
  }

  static Future<void> printFinancialReport(List<Map<String, dynamic>> transactions) async {
    final pdf = pw.Document();
    final font = await PdfGoogleFonts.notoSansRegular();
    final fontBold = await PdfGoogleFonts.notoSansBold();
    final currencyFormat = NumberFormat.currency(locale: 'en_PH', symbol: 'P');

    double totalRevenue = 0;
    Map<String, double> incomeByType = {};

    for (var tx in transactions) {
      final amount = (tx['amount'] as num? ?? 0.0).toDouble();
      final type = tx['documentType'] ?? 'Other';
      totalRevenue += amount;
      incomeByType[type] = (incomeByType[type] ?? 0) + amount;
    }
    double avgTransaction = transactions.isNotEmpty ? totalRevenue / transactions.length : 0;

    final aiSummary = await getFinancialAnalysis(totalRevenue, avgTransaction, incomeByType);

    pdf.addPage(
      pw.MultiPage(
        theme: pw.ThemeData.withFont(base: font, bold: fontBold),
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return [
            _buildHeader("Financial Performance Report"),
            pw.SizedBox(height: 20),
            pw.Row(
              children: [
                _buildMetricBox("Total Revenue", currencyFormat.format(totalRevenue)),
                _buildMetricBox("Transactions", "${transactions.length}"),
                _buildMetricBox("Avg. Ticket", currencyFormat.format(avgTransaction)),
              ],
            ),
            pw.SizedBox(height: 20),
            _buildAISummary("Executive Summary (CFO Analysis)", aiSummary),
            pw.SizedBox(height: 30),
            pw.Text("Income Segmentation", style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 10),
            pw.Table.fromTextArray(
              headers: ['Category', 'Revenue', '% Share'],
              data: incomeByType.entries.map((e) {
                 final percent = (e.value / totalRevenue * 100).toStringAsFixed(1);
                 return [e.key, currencyFormat.format(e.value), "$percent%"];
              }).toList(),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.green700),
              headerStyle: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold),
              cellAlignment: pw.Alignment.centerLeft,
            ),
            pw.SizedBox(height: 30),
            pw.Text("Recent Transactions (Last 50)", style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 10),
            pw.Table.fromTextArray(
              headers: ['Date', 'Type', 'Payer', 'Amount'],
              data: transactions.take(50).map((tx) {
                final dt = DateTime.tryParse(tx['timestamp'].toString()) ?? DateTime.now();
                final dateStr = "${dt.year}-${dt.month}-${dt.day}";
                return [
                  dateStr,
                  tx['documentType'] ?? '-',
                  tx['paidByName'] ?? 'Unknown',
                  currencyFormat.format(tx['amount'] ?? 0),
                ];
              }).toList(),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
              headerStyle: pw.TextStyle(color: PdfColors.black, fontWeight: pw.FontWeight.bold),
              cellStyle: const pw.TextStyle(fontSize: 9),
            ),
          ];
        },
      ),
    );

    await _saveAndShare(pdf, 'financial_report');
  }

  // ==========================================
  // 3. CENSUS / DEMOGRAPHIC REPORT
  // ==========================================

  static Future<String> getCensusAnalysis(
      int pop, int hhs, int male, int female, double avgInc, Map<String, int> puroks) async {
    try {
      final model = GenerativeModel(model: 'gemini-flash-latest', apiKey: _apiKey);
      final prompt = "You are a local government demographic analyst. "
          "Summarize this census data: "
          "Total Population: $pop. Valid Households: $hhs. "
          "Males: $male. Females: $female. "
          "Average Monthly Income: ₱$avgInc. "
          "Population by Purok: $puroks. "
          "Write a concise 'Demographic Executive Summary' (max 2 short paragraphs). "
          "Discuss the gender balance, the economic indicator (income), and the most populated purok. "
          "Keep it formal and professional.";

      final response = await model.generateContent([Content.text(prompt)]);
      return response.text ?? "No analysis generated.";
    } catch (e) {
      return "AI Demographic Analysis Unavailable: $e";
    }
  }

  static Future<void> printCensusReport({
    required int totalPopulation,
    required int validHouseholds,
    required int maleCount,
    required int femaleCount,
    required Map<String, int> ageGroups,
    required Map<String, int> purokPopulation,
    required double averageIncome,
    required List<Map<String, dynamic>> households,
    required Map<String, List<Map<String, dynamic>>> duplicateGroups,
    required Map<String, String> duplicateReasons,
  }) async {
    final pdf = pw.Document();
    final font = await PdfGoogleFonts.notoSansRegular();
    final fontBold = await PdfGoogleFonts.notoSansBold();
    final currencyFormat = NumberFormat.currency(locale: 'en_PH', symbol: 'P');

    final aiSummary = await getCensusAnalysis(
      totalPopulation, validHouseholds, maleCount, femaleCount, averageIncome, purokPopulation
    );

    // PAGE 1: Core Demographics
    pdf.addPage(
      pw.MultiPage(
        theme: pw.ThemeData.withFont(base: font, bold: fontBold),
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return [
            _buildCensusHeader(),
            pw.SizedBox(height: 20),
            
            // 4 Top Metrics
            pw.Row(
              children: [
                _buildMetricBox("Total Pop", "$totalPopulation", PdfColors.blue700),
                _buildMetricBox("Households", "$validHouseholds", PdfColors.green700),
                _buildMetricBox("Avg Income", currencyFormat.format(averageIncome), PdfColors.teal700),
                _buildMetricBox("M/F Ratio", "$maleCount / $femaleCount", PdfColors.purple700),
              ],
            ),
            pw.SizedBox(height: 20),
            
            _buildAISummary("Executive Summary (Demographics)", aiSummary),
            pw.SizedBox(height: 20),

            pw.Text("Demographics (Age Distribution)", style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 10),
            _buildAgeDistributionTable(ageGroups, totalPopulation),
            pw.SizedBox(height: 20),
            
            pw.Text("Population by Purok", style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 10),
            _buildPurokDistributionTable(purokPopulation, totalPopulation),
          ];
        },
      ),
    );

    // PAGE 2: Duplicate / Warning Logs (Only prints if there are duplicates)
    if (duplicateGroups.isNotEmpty) {
      pdf.addPage(
        pw.MultiPage(
          theme: pw.ThemeData.withFont(base: font, bold: fontBold),
          pageFormat: PdfPageFormat.a4,
          build: (pw.Context context) {
            return [
              pw.Header(
                level: 1,
                child: pw.Text("Data Quality Warnings", style: pw.TextStyle(color: PdfColors.red700, fontWeight: pw.FontWeight.bold)),
              ),
              pw.SizedBox(height: 10),
              pw.Text(
                "The following records appear to be duplicate entries based on matching family members. Manual verification is recommended.", 
                style: const pw.TextStyle(color: PdfColors.red900)
              ),
              pw.SizedBox(height: 15),
              ...duplicateGroups.entries.map((entry) {
                final groupId = entry.key;
                final group = entry.value;
                final reason = duplicateReasons[groupId] ?? "Unknown reason";
                return pw.Container(
                  margin: const pw.EdgeInsets.only(bottom: 15),
                  padding: const pw.EdgeInsets.all(10),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.red50,
                    border: pw.Border.all(color: PdfColors.red200),
                    borderRadius: pw.BorderRadius.circular(5),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text("Group: $groupId", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.red800)),
                      pw.SizedBox(height: 5),
                      pw.Text("Reason: $reason", style: const pw.TextStyle(fontSize: 10, color: PdfColors.black)),
                      pw.SizedBox(height: 10),
                      ...group.map((h) => pw.Text("• ${h['headOfFamily']} (ID: ${h['id']}, Purok: ${h['purok']})", style: const pw.TextStyle(fontSize: 10))),
                    ]
                  )
                );
              }),
            ];
          }
        )
      );
    }

    await _saveAndShare(pdf, 'census_report');
  }

  // ==========================================
  // HELPER WIDGETS
  // ==========================================

  static pw.Widget _buildHeader(String title) {
    return pw.Header(
      level: 0,
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(title, style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold, color: PdfColors.blueGrey800)),
          pw.Text("Date: ${DateTime.now().toString().split(' ')[0]}", style: const pw.TextStyle(color: PdfColors.grey)),
        ],
      ),
    );
  }

  static pw.Widget _buildAISummary(String title, String content) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey100,
        border: pw.Border.all(color: PdfColors.grey400),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(title, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.deepPurple)),
          pw.Divider(color: PdfColors.grey400),
          pw.Text(content, style: const pw.TextStyle(fontSize: 10, height: 1.5)),
        ],
      ),
    );
  }

  // Flexible Metric Box (Expands evenly)
  static pw.Widget _buildMetricBox(String label, String value, [PdfColor? color]) {
    final actualColor = color ?? PdfColors.green700;
    return pw.Expanded(
      child: pw.Container(
        margin: const pw.EdgeInsets.symmetric(horizontal: 4),
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey300, width: 2),
          borderRadius: pw.BorderRadius.circular(8),
          color: PdfColors.grey100, 
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.Text(
              label,
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
              textAlign: pw.TextAlign.center,
            ),
            pw.SizedBox(height: 6),
            pw.Text(
              value,
              style: pw.TextStyle(
                fontSize: 13,
                fontWeight: pw.FontWeight.bold,
                color: actualColor,
              ),
              textAlign: pw.TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  static pw.Widget _buildTableCell(String text, {bool isHeader = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(6),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: isHeader ? 11 : 10,
          fontWeight: isHeader ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      ),
    );
  }

  static pw.Widget _buildCensusHeader() {
    return pw.Container(
      decoration: pw.BoxDecoration(
        color: PdfColors.blue700,
        borderRadius: pw.BorderRadius.circular(8),
      ),
      padding: const pw.EdgeInsets.all(20),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                "BARANGAY PULARAQUEN",
                style: pw.TextStyle(
                  fontSize: 24,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.white,
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                "Census & Demographic Report",
                style: const pw.TextStyle(
                  fontSize: 14,
                  color: PdfColors.grey300,
                ),
              ),
            ],
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(
                "Generated:",
                style: const pw.TextStyle(
                  fontSize: 10,
                  color: PdfColors.grey300,
                ),
              ),
              pw.Text(
                DateFormat('MMMM dd, yyyy').format(DateTime.now()),
                style: pw.TextStyle(
                  fontSize: 12,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.white,
                ),
              ),
              pw.Text(
                DateFormat('hh:mm a').format(DateTime.now()),
                style: const pw.TextStyle(
                  fontSize: 10,
                  color: PdfColors.grey300,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildAgeDistributionTable(Map<String, int> ageGroups, int totalPopulation) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey400),
      columnWidths: {
        0: const pw.FlexColumnWidth(2),
        1: const pw.FlexColumnWidth(2),
        2: const pw.FlexColumnWidth(2),
        3: const pw.FlexColumnWidth(4),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.purple100),
          children: [
            _buildTableCell("Age Group", isHeader: true),
            _buildTableCell("Population", isHeader: true),
            _buildTableCell("Percentage", isHeader: true),
            _buildTableCell("Visual", isHeader: true),
          ],
        ),
        ...ageGroups.entries.map((entry) {
          final percent = totalPopulation > 0 ? (entry.value / totalPopulation * 100) : 0.0;
          return pw.TableRow(
            children: [
              _buildTableCell(entry.key),
              _buildTableCell(entry.value.toString()),
              _buildTableCell("${percent.toStringAsFixed(1)}%"),
              pw.Padding(
                padding: const pw.EdgeInsets.all(4),
                child: pw.Stack(
                  children: [
                    pw.Container(
                      height: 12,
                      decoration: pw.BoxDecoration(
                        color: PdfColors.grey300,
                        borderRadius: pw.BorderRadius.circular(2),
                      ),
                    ),
                    pw.Container(
                      height: 12,
                      width: 150 * (percent / 100),
                      decoration: pw.BoxDecoration(
                        color: PdfColors.purple400,
                        borderRadius: pw.BorderRadius.circular(2),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        }),
      ],
    );
  }

  static pw.Widget _buildPurokDistributionTable(Map<String, int> purokPopulation, int totalPopulation) {
    final sortedPuroks = purokPopulation.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey400),
      columnWidths: {
        0: const pw.FlexColumnWidth(2),
        1: const pw.FlexColumnWidth(2),
        2: const pw.FlexColumnWidth(2),
        3: const pw.FlexColumnWidth(4),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.green100),
          children: [
            _buildTableCell("Purok", isHeader: true),
            _buildTableCell("Population", isHeader: true),
            _buildTableCell("Percentage", isHeader: true),
            _buildTableCell("Distribution", isHeader: true),
          ],
        ),
        ...sortedPuroks.map((entry) {
          final percent = totalPopulation > 0 ? (entry.value / totalPopulation * 100) : 0.0;
          return pw.TableRow(
            children: [
              _buildTableCell(entry.key),
              _buildTableCell(entry.value.toString()),
              _buildTableCell("${percent.toStringAsFixed(1)}%"),
              pw.Padding(
                padding: const pw.EdgeInsets.all(4),
                child: pw.Stack(
                  children: [
                    pw.Container(
                      height: 12,
                      decoration: pw.BoxDecoration(
                        color: PdfColors.grey300,
                        borderRadius: pw.BorderRadius.circular(2),
                      ),
                    ),
                    pw.Container(
                      height: 12,
                      width: 150 * (percent / 100),
                      decoration: pw.BoxDecoration(
                        color: PdfColors.green400,
                        borderRadius: pw.BorderRadius.circular(2),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        }),
      ],
    );
  }

  static Future<void> _saveAndShare(pw.Document pdf, String prefix) async {
    try {
      final Uint8List bytes = await pdf.save();
      await Printing.sharePdf(
        bytes: bytes,
        filename: '${prefix}_${DateTime.now().millisecondsSinceEpoch}.pdf',
      );
    } catch (e) {
      print("Error saving PDF: $e");
    }
  }
}