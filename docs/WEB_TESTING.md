# Test the app on the web

Flutter's x64 Linux SDK cannot run on the aarch64 Debian-on-phone environment, so the app is built
and tested through GitHub instead of locally.

## Option A: GitHub Pages (easiest)

A workflow deploys the web build on every push to `main`.

1. Enable Pages once in the repository: **Settings → Pages → Source: GitHub Actions**
   (or let the first workflow run do it when Pages is configured with the workflow builder).
2. Push to `main` or run the `Web preview deploy` workflow manually.
3. Open `https://giovannidrago.github.io/photo-atlas-app/` from any browser, including the phone.

The API URL defaults to `http://localhost:8787`. If the API runs on the same device you are
browsing from, localhost usually works; otherwise open **Settings → API server** and set the LAN
address of the machine running the API (`http://192.168.1.x:8787`). The API already allows CORS from
any origin by default.

## Option B: Codespaces (live development)

The repository ships a `.devcontainer` using the Flutter image. Codespaces runs on x64 runners and
is free for public repositories within the monthly quota.

1. On GitHub: **Code → Codespaces → Create codespace on main**.
2. In the terminal:

   ```bash
   flutter pub get
   flutter run -d web-server --web-hostname 0.0.0.0 --web-port 8080
   ```

3. Open the forwarded port 8080 from the **Ports** panel (or the popup) on the phone browser.
   Hot reload (`r`) and hot restart (`R`) work as usual.

The API still runs on your machine: make it reachable from the browser context (same network or a
tunnel). The Codespace itself cannot reach your home network unless you expose it, but the browser
that opens the app can.

## Option C: another x64 machine

Follow [SETUP_DEBIAN.md](SETUP_DEBIAN.md) and [RUN.md](RUN.md); `flutter run -d chrome` or
`-d web-server` gives the same result with local hot reload.
