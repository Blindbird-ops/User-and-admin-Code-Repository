import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/widgets.dart' as pw;
import 'print_helper.dart';

class GeneratedBarangayIndigentPage extends StatefulWidget {
  final String initialFullName;

  const GeneratedBarangayIndigentPage({super.key, required this.initialFullName});

  @override
  _GeneratedBarangayIndigentPageState createState() =>
      _GeneratedBarangayIndigentPageState();
}

class _GeneratedBarangayIndigentPageState extends State<GeneratedBarangayIndigentPage> {
  bool _isEditing = false;
  late String fullName;
  late TextEditingController _fullNameController;

  @override
  void initState() {
    super.initState();
    fullName = widget.initialFullName;
    _fullNameController = TextEditingController(text: fullName);
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    super.dispose();
  }

  void _toggleEdit() {
    setState(() {
      if (_isEditing) {
        fullName = _fullNameController.text;
      }
      _isEditing = !_isEditing;
    });
  }

  /// UI Helper: Returns a list of inline spans where the day number is in the base style
  /// and the ordinal suffix is rendered in a smaller font and raised.
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
          offset: Offset(0, -5), // Adjust vertical offset as needed
          child: Text(
            suffix,
            style: baseStyle.copyWith(fontSize: baseStyle.fontSize! * 0.7),
          ),
        ),
      ),
    ];
  }

  /// PDF Helper: Returns just the ordinal suffix as a string.
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
    // Load asset images.
    final logo1Data = await rootBundle.load('assets/taytay_logo.png');
    final logo2Data = await rootBundle.load('assets/pularaquen_logo.png');
    final logo1 = pw.MemoryImage(logo1Data.buffer.asUint8List());
    final logo2 = pw.MemoryImage(logo2Data.buffer.asUint8List());

    // Load custom Times New Roman font.
    final fontData = await rootBundle.load('assets/times.ttf');
    final customFont = pw.Font.ttf(fontData.buffer.asByteData());

    // Format current date.
    final DateTime now = DateTime.now();
    final String month = DateFormat('MMMM').format(now);
    final String year = DateFormat('yyyy').format(now);

    final pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        margin: const pw.EdgeInsets.all(40),
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              // Header: Logos and Location Details.
              pw.Stack(
                children: [
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Image(logo1, width: 110, height: 110),
                      pw.Image(logo2, width: 90, height: 90),
                    ],
                  ),
                  pw.Positioned(
                    top: 20,
                    left: 0,
                    right: 0,
                    child: pw.Column(
                      children: [
                        pw.Text("Republic of the Philippines",
                            style: pw.TextStyle(font: customFont, fontSize: 12),
                            textAlign: pw.TextAlign.center),
                        pw.Text("Province of Palawan",
                            style: pw.TextStyle(font: customFont, fontSize: 12),
                            textAlign: pw.TextAlign.center),
                        pw.Text("Municipality of Taytay",
                            style: pw.TextStyle(font: customFont, fontSize: 12),
                            textAlign: pw.TextAlign.center),
                        pw.Text("Barangay Pularaquen",
                            style: pw.TextStyle(font: customFont, fontSize: 12),
                            textAlign: pw.TextAlign.center),
                      ],
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 20),
              // Headings.
              pw.Text("OFFICE OF THE PUNONG BARANGAY",
                  style: pw.TextStyle(font: customFont, fontSize: 14, fontWeight: pw.FontWeight.bold),
                  textAlign: pw.TextAlign.center),
              pw.SizedBox(height: 20),
              pw.Text("CERTIFICATE OF INDIGENCY",
                  style: pw.TextStyle(font: customFont, fontSize: 14, fontWeight: pw.FontWeight.bold),
                  textAlign: pw.TextAlign.center),
              pw.SizedBox(height: 25),
              pw.Align(
                alignment: pw.Alignment.centerLeft,
                child: pw.Text("TO WHOM IT MAY CONCERN:",
                    style: pw.TextStyle(font: customFont, fontSize: 12, fontWeight: pw.FontWeight.bold),
                    textAlign: pw.TextAlign.left),
              ),
              pw.SizedBox(height: 20),
              // Main body text.
              pw.RichText(
                textAlign: pw.TextAlign.justify,
                text: pw.TextSpan(
                  style: pw.TextStyle(font: customFont, fontSize: 12),
                  children: [
                    pw.TextSpan(text: "     This is to Certify that "),
                    pw.TextSpan(
                      text: fullName,
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                    ),
                    pw.TextSpan(
                        text:
                            " Filipino citizen, and a bona fide resident of this Barangay, is personally known to me as an indigent person living in this barangay.\n\n"),
                    pw.TextSpan(
                        text: "CERTIFY FURTHER,",
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                    pw.TextSpan(
                        text:
                            " that he/she is not gainfully employed and has no business registered in his/her name.\n\n"),
                    pw.TextSpan(text: "This "),
                    pw.TextSpan(
                        text: "CERTIFICATION",
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                    pw.TextSpan(
                        text:
                            " is being issued upon request of the above-named person for whatever purpose it may serve him/her best."),
                  ],
                ),
              ),
              pw.SizedBox(height: 20),
              // Issued Date using pw.RichText with superscript effect.
              pw.RichText(
                textAlign: pw.TextAlign.justify,
                text: pw.TextSpan(
                  style: pw.TextStyle(font: customFont, fontSize: 12),
                  children: [
                    pw.TextSpan(text: "Issued this "),
                    pw.TextSpan(text: "${now.day}", style: pw.TextStyle(font: customFont, fontSize: 12)),
                    pw.TextSpan(text: getSuffix(now.day), style: pw.TextStyle(font: customFont, fontSize: 8)),
                    pw.TextSpan(text: " day of $month, $year at Barangay Pularaquen, Taytay, Palawan."),
                  ],
                ),
              ),
              pw.SizedBox(height: 40),
              // Signature section.
              pw.Align(
                alignment: pw.Alignment.centerRight,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Padding(
                      padding: pw.EdgeInsets.only(right: 69),
                      child: pw.Text("Certified by:",
                          style: pw.TextStyle(font: customFont, fontSize: 12),
                          textAlign: pw.TextAlign.right),
                    ),
                    pw.SizedBox(height: 30),
                    pw.Text("ELY C. ABIS",
                        style: pw.TextStyle(font: customFont, fontSize: 12, fontWeight: pw.FontWeight.bold),
                        textAlign: pw.TextAlign.right),
                    pw.Text("Punong Barangay",
                        style: pw.TextStyle(font: customFont, fontSize: 12),
                        textAlign: pw.TextAlign.right),
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
    final DateTime now = DateTime.now();
    final String month = DateFormat('MMMM').format(now);
    final String year = DateFormat('yyyy').format(now);

    final TextStyle baseStyle = TextStyle(
      fontFamily: 'TimesNewRoman',
      fontSize: 12,
      color: Colors.black,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text("Certificate of Indigency", style: baseStyle),
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
          padding: const EdgeInsets.all(20),
          child: Container(
            width: 600, // Simulated bond paper width.
            padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 40),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: Colors.black, width: 1),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Header: Logos and Location Details.
                Stack(
                  children: [
                    SizedBox(
                      height: 120,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Image.asset('assets/taytay_logo.png', width: 110, height: 110),
                          Image.asset('assets/pularaquen_logo.png', width: 90, height: 90),
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
                const SizedBox(height: 20),
                Text(
                  "OFFICE OF THE PUNONG BARANGAY",
                  style: baseStyle.copyWith(fontWeight: FontWeight.bold, fontSize: 14),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                Text(
                  "CERTIFICATE OF INDIGENCY",
                  style: baseStyle.copyWith(fontWeight: FontWeight.bold, fontSize: 14),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 25),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    "TO WHOM IT MAY CONCERN:",
                    style: baseStyle.copyWith(fontWeight: FontWeight.bold),
                    textAlign: TextAlign.left,
                  ),
                ),
                const SizedBox(height: 20),
                Text.rich(
                  TextSpan(
                    children: [
                      const WidgetSpan(child: SizedBox(width: 40)),
                      TextSpan(text: "This is to Certify that ", style: baseStyle),
                      _isEditing
                          ? WidgetSpan(
                              child: SizedBox(
                                width: 200,
                                child: TextFormField(
                                  controller: _fullNameController,
                                  style: baseStyle,
                                ),
                              ),
                            )
                          : TextSpan(
                              text: fullName,
                              style: baseStyle.copyWith(fontWeight: FontWeight.bold),
                            ),
                      TextSpan(
                        text:
                            " Filipino citizen, and a bona fide resident of this Barangay, is personally known to me as an indigent person living in this barangay.\n\n",
                        style: baseStyle,
                      ),
                      const WidgetSpan(child: SizedBox(width: 40)),
                      TextSpan(text: "CERTIFY FURTHER,", style: baseStyle.copyWith(fontWeight: FontWeight.bold)),
                      TextSpan(
                        text:
                            " that he/she is not gainfully employed and has no business registered in his/her name.\n\n",
                        style: baseStyle,
                      ),
                      const WidgetSpan(child: SizedBox(width: 40)),
                      TextSpan(text: "This ", style: baseStyle),
                      TextSpan(text: "CERTIFICATION", style: baseStyle.copyWith(fontWeight: FontWeight.bold)),
                      TextSpan(
                        text:
                            " is being issued upon request of the above-named person for whatever purpose it may serve him/her best.",
                        style: baseStyle,
                      ),
                    ],
                  ),
                  textAlign: TextAlign.justify,
                ),
                const SizedBox(height: 20),
                // Issued Date using RichText with superscript effect.
                SizedBox(
                  width: double.infinity,
                  child: RichText(
                    textAlign: TextAlign.justify,
                    text: TextSpan(
                      style: baseStyle,
                      children: [
                        TextSpan(text: "Issued this "),
                        ...getDayTextSpans(now.day, baseStyle),
                        TextSpan(text: " day of $month, $year at Barangay Pularaquen, Taytay, Palawan."),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 40),
                Align(
                  alignment: Alignment.centerRight,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(right: 69),
                        child: Text("Certified by:", style: baseStyle, textAlign: TextAlign.right),
                      ),
                      const SizedBox(height: 30),
                      Text("ELY C. ABIS", style: baseStyle.copyWith(fontWeight: FontWeight.bold), textAlign: TextAlign.right),
                      Text("Punong Barangay", style: baseStyle, textAlign: TextAlign.right),
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
