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

/// Evidence-based biological age estimator using push-up / squat performance.
///
/// ### Scientific basis
///
/// **Push-ups:**
/// Yang J, et al. "Association Between Push-up Exercise Capacity and Future
/// Cardiovascular Events Among Active Adult Men." JAMA Network Open, 2019.
/// doi:10.1001/jamanetworkopen.2018.8341
/// — Men completing >40 push-ups had 96% lower CVD risk vs <10 push-ups.
///
/// **Fitness age as biomarker:**
/// Frontiers in Physiology, 2023. "A novel estimate of biological aging by
/// multiple fitness assessments." doi:10.3389/fphys.2023.1164943
/// — Composite fitness score (incl. push-ups, squats) correlates with CVD
///   risk, diabetes risk, and epigenetic age clocks.
///
/// **Norm tables:**
/// ACSM Guidelines for Exercise Testing and Prescription, 11th ed.
/// Push-up percentile norms stratified by age decade and sex.
///
/// ### Method
/// 1. Look up the user's expected "average" rep count for their age/sex.
/// 2. Compare actual reps to the age-decade norm curve to find which age
///    decade the performance corresponds to ("fitness age").
/// 3. Blend fitness age with modifiers for cadence consistency, fatigue
///    resistance, and hold endurance.
/// 4. Report confidence band based on tracking quality and session length.
class BioAgeEstimator {
  const BioAgeEstimator();

  BioAgeResult estimate(BioAgeInputFeatures f, UserProfile profile) {
    final norms = profile.sex == 'female' ? _femaleNorms : _maleNorms;
    final reps = f.totalValidReps;

    // Step 1: Find which age-decade the rep count maps to
    final fitnessAge = _repCountToFitnessAge(reps, norms);

    // Step 2: Modifiers (each shifts bio-age estimate by up to ±3 years)
    // Cadence consistency: low CV = steady pacing = better fitness
    final cadenceBonus = ((0.5 - f.cadenceCv) * 6).clamp(-3.0, 3.0);
    // Fatigue resistance: negative slope (speeding up) is excellent
    final fatigueBonus = (-f.fatigueSlope * 4).clamp(-3.0, 3.0);
    // Hold endurance: sustained isometric holds indicate control
    final holdBonus = (f.maxHoldSeconds * 0.8).clamp(0.0, 3.0);

    final rawBioAge = fitnessAge - cadenceBonus - fatigueBonus - holdBonus;
    final bioAge = rawBioAge.clamp(18.0, 90.0);

    // Step 3: Confidence band based on data quality
    final quality = f.trackingQuality;
    final sessionMinutes = f.sessionDuration.inSeconds / 60.0;
    final dataQuality = (quality * 0.7 + (sessionMinutes / 3.0).clamp(0, 1) * 0.3);
    final band = dataQuality > 0.7 ? 3.0 : dataQuality > 0.4 ? 5.0 : 8.0;
    final reliability = dataQuality > 0.7 ? 'high' : dataQuality > 0.4 ? 'medium' : 'low';

    // Step 4: Percentile label relative to chronological age norms
    final expectedAvg = _averageRepsForAge(profile.chronologicalAge, norms);
    final percentileLabel = _percentileLabel(reps, expectedAvg);

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

  /// Interpolate rep count onto the age-norm curve to get "fitness age".
  double _repCountToFitnessAge(int reps, List<_AgeNorm> norms) {
    // If reps exceed the youngest norm, return youngest age
    if (reps >= norms.first.avgReps) return norms.first.age.toDouble();
    // If reps below the oldest norm, return oldest age
    if (reps <= norms.last.avgReps) return norms.last.age.toDouble();

    for (var i = 0; i < norms.length - 1; i++) {
      final young = norms[i];
      final old = norms[i + 1];
      if (reps <= young.avgReps && reps >= old.avgReps) {
        // Linear interpolation between age decades
        final t = (young.avgReps - reps) / (young.avgReps - old.avgReps);
        return young.age + t * (old.age - young.age);
      }
    }
    return norms.last.age.toDouble();
  }

  double _averageRepsForAge(int age, List<_AgeNorm> norms) {
    for (var i = 0; i < norms.length - 1; i++) {
      if (age <= norms[i].age) continue;
      if (age >= norms[i + 1].age) continue;
      final t = (age - norms[i].age) / (norms[i + 1].age - norms[i].age);
      return norms[i].avgReps + t * (norms[i + 1].avgReps - norms[i].avgReps);
    }
    if (age <= norms.first.age) return norms.first.avgReps.toDouble();
    return norms.last.avgReps.toDouble();
  }

  String _percentileLabel(int reps, double expectedAvg) {
    final ratio = expectedAvg > 0 ? reps / expectedAvg : 1.0;
    if (ratio >= 1.6) return 'Excellent';
    if (ratio >= 1.3) return 'Above Average';
    if (ratio >= 0.85) return 'Average';
    if (ratio >= 0.6) return 'Below Average';
    return 'Needs Improvement';
  }
}

class _AgeNorm {
  final int age;
  final int avgReps; // ACSM "average" category midpoint
  const _AgeNorm(this.age, this.avgReps);
}

/// ACSM push-up norms — male (average category midpoint per decade).
const _maleNorms = [
  _AgeNorm(25, 22),  // 20-29: avg 20-24
  _AgeNorm(35, 17),  // 30-39: avg 15-19
  _AgeNorm(45, 15),  // 40-49: avg 13-17
  _AgeNorm(55, 12),  // 50-59: avg 10-14
  _AgeNorm(65, 8),   // 60+:   avg 6-9
];

/// ACSM push-up norms — female (average category midpoint per decade).
const _femaleNorms = [
  _AgeNorm(25, 14),  // 20-29: avg 12-15
  _AgeNorm(35, 11),  // 30-39: avg 9-12
  _AgeNorm(45, 8),   // 40-49: avg 7-9
  _AgeNorm(55, 6),   // 50-59: avg 5-7
  _AgeNorm(65, 4),   // 60+:   avg 3-4
];
