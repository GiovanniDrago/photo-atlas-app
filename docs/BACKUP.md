# Backup to kDrive

Originals are uploaded to kDrive under `Media/PhotoAtlas` (configurable with `KDRIVE_BASE_PATH` on
the API):

| Upload | Destination |
|---|---|
| Manual selection (central **+** button) | `Media/PhotoAtlas/Manual` |
| Folder backup (*Back up now*) | `Media/PhotoAtlas/<folder>` (album/folder name) |

Files keep their original name; kDrive is asked to rename on conflict, so nothing is ever
overwritten. Albums are database relations, never kDrive folders.

## How it works

1. **Index first**: every file is indexed before the upload (metadata, GPS, thumbnail) through
   `POST /api/media/batch`; the response returns the new ids so the app can upload immediately.
2. **Upload**: the app streams the original (`asset.originFile` on Android, the file on Linux) to
   `POST /api/media/:id/upload`; the API writes it to a temporary file, computes the SHA-256 while
   streaming, extracts EXIF server-side, uploads to kDrive (direct up to 1 GB, chunked session
   above) and stores `backup_status`, `kdrive_file_id`, `content_hash` and `backed_up_at`.
3. **Verify** (*Verify backup*): the API checks each backed-up file on kDrive
   (`GET /3/drive/{drive}/files/{id}`); a missing file or a size mismatch puts the item back to
   `pending` so the next backup uploads it again.
4. **Status**: gallery, timeline and detail show a cloud badge (uploaded / pending / failed); the
   Backup screen shows per-folder counters.

## Requirements

- kDrive connected in Settings → kDrive (the token is stored encrypted on the server).
- The app must be able to reach the API (`http://<vm-ip>:8787` by default on Android).
- Uploads run in the foreground by default; Android can also back up periodically in the
  background (see below).

## Automatic backup (Android)

The Backup screen has an **Automatic backup** switch, **off by default**. When it is on, the app
registers a periodic Android job (WorkManager, promoted to a foreground service with a
notification) that scans the selected folders for new media and uploads everything still pending.

- Configurable: frequency (15 min / 1 h / **6 h** / 24 h), *Only on Wi-Fi* (on by default) and
  *Only while charging* (off by default).
- Per-folder switches decide what is included; when the global switch is turned on and no folder is
  selected, the app offers to enable them all.
- Enabling asks for the notification permission (Android 13+); the job runs even if it is denied.
- Each run stops after ~8 minutes and the next run continues: the queue lives on the server
  (`GET /api/backup/pending` claims items with `backup_status='uploading'`, so a foreground run and
  the background job never upload the same file twice; claims older than 2 hours are released).
- A completed backup run updates `sources.backup_last_run_at`, shown in the Backup screen.
- Android may defer the job (Doze, battery optimization): whitelist the app if backups seem late.
- Linux and the web build schedule nothing; on Linux backups run in the foreground only.

## Limits and notes

- kDrive allows 60 requests per minute: uploads run one file at a time.
- Files larger than 1 GB use a chunked upload session and need free space on the API host for the
  temporary file (`MEDIA_UPLOAD_TMP_DIR`).
- The verification of a large library takes time (one kDrive request per file); it can be stopped
  and resumed.
- The web build cannot read device files, so backups are available on Android and Linux only.
