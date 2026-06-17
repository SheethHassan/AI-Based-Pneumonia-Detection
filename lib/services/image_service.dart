// =============================================================================
// Image Service — Gallery Image Picker
// =============================================================================
// Uses image_picker to select an image from the gallery.
// No camera access — gallery only per requirements.
// =============================================================================

import 'dart:io';
import 'package:image_picker/image_picker.dart';

class ImagePickerException implements Exception {
  final String message;
  const ImagePickerException(this.message);

  @override
  String toString() => message;
}

class ImageService {
  final ImagePicker _picker = ImagePicker();

  /// Pick an image from the device gallery.
  ///
  /// Returns the selected [File] or null if the user cancelled.
  /// Throws [ImagePickerException] when picking fails.
  Future<File?> pickFromGallery() async {
    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 90,
      );

      if (pickedFile != null) {
        return File(pickedFile.path);
      }
      return null;
    } on Exception catch (e) {
      final message = e.toString().toLowerCase();
      if (message.contains('permission') || message.contains('denied')) {
        throw const ImagePickerException(
          'Gallery access was denied. Please allow photo permissions in settings.',
        );
      }
      throw ImagePickerException(
        'Could not open the gallery. Please try again.',
      );
    }
  }
}
