import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Phones and desktops: write the file somewhere real, then hand it to the
/// system share sheet. That is what gets a workbook off a phone and into
/// Drive, WhatsApp or an email — saving it silently into an app-private
/// directory would leave the chairperson with no way to reach it.
Future<void> saveOrShareBytes({
  required Uint8List bytes,
  required String fileName,
  required String mimeType,
  String? subject,
}) async {
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}${Platform.pathSeparator}$fileName');
  await file.writeAsBytes(bytes, flush: true);

  await SharePlus.instance.share(
    ShareParams(
      files: [XFile(file.path, mimeType: mimeType, name: fileName)],
      subject: subject,
      fileNameOverrides: [fileName],
    ),
  );
}
