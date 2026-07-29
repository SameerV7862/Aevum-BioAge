import 'mediapipe_web_pose_engine.dart';
import 'pose_engine.dart';

/// Web platform factory. Returns [MediaPipeWebPoseEngine].
PoseEngine createPlatformPoseEngine() => MediaPipeWebPoseEngine();
