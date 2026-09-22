import 'dart:io';

import 'package:flutter/material.dart';

Widget localFileImage(
  BuildContext context, {
  required String path,
  BoxFit fit = BoxFit.cover,
  Widget Function()? onError,
}) {
  return Image.file(
    File(path),
    fit: fit,
    errorBuilder: (context, error, stackTrace) =>
        onError?.call() ?? const SizedBox.shrink(),
  );
}
