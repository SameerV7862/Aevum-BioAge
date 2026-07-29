import 'dart:async';

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import 'components/background.dart';
import 'components/crane_sprite.dart';
import 'components/pipe.dart';
import 'components/score_display.dart';

/// Velocity-based crane physics constants.
const double _gravity = 420.0; // px/s²
const double _flapImpulse = -200.0; // px/s
const double _glideImpulse = -60.0;
const double _boostImpulse = -320.0;
const double _maxFallSpeed = 400.0;
const double _scrollSpeed = 130.0;
const double _pipeGap = 150.0;

enum GameState { ready, playing, gameOver }

class AevumFlappyGame extends FlameGame
    with TapCallbacks {
  late CraneSpriteComponent crane;
  late PipeSpawner pipeSpawner;
  late GroundComponent ground;
  late SkyBackground sky;
  late ScoreDisplay scoreDisplay;

  double _velocityY = 0;
  GameState state = GameState.ready;

  /// Stream of game events for external listeners.
  final _eventController = StreamController<GameEvent>.broadcast();
  Stream<GameEvent> get events => _eventController.stream;

  /// Callback to notify Flutter overlay of state changes.
  void Function(GameState state)? onStateChanged;

  int get score => scoreDisplay.score;

  @override
  Color backgroundColor() => const Color(0x00000000); // transparent

  @override
  Future<void> onLoad() async {
    // Background layers
    sky = SkyBackground();
    add(sky);

    ground = GroundComponent(scrollSpeed: _scrollSpeed);
    add(ground);

    // Score
    scoreDisplay = ScoreDisplay();
    add(scoreDisplay);

    // Crane
    crane = CraneSpriteComponent()
      ..anchor = Anchor.center;
    add(crane);

    // Pipe spawner
    pipeSpawner = PipeSpawner(
      scrollSpeed: _scrollSpeed,
      gapHeight: _pipeGap,
    )..onScored = () {
        scoreDisplay.increment();
        _eventController.add(GameEvent.scored);
      };
    add(pipeSpawner);

    _resetPositions();
  }

  void _resetPositions() {
    crane.position = Vector2(size.x * 0.25, size.y * 0.4);
    _velocityY = 0;
  }

  @override
  void update(double dt) {
    super.update(dt);

    if (state != GameState.playing) return;

    // Gravity
    _velocityY += _gravity * dt;
    if (_velocityY > _maxFallSpeed) _velocityY = _maxFallSpeed;
    crane.y += _velocityY * dt;

    // Update pipe spawner crane position for scoring
    pipeSpawner.craneX = crane.x;

    // Ceiling clamp
    if (crane.y < 32) {
      crane.y = 32;
      _velocityY = 0;
    }

    // Ground collision
    if (crane.y > ground.topY - 16) {
      crane.y = ground.topY - 16;
      _die();
      return;
    }

    // Pipe collision (AABB check against crane bounds)
    _checkPipeCollisions();

    // Return to idle anim when falling
    if (_velocityY > 0 && crane.animState != CraneAnimState.idle) {
      crane.setAnimState(CraneAnimState.idle);
    }

    // Tilt crane based on velocity
    crane.angle = (_velocityY / _maxFallSpeed) * 0.5; // subtle rotation
  }

  void _checkPipeCollisions() {
    final craneRect = Rect.fromCenter(
      center: Offset(crane.x, crane.y),
      width: 40,
      height: 28,
    );

    for (final child in children) {
      if (child is PipePair) {
        final topRect = Rect.fromLTWH(
          child.x,
          0,
          child.pipeWidth,
          child.gapY,
        );
        final bottomRect = Rect.fromLTWH(
          child.x,
          child.gapY + child.gapHeight,
          child.pipeWidth,
          size.y - (child.gapY + child.gapHeight),
        );

        if (craneRect.overlaps(topRect) || craneRect.overlaps(bottomRect)) {
          _die();
          return;
        }
      }
    }
  }

  void _die() {
    state = GameState.gameOver;
    _eventController.add(GameEvent.died);
    onStateChanged?.call(state);
  }

  // --- Input handling ---

  @override
  void onTapDown(TapDownEvent event) {
    switch (state) {
      case GameState.ready:
        startPlaying();
      case GameState.playing:
        onNormalRep();
      case GameState.gameOver:
        break; // handled by overlay button
    }
  }

  void startPlaying() {
    state = GameState.playing;
    _velocityY = _flapImpulse * 0.5; // gentle initial lift
    onStateChanged?.call(state);
  }

  void restart() {
    pipeSpawner.reset();
    ground.reset();
    scoreDisplay.reset();
    _resetPositions();
    crane.angle = 0;
    crane.setAnimState(CraneAnimState.idle);
    state = GameState.ready;
    onStateChanged?.call(state);
  }

  // --- Exercise event inputs ---

  void onNormalRep() {
    if (state == GameState.ready) startPlaying();
    if (state != GameState.playing) return;
    _velocityY = _flapImpulse;
    crane.setAnimState(CraneAnimState.flap);
    _eventController.add(GameEvent.flap);
  }

  void onHoldEvent() {
    if (state != GameState.playing) return;
    _velocityY = _glideImpulse;
    crane.setAnimState(CraneAnimState.glide);
    _eventController.add(GameEvent.glide);
  }

  void onDoubleFast() {
    if (state == GameState.ready) startPlaying();
    if (state != GameState.playing) return;
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

enum GameEvent { flap, glide, boost, scored, died }

