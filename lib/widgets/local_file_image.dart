import 'package:flutter/material.dart';

import 'local_file_image_stub.dart'
    if (dart.library.io) 'local_file_image_io.dart'
    as impl;

Widget localFileImage(
  BuildContext context, {
  required String path,
  BoxFit fit = BoxFit.cover,
  Widget Function()? onError,
}) {
  return impl.localFileImage(context, path: path, fit: fit, onError: onError);
}
