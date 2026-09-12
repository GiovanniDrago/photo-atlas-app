import 'scan_models.dart';

bool get isSupported => false;

Future<ScanResult> scanDirectory({
  required String directoryPath,
  required ScanBatchCallback onBatch,
  required ScanProgressCallback onProgress,
}) async {
  throw UnsupportedError(
    'Local folder scanning is not available on the web. Use kDrive or the Android/Linux app.',
  );
}
