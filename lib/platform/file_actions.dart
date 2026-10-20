import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';

/// Cross-platform text file save/load without `dart:io`.
///
/// - **Export:** `XFile.fromData` + SharePlus (downloads on web, share sheet on mobile).
/// - **Import:** FilePicker with bytes / [PlatformFile.xFile] (works on web).
class FileActions {
  FileActions._();

  static Future<void> saveTextFile({
    required String filename,
    required String content,
    required String mimeType,
    String? subject,
  }) async {
    final bytes = Uint8List.fromList(utf8.encode(content));
    final file = XFile.fromData(
      bytes,
      mimeType: mimeType,
      name: filename,
      length: bytes.length,
    );
    await SharePlus.instance.share(
      ShareParams(
        files: [file],
        subject: subject ?? filename,
        title: subject ?? filename,
        fileNameOverrides: [filename],
      ),
    );
  }

  /// Picks a text file and returns its UTF-8 contents, or null if cancelled.
  static Future<String?> pickTextFile({
    required List<String> extensions,
  }) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: extensions,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return null;
    final picked = result.files.first;
    if (picked.bytes != null) {
      return utf8.decode(picked.bytes!, allowMalformed: true);
    }
    // Mobile may only expose a path; XFile abstracts read without dart:io.
    return picked.xFile.readAsString();
  }
}
