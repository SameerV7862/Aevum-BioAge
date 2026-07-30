import 'dart:math' as math;

import '../exercise/exercise_types.dart';
import 'bioage_estimator.dart';

/// Collects gameplay and tracking metrics during a session for bio-age estimation.
class SessionStats {
  final String mode;
  int pipesCleared = 0;
  final List<Duration> _scoreIntervals = [];
  DateTime? _lastScoreTime;
  DateTime? _sessionStart;
  double maxHoldSeconds = 0;
  double _trackingConfidenceSum = 0;
  int _trackingFrames = 0;

  SessionStats({required this.mode});

  void onEvent(ExerciseEvent event) {
    _sessionStart ??= event.timestamp;

    if (event is HoldCompletedEvent) {
      final secs = event.holdDuration.inMilliseconds / 1000.0;
      if (secs > maxHoldSeconds) maxHoldSeconds = secs;
    }
  }

  void onPipeCleared(DateTime timestamp) {
    _sessionStart ??= timestamp;
    pipesCleared++;
    if (_lastScoreTime != null) {
      _scoreIntervals.add(timestamp.difference(_lastScoreTime!));
    }
    _lastScoreTime = timestamp;
  }

  void onPoseFrame(double confidence) {
    _trackingConfidenceSum += confidence;
    _trackingFrames++;
  }

  double get cadenceCv {
    if (_scoreIntervals.length < 2) return 0.5;
    final ms = _scoreIntervals.map((d) => d.inMilliseconds.toDouble()).toList();
    final mean = ms.reduce((a, b) => a + b) / ms.length;
    if (mean == 0) return 1.0;
    final variance = ms.map((v) => (v - mean) * (v - mean)).reduce((a, b) => a + b) / ms.length;
    return (math.sqrt(variance) / mean).clamp(0.0, 1.0);
  }

  double get fatigueSlope {
    if (_scoreIntervals.length < 4) return 0.0;
    final half = _scoreIntervals.length ~/ 2;
    final firstHalf = _scoreIntervals.sublist(0, half).map((d) => d.inMilliseconds.toDouble());
    final secondHalf = _scoreIntervals.sublist(half).map((d) => d.inMilliseconds.toDouble());
    final avgFirst = firstHalf.reduce((a, b) => a + b) / firstHalf.length;
    final avgSecond = secondHalf.reduce((a, b) => a + b) / secondHalf.length;
    if (avgFirst == 0) return 0;
    return ((avgSecond - avgFirst) / avgFirst).clamp(-1.0, 1.0);
  }

  double get romConsistency => (1.0 - cadenceCv).clamp(0.0, 1.0);

  double get trackingQuality =>
      _trackingFrames > 0 ? (_trackingConfidenceSum / _trackingFrames).clamp(0.0, 1.0) : 0.5;

  Duration get sessionDuration {
    if (_sessionStart == null || _lastScoreTime == null) return Duration.zero;
    return _lastScoreTime!.difference(_sessionStart!);
  }

  /// Build the features struct for the BioAgeEstimator.
  BioAgeInputFeatures toFeatures({int? scoreOverride}) {
    final performanceScore = scoreOverride ?? pipesCleared;
    return BioAgeInputFeatures(
      mode: mode,
      totalValidReps: performanceScore,
      cadenceCv: cadenceCv,
      maxHoldSeconds: maxHoldSeconds,
      fatigueSlope: fatigueSlope,
      romConsistency: romConsistency,
      trackingQuality: trackingQuality,
      sessionDuration: sessionDuration,
    );
  }

  void reset() {
    pipesCleared = 0;
    _scoreIntervals.clear();
    _lastScoreTime = null;
    _sessionStart = null;
    maxHoldSeconds = 0;
    _trackingConfidenceSum = 0;
    _trackingFrames = 0;
  }
}
