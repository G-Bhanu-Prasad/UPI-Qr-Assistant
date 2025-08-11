import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'dart:math';
import 'package:qr_flutter/qr_flutter.dart';
import 'mainpage.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:intl/intl.dart';
import 'transactionspage.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();

  // Color Scheme matching Welcome Page
  static const Color primaryDarkGray = Color(0xFF37474F);
  static const Color secondaryGray = Color(0xFF455A64);
  static const Color darkTeal = Color(0xFF00695C);
  static const Color lightGray = Color(0xFFF5F5F5);
  static const Color mediumGray = Color(0xFF90A4AE);
  static const Color successGreen = Color(0xFF4CAF50);

  // UPI Details Controllers
  final TextEditingController _merchantNameController = TextEditingController();
  final TextEditingController _upiIdController = TextEditingController();
  final TextEditingController _businessDescController = TextEditingController();

  // Employee Controllers
  final TextEditingController _empNameController = TextEditingController();
  final TextEditingController _empPasswordController = TextEditingController();
  final TextEditingController _empRoleController = TextEditingController();

  bool _isLoading = false;
  bool _isLoadingEmployees = false;
  List<Map<String, dynamic>> _employees = [];
  User? _currentUser;
  String? _merchantId;

  bool _isUpdatingMerchant = false;
  bool _isAddingEmployee = false;
  bool _isAuthenticating = false;

  bool canEditUpi = false; // Controls if UPI can be edited

  final GlobalKey _qrKey = GlobalKey(); // Key for QR widget

  // Add these variables after the existing ones:
  List<Map<String, dynamic>> _transactions = [];
  bool _isLoadingTransactions = true;

  String _merchantName = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _currentUser = _auth.currentUser;
    _merchantId = _currentUser?.uid;
    _loadMerchantData();
    _loadEmployees();
    _loadTransactions();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _merchantNameController.dispose();
    _upiIdController.dispose();
    _businessDescController.dispose();
    _empNameController.dispose();
    _empPasswordController.dispose();
    _empRoleController.dispose();
    super.dispose();
  }

  Future<void> _refreshTransactions() async {
    await _loadTransactions();
  }

// Load transactions from SharedPreferences
  Future<void> _loadTransactions() async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String? transactionsJson = prefs.getString('transactions');

      if (transactionsJson != null) {
        List<dynamic> decoded = json.decode(transactionsJson);
        setState(() {
          _transactions = decoded.cast<Map<String, dynamic>>();
          _isLoadingTransactions = false;
        });
      } else {
        setState(() {
          _transactions = [];
          _isLoadingTransactions = false;
        });
      }
    } catch (e) {
      setState(() {
        _isLoadingTransactions = false;
      });
      _showMessage('Error loading transactions: $e', isError: true);
    }
  }

  double _getTotalAmount() {
    return _transactions.fold(0.0, (sum, transaction) {
      return sum + double.parse(transaction['amount'].toString());
    });
  }

  int _getTodayTransactionCount() {
    DateTime now = DateTime.now();
    return _transactions.where((transaction) {
      DateTime transactionDate = DateTime.parse(transaction['timestamp']);
      return transactionDate.day == now.day &&
          transactionDate.month == now.month &&
          transactionDate.year == now.year;
    }).length;
  }

  void _showMessage(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red[700] : successGreen,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  // Google Re-authentication with forced password entry
  Future<bool> _reauthenticateWithGoogle() async {
    try {
      setState(() {
        _isAuthenticating = true;
      });

      // Show modern loading dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          backgroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          content: Container(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Animated loading indicator
                SizedBox(
                  width: 50,
                  height: 50,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    valueColor:
                        AlwaysStoppedAnimation<Color>(Colors.indigo.shade700),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Authenticating...',
                  style: TextStyle(
                    color: Colors.indigo.shade900,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Please complete Google sign-in',
                  style: TextStyle(
                    color: mediumGray,
                    fontSize: 14,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );

      // Force sign out from Google to ensure fresh authentication
      await _googleSignIn.signOut();

      // Configure Google Sign In to force account selection and password entry
      final GoogleSignIn googleSignInForced = GoogleSignIn(
        forceCodeForRefreshToken: true,
      );

      // Sign in with forced authentication
      final GoogleSignInAccount? googleUser = await googleSignInForced.signIn();

      if (googleUser == null) {
        Navigator.pop(context); // Close loading dialog
        setState(() {
          _isAuthenticating = false;
        });
        _showMessage('Authentication cancelled', isError: true);
        return false;
      }

      // Verify this is the same account as currently logged in
      if (googleUser.email != _currentUser!.email) {
        Navigator.pop(context); // Close loading dialog
        setState(() {
          _isAuthenticating = false;
        });
        await googleSignInForced.signOut(); // Sign out the wrong account
        _showMessage(
            'Please authenticate with the same Google account you used to sign in',
            isError: true);
        return false;
      }

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      // Re-authenticate the user with fresh credentials
      await _currentUser!.reauthenticateWithCredential(credential);

      Navigator.pop(context); // Close loading dialog
      setState(() {
        _isAuthenticating = false;
      });

      // Show success message
      _showMessage('Authentication successful!');
      return true;
    } catch (e) {
      Navigator.pop(context); // Close loading dialog
      setState(() {
        _isAuthenticating = false;
      });

      String errorMessage = 'Authentication failed';
      if (e.toString().contains('network-request-failed')) {
        errorMessage = 'Network error. Please check your internet connection.';
      } else if (e.toString().contains('user-disabled')) {
        errorMessage = 'This account has been disabled.';
      } else if (e.toString().contains('wrong-password')) {
        errorMessage = 'Incorrect password. Please try again.';
      } else if (e.toString().contains('too-many-requests')) {
        errorMessage = 'Too many failed attempts. Please try again later.';
      }

      _showMessage(errorMessage, isError: true);
      return false;
    }
  }

  // Generate unique employee ID
  String _generateEmployeeId() {
    final random = Random();
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    return 'EMP${List.generate(6, (index) => chars[random.nextInt(chars.length)]).join()}';
  }

  // Check if employee ID already exists
  Future<bool> _isEmployeeIdUnique(String employeeId) async {
    try {
      QuerySnapshot query = await _firestore
          .collection('merchants')
          .doc(_currentUser!.uid)
          .collection('employees')
          .where('employeeId', isEqualTo: employeeId)
          .get();
      return query.docs.isEmpty;
    } catch (e) {
      return false;
    }
  }

  // Generate unique employee ID that doesn't exist
  Future<String> _generateUniqueEmployeeId() async {
    String employeeId;
    do {
      employeeId = _generateEmployeeId();
    } while (!(await _isEmployeeIdUnique(employeeId)));
    return employeeId;
  }

  Future<void> _loadMerchantData() async {
    if (_currentUser == null) return;

    try {
      DocumentSnapshot doc =
          await _firestore.collection('merchants').doc(_currentUser!.uid).get();

      if (doc.exists) {
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
        setState(() {
          _merchantNameController.text = data['merchantName'] ?? '';
          _upiIdController.text = data['upiId'] ?? '';
          _businessDescController.text = data['businessDescription'] ?? '';
          _merchantName = data['merchantName'] ?? ''; // Store merchant name
        });
      }
    } catch (e) {
      _showMessage('Error loading merchant data: $e', isError: true);
    }
  }

  Future<void> _loadEmployees() async {
    if (_currentUser == null) return;

    setState(() {
      _isLoadingEmployees = true;
    });

    try {
      QuerySnapshot snapshot = await _firestore
          .collection('merchants')
          .doc(_currentUser!.uid)
          .collection('employees')
          .orderBy('createdAt', descending: true)
          .get();

      setState(() {
        _employees = snapshot.docs
            .map((doc) => {
                  'id': doc.id,
                  ...doc.data() as Map<String, dynamic>,
                })
            .toList();
      });
    } catch (e) {
      _showMessage('Error loading employees: $e', isError: true);
    } finally {
      setState(() {
        _isLoadingEmployees = false;
      });
    }
  }

  Future<void> _updateMerchantDetails() async {
    if (_currentUser == null) return;

    // Validation
    if (_merchantNameController.text.trim().isEmpty) {
      _showMessage('Merchant name is required', isError: true);
      return;
    }

    if (_upiIdController.text.trim().isEmpty) {
      _showMessage('UPI ID is required', isError: true);
      return;
    }

    // Basic UPI ID validation
    String upiId = _upiIdController.text.trim();
    if (!upiId.contains('@') || upiId.split('@').length != 2) {
      _showMessage('Please enter a valid UPI ID (e.g., user@paytm)',
          isError: true);
      return;
    }

    // Show confirmation dialog before authentication
    bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Update Business Details',
          style: TextStyle(
            color: Colors.indigo.shade900,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'You are about to update your business details:',
              style: TextStyle(color: secondaryGray),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: lightGray,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: mediumGray.withOpacity(0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Business Name: ${_merchantNameController.text.trim()}',
                      style: TextStyle(color: primaryDarkGray, fontSize: 13)),
                  const SizedBox(height: 6),
                  Text('UPI ID: ${_upiIdController.text.trim()}',
                      style: TextStyle(color: primaryDarkGray, fontSize: 13)),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.amber.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.security, color: Colors.amber.shade800, size: 22),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'You will be asked to enter your Google password to confirm this update.',
                      style:
                          TextStyle(color: Colors.amber.shade800, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            style: TextButton.styleFrom(
              foregroundColor: mediumGray,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.indigo.shade900,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('Continue'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // Authenticate with Google
    bool authenticated = await _reauthenticateWithGoogle();
    if (!authenticated) return;

    setState(() {
      _isUpdatingMerchant = true;
    });

    try {
      await _firestore.collection('merchants').doc(_currentUser!.uid).set({
        'merchantName': _merchantNameController.text.trim(),
        'upiId': _upiIdController.text.trim(),
        'businessDescription': _businessDescController.text.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      _showMessage('Business details updated successfully!');

      // Show success dialog and redirect to main page
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          backgroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          content: Container(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: successGreen.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.check_circle,
                    color: successGreen,
                    size: 35,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Success!',
                  style: TextStyle(
                    color: Colors.indigo.shade900,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Your business details have been updated successfully. You will be redirected to the main page.',
                  style: TextStyle(color: secondaryGray, fontSize: 14),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          actions: [
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(context); // Close dialog
                  Navigator.of(context)
                      .pushNamedAndRemoveUntil('/main', (route) => false);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: successGreen,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('Continue', style: TextStyle(fontSize: 16)),
              ),
            ),
          ],
        ),
      );
    } catch (e) {
      _showMessage('Error updating details: $e', isError: true);
    } finally {
      setState(() {
        _isUpdatingMerchant = false;
      });
    }
  }

  Future<void> _addEmployee() async {
    if (_currentUser == null) return;

    // Validation
    if (_empNameController.text.trim().isEmpty ||
        _empPasswordController.text.trim().isEmpty) {
      _showMessage('Name and password are required', isError: true);
      return;
    }

    if (_empPasswordController.text.length < 6) {
      _showMessage('Password must be at least 6 characters', isError: true);
      return;
    }

    setState(() {
      _isAddingEmployee = true;
    });

    try {
      // Generate unique employee ID
      String employeeId = await _generateUniqueEmployeeId();

      await _firestore
          .collection('merchants')
          .doc(_currentUser!.uid)
          .collection('employees')
          .add({
        'name': _empNameController.text.trim(),
        'employeeId': employeeId,
        'password': _empPasswordController.text.trim(),
        'role': _empRoleController.text.trim().isEmpty
            ? 'Staff'
            : _empRoleController.text.trim(),
        'merchantId': _currentUser!.uid,
        'isActive': true,
        'createdAt': FieldValue.serverTimestamp(),
        'createdBy': _currentUser!.uid,
      });

      // Add to global index
      await _firestore.collection('employeesIndex').doc(employeeId).set({
        'employeeId': employeeId,
        'merchantId': _currentUser!.uid,
        'password': _empPasswordController.text.trim(),
      });

      // Show success dialog with employee credentials
      _showEmployeeCredentialsDialog(employeeId, _empPasswordController.text);

      // Clear form
      _empNameController.clear();
      _empPasswordController.clear();
      _empRoleController.clear();

      _loadEmployees(); // Refresh list
    } catch (e) {
      _showMessage('Error adding employee: $e', isError: true);
    } finally {
      setState(() {
        _isAddingEmployee = false;
      });
    }
  }

// Function to share employee details as text
  Future<void> _shareEmployeeDetails(
      String employeeName, String employeeId, String password) async {
    try {
      // Capture QR code as image
      RenderRepaintBoundary? boundary =
          _qrKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;

      if (boundary != null) {
        // Capture the QR code widget as an image
        ui.Image image = await boundary.toImage(pixelRatio: 3.0);
        ByteData? byteData =
            await image.toByteData(format: ui.ImageByteFormat.png);

        if (byteData != null) {
          Uint8List pngBytes = byteData.buffer.asUint8List();

          // Create share text
          String shareText = '''
Employee Login Details

Name: $employeeName
Employee ID: $employeeId
Password: $password

The QR code can be scanned during login to autofill the Employee ID.
        ''';

          // Share both text and QR code image
          await Share.shareXFiles(
            [
              XFile.fromData(
                pngBytes,
                name: 'employee_qr_$employeeId.png',
                mimeType: 'image/png',
              ),
            ],
            text: shareText,
            subject: 'Employee Login Credentials - $employeeName',
          );

          _showMessage('Employee details and QR code shared successfully!');
        } else {
          // Fallback to text only if QR capture fails
          await _shareTextOnly(employeeName, employeeId, password);
        }
      } else {
        // Fallback to text only if boundary is null
        await _shareTextOnly(employeeName, employeeId, password);
      }
    } catch (e) {
      print('Error sharing with QR: $e');
      // Fallback to text only sharing
      await _shareTextOnly(employeeName, employeeId, password);
    }
  }

  Future<void> _shareTextOnly(
      String employeeName, String employeeId, String password) async {
    try {
      String shareText = '''
Employee Login Details

Name: $employeeName
// Employee ID: $employeeId
// Password: $password
    ''';

      await Share.share(
        shareText,
        subject: 'Employee Login Credentials - $employeeName',
      );

      //_showMessage('Employee details shared successfully!');
    } catch (e) {
      _showMessage('Error sharing employee details: $e', isError: true);
    }
  }

  void _showEmployeeCredentialsDialog(String employeeId, String password) {
    final qrData = {
      'name': _empNameController.text.trim(),
      'employeeId': employeeId,
      'password': password,
      'role': _empRoleController.text.trim().isEmpty
          ? 'Staff'
          : _empRoleController.text.trim(),
      'merchantId': _currentUser!.uid,
      'merchantName': _merchantName, // Include merchant name
      'isActive': true,
      'createdAt':
          DateTime.now().toIso8601String(), // Convert timestamp to string
      'createdBy': _currentUser!.uid,
    };

    // Convert to JSON string for QR code
    final String qrString = json.encode(qrData);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Employee Added Successfully!',
          style: TextStyle(
            color: Colors.indigo.shade900,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Employee login credentials:',
                style: TextStyle(color: secondaryGray, fontSize: 14),
              ),
              const SizedBox(height: 16),
              _buildCredentialRow('Name:', _empNameController.text.trim()),
              _buildCredentialRow('Employee ID:', employeeId),
              _buildCredentialRow('Password:', password),
              _buildCredentialRow(
                  'Role:',
                  _empRoleController.text.trim().isEmpty
                      ? 'Staff'
                      : _empRoleController.text.trim()),
              _buildCredentialRow('Business:', _merchantName),
              const SizedBox(height: 16),
              Center(
                child: RepaintBoundary(
                  key: _qrKey,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: lightGray,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: mediumGray.withOpacity(0.3)),
                    ),
                    child: QrImageView(
                      data: qrString,
                      version: QrVersions.auto,
                      size: 180,
                      backgroundColor: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Employee can scan this QR during login to autofill all details.',
                style: TextStyle(color: Colors.indigo.shade700, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        actions: [
          TextButton.icon(
            iconAlignment: IconAlignment.start,
            onPressed: () async {
              String employeeName = _empNameController.text.trim();
              await _shareEmployeeDetails(employeeName, employeeId, password);
            },
            icon: const Icon(Icons.share, size: 18),
            label: const Text('Share Details'),
            style: TextButton.styleFrom(
              foregroundColor: Colors.indigo.shade900,
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            style: TextButton.styleFrom(
              foregroundColor: Colors.indigo.shade900,
            ),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Widget _buildCredentialRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(color: secondaryGray, fontSize: 12),
            ),
          ),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: lightGray,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: mediumGray.withOpacity(0.3)),
              ),
              child: SelectableText(
                value,
                style: TextStyle(color: primaryDarkGray, fontSize: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleEmployeeStatus(
      String employeeId, bool currentStatus) async {
    try {
      await _firestore
          .collection('merchants')
          .doc(_currentUser!.uid)
          .collection('employees')
          .doc(employeeId)
          .update({
        'isActive': !currentStatus,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      _showMessage(
          'Employee ${!currentStatus ? 'activated' : 'deactivated'} successfully!');
      _loadEmployees();
    } catch (e) {
      _showMessage('Error updating employee status: $e', isError: true);
    }
  }

  Future<void> _deleteEmployee(String employeeId, String employeeName) async {
    bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Confirm Delete',
          style: TextStyle(
            color: Colors.indigo.shade900,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          'Are you sure you want to delete $employeeName?',
          style: TextStyle(color: secondaryGray),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            style: TextButton.styleFrom(foregroundColor: mediumGray),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _firestore
            .collection('merchants')
            .doc(_currentUser!.uid)
            .collection('employees')
            .doc(employeeId)
            .delete();

        _showMessage('Employee deleted successfully!');
        _loadEmployees();
      } catch (e) {
        _showMessage('Error deleting employee: $e', isError: true);
      }
    }
  }

  void _showEmployeeCredentials(Map<String, dynamic> employee) {
    final qrData = {
      'name': employee['name'],
      'employeeId': employee['employeeId'],
      'password': employee['password'],
      'role': employee['role'] ?? 'Staff',
      'merchantId': employee['merchantId'] ?? _merchantId ?? '',
      'merchantName': _merchantName,
      'isActive': employee['isActive'] ?? true,
      'createdAt': employee['createdAt']?.toDate()?.toIso8601String() ??
          DateTime.now().toIso8601String(),
      'createdBy': employee['createdBy'] ?? _currentUser!.uid,
    };

    // Convert to JSON string for QR code
    final String qrString = json.encode(qrData);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          '${employee['name']} - Login Credentials',
          style: TextStyle(
            color: Colors.indigo.shade900,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildCredentialRow('Name:', employee['name']),
              _buildCredentialRow('Employee ID:', employee['employeeId']),
              _buildCredentialRow('Password:', employee['password']),
              _buildCredentialRow('Role:', employee['role'] ?? 'Staff'),
              _buildCredentialRow('Business:', _merchantName),
              _buildCredentialRow(
                  'Status:', employee['isActive'] ? 'Active' : 'Inactive'),
              const SizedBox(height: 16),
              Center(
                child: RepaintBoundary(
                  key: _qrKey,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: lightGray,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: mediumGray.withOpacity(0.3)),
                    ),
                    child: QrImageView(
                      data: qrString,
                      version: QrVersions.auto,
                      size: 180,
                      backgroundColor: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'This QR contains complete employee details for easy login.',
                style: TextStyle(color: Colors.indigo.shade700, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        actions: [
          TextButton.icon(
            iconAlignment: IconAlignment.start,
            onPressed: () async {
              String employeeName = employee['name'];
              await _shareEmployeeDetails(
                  employeeName, employee['employeeId'], employee['password']);
            },
            icon: const Icon(Icons.share, size: 18),
            label: const Text('Share Details'),
            style: TextButton.styleFrom(
              foregroundColor: Colors.indigo.shade900,
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            style: TextButton.styleFrom(
              foregroundColor: Colors.indigo.shade900,
            ),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _logout() async {
    try {
      await _auth.signOut();
      Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
    } catch (e) {
      _showMessage('Error signing out: $e', isError: true);
    }
  }

  Widget _buildInputField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
    String? hint,
    bool obscureText = false,
    int? maxLines,
    bool canEditUpi = false,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        //border: Border.all(color: mediumGray.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color: secondaryGray.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        readOnly: !canEditUpi,
        obscureText: obscureText,
        maxLines: maxLines ?? 1,
        cursorColor: Colors.indigo.shade700,
        style: TextStyle(color: primaryDarkGray),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          labelStyle:
              TextStyle(color: secondaryGray, fontWeight: FontWeight.bold),
          hintStyle: TextStyle(color: mediumGray),
          prefixIcon: Icon(icon, color: Colors.indigo.shade700),
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.indigo.shade700, width: 2),
          ),
        ),
      ),
    );
  }

  Widget _buildCard({required Widget child}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
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
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: child,
      ),
    );
  }

  Widget _buildUpiDetailsTab() {
    return Container(
      color: lightGray,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.indigo.shade100,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          Icons.business,
                          color: Colors.indigo.shade900,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Business Information',
                        style: TextStyle(
                          color: Colors.indigo.shade900,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  _buildInputField(
                    controller: _merchantNameController,
                    label: 'Merchant Name',
                    icon: Icons.business,
                    hint: 'Enter your business name',
                  ),
                  _buildInputField(
                    controller: _upiIdController,
                    label: 'UPI ID',
                    icon: Icons.account_balance_wallet,
                    hint: 'e.g., merchant@paytm',
                    keyboardType: TextInputType.emailAddress,
                  ),
                  // _buildInputField(
                  //   controller: _businessDescController,
                  //   label: 'Business Description (Optional)',
                  //   icon: Icons.description,
                  //   hint: 'Brief description of your business',
                  //   maxLines: 3,
                  // ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: (_isUpdatingMerchant || _isAuthenticating)
                          ? null
                          : () async {
                              setState(() {
                                _isAuthenticating = true;
                              });

                              bool isAuthSuccess =
                                  await _reauthenticateWithGoogle();

                              setState(() {
                                _isAuthenticating = false;
                              });

                              if (isAuthSuccess) {
                                setState(() {
                                  canEditUpi = true;
                                });

                                // Navigate to your actual Merchant Setup screen
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (context) => MainPage()),
                                );
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text('Authentication failed')),
                                );
                              }
                            },
                      icon: (_isUpdatingMerchant || _isAuthenticating)
                          ? SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : const Icon(Icons.save, size: 20),
                      label: Text(
                        (_isUpdatingMerchant || _isAuthenticating)
                            ? 'Updating...'
                            : 'Update Details',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.indigo.shade900,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation:
                            (_isUpdatingMerchant || _isAuthenticating) ? 0 : 2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // _buildCard(
            //   child: Column(
            //     crossAxisAlignment: CrossAxisAlignment.start,
            //     children: [
            //       Row(
            //         children: [
            //           Container(
            //             padding: const EdgeInsets.all(8),
            //             decoration: BoxDecoration(
            //               color: Colors.indigo.shade100,
            //               borderRadius: BorderRadius.circular(8),
            //             ),
            //             child: Icon(
            //               Icons.key,
            //               color: Colors.indigo.shade900,
            //               size: 20,
            //             ),
            //           ),
            //           const SizedBox(width: 12),
            //           Text(
            //             'Your Merchant ID',
            //             style: TextStyle(
            //               color: Colors.indigo.shade900,
            //               fontSize: 16,
            //               fontWeight: FontWeight.bold,
            //             ),
            //           ),
            //         ],
            //       ),
            //       const SizedBox(height: 12),
            //       Container(
            //         width: double.infinity,
            //         padding: const EdgeInsets.all(12),
            //         decoration: BoxDecoration(
            //           color: lightGray,
            //           borderRadius: BorderRadius.circular(8),
            //           border: Border.all(color: mediumGray.withOpacity(0.3)),
            //         ),
            //         child: SelectableText(
            //           _merchantId ?? 'Loading...',
            //           style: TextStyle(color: primaryDarkGray, fontSize: 14),
            //         ),
            //       ),
            //       const SizedBox(height: 8),
            //       Text(
            //         'Share this ID with employees for login',
            //         style:
            //             TextStyle(color: Colors.indigo.shade700, fontSize: 12),
            //       ),
            //     ],
            //   ),
            // ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmployeeManagementTab() {
    return Container(
      color: lightGray,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      // Container(
                      //   padding: const EdgeInsets.all(8),
                      //   decoration: BoxDecoration(
                      //     color: successGreen.withOpacity(0.2),
                      //     borderRadius: BorderRadius.circular(8),
                      //   ),
                      //   child: Icon(
                      //     Icons.person_add,
                      //     color: successGreen,
                      //     size: 20,
                      //   ),
                      // ),
                      const SizedBox(width: 12),
                      Text(
                        'Add New Employee',
                        style: TextStyle(
                          color: Colors.indigo.shade900,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  _buildInputField(
                    controller: _empNameController,
                    canEditUpi: !canEditUpi,
                    label: 'Employee Name',
                    icon: Icons.person,
                    hint: 'Enter employee full name',
                  ),
                  _buildInputField(
                    controller: _empPasswordController,
                    canEditUpi: !canEditUpi,
                    label: 'Password',
                    icon: Icons.lock,
                    hint: 'Minimum 6 characters',
                    obscureText: true,
                  ),
                  _buildInputField(
                    controller: _empRoleController,
                    canEditUpi: !canEditUpi,
                    label: 'Role (Optional)',
                    icon: Icons.work,
                    hint: 'e.g., Cashier, Manager (default: Staff)',
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isAddingEmployee ? null : _addEmployee,
                      icon: _isAddingEmployee
                          ? SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : const Icon(Icons.person_add, size: 20),
                      label: Text(
                        _isAddingEmployee
                            ? 'Adding Employee...'
                            : 'Add Employee',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: successGreen,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: _isAddingEmployee ? 0 : 2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            _buildCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.indigo.shade100,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          Icons.people,
                          color: Colors.indigo.shade900,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Current Employees',
                        style: TextStyle(
                          color: Colors.indigo.shade900,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      Container(
                        width: 60,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.indigo.shade100,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${_employees.length}',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.indigo.shade900,
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _isLoadingEmployees
                      ? const Center(
                          child: CircularProgressIndicator(),
                        )
                      : _employees.isEmpty
                          ? Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(24),
                              decoration: BoxDecoration(
                                color: lightGray,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                    color: mediumGray.withOpacity(0.3)),
                              ),
                              child: Column(
                                children: [
                                  Icon(Icons.people_outline,
                                      size: 48, color: mediumGray),
                                  const SizedBox(height: 12),
                                  Text(
                                    'No employees added yet',
                                    style: TextStyle(
                                      color: secondaryGray,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Add your first employee using the form above',
                                    style: TextStyle(
                                      color: mediumGray,
                                      fontSize: 12,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            )
                          : ListView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: _employees.length,
                              itemBuilder: (context, index) {
                                final employee = _employees[index];
                                final isActive = employee['isActive'] ?? true;

                                return Container(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: lightGray,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: isActive
                                          ? successGreen.withOpacity(0.3)
                                          : Colors.red.withOpacity(0.3),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      CircleAvatar(
                                        backgroundColor: isActive
                                            ? successGreen
                                            : Colors.red,
                                        child: Text(
                                          employee['name'][0].toUpperCase(),
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              employee['name'],
                                              style: TextStyle(
                                                color: primaryDarkGray,
                                                fontSize: 16,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            Text(
                                              'ID: ${employee['employeeId']} • ${employee['role']}',
                                              style: TextStyle(
                                                color: secondaryGray,
                                                fontSize: 12,
                                              ),
                                            ),
                                            Text(
                                              isActive ? 'Active' : 'Inactive',
                                              style: TextStyle(
                                                color: isActive
                                                    ? successGreen
                                                    : Colors.red,
                                                fontSize: 11,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      PopupMenuButton<String>(
                                        icon: Icon(Icons.more_vert,
                                            color: secondaryGray),
                                        color: Colors.white,
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        onSelected: (value) {
                                          if (value == 'toggle') {
                                            _toggleEmployeeStatus(
                                                employee['id'], isActive);
                                          } else if (value == 'delete') {
                                            _deleteEmployee(employee['id'],
                                                employee['name']);
                                          } else if (value == 'credentials') {
                                            _showEmployeeCredentials(employee);
                                          }
                                        },
                                        itemBuilder: (context) => [
                                          PopupMenuItem(
                                            value: 'credentials',
                                            child: Row(
                                              children: [
                                                Icon(Icons.key,
                                                    color:
                                                        Colors.indigo.shade700,
                                                    size: 20),
                                                const SizedBox(width: 8),
                                                Text('View Credentials',
                                                    style: TextStyle(
                                                        color:
                                                            primaryDarkGray)),
                                              ],
                                            ),
                                          ),
                                          PopupMenuItem(
                                            value: 'toggle',
                                            child: Row(
                                              children: [
                                                Icon(
                                                  isActive
                                                      ? Icons.pause
                                                      : Icons.play_arrow,
                                                  color: secondaryGray,
                                                  size: 20,
                                                ),
                                                const SizedBox(width: 8),
                                                Text(
                                                  isActive
                                                      ? 'Deactivate'
                                                      : 'Activate',
                                                  style: TextStyle(
                                                      color: primaryDarkGray),
                                                ),
                                              ],
                                            ),
                                          ),
                                          PopupMenuItem(
                                            value: 'delete',
                                            child: const Row(
                                              children: [
                                                Icon(Icons.delete,
                                                    color: Colors.red,
                                                    size: 20),
                                                SizedBox(width: 8),
                                                Text('Delete',
                                                    style: TextStyle(
                                                        color: Colors.red)),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingOverlay({required String message}) {
    return Container(
      color: Colors.black.withOpacity(0.3),
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(24),
          margin: const EdgeInsets.all(40),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 40,
                height: 40,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  valueColor:
                      AlwaysStoppedAnimation<Color>(Colors.indigo.shade700),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                message,
                style: TextStyle(
                  color: Colors.indigo.shade900,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTransactionsTab() {
    return Container(
      color: lightGray,
      child: _isLoadingTransactions
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Summary Card
                  _buildCard(
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Total Revenue',
                                style: TextStyle(
                                  color: secondaryGray,
                                  fontSize: 14,
                                ),
                              ),
                              Text(
                                '₹${_getTotalAmount().toStringAsFixed(2)}',
                                style: TextStyle(
                                  color: Colors.indigo.shade900,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          width: 1,
                          height: 50,
                          color: mediumGray.withOpacity(0.3),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                'Today\'s Transactions',
                                style: TextStyle(
                                  color: secondaryGray,
                                  fontSize: 14,
                                ),
                              ),
                              Text(
                                '${_getTodayTransactionCount()}',
                                style: TextStyle(
                                  color: successGreen,
                                  fontSize: 28,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Transactions List
                  _buildCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.indigo.shade100,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                Icons.receipt_long,
                                color: Colors.indigo.shade900,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              'Recent Transactions',
                              style: TextStyle(
                                color: Colors.indigo.shade900,
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const Spacer(),
                            if (_transactions.isNotEmpty)
                              TextButton(
                                onPressed: () async {
                                  final result = await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) =>
                                          const TransactionsPage(),
                                    ),
                                  );

                                  // If transactions were cleared, refresh the data
                                  if (result == true) {
                                    _refreshTransactions();
                                  }
                                },
                                child: Text(
                                  'View All',
                                  style: TextStyle(
                                    color: Colors.indigo.shade700,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 15,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        _transactions.isEmpty
                            ? Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(24),
                                decoration: BoxDecoration(
                                  color: lightGray,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                      color: mediumGray.withOpacity(0.3)),
                                ),
                                child: Column(
                                  children: [
                                    Icon(Icons.receipt_long_outlined,
                                        size: 48, color: mediumGray),
                                    const SizedBox(height: 12),
                                    Text(
                                      'No transactions yet',
                                      style: TextStyle(
                                        color: secondaryGray,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Start accepting payments to see transactions here',
                                      style: TextStyle(
                                        color: mediumGray,
                                        fontSize: 12,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                ),
                              )
                            : ListView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: _transactions.length > 5
                                    ? 5
                                    : _transactions.length,
                                itemBuilder: (context, index) {
                                  final transaction = _transactions[index];
                                  DateTime transactionDate =
                                      DateTime.parse(transaction['timestamp']);

                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: lightGray,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: mediumGray.withOpacity(0.2),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 40,
                                          height: 40,
                                          decoration: BoxDecoration(
                                            color:
                                                successGreen.withOpacity(0.1),
                                            shape: BoxShape.circle,
                                          ),
                                          child: Icon(
                                            Icons.payment,
                                            color: successGreen,
                                            size: 20,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                transaction['merchantName'],
                                                style: TextStyle(
                                                  color: primaryDarkGray,
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                              Text(
                                                DateFormat('MMM dd, hh:mm a')
                                                    .format(transactionDate),
                                                style: TextStyle(
                                                  color: secondaryGray,
                                                  fontSize: 11,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Text(
                                          '₹${transaction['amount']}',
                                          style: TextStyle(
                                            color: successGreen,
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: lightGray,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(
          'Settings',
          style: TextStyle(
            color: Colors.indigo.shade900,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Colors.indigo.shade900),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          TextButton.icon(
            onPressed: _logout,
            icon: const Icon(Icons.logout, color: Colors.red),
            label: const Text(
              'Logout',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Container(
            color: Colors.white,
            child: TabBar(
              controller: _tabController,
              indicatorColor: Colors.indigo.shade900,
              labelColor: Colors.indigo.shade900,
              unselectedLabelColor: mediumGray,
              indicatorWeight: 3,
              tabs: const [
                Tab(
                  icon: Icon(Icons.business),
                  text: 'Business Info',
                ),
                Tab(
                  icon: Icon(Icons.people),
                  text: 'Employees',
                ),
                Tab(
                  icon: Icon(Icons.receipt_long),
                  text: 'Transactions',
                ),
              ],
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildUpiDetailsTab(),
          _buildEmployeeManagementTab(),
          _buildTransactionsTab(),
        ],
      ),
    );
  }
}
