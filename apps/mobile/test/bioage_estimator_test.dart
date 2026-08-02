import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/scoring/bioage_estimator.dart';

void main() {
  const estimator = BioAgeEstimator();

  test('high score performance does not imply an extreme biological age reversal', () {
    final result = estimator.estimate(
      const BioAgeInputFeatures(
        mode: 'pushup',
        totalValidReps: 20,
        cadenceCv: 0.2,
        maxHoldSeconds: 1.0,
        fatigueSlope: 0.0,
        romConsistency: 0.8,
        trackingQuality: 0.9,
        sessionDuration: Duration(minutes: 2),
      ),
      const UserProfile(chronologicalAge: 45, sex: 'male'),
    );

    expect(result.estimatedBioAge, inInclusiveRange(39.0, 45.0));
    expect(result.ageDelta, greaterThanOrEqualTo(-8.0));
  });

  test('low score performance does not inflate biological age far beyond a single-test signal', () {
    final result = estimator.estimate(
      const BioAgeInputFeatures(
        mode: 'pushup',
        totalValidReps: 2,
        cadenceCv: 0.55,
        maxHoldSeconds: 0.0,
        fatigueSlope: 0.35,
        romConsistency: 0.45,
        trackingQuality: 0.75,
        sessionDuration: Duration(seconds: 70),
      ),
      const UserProfile(chronologicalAge: 35, sex: 'male'),
    );

    expect(result.estimatedBioAge, inInclusiveRange(37.0, 43.0));
    expect(result.ageDelta, lessThanOrEqualTo(8.0));
  });

  test('five pipes for a 35-year-old male is only a modest age increase', () {
    final result = estimator.estimate(
      const BioAgeInputFeatures(
        mode: 'pushup',
        totalValidReps: 5,
        cadenceCv: 0.5,
        maxHoldSeconds: 0.0,
        fatigueSlope: 0.0,
        romConsistency: 0.5,
        trackingQuality: 0.7,
        sessionDuration: Duration(minutes: 1),
      ),
      const UserProfile(chronologicalAge: 35, sex: 'male'),
    );

    expect(result.estimatedBioAge, inInclusiveRange(36.0, 38.0));
    expect(result.ageDelta, lessThanOrEqualTo(3.0));
  });

  test('six pipes for a 35-year-old male remains a modest increase', () {
    final result = estimator.estimate(
      const BioAgeInputFeatures(
        mode: 'pushup',
        totalValidReps: 6,
        cadenceCv: 0.5,
        maxHoldSeconds: 0.0,
        fatigueSlope: 0.0,
        romConsistency: 0.5,
        trackingQuality: 0.7,
        sessionDuration: Duration(minutes: 1),
      ),
      const UserProfile(chronologicalAge: 35, sex: 'male'),
    );

    expect(result.estimatedBioAge, inInclusiveRange(36.0, 39.0));
    expect(result.ageDelta, lessThanOrEqualTo(4.0));
  });

  test('seven pipes for a 35-year-old male is close to neutral on easier difficulty', () {
    final result = estimator.estimate(
      const BioAgeInputFeatures(
        mode: 'pushup',
        totalValidReps: 7,
        cadenceCv: 0.5,
        maxHoldSeconds: 0.0,
        fatigueSlope: 0.0,
        romConsistency: 0.5,
        trackingQuality: 0.7,
        sessionDuration: Duration(minutes: 1),
      ),
      const UserProfile(chronologicalAge: 35, sex: 'male'),
    );

    expect(result.estimatedBioAge, inInclusiveRange(35.0, 37.0));
    expect(result.ageDelta, lessThanOrEqualTo(2.0));
  });

  test('eight pipes for a 35-year-old male stays near chronological age', () {
    final result = estimator.estimate(
      const BioAgeInputFeatures(
        mode: 'pushup',
        totalValidReps: 8,
        cadenceCv: 0.5,
        maxHoldSeconds: 0.0,
        fatigueSlope: 0.0,
        romConsistency: 0.5,
        trackingQuality: 0.7,
        sessionDuration: Duration(minutes: 1),
      ),
      const UserProfile(chronologicalAge: 35, sex: 'male'),
    );

    expect(result.estimatedBioAge, inInclusiveRange(35.0, 36.0));
    expect(result.ageDelta, lessThanOrEqualTo(1.0));
  });

  test('same score in squat mode should not look better than push-up mode', () {
    const features = BioAgeInputFeatures(
      mode: 'pushup',
      totalValidReps: 12,
      cadenceCv: 0.28,
      maxHoldSeconds: 1.2,
      fatigueSlope: 0.05,
      romConsistency: 0.74,
      trackingQuality: 0.9,
      sessionDuration: Duration(minutes: 2),
    );
    const profile = UserProfile(chronologicalAge: 35, sex: 'male');

    final pushupResult = estimator.estimate(features, profile);
    final squatResult = estimator.estimate(
      const BioAgeInputFeatures(
        mode: 'squat',
        totalValidReps: 12,
        cadenceCv: 0.28,
        maxHoldSeconds: 1.2,
        fatigueSlope: 0.05,
        romConsistency: 0.74,
        trackingQuality: 0.9,
        sessionDuration: Duration(minutes: 2),
      ),
      profile,
    );

    expect(squatResult.estimatedBioAge, greaterThanOrEqualTo(pushupResult.estimatedBioAge));
  });

  test('high squat score still stays conservative for age reduction', () {
    final result = estimator.estimate(
      const BioAgeInputFeatures(
        mode: 'squat',
        totalValidReps: 20,
        cadenceCv: 0.2,
        maxHoldSeconds: 1.0,
        fatigueSlope: 0.0,
        romConsistency: 0.8,
        trackingQuality: 0.9,
        sessionDuration: Duration(minutes: 2),
      ),
      const UserProfile(chronologicalAge: 45, sex: 'male'),
    );

    expect(result.estimatedBioAge, inInclusiveRange(41.0, 46.0));
  });
}