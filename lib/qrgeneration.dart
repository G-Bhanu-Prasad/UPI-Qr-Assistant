import 'dart:ui' as ui;
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:PayPro/settings.dart';
import 'package:PayPro/employee_settings.dart';
import 'package:qr_flutter/qr_flutter.dart';

class QRGenerationPage extends StatefulWidget {
  final String merchantName;
  final String upiId;
  final bool isEmployee;

  const QRGenerationPage({
    super.key,
    required this.merchantName,
    required this.upiId,
    this.isEmployee = false,
  });

  @override
  State<QRGenerationPage> createState() => _QRGenerationPageState();
}

class _QRGenerationPageState extends State<QRGenerationPage> {
  final TextEditingController _amountController = TextEditingController();
  final GlobalKey _qrKey = GlobalKey();

  User? _currentUser;
  bool isMerchant = false;

  // For employee info
  String? employeeId;
  String? merchantId;
  String? employeeName;
  String? merchantName;

  bool get isEmployee => widget.isEmployee;

  // Color Scheme
  static const Color primaryDarkGray = Color(0xFF37474F);
  static const Color secondaryGray = Color(0xFF455A64);
  static const Color darkTeal = Color(0xFF00695C);
  static const Color lightGray = Color(0xFFF5F5F5);
  static const Color mediumGray = Color(0xFF90A4AE);
  static const Color successGreen = Color(0xFF4CAF50);
  static const Color errorRed = Color(0xFFF44336);

  @override
  void initState() {
    super.initState();
    _currentUser = FirebaseAuth.instance.currentUser;
    _checkUserRole();
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _checkUserRole() async {
    final userId = FirebaseAuth.instance.currentUser!.uid;

    final merchantDoc = await FirebaseFirestore.instance
        .collection('merchants')
        .doc(userId)
        .get();

    if (merchantDoc.exists) {
      setState(() {
        isMerchant = true;
      });
      return;
    }

    final employeeIndexSnapshot = await FirebaseFirestore.instance
        .collection('employeesIndex')
        .where('firebaseUid', isEqualTo: userId)
        .limit(1)
        .get();

    if (employeeIndexSnapshot.docs.isNotEmpty) {
      setState(() {
        isMerchant = false;
      });
    }
  }

  void _generateQRCode() {
    if (_amountController.text.trim().isEmpty) {
      _showMessage('Please enter an amount', isError: true);
      return;
    }

    String amount = _amountController.text.trim();
    String upiUri =
        'upi://pay?pa=${widget.upiId}&pn=${Uri.encodeComponent(widget.merchantName)}&am=$amount&cu=INR';

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PaymentQRScreen(
          qrData: upiUri,
          merchantName: widget.merchantName,
          upiId: widget.upiId,
          amount: amount,
          onMarkAsPaid: _handleMarkAsPaid,
        ),
      ),
    );
  }

  Future<void> _handleMarkAsPaid(String amount) async {
    await _storeTransaction(amount);
    _startNewTransaction();
  }

  Future<void> _storeTransaction(String amount) async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();

      // Create transaction object
      Map<String, dynamic> transaction = {
        'id': DateTime.now().millisecondsSinceEpoch.toString(),
        'merchantName': widget.merchantName,
        'upiId': widget.upiId,
        'amount': amount,
        'currency': 'INR',
        'timestamp': DateTime.now().toIso8601String(),
        'status': 'paid',
        'paymentMethod': 'UPI',
        'isEmployee': widget.isEmployee,
        'userId': _currentUser?.uid ?? '',
      };

      // Get existing transactions
      String? existingTransactionsJson = prefs.getString('transactions');
      List<Map<String, dynamic>> transactions = [];

      if (existingTransactionsJson != null) {
        List<dynamic> decoded = json.decode(existingTransactionsJson);
        transactions = decoded.cast<Map<String, dynamic>>();
      }

      // Add new transaction at the beginning (most recent first)
      transactions.insert(0, transaction);

      // Keep only last 100 transactions to avoid excessive storage
      if (transactions.length > 100) {
        transactions = transactions.take(100).toList();
      }

      // Save updated transactions
      String updatedTransactionsJson = json.encode(transactions);
      await prefs.setString('transactions', updatedTransactionsJson);

      // Also store last transaction separately for quick access
      await prefs.setString('lastTransaction', json.encode(transaction));

      print('Transaction stored successfully: ${transaction['id']}');
    } catch (e) {
      print('Error storing transaction: $e');
      _showMessage('Failed to save transaction', isError: true);
    }
  }

  void _startNewTransaction() {
    setState(() {
      _amountController.clear();
    });
    _showMessage('Transaction saved! Ready for new transaction');
  }

  void _showMessage(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.check_circle_outline,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: isError ? errorRed : successGreen,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(milliseconds: 500),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  Widget _buildCenteredAmountInput() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: mediumGray.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color: secondaryGray.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(Icons.currency_rupee, color: Colors.indigo.shade900, size: 40),
          const SizedBox(height: 16),
          TextField(
            controller: _amountController,
            cursorColor: Colors.indigo.shade900,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(
              color: primaryDarkGray,
              fontSize: 32,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
            decoration: InputDecoration(
              hintText: '0.00',
              hintStyle: TextStyle(
                color: mediumGray,
                fontSize: 32,
                fontWeight: FontWeight.bold,
              ),
              border: InputBorder.none,
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        SystemNavigator.pop();
      },
      child: Scaffold(
        backgroundColor: lightGray,
        appBar: AppBar(
          automaticallyImplyLeading: false,
          backgroundColor: lightGray,
          centerTitle: true,
          elevation: 0,
          actions: [
            if (isMerchant)
              IconButton(
                icon: Icon(Icons.person, color: Colors.indigo.shade900),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const SettingsPage(),
                    ),
                  );
                },
              ),
            if (isEmployee)
              IconButton(
                icon: Icon(Icons.person, color: Colors.indigo.shade900),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const EmployeeSettingsPage(),
                    ),
                  );
                },
              ),
          ],
        ),
        body: SingleChildScrollView(
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                children: [
                  const SizedBox(height: 50),
                  Text(
                    'Enter Amount',
                    style: TextStyle(
                      color: primaryDarkGray,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Enter the amount you want to receive',
                    style: TextStyle(
                      color: secondaryGray,
                      fontSize: 16,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 40),
                  _buildCenteredAmountInput(),
                  const SizedBox(height: 40),
                  SizedBox(
                    width: 300,
                    height: 60,
                    child: ElevatedButton.icon(
                      onPressed: _generateQRCode,
                      icon: const Icon(Icons.qr_code_2, size: 28),
                      label: const Text(
                        'Generate QR Code',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w600),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.indigo.shade900,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class PaymentQRScreen extends StatelessWidget {
  final String qrData;
  final String merchantName;
  final String upiId;
  final String amount;
  final Function(String) onMarkAsPaid;

  const PaymentQRScreen({
    Key? key,
    required this.qrData,
    required this.merchantName,
    required this.upiId,
    required this.amount,
    required this.onMarkAsPaid,
  }) : super(key: key);

  // Updated color scheme
  static const Color primaryDarkGray = Color(0xFF37474F);
  static const Color secondaryGray = Color(0xFF455A64);
  static const Color darkTeal = Color(0xFF00695C);
  static const Color lightGray = Color(0xFFF5F5F5);
  static const Color mediumGray = Color(0xFF90A4AE);
  static const Color successGreen = Color(0xFF4CAF50);
  static const Color errorRed = Color(0xFFF44336);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: const ui.Color.fromARGB(255, 2, 31, 74),
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const Expanded(
                    child: Text(
                      'Payment QR Code',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
            ),
            // Main content card
            Expanded(
              child: Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Scan to Pay',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: primaryDarkGray,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    // QR Code
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: mediumGray.withOpacity(0.3)),
                        boxShadow: [
                          BoxShadow(
                            color: secondaryGray.withOpacity(0.1),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: QrImageView(
                        data: qrData,
                        version: QrVersions.auto,
                        size: 200.0,
                        backgroundColor: Colors.white,
                        foregroundColor: primaryDarkGray,
                      ),
                    ),
                    const SizedBox(height: 24),
                    // UPI ID
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: lightGray,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: mediumGray.withOpacity(0.3)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              upiId,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                                color: primaryDarkGray,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: darkTeal,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.copy,
                                color: Colors.white,
                                size: 16,
                              ),
                            ),
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: upiId));
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content:
                                      const Text('UPI ID copied to clipboard'),
                                  backgroundColor: successGreen,
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),
                    // Payment details
                    Column(
                      children: [
                        _buildDetailRow('Merchant Name', merchantName),
                        const SizedBox(height: 16),
                        _buildDetailRow('Amount', '₹$amount'),
                        const SizedBox(height: 16),
                        _buildDetailRow('Payment Method', 'UPI'),
                      ],
                    ),
                    const Spacer(),
                    // Action buttons
                    Row(
                      children: [
                        // Cancel Button
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: mediumGray.withOpacity(0.2),
                              foregroundColor: secondaryGray,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(
                                    color: mediumGray.withOpacity(0.5)),
                              ),
                              elevation: 0,
                            ),
                            onPressed: () {
                              Navigator.of(context).pop();
                            },
                            icon: const Icon(Icons.cancel),
                            label: const Text(
                              'Cancel',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Mark as Paid Button
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: darkTeal,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 2,
                            ),
                            onPressed: () {
                              Navigator.of(context).pop();
                              onMarkAsPaid(amount);
                            },
                            icon: const Icon(Icons.check_circle),
                            label: const Text(
                              'Mark as Paid',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
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
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            color: mediumGray,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: primaryDarkGray,
          ),
        ),
      ],
    );
  }
}
