# Biological Age Model v1 (Push-up-only or Squat-only)

## Purpose
Generate a **wellness-oriented biological age estimate** from a single movement mode:
- Push-up game session
- Squat game session

## Important framing
- Not a diagnosis
- Not a substitute for clinician assessment
- Output includes confidence interval and caveats

## Feature groups
### A) Capacity
- Total valid reps
- Max reps in fixed interval
- Longest successful hold duration

### B) Tempo and neuromotor control
- Cadence variability (CV)
- Prompt response latency
- Ability to execute rapid doubles

### C) Quality & range
- Mean depth proxy (joint-angle based)
- Rep-to-rep ROM consistency
- Form break frequency

### D) Fatigue dynamics
- Late-session performance drop (slope)
- Increasing latency over time
- Decline in depth/quality trend

### E) Stability/confidence
- Pose confidence aggregate
- Occlusion-adjusted quality score

## Example model strategy (v1)
1. Normalize features by demographic bins (if demographics provided)
2. Compute latent performance score via weighted linear model
3. Map score to age-equivalent scale using calibration curve
4. Emit confidence band from signal quality + model uncertainty

## Output schema
- `mode`: pushup | squat
- `bio_age_estimate_years`: float
- `confidence_low`: float
- `confidence_high`: float
- `reliability`: low | medium | high
- `top_contributors`: array
- `recommendations`: array

## Validation plan
- Test-retest reliability cohort
- Inter-device consistency checks
- Criterion correlation against established functional fitness benchmarks

## Research integration notes
The model should be iteratively aligned with peer-reviewed evidence linking muscular endurance, lower-body function, tempo control, and age-related functional decline.
