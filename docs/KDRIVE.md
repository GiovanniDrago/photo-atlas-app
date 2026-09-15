# kDrive from the app

The app never stores or sees your Infomaniak token: it sends it once to the API, which encrypts it
and uses it for every kDrive call. See the API documentation for endpoint details:
[photo-atlas-api/docs/KDRIVE.md](https://github.com/GiovanniDrago/photo-atlas-api/blob/main/docs/KDRIVE.md).

## Connect

1. Create a token with the **drive** scope at
   <https://manager.infomaniak.com/v3/ng/accounts/token/list> (the ⓘ button next to the kDrive
   section title in Settings repeats these steps with direct links).
2. Find your drive id in the kDrive web app URL:
   `https://ksuite.infomaniak.com/all/kdrive/app/drive/<DRIVE_ID>`.
3. In **Settings → kDrive**, paste the token and the drive id and tap **Connect**.
4. The token field is cleared afterwards on purpose, but the token is **saved encrypted** on the
   server: the status chip shows the connected drive and you do not need to paste it again. Use
   **Replace token** if you ever want to change it.
5. If the status check cannot reach the API (for example while the server restarts), the section
   shows "Could not check the connection" with a **Retry** button instead of pretending the token
   is missing.

## Scan folders one by one

1. Tap **Add folder**: a picker opens showing the drive root and its subfolders (breadcrumb chips
   navigate back).
2. Choose the folder to index and set **Include subfolders**:
   - ON (default): the whole subtree below the chosen folder is indexed
   - OFF: only the files directly inside it
3. Tap **Select this folder**: a new kDrive source is created and scanned in the background. The
   message line shows `files seen / indexed` and updates every 2 seconds.
4. The folder appears under **Folders in kDrive** with its indexed item count, the subfolder mode
   and the last scan time. From its menu you can:
   - **Scan again** (uses the stored subfolder mode)
   - toggle **Include subfolders** (persisted per folder)
   - **Delete**: removes the local index only; files in kDrive are never touched
5. Selecting the drive **root** is allowed but shows a warning: it indexes the entire drive.

An **Advanced** section still allows scanning a numeric folder id manually.

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

- One kDrive account per user in this version.
- Videos are indexed but not enriched (no video metadata parsing yet).
- The folder picker lists directories only; file-level selection is not supported.
