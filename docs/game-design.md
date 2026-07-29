# Game Design — Aevum Crane Rhythm Runner (Flappy-style)

## Concept
A side-scrolling game where the player controls an **Aevum crane**. Instead of tapping, the crane’s vertical boosts/steady states are driven by exercise events from push-ups or squats.

## Control mapping
### Push-up mode
- **Standard rep completed** → normal flap impulse
- **Hold-bottom for prompt duration** → sustained altitude/slow descent
- **Two quick reps in succession** → burst boost
- **Slow eccentric under cadence target** → precision bonus window

### Squat mode
- **Full-depth squat completed** → normal flap impulse
- **Isometric hold at target depth** → glide stabilization
- **Rapid double squat** → burst boost
- **Controlled tempo squat** → precision bonus window

## Irregular rhythm prompts
Prompts are generated from a pattern engine:
- `HOLD_2S`
- `HOLD_3S`
- `DOUBLE_FAST`
- `SLOW_REP`
- `NORMAL_REP`

Rules:
- No more than 2 high-intensity prompts in a row
- Adaptive difficulty based on fatigue indicators
- Missed prompt does not hard-fail immediately; increases pipe pressure

## Obstacles & scoring
- Pipes represent timing gates and form consistency checks
- Score dimensions:
  - Survival time
  - Prompt accuracy
  - Form quality multiplier
  - Consistency streak

## Failure states
- Repeated prompt misses
- Form quality below threshold for sustained period
- Tracking confidence too low (session paused and guidance shown)

## Accessibility
- Prompt text + audio cue + haptic pattern
- Color-safe prompt indicators
- Adjustable session length and pace

## Avatar requirement
The flappy character must be an **Aevum crane** (not generic bird). Asset pipeline should support:
- Neutral flap animation
- Boost animation
- Hold/glide animation
