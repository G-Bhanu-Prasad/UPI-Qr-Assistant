import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:PayPro/mainpage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:PayPro/main.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class SignupPage extends StatefulWidget {
  const SignupPage({super.key});

  @override
  State<SignupPage> createState() => _SignupPageState();
}

class _SignupPageState extends State<SignupPage> with TickerProviderStateMixin {
  bool _isLoading = false;
  bool _showAccountSelection = false;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  // Color Scheme matching QR Generation Page
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
    _pulseController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    );
    _pulseAnimation = Tween<double>(
      begin: 1.0,
      end: 1.1,
    ).animate(CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    ));
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  void _showAccountSelectionDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(30),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
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
              mainAxisSize: MainAxisSize.min,
              children: [
                // Animated Google Icon
                AnimatedBuilder(
                  animation: _pulseAnimation,
                  builder: (context, child) {
                    return Transform.scale(
                      scale: _pulseAnimation.value,
                      child: Container(
                        width: 60,
                        height: 60,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: lightGray,
                          borderRadius: BorderRadius.circular(12),
                          border:
                              Border.all(color: mediumGray.withOpacity(0.3)),
                        ),
                        child: Image.asset('lib/images/google.png'),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 20),
                Text(
                  'Choose Your Account',
                  style: TextStyle(
                    color: primaryDarkGray,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Google account selection will open shortly.\nPlease select the account you want to use.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: secondaryGray,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 20),
                CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(darkTeal),
                  strokeWidth: 2,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _signInWithGoogle() async {
    setState(() {
      _isLoading = true;
    });

    // Start pulse animation
    _pulseController.repeat(reverse: true);

    try {
      final GoogleSignIn googleSignIn = GoogleSignIn();

      // Force sign out to always show account selection
      await googleSignIn.signOut();

      // Prompt user to select an account
      final GoogleSignInAccount? googleUser = await googleSignIn.signIn();

      if (googleUser == null) {
        _showMessage('Google sign-in cancelled', isError: true);
        setState(() {
          _isLoading = false;
        });
        _pulseController.stop();
        return;
      }

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      // Sign in with Firebase
      final UserCredential userCredential =
          await FirebaseAuth.instance.signInWithCredential(credential);

      // Check if this is a new user
      if (userCredential.additionalUserInfo?.isNewUser == true) {
        // New user - create basic profile but don't create merchant data yet
        await FirebaseFirestore.instance
            .collection('users')
            .doc(userCredential.user!.uid)
            .set({
          'email': userCredential.user!.email,
          'displayName': userCredential.user!.displayName,
          'photoURL': userCredential.user!.photoURL,
          'createdAt': FieldValue.serverTimestamp(),
          'signInMethod': 'google',
        });
      }

      // Navigate directly to AuthGate - let it handle the welcome screen
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => AuthGate(),
          ),
        );
      }
    } on FirebaseAuthException catch (e) {
      _showMessage('Authentication Error: ${e.message}', isError: true);
    } catch (e) {
      _showMessage('Something went wrong. Please try again.', isError: true);
    } finally {
      setState(() {
        _isLoading = false;
      });
      _pulseController.stop();
    }
  }

  void _showSuccessDialog(GoogleSignInAccount user) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(30),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: successGreen.withOpacity(0.3)),
              boxShadow: [
                BoxShadow(
                  color: secondaryGray.withOpacity(0.1),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Success Icon
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: successGreen,
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: const Icon(
                    Icons.check,
                    color: Colors.white,
                    size: 30,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Welcome, ${user.displayName?.split(' ')[0] ?? 'User'}!',
                  style: TextStyle(
                    color: primaryDarkGray,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  user.email,
                  style: TextStyle(
                    color: secondaryGray,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Setting up your account...',
                  style: TextStyle(
                    color: mediumGray,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: lightGray,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 30),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // App Logo or Icon
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: mediumGray.withOpacity(0.3), width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: secondaryGray.withOpacity(0.1),
                        blurRadius: 20,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  child: Icon(
                    Icons.person_add_alt_1,
                    size: 60,
                    color: Colors.indigo.shade900,
                  ),
                ),

                const SizedBox(height: 50),

                // Welcome Text
                Text(
                  'Welcome!',
                  style: TextStyle(
                    color: Colors.indigo.shade900,
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),

                const SizedBox(height: 10),

                Text(
                  'Your merchant story starts here',
                  style: TextStyle(
                    color: secondaryGray,
                    fontSize: 16,
                    fontWeight: FontWeight.w300,
                  ),
                ),

                const SizedBox(height: 50),

                // Enhanced Google Sign Up Button
                Container(
                  width: double.infinity,
                  height: 56,
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
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: _isLoading ? null : _signInWithGoogle,
                      child: _isLoading
                          ? Center(
                              child: SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor:
                                      AlwaysStoppedAnimation<Color>(darkTeal),
                                ),
                              ),
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.transparent,
                                    borderRadius: BorderRadius.circular(8),
                                    border:
                                        Border.all(color: Colors.transparent),
                                  ),
                                  child: Image.asset(
                                    'lib/images/google.png',
                                    height: 20,
                                    width: 20,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  'Continue with Google',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.indigo.shade900,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                ),

                const SizedBox(height: 50),

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    'By continuing, you agree to our Terms of Service and Privacy Policy',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: mediumGray,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
