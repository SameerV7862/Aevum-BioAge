class BioAgeInputFeatures {
  final String mode; // pushup | squat
  final int totalValidReps;
  final double cadenceCv;
  final double maxHoldSeconds;
  final double fatigueSlope;
  final double romConsistency;
  final double trackingQuality;

  const BioAgeInputFeatures({
    required this.mode,
    required this.totalValidReps,
    required this.cadenceCv,
    required this.maxHoldSeconds,
    required this.fatigueSlope,
    required this.romConsistency,
    required this.trackingQuality,
  });
}

class BioAgeResult {
  final double estimatedAge;
  final double confidenceLow;
  final double confidenceHigh;
  final String reliability;

  const BioAgeResult({
    required this.estimatedAge,
    required this.confidenceLow,
    required this.confidenceHigh,
    required this.reliability,
  });
}

class BioAgeEstimator {
  const BioAgeEstimator();

  BioAgeResult estimate(BioAgeInputFeatures f) {
    // Placeholder interpretable weighted scoring.
    final performanceScore =
        (f.totalValidReps * 0.6) +
        ((1 - f.cadenceCv).clamp(0, 1) * 15) +
        (f.maxHoldSeconds * 1.2) +
        (f.romConsistency * 20) +
        (f.trackingQuality * 10) -
        (f.fatigueSlope * 8);

    final estimatedAge = (75 - (performanceScore * 0.35)).clamp(18, 85).toDouble();

    final quality = f.trackingQuality;
    final band = quality > 0.8
        ? 4.0
        : quality > 0.6
            ? 6.0
            : 9.0;

    final reliability = quality > 0.8
        ? 'high'
        : quality > 0.6
            ? 'medium'
            : 'low';

    return BioAgeResult(
      estimatedAge: estimatedAge,
      confidenceLow: (estimatedAge - band).clamp(18, 90).toDouble(),
      confidenceHigh: (estimatedAge + band).clamp(18, 90).toDouble(),
      reliability: reliability,
    );
  }
}
