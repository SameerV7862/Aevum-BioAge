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

/// Base thresholds; effective thresholds are adapted to observed range.
const double _elbowDownThreshold = 104.0;
const double _elbowRecoveryThreshold = 122.0;
const double _elbowUpThreshold = 146.0;
const double _elbowDescendingTrigger = 136.0;
const int _repCooldownMs = 320;
const int _minRepDurationMs = 420;

class PushupDetector implements ExerciseDetector {
  PushupState _state = PushupState.up;
  DateTime? _downStart;
  DateTime? _cycleStart;
  DateTime? _lastRepTime;
  double? _smoothedAngle;
  double _observedTop = 160.0;
  double _observedBottom = 96.0;

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

    final rawAngle = elbowAngle;
    _smoothedAngle = _smoothedAngle == null
        ? rawAngle
        : (_smoothedAngle! + (rawAngle - _smoothedAngle!) * 0.32);
    final angle = _smoothedAngle!;

    _observedTop = (_observedTop * 0.98) + (angle * 0.02);
    _observedBottom = (_observedBottom * 0.98) + (angle * 0.02);
    if (angle > _observedTop) _observedTop = angle;
    if (angle < _observedBottom) _observedBottom = angle;

    final dynamicDescendingTrigger = (_observedTop - 14).clamp(128.0, 148.0);
    final dynamicDownThreshold = (_observedTop - 40).clamp(88.0, 118.0);
    final dynamicRecoveryThreshold = (dynamicDownThreshold + 12).clamp(104.0, 132.0);
    final dynamicUpThreshold = (_observedTop - 6).clamp(132.0, 154.0);

    switch (_state) {
      case PushupState.up:
        if (angle < dynamicDescendingTrigger) {
          _state = PushupState.descending;
          _cycleStart = frame.timestamp;
        }
      case PushupState.descending:
        if (angle < dynamicDownThreshold) {
          _state = PushupState.down;
          _downStart = frame.timestamp;
        } else if (angle > dynamicUpThreshold) {
          // Went back up without reaching bottom
          _state = PushupState.up;
        }
      case PushupState.down:
        if (angle > dynamicRecoveryThreshold) {
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
        if (angle > dynamicUpThreshold) {
          final durationOk = _cycleStart == null
              ? true
              : frame.timestamp.difference(_cycleStart!).inMilliseconds >= _minRepDurationMs;
          final cooldownOk = _lastRepTime == null
              ? true
              : frame.timestamp.difference(_lastRepTime!).inMilliseconds >= _repCooldownMs;

          _state = PushupState.up;
          if (durationOk && cooldownOk) {
            _lastRepTime = frame.timestamp;
            events.add(RepCompletedEvent(frame.timestamp, type: 'pushup'));
          }
        } else if (angle < dynamicDownThreshold) {
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
    _cycleStart = null;
    _lastRepTime = null;
    _smoothedAngle = null;
    _observedTop = 160.0;
    _observedBottom = 96.0;
  }
}
