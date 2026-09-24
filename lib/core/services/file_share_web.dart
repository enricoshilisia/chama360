import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// The browser: a plain download. The Web Share API exists but is absent on
/// desktop Chrome and refuses files on several others, and a chairperson
/// installing this on a Mac expects a file in Downloads.
Future<void> saveOrShareBytes({
  required Uint8List bytes,
  required String fileName,
  required String mimeType,
  String? subject,
}) async {
  final blob = web.Blob(
    [bytes.toJS].toJS,
    web.BlobPropertyBag(type: mimeType),
  );
  final url = web.URL.createObjectURL(blob);

  final anchor = web.document.createElement('a') as web.HTMLAnchorElement
    ..href = url
    ..download = fileName
    ..style.display = 'none';

  web.document.body?.appendChild(anchor);
  anchor.click();
  anchor.remove();

  // Give the download a moment to start before the blob goes away.
  await Future<void>.delayed(const Duration(milliseconds: 200));
  web.URL.revokeObjectURL(url);
}
