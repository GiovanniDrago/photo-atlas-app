import 'dart:io';

import 'package:url_launcher/url_launcher.dart';

Uri? deviceFolderUri({
  String? relativePath,
  String? absolutePath,
  bool isAndroid = true,
}) {
  if (isAndroid && relativePath != null && relativePath.isNotEmpty) {
    // DocumentsUI opens the system Files app on this folder.
    return Uri.parse(
      'content://com.android.externalstorage.documents/document/'
      'primary%3A${Uri.encodeComponent(relativePath)}',
    );
  }
  if (absolutePath != null && absolutePath.isNotEmpty) {
    return Uri.file(absolutePath);
  }
  return null;
}

Future<bool> openDeviceFolder({
  String? relativePath,
  String? absolutePath,
}) async {
  final uri = deviceFolderUri(
    relativePath: relativePath,
    absolutePath: absolutePath,
    isAndroid: Platform.isAndroid,
  );
  if (uri == null) return false;
  try {
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}
