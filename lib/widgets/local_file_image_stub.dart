import 'package:flutter/material.dart';

Widget localFileImage(
  BuildContext context, {
  required String path,
  BoxFit fit = BoxFit.cover,
  Widget Function()? onError,
}) {
  return onError?.call() ?? const SizedBox.shrink();
}
