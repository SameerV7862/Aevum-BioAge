# Aevum BioAge

Cross-platform **biological age estimate** experience using movement performance from:
- Push-up game mode
- Squat game mode

Built for **Aevum** with an arcade layer inspired by Flappy mechanics, where the player controls an **Aevum crane** through exercise-driven rhythm challenges.

## Why cross-platform
Primary audience includes Android-first users. This implementation uses a shared Flutter codebase so iOS and Android both work from day one.

## Tech stack (v1 scaffold)
- Flutter + Dart
- Flame (2D game loop and scene)
- Camera plugin
- Pose abstraction ready for MediaPipe integration

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
    pubspec.yaml
docs/
research/
```

## Run the mobile app

1. Install Flutter SDK
2. From `apps/mobile`:
   - `flutter pub get`
   - `flutter run`

## Current scaffold status
- App shell and navigation
- Camera preview screen scaffold
- Pose engine interface + placeholder implementation
- Push-up and squat detector state machine skeletons
- Rhythm prompt engine (irregular cadence prompts)
- Flame game scene with Aevum crane placeholder component
- Bio-age scoring engine skeleton
- Aevum theme token placeholders

## Next integration tasks
1. Wire real-time camera frames to pose engine
2. Integrate MediaPipe pose model and landmarks
3. Finalize rep detection thresholds with test clips
4. Connect exercise events into Flame game controls
5. Calibrate bio-age mapping with evidence-backed coefficients
