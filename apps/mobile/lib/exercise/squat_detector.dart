import '../pose/pose_types.dart';
import 'exercise_types.dart';

enum SquatState { standing, descending, bottom, ascending }

class SquatDetector implements ExerciseDetector {
  SquatState _state = SquatState.standing;
  DateTime? _bottomStart;

  @override
  List<ExerciseEvent> update(PoseFrame frame) {
    // TODO: Replace with real hip/knee angle thresholds using landmarks.
    final events = <ExerciseEvent>[];
    if (frame.trackingConfidence < 0.4) return events;

    final second = frame.timestamp.second;
    if (second % 5 == 1 && _state == SquatState.standing) {
      _state = SquatState.descending;
    } else if (second % 5 == 2 && _state == SquatState.descending) {
      _state = SquatState.bottom;
      _bottomStart = frame.timestamp;
    } else if (second % 5 == 3 && _state == SquatState.bottom) {
      _state = SquatState.ascending;
      if (_bottomStart != null) {
        final hold = frame.timestamp.difference(_bottomStart!);
        if (hold.inMilliseconds > 1500) {
          events.add(HoldCompletedEvent(frame.timestamp, type: 'squat', holdDuration: hold));
        }
      }
    } else if (second % 5 == 4 && _state == SquatState.ascending) {
      _state = SquatState.standing;
      events.add(RepCompletedEvent(frame.timestamp, type: 'squat'));
    }

    return events;
  }

  @override
  void reset() {
    _state = SquatState.standing;
    _bottomStart = null;
  }
}
