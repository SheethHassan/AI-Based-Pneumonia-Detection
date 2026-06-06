// =============================================================================
// Classification Result — Data Model
// =============================================================================
// Holds the prediction output from TFLite inference.
// =============================================================================

import 'dart:typed_data';

class ClassificationResult {
  /// "Normal" or "Pneumonia"
  final String label;

  /// Confidence score between 0.0 and 1.0
  final double confidence;

  /// Time taken for inference in milliseconds
  final int inferenceTimeMs;

  /// Optional Grad-CAM heatmap image bytes
  final Uint8List? heatmapImage;

  const ClassificationResult({
    required this.label,
    required this.confidence,
    required this.inferenceTimeMs,
    this.heatmapImage,
  });

  /// Whether the prediction indicates pneumonia
  bool get isPneumonia => label.toLowerCase() == 'pneumonia';

  /// Confidence as a percentage string (e.g. "94.3%")
  String get confidencePercent => '${(confidence * 100).toStringAsFixed(1)}%';

  @override
  String toString() =>
      'ClassificationResult(label: $label, confidence: $confidencePercent, '
      'inferenceTime: ${inferenceTimeMs}ms)';
}
