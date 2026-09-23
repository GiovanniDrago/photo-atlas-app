import 'dart:io';

import 'package:url_launcher/url_launcher.dart';

Future<bool> openDeviceFolder({
  String? relativePath,
  String? absolutePath,
}) async {
  Uri? uri;
  if (Platform.isAndroid && relativePath != null && relativePath.isNotEmpty) {
    // DocumentsUI opens the system Files app on this folder.
    uri = Uri.parse(
      'content://com.android.externalstorage.documents/document/'
      'primary%3A${Uri.encodeComponent(relativePath)}',
    );
  } else if (absolutePath != null && absolutePath.isNotEmpty) {
    uri = Uri.file(absolutePath);
  }
  if (uri == null) return false;
  try {
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}
