# Test the app on the web

Flutter's x64 Linux SDK cannot run on the aarch64 Debian machine, so the web app is built by
GitHub Actions and downloaded here. This is the recommended local test flow.

## Option A: local HTTP preview (recommended)

The app is served over plain HTTP on the VM IP, and the web build detects its own host, so it
automatically uses `http://<same-host>:8787` as the API. No manual URL typing, no tunnels, nothing
public.

```bash
# one-time (and after every web change merged to main): fetch the CI build
photo-atlas-app/scripts/fetch-web-build.sh

# combined with the API + database:
photo-atlas-api/scripts/dev-up.sh

# or only the web server:
photo-atlas-app/scripts/serve-web.sh            # foreground
photo-atlas-app/scripts/serve-web.sh --background
photo-atlas-app/scripts/serve-web.sh --stop
```

The scripts print the URL to open on the phone, for example:

```
http://10.30.127.225:8080/photo-atlas-app/
```

The web app then calls `http://10.30.127.225:8787` automatically because `Uri.base.host` is the
machine serving the app. If an old value is stored, tap **Settings → Detect** once.

The VM IP changes across restarts; always use the URL printed by the scripts
(`photo-atlas-api/scripts/dev-urls.sh` shows it too).

## Option B: Codespaces (live development)

The repository ships a `.devcontainer` using the Flutter image. Codespaces runs on x64 runners and
is free for public repositories within the monthly quota.

1. On GitHub: **Code → Codespaces → Create codespace on main**.
2. In the terminal:

   ```bash
   flutter pub get
   flutter run -d web-server --web-hostname 0.0.0.0 --web-port 8080
   ```

3. Open the forwarded port 8080 from the **Ports** panel on the phone browser.

The API still runs on your machine; set its address in Settings if it is reachable from the browser.

## Option C: another x64 machine

Follow [SETUP_DEBIAN.md](SETUP_DEBIAN.md) and [RUN.md](RUN.md); `flutter run -d chrome` or
`-d web-server` gives local hot reload.

## GitHub Pages

The Pages deployment at `https://giovannidrago.github.io/photo-atlas-app/` is kept up to date by CI.
Because it is served over HTTPS, it can only call an **HTTPS** API: a plain-HTTP LAN API is blocked
as mixed content. Use it for UI review, and use Option A for full local testing. Public tunnels are
never started automatically; see `AGENTS.md`.
