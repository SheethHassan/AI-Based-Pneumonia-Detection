import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pneumonia_detection/models/model_info.dart';
import 'package:pneumonia_detection/services/image_preprocessor.dart';
import 'package:pneumonia_detection/services/image_validation.dart';

void main() {
  group('ModelInfo', () {
    test('fromJson parses metadata', () {
      final info = ModelInfo.fromJson({
        'name': 'DenseNet121',
        'version': '2.0.0',
        'inputSize': 224,
        'classes': ['Normal', 'Pneumonia'],
        'format': 'TensorFlow Lite',
        'description': 'Test model',
      });

      expect(info.displayLabel, 'DenseNet121 v2.0.0');
      expect(info.inputSize, 224);
    });
  });

  group('ImageValidation', () {
    test('rejects missing file', () async {
      final file = File('nonexistent_test_image.jpg');
      expect(
        () => ImageValidation.validateAndDecode(file),
        throwsA(isA<ImageValidationException>()),
      );
    });
  });

  group('ImagePreprocessor', () {
    test('normalizePixel scales channels to 0..1', () {
      final white = ImagePreprocessor.normalizePixel(255, 255, 255);
      expect(white[0], closeTo(1.0, 1e-9));
      expect(white[1], closeTo(1.0, 1e-9));
      expect(white[2], closeTo(1.0, 1e-9));

      final black = ImagePreprocessor.normalizePixel(0, 0, 0);
      expect(black[0], closeTo(0.0, 1e-9));
      expect(black[1], closeTo(0.0, 1e-9));
      expect(black[2], closeTo(0.0, 1e-9));
    });

    test('normalizePixel handles mid-gray channel independently', () {
      final gray = ImagePreprocessor.normalizePixel(128, 128, 128);
      expect(gray[0], closeTo(128 / 255.0, 1e-9));
      expect(gray[1], closeTo(128 / 255.0, 1e-9));
      expect(gray[2], closeTo(128 / 255.0, 1e-9));
    });

    test('imageToFloat32Tensor produces correct shape and corner values', () {
      const size = 4;
      final image = img.Image(width: size, height: size);
      image.setPixel(0, 0, img.ColorRgb8(255, 0, 0));
      image.setPixel(3, 3, img.ColorRgb8(0, 0, 255));

      final tensor = ImagePreprocessor.imageToFloat32Tensor(
        image,
        inputSize: size,
      );

      expect(tensor.length, 1);
      expect(tensor[0].length, size);
      expect(tensor[0][0].length, size);
      expect(tensor[0][0][0].length, 3);

      final topLeft = tensor[0][0][0];
      expect(topLeft[0], closeTo(1.0, 1e-9));
      expect(topLeft[1], closeTo(0.0, 1e-9));
      expect(topLeft[2], closeTo(0.0, 1e-9));

      final bottomRight = tensor[0][3][3];
      expect(bottomRight[0], closeTo(0.0, 1e-9));
      expect(bottomRight[1], closeTo(0.0, 1e-9));
      expect(bottomRight[2], closeTo(1.0, 1e-9));
    });

    test('default input size matches deployed model', () {
      expect(ImagePreprocessor.defaultInputSize, 224);
    });
  });
}
