import 'dart:io';
import 'package:flutter/material.dart';

enum VerificationStatus {
  loading,
  notSubmitted,
  pending,
  approved,
  rejected,
}

class VerificationData {
  final String? idType;
  final Map<String, TextEditingController> fieldControllers;
  final File? idImageFile;
  final File? selfieImageFile;
  final List<File> supportingDocs;

  VerificationData({
    required this.idType,
    required this.fieldControllers,
    required this.idImageFile,
    required this.selfieImageFile,
    this.supportingDocs = const [],
  });
}