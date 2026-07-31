import 'dart:math' as math;

/// User profile collected before a session begins.
class UserProfile {
  final int chronologicalAge;
  final String sex; // 'male' | 'female'

  const UserProfile({required this.chronologicalAge, required this.sex});
}

/// Raw metrics collected during a game session.
class BioAgeInputFeatures {
  final String mode; // pushup | squat
  final int totalValidReps;
  final double cadenceCv; // coefficient of variation of rep timing
  final double maxHoldSeconds;
  final double fatigueSlope; // positive = slowing down
  final double romConsistency; // 0–1
  final double trackingQuality; // 0–1
  final Duration sessionDuration;

  const BioAgeInputFeatures({
    required this.mode,
    required this.totalValidReps,
    required this.cadenceCv,
    required this.maxHoldSeconds,
    required this.fatigueSlope,
    required this.romConsistency,
    required this.trackingQuality,
    required this.sessionDuration,
  });
}

class BioAgeResult {
  final double estimatedBioAge;
  final double confidenceLow;
  final double confidenceHigh;
  final String reliability; // high | medium | low
  final String percentileLabel; // e.g. "Above Average"
  final int chronologicalAge;
  final double ageDelta; // negative = younger than chronological

  const BioAgeResult({
    required this.estimatedBioAge,
    required this.confidenceLow,
    required this.confidenceHigh,
    required this.reliability,
    required this.percentileLabel,
    required this.chronologicalAge,
    required this.ageDelta,
  });
}

/// Evidence-based biological age estimator using game performance.
///
/// ### Scientific basis
///
/// **Fitness age as biomarker:**
/// Frontiers in Physiology, 2023. "A novel estimate of biological aging by
/// multiple fitness assessments." doi:10.3389/fphys.2023.1164943
/// — Composite fitness score correlates with CVD
///   risk, diabetes risk, and epigenetic age clocks.
///
/// **Game adaptation:**
/// Pipes-cleared score and consistency are mapped to age-banded movement
/// capacity norms tuned for current spacing/difficulty settings.
///
/// ### Method
/// 1. Look up the user's expected "average" pipe-clear score for age/sex.
/// 2. Compare actual score to the age-decade norm curve to find which age
///    decade the performance corresponds to ("fitness age").
/// 3. Blend fitness age with modifiers for cadence consistency, fatigue
///    resistance, and hold endurance.
/// 4. Report confidence band based on tracking quality and session length.
class BioAgeEstimator {
  const BioAgeEstimator();

  BioAgeResult estimate(BioAgeInputFeatures f, UserProfile profile) {
    final norms = profile.sex == 'female' ? _femaleScoreNorms : _maleScoreNorms;
    final clearedPipes = f.totalValidReps;

  // A single repetition test should not be treated as a direct age clock.
  // Yang et al. (JAMA Netw Open, 2019) reported push-up capacity as a risk
  // discriminator in broad categories, while Manca et al. (Front Physiol,
  // 2023) built fitness-age from multiple functional tests. We therefore
  // shrink the rep-matched age strongly back toward chronological age and let
  // session-quality modifiers contribute only modestly.
    final scoreMatchedAge = _scoreToFitnessAge(clearedPipes, norms);
    final rawScoreAgeShift = (scoreMatchedAge - profile.chronologicalAge) * 0.18;

    // Difficulty guardrail:
    // - Mid-range runs (like 6 clears at current tuning) should be near-neutral.
    // - Very low scores still add some age penalty.
    // - High scores can still reduce estimated age.
    final scoreAgeShift = rawScoreAgeShift < 0
      ? rawScoreAgeShift.clamp(-5.0, 0.0)
      : _lowScorePenalty(clearedPipes, rawScoreAgeShift);
  final cadenceAdjustment = ((0.35 - f.cadenceCv) * 2.0).clamp(-1.0, 1.0);
  final fatigueAdjustment = (-f.fatigueSlope * 1.5).clamp(-1.0, 1.0);
  final holdAdjustment = (f.maxHoldSeconds / 3.0).clamp(0.0, 1.0) * 0.75;
  final consistencyAdjustment =
    ((f.romConsistency - 0.6) * 1.5).clamp(-0.75, 0.75);
    final trackingPenalty =
      ((0.55 - f.trackingQuality) * 1.8).clamp(0.0, 1.2);

  final rawBioAge = profile.chronologicalAge +
    scoreAgeShift -
    cadenceAdjustment -
    fatigueAdjustment -
    holdAdjustment -
    consistencyAdjustment +
    trackingPenalty;
  final bioAge = rawBioAge
    .clamp(profile.chronologicalAge - 8.0, profile.chronologicalAge + 8.0)
    .clamp(18.0, 90.0)
    .toDouble();

    // Step 3: Confidence band based on data quality
    final quality = f.trackingQuality;
    final sessionMinutes = f.sessionDuration.inSeconds / 60.0;
    final dataQuality = (quality * 0.7 + (sessionMinutes / 3.0).clamp(0, 1) * 0.3);
    final band = dataQuality > 0.7 ? 4.0 : dataQuality > 0.4 ? 6.0 : 8.0;
    final reliability = dataQuality > 0.7 ? 'high' : dataQuality > 0.4 ? 'medium' : 'low';

    // Step 4: Percentile label relative to chronological age norms
    final expectedAvg = _averageScoreForAge(profile.chronologicalAge, norms);
    final percentileLabel = _percentileLabel(clearedPipes, expectedAvg);

    return BioAgeResult(
      estimatedBioAge: bioAge.roundToDouble(),
      confidenceLow: (bioAge - band).clamp(18, 90).roundToDouble(),
      confidenceHigh: (bioAge + band).clamp(18, 90).roundToDouble(),
      reliability: reliability,
      percentileLabel: percentileLabel,
      chronologicalAge: profile.chronologicalAge,
      ageDelta: (bioAge - profile.chronologicalAge).roundToDouble(),
    );
  }

  /// Interpolate score onto the age-norm curve to get "fitness age".
  double _scoreToFitnessAge(int score, List<_AgeNorm> norms) {
    // If score exceeds the youngest norm, return youngest age.
    if (score >= norms.first.avgScore) return norms.first.age.toDouble();
    // If score is below the oldest norm, return oldest age.
    if (score <= norms.last.avgScore) return norms.last.age.toDouble();

    for (var i = 0; i < norms.length - 1; i++) {
      final young = norms[i];
      final old = norms[i + 1];
      if (score <= young.avgScore && score >= old.avgScore) {
        // Linear interpolation between age decades
        final t = (young.avgScore - score) / (young.avgScore - old.avgScore);
        return young.age + t * (old.age - young.age);
      }
    }
    return norms.last.age.toDouble();
  }

  double _averageScoreForAge(int age, List<_AgeNorm> norms) {
    for (var i = 0; i < norms.length - 1; i++) {
      if (age <= norms[i].age) continue;
      if (age >= norms[i + 1].age) continue;
      final t = (age - norms[i].age) / (norms[i + 1].age - norms[i].age);
      return norms[i].avgScore + t * (norms[i + 1].avgScore - norms[i].avgScore);
    }
    if (age <= norms.first.age) return norms.first.avgScore.toDouble();
    return norms.last.avgScore.toDouble();
  }

  String _percentileLabel(int score, double expectedAvg) {
    final ratio = expectedAvg > 0 ? score / expectedAvg : 1.0;
    if (ratio >= 1.5) return 'Excellent';
    if (ratio >= 1.25) return 'Above Average';
    if (ratio >= 0.85) return 'Average';
    if (ratio >= 0.6) return 'Below Average';
    return 'Needs Improvement';
  }
}

double _lowScorePenalty(int score, double rawShift) {
  if (score >= 8) return 0.0;
  final severity = ((8 - score) / 4.0).clamp(0.0, 1.0);
  return (rawShift * severity).clamp(0.0, 2.0);
}

class _AgeNorm {
  final int age;
  final int avgScore;
  const _AgeNorm(this.age, this.avgScore);
}

/// Score norms tuned for current game spacing/assist settings.
const _maleScoreNorms = [
  _AgeNorm(25, 17),
  _AgeNorm(35, 14),
  _AgeNorm(45, 11),
  _AgeNorm(55, 9),
  _AgeNorm(65, 7),
];

const _femaleScoreNorms = [
  _AgeNorm(25, 15),
  _AgeNorm(35, 12),
  _AgeNorm(45, 10),
  _AgeNorm(55, 8),
  _AgeNorm(65, 6),
];
