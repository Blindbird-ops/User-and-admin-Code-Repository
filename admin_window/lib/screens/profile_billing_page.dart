import 'package:admin_window/services/report_generator.dart';
import 'package:flutter/material.dart';
import 'package:admin_window/services/data_service.dart'; 
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart'; 
import 'dart:math';

enum ChartView { sevenDays, thisMonth, thisYear }

class ProfileBillingPage extends StatefulWidget {
  final String token;
  const ProfileBillingPage({super.key, required this.token});

  @override
  State<ProfileBillingPage> createState() => _ProfileBillingPageState();
}

class _ProfileBillingPageState extends State<ProfileBillingPage> {
  late DataService _dataService;
  bool _isGeneratingReport = false;

  bool _isLoading = true;
  String? _error; 
  List<Map<String, dynamic>> _allTransactions = [];
  List<Map<String, dynamic>> _filteredTransactions = [];
  
  double _totalEarnings = 0.0;
  double _averageTransaction = 0.0;
  int _transactionsToday = 0;
  List<BarChartGroupData> _chartData = [];
  Map<String, double> _incomeByType = {};
  double _currentMonthEarnings = 0.0;
  ChartView _selectedChartView = ChartView.sevenDays;

  late int _selectedYear;
  List<int> _availableYears = [];

  final currencyFormatter = NumberFormat.currency(locale: 'en_PH', symbol: '₱');
  final dateTimeFormatter = DateFormat('MMM d, yyyy • hh:mm a');

  @override
  void initState() {
    super.initState();
    _selectedYear = DateTime.now().year;
    _dataService = DataService(); 
    _fetchAndProcessData();
  }

  String _createFullName(Map<String, dynamic> userData) {
    final firstName = (userData['firstName'] ?? '').toString().trim();
    final middleName = (userData['middleName'] ?? '').toString().trim();
    final lastName = (userData['lastName'] ?? '').toString().trim();
    if (firstName.isEmpty && lastName.isEmpty) {
      return (userData['username'] ?? 'N/A').toString();
    }
    final nameParts = [firstName];
    if (middleName.isNotEmpty) {
      nameParts.add('${middleName[0]}.');
    }
    nameParts.add(lastName);
    return nameParts.where((part) => part.isNotEmpty).join(' ');
  }

  Future<void> _fetchAndProcessData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final results = await Future.wait([
        _dataService.getData('transactions'),
        _dataService.getData('users'),
      ]);

      if (!mounted) return;

      final transactionsData = results[0];
      final usersData = results[1];
      
      final Map<String, String> userNames = {};
      if (usersData != null) {
        usersData.forEach((userId, userData) {
          if (userData is Map) {
            userNames[userId] = _createFullName(Map<String, dynamic>.from(userData));
          }
        });
      }

      final List<Map<String, dynamic>> loadedTransactions = [];
      if (transactionsData != null) {
        transactionsData.forEach((key, value) {
          if (value is Map) {
            final transaction = Map<String, dynamic>.from(value);
            transaction['id'] = key;
            transaction['timestamp_dt'] = DateTime.tryParse(transaction['timestamp'] ?? '') ?? DateTime.now();
            
            final userId = transaction['userId']?.toString();
            
            // --- UPDATED NAME LOGIC ---
            String displayName = 'Unknown User';
            bool isOffline = false;

            // 1. Try Online User ID
            if (userId != null && userNames.containsKey(userId)) {
              displayName = userNames[userId]!;
            } 
            // 2. Try Transaction Name (Offline / Walk-in)
            else if (transaction['fullName'] != null && transaction['fullName'].toString().isNotEmpty) {
              displayName = transaction['fullName'];
              // If no userId but has fullName, it's likely offline/walk-in
              if (userId == null || userId == 'null') {
                isOffline = true;
              }
            }
            // 3. Fallback
            else if (transaction['userEmail'] != null) {
              displayName = transaction['userEmail'];
            }

            transaction['paidByName'] = displayName;
            transaction['isOffline'] = isOffline; // New Flag
            
            loadedTransactions.add(transaction);
          }
        });
      }
      loadedTransactions.sort((a, b) => (b['timestamp_dt'] as DateTime).compareTo(a['timestamp_dt'] as DateTime));

      final Set<int> years = {};
      for (var tx in loadedTransactions) {
        years.add((tx['timestamp_dt'] as DateTime).year);
      }
      
      List<int> finalYears;
      if (years.isNotEmpty) {
        finalYears = years.toList();
        finalYears.sort((a, b) => b.compareTo(a));
      } else {
        finalYears = [DateTime.now().year];
      }
      
      setState(() {
        _allTransactions = loadedTransactions;
        _availableYears = finalYears;
        if (!_availableYears.contains(_selectedYear)) {
          _selectedYear = _availableYears.first;
        }
        _error = null;
        _isLoading = false;
      });

      _calculateDashboardMetrics();

    } catch (e) {
      print("Failed to load billing data: $e");
    }
  }

  // ... (Keep existing calc methods: _calculateDashboardMetrics, _calculateIncomeSegregation, _prepareChartData) ...
  void _calculateDashboardMetrics() {
    final now = DateTime.now();
    _filteredTransactions = List.from(_allTransactions);

    _totalEarnings = _filteredTransactions.fold(0.0, (sum, item) => sum + (item['amount'] as num? ?? 0.0));
    _averageTransaction = _filteredTransactions.isNotEmpty ? _totalEarnings / _filteredTransactions.length : 0.0;
    
    _transactionsToday = _filteredTransactions.where((t) {
      final txDate = t['timestamp_dt'] as DateTime;
      return txDate.year == now.year && txDate.month == now.month && txDate.day == now.day;
    }).length;

    _currentMonthEarnings = _filteredTransactions
        .where((t) {
          final txDate = t['timestamp_dt'] as DateTime;
          return txDate.year == now.year && txDate.month == now.month;
        })
        .fold(0.0, (sum, item) => sum + (item['amount'] as num? ?? 0.0));
    
    _calculateIncomeSegregation();
    _prepareChartData();
  }
  
  void _calculateIncomeSegregation() {
    final Map<String, double> incomeMap = {};
    for (final transaction in _filteredTransactions) {
      final docType = transaction['documentType']?.toString() ?? 'Other';
      final amount = (transaction['amount'] as num? ?? 0.0).toDouble();
      incomeMap.update(docType, (value) => value + amount, ifAbsent: () => amount);
    }
    var sortedEntries = incomeMap.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    setState(() => _incomeByType = Map.fromEntries(sortedEntries));
  }
  
  void _prepareChartData() {
    final now = DateTime.now();
    List<BarChartGroupData> newChartData = [];

    if (_selectedChartView == ChartView.sevenDays) {
      final Map<int, double> dailyTotals = { for (var i = 0; i < 7; i++) i: 0.0 };
      for (final transaction in _allTransactions) {
        final txDate = transaction['timestamp_dt'] as DateTime;
        final difference = now.difference(txDate).inDays;
        if (difference >= 0 && difference < 7) {
          dailyTotals[difference] = (dailyTotals[difference] ?? 0) + (transaction['amount'] as num);
        }
      }
      newChartData = List.generate(7, (index) {
        final dayIndex = 6 - index;
        return BarChartGroupData(x: dayIndex, barRods: [
          BarChartRodData(
            toY: dailyTotals[dayIndex] ?? 0.0,
            gradient: LinearGradient(colors: [Colors.blue.shade400, Colors.blue.shade700], begin: Alignment.bottomCenter, end: Alignment.topCenter),
            width: 16,
            borderRadius: BorderRadius.circular(4),
          ),
        ]);
      }).reversed.toList();
    } else if (_selectedChartView == ChartView.thisMonth) {
      final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
      final Map<int, double> monthlyTotals = {};
      for (final transaction in _allTransactions) {
        final txDate = transaction['timestamp_dt'] as DateTime;
        if (txDate.year == now.year && txDate.month == now.month) {
          final dayOfMonth = txDate.day;
          monthlyTotals[dayOfMonth] = (monthlyTotals[dayOfMonth] ?? 0) + (transaction['amount'] as num);
        }
      }
      newChartData = List.generate(daysInMonth, (index) {
        final day = index + 1;
        return BarChartGroupData(x: day, barRods: [
          BarChartRodData(
            toY: monthlyTotals[day] ?? 0.0,
            gradient: LinearGradient(colors: [Colors.purple.shade400, Colors.purple.shade700], begin: Alignment.bottomCenter, end: Alignment.topCenter),
            width: 12,
            borderRadius: BorderRadius.circular(4),
          ),
        ]);
      });
    } else { // 'thisYear' view logic
      final Map<int, double> yearlyTotals = { for (var i = 1; i <= 12; i++) i: 0.0 };
      for (final transaction in _allTransactions) {
        final txDate = transaction['timestamp_dt'] as DateTime;
        if (txDate.year == _selectedYear) {
          final month = txDate.month;
          yearlyTotals[month] = (yearlyTotals[month] ?? 0) + (transaction['amount'] as num);
        }
      }
      newChartData = List.generate(12, (index) {
        final month = index + 1;
        return BarChartGroupData(x: month, barRods: [
          BarChartRodData(
            toY: yearlyTotals[month] ?? 0.0,
            gradient: LinearGradient(colors: [Colors.teal.shade400, Colors.teal.shade700], begin: Alignment.bottomCenter, end: Alignment.topCenter),
            width: 20,
            borderRadius: BorderRadius.circular(4),
          ),
        ]);
      });
    }
    setState(() => _chartData = newChartData);
  }

Future<void> _handleDownloadReport() async {
  if (_allTransactions.isEmpty) return;

  setState(() => _isGeneratingReport = true);
  
  // Call the NEW financial report function
  // We pass the processed list which already has 'paidByName' and 'timestamp_dt'
  await ReportGenerator.printFinancialReport(_allTransactions);
  
  if (mounted) {
    setState(() => _isGeneratingReport = false);
  }
}

@override
Widget build(BuildContext context) {
  return Scaffold(
    backgroundColor: const Color(0xFFEDF1F6),
    appBar: AppBar(
      title: const Text('Financial Dashboard', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
      backgroundColor: Colors.transparent,
      foregroundColor: const Color(0xFF475569),
      elevation: 0,
      actions: [
        // --- ADDED BUTTON HERE ---
        IconButton(
          onPressed: (_isLoading || _isGeneratingReport || _allTransactions.isEmpty) 
              ? null 
              : _handleDownloadReport,
          icon: _isGeneratingReport 
            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.picture_as_pdf),
          tooltip: 'Download AI Financial Report',
        ),
        // -------------------------
        IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: _isLoading ? null : _fetchAndProcessData,
          tooltip: 'Refresh Data',
        ),
      ],
    ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: Colors.red)))
              : ListView(
                  padding: const EdgeInsets.all(16.0),
                  children: [
                    _buildDashboardMetrics(),
                    const SizedBox(height: 24),
                    _buildRevenueChart(),
                    const SizedBox(height: 24),
                    _buildIncomeSegregation(),
                    const SizedBox(height: 24),
                    _buildTransactionListHeader(),
                    _buildTransactionList(),
                  ],
                ),
    );
  }
  
  // ... (Keep existing _buildDashboardMetrics, _buildMetricCard, _buildYearSelector, _buildRevenueChart, _buildIncomeSegregation, _buildTransactionListHeader, _buildTransactionList) ...
  Widget _buildDashboardMetrics() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildMetricCard(
                title: 'Total Revenue',
                value: currencyFormatter.format(_totalEarnings),
                icon: Icons.account_balance_wallet,
                color: Colors.green,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildMetricCard(
                title: 'This Month\'s Revenue',
                value: currencyFormatter.format(_currentMonthEarnings),
                icon: Icons.calendar_month,
                color: Colors.purple,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _buildMetricCard(
                title: 'Avg. Transaction',
                value: currencyFormatter.format(_averageTransaction),
                icon: Icons.functions,
                color: Colors.orange,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildMetricCard(
                title: 'Transactions Today',
                value: _transactionsToday.toString(),
                icon: Icons.today,
                color: Colors.blue,
              ),
            ),
          ],
        ),
      ],
    );
  }


  Widget _buildMetricCard({required String title, required String value, required IconData icon, required Color color}) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            CircleAvatar(backgroundColor: color.withOpacity(0.1), child: Icon(icon, color: color)),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(title, style: TextStyle(color: Colors.grey.shade600, fontSize: 14)),
                  const SizedBox(height: 4),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildYearSelector() {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 12.0),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8.0),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: _selectedYear,
          items: _availableYears.map<DropdownMenuItem<int>>((int year) {
            return DropdownMenuItem<int>(
              value: year,
              child: Text(
                year.toString(),
                style: const TextStyle(fontWeight: FontWeight.w500, color: Color(0xFF1E293B)),
              ),
            );
          }).toList(),
          onChanged: (int? newValue) {
            if (newValue != null) {
              setState(() {
                _selectedYear = newValue;
                _prepareChartData();
              });
            }
          },
          icon: const Icon(Icons.unfold_more, size: 20),
          isDense: true,
        ),
      ),
    );
  }

  Widget _buildRevenueChart() {
    final now = DateTime.now();
    
    String getChartTitle() {
      switch (_selectedChartView) {
        case ChartView.sevenDays:
          return 'Revenue (Last 7 Days)';
        case ChartView.thisMonth:
          return 'Revenue (${DateFormat('MMMM yyyy').format(now)})';
        case ChartView.thisYear:
          return 'Revenue';
      }
    }

    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Flexible(
                  child: Row(
                    children: [
                      Text(
                        getChartTitle(),
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                      ),
                      if (_selectedChartView == ChartView.thisYear)
                        Padding(
                          padding: const EdgeInsets.only(left: 16.0),
                          child: _buildYearSelector(),
                        ),
                    ],
                  ),
                ),
                ToggleButtons(
                  isSelected: [
                    _selectedChartView == ChartView.sevenDays,
                    _selectedChartView == ChartView.thisMonth,
                    _selectedChartView == ChartView.thisYear
                  ],
                  onPressed: (index) {
                    setState(() {
                      if (index == 0) _selectedChartView = ChartView.sevenDays;
                      if (index == 1) _selectedChartView = ChartView.thisMonth;
                      if (index == 2) _selectedChartView = ChartView.thisYear;
                      _selectedYear = DateTime.now().year;
                      if (!_availableYears.contains(_selectedYear)) {
                        _selectedYear = _availableYears.isNotEmpty ? _availableYears.first : DateTime.now().year;
                      }
                      _prepareChartData();
                    });
                  },
                  borderRadius: BorderRadius.circular(8),
                  constraints: const BoxConstraints(minHeight: 32, minWidth: 50),
                  children: const [Text('7D'), Text('Month'), Text('Year')],
                ),
              ],
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 200,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  barTouchData: BarTouchData(
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipColor: (group) => Colors.grey.shade800,
                      getTooltipItem: (group, groupIndex, rod, rodIndex) {
                        String title;
                        switch (_selectedChartView) {
                          case ChartView.sevenDays:
                            title = DateFormat('EEE').format(now.subtract(Duration(days: 6 - group.x)));
                            break;
                          case ChartView.thisMonth:
                            title = DateFormat('MMM d').format(DateTime(now.year, now.month, group.x.toInt()));
                            break;
                          case ChartView.thisYear:
                            title = DateFormat('MMM').format(DateTime(_selectedYear, group.x.toInt()));
                            break;
                        }
                        return BarTooltipItem(
                          '$title\n',
                          const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          children: <TextSpan>[
                            TextSpan(
                              text: currencyFormatter.format(rod.toY),
                              style: const TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.w500, fontSize: 14),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  titlesData: FlTitlesData(
                    show: true,
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (double value, TitleMeta meta) {
                          String text;
                          switch (_selectedChartView) {
                            case ChartView.sevenDays:
                              final day = now.subtract(Duration(days: 6 - value.toInt()));
                              text = DateFormat('E').format(day);
                              break;
                            case ChartView.thisMonth:
                              text = (value.toInt() % 5 == 0 || value.toInt() == 1) ? value.toInt().toString() : '';
                              break;
                            case ChartView.thisYear:
                              text = DateFormat('MMM').format(DateTime(0, value.toInt()));
                              break;
                          }
                          return SideTitleWidget(
                            space: 4, meta: meta,
                            child: Text(text, style: TextStyle(color: Colors.grey.shade600, fontSize: 12))
                          );
                        },
                        reservedSize: 38,
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true, reservedSize: 50,
                        getTitlesWidget: (value, meta) {
                          if (value == 0) return const SizedBox.shrink();
                          return SideTitleWidget(
                            space: 8, meta: meta,
                            child: Text('₱${(value / 1000).toStringAsFixed(0)}k', style: TextStyle(fontSize: 12, color: Colors.grey.shade600), textAlign: TextAlign.left),
                          );
                        },
                      ),
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  gridData: FlGridData(
                    show: true,
                    getDrawingHorizontalLine: (value) => FlLine(color: Colors.grey.shade200, strokeWidth: 1),
                    drawVerticalLine: false
                  ),
                  barGroups: _chartData,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIncomeSegregation() {
    if (_incomeByType.isEmpty) {
      return const SizedBox.shrink();
    }
    final List<Color> colors = [Colors.blue, Colors.green, Colors.orange, Colors.purple, Colors.red, Colors.teal, Colors.pink, Colors.amber];
    int colorIndex = 0;

    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Income Segregation', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
            const SizedBox(height: 16),
            ..._incomeByType.entries.map((entry) {
              final documentType = entry.key;
              final amount = entry.value;
              final percentage = _totalEarnings > 0 ? (amount / _totalEarnings) * 100 : 0.0;
              final color = colors[colorIndex % colors.length];
              colorIndex++;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(documentType, style: const TextStyle(fontWeight: FontWeight.w600)),
                        Text('${currencyFormatter.format(amount)} (${percentage.toStringAsFixed(1)}%)', style: const TextStyle(fontWeight: FontWeight.w500, color: Color(0xFF475569))),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: LinearProgressIndicator(value: percentage / 100, backgroundColor: color.withOpacity(0.2), valueColor: AlwaysStoppedAnimation<Color>(color), minHeight: 8),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildTransactionListHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text('Recent Transactions', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
          TextButton(onPressed: () {}, child: const Text('View All')),
        ],
      ),
    );
  }

  Widget _buildTransactionList() {
    if (_allTransactions.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 40.0),
          child: Text("No transactions recorded yet.", style: TextStyle(color: Colors.grey)),
        ),
      );
    }
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: min(5, _allTransactions.length),
      itemBuilder: (context, index) {
        return _TransactionCard(transaction: _allTransactions[index]);
      },
    );
  }
}

// --- UPDATED TRANSACTION CARD ---
class _TransactionCard extends StatefulWidget {
  final Map<String, dynamic> transaction;
  const _TransactionCard({required this.transaction});

  @override
  State<_TransactionCard> createState() => __TransactionCardState();
}

class __TransactionCardState extends State<_TransactionCard> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final currencyFormatter = NumberFormat.currency(locale: 'en_PH', symbol: '₱');
    final dateTimeFormatter = DateFormat('MMM d, yyyy • hh:mm a');

    final amount = widget.transaction['amount'] as num? ?? 0.0;
    final documentType = widget.transaction['documentType']?.toString() ?? 'N/A';
    final paidByName = widget.transaction['paidByName']?.toString() ?? 'N/A';
    final timestamp = widget.transaction['timestamp_dt'] as DateTime;
    final processedBy = widget.transaction['processedBy']?.toString() ?? 'N/A';
    final requestId = widget.transaction['requestId']?.toString() ?? 'N/A';
    
    // Check if offline
    final isOffline = widget.transaction['isOffline'] == true;

    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.symmetric(vertical: 6.0),
      child: InkWell(
        onTap: () => setState(() => _isExpanded = !_isExpanded),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              Row(
                children: [
                  CircleAvatar(backgroundColor: Colors.green.withOpacity(0.1), child: const Icon(Icons.payment, color: Colors.green)),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(documentType, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Text(paidByName, style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                            if (isOffline) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.orange.shade100,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  "Offline Request",
                                  style: TextStyle(fontSize: 10, color: Colors.orange.shade800, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  Text(currencyFormatter.format(amount), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green, fontSize: 16)),
                ],
              ),
              AnimatedCrossFade(
                firstChild: const SizedBox.shrink(),
                secondChild: _buildExpandedDetails(timestamp, processedBy, requestId, dateTimeFormatter),
                crossFadeState: _isExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                duration: const Duration(milliseconds: 300),
              )
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildExpandedDetails(DateTime timestamp, String processedBy, String requestId, DateFormat formatter) {
    return Padding(
      padding: const EdgeInsets.only(top: 16.0),
      child: Column(
        children: [
          Divider(color: Colors.grey.shade200),
          const SizedBox(height: 8),
          _buildDetailRow('Date & Time', formatter.format(timestamp.toLocal())),
          _buildDetailRow('Processed By', processedBy),
          _buildDetailRow('Request ID', requestId),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey.shade600)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}