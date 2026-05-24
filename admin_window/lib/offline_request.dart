class OfflineRequest {
  final String id;
  final String fullName;
  final String title;
  final String documentType;
  
  // Business Fields
  final String businessName;
  final String businessAddress;
  final String operatorName;
  final String operatorAddress;
  
  final double amountPaid;
  final DateTime createdAt;
  bool synced;

  // Birth Certificate Fields
  final String? birthDate;
  final String? placeOfBirth;
  final String? fatherName;
  final String? motherName;
  final String? controlNumber;

  // Cohabitation Fields
  final String? partnerName;
  final String? partnerBirthDate;
  final String? cohabitationStartDate;

  // Seaweeds Fields
  final String? buyerName;
  final String? quantity;
  final String? amountWords;
  final String? amountFigures;
  
  final String status; 

  OfflineRequest({
    required this.id,
    required this.fullName,
    required this.title,
    required this.documentType,
    required this.businessName,
    required this.businessAddress,
    required this.operatorName,
    required this.operatorAddress,
    required this.amountPaid,
    required this.createdAt,
    this.synced = false,
    
    // UPDATED DEFAULT HERE:
    this.status = 'Released', 

    // Optional params
    this.birthDate,
    this.placeOfBirth,
    this.fatherName,
    this.motherName,
    this.controlNumber,
    
    // New params
    this.partnerName,
    this.partnerBirthDate,
    this.cohabitationStartDate,
    this.buyerName,
    this.quantity,
    this.amountWords,
    this.amountFigures,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'fullName': fullName,
    'title': title,
    'documentType': documentType,
    'status': status,
    'businessName': businessName,
    'businessAddress': businessAddress,
    'operatorName': operatorName,
    'operatorAddress': operatorAddress,
    'amountPaid': amountPaid,
    'createdAt': createdAt.toIso8601String(),
    'synced': synced,
    
    'birthDate': birthDate,
    'placeOfBirth': placeOfBirth,
    'fatherName': fatherName,
    'motherName': motherName,
    'controlNumber': controlNumber,

    'partnerName': partnerName,
    'partnerBirthDate': partnerBirthDate,
    'cohabitationStartDate': cohabitationStartDate,
    'buyerName': buyerName,
    'quantity': quantity,
    'amountWords': amountWords,
    'amountFigures': amountFigures,
  };

  factory OfflineRequest.fromMap(Map<String, dynamic> map) => OfflineRequest(
    id: map['id'],
    fullName: map['fullName'],
    title: map['title'],
    documentType: map['documentType'],
    
    // UPDATED FALLBACK HERE:
    // If we load old data that says "Successful", we keep it. 
    // If data is missing status, we assume "Released".
    status: map['status'] ?? 'Released', 
    
    businessName: map['businessName'] ?? '',
    businessAddress: map['businessAddress'] ?? '',
    operatorName: map['operatorName'] ?? '',
    operatorAddress: map['operatorAddress'] ?? '',
    amountPaid: (map['amountPaid'] as num?)?.toDouble() ?? 0.0,
    createdAt: DateTime.parse(map['createdAt']),
    synced: map['synced'] ?? false,
    
    birthDate: map['birthDate'],
    placeOfBirth: map['placeOfBirth'],
    fatherName: map['fatherName'],
    motherName: map['motherName'],
    controlNumber: map['controlNumber'],

    partnerName: map['partnerName'],
    partnerBirthDate: map['partnerBirthDate'],
    cohabitationStartDate: map['cohabitationStartDate'],
    buyerName: map['buyerName'],
    quantity: map['quantity'],
    amountWords: map['amountWords'],
    amountFigures: map['amountFigures'],
  );
}