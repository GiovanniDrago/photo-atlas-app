import 'dart:io';

import 'package:path_provider/path_provider.dart';

Future<String?> saveMetadataExport({
  required String filename,
  required String content,
}) async {
  final base = await getApplicationDocumentsDirectory();
  final directory = Directory('${base.path}/photo-atlas-exports');
  await directory.create(recursive: true);
  final file = File('${directory.path}/$filename');
  await file.writeAsString(content);
  return file.path;
}
