import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // Add this
import 'firebase_options.dart';
import 'package:PayPro/mainpage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:PayPro/signuppage.dart';
import 'package:PayPro/qrgeneration.dart';
import 'package:PayPro/welcomepage.dart';
import 'dart:async';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Enable offline persistence explicitly (optional, enabled by default)
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: AuthGate(),
    );
  }
}

// Add this WelcomePage class
class LoadingPage extends StatelessWidget {
  const LoadingPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF667eea),
              Color(0xFF764ba2),
            ],
          ),
        ),
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.qr_code_2,
                size: 100,
                color: Colors.white,
              ),
              SizedBox(height: 24),
              Text(
                'PayPro',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'Your Payment Solution',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.white70,
                ),
              ),
              SizedBox(height: 40),
              CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Updated AuthGate class
// Updated AuthGate class with 2-second welcome screen
// Alternative AuthGate - Shows welcome screen only for returning users
class AuthGate extends StatefulWidget {
  @override
  _AuthGateState createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _showWelcome = false;
  bool _initialCheckDone = false;

  @override
  void initState() {
    super.initState();
    _checkInitialAuthState();
  }

  void _checkInitialAuthState() {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      // User is already signed in, show welcome screen
      setState(() {
        _showWelcome = true;
      });

      // Hide welcome screen after 2 seconds
      Timer(Duration(seconds: 2), () {
        if (mounted) {
          setState(() {
            _showWelcome = false;
            _initialCheckDone = true;
          });
        }
      });
    } else {
      // No user signed in, skip welcome screen
      setState(() {
        _initialCheckDone = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_showWelcome) {
      return const LoadingPage();
    }

    if (!_initialCheckDone) {
      return const LoadingPage();
    }

    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const LoadingPage();
        } else if (snapshot.hasData) {
          final user = snapshot.data!;
          return FutureBuilder<DocumentSnapshot>(
            future: FirebaseFirestore.instance
                .collection('merchants')
                .doc(user.uid)
                .get(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const LoadingPage();
              }

              if (!snapshot.hasData || !snapshot.data!.exists) {
                return const MainPage();
              }

              final data = snapshot.data!.data() as Map<String, dynamic>;
              return QRGenerationPage(
                merchantName: data['merchantName'] ?? 'Unnamed Store',
                upiId: data['upiId'] ?? 'no@upi',
              );
            },
          );
        } else {
          return const WelcomePage(); // User not signed in
        }
      },
    );
  }
}
