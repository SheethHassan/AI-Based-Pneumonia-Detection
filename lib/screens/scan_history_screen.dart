// =============================================================================
// Scan History Screen — Past analyses for the signed-in doctor
// =============================================================================

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/scan_record.dart';
import '../theme/app_theme.dart';

class ScanHistoryScreen extends StatelessWidget {
  final String doctorEmail;

  const ScanHistoryScreen({
    super.key,
    required this.doctorEmail,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Scan History',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
        ),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: isDark
              ? AppTheme.darkBackgroundGradient
              : AppTheme.backgroundGradient,
        ),
        child: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('scans')
              .where('doctorEmail', isEqualTo: doctorEmail)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(color: AppTheme.primaryBlue),
              );
            }

            if (snapshot.hasError) {
              return _messageState(
                context,
                icon: Icons.error_outline_rounded,
                title: 'Could not load history',
                subtitle: snapshot.error.toString(),
              );
            }

            if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
              return _messageState(
                context,
                icon: Icons.history_rounded,
                title: 'No scans yet',
                subtitle: 'Your completed analyses will appear here.',
              );
            }

            final records = snapshot.data!.docs
                .map((doc) => ScanRecord.fromFirestore(doc))
                .toList()
              ..sort((a, b) {
                final aTime = a.timestamp ?? DateTime.fromMillisecondsSinceEpoch(0);
                final bTime = b.timestamp ?? DateTime.fromMillisecondsSinceEpoch(0);
                return bTime.compareTo(aTime);
              });

            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              itemCount: records.length,
              itemBuilder: (context, index) => _ScanHistoryCard(record: records[index]),
            );
          },
        ),
      ),
    );
  }

  Widget _messageState(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: AppTheme.primaryBlue.withAlpha(180)),
            const SizedBox(height: 16),
            Text(
              title,
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 14,
                color: isDark ? AppTheme.textDarkSecondary : AppTheme.textSecondary,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScanHistoryCard extends StatelessWidget {
  final ScanRecord record;

  const _ScanHistoryCard({required this.record});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isPneumonia = record.isPneumonia;
    final color = isPneumonia ? AppTheme.dangerRed : AppTheme.successGreen;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.surfaceDarkCard : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: isDark ? null : AppTheme.cardShadow,
        border: isDark ? Border.all(color: Colors.white.withAlpha(20)) : null,
      ),
      child: Semantics(
        label: '${record.result}, confidence ${record.confidencePercent}, '
            '${_formatDate(record.timestamp)}',
        button: true,
        child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: color.withAlpha(25),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            isPneumonia ? Icons.warning_rounded : Icons.check_circle_rounded,
            color: color,
          ),
        ),
        title: Text(
          record.result,
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : AppTheme.textPrimary,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              'Confidence: ${record.confidencePercent}',
              style: GoogleFonts.inter(
                fontSize: 13,
                color: isDark ? AppTheme.textDarkSecondary : AppTheme.textSecondary,
              ),
            ),
            if (record.modelVersion != null)
              Text(
                'Model v${record.modelVersion}',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: isDark ? AppTheme.textDarkSecondary : AppTheme.textLight,
                ),
              ),
            Text(
              _formatDate(record.timestamp),
              style: GoogleFonts.inter(
                fontSize: 12,
                color: isDark ? AppTheme.textDarkSecondary : AppTheme.textLight,
              ),
            ),
          ],
        ),
        trailing: Icon(
          Icons.chevron_right_rounded,
          color: isDark ? Colors.white38 : AppTheme.textLight,
        ),
        onTap: () => _showDetails(context, record),
      ),
      ),
    );
  }

  String _formatDate(DateTime? dt) {
    if (dt == null) return 'Date unknown';
    return '${dt.day}/${dt.month}/${dt.year} · '
        '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
  }

  void _showDetails(BuildContext context, ScanRecord record) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: isDark ? AppTheme.surfaceDarkCard : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Scan Details',
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 16),
            _detailLine(context, 'Result', record.result),
            _detailLine(context, 'Confidence', record.confidencePercent),
            _detailLine(context, 'Doctor', record.doctorName),
            if (record.modelVersion != null)
              _detailLine(context, 'Model', 'v${record.modelVersion}'),
            _detailLine(context, 'Date', _formatDate(record.timestamp)),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _detailLine(BuildContext context, String label, String value) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 13,
                color: isDark ? AppTheme.textDarkSecondary : AppTheme.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : AppTheme.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
