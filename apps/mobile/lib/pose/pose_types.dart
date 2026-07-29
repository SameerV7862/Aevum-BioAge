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
}
