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

Build output:
- `apps/mobile/build/web`

## Option A: Nginx on VPS
1. Build web assets.
2. Copy `apps/mobile/build/web/*` to your server web root.
3. Use `deploy/nginx.conf` (SPA fallback included).
4. Serve over HTTPS for camera access.

## Option B: Docker

From repo root:

```bash
docker build -f deploy/Dockerfile -t aevum-bioage-web .
docker run -p 8080:80 aevum-bioage-web
```

Then open `http://localhost:8080`.

## Option C: Vercel
- Use `deploy/vercel.json` settings
- Ensure project root can access `apps/mobile`

## Option D: Netlify
- Use `deploy/netlify.toml`
- Build command and publish folder already configured

## Camera constraints on web
Browser camera requires:
- HTTPS (or localhost)
- User-granted camera permission
- Compatible browser (Chrome/Edge/Safari latest preferred)

If camera fails, the app shows fallback instructions.
