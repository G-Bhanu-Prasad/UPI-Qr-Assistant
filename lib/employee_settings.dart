import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:intl/intl.dart';
import 'transactionspage.dart';

class EmployeeSettingsPage extends StatefulWidget {
  const EmployeeSettingsPage({super.key});

  @override
  State<EmployeeSettingsPage> createState() => _EmployeeSettingsPageState();
}

class _EmployeeSettingsPageState extends State<EmployeeSettingsPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Updated Color Scheme matching Employee Login Page
  static const Color primaryDarkGray = Color(0xFF37474F);
  static const Color secondaryGray = Color(0xFF455A64);
  static const Color darkTeal = Color(0xFF00695C);
  static const Color lightGray = Color(0xFFF5F5F5);
  static const Color mediumGray = Color(0xFF90A4AE);
  static const Color successGreen = Color(0xFF4CAF50);

  // Employee data
  String? _employeeId;
  String? _employeeName;
  String? _employeeRole;
  String? _merchantId;
  String? _merchantName;
  bool _isActive = true;
  DateTime? _createdAt;

  // Transactions data
  List<Map<String, dynamic>> _transactions = [];
  bool _isLoadingTransactions = true;
  bool _isLoadingProfile = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadEmployeeProfile();
    _loadTransactions();
  }

  @override
  void dispose() {
    _tabController.dispose();
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
        duration: const Duration(seconds: 4),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  Future<void> _loadEmployeeProfile() async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();

      setState(() {
        _employeeId = prefs.getString('currentEmployeeId') ?? 'EMP123456';
        _employeeName = prefs.getString('currentEmployeeName') ?? 'John Doe';
        _employeeRole = prefs.getString('currentEmployeeRole') ?? 'Staff';
        _merchantId = prefs.getString('currentMerchantId') ?? '';
        _merchantName = prefs.getString('currentMerchantName') ?? 'Demo Store';
        _isActive = prefs.getBool('currentEmployeeActive') ?? true;
        _createdAt = DateTime.now();
        _isLoadingProfile = false;
      });
    } catch (e) {
      setState(() {
        _isLoadingProfile = false;
      });
      _showMessage('Error loading profile: $e', isError: true);
    }
  }

  Future<void> _refreshTransactions() async {
    await _loadTransactions();
  }

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

  Future<void> _logout() async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.remove('currentEmployeeId');
      await prefs.remove('currentEmployeeName');
      await prefs.remove('currentEmployeeRole');
      await prefs.remove('currentMerchantId');
      await prefs.remove('currentMerchantName');
      await prefs.remove('currentEmployeeActive');

      _showMessage('Logged out successfully');
      Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
    } catch (e) {
      _showMessage('Error signing out: $e', isError: true);
    }
  }

  Widget _buildCard(
      {required Widget child, EdgeInsets? padding, EdgeInsets? margin}) {
    return Container(
      margin: margin ?? const EdgeInsets.only(bottom: 20),
      padding: padding ?? const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: mediumGray.withOpacity(0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 20,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _buildProfileTab() {
    return Container(
      //color: Colors.grey.shade50,
      child: _isLoadingProfile
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  // Simple Profile Card
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(32),
                    margin: const EdgeInsets.only(bottom: 24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.04),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        // Simple Avatar
                        Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.person_outline,
                            size: 40,
                            color: Colors.indigo.shade900,
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Name
                        Text(
                          _employeeName ?? 'Loading...',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w600,
                            color: Colors.indigo.shade900,
                          ),
                        ),
                        const SizedBox(height: 8),

                        // Role & Status
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              _employeeRole ?? 'Staff',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey.shade600,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Container(
                              width: 4,
                              height: 4,
                              decoration: BoxDecoration(
                                color: Colors.grey.shade400,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: _isActive
                                    ? Colors.green.shade50
                                    : Colors.red.shade50,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                _isActive ? 'Active' : 'Inactive',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: _isActive
                                      ? Colors.green.shade700
                                      : Colors.red.shade700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Details Card
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    margin: const EdgeInsets.only(bottom: 24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.04),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Details',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: Colors.indigo.shade900,
                          ),
                        ),
                        const SizedBox(height: 20),
                        _buildSimpleDetailRow(
                            'Employee ID', _employeeId ?? 'Loading...'),
                        _buildSimpleDetailRow(
                            'Business', _merchantName ?? 'Loading...'),
                        _buildSimpleDetailRow(
                          'Joined',
                          _createdAt != null
                              ? DateFormat('MMM dd, yyyy').format(_createdAt!)
                              : 'Recently',
                          isLast: true,
                        ),
                      ],
                    ),
                  ),

                  // Container(
                  //   width: ,
                  //   margin: const EdgeInsets.only(right: 16),
                  //   decoration: BoxDecoration(
                  //     color: Colors.red.shade50,
                  //     borderRadius: BorderRadius.circular(8),
                  //     border: Border.all(color: Colors.red.withOpacity(0.3)),
                  //   ),
                  //   child: TextButton.icon(
                  //     onPressed: _logout,
                  //     icon:
                  //         const Icon(Icons.logout, color: Colors.red, size: 18),
                  //     label: const Text(
                  //       'Logout',
                  //       style: TextStyle(
                  //           color: Colors.red, fontWeight: FontWeight.w600),
                  //     ),
                  //   ),
                  // ),

                  // Stats Card
                  // Container(
                  //   width: double.infinity,
                  //   padding: const EdgeInsets.all(24),
                  //   decoration: BoxDecoration(
                  //     color: Colors.white,
                  //     borderRadius: BorderRadius.circular(16),
                  //     boxShadow: [
                  //       BoxShadow(
                  //         color: Colors.black.withOpacity(0.04),
                  //         blurRadius: 10,
                  //         offset: const Offset(0, 2),
                  //       ),
                  //     ],
                  //   ),
                  //   child: Column(
                  //     crossAxisAlignment: CrossAxisAlignment.start,
                  //     children: [
                  //       const Text(
                  //         'Statistics',
                  //         style: TextStyle(
                  //           fontSize: 18,
                  //           fontWeight: FontWeight.w600,
                  //           color: Color(0xFF1a1a1a),
                  //         ),
                  //       ),
                  //       const SizedBox(height: 20),
                  //       Row(
                  //         children: [
                  //           Expanded(
                  //             child: Column(
                  //               crossAxisAlignment: CrossAxisAlignment.start,
                  //               children: [
                  //                 Text(
                  //                   'Today\'s Sales',
                  //                   style: TextStyle(
                  //                     fontSize: 14,
                  //                     color: Colors.grey.shade600,
                  //                   ),
                  //                 ),
                  //                 const SizedBox(height: 8),
                  //                 Text(
                  //                   '${_getTodayTransactionCount()}',
                  //                   style: const TextStyle(
                  //                     fontSize: 28,
                  //                     fontWeight: FontWeight.w700,
                  //                     color: Color(0xFF1a1a1a),
                  //                   ),
                  //                 ),
                  //               ],
                  //             ),
                  //           ),
                  //           Container(
                  //             width: 1,
                  //             height: 40,
                  //             color: Colors.grey.shade200,
                  //           ),
                  //           Expanded(
                  //             child: Column(
                  //               crossAxisAlignment: CrossAxisAlignment.end,
                  //               children: [
                  //                 Text(
                  //                   'Total Revenue',
                  //                   style: TextStyle(
                  //                     fontSize: 14,
                  //                     color: Colors.grey.shade600,
                  //                   ),
                  //                 ),
                  //                 const SizedBox(height: 8),
                  //                 Text(
                  //                   '₹${_getTotalAmount().toStringAsFixed(0)}',
                  //                   style: const TextStyle(
                  //                     fontSize: 28,
                  //                     fontWeight: FontWeight.w700,
                  //                     color: Color(0xFF1a1a1a),
                  //                   ),
                  //                 ),
                  //               ],
                  //             ),
                  //           ),
                  //         ],
                  //       ),
                  //     ],
                  //   ),
                  //),
                ],
              ),
            ),
    );
  }

  Widget _buildSimpleDetailRow(String label, String value,
      {bool isLast = false}) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w500,
            ),
          ),
          Flexible(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 14,
                color: Colors.indigo.shade900,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionsTab() {
    return Container(
      color: lightGray,
      child: _isLoadingTransactions
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(15),
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
                              const Text(
                                'Total Revenue',
                                style: TextStyle(
                                  color: secondaryGray,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '₹${_getTotalAmount().toStringAsFixed(2)}',
                                style: TextStyle(
                                  color: Colors.indigo.shade900,
                                  fontSize: 22,
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
                              const Text(
                                'Today\'s Transactions',
                                style: TextStyle(
                                  color: secondaryGray,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                                textAlign: TextAlign.end,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${_getTodayTransactionCount()}',
                                style: const TextStyle(
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

                  // Transactions List Card
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

  Widget _buildInfoCard({
    required String title,
    required IconData icon,
    required Widget content,
    Color? iconColor,
  }) {
    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: (iconColor ?? Colors.indigo.shade900).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color:
                        (iconColor ?? Colors.indigo.shade900).withOpacity(0.3),
                  ),
                ),
                child: Icon(
                  icon,
                  color: iconColor ?? Colors.indigo.shade900,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                title,
                style: TextStyle(
                  color: Colors.indigo.shade900,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          content,
        ],
      ),
    );
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
        title: Text(
          'Employee Settings',
          style: TextStyle(
            color: Colors.indigo.shade900,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
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
            color: lightGray,
            child: TabBar(
              controller: _tabController,
              indicatorColor: Colors.indigo.shade900,
              labelColor: Colors.indigo.shade900,
              unselectedLabelColor: mediumGray,
              indicatorWeight: 3,
              labelStyle: const TextStyle(fontWeight: FontWeight.w600),
              tabs: const [
                Tab(
                  icon: Icon(Icons.person),
                  text: 'Profile',
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
          _buildProfileTab(),
          _buildTransactionsTab(),
        ],
      ),
    );
  }
}
