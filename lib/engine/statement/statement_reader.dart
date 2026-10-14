import 'dart:typed_data';

import 'package:pdfrx/pdfrx.dart';

/// The PDF is encrypted and none of the passwords tried opened it.
class StatementLockedException implements Exception {
  const StatementLockedException({required this.triedAny});

  /// True when at least one password was offered and refused, so the UI can
  /// say "that didn't open it" rather than "this statement is locked".
  final bool triedAny;
}

/// The file is not a readable PDF.
class StatementUnreadableException implements Exception {
  const StatementUnreadableException(this.message);
  final String message;
}

/// Opens a statement PDF on the device and returns its text.
///
/// Uses PDFium through pdfrx. Nothing leaves the phone: the bytes go to the
/// native library in this process, the text comes back, the document is
/// disposed.
abstract final class StatementReader {
  /// Reads every page's text, trying [passwords] in order on an encrypted
  /// file. An unencrypted file opens without consulting them. Also returns the
  /// password that opened it (null when none was needed), so the caller can
  /// remember it for that manager.
  static Future<({String text, String? password})> readText(
    Uint8List bytes, {
    List<String> passwords = const [],
  }) async {
    await pdfrxFlutterInitialize();
    var i = 0;
    PdfDocument doc;
    try {
      doc = await PdfDocument.openData(
        bytes,
        // pdfrx calls this again after each refusal; returning null ends the
        // attempts with a PdfPasswordException.
        passwordProvider: () => i < passwords.length ? passwords[i++] : null,
        sourceName:
            'statement-${bytes.length}-${DateTime.now().microsecondsSinceEpoch}',
      );
    } on PdfPasswordException {
      throw StatementLockedException(triedAny: passwords.isNotEmpty);
    } catch (e) {
      throw StatementUnreadableException('$e');
    }

    try {
      final buf = StringBuffer();
      for (final page in doc.pages) {
        final text = await page.loadText();
        if (text != null) {
          buf
            ..write(text.fullText)
            ..write('\n');
        }
      }
      return (text: buf.toString(), password: i == 0 ? null : passwords[i - 1]);
    } finally {
      await doc.dispose();
    }
  }
}
