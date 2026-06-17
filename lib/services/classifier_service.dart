// =============================================================================
// Classifier Service - TFLite Inference Engine (DenseNet121)
// =============================================================================
// Loads the bundled multi-output TFLite model, preprocesses chest X-rays in the
// same way as the deployed FastAPI/Keras path, runs offline inference, and
// renders the model's focus-map output as a CAM/Grad-CAM-style overlay.
// =============================================================================

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

import '../models/classification_result.dart';
import '../models/model_info.dart';

class ClassifierService {
  ClassifierService._internal();

  static final ClassifierService instance = ClassifierService._internal();

  factory ClassifierService() => instance;

  static const String _modelPath =
      'assets/model/MULTI_OUTPUT_MODEL_flutter.tflite';
  static const String _legacyModelPath =
      'assets/model/densenet_pneumonia.tflite';
  static const String _labelsPath = 'assets/model/labels.txt';
  static const String _modelInfoPath = 'assets/model/model_info.json';
  static const int _inputSize = 224;

  // The bundled Colab/FastAPI model was trained with ImageDataGenerator
  // rescale=1./255, so offline inference must use the same scaling.
  static const double _pneumoniaThreshold = 0.5;

  Interpreter? _interpreter;
  List<String> _labels = const [];
  ModelInfo _modelInfo = ModelInfo.fallback;
  bool _isInitialized = false;

  /// Whether the model is loaded and ready.
  bool get isReady => _isInitialized;

  /// Load the TFLite model and labels from assets.
  Future<void> initialize() async {
    try {
      final options = InterpreterOptions()..threads = 4;

      _interpreter?.close();
      _interpreter = await _loadInterpreter(options);

      final outputTensors = _interpreter!.getOutputTensors();
      debugPrint('Model loaded successfully.');
      debugPrint('Model has ${outputTensors.length} outputs:');
      for (var i = 0; i < outputTensors.length; i++) {
        debugPrint(
          '  Output $i: name=${outputTensors[i].name}, '
          'shape=${outputTensors[i].shape}, type=${outputTensors[i].type}',
        );
      }

      _labels = await _loadLabels();
      _modelInfo = await _loadModelInfo();
      _isInitialized = true;
      debugPrint('Classifier initialized with labels: $_labels');
    } catch (e) {
      debugPrint('CRITICAL ERROR: Failed to initialize ClassifierService: $e');
      _isInitialized = false;
      rethrow;
    }
  }

  Future<Interpreter> _loadInterpreter(InterpreterOptions options) async {
    final candidates = <String>[
      _modelPath.replaceFirst('assets/', ''),
      _modelPath,
      _legacyModelPath.replaceFirst('assets/', ''),
      _legacyModelPath,
    ];

    Object? lastError;
    for (final candidate in candidates) {
      try {
        debugPrint('Attempting to load model from: $candidate');
        return await Interpreter.fromAsset(candidate, options: options);
      } catch (e) {
        lastError = e;
        debugPrint('Failed to load model from $candidate: $e');
      }
    }

    throw Exception(
      'Could not load TFLite model. Last error: ${lastError ?? 'unknown'}',
    );
  }

  Future<List<String>> _loadLabels() async {
    try {
      final labelsData = await rootBundle.loadString(_labelsPath);
      return labelsData
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList();
    } catch (e) {
      debugPrint('Could not load labels, using defaults: $e');
      return const ['Normal', 'Pneumonia'];
    }
  }

  Future<ModelInfo> _loadModelInfo() async {
    try {
      final raw = await rootBundle.loadString(_modelInfoPath);
      return ModelInfo.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (e) {
      debugPrint('Could not load model metadata, using fallback: $e');
      return ModelInfo.fallback;
    }
  }

  /// Classify an image file and return the prediction result.
  ///
  /// The image is resized to 224x224 and scaled to [0, 1], matching the
  /// currently bundled multi-output model and the working FastAPI endpoint.
  Future<ClassificationResult> classify(File imageFile) async {
    if (!_isInitialized || _interpreter == null) {
      throw StateError('Classifier not initialized. Call initialize() first.');
    }

    final stopwatch = Stopwatch()..start();

    final imageBytes = await imageFile.readAsBytes();
    final originalImage = img.decodeImage(imageBytes);
    if (originalImage == null) {
      throw ArgumentError('Could not decode image file.');
    }

    final resized = img.copyResize(
      originalImage,
      width: _inputSize,
      height: _inputSize,
      interpolation: img.Interpolation.linear,
    );

    final input = _imageToFloat32List(resized);
    final outputTensors = _interpreter!.getOutputTensors();
    final outputs = _createOutputBuffers(outputTensors);

    try {
      if (outputTensors.length == 1) {
        _interpreter!.run(input, outputs[0]!);
      } else {
        _interpreter!.runForMultipleInputs([input], outputs);
      }
    } catch (e) {
      debugPrint('Multi-output inference failed, trying single output: $e');
      final fallbackOutput = _createOutputBuffer(outputTensors.first.shape);
      _interpreter!.run(input, fallbackOutput);
      outputs
        ..clear()
        ..[0] = fallbackOutput;
    }

    stopwatch.stop();

    final predictionIndex = _findPredictionOutputIndex(outputTensors, outputs);
    final prediction = _readScalar(outputs[predictionIndex]);
    final isPneumonia = prediction > _pneumoniaThreshold;
    final label = isPneumonia
        ? (_labels.length > 1 ? _labels[1] : 'Pneumonia')
        : (_labels.isNotEmpty ? _labels[0] : 'Normal');
    final confidence = isPneumonia ? prediction : (1.0 - prediction);

    Uint8List? heatmapBytes;
    final heatmapIndex = _findHeatmapOutputIndex(
      outputTensors,
      outputs,
      predictionIndex,
    );
    if (heatmapIndex != null) {
      try {
        final focusMap = _extractSpatialMap(outputs[heatmapIndex]);
        if (focusMap != null) {
          heatmapBytes = _generateHeatmapImage(resized, focusMap);
        }
      } catch (e) {
        debugPrint('Failed to generate offline heatmap: $e');
      }
    }

    return ClassificationResult(
      label: label,
      confidence: confidence,
      inferenceTimeMs: stopwatch.elapsedMilliseconds,
      heatmapImage: heatmapBytes,
      modelInfo: _modelInfo,
    );
  }

  Map<int, Object> _createOutputBuffers(List<Tensor> outputTensors) {
    final outputs = <int, Object>{};
    for (var i = 0; i < outputTensors.length; i++) {
      outputs[i] = _createOutputBuffer(outputTensors[i].shape);
    }
    return outputs;
  }

  Object _createOutputBuffer(List<int> shape) {
    final dims = shape.map((dim) => dim <= 0 ? 1 : dim).toList();

    switch (dims.length) {
      case 1:
        return List<double>.filled(dims[0], 0.0);
      case 2:
        return List.generate(dims[0], (_) => List<double>.filled(dims[1], 0.0));
      case 3:
        return List.generate(
          dims[0],
          (_) =>
              List.generate(dims[1], (_) => List<double>.filled(dims[2], 0.0)),
        );
      case 4:
        return List.generate(
          dims[0],
          (_) => List.generate(
            dims[1],
            (_) => List.generate(
              dims[2],
              (_) => List<double>.filled(dims[3], 0.0),
            ),
          ),
        );
      default:
        return List<double>.filled(_elementCount(dims), 0.0);
    }
  }

  int _findPredictionOutputIndex(
    List<Tensor> outputTensors,
    Map<int, Object> outputs,
  ) {
    for (var i = 0; i < outputTensors.length; i++) {
      if (_elementCount(outputTensors[i].shape) == 1) {
        return i;
      }
    }

    for (final entry in outputs.entries) {
      if (_canReadSingleScalar(entry.value)) {
        return entry.key;
      }
    }

    return 0;
  }

  int? _findHeatmapOutputIndex(
    List<Tensor> outputTensors,
    Map<int, Object> outputs,
    int predictionIndex,
  ) {
    for (var i = 0; i < outputTensors.length; i++) {
      if (i == predictionIndex) continue;

      final shape = outputTensors[i].shape;
      if (shape.length == 4 && shape[1] > 1 && shape[2] > 1) {
        return i;
      }
      if (shape.length == 3 && shape[0] > 1 && shape[1] > 1) {
        return i;
      }
    }

    for (final entry in outputs.entries) {
      if (entry.key == predictionIndex) continue;
      if (_extractSpatialMap(entry.value) != null) {
        return entry.key;
      }
    }

    return null;
  }

  int _elementCount(List<int> shape) {
    if (shape.isEmpty) return 1;
    return shape.fold<int>(1, (total, dim) => total * (dim <= 0 ? 1 : dim));
  }

  bool _canReadSingleScalar(Object? value) {
    try {
      _readScalar(value);
      return true;
    } catch (_) {
      return false;
    }
  }

  double _readScalar(Object? value) {
    if (value is num) return value.toDouble();
    if (value is List && value.isNotEmpty) {
      if (value.length == 1) {
        return _readScalar(value.first);
      }
    }
    throw ArgumentError('Output is not a single scalar.');
  }

  List<List<double>>? _extractSpatialMap(Object? value) {
    final root = _asList(value);
    if (root == null || root.isEmpty) return null;

    Object? spatialValue = root;
    if (root.length == 1 && _asList(root.first) != null) {
      spatialValue = root.first;
    }

    final spatial = _asList(spatialValue);
    if (spatial == null || spatial.length < 2) return null;

    final firstRow = _asList(spatial.first);
    if (firstRow == null || firstRow.length < 2) return null;

    return List.generate(spatial.length, (y) {
      final row = _asList(spatial[y]);
      if (row == null) {
        throw ArgumentError('Heatmap row $y is not a list.');
      }

      return List.generate(row.length, (x) {
        final cell = row[x];
        final channels = _asList(cell);
        if (channels == null) {
          return _toDouble(cell);
        }
        return _collapseChannels(channels);
      });
    });
  }

  List<dynamic>? _asList(Object? value) {
    if (value is List) return value.cast<dynamic>();
    return null;
  }

  double _collapseChannels(List<dynamic> channels) {
    if (channels.isEmpty) return 0.0;
    if (channels.length == 1) return _toDouble(channels.first);

    double sum = 0.0;
    for (final channel in channels) {
      sum += math.max(0.0, _toDouble(channel));
    }
    return sum / channels.length;
  }

  double _toDouble(Object? value) {
    if (value is num) return value.toDouble();
    if (value is List && value.isNotEmpty) return _toDouble(value.first);
    throw ArgumentError('Could not read numeric heatmap value.');
  }

  Uint8List _generateHeatmapImage(
    img.Image baseImage,
    List<List<double>> rawHeatmap,
  ) {
    final heatmap = _reluNormalize(rawHeatmap);
    final overlay = img.Image(width: _inputSize, height: _inputSize);

    for (var y = 0; y < _inputSize; y++) {
      for (var x = 0; x < _inputSize; x++) {
        final value = _sampleBilinear(heatmap, x, y);
        final color = _jetColor(value);
        final pixel = baseImage.getPixel(x, y);

        final r = _blendChannel(pixel.r.toDouble(), color[0]);
        final g = _blendChannel(pixel.g.toDouble(), color[1]);
        final b = _blendChannel(pixel.b.toDouble(), color[2]);

        overlay.setPixel(x, y, img.ColorRgb8(r, g, b));
      }
    }

    return Uint8List.fromList(img.encodePng(overlay));
  }

  List<List<double>> _reluNormalize(List<List<double>> heatmap) {
    double maxVal = 0.0;
    final reluMap = List.generate(heatmap.length, (y) {
      return List.generate(heatmap[y].length, (x) {
        final value = math.max(0.0, heatmap[y][x]);
        maxVal = math.max(maxVal, value);
        return value;
      });
    });

    if (maxVal <= 0.0) return reluMap;

    for (var y = 0; y < reluMap.length; y++) {
      for (var x = 0; x < reluMap[y].length; x++) {
        reluMap[y][x] = reluMap[y][x] / maxVal;
      }
    }
    return reluMap;
  }

  double _sampleBilinear(List<List<double>> heatmap, int outX, int outY) {
    final h = heatmap.length;
    final w = heatmap.first.length;

    if (h == 1 && w == 1) return heatmap[0][0];

    final srcX = w == 1 ? 0.0 : outX * (w - 1) / (_inputSize - 1);
    final srcY = h == 1 ? 0.0 : outY * (h - 1) / (_inputSize - 1);

    final x0 = srcX.floor().clamp(0, w - 1);
    final y0 = srcY.floor().clamp(0, h - 1);
    final x1 = (x0 + 1).clamp(0, w - 1);
    final y1 = (y0 + 1).clamp(0, h - 1);
    final dx = srcX - x0;
    final dy = srcY - y0;

    final top = heatmap[y0][x0] * (1.0 - dx) + heatmap[y0][x1] * dx;
    final bottom = heatmap[y1][x0] * (1.0 - dx) + heatmap[y1][x1] * dx;
    return top * (1.0 - dy) + bottom * dy;
  }

  List<int> _jetColor(double value) {
    final v = value.clamp(0.0, 1.0).toDouble();

    int channel(double center) {
      final intensity = (1.5 - (4.0 * v - center).abs()).clamp(0.0, 1.0);
      return (255 * intensity).round().clamp(0, 255);
    }

    return [channel(3.0), channel(2.0), channel(1.0)];
  }

  int _blendChannel(double base, int heatmap) {
    return (base * 0.60 + heatmap * 0.40).round().clamp(0, 255);
  }

  /// Convert an [img.Image] to a [1, 224, 224, 3] float32 tensor.
  List<List<List<List<double>>>> _imageToFloat32List(img.Image image) {
    return List.generate(
      1,
      (_) => List.generate(
        _inputSize,
        (y) => List.generate(_inputSize, (x) {
          final pixel = image.getPixel(x, y);
          return [
            pixel.r.toDouble() / 255.0,
            pixel.g.toDouble() / 255.0,
            pixel.b.toDouble() / 255.0,
          ];
        }),
      ),
    );
  }

  /// Release the interpreter resources.
  void dispose() {
    _interpreter?.close();
    _interpreter = null;
    _isInitialized = false;
  }
}
