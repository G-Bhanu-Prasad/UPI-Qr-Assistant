import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'dart:math';

class EnhancedAuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();

  // Rate limiting for authentication attempts
  static const int maxAuthAttempts = 3;
  static const Duration authCooldownDuration = Duration(minutes: 15);
  static Map<String, AuthAttemptTracker> _attemptTrackers = {};

  // Session validation
  static const Duration sessionValidityDuration = Duration(minutes: 10);
  static Map<String, DateTime> _lastAuthTimes = {};

  /// Enhanced re-authentication with comprehensive security measures
  Future<AuthResult> reauthenticateUser(BuildContext context) async {
    final user = _auth.currentUser;
    if (user == null) {
      return AuthResult.failure('No user logged in');
    }

    // Check rate limiting
    if (_isRateLimited(user.uid)) {
      return AuthResult.failure(
          'Too many authentication attempts. Please try again in ${_getRemainingCooldown(user.uid)} minutes.');
    }

    // Check if recent authentication is still valid
    if (_isRecentAuthValid(user.uid)) {
      return AuthResult.success('Recent authentication is still valid');
    }

    try {
      _showAuthLoadingDialog(context);

      // Determine authentication method based on provider
      AuthResult result;
      final providerData = user.providerData.first;

      switch (providerData.providerId) {
        case 'google.com':
          result = await _reauthenticateWithGoogle(user);
          break;
        case 'password':
          Navigator.pop(context); // Close loading dialog
          result = await _reauthenticateWithPassword(context, user);
          break;
        default:
          result = AuthResult.failure('Unsupported authentication provider');
      }

      if (context.mounted && Navigator.canPop(context)) {
        Navigator.pop(context); // Close any remaining dialogs
      }

      // Handle result
      if (result.isSuccess) {
        _recordSuccessfulAuth(user.uid);
        _showSuccessMessage(context, 'Authentication successful!');
      } else {
        _recordFailedAuth(user.uid);
        _showErrorMessage(context, result.error!);
      }

      return result;
    } catch (e) {
      if (context.mounted && Navigator.canPop(context)) {
        Navigator.pop(context);
      }

      _recordFailedAuth(user.uid);
      return AuthResult.failure(_getErrorMessage(e));
    }
  }

  /// Google re-authentication with enhanced security
  Future<AuthResult> _reauthenticateWithGoogle(User user) async {
    try {
      // Force sign out to ensure fresh authentication
      await _googleSignIn.signOut();
      await _googleSignIn.disconnect(); // Complete disconnect

      // Configure Google Sign In for fresh authentication
      final GoogleSignIn freshGoogleSignIn = GoogleSignIn(
        forceCodeForRefreshToken: true,
        scopes: ['email', 'profile'],
      );

      // Initiate sign in with account picker
      final GoogleSignInAccount? googleUser = await freshGoogleSignIn.signIn();

      if (googleUser == null) {
        return AuthResult.failure('Authentication was cancelled');
      }

      // Verify same account
      if (googleUser.email != user.email) {
        await freshGoogleSignIn.signOut();
        return AuthResult.failure(
            'Please authenticate with the same Google account (${_maskEmail(user.email!)})');
      }

      // Get fresh authentication tokens
      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      if (googleAuth.accessToken == null || googleAuth.idToken == null) {
        return AuthResult.failure('Failed to obtain authentication tokens');
      }

      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      // Perform re-authentication
      await user.reauthenticateWithCredential(credential);

      // Verify token freshness (should be recent)
      final tokenResult = await user.getIdTokenResult(true);
      final tokenAge = DateTime.now().difference(tokenResult.authTime!);

      if (tokenAge > Duration(minutes: 5)) {
        return AuthResult.failure('Authentication token is not fresh enough');
      }

      return AuthResult.success('Google authentication successful');
    } catch (e) {
      return AuthResult.failure(_getErrorMessage(e));
    }
  }

  /// Password re-authentication with secure input
  Future<AuthResult> _reauthenticateWithPassword(
      BuildContext context, User user) async {
    final TextEditingController passwordController = TextEditingController();
    bool obscurePassword = true;
    bool isLoading = false;

    final result = await showDialog<AuthResult>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          backgroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(Icons.security, color: Colors.amber.shade800),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Confirm Your Identity',
                  style: TextStyle(
                    color: Colors.indigo.shade900,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Please enter your password to confirm this sensitive operation.',
                style: TextStyle(color: Colors.grey.shade700),
              ),
              SizedBox(height: 16),
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.email, color: Colors.blue.shade800, size: 16),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _maskEmail(user.email!),
                        style: TextStyle(
                          color: Colors.blue.shade800,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 12),
              TextField(
                controller: passwordController,
                obscureText: obscurePassword,
                enabled: !isLoading,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Password',
                  hintText: 'Enter your account password',
                  prefixIcon: Icon(Icons.lock),
                  suffixIcon: IconButton(
                    icon: Icon(obscurePassword
                        ? Icons.visibility
                        : Icons.visibility_off),
                    onPressed: () =>
                        setState(() => obscurePassword = !obscurePassword),
                  ),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8)),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide:
                        BorderSide(color: Colors.indigo.shade700, width: 2),
                  ),
                ),
                onSubmitted: isLoading
                    ? null
                    : (value) async {
                        if (value.trim().isNotEmpty) {
                          setState(() => isLoading = true);
                          final authResult =
                              await _performPasswordReauth(user, value.trim());
                          if (context.mounted) {
                            Navigator.pop(context, authResult);
                          }
                        }
                      },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: isLoading
                  ? null
                  : () => Navigator.pop(
                      context, AuthResult.failure('Authentication cancelled')),
              child: Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: isLoading || passwordController.text.trim().isEmpty
                  ? null
                  : () async {
                      setState(() => isLoading = true);
                      final authResult = await _performPasswordReauth(
                          user, passwordController.text.trim());
                      if (context.mounted) {
                        Navigator.pop(context, authResult);
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigo.shade900,
                foregroundColor: Colors.white,
              ),
              child: isLoading
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : Text('Confirm'),
            ),
          ],
        ),
      ),
    );

    return result ?? AuthResult.failure('Authentication cancelled');
  }

  /// Perform password re-authentication
  Future<AuthResult> _performPasswordReauth(User user, String password) async {
    try {
      final credential = EmailAuthProvider.credential(
        email: user.email!,
        password: password,
      );

      await user.reauthenticateWithCredential(credential);
      return AuthResult.success('Password authentication successful');
    } catch (e) {
      return AuthResult.failure(_getErrorMessage(e));
    }
  }

  /// Check if user is rate limited
  bool _isRateLimited(String uid) {
    final tracker = _attemptTrackers[uid];
    if (tracker == null) return false;

    if (tracker.attempts >= maxAuthAttempts) {
      final cooldownEnd = tracker.lastAttempt.add(authCooldownDuration);
      if (DateTime.now().isBefore(cooldownEnd)) {
        return true;
      } else {
        // Reset after cooldown
        _attemptTrackers.remove(uid);
        return false;
      }
    }
    return false;
  }

  /// Get remaining cooldown time in minutes
  int _getRemainingCooldown(String uid) {
    final tracker = _attemptTrackers[uid];
    if (tracker == null) return 0;

    final cooldownEnd = tracker.lastAttempt.add(authCooldownDuration);
    final remaining = cooldownEnd.difference(DateTime.now());
    return remaining.inMinutes.clamp(0, authCooldownDuration.inMinutes);
  }

  /// Check if recent authentication is still valid
  bool _isRecentAuthValid(String uid) {
    final lastAuth = _lastAuthTimes[uid];
    if (lastAuth == null) return false;

    final validUntil = lastAuth.add(sessionValidityDuration);
    return DateTime.now().isBefore(validUntil);
  }

  /// Record successful authentication
  void _recordSuccessfulAuth(String uid) {
    _lastAuthTimes[uid] = DateTime.now();
    _attemptTrackers.remove(uid); // Reset failed attempts
  }

  /// Record failed authentication attempt
  void _recordFailedAuth(String uid) {
    final tracker = _attemptTrackers[uid] ?? AuthAttemptTracker();
    tracker.attempts++;
    tracker.lastAttempt = DateTime.now();
    _attemptTrackers[uid] = tracker;
  }

  /// Show loading dialog
  void _showAuthLoadingDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text(
              'Authenticating...',
              style: TextStyle(color: Colors.grey.shade700),
            ),
            SizedBox(height: 8),
            Text(
              'Please complete the authentication process',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  /// Show success message
  void _showSuccessMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.check_circle, color: Colors.white),
            SizedBox(width: 8),
            Text(message),
          ],
        ),
        backgroundColor: Colors.green.shade600,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: EdgeInsets.all(16),
      ),
    );
  }

  /// Show error message
  void _showErrorMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.error, color: Colors.white),
            SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.red.shade600,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: EdgeInsets.all(16),
        duration: Duration(seconds: 5),
      ),
    );
  }

  /// Mask email for security display
  String _maskEmail(String email) {
    final parts = email.split('@');
    if (parts.length != 2) return email;

    final username = parts[0];
    final domain = parts[1];

    if (username.length <= 2) return email;

    final maskedUsername =
        username.substring(0, 2) + '*' * (username.length - 2);

    return '$maskedUsername@$domain';
  }

  /// Get user-friendly error message
  String _getErrorMessage(dynamic error) {
    final errorString = error.toString().toLowerCase();

    if (errorString.contains('network-request-failed')) {
      return 'Network error. Please check your internet connection and try again.';
    } else if (errorString.contains('user-disabled')) {
      return 'This account has been disabled. Please contact support.';
    } else if (errorString.contains('wrong-password')) {
      return 'Incorrect password. Please try again.';
    } else if (errorString.contains('invalid-credential')) {
      return 'Authentication failed. Please check your credentials.';
    } else if (errorString.contains('too-many-requests')) {
      return 'Too many failed attempts. Please wait before trying again.';
    } else if (errorString.contains('user-token-expired')) {
      return 'Your session has expired. Please sign in again.';
    } else if (errorString.contains('requires-recent-login')) {
      return 'This operation requires recent authentication. Please try again.';
    }

    return 'Authentication failed. Please try again.';
  }

  /// Clear authentication cache (call on logout)
  static void clearAuthCache(String uid) {
    _lastAuthTimes.remove(uid);
    _attemptTrackers.remove(uid);
  }

  /// Clear all authentication caches
  static void clearAllAuthCaches() {
    _lastAuthTimes.clear();
    _attemptTrackers.clear();
  }
}

/// Authentication result wrapper
class AuthResult {
  final bool isSuccess;
  final String? error;
  final String? message;

  AuthResult._(this.isSuccess, this.error, this.message);

  factory AuthResult.success(String message) =>
      AuthResult._(true, null, message);
  factory AuthResult.failure(String error) => AuthResult._(false, error, null);
}

/// Track authentication attempts for rate limiting
class AuthAttemptTracker {
  int attempts = 0;
  DateTime lastAttempt = DateTime.now();
}

/// Enhanced merchant details update method
class EnhancedMerchantUpdate {
  final EnhancedAuthService _authService = EnhancedAuthService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Future<void> updateMerchantDetailsSecure(
    BuildContext context, {
    required String merchantName,
    required String upiId,
    required String businessDescription,
    required Function(String, {bool isError}) showMessage,
    required Function(bool) setLoading,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      showMessage('No user logged in', isError: true);
      return;
    }

    // Input validation
    final validationResult = _validateInputs(merchantName, upiId);
    if (validationResult != null) {
      showMessage(validationResult, isError: true);
      return;
    }

    // Show confirmation dialog
    final confirmed = await _showUpdateConfirmationDialog(
      context,
      merchantName: merchantName,
      upiId: upiId,
      businessDescription: businessDescription,
    );

    if (!confirmed) return;

    // Perform authentication
    final authResult = await _authService.reauthenticateUser(context);
    if (!authResult.isSuccess) {
      showMessage(authResult.error!, isError: true);
      return;
    }

    setLoading(true);

    try {
      // Create update data with additional metadata
      final updateData = {
        'merchantName': merchantName.trim(),
        'upiId': upiId.trim().toLowerCase(),
        'businessDescription': businessDescription.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': user.uid,
        'lastUpdateIP': await _getClientIP(), // Optional: for audit trail
        'updateVersion': DateTime.now().millisecondsSinceEpoch,
      };

      // Perform atomic update with transaction
      await _firestore.runTransaction((transaction) async {
        final merchantRef = _firestore.collection('merchants').doc(user.uid);

        // Read current data
        final currentDoc = await transaction.get(merchantRef);

        // Verify user still has permission (additional security check)
        if (currentDoc.exists) {
          final currentData = currentDoc.data() as Map<String, dynamic>;
          if (currentData['owner'] != null &&
              currentData['owner'] != user.uid) {
            throw Exception(
                'Permission denied: You are not the owner of this merchant account');
          }
        }

        // Update with merge to preserve other fields
        transaction.set(merchantRef, updateData, SetOptions(merge: true));

        // Optional: Log the update for audit trail
        transaction.set(
          _firestore.collection('merchantUpdateLogs').doc(),
          {
            'merchantId': user.uid,
            'updatedFields': ['merchantName', 'upiId', 'businessDescription'],
            'timestamp': FieldValue.serverTimestamp(),
            'userAgent': 'Flutter App', // You can make this more specific
          },
        );
      });

      showMessage('Business details updated successfully!');

      // Show success dialog and redirect
      await _showSuccessDialog(context);
    } catch (e) {
      showMessage('Failed to update details: ${_getUpdateErrorMessage(e)}',
          isError: true);
    } finally {
      setLoading(false);
    }
  }

  /// Validate merchant inputs
  String? _validateInputs(String merchantName, String upiId) {
    if (merchantName.trim().isEmpty) {
      return 'Merchant name is required';
    }

    if (merchantName.trim().length < 2) {
      return 'Merchant name must be at least 2 characters long';
    }

    if (upiId.trim().isEmpty) {
      return 'UPI ID is required';
    }

    // Enhanced UPI ID validation
    final upiPattern = RegExp(r'^[a-zA-Z0-9._-]+@[a-zA-Z0-9.-]+$');
    if (!upiPattern.hasMatch(upiId.trim())) {
      return 'Please enter a valid UPI ID (e.g., merchant@paytm)';
    }

    // Check for common UPI providers
    final validProviders = [
      'paytm',
      'googlepay',
      'phonepe',
      'ybl',
      'ibl',
      'axl',
      'oksbi',
      'upi'
    ];
    final domain = upiId.trim().split('@')[1].toLowerCase();
    final isValidProvider =
        validProviders.any((provider) => domain.contains(provider));

    if (!isValidProvider) {
      return 'Please use a valid UPI provider (PayTM, Google Pay, PhonePe, etc.)';
    }

    return null;
  }

  /// Show update confirmation dialog
  Future<bool> _showUpdateConfirmationDialog(
    BuildContext context, {
    required String merchantName,
    required String upiId,
    required String businessDescription,
  }) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: Colors.white,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                Icon(Icons.security, color: Colors.amber.shade800),
                SizedBox(width: 12),
                Text(
                  'Confirm Update',
                  style: TextStyle(
                    color: Colors.indigo.shade900,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'You are about to update your business details:',
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
                  SizedBox(height: 16),
                  _buildPreviewCard('Business Name', merchantName),
                  SizedBox(height: 8),
                  _buildPreviewCard('UPI ID', upiId),
                  if (businessDescription.isNotEmpty) ...[
                    SizedBox(height: 8),
                    _buildPreviewCard('Description', businessDescription),
                  ],
                  SizedBox(height: 16),
                  Container(
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.amber.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.lock,
                            color: Colors.amber.shade800, size: 20),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'You will need to authenticate to confirm this sensitive operation.',
                            style: TextStyle(
                              color: Colors.amber.shade800,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo.shade900,
                  foregroundColor: Colors.white,
                ),
                child: Text('Continue'),
              ),
            ],
          ),
        ) ??
        false;
  }

  /// Build preview card for confirmation dialog
  Widget _buildPreviewCard(String label, String value) {
    return Container(
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: Colors.grey.shade900,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  /// Show success dialog
  Future<void> _showSuccessDialog(BuildContext context) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green.shade600, size: 28),
            SizedBox(width: 12),
            Text(
              'Success!',
              style: TextStyle(
                color: Colors.green.shade600,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: Text(
          'Your business details have been updated successfully. You will be redirected to the main page.',
          style: TextStyle(color: Colors.grey.shade700),
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.of(context)
                  .pushNamedAndRemoveUntil('/main', (route) => false);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green.shade600,
              foregroundColor: Colors.white,
            ),
            child: Text('Continue'),
          ),
        ],
      ),
    );
  }

  /// Get client IP for audit trail (optional)
  Future<String> _getClientIP() async {
    // In a real app, you might want to get the actual client IP
    // For now, return a placeholder
    return 'mobile-app';
  }

  /// Get user-friendly update error message
  String _getUpdateErrorMessage(dynamic error) {
    final errorString = error.toString().toLowerCase();

    if (errorString.contains('permission')) {
      return 'You do not have permission to update this merchant account.';
    } else if (errorString.contains('network')) {
      return 'Network error. Please check your connection and try again.';
    } else if (errorString.contains('firestore')) {
      return 'Database error. Please try again in a moment.';
    }

    return 'An unexpected error occurred. Please try again.';
  }
}
 