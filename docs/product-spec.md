# Product Spec — Aevum BioAge (v1)

## 1) Problem
Most people cannot easily translate daily functional performance into a meaningful longevity signal. We want an engaging camera-based experience that converts push-up or squat performance into an interpretable biological age estimate.

## 2) Target users
- Adults interested in fitness and healthy aging
- Users who prefer gamified, short assessments
- Users with only a smartphone (no wearables required)

## 3) Product experience
### Session flow
1. Consent + disclaimer
2. Calibration (camera framing, body visibility)
3. Select mode:
   - Push-up challenge
   - Squat challenge
4. Play Aevum crane arcade challenge with irregular cadence prompts
5. View results:
   - Score summary
   - Biological age estimate
   - Confidence band
   - Improvement hints

## 4) Inputs
- iPhone camera video stream
- Optional: age/sex/height/weight (user-entered, optional in v1)

## 5) Outputs
- Rep count and quality metrics
- Session-level performance features
- Biological age estimate based on push-up-only or squat-only mode

## 6) Functional requirements
- Real-time pose tracking at playable frame rate
- Robust rep detection for push-ups and squats
- Irregular rhythm challenge generation
- Flappy-style obstacle loop with Aevum crane avatar
- Session recording of feature vectors
- Age estimate + confidence output in under 2 seconds post-session

## 7) Non-functional requirements
- On-device processing preference
- Graceful degradation on lower-end iPhones
- Clear accessibility text and cues
- Privacy-by-design (no raw video upload by default)

## 8) Success criteria (v1)
- >95% correct rep counting in controlled internal tests
- <100 ms average gameplay control latency from movement event to game response
- Stable age estimate reproducibility (within tolerance on repeat trials)

## 9) Risks
- Pose occlusion and poor lighting degrade reliability
- Fatigue/form variability may confound age mapping
- Over-interpretation risk without proper framing

## 10) Mitigations
- Quality gating + confidence suppression when tracking poor
- Conservative model claims with plain-language explanations
- Iterative calibration and validation protocol
