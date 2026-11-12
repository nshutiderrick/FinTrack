import 'package:flutter/services.dart';

/// The text of a PDF on the phone, one table cell per line (android/.../PdfText.kt).
class PdfTextReader {
  const PdfTextReader();

  static const _channel = MethodChannel('expense_tracker/pdf');

  /// Throws [PdfPasswordException] for a password-protected PDF.
  Future<List<String>> lines(String path) async {
    try {
      final text = await _channel.invokeMethod<String>('text', path) ?? '';
      return text.split('\n');
    } on PlatformException catch (e) {
      if (e.code == 'password') throw const PdfPasswordException();
      rethrow;
    }
  }
}

class PdfPasswordException implements Exception {
  const PdfPasswordException();
}
