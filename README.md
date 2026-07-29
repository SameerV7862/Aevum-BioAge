# Aevum BioAge

Camera-based **biological age estimate** experience using movement performance from:
- Push-up game mode
- Squat game mode

Built for **Aevum** with an arcade layer inspired by Flappy mechanics, where the player controls an **Aevum crane** through exercise-driven rhythm challenges.

## Vision
A user performs push-ups or squats in front of an iPhone camera. Real-time pose tracking powers:
1. Rep/form detection
2. Irregular rhythm challenges (holds, quick doubles, tempo shifts)
3. Arcade survival/progression using an Aevum crane avatar
4. A movement-derived biological age estimate (wellness metric)

## Core principles
- **On-device first** pose and scoring where possible
- **Interpretable** model outputs (feature-based, not black-box-only)
- **Wellness estimate, not diagnosis**
- **Fast iteration** with modular game + scoring architecture

## Repository layout

```text
ios/
  AevumBioAge/
docs/
  product-spec.md
  game-design.md
  bioage-model-v1.md
  implementation-roadmap.md
  brand-guidelines.md
research/
  literature-notes.md
  feature-to-bioage-mapping.md
```

## Initial scope (v1)
- iPhone camera feed + pose estimation
- Push-up and squat detectors (rep count + quality signals)
- Aevum crane Flappy-style overlay with movement-triggered control events
- Feature extraction from exercise/gameplay
- Biological age estimate from push-up-only or squat-only session data
- Results screen with confidence band + plain-language explanation

## Non-goals (v1)
- Medical diagnosis or treatment recommendations
- Multi-sensor wearable fusion
- Cloud-dependent mandatory inference

## Compliance & disclaimers
This product provides a **fitness/wellness estimate** and is **not a medical device** in v1 unless regulatory strategy changes.

See `docs/bioage-model-v1.md` and `docs/product-spec.md` for details.
