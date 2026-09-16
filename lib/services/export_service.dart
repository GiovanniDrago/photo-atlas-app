import 'export_service_stub.dart'
    if (dart.library.io) 'export_service_io.dart'
    if (dart.library.js_interop) 'export_service_web.dart'
    as impl;

Future<String?> saveMetadataExport({
  required String filename,
  required String content,
}) {
  return impl.saveMetadataExport(filename: filename, content: content);
}
