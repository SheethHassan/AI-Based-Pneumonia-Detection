// =============================================================================
// Image Validation — Pre-inference checks for X-ray uploads
// =============================================================================

import 'dart:io';
import 'package:image/image.dart' as img;

class ImageValidationException implements Exception {
  final String message;
  const ImageValidationException(this.message);

  @override
  String toString() => message;
}

class ImageValidation {
  static const int minWidth = 64;
  static const int minHeight = 64;
  static const int maxBytes = 20 * 1024 * 1024; // 20 MB

  static const _allowedExtensions = {'.jpg', '.jpeg', '.png', '.bmp', '.webp'};

  /// Validates file metadata and decodes the image for downstream use.
  static Future<img.Image> validateAndDecode(File file) async {
    if (!await file.exists()) {
      throw const ImageValidationException('Image file not found.');
    }

    final ext = _extension(file.path);
    if (ext.isNotEmpty && !_allowedExtensions.contains(ext)) {
      throw ImageValidationException(
        'Unsupported file type "$ext". Please use JPG or PNG.',
      );
    }

    final bytes = await file.length();
    if (bytes == 0) {
      throw const ImageValidationException('The selected file is empty.');
    }
    if (bytes > maxBytes) {
      throw const ImageValidationException(
        'Image is too large. Please use a file under 20 MB.',
      );
    }

    final rawBytes = await file.readAsBytes();
    final decoded = img.decodeImage(rawBytes);
    if (decoded == null) {
      throw const ImageValidationException(
        'Could not read this image. The file may be corrupted.',
      );
    }

    if (decoded.width < minWidth || decoded.height < minHeight) {
      throw ImageValidationException(
        'Image is too small (${decoded.width}×${decoded.height}). '
        'Minimum size is $minWidth×$minHeight pixels.',
      );
    }

    return decoded;
  }

  static String _extension(String path) {
    final dot = path.lastIndexOf('.');
    if (dot == -1) return '';
    return path.substring(dot).toLowerCase();
  }
}
