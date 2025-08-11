import 'package:flutter/material.dart';
import 'package:PayPro/signuppage.dart';
import 'package:PayPro/emplylogin.dart';

class WelcomePage extends StatelessWidget {
  const WelcomePage({super.key});

  // Color Scheme matching QR Generation Page
  static const Color primaryDarkGray = Color(0xFF37474F);
  static const Color secondaryGray = Color(0xFF455A64);
  static const Color darkTeal = Color(0xFF00695C);
  static const Color lightGray = Color(0xFFF5F5F5);
  static const Color mediumGray = Color(0xFF90A4AE);
  static const Color successGreen = Color(0xFF4CAF50);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: lightGray,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // App Logo/Title
              Icon(
                Icons.qr_code_rounded,
                size: 80,
                color: Colors.indigo.shade900,
              ),
              const SizedBox(height: 24),

              // Welcome Text
              Text(
                'Welcome to PayPro',
                style: TextStyle(
                  color: Colors.indigo.shade900,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'Choose your login type to continue',
                style: TextStyle(
                  color: secondaryGray,
                  fontSize: 16,
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 60),

              // Merchant Login Button
              _buildLoginButton(
                context: context,
                title: 'Merchant Login',
                subtitle: 'Access merchant dashboard',
                icon: Icons.business,
                color: Colors.indigo.shade900,
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const SignupPage()),
                ),
              ),

              const SizedBox(height: 20),

              // Employee Login Button
              _buildLoginButton(
                context: context,
                title: 'Employee Login',
                subtitle: 'Access employee dashboard',
                icon: Icons.person,
                color: Colors.indigo.shade900,
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) => const EmployeeLoginPage()),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoginButton({
    required BuildContext context,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return Container(
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
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: color.withOpacity(0.3)),
                  ),
                  child: Icon(
                    icon,
                    color: color,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: Colors.indigo.shade900,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: secondaryGray,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.arrow_forward_ios,
                  color: mediumGray,
                  size: 16,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
