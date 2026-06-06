import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_theme.dart';
import '../../models/doctor.dart';
import '../../services/auth_service.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../main.dart'; 
import '../home_screen.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  int _currentTab = 0; // 0 for Users, 1 for Alerts, 2 for Analytics
  String _searchQuery = '';
  String _alertFilter = 'pending'; // 'pending' or 'resolved'

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Console'),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.medical_services_outlined),
            onPressed: () {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (_) => HomeScreen(
                    doctorName: user?.displayName ?? 'Admin',
                    doctorEmail: user?.email ?? '',
                    role: 'admin',
                  ),
                ),
              );
            },
            tooltip: 'Switch to Doctor Mode',
          ),
          ValueListenableBuilder<ThemeMode>(
            valueListenable: themeModeNotifier,
            builder: (context, mode, _) {
              final isDark = mode == ThemeMode.dark;
              return IconButton(
                icon: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: Icon(
                    isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                    key: ValueKey(isDark),
                    color: isDark ? Colors.amber : Colors.blueGrey,
                  ),
                ),
                onPressed: () {
                  themeModeNotifier.value = isDark ? ThemeMode.light : ThemeMode.dark;
                },
                tooltip: 'Toggle Theme',
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout_rounded),
            onPressed: () => AuthService.signOut(),
            tooltip: 'Sign Out',
          ),
          const SizedBox(width: 8),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: _buildTabSwitcher(),
        ),
      ),
      floatingActionButton: _currentTab == 0
          ? FloatingActionButton.extended(
              onPressed: () => _showDoctorForm(),
              label: const Text('Add User'),
              icon: const Icon(Icons.person_add_alt_1_rounded),
              backgroundColor: AppTheme.primaryBlue,
              foregroundColor: Colors.white,
            )
          : null,
      body: _buildBody(),
    );
  }

  Widget _buildTabSwitcher() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
      child: Container(
        height: 45,
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.light ? Colors.grey.shade200 : Colors.white.withAlpha(10), 
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            _tabButton(0, 'Users', Icons.people_alt_rounded),
            _buildAlertsTabButton(),
            _tabButton(2, 'Analytics', Icons.analytics_rounded),
            _tabButton(3, 'Logs', Icons.security_rounded),
          ],
        ),
      ),
    );
  }

  Widget _buildAlertsTabButton() {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore.collection('reports').where('status', isEqualTo: 'pending').snapshots(),
      builder: (context, snapshot) {
        final count = snapshot.hasData ? snapshot.data!.docs.length : 0;
        return _tabButton(1, 'Alerts', Icons.notification_important_rounded, badgeCount: count);
      },
    );
  }

  Widget _tabButton(int index, String label, IconData icon, {int badgeCount = 0}) {
    final isSelected = _currentTab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _currentTab = index),
        child: Container(
          margin: const EdgeInsets.all(4), 
          decoration: BoxDecoration(
            color: isSelected ? (Theme.of(context).brightness == Brightness.light ? Colors.white : AppTheme.surfaceDarkCard) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            boxShadow: isSelected ? [BoxShadow(color: Colors.black.withAlpha(isSelected ? 20 : 0), blurRadius: 4, offset: const Offset(0, 2))] : null,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    icon, 
                    size: 16, 
                    color: isSelected ? AppTheme.primaryBlue : (Theme.of(context).brightness == Brightness.light ? Colors.black45 : Colors.white70) 
                  ),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                      color: isSelected ? AppTheme.primaryBlue : (Theme.of(context).brightness == Brightness.light ? Colors.black45 : Colors.white70),
                    ),
                  ),
                  if (badgeCount > 0) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(10)),
                      child: Text(
                        badgeCount.toString(),
                        style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPersonnelTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore.collection('users').where('role', isNotEqualTo: 'admin').snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

        final docs = snapshot.data!.docs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final name = (data['name'] ?? '').toString().toLowerCase();
          final id = (doc.id).toLowerCase();
          return name.contains(_searchQuery.toLowerCase()) || id.contains(_searchQuery.toLowerCase());
        }).toList();

        final doctors = docs.map((doc) => Doctor.fromFirestore(doc)).toList();

        return CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _buildStats(doctors.length)),
            SliverToBoxAdapter(child: _buildSearchBar()),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) => _buildDoctorCard(doctors[index]),
                  childCount: doctors.length,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
  // ── SearchBar ───────────────────────────────────────────────────────────────
  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
      child: TextField(
        onChanged: (v) => setState(() => _searchQuery = v),
        decoration: InputDecoration(
          hintText: 'Search by Name or ID...',
          prefixIcon: const Icon(Icons.search_rounded),
          fillColor: Theme.of(context).brightness == Brightness.light ? Colors.white : AppTheme.surfaceDarkCard,
          filled: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
        ),
      ),
    );
  }

  Widget _buildAlertsTab() {
    return Column(
      children: [
        _buildAlertFilterBar(),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: _firestore
                .collection('reports')
                .where('status', isEqualTo: _alertFilter)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) return Center(child: Text('Error: ${snapshot.error}'));
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
              
              // Manual Sorting to avoid Index/Subscription requirements
              final docs = snapshot.data!.docs.toList();
              docs.sort((a, b) {
                final aTime = (a.data() as Map)['timestamp'] as Timestamp?;
                final bTime = (b.data() as Map)['timestamp'] as Timestamp?;
                if (aTime == null || bTime == null) return 1;
                return bTime.compareTo(aTime);
              });

              if (docs.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.done_all_rounded, size: 64, color: Colors.grey.shade300),
                      const SizedBox(height: 16),
                      Text('No $_alertFilter reports found.', style: GoogleFonts.inter(color: Colors.grey)),
                    ],
                  ),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: docs.length,
                itemBuilder: (context, index) {
                  final report = docs[index];
                  final data = report.data() as Map<String, dynamic>;
                  return _buildAlertCard(report.id, data);
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildAlertFilterBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          _filterChip('pending', 'Pending', Icons.hourglass_empty_rounded),
          const SizedBox(width: 8),
          _filterChip('resolved', 'Resolved', Icons.check_circle_outline_rounded),
        ],
      ),
    );
  }

  Widget _filterChip(String value, String label, IconData icon) {
    final isSelected = _alertFilter == value;
    return GestureDetector(
      onTap: () => setState(() => _alertFilter = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primaryBlue : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isSelected ? AppTheme.primaryBlue : Colors.grey.shade300),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: isSelected ? Colors.white : Colors.grey),
            const SizedBox(width: 8),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isSelected ? Colors.white : Colors.grey.shade700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnalyticsTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore.collection('scans').snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: Text('Error: ${snapshot.error}'));
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

        final scans = snapshot.data!.docs;
        final totalScans = scans.length;
        final pneumoniaScans = scans.where((doc) => (doc.data() as Map)['result'] == 'Pneumonia').length;
        final normalScans = totalScans - pneumoniaScans;
        
        final pneumoniaRatio = totalScans == 0 ? 0 : (pneumoniaScans / totalScans * 100).round();
        final normalRatio = 100 - pneumoniaRatio;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('System Performance', 
                style: GoogleFonts.poppins(
                  fontSize: 20, 
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).brightness == Brightness.light ? AppTheme.textPrimary : AppTheme.textDarkPrimary,
                )),
              const SizedBox(height: 24),
              
              // --- Real-time Pie Chart ---
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardTheme.color,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: Theme.of(context).brightness == Brightness.light ? AppTheme.cardShadow : null,
                  border: Theme.of(context).brightness == Brightness.dark ? Border.all(color: Colors.white.withAlpha(20)) : null,
                ),
                child: Row(
                  children: [
                    Expanded(
                      flex: 4,
                      child: SizedBox(
                        height: 140,
                        child: PieChart(
                          PieChartData(
                            sectionsSpace: 2,
                            centerSpaceRadius: 35,
                            sections: [
                              PieChartSectionData(
                                value: normalScans.toDouble(),
                                title: normalRatio > 0 ? '$normalRatio%' : '',
                                color: AppTheme.successGreen,
                                radius: 30,
                                titleStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                              ),
                              PieChartSectionData(
                                value: pneumoniaScans.toDouble(),
                                title: pneumoniaRatio > 0 ? '$pneumoniaRatio%' : '',
                                color: AppTheme.dangerRed,
                                radius: 30,
                                titleStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 5,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _chartLegend('Normal', AppTheme.successGreen, normalScans),
                          const SizedBox(height: 12),
                          _chartLegend('Pneumonia', AppTheme.dangerRed, pneumoniaScans),
                          const Divider(height: 24),
                          Text('Total Scans: $totalScans', 
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              color: Theme.of(context).brightness == Brightness.light ? AppTheme.textPrimary : AppTheme.textDarkPrimary,
                            )
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),
              _buildBroadcastSection(),
              const SizedBox(height: 100),
            ],
          ),
        );
      }
    );
  }

  Widget _chartLegend(String label, Color color, int value) {
    return Row(
      children: [
        Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Text(label, style: GoogleFonts.inter(fontSize: 13, color: Theme.of(context).brightness == Brightness.light ? AppTheme.textSecondary : AppTheme.textDarkSecondary)),
        const Spacer(),
        Text(value.toString(), style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _buildAuditLogs() {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore.collection('system_logs').orderBy('timestamp', descending: true).limit(10).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox(height: 100, child: Center(child: CircularProgressIndicator()));
        final logs = snapshot.data!.docs;
        if (logs.isEmpty) return Center(child: Text('No logs yet.', style: GoogleFonts.inter(color: Colors.grey)));

        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: logs.length,
          itemBuilder: (context, index) {
            final log = logs[index].data() as Map<String, dynamic>;
            return _buildLogCard(log);
          },
        );
      },
    );
  }

  Widget _buildLogCard(Map<String, dynamic> log) {
    final bool isLogin = log['action'].toString().contains('Login');
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withAlpha(10)),
      ),
      child: Row(
        children: [
          Icon(isLogin ? Icons.login_rounded : Icons.logout_rounded, 
               size: 18, color: isLogin ? AppTheme.successGreen : AppTheme.dangerRed),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(log['email'] ?? 'Unknown', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                Text(log['action'] ?? '', style: const TextStyle(fontSize: 11, color: Colors.grey)),
              ],
            ),
          ),
          Text(_formatTimestamp(log['timestamp']), style: const TextStyle(fontSize: 10, color: Colors.grey)),
        ],
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppTheme.dangerRed,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Widget _buildBody() {
    return Container(
      decoration: BoxDecoration(
        gradient: Theme.of(context).brightness == Brightness.light
            ? AppTheme.backgroundGradient
            : AppTheme.darkBackgroundGradient,
      ),
      child: _buildCurrentTab(),
    );
  }

  Widget _buildCurrentTab() {
    switch (_currentTab) {
      case 0: return _buildPersonnelTab();
      case 1: return _buildAlertsTab();
      case 2: return _buildAnalyticsTab();
      case 3: return _buildLogsTab();
      default: return _buildPersonnelTab();
    }
  }

  Widget _buildLogsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.security_rounded, color: AppTheme.primaryBlue, size: 28),
              const SizedBox(width: 12),
              Text('Security Audit Logs', 
                style: GoogleFonts.poppins(
                  fontSize: 22, 
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).brightness == Brightness.light ? AppTheme.textPrimary : AppTheme.textDarkPrimary,
                )),
            ],
          ),
          const SizedBox(height: 8),
          Text('Real-time monitoring of all system access and authentication events.', 
            style: GoogleFonts.inter(
              fontSize: 13, 
              color: Theme.of(context).brightness == Brightness.light ? AppTheme.textSecondary : AppTheme.textDarkSecondary,
            )),
          const SizedBox(height: 24),
          _buildAuditLogs(),
          const SizedBox(height: 100),
        ],
      ),
    );
  }

  Widget _buildAlertCard(String id, Map<String, dynamic> data) {
    final bool isResolved = data['status'] == 'resolved';
    
    return Opacity(
      opacity: isResolved ? 0.6 : 1.0, // Dimmed if resolved
      child: Card(
        margin: const EdgeInsets.only(bottom: 16),
        elevation: 0,
        color: Theme.of(context).cardTheme.color,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: Theme.of(context).brightness == Brightness.dark 
                ? Colors.white.withAlpha(20) 
                : (isResolved ? Colors.grey.shade200 : Colors.grey.shade100),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: isResolved 
                        ? Colors.grey.withAlpha(20) 
                        : (data['priority'] == 'high' ? Colors.red : Colors.orange).withAlpha(20),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      (data['priority'] ?? 'normal').toUpperCase(),
                      style: TextStyle(
                        fontSize: 10, 
                        fontWeight: FontWeight.bold, 
                        color: isResolved ? Colors.grey : (data['priority'] == 'high' ? Colors.red : Colors.orange)
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      if (!isResolved)
                        IconButton(
                          icon: const Icon(Icons.check_circle_outline, color: Colors.green, size: 22),
                          onPressed: () => _updateAlertStatus(id, 'resolved'),
                          tooltip: 'Resolve',
                        )
                      else
                        IconButton(
                          icon: const Icon(Icons.history_rounded, color: Colors.blueGrey, size: 22),
                          onPressed: () => _updateAlertStatus(id, 'pending'),
                          tooltip: 'Re-open',
                        ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline_rounded, color: Colors.grey, size: 22),
                        onPressed: () => _deleteAlert(id),
                        tooltip: 'Delete',
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                data['title'] ?? 'System Issue', 
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w700, 
                  fontSize: 16,
                  color: isResolved ? Colors.grey.shade600 : Colors.black87,
                )
              ),
              const SizedBox(height: 4),
              Text(
                data['description'] ?? '', 
                style: GoogleFonts.inter(
                  fontSize: 14, 
                  color: isResolved 
                      ? Colors.grey 
                      : (Theme.of(context).brightness == Brightness.light ? AppTheme.textSecondary : AppTheme.textDarkSecondary)
                )
              ),
              const Divider(height: 32),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'From: Dr. ${data['doctorName'] ?? 'Unknown'}',
                    style: TextStyle(fontSize: 11, color: isResolved ? Colors.grey : AppTheme.textLight),
                  ),
                  Text(
                    _formatTimestamp(data['timestamp']),
                    style: TextStyle(fontSize: 11, color: isResolved ? Colors.grey : AppTheme.textLight),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTimestamp(dynamic timestamp) {
    if (timestamp == null) return 'Now';
    final DateTime dt = (timestamp as Timestamp).toDate();
    return "${dt.day}/${dt.month} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}";
  }

  Future<void> _updateAlertStatus(String id, String status) async {
    await _firestore.collection('reports').doc(id).update({'status': status});
  }

  Future<void> _deleteAlert(String id) async {
    await _firestore.collection('reports').doc(id).delete();
  }

  Widget _buildStats(int count) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(
        gradient: AppTheme.primaryGradient,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(32),
          bottomRight: Radius.circular(32),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'System Overview',
                style: GoogleFonts.inter(
                  color: Colors.white70,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Icon(Icons.security_rounded, color: Colors.white24, size: 20),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _statItem('Total Staff', count.toString(), Icons.people_outline),
              const SizedBox(width: 16),
              _buildMaintenanceToggle(),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMaintenanceToggle() {
    return StreamBuilder<DocumentSnapshot>(
      stream: _firestore.collection('settings').doc('system').snapshots(),
      builder: (context, snapshot) {
        bool isMaintenance = false;
        if (snapshot.hasData && snapshot.data!.exists) {
          isMaintenance = (snapshot.data!.data() as Map)['isMaintenance'] ?? false;
        }

        final activeColor = isMaintenance ? Colors.orange.shade800 : const Color(0xFF10B981); // Professional Emerald Green
        final cardBg = isMaintenance ? Colors.orange.shade900.withAlpha(200) : const Color(0xFF064E3B).withAlpha(150);

        return Expanded(
          child: GestureDetector(
            onTap: () => _toggleMaintenance(!isMaintenance),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withAlpha(isMaintenance ? 100 : 30), width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: activeColor.withAlpha(isMaintenance ? 60 : 30),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  )
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(color: Colors.white.withAlpha(40), shape: BoxShape.circle),
                        child: Icon(
                          isMaintenance ? Icons.construction_rounded : Icons.bolt_rounded, 
                          color: Colors.white, size: 18
                        ),
                      ),
                      SizedBox(
                        height: 20,
                        width: 34,
                        child: Switch(
                          value: isMaintenance,
                          onChanged: (v) => _toggleMaintenance(v),
                          activeColor: Colors.white,
                          activeTrackColor: Colors.orangeAccent,
                          inactiveThumbColor: Colors.white70,
                          inactiveTrackColor: const Color(0xFF10B981).withAlpha(100),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    isMaintenance ? 'MAINTENANCE' : 'SYSTEM LIVE',
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: 0.5,
                    ),
                  ),
                  Text(
                    ' System Status',
                    style: GoogleFonts.inter(fontSize: 10, color: Colors.white70),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _toggleMaintenance(bool value) async {
    await _firestore.collection('settings').doc('system').set({
      'isMaintenance': value,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    
    // Also send a broadcast message automatically
    if (value) {
      await _sendBroadcast("The system is currently under maintenance. Please check back later.");
    } else {
      await _sendBroadcast("Maintenance complete. The system is now active.");
    }
  }

  Widget _statItem(String label, String value, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withAlpha(40),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: Colors.white, size: 22),
            const SizedBox(height: 8),
            Text(
              value,
              style: GoogleFonts.poppins(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 11,
                color: Colors.white70,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBroadcastSection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppTheme.warningAmber.withAlpha(Theme.of(context).brightness == Brightness.light ? 15 : 30),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppTheme.warningAmber.withAlpha(Theme.of(context).brightness == Brightness.light ? 40 : 80)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.campaign_rounded, color: AppTheme.warningAmber, size: 24),
                const SizedBox(width: 12),
                Text(
                  'Broadcast Message',
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).brightness == Brightness.light ? AppTheme.textPrimary : AppTheme.textDarkPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Send a notification or alert to all doctors using the system.',
              style: GoogleFonts.inter(
                fontSize: 13, 
                color: Theme.of(context).brightness == Brightness.light ? AppTheme.textSecondary : AppTheme.textDarkSecondary,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: TextEditingController(), // Used for one-time sending
              onSubmitted: (v) => _sendBroadcast(v),
              decoration: const InputDecoration(
                hintText: 'Enter message...',
                suffixIcon: Icon(Icons.send_rounded, color: AppTheme.primaryBlue),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _sendBroadcast(String message) async {
    if (message.trim().isEmpty) return;
    final user = FirebaseAuth.instance.currentUser;
    await _firestore.collection('notifications').add({
      'type': 'Broadcast',
      'message': message.trim(),
      'sender': user?.displayName ?? 'Admin',
      'timestamp': FieldValue.serverTimestamp(),
    });
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Message broadcasted!')));
  }

  Widget _buildDoctorCard(Doctor doctor) {
    Color roleColor;
    switch (doctor.role.toLowerCase()) {
      case 'admin': roleColor = Colors.blue; break;
      case 'radiologist': roleColor = Colors.purple; break;
      case 'technician': roleColor = Colors.orange; break;
      default: roleColor = Colors.teal;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      color: Theme.of(context).cardTheme.color,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: Theme.of(context).brightness == Brightness.dark 
              ? Colors.white.withAlpha(20) 
              : Colors.grey.shade100,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: roleColor.withAlpha(15), shape: BoxShape.circle),
          child: Icon(Icons.person_outline, color: roleColor, size: 24),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                doctor.name, 
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w600, 
                  fontSize: 15,
                  color: Theme.of(context).brightness == Brightness.light ? AppTheme.textPrimary : AppTheme.textDarkPrimary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: roleColor.withAlpha(20), borderRadius: BorderRadius.circular(4)),
              child: Text(
                doctor.role.toUpperCase(),
                style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: roleColor),
              ),
            ),
          ],
        ),
        subtitle: Text(
          doctor.email, 
          style: TextStyle(
            fontSize: 12, 
            color: Theme.of(context).brightness == Brightness.light ? AppTheme.textSecondary : AppTheme.textDarkSecondary,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.edit_note_rounded, color: Colors.blueGrey),
              onPressed: () => _showDoctorForm(doctor: doctor),
            ),
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined, color: AppTheme.dangerRed),
              onPressed: () => _confirmDelete(doctor),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _sendResetEmail(String email) async {
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Password reset email sent!')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  // --- CRUD Operations ---

  void _showDoctorForm({Doctor? doctor}) {
    final nameController = TextEditingController(text: doctor?.name);
    // Strip @moh.om if editing
    final initialId = doctor?.email.split('@').first ?? '';
    final idController = TextEditingController(text: initialId);
    final passController = TextEditingController(text: doctor?.password);
    
    final List<String> roles = ['doctor', 'radiologist', 'technician'];
    String selectedRole = doctor?.role ?? 'doctor';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.light ? Colors.white : AppTheme.surfaceDarkCard,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          ),
          padding: EdgeInsets.fromLTRB(28, 24, 28, MediaQuery.of(context).viewInsets.bottom + 32),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  doctor == null ? 'Register New Staff' : 'Update Credentials',
                  style: GoogleFonts.poppins(
                    fontSize: 22, 
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).brightness == Brightness.light ? AppTheme.textPrimary : Colors.white,
                  ),
                ),
                const SizedBox(height: 28),
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'Full Name', prefixIcon: Icon(Icons.person)),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: selectedRole,
                  dropdownColor: Theme.of(context).brightness == Brightness.light ? Colors.white : AppTheme.surfaceDarkCard,
                  decoration: const InputDecoration(labelText: 'Assigned Role', prefixIcon: Icon(Icons.security_rounded)),
                  items: roles.map((role) => DropdownMenuItem(
                    value: role,
                    child: Text(role.toUpperCase(), style: const TextStyle(fontSize: 14)),
                  )).toList(),
                  onChanged: (val) {
                    if (val != null) setModalState(() => selectedRole = val);
                  },
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: idController,
                  enabled: doctor == null,
                  decoration: const InputDecoration(
                    labelText: 'Staff Username / ID', 
                    prefixIcon: Icon(Icons.badge_rounded),
                    suffixText: '@moh.om',
                    suffixStyle: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: passController,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Account Password', prefixIcon: Icon(Icons.lock_outline_rounded)),
                ),
                const SizedBox(height: 32),
                ElevatedButton(
                  onPressed: () async {
                    final String staffName = nameController.text.trim();
                    final String staffId = idController.text.trim();
                    final String password = passController.text.trim();

                    // --- Validation ---
                    if (staffName.isEmpty) {
                      _showError('Please enter full name');
                      return;
                    }
                    if (staffId.isEmpty) {
                      _showError('Please enter Staff ID');
                      return;
                    }
                    if (password.length < 6) {
                      _showError('Password must be at least 6 characters');
                      return;
                    }

                    final String generatedEmail = "$staffId@moh.om";
                    
                    final data = {
                      'name': staffName,
                      'email': generatedEmail,
                      'password': password,
                      'role': selectedRole,
                      if (doctor == null) 'createdAt': FieldValue.serverTimestamp(),
                    };
                    
                    try {
                      if (doctor == null) {
                        // Check if already exists
                        final existing = await _firestore.collection('users').doc(generatedEmail).get();
                        if (existing.exists) {
                          _showError('This Staff ID is already registered');
                          return;
                        }
                        await _firestore.collection('users').doc(generatedEmail).set(data);
                      } else {
                        await _firestore.collection('users').doc(doctor.id).update(data);
                      }
                      if (mounted) Navigator.pop(context);
                    } catch (e) {
                      _showError('Failed to save user: $e');
                    }
                  },
                  child: Text(doctor == null ? 'Complete Registration' : 'Update Credentials'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _confirmDelete(Doctor doctor) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Confirm Deletion'),
        content: Text('Are you sure you want to revoke access for Dr. ${doctor.name}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              await _firestore.collection('users').doc(doctor.id).delete();
              if (mounted) Navigator.pop(context);
            },
            style: TextButton.styleFrom(foregroundColor: AppTheme.dangerRed),
            child: const Text('Revoke Access'),
          ),
        ],
      ),
    );
  }
}
