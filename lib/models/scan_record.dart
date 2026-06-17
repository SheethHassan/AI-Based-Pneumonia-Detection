// =============================================================================
// Scan Record — Firestore scan history entry
// =============================================================================

import 'package:cloud_firestore/cloud_firestore.dart';

class ScanRecord {
  final String id;
  final String doctorName;
  final String doctorEmail;
  final String result;
  final double confidence;
  final String? modelVersion;
  final DateTime? timestamp;

  const ScanRecord({
    required this.id,
    required this.doctorName,
    required this.doctorEmail,
    required this.result,
    required this.confidence,
    this.modelVersion,
    this.timestamp,
  });

  factory ScanRecord.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return ScanRecord(
      id: doc.id,
      doctorName: data['doctorName'] as String? ?? 'Unknown',
      doctorEmail: data['doctorEmail'] as String? ?? '',
      result: data['result'] as String? ?? 'Unknown',
      confidence: (data['confidence'] as num?)?.toDouble() ?? 0,
      modelVersion: data['modelVersion'] as String?,
      timestamp: (data['timestamp'] as Timestamp?)?.toDate(),
    );
  }

  bool get isPneumonia => result.toLowerCase() == 'pneumonia';

  String get confidencePercent => '${(confidence * 100).toStringAsFixed(1)}%';
}
