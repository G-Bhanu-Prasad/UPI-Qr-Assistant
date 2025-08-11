import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:PayPro/qrgeneration.dart'; // Add this import
import 'package:file_picker/file_picker.dart';
import 'package:qr_code_tools/qr_code_tools.dart';
import 'package:shared_preferences/shared_preferences.dart'; // Add this import
import 'dart:convert';

class EmployeeLoginPage extends StatefulWidget {
  const EmployeeLoginPage({super.key});

  @override
  State<EmployeeLoginPage> createState() => _EmployeeLoginPageState();
}

class _EmployeeLoginPageState extends State<EmployeeLoginPage> {
  final TextEditingController _merchantIdController = TextEditingController();
  final TextEditingController _employeeIdController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  bool _isLoading = false;
  bool _obscurePassword = true;
  final _formKey = GlobalKey<FormState>();

  // Color Scheme matching Welcome Page
  static const Color primaryDarkGray = Color(0xFF37474F);
  static const Color secondaryGray = Color(0xFF455A64);
  static const Color darkTeal = Color(0xFF00695C);
  static const Color lightGray = Color(0xFFF5F5F5);
  static const Color mediumGray = Color(0xFF90A4AE);
  static const Color successGreen = Color(0xFF4CAF50);

  @override
  void dispose() {
    _merchantIdController.dispose();
    _employeeIdController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _showMessage(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(fontSize: 14),
        ),
        backgroundColor: isError ? Colors.red[700] : successGreen,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration:
            const Duration(seconds: 4), // Longer duration for detailed messages
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  // Add this method to save employee data to SharedPreferences
  Future<void> _saveEmployeeData({
    required String employeeId,
    required String employeeName,
    required String employeeRole,
    required String merchantId,
    required String merchantName,
    required bool isActive,
    DateTime? createdAt,
  }) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();

    await prefs.setString('currentEmployeeId', employeeId);
    await prefs.setString('currentEmployeeName', employeeName);
    await prefs.setString('currentEmployeeRole', employeeRole);
    await prefs.setString('currentMerchantId', merchantId);
    await prefs.setString('currentMerchantName', merchantName);
    await prefs.setBool('currentEmployeeActive', isActive);

    if (createdAt != null) {
      await prefs.setString(
          'currentEmployeeCreatedAt', createdAt.toIso8601String());
    }
  }

  Future<void> _loginEmployee() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final empId = _employeeIdController.text.trim();
      final password = _passwordController.text.trim();

      // Step 1: Look up merchantId using employeeId from global index
      print("Looking up employee ID: $empId"); // Debug print

      final indexDoc =
          await _firestore.collection('employeesIndex').doc(empId).get();

      if (!indexDoc.exists) {
        _showMessage('Employee ID not found. Please check your credentials.',
            isError: true);
        return;
      }

      final indexData = indexDoc.data()!;
      final merchantId = indexData['merchantId'];

      print("Found merchant ID: $merchantId"); // Debug print

      // Step 2: Search in merchant's employees subcollection by employeeId field
      final querySnapshot = await _firestore
          .collection('merchants')
          .doc(merchantId)
          .collection('employees')
          .where('employeeId', isEqualTo: empId)
          .limit(1)
          .get();

      if (querySnapshot.docs.isEmpty) {
        _showMessage('Employee record not found. Please contact your manager.',
            isError: true);
        return;
      }

      final employeeDoc = querySnapshot.docs.first;
      final employeeData = employeeDoc.data();

      print("Employee data found: ${employeeData['name']}"); // Debug print

      // Step 3: Validate credentials
      if (employeeData['password'] != password) {
        _showMessage('Incorrect password. Please try again.', isError: true);
        return;
      }

      if (employeeData['isActive'] != true) {
        _showMessage('Your account is inactive. Please contact your manager.',
            isError: true);
        return;
      }

      // Step 4: Fetch merchant data
      final merchantDoc =
          await _firestore.collection('merchants').doc(merchantId).get();

      if (!merchantDoc.exists) {
        _showMessage('Business information not found. Please contact support.',
            isError: true);
        return;
      }

      final merchantData = merchantDoc.data()!;

      // Step 5: Save employee data to SharedPreferences
      await _saveEmployeeData(
        employeeId: empId,
        employeeName: employeeData['name'] ?? 'Unknown Employee',
        employeeRole: employeeData['role'] ?? 'Staff',
        merchantId: merchantId,
        merchantName: merchantData['merchantName'] ?? 'Unknown Business',
        isActive: employeeData['isActive'] ?? true,
        createdAt: employeeData['createdAt'] != null
            ? (employeeData['createdAt'] as Timestamp).toDate()
            : DateTime.now(),
      );

      // Enhanced success message
      String welcomeMessage =
          'Login successful! Welcome ${employeeData['name']}';
      if (employeeData['role'] != null && employeeData['role'].isNotEmpty) {
        welcomeMessage += ' (${employeeData['role']})';
      }

      _showMessage(welcomeMessage);

      // Step 6: Navigate to next screen
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => QRGenerationPage(
            merchantName: merchantData['merchantName'] ?? 'Unknown Business',
            upiId: merchantData['upiId'] ?? '',
            isEmployee: true,
          ),
        ),
      );
    } catch (e) {
      print("Login error: $e"); // Debug print
      _showMessage(
          'Login failed. Please check your internet connection and try again.',
          isError: true);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Widget _buildInputField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required String? Function(String?) validator,
    TextInputType? keyboardType,
    String? hint,
    bool obscureText = false,
    Widget? suffixIcon,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: mediumGray.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color: secondaryGray.withOpacity(0.1),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        obscureText: obscureText,
        validator: validator,
        cursorColor: Colors.indigo.shade900,
        style: TextStyle(color: Colors.indigo.shade900, fontSize: 17),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          labelStyle: const TextStyle(
              color: secondaryGray, fontSize: 15, fontWeight: FontWeight.bold),
          hintStyle: const TextStyle(color: mediumGray, fontSize: 15),
          prefixIcon: Icon(icon, color: Colors.indigo.shade900, size: 20),
          suffixIcon: suffixIcon,
          filled: true,
          fillColor: Colors.transparent,
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
            borderSide: BorderSide(color: Colors.indigo.shade900, width: 2),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.red, width: 1),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.red, width: 2),
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      ),
    );
  }

  Future<void> _selectQrFileAndExtractMerchantId() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.image,
      );

      if (result == null || result.files.single.path == null) {
        _showMessage("No file selected", isError: true);
        return;
      }

      String imagePath = result.files.single.path!;
      String? qrData = await QrCodeToolsPlugin.decodeFrom(imagePath);

      if (qrData == null || qrData.trim().isEmpty) {
        _showMessage("No QR code found in the image", isError: true);
        return;
      }

      print("Raw QR Data: $qrData"); // Debug print

      try {
        // Try to parse as JSON first (new format)
        Map<String, dynamic> data = json.decode(qrData);

        setState(() {
          // Extract data from JSON structure
          _employeeIdController.text = data['employeeId']?.toString() ?? '';
          _passwordController.text = data['password']?.toString() ?? '';
        });

        // Show success message with employee details if available
        String employeeName = data['name']?.toString() ?? '';
        String role = data['role']?.toString() ?? '';
        String merchantName = data['merchantName']?.toString() ?? '';

        String successMessage = "QR scanned successfully!";
        if (employeeName.isNotEmpty) {
          successMessage += "\nEmployee: $employeeName";
          if (role.isNotEmpty) successMessage += " ($role)";
          if (merchantName.isNotEmpty)
            successMessage += "\nBusiness: $merchantName";
        }

        _showMessage(successMessage);
      } catch (jsonException) {
        print("JSON parsing failed: $jsonException");

        // Fallback to old format parsing
        try {
          // Expected old format: {merchantId: ..., employeeId: ..., password: ...}
          final cleaned = qrData.trim().replaceAll(RegExp(r'^{|}$'), '');
          final parts = cleaned.split(',');
          Map<String, String> data = {};

          for (var part in parts) {
            final kv = part.split(':');
            if (kv.length == 2) {
              final key = kv[0].trim();
              final value = kv[1].trim();
              data[key] = value;
            }
          }

          setState(() {
            _employeeIdController.text = data['employeeId'] ?? '';
            _passwordController.text = data['password'] ?? '';
          });

          _showMessage("QR scanned successfully!");
        } catch (fallbackException) {
          print("Fallback parsing failed: $fallbackException");
          _showMessage("Invalid QR code format", isError: true);
        }
      }
    } catch (e) {
      print("General error: $e");
      _showMessage("Failed to read QR: $e", isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: lightGray,
      appBar: AppBar(
        backgroundColor: lightGray,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Colors.indigo.shade900),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Header Section - matching welcome page style
                  Icon(
                    Icons.person,
                    size: 60,
                    color: Colors.indigo.shade900,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Employee Login',
                    style: TextStyle(
                      color: Colors.indigo.shade900,
                      fontSize: 25,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Enter your credentials to access the system',
                    style: TextStyle(
                      color: secondaryGray,
                      fontSize: 15,
                    ),
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: 30),

                  // Login Form
                  _buildInputField(
                    controller: _employeeIdController,
                    label: 'Employee ID',
                    icon: Icons.badge,
                    hint: 'Enter your employee ID',
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Employee ID is required';
                      }
                      return null;
                    },
                  ),

                  _buildInputField(
                    controller: _passwordController,
                    label: 'Password',
                    icon: Icons.lock,
                    hint: 'Enter your password',
                    obscureText: _obscurePassword,
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility
                            : Icons.visibility_off,
                        color: Colors.indigo.shade900,
                      ),
                      onPressed: () {
                        setState(() {
                          _obscurePassword = !_obscurePassword;
                        });
                      },
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Password is required';
                      }
                      return null;
                    },
                  ),

                  const SizedBox(height: 10),

                  // Help Text - styled like welcome page cards
                  Container(
                    padding: const EdgeInsets.all(20),
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
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.indigo.shade900.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: Colors.indigo.shade900.withOpacity(0.3)),
                          ),
                          child: Icon(
                            Icons.info_outline,
                            color: Colors.indigo.shade900,
                            size: 16,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Need help?',
                                style: TextStyle(
                                  color: Colors.indigo.shade900,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'If you don\'t have your login credentials, please contact your manager',
                                style: TextStyle(
                                  color: secondaryGray,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 40),

                  // Login Button - styled like welcome page buttons
                  Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.indigo.shade900,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.indigo.shade900.withOpacity(0.3),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: _isLoading ? null : _loginEmployee,
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (_isLoading)
                                const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                        Colors.white),
                                  ),
                                )
                              else
                                const Icon(
                                  Icons.login,
                                  color: Colors.white,
                                  size: 24,
                                ),
                              const SizedBox(width: 12),
                              Text(
                                _isLoading ? 'Logging in...' : 'Login',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Upload QR Image Button
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: _selectQrFileAndExtractMerchantId,
                      icon: Icon(Icons.qr_code_scanner,
                          color: Colors.indigo.shade900),
                      label: Text(
                        'Upload QR Image',
                        style: TextStyle(color: Colors.indigo.shade900),
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
