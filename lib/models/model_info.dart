// =============================================================================
// Model Info — Metadata for the deployed TFLite model
// =============================================================================

class ModelInfo {
  final String name;
  final String version;
  final int inputSize;
  final List<String> classes;
  final String format;
  final String description;

  const ModelInfo({
    required this.name,
    required this.version,
    required this.inputSize,
    required this.classes,
    required this.format,
    required this.description,
  });

  factory ModelInfo.fromJson(Map<String, dynamic> json) {
    return ModelInfo(
      name: json['name'] as String? ?? 'Unknown',
      version: json['version'] as String? ?? '0.0.0',
      inputSize: json['inputSize'] as int? ?? 224,
      classes: (json['classes'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const ['Normal', 'Pneumonia'],
      format: json['format'] as String? ?? 'TensorFlow Lite',
      description: json['description'] as String? ?? '',
    );
  }

  static const ModelInfo fallback = ModelInfo(
    name: 'DenseNet121',
    version: '1.0.0',
    inputSize: 224,
    classes: ['Normal', 'Pneumonia'],
    format: 'TensorFlow Lite',
    description: 'Chest X-ray pneumonia classifier',
  );

  String get displayLabel => '$name v$version';
}
