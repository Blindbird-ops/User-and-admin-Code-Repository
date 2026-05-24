import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;

// --- Model Classes ---

class Province {
  final String code;
  final String name;

  Province({required this.code, required this.name});

  factory Province.fromJson(Map<String, dynamic> json) {
    return Province(
      code: json['code']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
    );
  }
}

class Municipality {
  final String code;
  final String name;
  final String provinceCode;

  Municipality({required this.code, required this.name, required this.provinceCode});

  factory Municipality.fromJson(Map<String, dynamic> json) {
    return Municipality(
      code: json['code']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      provinceCode: json['provinceCode']?.toString() ?? '',
    );
  }
}

class Barangay {
  final String code;
  final String name;
  final String parentCode; 

  Barangay({required this.code, required this.name, required this.parentCode});

  factory Barangay.fromJson(Map<String, dynamic> json) {
    // --- THIS IS THE FIX ---
    // The GitLab API uses 'municipalityCode' for municipalities and 'cityCode' for cities.
    // We check 'municipalityCode' first. If it's false/null, we check 'cityCode'.
    // If both are missing, we default to empty.
    String pCode = '';
    
    if (json['municipalityCode'] != null && json['municipalityCode'] != false) {
      pCode = json['municipalityCode'].toString();
    } else if (json['cityCode'] != null && json['cityCode'] != false) {
      pCode = json['cityCode'].toString();
    }

    return Barangay(
      code: json['code']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      parentCode: pCode,
    );
  }
}

// --- Local Data Service ---

class PsgcApiService {
  List<Province>? _cachedProvinces;
  List<Municipality>? _cachedMunicipalities;
  List<Barangay>? _cachedBarangays;

  // 1. Fetch Provinces
  Future<List<Province>> fetchProvinces() async {
    if (_cachedProvinces != null) return _cachedProvinces!;

    try {
      final String response = await rootBundle.loadString('assets/json/provinces.json');
      final List<dynamic> data = json.decode(response);
      
      _cachedProvinces = data.map((json) => Province.fromJson(json)).toList();
      _cachedProvinces!.sort((a, b) => a.name.compareTo(b.name));
      
      return _cachedProvinces!;
    } catch (e) {
      print("Error loading provinces: $e");
      return [];
    }
  }

  // 2. Fetch Municipalities
  Future<List<Municipality>> fetchMunicipalities(String provinceCode) async {
    if (_cachedMunicipalities == null) {
      try {
        final String response = await rootBundle.loadString('assets/json/municipalities.json');
        final List<dynamic> data = json.decode(response);
        _cachedMunicipalities = data.map((json) => Municipality.fromJson(json)).toList();
      } catch (e) {
        print("Error loading municipalities: $e");
        return [];
      }
    }

    List<Municipality> filtered = _cachedMunicipalities!
        .where((m) => m.provinceCode == provinceCode)
        .toList();
    
    filtered.sort((a, b) => a.name.compareTo(b.name));
    return filtered;
  }

  // 3. Fetch Barangays
  Future<List<Barangay>> fetchBarangays(String municipalityCode) async {
    if (_cachedBarangays == null) {
      try {
        final String response = await rootBundle.loadString('assets/json/barangays.json');
        final List<dynamic> data = json.decode(response);
        _cachedBarangays = data.map((json) => Barangay.fromJson(json)).toList();
      } catch (e) {
        print("Error loading barangays: $e");
        return [];
      }
    }

    // Filter by parentCode
    List<Barangay> filtered = _cachedBarangays!
        .where((b) => b.parentCode == municipalityCode)
        .toList();

    filtered.sort((a, b) => a.name.compareTo(b.name));
    return filtered;
  }
}