import 'dart:async';

import 'package:flame/components.dart';
import 'package:flame/game.dart';

import 'components/crane_sprite.dart';

/// Velocity-based crane physics constants.
const double _gravity = 320.0; // px/s²
const double _flapImpulse = -180.0; // px/s
const double _glideImpulse = -40.0;
const double _boostImpulse = -280.0;
const double _maxFallSpeed = 300.0;

class AevumFlappyGame extends FlameGame {
  late final CraneSpriteComponent crane;
  double _velocityY = 0;
  bool _alive = true;

  /// Stream of game events for external listeners (score UI, analytics, etc.).
  final _eventController = StreamController<GameEvent>.broadcast();
  Stream<GameEvent> get events => _eventController.stream;

  @override
  Future<void> onLoad() async {
    crane = CraneSpriteComponent()
      ..position = Vector2(size.x * 0.25, size.y * 0.5)
      ..anchor = Anchor.center;
    add(crane);
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (!_alive) return;

    _velocityY += _gravity * dt;
    if (_velocityY > _maxFallSpeed) _velocityY = _maxFallSpeed;
    crane.y += _velocityY * dt;

    // Clamp to screen bounds
    if (crane.y < 0) {
      crane.y = 0;
      _velocityY = 0;
    }
    if (crane.y > size.y) {
      crane.y = size.y;
      _velocityY = 0;
    }

    // Return to idle when falling
    if (_velocityY > 0 && crane.animState != CraneAnimState.idle) {
      crane.setAnimState(CraneAnimState.idle);
    }
  }

  void onNormalRep() {
    _velocityY = _flapImpulse;
    crane.setAnimState(CraneAnimState.flap);
    _eventController.add(GameEvent.flap);
  }

  void onHoldEvent() {
    _velocityY = _glideImpulse;
    crane.setAnimState(CraneAnimState.glide);
    _eventController.add(GameEvent.glide);
  }

  void onDoubleFast() {
    _velocityY = _boostImpulse;
    crane.setAnimState(CraneAnimState.boost);
    _eventController.add(GameEvent.boost);
  }

  @override
  void onRemove() {
    _eventController.close();
    super.onRemove();
  }
}

enum GameEvent { flap, glide, boost }

