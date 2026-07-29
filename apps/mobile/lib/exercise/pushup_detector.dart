import 'dart:math' as math;

import '../pose/pose_types.dart';
import 'exercise_types.dart';

enum PushupState { up, descending, down, ascending }

/// Computes the angle (in degrees) at vertex point [b] formed by
/// points [a]–[b]–[c].
double _angleDeg(PoseLandmark a, PoseLandmark b, PoseLandmark c) {
  final ba = math.Point(a.x - b.x, a.y - b.y);
  final bc = math.Point(c.x - b.x, c.y - b.y);
  final dot = ba.x * bc.x + ba.y * bc.y;
  final cross = ba.x * bc.y - ba.y * bc.x;
  final angle = math.atan2(cross.abs(), dot);
  return angle * 180 / math.pi;
}

PoseLandmark? _lm(PoseFrame frame, String name) {
  for (final lm in frame.landmarks) {
    if (lm.name == name) return lm;
  }
  return null;
}

/// Thresholds (degrees) for elbow angle to classify push-up phase.
const double _elbowDownThreshold = 90.0;
const double _elbowUpThreshold = 150.0;

class PushupDetector implements ExerciseDetector {
  PushupState _state = PushupState.up;
  DateTime? _downStart;

  @override
  List<ExerciseEvent> update(PoseFrame frame) {
    final events = <ExerciseEvent>[];

    if (frame.trackingConfidence < 0.4) return events;

    // Use the side with higher confidence landmarks.
    final leftShoulder = _lm(frame, 'left_shoulder');
    final leftElbow = _lm(frame, 'left_elbow');
    final leftWrist = _lm(frame, 'left_wrist');
    final rightShoulder = _lm(frame, 'right_shoulder');
    final rightElbow = _lm(frame, 'right_elbow');
    final rightWrist = _lm(frame, 'right_wrist');

    double? elbowAngle;

    if (leftShoulder != null && leftElbow != null && leftWrist != null &&
        rightShoulder != null && rightElbow != null && rightWrist != null) {
      final leftAngle = _angleDeg(leftShoulder, leftElbow, leftWrist);
      final rightAngle = _angleDeg(rightShoulder, rightElbow, rightWrist);
      // Average both sides for stability
      elbowAngle = (leftAngle + rightAngle) / 2;
    } else if (leftShoulder != null && leftElbow != null && leftWrist != null) {
      elbowAngle = _angleDeg(leftShoulder, leftElbow, leftWrist);
    } else if (rightShoulder != null && rightElbow != null && rightWrist != null) {
      elbowAngle = _angleDeg(rightShoulder, rightElbow, rightWrist);
    }

    if (elbowAngle == null) return events;

    switch (_state) {
      case PushupState.up:
        if (elbowAngle < _elbowDownThreshold) {
          _state = PushupState.descending;
        }
      case PushupState.descending:
        if (elbowAngle < _elbowDownThreshold) {
          _state = PushupState.down;
          _downStart = frame.timestamp;
        } else if (elbowAngle > _elbowUpThreshold) {
          // Went back up without reaching bottom
          _state = PushupState.up;
        }
      case PushupState.down:
        if (elbowAngle > _elbowUpThreshold) {
          _state = PushupState.ascending;
          if (_downStart != null) {
            final hold = frame.timestamp.difference(_downStart!);
            if (hold.inMilliseconds > 1200) {
              events.add(HoldCompletedEvent(
                frame.timestamp,
                type: 'pushup',
                holdDuration: hold,
              ));
            }
          }
        }
      case PushupState.ascending:
        if (elbowAngle > _elbowUpThreshold) {
          _state = PushupState.up;
          events.add(RepCompletedEvent(frame.timestamp, type: 'pushup'));
        } else if (elbowAngle < _elbowDownThreshold) {
          _state = PushupState.down;
          _downStart = frame.timestamp;
        }
    }

    return events;
  }

  @override
  void reset() {
    _state = PushupState.up;
    _downStart = null;
  }
}
