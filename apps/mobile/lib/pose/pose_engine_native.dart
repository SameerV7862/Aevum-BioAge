import 'pose_engine.dart';
import 'placeholder_pose_engine.dart';

/// Stub for non-web platforms. Returns [PlaceholderPoseEngine].
PoseEngine createPlatformPoseEngine() => PlaceholderPoseEngine();
