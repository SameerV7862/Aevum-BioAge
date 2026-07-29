import '../exercise/exercise_types.dart';
import '../game/aevum_flappy_game.dart';

/// Maps [ExerciseEvent]s from the pose-detection pipeline into game actions.
///
/// Tracks rapid successive reps to trigger double-fast / burst-boost.
class ExerciseGameBridge {
  final AevumFlappyGame game;

  DateTime? _lastRepTime;
  static const _doubleFastWindow = Duration(milliseconds: 800);

  ExerciseGameBridge(this.game);

  /// Feed an exercise event; the bridge decides which game action to fire.
  void onEvent(ExerciseEvent event) {
    if (event is HoldCompletedEvent) {
      game.onHoldEvent();
      return;
    }

    if (event is RepCompletedEvent) {
      final now = event.timestamp;
      if (_lastRepTime != null &&
          now.difference(_lastRepTime!) < _doubleFastWindow) {
        game.onDoubleFast();
        _lastRepTime = null; // consume the pair
      } else {
        game.onNormalRep();
        _lastRepTime = now;
      }
    }
  }

  void reset() {
    _lastRepTime = null;
  }
}
