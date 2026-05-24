import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// --- 1. ICON LOGIC ---
Widget getDocumentIcon(String documentType, {double size = 48, Color? color}) {
  String? assetPath;
  switch (documentType) {
    case 'Barangay Business Clearance':
      assetPath = 'assets/icons/business_clearance.png';
      break;
    case 'Barangay Indigent':
      assetPath = 'assets/icons/barangay_indigent.png';
      break;
    case 'Certification (Late) Registration':
      assetPath = 'assets/icons/certification_late_registration.png';
      break;
    case 'Barangay Clearance':
      assetPath = 'assets/icons/clearance.png';
      break;
    case 'Barangay Certification':
      assetPath = 'assets/icons/certification.png';
      break;
    case 'Certificate of Cohabitation':
      assetPath = 'assets/icons/cohabitation.png';
      break;
    case 'Certificate of Seaweeds':
      assetPath = 'assets/icons/seaweeds.png';
      break;
  }

  if (assetPath != null) {
    return Image.asset(
      assetPath,
      width: size,
      height: size,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stack) =>
          Icon(Icons.description, size: size, color: color ?? Colors.deepPurple),
    );
  }
  return Icon(Icons.description, size: size, color: color ?? Colors.deepPurple);
}

// --- 2. TEXT FORMATTER ---
class TitleCaseTextFormatter extends TextInputFormatter {
  String _applyTitleCase(String input) {
    if (input.isEmpty) return input;
    final buffer = StringBuffer();
    bool capitalizeNext = true;

    for (var i = 0; i < input.length; i++) {
      final char = input[i];
      final isLetter = RegExp(r'[A-Za-z]').hasMatch(char);
      if (isLetter) {
        buffer.write(capitalizeNext ? char.toUpperCase() : char.toLowerCase());
        capitalizeNext = false;
      } else {
        buffer.write(char);
        capitalizeNext = (char == ' ' || char == '-' || char == '\'' || char == '/' || char == '\t' || char == '.');
      }
    }
    return buffer.toString();
  }

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final cased = _applyTitleCase(newValue.text);
    return TextEditingValue(
      text: cased,
      selection: newValue.selection,
      composing: TextRange.empty,
    );
  }
}

// --- 3. CURRENCY CONVERTER ---
String convertToCurrencyWords(double amount) {
  if (amount == 0) return "Zero Pesos Only";
  
  final units = ["", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine"];
  final teens = ["Ten", "Eleven", "Twelve", "Thirteen", "Fourteen", "Fifteen", "Sixteen", "Seventeen", "Eighteen", "Nineteen"];
  final tens = ["", "", "Twenty", "Thirty", "Forty", "Fifty", "Sixty", "Seventy", "Eighty", "Ninety"];
  
  String numToWords(int n) {
    if (n < 10) return units[n];
    if (n < 20) return teens[n - 10];
    if (n < 100) return "${tens[n ~/ 10]} ${units[n % 10]}".trim();
    if (n < 1000) return "${units[n ~/ 100]} Hundred ${numToWords(n % 100)}".trim();
    if (n < 1000000) return "${numToWords(n ~/ 1000)} Thousand ${numToWords(n % 1000)}".trim();
    return "$n"; 
  }

  int whole = amount.floor();
  int cents = ((amount - whole) * 100).round();
  
  String words = numToWords(whole) + " Pesos";
  if (cents > 0) {
    words += " and $cents/100";
  }
  
  return "$words Only";
}