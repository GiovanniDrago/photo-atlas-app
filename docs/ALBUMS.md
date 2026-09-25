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
  scan), with thumbnails and downloads through signed URLs.
- Selection actions: **Share**, **Download original**, **Remove from album** (manual albums) and
  **Use as cover**.
- Pull to refresh reloads the album and the list counters.

## How it works

- `GET /api/albums` returns each album with `item_count` and the resolved cover (explicit cover or
  the newest matching item).
- Manual membership is stored in `album_items` (`album_id`, `media_id`, `added_at`); smart albums
  store their rules in `albums.rules` and are compiled to parameterized SQL at query time.
- `GET /api/albums/:id/media` returns the items with the same `{items, total, limit, offset}` shape
  as `/api/media`, ordered by capture date.
- Deleting media cascades the relations (`album_items`) and clears an explicit cover, but never the
  other way round.
