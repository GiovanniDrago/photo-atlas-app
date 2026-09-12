# kDrive from the app

The app never stores or sees your Infomaniak token: it sends it once to the API, which encrypts it
and uses it for every kDrive call. See the API documentation for endpoint details:
[photo-atlas-api/docs/KDRIVE.md](https://github.com/GiovanniDrago/photo-atlas-api/blob/main/docs/KDRIVE.md).

## Connect

1. Create a token with the **drive** scope at
   <https://manager.infomaniak.com/v3/ng/accounts/token/list>.
2. Find your drive id in the kDrive web app URL:
   `https://ksuite.infomaniak.com/all/kdrive/app/drive/<DRIVE_ID>`.
3. In **Settings → kDrive**, paste the token and the drive id and tap **Connect**.
4. The status chip shows `Connected to drive <id>` when the API validates the token.

## Scan a folder

1. Enter the folder id to scan (`1` is the root) in **Folder ID**.
2. Tap **Scan kDrive folder**. The API walks the folder recursively at 60 requests/minute and
   indexes file names, sizes, MIME types and kDrive timestamps.
3. The message line shows progress (`files seen / indexed`) while the settings screen polls the scan
   run; it switches to "Scan complete" at the end.
4. New items are visible immediately in the gallery; without GPS they only appear on the map after
   enrichment.

## Enrich dates and GPS

kDrive listings do not include capture date or GPS. Tap **Enrich metadata**:

- The API downloads only the first ~256 KB of each pending image and parses EXIF with `exifr`.
- `taken_at`, `lat`, `lon`, `width`, `height` and `metadata_status` are updated in batches.
- The progress line shows processed and updated counts; up to 200 items per request (the app asks
  for 50 at a time).

Run enrichment again until it reports zero updated items; large libraries can be enriched in
multiple passes.

## What is stored where

| Data | Location |
|---|---|
| Token | encrypted in `kdrive_accounts` on the API database |
| File listing metadata | `media_items` rows |
| Images and videos | remain in your kDrive |
| Thumbnails | fetched on demand through the API proxy |

## Limitations

- One kDrive account per API instance in this version.
- Videos are indexed but not enriched (no video metadata parsing yet).
- Only the folder id is entered manually; a folder browser is planned.
