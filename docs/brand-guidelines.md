# Brand Guidelines (Aevum Integration)

## Goal
Apply visual styling aligned with Aevum brand identity from:
- https://www.aevumhealthhub.com/

## Note
Exact hex values should be confirmed against finalized brand assets or design tokens. Until then, this file defines placeholders and usage roles.

## Token placeholders
- `AevumPrimary`
- `AevumPrimaryDark`
- `AevumSecondary`
- `AevumAccent`
- `AevumBackground`
- `AevumSurface`
- `AevumTextPrimary`
- `AevumTextSecondary`
- `AevumSuccess`
- `AevumWarning`
- `AevumError`

## UI usage
- Primary CTAs: `AevumPrimary`
- Interactive highlights/game boosts: `AevumAccent`
- Background gradients: `AevumBackground` -> `AevumSurface`
- Body text: `AevumTextPrimary`

## Game-specific usage
- Pipes should use brand-compatible contrast tones
- Prompt badges must remain readable under colorblind-safe checks
- Aevum crane palette should harmonize with primary/accent tokens

## Accessibility constraints
- Minimum contrast ratio WCAG AA for all critical text
- Avoid color-only signaling; include icons/text/haptics

## Next step
Extract exact brand palette from approved Aevum design source and replace placeholders in app theme constants.
