import '../pose/pose_types.dart';
import 'exercise_types.dart';

enum PushupState { up, descending, down, ascending }

class PushupDetector implements ExerciseDetector {
  PushupState _state = PushupState.up;
  DateTime? _downStart;

  @override
  List<ExerciseEvent> update(PoseFrame frame) {
    // TODO: Replace with real joint-angle logic from landmarks.
    // Scaffold keeps state-machine hooks for easy threshold tuning later.
    final events = <ExerciseEvent>[];

    if (frame.trackingConfidence < 0.4) return events;

    // Placeholder pseudo-cycle trigger by timestamp seconds.
    final second = frame.timestamp.second;
    if (second % 4 == 1 && _state == PushupState.up) {
      _state = PushupState.descending;
    } else if (second % 4 == 2 && _state == PushupState.descending) {
      _state = PushupState.down;
      _downStart = frame.timestamp;
    } else if (second % 4 == 3 && _state == PushupState.down) {
      _state = PushupState.ascending;
      if (_downStart != null) {
        final hold = frame.timestamp.difference(_downStart!);
        if (hold.inMilliseconds > 1200) {
          events.add(HoldCompletedEvent(frame.timestamp, type: 'pushup', holdDuration: hold));
        }
      }
    } else if (second % 4 == 0 && _state == PushupState.ascending) {
      _state = PushupState.up;
      events.add(RepCompletedEvent(frame.timestamp, type: 'pushup'));
    }

    return events;
  }

  @override
  void reset() {
    _state = PushupState.up;
    _downStart = null;
  }
}
