import 'pose_engine.dart';
import 'mediapipe_web_pose_engine.dart';

PoseEngine createPlatformPoseEngine() => MediaPipeWebPoseEngine();