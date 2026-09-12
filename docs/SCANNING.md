# Local folder scanning

Available on Android and Linux desktop. The web cannot read arbitrary local folders, so the web
build falls back to kDrive or the manual API.

## What is indexed

For every image or video found in the selected folder (recursively):

| Field | Source |
|---|---|
| name, path, size | filesystem |
| MIME type, image/video | file extension |
| taken_at | EXIF `DateTimeOriginal` / `DateTimeDigitized` / `DateTime` |
| lat, lon | EXIF GPS IFD converted from degrees/minutes/seconds |
| width, height | EXIF image dimensions |
| modified_at, file_created_at | filesystem timestamps |

Items are sent to `POST /api/media/batch` in batches of 100 and upserted per `(source, path)`.
The API derives `metadata_status`:

- `full`: capture date and GPS
- `partial`: only one of them
- `none`: neither; the item still appears in the gallery, marked "No metadata"

## Implementation

- `lib/services/scan_service.dart` chooses the platform implementation at compile time
  (`scan_service_io.dart` on Android/Linux, `scan_service_stub.dart` on the web).
- Files are enumerated with `Directory.list(recursive: true, followLinks: false)`.
- For images, the first 256 KB are read and parsed with `package:exif` inside
  `Isolate.run`, so the UI thread never blocks on large files.
- Videos are indexed from filesystem metadata only; container metadata is not parsed.
- Progress is reported to the settings screen (files seen / indexed) and the scan is tracked as a
  `scan_run` row so it appears in the API history.

## Android notes

- Folder picking uses `file_picker`'s directory picker. Android's storage access framework may
  return a path that is readable only for the current session; if a folder cannot be re-scanned,
  pick it again.
- Grant media read permission when the system asks (the release manifest declares `INTERNET`;
  storage access is granted per-folder by the picker).

## Rerunning a scan

Scanning the same folder again reuses the existing `local` source for that path and updates changed
rows, so it is safe to re-run. To start over, delete the source with
`DELETE /api/sources/:id` and scan again.

## Troubleshooting

| Symptom | Fix |
|---|---|
| `scanUnsupportedWeb` snackbar | Use Android/Linux or kDrive |
| Scan finishes with 0 indexed | The folder has no supported extensions |
| Items without date/GPS | Files have no EXIF; they appear in the gallery with a badge |
| API rejects a batch | Check the API logs; batches are limited to 500 items |
