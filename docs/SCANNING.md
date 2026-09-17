# Local folder scanning

Available on Android and Linux desktop. The web cannot read arbitrary local folders, so the web
build falls back to kDrive or the manual API.

## What is indexed

| Field | Android (media albums) | Linux desktop (folders) |
|---|---|---|
| name, path, size | MediaStore + app cache file | filesystem |
| MIME type, image/video | MediaStore | file extension |
| taken_at | `asset.createDateTime` | EXIF `DateTimeOriginal` / `DateTimeDigitized` / `DateTime` |
| lat, lon | EXIF GPS via `AssetEntity.latlngAsync()` | EXIF GPS IFD converted from degrees/minutes/seconds |
| width, height | MediaStore | EXIF image dimensions |
| modified_at, file_created_at | MediaStore | filesystem timestamps |
| preview | 320 px JPEG uploaded with the batch | generated server side from the file path |

Items are sent to `POST /api/media/batch` in batches of 100 and upserted per
`(source, external_key)`. The API derives `metadata_status`:

- `full`: capture date and GPS
- `partial`: only one of them
- `none`: neither; the item still appears in the gallery, marked "No metadata"

## Android

Android uses the system media library (`photo_manager`), not raw file paths: scoped storage does
not grant apps read access to folders returned by a file picker, so a path-based scan can silently
find 0 files.

- *Add folder* opens the album picker (Camera, Download, app albums…); the chosen album is stored
  as `rootPath = album:<id>` and re-scanned through MediaStore.
- The first scan asks for the media permission and, on Android 10+, for the photo **location**
  permission (`ACCESS_MEDIA_LOCATION`). Without it `MediaStore` redacts GPS and the plugin returns
  no coordinates even though the file contains them. `AssetEntity.latitude` is always null on
  Android 10+; the app calls `latlngAsync()`, which reads EXIF (or video metadata) from the original
  file.
- Preview thumbnails are generated on the phone (`thumbnailDataWithSize`, 320 px, quality 75) and
  uploaded as `thumbnail_b64` because the API cannot read files that live only on the device.
  Rescanning overwrites them.
- Videos are indexed with MediaStore duration; location comes from the video metadata.
- Settings → Local folders lists every source with its indexed count and last scan; *Scan again*
  refreshes date, GPS and previews, *Delete* removes the index only (files are never touched).

## Linux desktop

Files are enumerated with `Directory.list(recursive: true, followLinks: false)`. For images, the
first 256 KB are read and parsed with `package:exif` inside `Isolate.run`, so the UI thread never
blocks on large files. Videos are indexed from filesystem metadata; container metadata is not
parsed. Thumbnails and downloads are served by the API directly from the paths, which works when
the API runs on the same machine (the normal setup); a remote API cannot read those files.

## Rerunning a scan

Scanning the same album/folder again reuses the existing `local` source (matched by `root_path`)
and updates changed rows, so it is safe to re-run. This is how GPS and previews are backfilled for
items indexed by older versions.

## Troubleshooting

| Symptom | Fix |
|---|---|
| `scanUnsupportedWeb` snackbar | Use Android/Linux or kDrive |
| Scan finishes with 0 indexed | The album/folder has no images or videos |
| Items without GPS | Grant the photo location permission (`ACCESS_MEDIA_LOCATION`), then *Scan again*; files without EXIF GPS stay empty |
| Gray placeholders instead of previews | Rescan the album so the thumbnails are uploaded; restart the app if a placeholder is still cached |
| API rejects a batch | Check the API logs; batches are limited to 500 items |
