import 'dart:js_interop';
import 'dart:typed_data';

import 'pose_engine.dart';
import 'pose_types.dart';

/// Standard MediaPipe Pose landmark names (33 landmarks).
const List<String> _mediaPipeLandmarkNames = [
  'nose', 'left_eye_inner', 'left_eye', 'left_eye_outer',
  'right_eye_inner', 'right_eye', 'right_eye_outer',
  'left_ear', 'right_ear', 'mouth_left', 'mouth_right',
  'left_shoulder', 'right_shoulder', 'left_elbow', 'right_elbow',
  'left_wrist', 'right_wrist', 'left_pinky', 'right_pinky',
  'left_index', 'right_index', 'left_thumb', 'right_thumb',
  'left_hip', 'right_hip', 'left_knee', 'right_knee',
  'left_ankle', 'right_ankle', 'left_heel', 'right_heel',
  'left_foot_index', 'right_foot_index',
];

// --- JS interop bindings ---

@JS('AevumPoseBridge.initialize')
external JSPromise _jsInitialize();

@JS('AevumPoseBridge.processVideoFrame')
external JSPromise _jsProcessVideoFrame();

@JS('AevumPoseBridge.dispose')
external void _jsDispose();

@JS('AevumPoseBridge.setVideoElement')
external void _jsSetVideoElement(JSObject videoEl);

/// JS interop extension type for the pose result object returned by the bridge.
extension type JSPoseResult._(JSObject _) implements JSObject {
  external JSArray<JSLandmark> get landmarks;
  external JSNumber get confidence;
}

/// JS interop extension type for a single landmark.
extension type JSLandmark._(JSObject _) implements JSObject {
  external JSNumber get x;
  external JSNumber get y;
  external JSNumber get z;
  external JSNumber get visibility;
}

/// Web-specific [PoseEngine] that delegates to MediaPipe Pose Landmarker
/// running in the browser via `mediapipe_pose_bridge.js`.
///
/// On non-web platforms this class should never be instantiated — use
/// [PlaceholderPoseEngine] or a native ML Kit adapter instead.
class MediaPipeWebPoseEngine implements PoseEngine {
  bool _initialized = false;

  @override
  Future<void> initialize() async {
    final jsResult = await _jsInitialize().toDart;
    _initialized = (jsResult as JSBoolean).toDart;
    if (!_initialized) {
      throw StateError('MediaPipe Pose Landmarker failed to initialize');
    }
  }

  /// Attach the HTML <video> element that the camera feed writes to.
  void setVideoElement(JSObject videoElement) {
    _jsSetVideoElement(videoElement);
  }

  @override
  Future<PoseFrame?> processCameraFrame(
    Uint8List bytes,
    int width,
    int height,
  ) async {
    if (!_initialized) return null;

    final jsResult = await _jsProcessVideoFrame().toDart;
    if (jsResult == null || jsResult.isUndefinedOrNull) return null;

    final result = jsResult as JSPoseResult;
    final jsLandmarks = result.landmarks;
    final confidence = result.confidence.toDartDouble;
    final count = jsLandmarks.length;

    final landmarks = <PoseLandmark>[];
    for (var i = 0; i < count && i < 33; i++) {
      final lm = jsLandmarks[i];
      landmarks.add(PoseLandmark(
        name: i < _mediaPipeLandmarkNames.length
            ? _mediaPipeLandmarkNames[i]
            : 'landmark_$i',
        x: lm.x.toDartDouble,
        y: lm.y.toDartDouble,
        z: lm.z.toDartDouble,
        confidence: lm.visibility.toDartDouble,
      ));
    }

    return PoseFrame(
      landmarks: landmarks,
      trackingConfidence: confidence,
      timestamp: DateTime.now(),
    );
  }

  @override
  Future<void> dispose() async {
    if (_initialized) {
      _jsDispose();
      _initialized = false;
    }
  }
}
