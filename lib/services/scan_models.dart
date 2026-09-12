const imageExtensions = <String>{
  'jpg',
  'jpeg',
  'png',
  'gif',
  'webp',
  'heic',
  'heif',
  'tif',
  'tiff',
  'bmp',
  'avif',
  'dng',
  'cr2',
  'nef',
  'arw',
};

const videoExtensions = <String>{
  'mp4',
  'mov',
  'mkv',
  'webm',
  'avi',
  'm4v',
  '3gp',
  'mpeg',
  'mpg',
};

const mimeByExtension = <String, String>{
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'png': 'image/png',
  'gif': 'image/gif',
  'webp': 'image/webp',
  'heic': 'image/heic',
  'heif': 'image/heif',
  'tif': 'image/tiff',
  'tiff': 'image/tiff',
  'bmp': 'image/bmp',
  'avif': 'image/avif',
  'dng': 'image/x-adobe-dng',
  'cr2': 'image/x-canon-cr2',
  'nef': 'image/x-nikon-nef',
  'arw': 'image/x-sony-arw',
  'mp4': 'video/mp4',
  'mov': 'video/quicktime',
  'mkv': 'video/x-matroska',
  'webm': 'video/webm',
  'avi': 'video/x-msvideo',
  'm4v': 'video/x-m4v',
  '3gp': 'video/3gpp',
  'mpeg': 'video/mpeg',
  'mpg': 'video/mpeg',
};

String extensionOf(String name) {
  final index = name.lastIndexOf('.');
  return index == -1 ? '' : name.substring(index + 1).toLowerCase();
}

String? mediaTypeForExtension(String extension) {
  if (imageExtensions.contains(extension)) return 'image';
  if (videoExtensions.contains(extension)) return 'video';
  return null;
}

class ScannedMedia {
  final String externalKey;
  final String path;
  final String name;
  final String mime;
  final String mediaType;
  final int sizeBytes;
  final DateTime? takenAt;
  final DateTime? modifiedAt;
  final double? lat;
  final double? lon;
  final int? width;
  final int? height;

  const ScannedMedia({
    required this.externalKey,
    required this.path,
    required this.name,
    required this.mime,
    required this.mediaType,
    required this.sizeBytes,
    this.takenAt,
    this.modifiedAt,
    this.lat,
    this.lon,
    this.width,
    this.height,
  });

  Map<String, dynamic> toJson() => {
    'external_key': externalKey,
    'path': path,
    'name': name,
    'mime': mime,
    'media_type': mediaType,
    'size_bytes': sizeBytes,
    'taken_at': takenAt?.toUtc().toIso8601String(),
    'file_created_at': modifiedAt?.toUtc().toIso8601String(),
    'modified_at': modifiedAt?.toUtc().toIso8601String(),
    'lat': lat,
    'lon': lon,
    'width': width,
    'height': height,
  };
}

class ScanResult {
  final int filesSeen;
  final int indexed;

  const ScanResult({required this.filesSeen, required this.indexed});
}

typedef ScanBatchCallback = Future<void> Function(List<ScannedMedia> batch);
typedef ScanProgressCallback = void Function(int seen, int indexed);
