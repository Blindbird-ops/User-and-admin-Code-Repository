import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

/// Prints the provided PDF document.
Future<void> printPdfDocument(pw.Document document) async {
  await Printing.layoutPdf(
    onLayout: (PdfPageFormat format) async => document.save(),
  );
}
