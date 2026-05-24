import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/widgets.dart' as pw;
import 'print_helper.dart';

class GeneratedBarangayBusinessClearancePage extends StatefulWidget {
  final String initialBusinessName;
  final String initialBusinessAddress;
  final String initialOperatorName;
  final String initialOperatorAddress;

  const GeneratedBarangayBusinessClearancePage({
    super.key,
    required this.initialBusinessName,
    required this.initialBusinessAddress,
    required this.initialOperatorName,
    required this.initialOperatorAddress,
  });

  @override
  _GeneratedBarangayBusinessClearancePageState createState() =>
      _GeneratedBarangayBusinessClearancePageState();
}

class _GeneratedBarangayBusinessClearancePageState
    extends State<GeneratedBarangayBusinessClearancePage> {
  bool _isEditing = false;

  late String businessName;
  late String businessAddress;
  late String operatorName;
  late String operatorAddress;

  late TextEditingController _businessNameController;
  late TextEditingController _businessAddressController;
  late TextEditingController _operatorNameController;
  late TextEditingController _operatorAddressController;
  late TextEditingController _amountPaidController;

  @override
  void initState() {
    super.initState();
    businessName = widget.initialBusinessName;
    businessAddress = widget.initialBusinessAddress;
    operatorName = widget.initialOperatorName;
    operatorAddress = widget.initialOperatorAddress;

    _businessNameController = TextEditingController(text: businessName);
    _businessAddressController = TextEditingController(text: businessAddress);
    _operatorNameController = TextEditingController(text: operatorName);
    _operatorAddressController = TextEditingController(text: operatorAddress);
    _amountPaidController = TextEditingController(text: "200.00");
  }

  @override
  void dispose() {
    _businessNameController.dispose();
    _businessAddressController.dispose();
    _operatorNameController.dispose();
    _operatorAddressController.dispose();
    _amountPaidController.dispose();
    super.dispose();
  }

  void _toggleEdit() {
    setState(() {
      if (_isEditing) {
        // Save changes when toggling off edit mode.
        businessName = _businessNameController.text;
        businessAddress = _businessAddressController.text;
        operatorName = _operatorNameController.text;
        operatorAddress = _operatorAddressController.text;
      }
      _isEditing = !_isEditing;
    });
  }

  /// --- UI Helpers ---
  ///
  /// Returns a list of InlineSpan where the day number is rendered in normal style
  /// and the suffix (st, nd, rd, th) is rendered in a smaller font and raised.
  List<InlineSpan> getDayTextSpans(int day, TextStyle baseStyle) {
    String dayStr = day.toString();
    String suffix;
    if (day == 1 || day == 21 || day == 31) {
      suffix = "st";
    } else if (day == 2 || day == 22) {
      suffix = "nd";
    } else if (day == 3 || day == 23) {
      suffix = "rd";
    } else {
      suffix = "th";
    }
    return [
      TextSpan(text: dayStr, style: baseStyle),
      WidgetSpan(
        child: Transform.translate(
          offset: Offset(0, -5), // Adjust the vertical offset as needed
          child: Text(
            suffix,
            style: baseStyle.copyWith(fontSize: baseStyle.fontSize! * 0.7),
          ),
        ),
      ),
    ];
  }

  /// --- PDF Helpers ---
  ///
  /// Returns just the suffix string for the given day.
  String getSuffix(int day) {
    if (day == 1 || day == 21 || day == 31) {
      return "st";
    } else if (day == 2 || day == 22) {
      return "nd";
    } else if (day == 3 || day == 23) {
      return "rd";
    } else {
      return "th";
    }
  }

  Future<void> _printDocument() async {
    // Load asset images as bytes.
    final logo1Data = await rootBundle.load('assets/taytay_logo.png');
    final logo2Data = await rootBundle.load('assets/pularaquen_logo.png');
    final logo1 = pw.MemoryImage(logo1Data.buffer.asUint8List());
    final logo2 = pw.MemoryImage(logo2Data.buffer.asUint8List());

    // Load the custom TimesNewRoman font from your assets.
    final fontData = await rootBundle.load('assets/times.ttf');
    final customFont = pw.Font.ttf(fontData.buffer.asByteData());

    // Current date values.
    final DateTime now = DateTime.now();
    final String issuedMonth = DateFormat('MMMM').format(now);
    final String issuedYear = DateFormat('yyyy').format(now);
    final String issuedOn = DateFormat('dd-MM-yyyy').format(now);

    final pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        margin: const pw.EdgeInsets.all(40),
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              // Top Row with Logos and Government Hierarchy Text.
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Image(logo1, width: 80, height: 80),
                  pw.Column(
                    children: [
                      pw.Text(
                        "Republic of the Philippines",
                        style: pw.TextStyle(font: customFont, fontSize: 12),
                        textAlign: pw.TextAlign.center,
                      ),
                      pw.Text(
                        "Province of Palawan",
                        style: pw.TextStyle(font: customFont, fontSize: 12),
                        textAlign: pw.TextAlign.center,
                      ),
                      pw.Text(
                        "Municipality of Taytay",
                        style: pw.TextStyle(font: customFont, fontSize: 12),
                        textAlign: pw.TextAlign.center,
                      ),
                      pw.Text(
                        "Barangay Pularaquen",
                        style: pw.TextStyle(font: customFont, fontSize: 12),
                        textAlign: pw.TextAlign.center,
                      ),
                    ],
                  ),
                  pw.Image(logo2, width: 80, height: 80),
                ],
              ),
              pw.SizedBox(height: 20),
              // Office Heading.
              pw.Text(
                "OFFICE OF THE PUNONG BARANGAY",
                style: pw.TextStyle(font: customFont, fontSize: 14, fontWeight: pw.FontWeight.bold),
                textAlign: pw.TextAlign.center,
              ),
              pw.SizedBox(height: 10),
              pw.Text(
                "BARANGAY BUSINESS CLEARANCE",
                style: pw.TextStyle(font: customFont, fontSize: 14, fontWeight: pw.FontWeight.bold),
                textAlign: pw.TextAlign.center,
              ),
              pw.SizedBox(height: 20),
              // "To Whom It May Concern" Section.
              pw.Align(
                alignment: pw.Alignment.centerLeft,
                child: pw.Text(
                  "TO WHOM IT MAY CONCERN:",
                  style: pw.TextStyle(font: customFont, fontSize: 12, fontWeight: pw.FontWeight.bold),
                  textAlign: pw.TextAlign.left,
                ),
              ),
              pw.SizedBox(height: 10),
              // Intro Paragraph.
              pw.Text(
                "This is to Certify that the Business or Trade Activity described below;",
                style: pw.TextStyle(font: customFont, fontSize: 12),
                textAlign: pw.TextAlign.justify,
              ),
              pw.SizedBox(height: 20),
              // Business Details with Parenthetical Labels.
              // Business Name.
              pw.Text(
                businessName.isNotEmpty ? businessName : "_________________________",
                style: pw.TextStyle(font: customFont, fontSize: 12, fontWeight: pw.FontWeight.bold),
                textAlign: pw.TextAlign.center,
              ),
              pw.Text(
                "(Business or Trade Activity)",
                style: pw.TextStyle(font: customFont, fontSize: 12),
                textAlign: pw.TextAlign.center,
              ),
              pw.SizedBox(height: 10),
              // Business Address.
              pw.Text(
                businessAddress.isNotEmpty ? businessAddress : "_________________________",
                style: pw.TextStyle(font: customFont, fontSize: 12),
                textAlign: pw.TextAlign.center,
              ),
              pw.Text(
                "(Address/Location)",
                style: pw.TextStyle(font: customFont, fontSize: 12),
                textAlign: pw.TextAlign.center,
              ),
              pw.SizedBox(height: 10),
              // Operator Name.
              pw.Text(
                operatorName.isNotEmpty ? operatorName : "_________________________",
                style: pw.TextStyle(font: customFont, fontSize: 12, fontWeight: pw.FontWeight.bold),
                textAlign: pw.TextAlign.center,
              ),
              pw.Text(
                "(Operator/Manager)",
                style: pw.TextStyle(font: customFont, fontSize: 12),
                textAlign: pw.TextAlign.center,
              ),
              pw.SizedBox(height: 10),
              // Operator Address.
              pw.Text(
                operatorAddress.isNotEmpty ? operatorAddress : "_________________________",
                style: pw.TextStyle(font: customFont, fontSize: 12),
                textAlign: pw.TextAlign.center,
              ),
              pw.Text(
                "(Address)",
                style: pw.TextStyle(font: customFont, fontSize: 12),
                textAlign: pw.TextAlign.center,
              ),
              pw.SizedBox(height: 20),
              // Additional Paragraph.
              pw.Text(
                "Proposed to be established in this barangay and this is to applied for new Barangay Clearance to be used in securing Mayor’s permit. It has been found to be in conformity with the provisions of existing Ordinances, rules and regulations being enforced in this barangay.",
                style: pw.TextStyle(font: customFont, fontSize: 12),
                textAlign: pw.TextAlign.justify,
              ),
              pw.SizedBox(height: 20),
              // Issued Date using RichText for superscript effect.
              pw.RichText(
                textAlign: pw.TextAlign.center,
                text: pw.TextSpan(
                  style: pw.TextStyle(font: customFont, fontSize: 12),
                  children: [
                    pw.TextSpan(text: "Issued this "),
                    pw.TextSpan(text: "${now.day}", style: pw.TextStyle(font: customFont, fontSize: 12)),
                    pw.TextSpan(text: getSuffix(now.day), style: pw.TextStyle(font: customFont, fontSize: 8)),
                    pw.TextSpan(text: " day of $issuedMonth, $issuedYear"),
                  ],
                ),
              ),
              pw.SizedBox(height: 40),
              // Signature Section.
              pw.Align(
                alignment: pw.Alignment.centerRight,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text("Certified by:", style: pw.TextStyle(font: customFont, fontSize: 12)),
                    pw.SizedBox(height: 20),
                    pw.Text(
                      "ELY C. ABIS",
                      style: pw.TextStyle(font: customFont, fontSize: 12, fontWeight: pw.FontWeight.bold),
                    ),
                    pw.Text("Punong Barangay", style: pw.TextStyle(font: customFont, fontSize: 12)),
                    pw.SizedBox(height: 20),
                    pw.Text(
                      "BOBBY C. ALVEZ",
                      style: pw.TextStyle(font: customFont, fontSize: 12, fontWeight: pw.FontWeight.bold),
                    ),
                    pw.Text("Barangay Kagawad", style: pw.TextStyle(font: customFont, fontSize: 12)),
                  ],
                ),
              ),
              pw.SizedBox(height: 40),
              // Administrative Details.
              pw.Align(
                alignment: pw.Alignment.centerLeft,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text("OR No.: _____________", style: pw.TextStyle(font: customFont, fontSize: 12)),
                    pw.Text("Issued at: Bgy. Pularaquen", style: pw.TextStyle(font: customFont, fontSize: 12)),
                    pw.Text("Issued on: $issuedOn", style: pw.TextStyle(font: customFont, fontSize: 12)),
                    pw.Text(
                      "Amount Paid: ₱${_amountPaidController.text}",
                      style: pw.TextStyle(font: customFont, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );

    await printPdfDocument(pdf);
  }

  @override
  Widget build(BuildContext context) {
    // Format current date values.
    final DateTime now = DateTime.now();
    final String issuedMonth = DateFormat('MMMM').format(now);
    final String issuedYear = DateFormat('yyyy').format(now);
    final String issuedOn = DateFormat('dd-MM-yyyy').format(now);

    final TextStyle baseStyle = TextStyle(
      fontFamily: 'TimesNewRoman',
      fontSize: 12,
      color: Colors.black,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text("Barangay Business Clearance", style: baseStyle),
        actions: [
          IconButton(
            icon: Icon(Icons.print),
            tooltip: "Print Document",
            onPressed: _printDocument,
          ),
          IconButton(
            icon: Icon(_isEditing ? Icons.save : Icons.edit),
            tooltip: _isEditing ? "Save Changes" : "Edit Document",
            onPressed: _toggleEdit,
          ),
        ],
      ),
      backgroundColor: Colors.grey[300],
      body: Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(20),
          child: Container(
            width: 600, // Simulate bond paper width for UI preview.
            padding: EdgeInsets.symmetric(vertical: 40, horizontal: 40),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: Colors.black, width: 1),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // UI Layout (on-screen display).
                Stack(
                  children: [
                    SizedBox(
                      height: 120,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Image.asset('assets/taytay_logo.png', width: 80, height: 80),
                          Image.asset('assets/pularaquen_logo.png', width: 80, height: 80),
                        ],
                      ),
                    ),
                    Positioned(
                      top: 20,
                      left: 0,
                      right: 0,
                      child: Column(
                        children: [
                          Text("Republic of the Philippines", style: baseStyle, textAlign: TextAlign.center),
                          Text("Province of Palawan", style: baseStyle, textAlign: TextAlign.center),
                          Text("Municipality of Taytay", style: baseStyle, textAlign: TextAlign.center),
                          Text("Barangay Pularaquen", style: baseStyle, textAlign: TextAlign.center),
                        ],
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 20),
                Text(
                  "OFFICE OF THE PUNONG BARANGAY",
                  style: baseStyle.copyWith(fontWeight: FontWeight.bold, fontSize: 14),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 10),
                Text(
                  "BARANGAY BUSINESS CLEARANCE",
                  style: baseStyle.copyWith(fontWeight: FontWeight.bold, fontSize: 14),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 20),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    "TO WHOM IT MAY CONCERN:",
                    style: baseStyle.copyWith(fontWeight: FontWeight.bold),
                    textAlign: TextAlign.left,
                  ),
                ),
                SizedBox(height: 10),
                Text(
                  "This is to Certify that the Business or Trade Activity described below;",
                  style: baseStyle,
                  textAlign: TextAlign.justify,
                ),
                SizedBox(height: 20),
                // Business Details.
                Text(
                  businessName.isNotEmpty ? businessName : "_________________________",
                  style: baseStyle.copyWith(fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                Text(
                  "(Business or Trade Activity)",
                  style: baseStyle,
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 10),
                Text(
                  businessAddress.isNotEmpty ? businessAddress : "_________________________",
                  style: baseStyle,
                  textAlign: TextAlign.center,
                ),
                Text(
                  "(Address/Location)",
                  style: baseStyle,
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 10),
                Text(
                  operatorName.isNotEmpty ? operatorName : "_________________________",
                  style: baseStyle.copyWith(fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                Text(
                  "(Operator/Manager)",
                  style: baseStyle,
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 10),
                Text(
                  operatorAddress.isNotEmpty ? operatorAddress : "_________________________",
                  style: baseStyle,
                  textAlign: TextAlign.center,
                ),
                Text(
                  "(Address)",
                  style: baseStyle,
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 20),
                Text(
                  "Proposed to be established in this barangay and this is to applied for new Barangay Clearance to be used in securing Mayor’s permit has been found to be in conformity with the provision of existing Ordinances, rules and regulations being enforced in this barangay.",
                  style: baseStyle,
                  textAlign: TextAlign.justify,
                ),
                SizedBox(height: 20),
                // Issued Date using RichText to display superscript for the day suffix.
                SizedBox(
                  width: double.infinity,
                  child: RichText(
                    textAlign: TextAlign.center,
                    text: TextSpan(
                      style: baseStyle,
                      children: [
                        TextSpan(text: "Issued this "),
                        ...getDayTextSpans(now.day, baseStyle),
                        TextSpan(text: " day of $issuedMonth, $issuedYear"),
                      ],
                    ),
                  ),
                ),
                SizedBox(height: 40),
                Align(
                  alignment: Alignment.centerRight,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text("Certified by:", style: baseStyle),
                      SizedBox(height: 20),
                      Text("ELY C. ABIS", style: baseStyle.copyWith(fontWeight: FontWeight.bold)),
                      Text("Punong Barangay", style: baseStyle),
                      SizedBox(height: 20),
                      Text("BOBBY C. ALVEZ", style: baseStyle.copyWith(fontWeight: FontWeight.bold)),
                      Text("Barangay Kagawad", style: baseStyle),
                    ],
                  ),
                ),
                SizedBox(height: 40),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("OR No.: _____________", style: baseStyle),
                      Text("Issued at: Bgy. Pularaquen", style: baseStyle),
                      Text("Issued on: $issuedOn", style: baseStyle),
                      _isEditing
                          ? TextFormField(
                              controller: _amountPaidController,
                              decoration: InputDecoration(
                                labelText: "Amount Paid",
                                prefixText: "₱",
                              ),
                              style: baseStyle,
                              keyboardType: TextInputType.numberWithOptions(decimal: true),
                            )
                          : Text(
                              "Amount Paid: ₱${_amountPaidController.text}",
                              style: baseStyle,
                            ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
