// =============================================================================
// Result Export Service — Save, PDF, and share analysis results
// =============================================================================

import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import '../models/classification_result.dart';
import '../models/model_info.dart';

class ResultSaveException implements Exception {
  final String message;
  const ResultSaveException(this.message);

  @override
  String toString() => message;
}

class ResultExportService {
  /// Saves the X-ray image, a text report (for legacy support/simple parsing),
  /// and a PDF report to app storage.
  static Future<String> saveResult({
    required ClassificationResult result,
    required File imageFile,
    ModelInfo? modelInfo,
  }) async {
    try {
      final saveDir = await _createSaveDirectory();
      final info = modelInfo ?? result.modelInfo ?? ModelInfo.fallback;
      // Preserve the original file extension (supports .jpg, .png, .jpeg, .webp)
      final ext = _imageExtension(imageFile.path);
      final savedImage = await imageFile.copy('${saveDir.path}/xray$ext');

      // Write the plain‑text report for easy parsing/debugging
      await File('${saveDir.path}/report.txt')
          .writeAsString(_buildTextReport(result, info, DateTime.now()));

      // Generate a PDF in the SAME folder (instead of a separate call that creates a new folder)
      final pdfFile = await _generatePdfReportInFolder(
        result: result,
        imageFile: savedImage,
        modelInfo: info,
        folder: saveDir,
      );

      // On Android, trigger a media‑scan so the file appears in the emulator's file explorer
      if (Platform.isAndroid) {
        try {
          // ignore: avoid_dynamic_calls
          await const MethodChannel('com.example.omnisense/media_scanner')
              .invokeMethod('scanFile', pdfFile.path);
        } catch (_) {
          // If the channel is not set up, we silently ignore – the file is still accessible via the path.
        }
      }

      return saveDir.path;
    } catch (e) {
      throw ResultSaveException('Failed to save result: $e');
    }
  }

  /// Internal helper that creates a PDF **inside** the provided folder.
  /// This avoids creating a second timestamped folder when `saveResult`
  /// already generated one.
  static Future<File> _generatePdfReportInFolder({
    required ClassificationResult result,
    required File imageFile,
    ModelInfo? modelInfo,
    required Directory folder,
  }) async {
    try {
      final info = modelInfo ?? result.modelInfo ?? ModelInfo.fallback;
      final timestamp = DateTime.now();
      final pdfPath = '${folder.path}/report.pdf';

      final imageBytes = await imageFile.readAsBytes();
      final pdfImage = pw.MemoryImage(imageBytes);

      final doc = pw.Document();
      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(40),
          build: (context) => [
            pw.Text(
              'OmniSense AI',
              style: pw.TextStyle(
                fontSize: 22,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.blue800,
              ),
            ),
            pw.Text(
              'Chest X-Ray Analysis Report',
              style: pw.TextStyle(fontSize: 16, color: PdfColors.grey700),
            ),
            pw.SizedBox(height: 8),
            pw.Text(
              'Generated: ${timestamp.toLocal()}',
              style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
            ),
            pw.Divider(),
            pw.SizedBox(height: 12),
            pw.Center(
              child: pw.Container(
                constraints: const pw.BoxConstraints(maxHeight: 280),
                child: pw.Image(pdfImage, fit: pw.BoxFit.contain),
              ),
            ),
            pw.SizedBox(height: 20),
            _pdfDetailRow('Result', result.label),
            _pdfDetailRow('Confidence', result.confidencePercent),
            _pdfDetailRow('Inference Time', '${result.inferenceTimeMs} ms'),
            _pdfDetailRow('Model', info.displayLabel),
            _pdfDetailRow('Processing', 'On-device inference'),
            pw.SizedBox(height: 24),
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                color: PdfColors.amber50,
                border: pw.Border.all(color: PdfColors.amber200),
                borderRadius: pw.BorderRadius.circular(8),
              ),
              child: pw.Text(
                'Disclaimer: For educational and support purposes only. '
                'Not a substitute for professional medical diagnosis.',
                style: pw.TextStyle(fontSize: 9, color: PdfColors.grey800),
              ),
            ),
          ],
        ),
      );

      final pdfBytes = await doc.save();
      final pdfFile = File(pdfPath);
      await pdfFile.writeAsBytes(pdfBytes);
      return pdfFile;
    } catch (e) {
      throw ResultSaveException('Failed to generate PDF: $e');
    }
  }

  /// Share a PDF report. The PDF is generated **in the same folder** as the image and txt report.
  static Future<void> sharePdfReport({
    required ClassificationResult result,
    required File imageFile,
    ModelInfo? modelInfo,
  }) async {
    final tempDir = await getTemporaryDirectory();
    final pdfFile = await _generatePdfReportInFolder(
      result: result,
      imageFile: imageFile,
      modelInfo: modelInfo,
      folder: tempDir,
    );

    await Share.shareXFiles(
      [XFile(pdfFile.path, mimeType: 'application/pdf')],
      subject: 'OmniSense AI — ${result.label} Report',
      text: 'Chest X-Ray Analysis: ${result.label} (${result.confidencePercent})',
    );
  }

  static pw.Widget _pdfDetailRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 8),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 120,
            child: pw.Text(
              label,
              style: pw.TextStyle(
                fontSize: 11,
                color: PdfColors.grey700,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
          pw.Expanded(
            child: pw.Text(value, style: const pw.TextStyle(fontSize: 11)),
          ),
        ],
      ),
    );
  }

  static String _buildTextReport(
    ClassificationResult result,
    ModelInfo info,
    DateTime timestamp,
  ) {
    final buffer = StringBuffer()
      ..writeln('OmniSense AI — Chest X-Ray Analysis Report')
      ..writeln('Saved: ${timestamp.toLocal()}')
      ..writeln('─────────────────────────────────')
      ..writeln('Result: ${result.label}')
      ..writeln('Confidence: ${result.confidencePercent}')
      ..writeln('Inference Time: ${result.inferenceTimeMs} ms')
      ..writeln('Model: ${info.displayLabel}')
      ..writeln('Processing: On-device inference')
      ..writeln()
      ..writeln(
        'Disclaimer: For educational and support purposes only. '
        'Not a substitute for professional medical diagnosis.',
      );
    return buffer.toString();
  }

  static Future<Directory> _createSaveDirectory() async {
    // On Android we store results in external storage so they are visible
    // via the emulator's file explorer. For other platforms we keep the
    // existing documents directory.
    final Directory baseDir =
        Platform.isAndroid ? await getExternalStorageDirectory() ?? await getApplicationDocumentsDirectory() : await getApplicationDocumentsDirectory();
    final timestamp = DateTime.now();
    final folderName =
        'scan_${timestamp.year}${_pad(timestamp.month)}${_pad(timestamp.day)}'
        '_${_pad(timestamp.hour)}${_pad(timestamp.minute)}${_pad(timestamp.second)}';
    final saveDir = Directory('${baseDir.path}/scan_results/$folderName');
    if (!await saveDir.exists()) {
      await saveDir.create(recursive: true);
    }
    return saveDir;
  }

  static String _pad(int n) => n.toString().padLeft(2, '0');

  static String _imageExtension(String path) {
    final dot = path.lastIndexOf('.');
    if (dot == -1) return '.jpg';
    final ext = path.substring(dot).toLowerCase();
    if (ext == '.png' || ext == '.jpg' || ext == '.jpeg' || ext == '.webp') {
      return ext == '.jpeg' ? '.jpg' : ext;
    }
    return '.jpg';
  }
}
