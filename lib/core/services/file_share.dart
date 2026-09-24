import 'dart:typed_data';

import 'file_share_io.dart' if (dart.library.js_interop) 'file_share_web.dart';

/// Hands a generated file to the person, in whatever way the platform they
/// are on actually delivers files.
///
/// On the web that means a download; on a phone it means writing the file
/// somewhere durable and opening the share sheet, which is how a
/// chairperson gets a workbook onto their laptop or into their email.
Future<void> shareBytes({
  required Uint8List bytes,
  required String fileName,
  required String mimeType,
  String? subject,
}) {
  return saveOrShareBytes(
    bytes: bytes,
    fileName: fileName,
    mimeType: mimeType,
    subject: subject,
  );
}
