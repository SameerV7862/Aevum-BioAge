import 'dart:typed_data';

import 'pose_types.dart';

abstract class PoseEngine {
  Future<void> initialize();
  Future<PoseFrame?> processCameraFrame(Uint8List bytes, int width, int height);
  Future<void> dispose();
}
