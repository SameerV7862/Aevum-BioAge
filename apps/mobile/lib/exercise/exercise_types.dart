import '../pose/pose_types.dart';

abstract class ExerciseEvent {
  final DateTime timestamp;
  const ExerciseEvent(this.timestamp);
}

class RepCompletedEvent extends ExerciseEvent {
  final String type; // pushup | squat
  final bool valid;
  const RepCompletedEvent(super.timestamp, {required this.type, this.valid = true});
}

class HoldCompletedEvent extends ExerciseEvent {
  final String type;
  final Duration holdDuration;
  const HoldCompletedEvent(super.timestamp, {required this.type, required this.holdDuration});
}

abstract class ExerciseDetector {
  List<ExerciseEvent> update(PoseFrame frame);
  void reset();
}
