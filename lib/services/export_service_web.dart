import 'dart:convert';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

Future<String?> saveMetadataExport({
  required String filename,
  required String content,
}) async {
  final bytes = utf8.encode(content);
  final blob = web.Blob(
    [bytes.toJS].toJS,
    web.BlobPropertyBag(type: 'application/json'),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = filename;
  web.document.body?.appendChild(anchor);
  anchor.click();
  anchor.remove();
  web.URL.revokeObjectURL(url);
  return filename;
}
