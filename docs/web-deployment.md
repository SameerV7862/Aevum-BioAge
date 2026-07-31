# Web Deployment Guide

This guide makes Aevum BioAge runnable as a website on a server.

## Prerequisites
- Flutter SDK installed
- Chrome (for local web testing)

## Local run (web)

```bash
cd apps/mobile
flutter pub get
flutter run -d chrome
```

## Production web build

```bash
cd apps/mobile
flutter build web --release
```

For GitHub Pages on this repository, use:

```bash
cd apps/mobile
flutter build web --release --base-href /Aevum-BioAge/ --no-wasm-dry-run --pwa-strategy=none
```

Build output:
- `apps/mobile/build/web`

## Option A: GitHub Pages
1. Commit `.github/workflows/github-pages.yml`.
2. Push to `main`.
3. In the GitHub repository settings, open `Pages`.
4. Set `Source` to `GitHub Actions`.
5. Wait for the workflow to finish.

Expected URL:
- `https://sameerv7862.github.io/Aevum-BioAge/`

Notes:
- HTTPS is required for camera access and GitHub Pages provides it.
- This app already uses hash routes like `#/session`, so GitHub Pages SPA routing is acceptable.

## Option B: Nginx on VPS
1. Build web assets.
2. Copy `apps/mobile/build/web/*` to your server web root.
3. Use `deploy/nginx.conf` (SPA fallback included).
4. Serve over HTTPS for camera access.

## Option C: Docker

From repo root:

```bash
docker build -f deploy/Dockerfile -t aevum-bioage-web .
docker run -p 8080:80 aevum-bioage-web
```

Then open `http://localhost:8080`.

## Option D: Vercel

Recommended target:
- `https://bioage.aevumhealthhub.com/`

Repository setup in this repo:
- Root config: `vercel.json`
- App-root config: `apps/mobile/vercel.json`
- Reference config: `deploy/vercel.json`

Vercel project settings:
1. Import the GitHub repository.
2. Either:
	- keep the project root at the repository root, or
	- set the root directory to `apps/mobile`
3. Framework preset: `Other`.
4. Vercel will pick up the matching `vercel.json` automatically.
5. The build installs Flutter into `/tmp/flutter-sdk` and publishes the Flutter web output.

Custom domain setup:
1. Open the Vercel project.
2. Go to `Settings > Domains`.
3. Add `bioage.aevumhealthhub.com`.
4. Add the DNS record Vercel gives you for that subdomain.

Notes:
- This config builds with `--base-href /` because it is intended for a subdomain root.
- HTTPS is required for camera access and Vercel provides it.
- This app uses hash routes, so a single-page-app rewrite to `index.html` is sufficient.

## Option E: Netlify
- Use `deploy/netlify.toml`
- Build command and publish folder already configured

## Camera constraints on web
Browser camera requires:
- HTTPS (or localhost)
- User-granted camera permission
- Compatible browser (Chrome/Edge/Safari latest preferred)

If camera fails, the app shows fallback instructions.
