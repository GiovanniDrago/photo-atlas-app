import 'folder_launcher_stub.dart'
    if (dart.library.io) 'folder_launcher_io.dart'
    as impl;

/// Opens the system file manager on the folder of a device file. Returns
/// false when the platform cannot handle it.
Future<bool> openDeviceFolder({String? relativePath, String? absolutePath}) {
  return impl.openDeviceFolder(
    relativePath: relativePath,
    absolutePath: absolutePath,
  );
}
