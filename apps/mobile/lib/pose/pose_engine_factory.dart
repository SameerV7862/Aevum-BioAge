import 'pose_engine.dart';
import 'pose_engine_native.dart'
	if (dart.library.html) 'pose_engine_web_factory.dart';

/// Creates the appropriate [PoseEngine] for the current platform.
PoseEngine createPoseEngine() => createPlatformPoseEngine();
