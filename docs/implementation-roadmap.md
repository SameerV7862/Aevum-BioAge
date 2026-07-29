# Implementation Roadmap

## Phase 0 — Foundation (Week 1)
- Define architecture boundaries (Pose, Exercise, Game, Scoring)
- Set up coding standards and CI basics
- Add initial Aevum theme tokens

## Phase 1 — Camera + Pose (Weeks 1–2)
- Integrate iPhone camera pipeline
- Add on-device pose estimation
- Expose joint-angle and confidence streams

## Phase 2 — Movement Detection (Weeks 2–3)
- Push-up rep state machine
- Squat rep state machine
- Hold detection and tempo detection
- Unit tests with recorded sample sequences

## Phase 3 — Game Loop (Weeks 3–4)
- Side-scroll environment + pipes
- Aevum crane avatar animations
- Event-to-control mapping from movement engine
- Prompt engine for irregular rhythm tasks

## Phase 4 — Scoring & BioAge (Weeks 4–5)
- Feature extraction pipeline
- Initial weighted scoring model
- Calibration utilities and confidence estimation
- Results screen and contributor explanations

## Phase 5 — UX + Reliability (Weeks 5–6)
- Tracking quality gating and user feedback
- Accessibility cues (audio/haptic/text)
- Performance optimization on target iPhones

## Phase 6 — Validation & Pilot (Weeks 6–8)
- Internal pilot sessions
- Rep counting and latency benchmarks
- Reliability and repeatability analysis
- Iterate model weights and prompt difficulty

## Technical stack (proposed)
- Swift + SwiftUI
- AVFoundation for camera
- Vision / Core ML pose model
- SpriteKit (or custom render layer) for game scene

## Immediate tasks
1. Create iOS app scaffold
2. Implement push-up detector MVP
3. Implement squat detector MVP
4. Create Aevum crane placeholder sprite + movement mapping
5. Wire first end-to-end push-up session with temporary scoring
