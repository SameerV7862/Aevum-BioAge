import 'pose_engine.dart';

// Conditional import: web targets get the MediaPipe adapter,
// native targets get the placeholder stub.
import 'pose_engine_native.dart'
    if (dart.library.js_interop) 'pose_engine_web.dart';

/// Creates the appropriate [PoseEngine] for the current platform.
///
/// On web → [MediaPipeWebPoseEngine] backed by the browser JS bridge.
/// On native → [PlaceholderPoseEngine] (swap for ML Kit / TFLite later).
PoseEngine createPoseEngine() => createPlatformPoseEngine();
