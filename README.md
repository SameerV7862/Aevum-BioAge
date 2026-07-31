# Aevum BioAge

Cross-platform **biological age estimate** experience using movement performance from:
- Push-up game mode
- Squat game mode

Built for **Aevum** with an arcade layer inspired by Flappy mechanics, where the player controls an **Aevum crane** through exercise-driven rhythm challenges.

## Why cross-platform
Primary audience includes Android-first users. This implementation uses a shared Flutter codebase so iOS, Android, and Web can work from one codebase.

## Tech stack (v1 scaffold)
- Flutter + Dart
- Flame (2D game loop and scene)
- Camera plugin
- Pose abstraction ready for MediaPipe integration
- Web static build deployable on any server/CDN

## Repository layout

```text
apps/
  mobile/
    lib/
      app/
      theme/
      camera/
      pose/
      exercise/
      game/
      scoring/
      features/session/
      features/web/
    web/
    pubspec.yaml
deploy/
  nginx.conf
  Dockerfile
  vercel.json
  netlify.toml
docs/
research/
```

## Local development

From `apps/mobile`:

```bash
flutter pub get
flutter run -d chrome
```

For mobile:

```bash
flutter run
```

## Build for web

```bash
cd apps/mobile
flutter build web --release
```

Output is generated at:
`apps/mobile/build/web`

## Server deploy options
- **GitHub Pages** via `.github/workflows/github-pages.yml`
- **Nginx static host** using `deploy/nginx.conf`
- **Docker** image using `deploy/Dockerfile`
- **Vercel** using `deploy/vercel.json`
- **Netlify** using `deploy/netlify.toml`

See `docs/web-deployment.md` for exact steps.

## GitHub Pages

This repo can deploy the Flutter web build automatically to GitHub Pages.

1. Push to `main`.
2. In GitHub, enable Pages and set the source to `GitHub Actions`.
3. The workflow builds `apps/mobile` with base path `/Aevum-BioAge/` and publishes the site.

Expected URL:
`https://sameerv7862.github.io/Aevum-BioAge/`

## Vercel

Recommended production target for the main website ecosystem:
`https://bioage.aevumhealthhub.com/`

This repo includes a root `vercel.json` that:
1. installs Flutter during the Vercel build
2. builds the app from `apps/mobile`
3. publishes the static output from `apps/mobile/build/web`

For exact setup, see [docs/web-deployment.md](/Users/varkasam/Aevum-BioAge/docs/web-deployment.md).

## Current scaffold status
- App shell and navigation
- Web-first landing page + start assessment flow
- Camera preview screen scaffold (mobile/web compatible fallback)
- Pose engine interface + placeholder implementation
- Push-up and squat detector state machine skeletons
- Rhythm prompt engine (irregular cadence prompts)
- Flame game scene with Aevum crane placeholder component
- Bio-age scoring engine skeleton
- Aevum theme token placeholders

## Next integration tasks
1. Wire real-time camera frames to pose engine
2. Integrate MediaPipe pose model and landmarks (web + mobile)
3. Finalize rep detection thresholds with test clips
4. Connect exercise events into Flame game controls
5. Calibrate bio-age mapping with evidence-backed coefficients
