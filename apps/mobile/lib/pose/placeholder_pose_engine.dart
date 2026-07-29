import 'dart:typed_data';

import 'pose_engine.dart';
import 'pose_types.dart';

class PlaceholderPoseEngine implements PoseEngine {
  @override
  Future<void> initialize() async {}

  @override
  Future<PoseFrame?> processCameraFrame(
    Uint8List bytes,
    int width,
    int height,
  ) async {
    return PoseFrame(
      landmarks: const [],
      trackingConfidence: 0.0,
      timestamp: DateTime.now(),
    );
  }

  @override
  Future<void> dispose() async {}
}
