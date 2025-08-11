import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:qr_code_tools/qr_code_tools.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:PayPro/signuppage.dart';
import 'package:PayPro/qrgeneration.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> with TickerProviderStateMixin {
  bool _isLoading = false;
  bool _isScanning = false;
  User? _currentUser;
  File? _qrFile;
  late AnimationController _fadeController;
  late AnimationController _slideController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  // Store extracted QR data for popup
  Map<String, String> _extractedQRData = {};

  // Color Scheme matching WelcomePage
  static const Color primaryDarkGray = Color(0xFF37474F);
  static const Color secondaryGray = Color(0xFF455A64);
  static const Color darkTeal = Color(0xFF00695C);
  static const Color lightGray = Color(0xFFF5F5F5);
  static const Color mediumGray = Color(0xFF90A4AE);
  static const Color successGreen = Color(0xFF4CAF50);
  static const Color warningOrange = Color(0xFFF59E0B);
  static const Color errorRed = Color(0xFFDC2626);

  @override
  void initState() {
    super.initState();
    _getCurrentUser();
    _initAnimations();
  }

  void _initAnimations() {
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeInOut),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(
        CurvedAnimation(parent: _slideController, curve: Curves.easeOutCubic));

    _fadeController.forward();
    _slideController.forward();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _slideController.dispose();
    super.dispose();
  }

  void _getCurrentUser() {
    _currentUser = FirebaseAuth.instance.currentUser;
  }

  Future<void> _logout(BuildContext context) async {
    try {
      await FirebaseAuth.instance.signOut();
      await GoogleSignIn().signOut();
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const SignupPage()),
      );
    } catch (e) {
      _showMessage("Error signing out: $e", isError: true);
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isError ? Icons.warning_rounded : Icons.check_circle_rounded,
                color: Colors.white,
                size: 18,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: isError ? errorRed : successGreen,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        margin: const EdgeInsets.all(20),
        elevation: 8,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  bool _validateUPI(String upi) {
    final upiRegex = RegExp(r'^[a-zA-Z0-9._-]+@[a-zA-Z0-9.-]+$');
    return upiRegex.hasMatch(upi);
  }

  void _showQRDetailsPopup(Map<String, String> qrData) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 350),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: secondaryGray.withOpacity(0.1),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.indigo.shade900,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(16),
                      topRight: Radius.circular(16),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.qr_code_rounded,
                          color: Colors.white, size: 24),
                      const SizedBox(width: 12),
                      const Text(
                        'QR Code Details',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),

                // Content
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Show only essential details
                      if (qrData['Merchant Name'] != null) ...[
                        _buildDetailRow('Merchant', qrData['Merchant Name']!),
                        const SizedBox(height: 12),
                      ],
                      if (qrData['UPI ID'] != null) ...[
                        _buildDetailRow('UPI ID', qrData['UPI ID']!),
                        const SizedBox(height: 12),
                      ],
                      if (qrData['Amount'] != null) ...[
                        _buildDetailRow('Amount', '₹${qrData['Amount']}'),
                        const SizedBox(height: 12),
                      ],

                      // Info note
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: darkTeal.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: darkTeal.withOpacity(0.2)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline, color: darkTeal, size: 16),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Complete setup to start generating payment QR codes',
                                style: TextStyle(
                                  color: Colors.indigo.shade900,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // Actions
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () {
                            Navigator.of(context).pop();
                            setState(() {
                              _qrFile = null;
                              _extractedQRData.clear();
                            });
                          },
                          style: TextButton.styleFrom(
                            foregroundColor: mediumGray,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                              side: BorderSide(
                                  color: mediumGray.withOpacity(0.3)),
                            ),
                          ),
                          child: const Text(
                            'Rescan',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton(
                          onPressed: _isLoading
                              ? null
                              : () async {
                                  await _completeSetup();
                                  Navigator.of(context).pop();
                                },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.indigo.shade900,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            elevation: 2,
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                        Colors.white),
                                  ),
                                )
                              : const Text(
                                  'Complete Setup',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // Helper method to build detail rows
  Widget _buildDetailRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 70,
          child: Text(
            '$label:',
            style: TextStyle(
              color: mediumGray,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              color: secondaryGray,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _completeSetup() async {
    setState(() {
      _isLoading = true;
    });

    try {
      if (_currentUser == null) throw Exception('User not authenticated');

      String upiId = _extractedQRData['UPI ID'] ?? '';
      String merchantName = _extractedQRData['Merchant Name'] ?? '';

      if (upiId.isEmpty || merchantName.isEmpty) {
        _showMessage('Missing required merchant details from QR code',
            isError: true);
        return;
      }

      await FirebaseFirestore.instance
          .collection('merchants')
          .doc(_currentUser!.uid)
          .set({
        'merchantName': merchantName,
        'upiId': upiId,
        'email': _currentUser!.email,
        'displayName': _currentUser!.displayName,
        'photoURL': _currentUser!.photoURL,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'isActive': true,
        'setupMethod': 'qr_upload',
        'additionalData': _extractedQRData,
      }, SetOptions(merge: true)).timeout(const Duration(seconds: 30));

      _showMessage('Merchant setup completed successfully!');

      setState(() {
        _qrFile = null;
        _extractedQRData.clear();
      });

      Future.delayed(const Duration(milliseconds: 500), () {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => QRGenerationPage(
              merchantName: merchantName,
              upiId: upiId,
            ),
          ),
        );
      });
    } on FirebaseException catch (e) {
      _showMessage('Firebase error: ${e.message}', isError: true);
    } catch (e) {
      _showMessage('Error setting up merchant: $e', isError: true);
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _pickQRCode() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowedExtensions: null,
      );

      if (result != null && result.files.single.path != null) {
        File selectedFile = File(result.files.single.path!);

        if (await selectedFile.exists()) {
          setState(() {
            _qrFile = selectedFile;
          });

          _showMessage('Analyzing QR code...');

          await _scanQRCode(selectedFile.path);
        } else {
          _showMessage('Selected file could not be accessed.', isError: true);
        }
      } else {
        _showMessage('No file selected.', isError: true);
      }
    } catch (e) {
      _showMessage('Error picking file: $e', isError: true);
      print('File picker error: $e');
    }
  }

  Future<void> _scanQRCode(String filePath) async {
    try {
      setState(() {
        _isScanning = true;
      });

      String? qrData = await QrCodeToolsPlugin.decodeFrom(filePath);

      if (qrData != null && qrData.isNotEmpty) {
        print('QR Data: $qrData');

        if (_parseUPIData(qrData)) {
          _showQRDetailsPopup(_extractedQRData);
        } else {
          _showMessage('QR code does not contain valid UPI information.',
              isError: true);
          setState(() {
            _qrFile = null;
          });
        }
      } else {
        _showMessage('Could not read QR code. Please try again.',
            isError: true);
        setState(() {
          _qrFile = null;
        });
      }
    } catch (e) {
      _showMessage('Error reading QR code: $e', isError: true);
      print('QR Scan Error: $e');
      setState(() {
        _qrFile = null;
      });
    } finally {
      setState(() {
        _isScanning = false;
      });
    }
  }

  Future<void> _scanWithCamera() async {
    if (_isScanning) return;
    setState(() {
      _isScanning = true;
    });

    try {
      final status = await Permission.camera.request();
      if (!status.isGranted) {
        _showMessage('Camera permission is required to scan QR codes.',
            isError: true);
        return;
      }

      final raw = await Navigator.of(context).push<String?>(
        MaterialPageRoute(builder: (_) => const QRCameraScannerPage()),
      );

      if (raw != null && raw.isNotEmpty) {
        if (_parseUPIData(raw)) {
          _showQRDetailsPopup(_extractedQRData);
        } else {
          _showMessage('QR code does not contain valid UPI information.',
              isError: true);
        }
      } else {
        _showMessage('No QR code detected.', isError: true);
      }
    } catch (e) {
      _showMessage('Error during camera scan: $e', isError: true);
    } finally {
      setState(() {
        _isScanning = false;
      });
    }
  }

  bool _parseUPIData(String qrData) {
    try {
      _extractedQRData.clear();

      Uri? uri;

      if (qrData.startsWith('upi://pay?')) {
        uri = Uri.parse(qrData);
      } else if (qrData.contains('upi://pay?')) {
        int startIndex = qrData.indexOf('upi://pay?');
        String upiPart = qrData.substring(startIndex);
        uri = Uri.parse(upiPart);
      } else if (qrData.contains('pa=') && qrData.contains('@')) {
        uri = Uri.parse('upi://pay?' + qrData);
      } else {
        uri = Uri.tryParse(qrData);
      }

      if (uri != null) {
        return _extractUPIInfo(uri);
      }

      return false;
    } catch (e) {
      print('Error parsing UPI data: $e');
      return false;
    }
  }

  bool _extractUPIInfo(Uri uri) {
    bool foundData = false;

    String? upiId = uri.queryParameters['pa'];
    if (upiId != null && upiId.isNotEmpty && _validateUPI(upiId)) {
      _extractedQRData['UPI ID'] = upiId;
      foundData = true;
    }

    String? merchantName = uri.queryParameters['pn'];
    if (merchantName != null && merchantName.isNotEmpty) {
      _extractedQRData['Merchant Name'] = merchantName;
      foundData = true;
    }

    String? merchantCode = uri.queryParameters['mc'];
    String? transactionId = uri.queryParameters['tid'];
    String? transactionRef = uri.queryParameters['tr'];
    String? url = uri.queryParameters['url'];
    String? amount = uri.queryParameters['am'];
    String? currency = uri.queryParameters['cu'];
    String? note = uri.queryParameters['tn'];

    if (merchantCode != null && merchantCode.isNotEmpty) {
      _extractedQRData['Merchant Code'] = merchantCode;
      if (!_extractedQRData.containsKey('Merchant Name')) {
        _extractedQRData['Merchant Name'] = merchantCode;
      }
      foundData = true;
    }

    if (amount != null && amount.isNotEmpty) {
      _extractedQRData['Amount'] = amount;
    }

    if (currency != null && currency.isNotEmpty) {
      _extractedQRData['Currency'] = currency;
    }

    if (note != null && note.isNotEmpty) {
      _extractedQRData['Note'] = note;
    }

    if (transactionId != null && transactionId.isNotEmpty) {
      _extractedQRData['Transaction ID'] = transactionId;
    }

    if (transactionRef != null && transactionRef.isNotEmpty) {
      _extractedQRData['Transaction Ref'] = transactionRef;
    }

    if (url != null && url.isNotEmpty) {
      _extractedQRData['URL'] = url;
    }

    print('Extracted UPI Info:');
    _extractedQRData.forEach((key, value) {
      print('$key: $value');
    });

    return foundData;
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.only(
          top: MediaQuery.of(context).padding.top + 20,
          bottom: 30,
          left: 24,
          right: 24),
      decoration: BoxDecoration(
        color: Colors.indigo.shade900,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(32),
          bottomRight: Radius.circular(32),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Merchant Setup',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: IconButton(
                  icon: const Icon(Icons.logout_rounded, color: Colors.white),
                  onPressed: () => _logout(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: Colors.white.withOpacity(0.3), width: 2),
                  color: Colors.white.withOpacity(0.1),
                ),
                child: CircleAvatar(
                  radius: 28,
                  backgroundColor: Colors.transparent,
                  backgroundImage: _currentUser?.photoURL != null
                      ? NetworkImage(_currentUser!.photoURL!)
                      : null,
                  child: _currentUser?.photoURL == null
                      ? const Icon(Icons.person_rounded,
                          size: 32, color: Colors.white)
                      : null,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Welcome back,',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.8),
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _currentUser?.displayName?.split(' ')[0] ?? 'User',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _currentUser?.email ?? '',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.7),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInstructions() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
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
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: darkTeal.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: darkTeal.withOpacity(0.3)),
            ),
            child: Icon(Icons.info_outline_rounded, color: darkTeal, size: 28),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Quick Setup',
                  style: TextStyle(
                    color: Colors.indigo.shade900,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Scan your UPI QR code to automatically extract merchant details and start accepting payments.',
                  style: TextStyle(
                    color: secondaryGray,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQRUploadSection() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 15),
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: mediumGray.withOpacity(0.0)),
        boxShadow: [
          BoxShadow(
            color: secondaryGray.withOpacity(0.0),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: Colors.indigo.shade900.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: Colors.indigo.shade900.withOpacity(0.3)),
                  ),
                  child: Icon(Icons.qr_code_2_rounded,
                      color: Colors.indigo.shade900, size: 28),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Upload UPI QR Code',
                        style: TextStyle(
                          color: Colors.indigo.shade900,
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      // Text(
                      //   'Scan your UPI QR to get started',
                      //   style: TextStyle(
                      //     color: secondaryGray,
                      //     fontSize: 15,
                      //   ),
                      // ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Container(
              width: double.infinity,
              height: 250,
              decoration: BoxDecoration(
                color: lightGray,
                borderRadius: BorderRadius.circular(16),
                border:
                    Border.all(color: mediumGray.withOpacity(0.3), width: 2),
              ),
              child: _qrFile != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Stack(
                        children: [
                          Image.file(
                            _qrFile!,
                            height: 250,
                            width: double.infinity,
                            fit: BoxFit.contain,
                          ),
                          if (_isScanning)
                            Container(
                              color: Colors.black.withOpacity(0.3),
                              child: const Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    CircularProgressIndicator(
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                          Colors.white),
                                    ),
                                    SizedBox(height: 16),
                                    Text(
                                      'Analyzing QR Code...',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    )
                  : Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: Colors.indigo.shade900.withOpacity(0.1),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.qr_code_scanner_rounded,
                              size: 50,
                              color: Colors.indigo.shade900,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No QR Code Selected',
                            style: TextStyle(
                              color: Colors.indigo.shade900,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Scan your UPI QR code to get started',
                            style: TextStyle(
                              color: secondaryGray,
                              fontSize: 14,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 30),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isScanning ? null : _scanWithCamera,
                icon: _isScanning
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Icon(Icons.camera_alt_rounded, size: 20),
                label: Text(_isScanning ? 'Processing...' : 'Scan with Camera'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo.shade900,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 4,
                  shadowColor: Colors.indigo.shade900.withOpacity(0.3),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureCards() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          Expanded(
            child: Container(
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
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: successGreen.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: successGreen.withOpacity(0.3)),
                    ),
                    child: Icon(Icons.flash_on_rounded,
                        color: successGreen, size: 24),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Instant Setup',
                    style: TextStyle(
                      color: Colors.indigo.shade900,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Quick QR scan extraction',
                    style: TextStyle(
                      color: secondaryGray,
                      fontSize: 12,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
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
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: darkTeal.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: darkTeal.withOpacity(0.3)),
                    ),
                    child:
                        Icon(Icons.security_rounded, color: darkTeal, size: 24),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Secure Processing',
                    style: TextStyle(
                      color: Colors.indigo.shade900,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Bank-grade security',
                    style: TextStyle(
                      color: secondaryGray,
                      fontSize: 12,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
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
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: warningOrange.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: warningOrange.withOpacity(0.3)),
                    ),
                    child: Icon(Icons.payments_rounded,
                        color: warningOrange, size: 24),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Easy Payments',
                    style: TextStyle(
                      color: Colors.indigo.shade900,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Accept all UPI apps',
                    style: TextStyle(
                      color: secondaryGray,
                      fontSize: 12,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: lightGray,
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: SlideTransition(
          position: _slideAnimation,
          child: Column(
            children: [
              _buildHeader(),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      //const SizedBox(height: 30),
                      //_buildInstructions(),
                      const SizedBox(height: 20),
                      _buildQRUploadSection(),
                      const SizedBox(height: 24),
                      //_buildFeatureCards(),
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class QRCameraScannerPage extends StatefulWidget {
  const QRCameraScannerPage({super.key});

  @override
  State<QRCameraScannerPage> createState() => _QRCameraScannerPageState();
}

class _QRCameraScannerPageState extends State<QRCameraScannerPage>
    with TickerProviderStateMixin {
  bool _scanned = false;
  bool _isFlashOn = false;
  String? _error;
  late final MobileScannerController _controller;
  late AnimationController _scanlineController;
  late Animation<double> _scanlineAnimation;

  // Professional Color Scheme
  static const Color primaryBlue = Color(0xFF1E3A8A);
  static const Color successGreen = Color(0xFF059669);
  static const Color errorRed = Color(0xFFDC2626);
  static const Color softWhite = Color(0xFFFFFFFE);

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController(
      detectionSpeed: DetectionSpeed.noDuplicates,
      facing: CameraFacing.back,
      torchEnabled: false,
    );

    // Initialize animations
    _scanlineController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );

    _scanlineAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _scanlineController,
      curve: Curves.easeInOut,
    ));

    // Start animations
    _scanlineController.repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    _scanlineController.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_scanned) return;
    final List<Barcode> barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;
    final raw = barcodes.first.rawValue;
    if (raw == null || raw.isEmpty) return;

    setState(() {
      _scanned = true;
    });

    // Stop animations
    _scanlineController.stop();

    // Add haptic feedback
    // HapticFeedback.mediumImpact();

    Navigator.of(context).pop(raw);
  }

  void _toggleFlash() async {
    await _controller.toggleTorch();
    setState(() {
      _isFlashOn = !_isFlashOn;
    });
  }

  Future<void> _pickFromGallery() async {
    try {
      // Import file_picker for image selection
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowedExtensions: null,
      );

      if (result != null && result.files.single.path != null) {
        final selectedFile = File(result.files.single.path!);

        if (await selectedFile.exists()) {
          // Scan the selected QR code image
          final qrData = await QrCodeToolsPlugin.decodeFrom(selectedFile.path);

          if (qrData != null && qrData.isNotEmpty) {
            // Stop animations and return the QR data
            _scanlineController.stop();
            Navigator.of(context).pop(qrData);
          } else {
            // Show error if QR code couldn't be read
            setState(() {
              _error = 'Could not read QR code from the selected image';
            });

            // Clear error after 3 seconds
            Future.delayed(const Duration(seconds: 3), () {
              if (mounted) {
                setState(() {
                  _error = null;
                });
              }
            });
          }
        } else {
          setState(() {
            _error = 'Selected file could not be accessed';
          });

          Future.delayed(const Duration(seconds: 3), () {
            if (mounted) {
              setState(() {
                _error = null;
              });
            }
          });
        }
      }
    } catch (e) {
      setState(() {
        _error = 'Error picking file: $e';
      });

      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) {
          setState(() {
            _error = null;
          });
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Camera view
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error, child) {
              return Container(
                color: Colors.black,
                child: Center(
                  child: Text(
                    'Camera Error: ${error.errorDetails?.message ?? 'Unknown error'}',
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              );
            },
          ),

          // Dark overlay with cutout
          Container(
            color: Colors.black.withOpacity(0.6),
            child: Stack(
              children: [
                // Top overlay
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: MediaQuery.of(context).size.height * 0.35,
                  child: Container(color: Colors.black.withOpacity(0.7)),
                ),
                // Bottom overlay
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  height: MediaQuery.of(context).size.height * 0.35,
                  child: Container(color: Colors.black.withOpacity(0.7)),
                ),
                // Left overlay
                Positioned(
                  top: MediaQuery.of(context).size.height * 0.35,
                  bottom: MediaQuery.of(context).size.height * 0.35,
                  left: 0,
                  width: (MediaQuery.of(context).size.width - 280) / 2,
                  child: Container(color: Colors.black.withOpacity(0.7)),
                ),
                // Right overlay
                Positioned(
                  top: MediaQuery.of(context).size.height * 0.35,
                  bottom: MediaQuery.of(context).size.height * 0.35,
                  right: 0,
                  width: (MediaQuery.of(context).size.width - 280) / 2,
                  child: Container(color: Colors.black.withOpacity(0.7)),
                ),
              ],
            ),
          ),

          // Header with back button and flash toggle
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Back button
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.6),
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.2),
                          width: 1,
                        ),
                      ),
                      child: const Icon(
                        Icons.arrow_back_ios_new_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),

                  // Flash and gallery buttons
                  Row(
                    children: [
                      // Flash toggle
                      GestureDetector(
                        onTap: _toggleFlash,
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.6),
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.2),
                              width: 1,
                            ),
                          ),
                          child: Icon(
                            _isFlashOn
                                ? Icons.flash_on_rounded // Flash on icon
                                : Icons.flash_off_rounded, // Flash off icon
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                      ),
                      // const SizedBox(width: 12),
                      // // More options
                      // GestureDetector(
                      //   onTap: () {
                      //     // Show more options or settings
                      //   },
                      //   child: Container(
                      //     width: 44,
                      //     height: 44,
                      //     decoration: BoxDecoration(
                      //       color: Colors.black.withOpacity(0.6),
                      //       borderRadius: BorderRadius.circular(22),
                      //       border: Border.all(
                      //         color: Colors.white.withOpacity(0.2),
                      //         width: 1,
                      //       ),
                      //     ),
                      //     child: const Icon(
                      //       Icons.more_horiz_rounded,
                      //       color: Colors.white,
                      //       size: 20,
                      //     ),
                      //   ),
                      // ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Scanning frame with corners
          Center(
            child: SizedBox(
              width: 300,
              height: 300,
              child: Stack(
                children: [
                  // Animated scanning line
                  AnimatedBuilder(
                    animation: _scanlineAnimation,
                    builder: (context, child) {
                      return Positioned(
                        top: _scanlineAnimation.value * 260 + 10,
                        left: 10,
                        right: 10,
                        child: Container(
                          height: 2,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.transparent,
                                successGreen.withOpacity(0.8),
                                successGreen,
                                successGreen.withOpacity(0.8),
                                Colors.transparent,
                              ],
                              stops: const [0.0, 0.2, 0.5, 0.8, 1.0],
                            ),
                          ),
                        ),
                      );
                    },
                  ),

                  // Corner frames with pulse animation
                  Stack(
                    children: [
                      // Top-left corner
                      Positioned(
                        top: 0,
                        left: 0,
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            border: Border(
                              top: BorderSide(color: Colors.white, width: 4),
                              left: BorderSide(color: Colors.white, width: 4),
                            ),
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(20),
                            ),
                          ),
                        ),
                      ),
                      // Top-right corner
                      Positioned(
                        top: 0,
                        right: 0,
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            border: Border(
                              top: BorderSide(color: Colors.white, width: 4),
                              right: BorderSide(color: Colors.white, width: 4),
                            ),
                            borderRadius: const BorderRadius.only(
                              topRight: Radius.circular(20),
                            ),
                          ),
                        ),
                      ),
                      // Bottom-left corner
                      Positioned(
                        bottom: 0,
                        left: 0,
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(color: Colors.white, width: 4),
                              left: BorderSide(color: Colors.white, width: 4),
                            ),
                            borderRadius: const BorderRadius.only(
                              bottomLeft: Radius.circular(20),
                            ),
                          ),
                        ),
                      ),
                      // Bottom-right corner
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(color: Colors.white, width: 4),
                              right: BorderSide(color: Colors.white, width: 4),
                            ),
                            borderRadius: const BorderRadius.only(
                              bottomRight: Radius.circular(20),
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

          // Instructions text
          Positioned(
            bottom: 200,
            left: 0,
            right: 0,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 40),
              child: const Text(
                'Align QR code to fill inside the frame',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),

          // Bottom action button
          Positioned(
            bottom: 100,
            left: 0,
            right: 0,
            child: Center(
              child: GestureDetector(
                onTap: _pickFromGallery,
                child: Container(
                  width: 150,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.photo_library_rounded,
                        color: Colors.black,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Choose Image',
                        style: TextStyle(
                          color: Colors.black,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Error message
          if (_error != null)
            Positioned(
              bottom: 40,
              left: 20,
              right: 20,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: errorRed,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: errorRed.withOpacity(0.3),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.error_outline_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _error!,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
