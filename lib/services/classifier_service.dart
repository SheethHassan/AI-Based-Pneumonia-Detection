// =============================================================================
// Classifier Service — TFLite Inference Engine (DenseNet121)
// =============================================================================
// Loads the DenseNet121-based TFLite pneumonia detection model, preprocesses
// images (resize to 224×224, apply ImageNet normalization), runs inference,
// and returns a ClassificationResult.
//
// DenseNet121 Preprocessing:
//   1. Resize to 224×224
//   2. Scale pixel values to [0, 1]
//   3. Normalize with ImageNet mean & std:
//      mean = [0.485, 0.456, 0.406]
//      std  = [0.229, 0.224, 0.225]
//
// Model Output:
//   Sigmoid value [1, 1] — >0.5 = Pneumonia, ≤0.5 = Normal
// =============================================================================

import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'dart:typed_data';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;
import '../models/classification_result.dart';

class ClassifierService {
  static const String _modelPath = 'assets/model/densenet_pneumonia.tflite';
  static const String _labelsPath = 'assets/model/labels.txt';
  static const int _inputSize = 224;

  // ImageNet normalization constants (used by DenseNet121)
  static const List<double> _imagenetMean = [0.485, 0.456, 0.406];
  static const List<double> _imagenetStd = [0.229, 0.224, 0.225];

  Interpreter? _interpreter;
  List<String> _labels = [];
  bool _isInitialized = false;

  /// Whether the model is loaded and ready
  bool get isReady => _isInitialized;

  // ── Initialize ─────────────────────────────────────────────────────────────
  /// Load the TFLite model and labels from assets
  Future<void> initialize() async {
    try {
      final options = InterpreterOptions()..threads = 4;
      
      // Try loading with relative path (standard for tflite_flutter)
      final relativePath = _modelPath.replaceFirst('assets/', '');
      
      try {
        debugPrint('Attempting to load model from: $relativePath');
        _interpreter = await Interpreter.fromAsset(relativePath, options: options);
      } catch (e) {
        debugPrint('Failed to load from relative path, trying full path: $_modelPath');
        // If relative fails, try full path (some versions/platforms differ)
        _interpreter = await Interpreter.fromAsset(_modelPath, options: options);
      }

      if (_interpreter == null) {
        throw Exception('Interpreter could not be initialized.');
      }

      debugPrint('Model loaded successfully.');
      
      // Log model output details to see if it supports Grad-CAM (multiple outputs)
      final outputTensors = _interpreter!.getOutputTensors();
      debugPrint('Model has ${outputTensors.length} outputs:');
      for (var i = 0; i < outputTensors.length; i++) {
        debugPrint('  Output $i: name=${outputTensors[i].name}, shape=${outputTensors[i].shape}, type=${outputTensors[i].type}');
      }
      
      // Load labels
      debugPrint('Loading labels from: $_labelsPath');
      final labelsData = await rootBundle.loadString(_labelsPath);
      _labels = labelsData
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList();

      _isInitialized = true;
      debugPrint('Classifier initialized with labels: $_labels');
    } catch (e) {
      debugPrint('CRITICAL ERROR: Failed to initialize ClassifierService: $e');
      _isInitialized = false;
      rethrow;
    }
  }

  // ── Classify ───────────────────────────────────────────────────────────────
  /// Classify an image file and return the prediction result.
  ///
  /// The image is resized to 224×224 and normalized using ImageNet statistics
  /// (matching DenseNet121 training preprocessing).
  /// Returns a [ClassificationResult] with the label, confidence, and time.
  Future<ClassificationResult> classify(File imageFile) async {
    if (!_isInitialized || _interpreter == null) {
      throw StateError('Classifier not initialized. Call initialize() first.');
    }

    final stopwatch = Stopwatch()..start();

    // --- Load and preprocess image ---
    final imageBytes = await imageFile.readAsBytes();
    final originalImage = img.decodeImage(imageBytes);
    if (originalImage == null) {
      throw ArgumentError('Could not decode image file.');
    }

    // Resize to 224×224 for model input
    final resized = img.copyResize(
      originalImage,
      width: _inputSize,
      height: _inputSize,
      interpolation: img.Interpolation.linear,
    );

    // Convert to float32 tensor [1, 224, 224, 3] with ImageNet normalization
    final input = _imageToFloat32List(resized);

    // --- Run inference ---
    // We expect two outputs if the model supports Grad-CAM:
    // 1. [1, 1] - Probability (sigmoid)
    // 2. [1, 7, 7, 1024] - Conv layer activations
    
    final outputTensors = _interpreter!.getOutputTensors();
    final outputs = <int, Object>{};
    
    // Prepare output buffers based on model metadata
    for (var i = 0; i < outputTensors.length; i++) {
      final shape = outputTensors[i].shape;
      final type = outputTensors[i].type;
      
      // Initialize multi-dimensional lists based on shapes
      if (shape.length == 2) {
        // Likely [1, 1]
        outputs[i] = List.filled(shape[0], List.filled(shape[1], 0.0));
      } else if (shape.length == 4) {
        // Likely [1, 7, 7, 1024]
        outputs[i] = List.generate(shape[0], 
          (_) => List.generate(shape[1], 
            (_) => List.generate(shape[2], 
              (_) => List.generate(shape[3], (_) => 0.0))));
      } else {
        outputs[i] = List.filled(1, 0.0);
      }
    }

    try {
      _interpreter!.runForMultipleInputs([input], outputs);
    } catch (e) {
      debugPrint('Multi-output inference failed, falling back to single output: $e');
      final fallbackOutput = List.filled(1, List.filled(1, 0.0));
      _interpreter!.run(input, fallbackOutput);
      outputs[0] = fallbackOutput;
    }

    stopwatch.stop();

    // --- Interpret result ---
    // Assuming output 0 is probability
    final predictionList = outputs[0] as List<List<double>>;
    final prediction = predictionList[0][0];

    final isPneumonia = prediction > 0.5;
    final label = isPneumonia
        ? (_labels.length > 1 ? _labels[1] : 'Pneumonia')
        : (_labels.isNotEmpty ? _labels[0] : 'Normal');
    final confidence = isPneumonia ? prediction : (1.0 - prediction);

    // --- Generate Grad-CAM Heatmap ---
    Uint8List? heatmapBytes;
    if (outputs.length > 1) {
      try {
        final activations = outputs[1] as List<List<List<List<double>>>>;
        heatmapBytes = _generateHeatmapImage(resized, activations[0]);
      } catch (e) {
        debugPrint('Failed to generate heatmap: $e');
      }
    }

    return ClassificationResult(
      label: label,
      confidence: confidence,
      inferenceTimeMs: stopwatch.elapsedMilliseconds,
      heatmapImage: heatmapBytes,
    );
  }

  // ── Grad-CAM Heatmap Generation ─────────────────────────────────────────────
  /// Generates a heatmap image by averaging the last conv layer activations
  /// and overlaying them onto the original resized image.
  Uint8List _generateHeatmapImage(img.Image baseImage, List<List<List<double>>> activations) {
    final h = activations.length; // 7
    final w = activations[0].length; // 7
    final c = activations[0][0].length; // 1024

    // 1. Average across channels to get a [7, 7] heatmap
    final heatmap = List.generate(h, (_) => List.filled(w, 0.0));
    double maxVal = -double.infinity;
    double minVal = double.infinity;

    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        double sum = 0;
        for (var k = 0; k < c; k++) {
          sum += activations[y][x][k];
        }
        heatmap[y][x] = sum / c;
        if (heatmap[y][x] > maxVal) maxVal = heatmap[y][x];
        if (heatmap[y][x] < minVal) minVal = heatmap[y][x];
      }
    }

    // 2. Normalize to [0, 1]
    if (maxVal > minVal) {
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          heatmap[y][x] = (heatmap[y][x] - minVal) / (maxVal - minVal);
        }
      }
    }

    // 3. Upscale and Colorize
    final overlay = img.Image(width: _inputSize, height: _inputSize);
    
    for (var y = 0; y < _inputSize; y++) {
      for (var x = 0; x < _inputSize; x++) {
        // Bi-linear interpolation (simple version: nearest neighbor)
        final hX = (x / _inputSize * w).floor().clamp(0, w - 1);
        final hY = (y / _inputSize * h).floor().clamp(0, h - 1);
        final value = heatmap[hY][hX];

        // Apply Jet colormap (Blue -> Green -> Red)
        // value 0.0 (blue) -> 0.5 (green) -> 1.0 (red)
        int r, g, b;
        if (value < 0.5) {
          r = 0;
          g = (value * 2 * 255).toInt();
          b = ((0.5 - value) * 2 * 255).toInt();
        } else {
          r = ((value - 0.5) * 2 * 255).toInt();
          g = ((1.0 - value) * 2 * 255).toInt();
          b = 0;
        }

        // Blend with original image (alpha 0.5)
        final pixel = baseImage.getPixel(x, y);
        final finalR = (pixel.r * 0.4 + r * 0.6).toInt().clamp(0, 255);
        final finalG = (pixel.g * 0.4 + g * 0.6).toInt().clamp(0, 255);
        final finalB = (pixel.b * 0.4 + b * 0.6).toInt().clamp(0, 255);

        overlay.setPixel(x, y, img.ColorRgb8(finalR, finalG, finalB));
      }
    }

    return Uint8List.fromList(img.encodeJpg(overlay));
  }

  // ── Image Preprocessing ────────────────────────────────────────────────────
  /// Convert an [img.Image] to a [1, 224, 224, 3] float32 tensor.
  ///
  /// Applies DenseNet121 / ImageNet preprocessing:
  ///   1. Scale pixel values to [0, 1] by dividing by 255.0
  ///   2. Normalize each channel: (value - mean) / std
  ///      R: mean=0.485, std=0.229
  ///      G: mean=0.456, std=0.224
  ///      B: mean=0.406, std=0.225
  List<List<List<List<double>>>> _imageToFloat32List(img.Image image) {
    final result = List.generate(
      1,
      (_) => List.generate(
        _inputSize,
        (y) => List.generate(
          _inputSize,
          (x) {
            final pixel = image.getPixel(x, y);
            // Scale to [0, 1] then apply ImageNet normalization
            final r = (pixel.r.toDouble() / 255.0 - _imagenetMean[0]) / _imagenetStd[0];
            final g = (pixel.g.toDouble() / 255.0 - _imagenetMean[1]) / _imagenetStd[1];
            final b = (pixel.b.toDouble() / 255.0 - _imagenetMean[2]) / _imagenetStd[2];
            return [r, g, b];
          },
        ),
      ),
    );
    return result;
  }

  // ── Dispose ────────────────────────────────────────────────────────────────
  /// Release the interpreter resources
  void dispose() {
    _interpreter?.close();
    _interpreter = null;
    _isInitialized = false;
  }
}
