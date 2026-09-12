# Photo Atlas

Free and open source Flutter app that aggregates and organizes your **images and videos by time and
space** using their metadata. Runs on **Android**, **Linux desktop** and the **web**.

## Features

- **Planet map**: an orthographic 3D globe when you are zoomed out and a detailed map when you zoom
  in. Every group of media becomes a highlighted section sized by the number of items. Sections
  merge when you zoom out and split when you zoom in. Tap a section to list its photos below the map.
- **Timeline**: vertical distribution by date. The last 2 months are grouped by day, the previous
  3 months by week, everything older by month.
- **Gallery**: every indexed item, including photos and videos with **no metadata** or partial
  metadata.
- **Local folder scan**: index name, size, date, dimensions and GPS of every image or video in a
  folder (Android and Linux; the web cannot read local folders).
- **kDrive**: connect an Infomaniak kDrive, scan a folder recursively and enrich capture dates and
  GPS from EXIF. Only metadata is indexed; images stay in your cloud.
- **Themes**: minimal light and dark palettes that also drive the map colors. English and Italian.

## Architecture

```
lib/
  main.dart / app.dart       Riverpod root, MaterialApp, theme and locale
  theme/                     Theme catalog (light/dark seeds)
  l10n/                      English and Italian ARB files
  models/                    MediaItem, MediaCluster, TimelineBucket, sources
  providers/                 API client, clusters, timeline, gallery, settings
  services/                  HTTP client, EXIF parsing, folder scanning, geo data
  screens/                   shell + map, timeline, gallery, settings
  widgets/                   PlanetGlobe (custom painter), media thumbnails
assets/geo/                  Natural Earth 110m land polygons (public domain)
```

The app talks to [photo-atlas-api](https://github.com/GiovanniDrago/photo-atlas-api) over HTTP and
never handles cloud credentials directly: kDrive tokens live server-side.

## Quick start

A normal x64 Linux machine is required to build the app locally (Flutter does not ship an arm64
Linux SDK). On an aarch64 device use GitHub Actions or Codespaces instead: see
[docs/WEB_TESTING.md](docs/WEB_TESTING.md).

```bash
flutter pub get
flutter run -d linux      # or: -d chrome, or a connected Android device
```

Set the API URL in **Settings → API server** (default `http://localhost:8787`).

## Documentation

| Document | Content |
|---|---|
| [docs/SETUP_DEBIAN.md](docs/SETUP_DEBIAN.md) | Install Flutter, Android SDK and Linux desktop dependencies |
| [docs/RUN.md](docs/RUN.md) | Run on Android, Linux and web |
| [docs/WEB_TESTING.md](docs/WEB_TESTING.md) | Test on web with GitHub Pages or Codespaces |
| [docs/MAP_AND_GLOBE.md](docs/MAP_AND_GLOBE.md) | Globe, map and cluster behavior |
| [docs/SCANNING.md](docs/SCANNING.md) | How folder scanning and EXIF extraction work |
| [docs/KDRIVE.md](docs/KDRIVE.md) | Connecting and scanning kDrive |
| [docs/DEPLOY.md](docs/DEPLOY.md) | GitHub Actions workflows and secrets |
| [docs/FDROID.md](docs/FDROID.md) | F-Droid metadata and release checklist |

## Platform status

| Platform | Status |
|---|---|
| Web | built and deployed by GitHub Actions to GitHub Pages |
| Android | APKs and AAB built by GitHub Actions on tags; F-Droid metadata prepared |
| Linux desktop | bundles built by GitHub Actions for x86_64 and arm64 |

## License

GPL-3.0-only. See [LICENSE](LICENSE). Natural Earth data is public domain; map tiles are provided by
CARTO with OpenStreetMap data (attribution shown in the map).
