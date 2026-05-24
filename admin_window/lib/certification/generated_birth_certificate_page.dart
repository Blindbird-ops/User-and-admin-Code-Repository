import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/widgets.dart' as pw;
import 'print_helper.dart';

class GeneratedBirthCertificatePage extends StatefulWidget {
  final String initialFullName;
  final String initialBirthDate; // e.g. "APRIL 21, 2020"
  final String initialPlaceOfBirth; // e.g. "SITIO NEW SITE, BARANGAY PULARAQUEN, TAYTAY, PALAWAN"
  final String initialFatherName;
  final String initialMotherName;
  final String initialControlNumber; // Filled in by admin

  const GeneratedBirthCertificatePage({
    super.key,
    required this.initialFullName,
    required this.initialBirthDate,
    required this.initialPlaceOfBirth,
    required this.initialFatherName,
    required this.initialMotherName,
    required this.initialControlNumber,
  });

  @override
  _GeneratedBirthCertificatePageState createState() =>
      _GeneratedBirthCertificatePageState();
}

class _GeneratedBirthCertificatePageState
    extends State<GeneratedBirthCertificatePage> {
  bool _isEditing = false;
  late String fullName;
  late String birthDate;
  late String placeOfBirth;
  late String fatherName;
  late String motherName;
  late String controlNumber;

  late TextEditingController _fullNameController;
  late TextEditingController _birthDateController;
  late TextEditingController _placeOfBirthController;
  late TextEditingController _fatherNameController;
  late TextEditingController _motherNameController;
  late TextEditingController _controlNumberController;

  @override
  void initState() {
    super.initState();
    fullName = widget.initialFullName;
    birthDate = widget.initialBirthDate;
    placeOfBirth = widget.initialPlaceOfBirth;
    fatherName = widget.initialFatherName;
    motherName = widget.initialMotherName;
    controlNumber = widget.initialControlNumber;

    _fullNameController = TextEditingController(text: fullName);
    _birthDateController = TextEditingController(text: birthDate);
    _placeOfBirthController = TextEditingController(text: placeOfBirth);
    _fatherNameController = TextEditingController(text: fatherName);
    _motherNameController = TextEditingController(text: motherName);
    _controlNumberController = TextEditingController(text: controlNumber);
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _birthDateController.dispose();
    _placeOfBirthController.dispose();
    _fatherNameController.dispose();
    _motherNameController.dispose();
    _controlNumberController.dispose();
    super.dispose();
  }

  void _toggleEdit() {
    setState(() {
      if (_isEditing) {
        fullName = _fullNameController.text;
        birthDate = _birthDateController.text;
        placeOfBirth = _placeOfBirthController.text;
        fatherName = _fatherNameController.text;
        motherName = _motherNameController.text;
        controlNumber = _controlNumberController.text;
      }
      _isEditing = !_isEditing;
    });
  }

  /// UI Helper: Returns inline spans for day number and its ordinal suffix.
  /// (Superscript effect is simulated by reducing the font size of the suffix.)
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
        child: Text(
          suffix,
          style: baseStyle.copyWith(
            fontSize: baseStyle.fontSize! * 0.7,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    ];
  }

  /// PDF Helper: Returns the ordinal suffix as a string.
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

    // Use current date for issuance.
    final DateTime now = DateTime.now();
    final String issuanceDay = DateFormat('d').format(now);
    final String issuanceMonth = DateFormat('MMMM').format(now);
    final String issuanceYear = DateFormat('yyyy').format(now);

    final pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        margin: pw.EdgeInsets.all(40),
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              // Header: Logos and Location details.
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
              // Office Heading.
              pw.Text("OFFICE OF THE PUNONG BARANGAY",
                  style: pw.TextStyle(
                      font: customFont, fontSize: 14, fontWeight: pw.FontWeight.bold),
                  textAlign: pw.TextAlign.center),
              pw.SizedBox(height: 10),
              // Control Number inline.
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.center,
                children: [
                  pw.Text("Control No.: ",
                      style: pw.TextStyle(font: customFont, fontSize: 12)),
                  pw.Container(
                    width: 50,
                    alignment: pw.Alignment.center,
                    child: pw.Text(controlNumber,
                        style: pw.TextStyle(font: customFont, fontSize: 12)),
                  ),
                ],
              ),
              pw.SizedBox(height: 20),
              pw.Text("C E R T I F I C A T I O N",
                  style: pw.TextStyle(
                      font: customFont, fontSize: 14, fontWeight: pw.FontWeight.bold),
                  textAlign: pw.TextAlign.center),
              pw.SizedBox(height: 25),
              // TO WHOM IT MAY CONCERN:
              pw.Align(
                alignment: pw.Alignment.centerLeft,
                child: pw.Text("TO WHOM IT MAY CONCERN:",
                    style: pw.TextStyle(
                        font: customFont, fontSize: 12, fontWeight: pw.FontWeight.bold),
                    textAlign: pw.TextAlign.left),
              ),
              pw.SizedBox(height: 20),
              // Main Body Text.
              pw.RichText(
                textAlign: pw.TextAlign.justify,
                text: pw.TextSpan(
                  style: pw.TextStyle(font: customFont, fontSize: 12),
                  children: [
                    pw.TextSpan(text: "     THIS IS TO CERTIFY that "),
                    pw.TextSpan(
                      text: fullName.toUpperCase(),
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                    ),
                    pw.TextSpan(text: ", Filipino citizen, "),
                    // Literal "single/married" inserted in a smaller font.
                    pw.TextSpan(
                      text: "single/married",
                      style: pw.TextStyle(font: customFont, fontSize: 8),
                    ),
                    pw.TextSpan(text: " who was born on "),
                    pw.TextSpan(
                      text: birthDate.toUpperCase(),
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                    ),
                    pw.TextSpan(text: " at "),
                    pw.TextSpan(
                      text: placeOfBirth.toUpperCase(),
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                    ),
                    pw.TextSpan(text: ", child/ward of "),
                    pw.TextSpan(
                      text: "MR. ",
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                    ),
                    pw.TextSpan(
                      text: fatherName.toUpperCase(),
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                    ),
                    pw.TextSpan(text: " and "),
                    pw.TextSpan(
                      text: "MS. ",
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                    ),
                    pw.TextSpan(
                      text: motherName.toUpperCase(),
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                    ),
                    pw.TextSpan(
                        text:
                            ", is a bona fide resident of Barangay Pularaquen, Taytay, Palawan.\n\n"),
                    pw.TextSpan(
                        text:
                            "     This certification is issued upon the request of the interested party for the purpose of LATE REGISTRATION of his/her BIRTH CERTIFICATE.\n\n"),
                  ],
                ),
              ),
              pw.SizedBox(height: 20),
              // Issuance Date using RichText.
              pw.RichText(
                textAlign: pw.TextAlign.center,
                text: pw.TextSpan(
                  style: pw.TextStyle(font: customFont, fontSize: 12),
                  children: [
                    pw.TextSpan(text: "Done this "),
                    pw.TextSpan(
                        text: "${int.parse(issuanceDay)}",
                        style: pw.TextStyle(font: customFont, fontSize: 12)),
                    pw.TextSpan(
                        text: getSuffix(int.parse(issuanceDay)),
                        style: pw.TextStyle(
                          font: customFont,
                          fontSize: 8,
                          fontWeight: pw.FontWeight.bold,
                        )),
                    pw.TextSpan(
                        text:
                            " day of $issuanceMonth, $issuanceYear at Barangay Pularaquen, Taytay, Palawan.",
                        style: pw.TextStyle(font: customFont, fontSize: 12)),
                  ],
                ),
              ),
              pw.SizedBox(height: 40),
              // Signature Sections.
              pw.Align(
                alignment: pw.Alignment.centerRight,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text("Certified by:",
                        style: pw.TextStyle(font: customFont, fontSize: 12)),
                    pw.SizedBox(height: 20),
                    pw.Text("ELY C. ABIS",
                        style: pw.TextStyle(
                            font: customFont,
                            fontSize: 12,
                            fontWeight: pw.FontWeight.bold),
                        textAlign: pw.TextAlign.right),
                    pw.Text("Punong Barangay",
                        style: pw.TextStyle(font: customFont, fontSize: 12),
                        textAlign: pw.TextAlign.right),
                    pw.SizedBox(height: 30),
                    pw.Text("Verified By:",
                        style: pw.TextStyle(font: customFont, fontSize: 12)),
                    pw.SizedBox(height: 20),
                    pw.Text("AIAN L. CATANDUANES",
                        style: pw.TextStyle(
                            font: customFont,
                            fontSize: 12,
                            fontWeight: pw.FontWeight.bold)),
                    pw.Text("BGY. SECRETARY",
                        style: pw.TextStyle(font: customFont, fontSize: 12)),
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
    final String day = DateFormat('d').format(now);
    final String month = DateFormat('MMMM').format(now);
    final String year = DateFormat('yyyy').format(now);

    final TextStyle baseStyle = TextStyle(
      fontFamily: 'TimesNewRoman',
      fontSize: 12,
      color: Colors.black,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text("Birth Certificate", style: baseStyle),
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
            width: 600, // Simulate bond paper width.
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
                const SizedBox(height: 10),
                // Control Number with underline.
                Row(
                  children: [
                    Text("Control No.: ", style: baseStyle),
                    Container(
                      width: 50,
                      padding: EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: Colors.black, width: 1),
                        ),
                      ),
                      child: TextFormField(
                        controller: _controlNumberController,
                        decoration: InputDecoration(
                          isDense: true,
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(vertical: 2),
                        ),
                        style: baseStyle,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  "CERTIFICATION",
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
                // Main certificate text.
                Text.rich(
                  TextSpan(
                    children: [
                      const WidgetSpan(child: SizedBox(width: 40)),
                      TextSpan(text: "THIS IS TO CERTIFY that ", style: baseStyle),
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
                              text: fullName.toUpperCase(),
                              style: baseStyle.copyWith(fontWeight: FontWeight.bold),
                            ),
                      TextSpan(text: ", Filipino citizen, ", style: baseStyle),
                      // Literal "single/married" in a smaller font.
                      TextSpan(
                        text: "single/married",
                        style: baseStyle.copyWith(fontSize: baseStyle.fontSize! - 2),
                      ),
                      TextSpan(text: " who was born on ", style: baseStyle),
                      _isEditing
                          ? WidgetSpan(
                              child: SizedBox(
                                width: 120,
                                child: TextFormField(
                                  controller: _birthDateController,
                                  style: baseStyle,
                                  decoration: InputDecoration(labelText: "Birth Date", isDense: true),
                                ),
                              ),
                            )
                          : TextSpan(
                              text: birthDate.toUpperCase(),
                              style: baseStyle.copyWith(fontWeight: FontWeight.bold),
                            ),
                      TextSpan(text: " at ", style: baseStyle),
                      _isEditing
                          ? WidgetSpan(
                              child: SizedBox(
                                width: 220,
                                child: TextFormField(
                                  controller: _placeOfBirthController,
                                  style: baseStyle,
                                  decoration: InputDecoration(labelText: "Place of Birth", isDense: true),
                                ),
                              ),
                            )
                          : TextSpan(
                              text: placeOfBirth.toUpperCase(),
                              style: baseStyle.copyWith(fontWeight: FontWeight.bold),
                            ),
                      TextSpan(text: ", child/ward of ", style: baseStyle),
                      // Bold the parent's title "MR. "
                      TextSpan(
                        text: "MR. ",
                        style: baseStyle.copyWith(fontWeight: FontWeight.bold),
                      ),
                      _isEditing
                          ? WidgetSpan(
                              child: SizedBox(
                                width: 150,
                                child: TextFormField(
                                  controller: _fatherNameController,
                                  style: baseStyle,
                                  decoration: InputDecoration(labelText: "Father's Name", isDense: true),
                                ),
                              ),
                            )
                          : TextSpan(
                              text: fatherName.toUpperCase(),
                              style: baseStyle.copyWith(fontWeight: FontWeight.bold),
                            ),
                      TextSpan(text: " and ", style: baseStyle),
                      // Bold the parent's title "MS. "
                      TextSpan(
                        text: "MS. ",
                        style: baseStyle.copyWith(fontWeight: FontWeight.bold),
                      ),
                      _isEditing
                          ? WidgetSpan(
                              child: SizedBox(
                                width: 150,
                                child: TextFormField(
                                  controller: _motherNameController,
                                  style: baseStyle,
                                  decoration: InputDecoration(labelText: "Mother's Name", isDense: true),
                                ),
                              ),
                            )
                          : TextSpan(
                              text: motherName.toUpperCase(),
                              style: baseStyle.copyWith(fontWeight: FontWeight.bold),
                            ),
                      TextSpan(
                        text: " is a bona fide resident of Barangay Pularaquen, Taytay, Palawan.\n\n"
                              "This certification is issued upon the request of the interested party for the purpose of LATE REGISTRATION of his/her BIRTH CERTIFICATE.",
                        style: baseStyle,
                      ),
                    ],
                  ),
                  textAlign: TextAlign.justify,
                ),
                const SizedBox(height: 20),
                // Issuance Date using RichText.
                SizedBox(
                  width: double.infinity,
                  child: RichText(
                    textAlign: TextAlign.center,
                    text: TextSpan(
                      style: baseStyle,
                      children: [
                        TextSpan(text: "Done this "),
                        ...getDayTextSpans(int.parse(day), baseStyle),
                        TextSpan(text: " day of $month, $year at Barangay Pularaquen, Taytay, Palawan."),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 40),
                // Signature Sections.
                Align(
                  alignment: Alignment.centerRight,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text("Certified by:", style: baseStyle, textAlign: TextAlign.right),
                      const SizedBox(height: 20),
                      Text("ELY C. ABIS", style: baseStyle.copyWith(fontWeight: FontWeight.bold), textAlign: TextAlign.right),
                      Text("Punong Barangay", style: baseStyle, textAlign: TextAlign.right),
                      const SizedBox(height: 30),
                      Text("Verified By:", style: baseStyle, textAlign: TextAlign.left),
                      const SizedBox(height: 20),
                      Text("AIAN L. CATANDUANES", style: baseStyle.copyWith(fontWeight: FontWeight.bold), textAlign: TextAlign.left),
                      Text("BGY. SECRETARY", style: baseStyle, textAlign: TextAlign.left),
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
