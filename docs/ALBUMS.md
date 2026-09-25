# Albums

Albums live in the database as **relations**, never as kDrive or device folders: a photo can belong
to many albums and removing it from an album never deletes the file, the kDrive copy or the device
original. The **Albums** tab sits between Gallery and Settings: one card per album with the cover,
the name, the item count and a **Manual** / **Smart** badge.

## Manual albums

- Create one with **+ → Manual album**, or from a selection: in the Gallery, Timeline or the full
  screen viewer use **Add to album → New album** (the selected items are added right away).
- **Add items**: selection in the Gallery/Timeline/viewer → *Add to album* → pick the album.
  Device-only entries are indexed first (metadata + thumbnail, same as a folder scan) so they get a
  media id; they are **not** uploaded to kDrive by this action.
- **Remove items**: open the album, select the items and press *Remove from album* (the relation
  goes away, the files stay).
- **Cover**: select one or more items and press *Use as cover*. Without an explicit cover the most
  recent item of the album is used.
- **Rename** and **delete** from the card menu or the album detail menu. Deleting an album only
  removes the album and its relations.

## Smart albums

Smart albums are **resolved live** from a rule tree, so new matching media appear automatically.
The builder exposes:

| Rule | Column | Notes |
|---|---|---|
| Capture date | `taken_at` | from / to, `to` is inclusive |
| Upload date | `backed_up_at` | only items actually uploaded to kDrive match |
| Location + radius | `geog` | pick the center on the map, radius up to 200 km (`ST_DWithin`) |
| Type | `media_type` | all / photos / videos |

Rules are combined with AND and the builder shows a live **matching items** count
(`POST /api/albums/preview`). The server-side engine also supports source, device, backup status,
metadata status and name rules; they are not exposed in the builder yet (see
[API.md](../../photo-atlas-api/docs/API.md#albums) in the API repository).

## Album detail

- The detail is a **cloud-only** gallery: it loads only the album items (no full device library
  scan), with thumbnails and downloads through signed URLs. For items whose source is a device
  folder the app also resolves the local file (Android asset by id, local file on desktop), so
  upload and device actions work; if the photo permission is denied the usual banner links to the
  system settings.
- Selection actions (scrollable bar): **Upload**, **Share**, **Download original**, **Delete**,
  **Remove from album** (manual albums) and **Use as cover**.
- **Upload** retries pending or failed items (the device file is uploaded to kDrive again; the
  gallery badge updates at the end).
- **Delete** opens the dialog with up to three options:
  - *From the album*: removes only the relation (manual albums), files stay;
  - *From the device*: moves the device file to the system trash (Android 11+); if it was not
    uploaded the index row goes away too;
  - *From the cloud*: moves the kDrive copy to the trash and drops the index row, so the item
    leaves the album as well.
- When the album has items whose upload **failed**, the header shows a red row
  "N failed uploads · Retry" that re-uploads all of them in one run (with the same progress bar).
- Pull to refresh reloads the album, the failed count and the list counters.

## How it works

- `GET /api/albums` returns each album with `item_count` and the resolved cover (explicit cover or
  the newest matching item).
- Manual membership is stored in `album_items` (`album_id`, `media_id`, `added_at`); smart albums
  store their rules in `albums.rules` and are compiled to parameterized SQL at query time.
- `GET /api/albums/:id/media` returns the items with the same `{items, total, limit, offset}` shape
  as `/api/media`, ordered by capture date.
- Deleting media cascades the relations (`album_items`) and clears an explicit cover, but never the
  other way round.
