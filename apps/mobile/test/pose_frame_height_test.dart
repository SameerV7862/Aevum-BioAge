import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/pose/pose_types.dart';

void main() {
  test('estimates normalized height from visible landmarks', () {
    final frame = PoseFrame(
      landmarks: const [
        PoseLandmark(name: 'nose', x: 0.5, y: 0.2, z: 0.0, confidence: 0.9),
        PoseLandmark(name: 'left_shoulder', x: 0.3, y: 0.4, z: 0.0, confidence: 0.9),
        PoseLandmark(name: 'right_shoulder', x: 0.7, y: 0.4, z: 0.0, confidence: 0.9),
      ],
      trackingConfidence: 0.8,
      timestamp: DateTime.now(),
    );

    expect(frame.estimateVerticalNormalizedHeight(), closeTo(0.6, 1e-9));
  });

  test('calibrator maps observed maximum extension to full height', () {
    final calibrator = PoseHeightCalibrator();

    expect(calibrator.normalize(0.48), closeTo(0.0, 1e-9));
    expect(calibrator.normalize(0.57), closeTo(0.5, 1e-9));
    expect(calibrator.normalize(0.66), closeTo(1.0, 1e-9));
  });

  test('view assessment reports ready when upper body is visible and centered', () {
    final frame = PoseFrame(
      landmarks: const [
        PoseLandmark(name: 'nose', x: 0.5, y: 0.18, z: 0.0, confidence: 0.9),
        PoseLandmark(name: 'left_shoulder', x: 0.38, y: 0.33, z: 0.0, confidence: 0.9),
        PoseLandmark(name: 'right_shoulder', x: 0.62, y: 0.33, z: 0.0, confidence: 0.9),
        PoseLandmark(name: 'left_hip', x: 0.42, y: 0.58, z: 0.0, confidence: 0.8),
        PoseLandmark(name: 'right_hip', x: 0.58, y: 0.58, z: 0.0, confidence: 0.8),
      ],
      trackingConfidence: 0.8,
      timestamp: DateTime.now(),
    );

    expect(frame.assessView().isReady, isTrue);
  });

  test('view assessment can stay ready with upper-body tracking when hips are not visible', () {
    final frame = PoseFrame(
      landmarks: const [
        PoseLandmark(name: 'nose', x: 0.5, y: 0.18, z: 0.0, confidence: 0.9),
        PoseLandmark(name: 'left_shoulder', x: 0.38, y: 0.33, z: 0.0, confidence: 0.9),
        PoseLandmark(name: 'right_shoulder', x: 0.62, y: 0.33, z: 0.0, confidence: 0.9),
      ],
      trackingConfidence: 0.8,
      timestamp: DateTime.now(),
    );

    expect(frame.assessView().isReady, isTrue);
  });
}
