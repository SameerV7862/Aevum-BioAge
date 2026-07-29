import 'dart:async';
import 'dart:typed_data';

import '../exercise/exercise_types.dart';
import '../pose/pose_engine.dart';
import '../pose/pose_types.dart';

/// Orchestrates the camera → pose → exercise-detector pipeline.
///
/// [PosePipeline] accepts raw camera frames, runs them through a
/// [PoseEngine], feeds the resulting [PoseFrame] to the active
/// [ExerciseDetector], and emits any resulting [ExerciseEvent]s.
class PosePipeline {
  final PoseEngine poseEngine;
  ExerciseDetector detector;

  final _eventController = StreamController<ExerciseEvent>.broadcast();

  /// Stream of exercise events produced by the active detector.
  Stream<ExerciseEvent> get events => _eventController.stream;

  /// The most recent pose frame (for debug overlay, etc.).
  PoseFrame? lastFrame;

  bool _processing = false;

  PosePipeline({required this.poseEngine, required this.detector});

  /// Initialize the underlying pose engine.
  Future<void> initialize() => poseEngine.initialize();

  /// Process a single camera frame. Drops frames if the previous
  /// one hasn't finished (non-blocking back-pressure).
  Future<void> processFrame(Uint8List bytes, int width, int height) async {
    if (_processing) return; // drop frame
    _processing = true;

    try {
      final frame = await poseEngine.processCameraFrame(bytes, width, height);
      if (frame != null) {
        lastFrame = frame;
        final events = detector.update(frame);
        for (final event in events) {
          _eventController.add(event);
        }
      }
    } finally {
      _processing = false;
    }
  }

  /// Switch the active detector (e.g. pushup ↔ squat).
  void setDetector(ExerciseDetector newDetector) {
    detector.reset();
    detector = newDetector;
  }

  Future<void> dispose() async {
    await _eventController.close();
    await poseEngine.dispose();
  }
}
