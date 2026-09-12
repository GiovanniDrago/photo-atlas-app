# Map, globe and clusters

The main screen has two rendering modes that crossfade on zoom:

| Zoom | Mode | Widget |
|---|---|---|
| 0 - ~3 | 3D planet | `PlanetGlobe` (custom painter, orthographic projection) |
| 3+ | Detailed map | `flutter_map` + CARTO tiles |

## Planet globe

`lib/widgets/planet_globe.dart` draws the Earth with an orthographic projection:

- Land polygons come from `assets/geo/ne_110m_land.geojson` (Natural Earth 110m, public domain).
- Colors are derived from the active theme: ocean is `surfaceContainerHighest`, land is `primary`
  with low opacity, clusters are `primary` with an `onPrimary` border.
- Drag rotates (longitude wraps, latitude clamped to ±75°); pinch scales up. Reaching scale 2.5
  switches to the detailed map at zoom 4.5 centered on the globe center.
- Tapping a cluster selects it and opens the media list below.

Coordinates are rotated in spherical math (`sin/cos` orthographic projection), so the planet can be
spun freely; polygons crossing the horizon are clipped by skipping the hidden points.

## Detailed map

`flutter_map` renders raster tiles:

- Light theme: `https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png`
- Dark theme: `https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png`
- Attribution: OpenStreetMap contributors and CARTO, shown by `RichAttributionWidget`.

Both are free to use and require no API key. Zooming below 2.6 returns to the globe.

## Cluster semantics

Clusters are computed server side by `media_clusters(west, south, east, north, zoom)`:

- Cell size is `360 / 2^zoom` degrees. Zoom 0 puts the whole world in one cell, so all media with
  GPS merges into a single section.
- Each zoom level halves the cell. Two cities in the same country stay in one section while zoomed
  out and land in different cells when you zoom in, splitting into two sections.
- Section radius grows with `sqrt(item_count)`, so a city with 8 photos is visibly bigger than a
  city with 2.
- The globe queries zoom 1-3 depending on the pinch scale; the map queries the visible bounds with
  the current integer zoom.

At very high zoom, each cell contains a single location and the section becomes a point-like
marker.

## Selection

Selecting a section:

1. The map highlights it (globe ring or map circle).
2. Below the map, a 200 px pane appears with the title, the item count and a horizontal list of
   thumbnails for up to 200 media inside the section bounding box.
3. Closing the pane clears the selection.

## Tuning

| Constant | Where | Meaning |
|---|---|---|
| `2.5` / `2.6` | `map_screen.dart` | Globe to map and back thresholds |
| `450 ms` | `map_screen.dart` | Debounce before refetching clusters after a pan/zoom |
| `0.42 * scale` | `planet_globe.dart` | Globe radius relative to the smallest side |
| `sqrt(count/max)` | globe and map | Section radius scaling |
