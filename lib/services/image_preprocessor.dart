// =============================================================================
// Image Preprocessor - deployed DenseNet121 TFLite input scaling
// =============================================================================
// Matches the bundled Colab/FastAPI model input pipeline:
//   channel_value = pixel / 255.0
// =============================================================================

import 'package:image/image.dart' as img;

class ImagePreprocessor {
  static const int defaultInputSize = 224;

  /// Scale a single RGB pixel to the model input range.
  static List<double> normalizePixel(int r, int g, int b) {
    return [_scaleChannel(r), _scaleChannel(g), _scaleChannel(b)];
  }

  static double _scaleChannel(int value) {
    return value / 255.0;
  }

  /// Build a [1, height, width, 3] float tensor from a decoded image.
  static List<List<List<List<double>>>> imageToFloat32Tensor(
    img.Image image, {
    int inputSize = defaultInputSize,
  }) {
    return List.generate(
      1,
      (_) => List.generate(
        inputSize,
        (y) => List.generate(inputSize, (x) {
          final pixel = image.getPixel(x, y);
          return normalizePixel(
            pixel.r.toInt(),
            pixel.g.toInt(),
            pixel.b.toInt(),
          );
        }),
      ),
    );
  }
}
