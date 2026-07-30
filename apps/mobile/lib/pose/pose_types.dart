class PoseLandmark {
  final String name;
  final double x;
  final double y;
  final double z;
  final double confidence;

  const PoseLandmark({
    required this.name,
    required this.x,
    required this.y,
    required this.z,
    required this.confidence,
  });
}

class PoseFrame {
  final List<PoseLandmark> landmarks;
  final double trackingConfidence;
  final DateTime timestamp;

  const PoseFrame({
    required this.landmarks,
    required this.trackingConfidence,
    required this.timestamp,
  });

  double estimateVerticalNormalizedHeight() {
    if (landmarks.isEmpty) return 0.0;

    final shoulders = landmarks.where((landmark) => landmark.name.contains('shoulder')).toList();
    final hips = landmarks.where((landmark) => landmark.name.contains('hip')).toList();

    // Prefer torso center so slight head movements do not dominate control.
    if (shoulders.isNotEmpty && hips.isNotEmpty) {
      final avgShoulderY = shoulders.fold<double>(0.0, (sum, landmark) => sum + landmark.y) / shoulders.length;
      final avgHipY = hips.fold<double>(0.0, (sum, landmark) => sum + landmark.y) / hips.length;
      final torsoCenter = (avgShoulderY + avgHipY) / 2.0;
      return (1.0 - torsoCenter).clamp(0.0, 1.0);
    }

    if (shoulders.isNotEmpty) {
      final avgShoulderY = shoulders.fold<double>(0.0, (sum, landmark) => sum + landmark.y) / shoulders.length;
      return (1.0 - avgShoulderY).clamp(0.0, 1.0);
    }

    final visibleLandmarks = landmarks.where((landmark) => landmark.confidence > 0.2).toList();
    if (visibleLandmarks.isEmpty) return 0.0;

    final minY = visibleLandmarks.map((landmark) => landmark.y).reduce((a, b) => a < b ? a : b);
    final maxY = visibleLandmarks.map((landmark) => landmark.y).reduce((a, b) => a > b ? a : b);
    return (1.0 - ((minY + maxY) / 2.0)).clamp(0.0, 1.0);
  }

  double estimateUpperBodyNormalizedHeight() {
    if (landmarks.isEmpty) return 0.0;

    final shoulders = landmarks
        .where((landmark) => landmark.name.contains('shoulder') && landmark.confidence > 0.3)
        .toList();
    if (shoulders.isNotEmpty) {
      final avgShoulderY =
          shoulders.fold<double>(0.0, (sum, landmark) => sum + landmark.y) / shoulders.length;
      return (1.0 - avgShoulderY).clamp(0.0, 1.0);
    }

    final nose = landmarks
        .where((landmark) => landmark.name == 'nose' && landmark.confidence > 0.3)
        .firstOrNull;
    if (nose != null) {
      return (1.0 - nose.y).clamp(0.0, 1.0);
    }

    return estimateVerticalNormalizedHeight();
  }

  PoseViewAssessment assessView() {
    if (trackingConfidence < 0.4) {
      return const PoseViewAssessment(
        isReady: false,
        message: 'Move into brighter light and face the camera directly.',
      );
    }

    final leftShoulder = landmarks.where((landmark) => landmark.name == 'left_shoulder' && landmark.confidence > 0.35).firstOrNull;
    final rightShoulder = landmarks.where((landmark) => landmark.name == 'right_shoulder' && landmark.confidence > 0.35).firstOrNull;
    final nose = landmarks.where((landmark) => landmark.name == 'nose' && landmark.confidence > 0.3).firstOrNull;
    final leftHip = landmarks.where((landmark) => landmark.name == 'left_hip' && landmark.confidence > 0.25).firstOrNull;
    final rightHip = landmarks.where((landmark) => landmark.name == 'right_hip' && landmark.confidence > 0.25).firstOrNull;

    if (leftShoulder == null || rightShoulder == null) {
      return const PoseViewAssessment(
        isReady: false,
        message: 'Step back until both shoulders are clearly visible.',
      );
    }

    // Hips are helpful, but do not hard-fail readiness when upper body is stable.
    final hasHips = leftHip != null && rightHip != null;
    final hasHeadAnchor = nose != null;

    if (!hasHeadAnchor && !hasHips) {
      return const PoseViewAssessment(
        isReady: false,
        message: 'Keep your upper torso visible throughout the full movement range.',
      );
    }

    final centerX = hasHips
        ? (leftShoulder.x + rightShoulder.x + leftHip!.x + rightHip!.x) / 4.0
        : (leftShoulder.x + rightShoulder.x) / 2.0;
    if (centerX < 0.24 || centerX > 0.76) {
      return const PoseViewAssessment(
        isReady: false,
        message: 'Center your body in the frame before starting calibration.',
      );
    }

    if (hasHips) {
      final topAnchorY = nose?.y ?? ((leftShoulder.y + rightShoulder.y) / 2.0 - 0.08).clamp(0.0, 1.0);
      final torsoHeight = ((leftHip.y + rightHip.y) / 2.0) - topAnchorY;
      if (torsoHeight < 0.14) {
        return const PoseViewAssessment(
          isReady: false,
          message: 'Move slightly closer only if your full rep range still stays in frame.',
        );
      }
      if (torsoHeight > 0.78) {
        return const PoseViewAssessment(
          isReady: false,
          message: 'Step back a bit so your full movement range remains visible.',
        );
      }
    }

    if (!hasHips) {
      return const PoseViewAssessment(
        isReady: true,
        message: 'Upper body tracking is ready. Keep enough distance for full range of motion.',
      );
    }

    if (!hasHeadAnchor) {
      return const PoseViewAssessment(
        isReady: true,
        message: 'Torso tracking is ready even if your head dips out of frame during reps.',
      );
    }

    return const PoseViewAssessment(
      isReady: true,
      message: 'You are properly in view. Hold position while calibration finishes.',
    );
  }
}

class PoseViewAssessment {
  final bool isReady;
  final String message;

  const PoseViewAssessment({required this.isReady, required this.message});
}

class PoseHeightCalibrator {
  double? _minObserved;
  double? _maxObserved;
  double? _lockedMin;
  double? _lockedMax;
  double? _lockedBaseline;
  final List<double> _calibrationSamples = <double>[];

  bool get hasLockedRange => _lockedMin != null && _lockedMax != null;

  void addCalibrationSample(double rawHeight) {
    final clamped = rawHeight.clamp(0.0, 1.0);
    _calibrationSamples.add(clamped);
    if (_calibrationSamples.length > 1200) {
      _calibrationSamples.removeAt(0);
    }
  }

  bool finalizeCalibration({double minimumRange = 0.1}) {
    if (_calibrationSamples.length < 24) return false;

    final sorted = [..._calibrationSamples]..sort();
    final p10 = _percentile(sorted, 0.10);
    final p90 = _percentile(sorted, 0.90);
    final median = _percentile(sorted, 0.50);
    final observedRange = p90 - p10;

    if (observedRange < minimumRange) return false;

    final expanded = observedRange * 1.15;
    final minLocked = (median - expanded * 0.55).clamp(0.0, 1.0);
    final maxLocked = (median + expanded * 0.45).clamp(0.0, 1.0);
    final lockedRange = (maxLocked - minLocked).clamp(0.12, 1.0);

    _lockedMin = minLocked;
    _lockedMax = minLocked + lockedRange;
    _lockedBaseline = median.clamp(_lockedMin!, _lockedMax!);
    return true;
  }

  void setLockedRange({required double minValue, required double maxValue, double? baseline}) {
    final minLocked = minValue.clamp(0.0, 1.0);
    final maxLocked = maxValue.clamp(0.0, 1.0);
    final range = (maxLocked - minLocked).clamp(0.12, 1.0);
    _lockedMin = minLocked;
    _lockedMax = minLocked + range;
    _lockedBaseline = (baseline ?? (minLocked + range * 0.5)).clamp(_lockedMin!, _lockedMax!);
  }

  double normalizeForControl(double rawHeight, {bool reduceSensitivity = true}) {
    final normalized = normalize(rawHeight);
    if (!reduceSensitivity) return normalized;

    // Keep controls responsive while avoiding extremes from minor jitter.
    final softened = 0.14 + (normalized * 0.72);
    return softened.clamp(0.0, 1.0);
  }

  double normalizeRelativeToBaseline(double rawHeight) {
    if (_lockedMin == null || _lockedMax == null || _lockedBaseline == null) {
      return normalizeForControl(rawHeight);
    }

    final clamped = rawHeight.clamp(0.0, 1.0);
    final minLocked = _lockedMin!;
    final maxLocked = _lockedMax!;
    final baseline = _lockedBaseline!;

    final downSpan = (baseline - minLocked).clamp(0.06, 1.0);
    final upSpan = (maxLocked - baseline).clamp(0.06, 1.0);

    if (clamped <= baseline) {
      final t = (clamped - minLocked) / downSpan;
      return (0.12 + (t.clamp(0.0, 1.0) * 0.44)).clamp(0.0, 1.0);
    }

    final t = (clamped - baseline) / upSpan;
    return (0.56 + (t.clamp(0.0, 1.0) * 0.36)).clamp(0.0, 1.0);
  }

  double normalize(double rawHeight) {
    final clamped = rawHeight.clamp(0.0, 1.0);

    if (_lockedMin != null && _lockedMax != null) {
      final minLocked = _lockedMin!;
      final maxLocked = _lockedMax!;
      final range = (maxLocked - minLocked).clamp(0.12, 1.0);
      final normalized = (clamped - minLocked) / range;
      return normalized.clamp(0.0, 1.0);
    }

    _minObserved = _minObserved == null ? clamped : (_minObserved! > clamped ? clamped : _minObserved!);
    _maxObserved = _maxObserved == null ? clamped : (_maxObserved! < clamped ? clamped : _maxObserved!);

    final minObserved = _minObserved ?? 0.0;
    final maxObserved = _maxObserved ?? 1.0;
    final range = (maxObserved - minObserved).clamp(0.18, 1.0);
    final normalized = (clamped - minObserved) / range;
    return normalized.clamp(0.0, 1.0);
  }

  void reset() {
    _minObserved = null;
    _maxObserved = null;
    _lockedMin = null;
    _lockedMax = null;
    _lockedBaseline = null;
    _calibrationSamples.clear();
  }

  double _percentile(List<double> sorted, double percentile) {
    if (sorted.isEmpty) return 0.0;
    if (sorted.length == 1) return sorted.first;
    final rank = percentile.clamp(0.0, 1.0) * (sorted.length - 1);
    final lower = rank.floor();
    final upper = rank.ceil();
    if (lower == upper) return sorted[lower];
    final weight = rank - lower;
    return sorted[lower] * (1 - weight) + sorted[upper] * weight;
  }
}

extension on Iterable<PoseLandmark> {
  PoseLandmark? get firstOrNull => isEmpty ? null : first;
}
