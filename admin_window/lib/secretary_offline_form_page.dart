import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:open_file/open_file.dart'; 
import 'package:intl/intl.dart';

import 'offline_request.dart';
import 'offline_request_service.dart';

class TitleCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    if (newValue.text.isEmpty) return newValue;
    return TextEditingValue(
      text: newValue.text.split(' ').map((word) => word.isNotEmpty 
          ? '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}' 
          : '').join(' '),
      selection: newValue.selection,
    );
  }
}

class SecretaryOfflineFormPage extends StatefulWidget {
  final String documentType;
  const SecretaryOfflineFormPage({super.key, required this.documentType});

  @override
  _SecretaryOfflineFormPageState createState() => _SecretaryOfflineFormPageState();
}

class _SecretaryOfflineFormPageState extends State<SecretaryOfflineFormPage> {
  final _formKey = GlobalKey<FormState>();
  bool _isSaving = false;

  // ================= CONTROLLERS =================
  
  // 1. Requestor Info
  final _titleController = TextEditingController();
  final _firstNameController = TextEditingController();
  final _middleNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  String? _selectedSuffix; 

  // 2. Business
  final _businessNameController = TextEditingController();
  final _businessAddressController = TextEditingController();
  final _operatorNameController = TextEditingController();
  final _operatorAddressController = TextEditingController();

  // 3. Late Reg
  final _birthDateController = TextEditingController();
  final _placeOfBirthController = TextEditingController();
  final _fatherNameController = TextEditingController();
  final _motherNameController = TextEditingController();
  final _controlNumberController = TextEditingController();

  // 4. Cohabitation
  final _requesterBirthDateController = TextEditingController(); // <--- ADDED THIS
  final _partnerNameController = TextEditingController();
  final _partnerDobController = TextEditingController();
  final _cohabStartDateController = TextEditingController();

  // 5. Seaweeds
  final _buyerNameController = TextEditingController();
  final _quantityController = TextEditingController();
  final _seaweedsAmountController = TextEditingController();
  String? _selectedSeaweedsUnit;

  // 6. STATUS & PAYMENT
  String _selectedStatus = "Released"; 
  final _amountPaidController = TextEditingController();

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
      if (n < 1000000000) return "${numToWords(n ~/ 1000000)} Million ${numToWords(n % 1000000)}".trim();
      return "$n"; 
    }

    int whole = amount.floor();
    int cents = ((amount - whole) * 100).round();
    String words = "${numToWords(whole)} Pesos";
    if (cents > 0) words += " and $cents/100";
    return "$words Only";
  }

  String get _combinedFullName {
    String name = "${_firstNameController.text.trim()} ";
    if (_middleNameController.text.isNotEmpty) {
      name += "${_middleNameController.text.trim()[0].toUpperCase()}. ";
    }
    name += _lastNameController.text.trim();
    if (_selectedSuffix != null && _selectedSuffix != "None") {
      name += " $_selectedSuffix";
    }
    return name.trim();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _firstNameController.dispose();
    _middleNameController.dispose();
    _lastNameController.dispose();
    _businessNameController.dispose();
    _businessAddressController.dispose();
    _operatorNameController.dispose();
    _operatorAddressController.dispose();
    _birthDateController.dispose();
    _placeOfBirthController.dispose();
    _fatherNameController.dispose();
    _motherNameController.dispose();
    _controlNumberController.dispose();
    _requesterBirthDateController.dispose(); // <--- Dispose

    _partnerNameController.dispose();
    _partnerDobController.dispose();
    _cohabStartDateController.dispose();
    _buyerNameController.dispose();
    _quantityController.dispose();
    _seaweedsAmountController.dispose();
    _amountPaidController.dispose();
    super.dispose();
  }

  Future<void> _selectDate(TextEditingController controller) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      controller.text = DateFormat('MMMM dd, yyyy').format(picked);
    }
  }

  // ================= 1. CONFIRMATION DIALOG =================
  // REPLACE THE ENTIRE _confirmAction FUNCTION
  Future<bool> _confirmAction() async {
    return await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Confirm Generation"),
        // EXPLANATION: We check if status is 'Released' to show the amount
        content: Text("You are about to generate a document for $_combinedFullName.\n\nStatus: $_selectedStatus\nAmount: ${_selectedStatus == 'Released' ? '₱${_amountPaidController.text}' : '₱0.00'}\n\nProceed?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Yes, Generate"),
          ),
        ],
      ),
    ) ?? false;
  }
  // ================= 2. SAVE LOGIC =================
  // REPLACE THE ENTIRE _saveRequest FUNCTION
  Future<void> _saveRequest() async {
    if (!_formKey.currentState!.validate()) return;

    // Show Confirmation Dialog
    if (!await _confirmAction()) return;

    setState(() => _isSaving = true);

    try {
      final String reqId = const Uuid().v4();
      
      // EXPLANATION: Check for "Released" instead of "Successful"
      double paymentAmount = 0.0;
      if (_selectedStatus == "Released") {
        paymentAmount = double.tryParse(_amountPaidController.text) ?? 0.0;
      }

      String fullQty = "";
      String amtWords = "";
      String amtFigures = "";
      
      if (widget.documentType.contains("Seaweeds")) {
        String qty = _quantityController.text.trim();
        String unit = _selectedSeaweedsUnit ?? "";
        if (double.tryParse(qty) == 1.0 && unit.endsWith('s')) {
          unit = unit.substring(0, unit.length - 1);
        }
        fullQty = "$qty $unit";
        
        double soldPrice = double.tryParse(_seaweedsAmountController.text.replaceAll(',', '')) ?? 0.0;
        amtFigures = NumberFormat("#,##0.00", "en_US").format(soldPrice);
        amtWords = convertToCurrencyWords(soldPrice); 
      }

      final request = OfflineRequest(
        id: reqId,
        fullName: _combinedFullName, 
        title: _titleController.text,
        documentType: widget.documentType,
        status: _selectedStatus, // <--- This now saves "Released"
        
        businessName: _businessNameController.text,
        businessAddress: _businessAddressController.text,
        operatorName: _operatorNameController.text,
        operatorAddress: _operatorAddressController.text,
        
        amountPaid: paymentAmount,
        createdAt: DateTime.now(),
        synced: false,
        
        birthDate: widget.documentType.contains('Cohabitation') 
            ? _requesterBirthDateController.text 
            : _birthDateController.text,         
        placeOfBirth: _placeOfBirthController.text,
        fatherName: _fatherNameController.text,
        motherName: _motherNameController.text,
        controlNumber: _controlNumberController.text,
        partnerName: _partnerNameController.text,
        partnerBirthDate: _partnerDobController.text,
        cohabitationStartDate: _cohabStartDateController.text,
        buyerName: _buyerNameController.text,
        quantity: fullQty, 
        amountWords: amtWords, 
        amountFigures: amtFigures,
      );

      // Save Request
      await OfflineRequestService.saveRequest(request);

      // Save Transaction (ONLY IF RELEASED)
      if (_selectedStatus == "Released" && paymentAmount > 0) {
        await OfflineRequestService.saveTransaction(
          requestId: reqId,
          fullName: _combinedFullName,
          amount: paymentAmount,
          documentType: widget.documentType,
        );
      }

      // Save Log
      await OfflineRequestService.saveLog(
        "Generated ${widget.documentType} ($_selectedStatus) for $_combinedFullName (Offline)", 
        "Secretary (Offline)"
      );

      // Send to Python
      Map<String, dynamic> pythonData = request.toMap();

      if (widget.documentType.contains('Cohabitation')) {
         pythonData['cohabitationDetails'] = {
           'partnerName': _partnerNameController.text,
           'partnerBirthDate': _partnerDobController.text,
           'cohabitationStartDate': _cohabStartDateController.text,
         };
      }
      if (widget.documentType.contains('Seaweeds')) {
         pythonData['seaweedsDetails'] = {
           'buyerName': _buyerNameController.text,
           'quantity': fullQty,
           'amountWords': amtWords,
           'amountFigures': amtFigures,
         };
      }

      final pythonUrl = Uri.parse('http://127.0.0.1:5000/generate_offline');
      
      final response = await http.post(
        pythonUrl,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(pythonData),
      );

      if (response.statusCode == 200) {
        final jsonResponse = jsonDecode(response.body);
        final String path = jsonResponse['path'];
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Generated ($_selectedStatus)! Opening Word..."), backgroundColor: Colors.green)
        );
        
        await OpenFile.open(path);
        
        // Reset Form
        _formKey.currentState!.reset();
        _firstNameController.clear();
        _middleNameController.clear();
        _lastNameController.clear();
        _selectedSuffix = null;
        _titleController.text = "";
        _amountPaidController.clear();
        _seaweedsAmountController.clear();
        _buyerNameController.clear();
        _quantityController.clear();

      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Python Error: ${response.body}"), backgroundColor: Colors.orange)
        );
      }

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Saved locally. Python backend not reachable? Error: $e"), backgroundColor: Colors.red)
      );
    } finally {
      setState(() => _isSaving = false);
    }
  }
  // ================= LAYOUT =================
  @override
  Widget build(BuildContext context) {
    final isBusiness = widget.documentType == 'Barangay Business Clearance';
    final isLateReg = widget.documentType.contains('Late Registration') || widget.documentType.contains('Birth Certificate');
    final isCohabitation = widget.documentType == 'Certificate of Cohabitation';
    final isSeaweeds = widget.documentType == 'Certificate of Seaweeds';

    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      appBar: AppBar(
        title: Text("Offline Generation: ${widget.documentType}"),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 1,
      ),
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 1000),
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: ListView(
              children: [
                _buildCardHeader("Requestor Information"),
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 100,
                              child: DropdownButtonFormField<String>(
                                initialValue: _titleController.text.isNotEmpty ? _titleController.text : null,
                                decoration: const InputDecoration(labelText: "Title", border: OutlineInputBorder()),
                                items: ['Mr.', 'Ms.', 'Mrs.'].map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                                onChanged: (v) => setState(() => _titleController.text = v ?? ''),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(child: _buildTextField(_firstNameController, "First Name", Icons.person, isTitleCase: true)),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(flex: 3, child: _buildTextField(_middleNameController, "Middle Name (Optional)", Icons.short_text, isTitleCase: true)),
                            const SizedBox(width: 16),
                            Expanded(flex: 4, child: _buildTextField(_lastNameController, "Last Name", Icons.person_outline, isTitleCase: true)),
                            const SizedBox(width: 16),
                            SizedBox(
                              width: 100,
                              child: DropdownButtonFormField<String>(
                                initialValue: _selectedSuffix,
                                decoration: const InputDecoration(labelText: "Suffix", border: OutlineInputBorder()),
                                items: ["None", "Jr.", "Sr.", "II", "III", "IV", "V"].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                                onChanged: (v) => setState(() => _selectedSuffix = v),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                if (isBusiness) ...[
                  _buildCardHeader("Business Details"),
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    child: Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: Column(
                        children: [
                          _buildDualRow(_buildTextField(_businessNameController, "Business Name", Icons.store), _buildTextField(_businessAddressController, "Business Address", Icons.location_on)),
                          const SizedBox(height: 16),
                          _buildDualRow(_buildTextField(_operatorNameController, "Operator/Manager", Icons.person_outline), _buildTextField(_operatorAddressController, "Operator Address", Icons.home)),
                        ],
                      ),
                    ),
                  ),
                ],

                if (isLateReg) ...[
                  _buildCardHeader("Birth Information"),
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    child: Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: Column(
                        children: [
                          _buildDualRow(
                            TextFormField(
                              controller: _birthDateController,
                              decoration: const InputDecoration(labelText: "Birth Date", prefixIcon: Icon(Icons.calendar_today), border: OutlineInputBorder()),
                              readOnly: true,
                              onTap: () => _selectDate(_birthDateController),
                              validator: (v) => v!.isEmpty ? "Required" : null,
                            ),
                            _buildTextField(_placeOfBirthController, "Place of Birth", Icons.map),
                          ),
                          const SizedBox(height: 16),
                          _buildDualRow(_buildTextField(_fatherNameController, "Father's Name", Icons.male, isTitleCase: true), _buildTextField(_motherNameController, "Mother's Name", Icons.female, isTitleCase: true)),
                          const SizedBox(height: 16),
                          _buildTextField(_controlNumberController, "Control No. (Optional)", Icons.numbers),
                        ],
                      ),
                    ),
                  ),
                ],

                if (isCohabitation) ...[
                  _buildCardHeader("Partner & Living Details"),
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    child: Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: Column(
                        children: [
                          // --- FIXED: ADDED REQUESTER BIRTHDATE ---
                          _buildDualRow(
                            TextFormField(
                              controller: _requesterBirthDateController,
                              decoration: const InputDecoration(labelText: "My Birth Date", prefixIcon: Icon(Icons.cake), border: OutlineInputBorder()),
                              readOnly: true,
                              onTap: () => _selectDate(_requesterBirthDateController),
                              validator: (v) => v!.isEmpty ? "Required" : null,
                            ),
                            _buildTextField(_partnerNameController, "Partner's Name", Icons.favorite, isTitleCase: true),
                          ),
                          const SizedBox(height: 16),
                          _buildDualRow(
                            TextFormField(
                              controller: _partnerDobController,
                              decoration: const InputDecoration(labelText: "Partner's Birth Date", prefixIcon: Icon(Icons.cake), border: OutlineInputBorder()),
                              readOnly: true,
                              onTap: () => _selectDate(_partnerDobController),
                              validator: (v) => v!.isEmpty ? "Required" : null,
                            ),
                            TextFormField(
                              controller: _cohabStartDateController,
                              decoration: const InputDecoration(labelText: "Cohabitation Start Date", prefixIcon: Icon(Icons.date_range), border: OutlineInputBorder()),
                              readOnly: true,
                              onTap: () => _selectDate(_cohabStartDateController),
                              validator: (v) => v!.isEmpty ? "Required" : null,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],

                if (isSeaweeds) ...[
                  _buildCardHeader("Seaweeds Sale Details"),
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    child: Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: Column(
                        children: [
                          _buildTextField(_buyerNameController, "Buyer's Name", Icons.person_search, isTitleCase: true),
                          const SizedBox(height: 16),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(flex: 4, child: TextFormField(controller: _quantityController, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: "Qty", hintText: "2.5", prefixIcon: Icon(Icons.scale), border: OutlineInputBorder()), validator: (v) => v!.isEmpty ? "Req." : null)),
                              const SizedBox(width: 12),
                              Expanded(flex: 6, child: DropdownButtonFormField<String>(initialValue: _selectedSeaweedsUnit, decoration: const InputDecoration(labelText: "Unit", border: OutlineInputBorder()), items: ["Rolls", "Kgs", "Tons", "Sacks", "Bundles"].map((u) => DropdownMenuItem(value: u, child: Text(u))).toList(), onChanged: (v) => setState(() => _selectedSeaweedsUnit = v), validator: (v) => v == null ? "Req." : null)),
                            ],
                          ),
                          const SizedBox(height: 16),
                          _buildTextField(_seaweedsAmountController, "Total Amount Sold (Figures)", Icons.monetization_on, isNumber: true),
                        ],
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 24),

                // --- 3. STATUS & PAYMENT FOOTER ---
                // REPLACE THE LAST CARD IN YOUR BUILD METHOD (The Action & Billing Card)
                Card(
                  color: Colors.white,
                  elevation: 4,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("Action & Billing", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.deepPurple)),
                        const SizedBox(height: 16),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 1. Status Dropdown
                            Expanded(
                              flex: 3,
                              child: DropdownButtonFormField<String>(
                                initialValue: _selectedStatus,
                                decoration: const InputDecoration(
                                  labelText: "Status",
                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(Icons.flag),
                                ),
                                // EXPLANATION: Changed "Successful" to "Released"
                                items: ["For Signing", "Released"].map((s) {
                                  return DropdownMenuItem(value: s, child: Text(s));
                                }).toList(),
                                onChanged: (val) {
                                  setState(() {
                                    _selectedStatus = val!;
                                    // Clear amount if not released
                                    if (_selectedStatus == "For Signing") {
                                      _amountPaidController.clear();
                                    }
                                  });
                                },
                              ),
                            ),
                            const SizedBox(width: 16),
                            
                            // 2. Payment (Conditional)
                            Expanded(
                              flex: 3,
                              // EXPLANATION: Only show/enable payment if status is "Released"
                              child: Opacity(
                                opacity: _selectedStatus == "Released" ? 1.0 : 0.5,
                                child: TextFormField(
                                  controller: _amountPaidController,
                                  enabled: _selectedStatus == "Released",
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  decoration: const InputDecoration(
                                    labelText: "Amount Paid (₱)",
                                    prefixIcon: Icon(Icons.payments, color: Colors.green),
                                    border: OutlineInputBorder(),
                                    hintText: "0.00",
                                  ),
                                  validator: (v) {
                                    if (_selectedStatus == "Released" && (v == null || v.isEmpty)) {
                                      return "Amount required to Release";
                                    }
                                    return null;
                                  },
                                ),
                              ),
                            ),
                            
                            const SizedBox(width: 24),
                            
                            // 3. Save Button
                            Expanded(
                              flex: 4,
                              child: SizedBox(
                                height: 56, 
                                child: ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.deepPurple,
                                    foregroundColor: Colors.white,
                                    elevation: 2,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                  onPressed: _isSaving ? null : _saveRequest,
                                  icon: _isSaving 
                                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                    : const Icon(Icons.print_rounded),
                                  label: Text(
                                    _isSaving ? "GENERATING..." : "SAVE & PRINT",
                                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCardHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0, left: 4.0),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey.shade700, letterSpacing: 1.2),
      ),
    );
  }

  Widget _buildDualRow(Widget left, Widget right) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: left),
        const SizedBox(width: 16),
        Expanded(child: right),
      ],
    );
  }

  Widget _buildTextField(TextEditingController controller, String label, IconData icon, {bool isNumber = false, bool isTitleCase = false}) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label, 
        prefixIcon: Icon(icon, color: Colors.grey.shade700),
        border: const OutlineInputBorder(),
        filled: true,
        fillColor: Colors.white,
      ),
      inputFormatters: isTitleCase ? [TitleCaseTextFormatter()] : [],
      keyboardType: isNumber ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
      validator: (v) {
        if (label.contains("Optional")) return null;
        return (v == null || v.isEmpty) ? "Required" : null;
      },
    );
  }
}