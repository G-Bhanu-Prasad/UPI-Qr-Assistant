import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:intl/intl.dart';

class TransactionsPage extends StatefulWidget {
  const TransactionsPage({super.key});

  @override
  State<TransactionsPage> createState() => _TransactionsPageState();
}

class _TransactionsPageState extends State<TransactionsPage> {
  List<Map<String, dynamic>> _transactions = [];
  List<Map<String, dynamic>> _filteredTransactions = [];
  bool _isLoading = true;
  String _selectedFilter = 'All';
  final TextEditingController _searchController = TextEditingController();

  // Color Scheme
  static const Color primaryDarkGray = Color(0xFF37474F);
  static const Color secondaryGray = Color(0xFF455A64);
  static const Color darkTeal = Color(0xFF00695C);
  static const Color lightGray = Color(0xFFF5F5F5);
  static const Color mediumGray = Color(0xFF90A4AE);
  static const Color successGreen = Color(0xFF4CAF50);

  @override
  void initState() {
    super.initState();
    _loadTransactions();
    _searchController.addListener(_filterTransactions);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadTransactions() async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String? transactionsJson = prefs.getString('transactions');

      if (transactionsJson != null) {
        List<dynamic> decoded = json.decode(transactionsJson);
        setState(() {
          _transactions = decoded.cast<Map<String, dynamic>>();
          _filteredTransactions = List.from(_transactions);
          _isLoading = false;
        });
      } else {
        setState(() {
          _transactions = [];
          _filteredTransactions = [];
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      _showMessage('Error loading transactions: $e', isError: true);
    }
  }

  void _filterTransactions() {
    String query = _searchController.text.toLowerCase();
    List<Map<String, dynamic>> filtered = _transactions.where((transaction) {
      bool matchesSearch = transaction['merchantName']
              .toString()
              .toLowerCase()
              .contains(query) ||
          transaction['amount'].toString().contains(query);

      bool matchesFilter = _selectedFilter == 'All' ||
          (_selectedFilter == 'Today' && _isToday(transaction['timestamp'])) ||
          (_selectedFilter == 'This Week' &&
              _isThisWeek(transaction['timestamp'])) ||
          (_selectedFilter == 'This Month' &&
              _isThisMonth(transaction['timestamp']));

      return matchesSearch && matchesFilter;
    }).toList();

    setState(() {
      _filteredTransactions = filtered;
    });
  }

  bool _isToday(String timestamp) {
    DateTime transactionDate = DateTime.parse(timestamp);
    DateTime now = DateTime.now();
    return transactionDate.day == now.day &&
        transactionDate.month == now.month &&
        transactionDate.year == now.year;
  }

  bool _isThisWeek(String timestamp) {
    DateTime transactionDate = DateTime.parse(timestamp);
    DateTime now = DateTime.now();
    DateTime startOfWeek = now.subtract(Duration(days: now.weekday - 1));
    return transactionDate
        .isAfter(startOfWeek.subtract(const Duration(days: 1)));
  }

  bool _isThisMonth(String timestamp) {
    DateTime transactionDate = DateTime.parse(timestamp);
    DateTime now = DateTime.now();
    return transactionDate.month == now.month &&
        transactionDate.year == now.year;
  }

  double _getTotalAmount() {
    return _filteredTransactions.fold(0.0, (sum, transaction) {
      return sum + double.parse(transaction['amount'].toString());
    });
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

  Future<void> _clearAllTransactions() async {
    bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Clear All Transactions',
          style: TextStyle(
            color: Colors.red[700],
            fontWeight: FontWeight.bold,
          ),
        ),
        content: const Text(
          'Are you sure you want to delete all transaction history? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red[700],
              foregroundColor: Colors.white,
            ),
            child: const Text('Clear All'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        SharedPreferences prefs = await SharedPreferences.getInstance();
        await prefs.remove('transactions');
        await prefs.remove('lastTransaction');

        setState(() {
          _transactions.clear();
          _filteredTransactions.clear();
        });

        _showMessage('All transactions cleared successfully!');

        // Add this line to navigate back and signal that data was cleared
        Navigator.pop(
            context, true); // Return true to indicate transactions were cleared
      } catch (e) {
        _showMessage('Error clearing transactions: $e', isError: true);
      }
    }
  }

  void _showTransactionDetails(Map<String, dynamic> transaction) {
    DateTime transactionDate = DateTime.parse(transaction['timestamp']);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Transaction Details',
          style: TextStyle(
            color: Colors.indigo.shade900,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDetailRow('Transaction ID:', transaction['id']),
            _buildDetailRow('Merchant:', transaction['merchantName']),
            _buildDetailRow('Amount:', '₹${transaction['amount']}'),
            _buildDetailRow('UPI ID:', transaction['upiId']),
            _buildDetailRow(
                'Date:', DateFormat('MMM dd, yyyy').format(transactionDate)),
            _buildDetailRow(
                'Time:', DateFormat('hh:mm a').format(transactionDate)),
            _buildDetailRow(
                'Status:', transaction['status'].toString().toUpperCase()),
            _buildDetailRow('Payment Method:', transaction['paymentMethod']),
            if (transaction['isEmployee'] == true)
              _buildDetailRow('Employee Transaction:', 'Yes'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(
                color: secondaryGray,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: primaryDarkGray,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Total Amount',
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
                      overflow: TextOverflow.visible,
                    ),
                  ],
                ),
              ),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'Transactions',
                      style: TextStyle(
                        color: secondaryGray,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      '${_filteredTransactions.length}',
                      style: TextStyle(
                        color: successGreen,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildFilterChips() {
    List<String> filters = ['All', 'Today', 'This Week', 'This Month'];

    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: filters.length,
        itemBuilder: (context, index) {
          String filter = filters[index];
          bool isSelected = _selectedFilter == filter;

          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: Text(filter),
              selected: isSelected,
              onSelected: (selected) {
                setState(() {
                  _selectedFilter = filter;
                });
                _filterTransactions();
              },
              selectedColor: Colors.indigo.shade100,
              checkmarkColor: Colors.indigo.shade900,
              labelStyle: TextStyle(
                color: isSelected ? Colors.indigo.shade900 : secondaryGray,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildTransactionsList() {
    if (_filteredTransactions.isEmpty) {
      return Expanded(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.receipt_long_outlined,
                size: 64,
                color: mediumGray,
              ),
              const SizedBox(height: 16),
              Text(
                'No transactions found',
                style: TextStyle(
                  color: secondaryGray,
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _transactions.isEmpty
                    ? 'Start accepting payments to see transactions here'
                    : 'Try adjusting your search or filter',
                style: TextStyle(
                  color: mediumGray,
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return Expanded(
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _filteredTransactions.length,
        itemBuilder: (context, index) {
          Map<String, dynamic> transaction = _filteredTransactions[index];
          DateTime transactionDate = DateTime.parse(transaction['timestamp']);

          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: mediumGray.withOpacity(0.2)),
              boxShadow: [
                BoxShadow(
                  color: secondaryGray.withOpacity(0.05),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: InkWell(
              onTap: () => _showTransactionDetails(transaction),
              borderRadius: BorderRadius.circular(12),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: successGreen.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.payment,
                      color: successGreen,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          transaction['merchantName'],
                          style: TextStyle(
                            color: primaryDarkGray,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          DateFormat('MMM dd, yyyy • hh:mm a')
                              .format(transactionDate),
                          style: TextStyle(
                            color: secondaryGray,
                            fontSize: 12,
                          ),
                        ),
                        if (transaction['isEmployee'] == true) ...[
                          const SizedBox(height: 2),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: darkTeal.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'Employee',
                              style: TextStyle(
                                color: darkTeal,
                                fontSize: 10,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '₹${transaction['amount']}',
                        style: TextStyle(
                          color: successGreen,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: successGreen.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          transaction['status'].toString().toUpperCase(),
                          style: TextStyle(
                            color: successGreen,
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
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
          'Transactions',
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
          if (_transactions.isNotEmpty)
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert, color: Colors.indigo.shade900),
              color: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              onSelected: (value) {
                if (value == 'clear') {
                  _clearAllTransactions();
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'clear',
                  child: Row(
                    children: [
                      Icon(Icons.clear_all, color: Colors.red, size: 20),
                      SizedBox(width: 8),
                      Text('Clear All', style: TextStyle(color: Colors.red)),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (_transactions.isNotEmpty) ...[
                  _buildSummaryCard(),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'Search transactions...',
                        prefixIcon: Icon(Icons.search, color: mediumGray),
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding:
                            const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildFilterChips(),
                ],
                _buildTransactionsList(),
              ],
            ),
    );
  }
}
