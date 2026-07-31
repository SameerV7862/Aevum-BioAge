import 'dart:async';
import 'dart:math' as math;

import 'package:flame/components.dart';
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
const double _maxFallSpeed = 430.0;
const double _scrollSpeed = 118.0;
const double _pipeGap = 170.0;
const double _birdWidth = 44.0;
const double _birdHeight = 32.0;
const double _maxLiftAcceleration = 620.0;
const double _poseResponse = 4.8;
const double _airDrag = 0.982;
const double _collisionDropImpulse = 520.0;
const double _collisionDropNudge = 14.0;
const double _collisionFxDuration = 0.22;
const double _pipeAssistStrength = 0.42;
const double _pipeAssistWindow = 430.0;
const double _directionSwapDamping = 0.55;
const double _demoFloorRecoveryBand = 78.0;

enum GameState { ready, playing, gameOver }

class AevumFlappyGame extends FlameGame {
  late CraneSpriteComponent crane;
  late PipeSpawner pipeSpawner;
  late GroundComponent ground;
  late SkyBackground sky;
  late ScoreDisplay scoreDisplay;

  double _velocityY = 0;
  double _targetBirdY = 0;
  double _filteredPoseHeight = 0.5;
  GameState state = GameState.ready;
  bool _hasCollided = false;
  bool _isDemoRound = false;
  bool _demoCollisionSinceLastClear = false;
  double _demoCollisionCooldown = 0.0;
  double _collisionFxTime = 0.0;
  double _collisionBaseX = 0.0;

  /// Stream of game events for external listeners.
  final _eventController = StreamController<GameEvent>.broadcast();
  Stream<GameEvent> get events => _eventController.stream;

  /// Callback to notify Flutter overlay of state changes.
  void Function(GameState state)? onStateChanged;
  void Function(bool passed)? onDemoFinished;

  int get score => scoreDisplay.score;

  @override
  Color backgroundColor() => const Color(0x00000000); // transparent

  @override
  Future<void> onLoad() async {
    sky = SkyBackground();
    add(sky);

    ground = GroundComponent(scrollSpeed: _scrollSpeed);
    add(ground);

    scoreDisplay = ScoreDisplay();
    add(scoreDisplay);

    crane = CraneSpriteComponent()..anchor = Anchor.center;
    add(crane);

    pipeSpawner = PipeSpawner(
      scrollSpeed: _scrollSpeed,
      gapHeight: _pipeGap,
    )..onScored = () {
        if (!pipeSpawner.scoringEnabled) return;
        scoreDisplay.increment();
        _eventController.add(GameEvent.scored);
        if (_isDemoRound && scoreDisplay.score >= 1) {
          if (!_demoCollisionSinceLastClear) {
            _finishDemoRound(true);
            return;
          }

          // Require one clean pipe clear after any collision during demo.
          _demoCollisionSinceLastClear = false;
        }
      };
    add(pipeSpawner);

    _resetPositions();
  }

  void _resetPositions() {
    crane.position = Vector2(size.x * 0.25, size.y * 0.4);
    _velocityY = 0;
    _targetBirdY = size.y * 0.4;
    _filteredPoseHeight = 0.5;
    _hasCollided = false;
    _demoCollisionSinceLastClear = false;
    _demoCollisionCooldown = 0.0;
    _collisionFxTime = 0.0;
    _collisionBaseX = crane.x;
    pipeSpawner.active = false;
    pipeSpawner.scoringEnabled = false;
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (state != GameState.playing) return;

    if (_demoCollisionCooldown > 0) {
      _demoCollisionCooldown = math.max(0.0, _demoCollisionCooldown - dt);
    }

    if (_hasCollided) {
      if (_isDemoRound) {
        _resetDemoAttempt();
        return;
      }
      if (_collisionFxTime > 0) {
        _collisionFxTime = math.max(0.0, _collisionFxTime - dt);
        final elapsed = _collisionFxDuration - _collisionFxTime;
        final shake = math.sin(elapsed * 72.0) * 3.6;
        crane.x = _collisionBaseX + shake;
      } else {
        crane.x += (_collisionBaseX - crane.x) * 0.2;
      }
      crane.angle += (1.08 - crane.angle) * 0.18;

      _velocityY += (_gravity * 1.12) * dt;
      crane.y += _velocityY * dt;
      if (crane.y > ground.topY - 16) {
        crane.y = ground.topY - 16;
        _die();
      }
      return;
    }

    _velocityY += _gravity * dt;
    var assistedTargetY = _targetBirdY;
    final assistTarget = pipeSpawner.nextAssistTarget(crane.x);
    if (assistTarget != null) {
      final closeness = (1.0 - (assistTarget.distanceX / _pipeAssistWindow)).clamp(0.0, 1.0);
      final assistFactor = _pipeAssistStrength * closeness;
      assistedTargetY += (assistTarget.gapCenterY - assistedTargetY) * assistFactor;
    }

    final targetDelta = assistedTargetY - crane.y;
    final reversingDirection = (targetDelta < -5 && _velocityY > 24) ||
        (targetDelta > 5 && _velocityY < -24);
    if (reversingDirection) {
      _velocityY *= _directionSwapDamping;
    }

    final liftAcceleration = (targetDelta * _poseResponse).clamp(-_maxLiftAcceleration, _maxLiftAcceleration);
    _velocityY += liftAcceleration * dt;

    if (_isDemoRound) {
      final floorY = ground.topY - _demoFloorRecoveryBand;
      if (crane.y > floorY) {
        final depth = ((crane.y - floorY) / 42.0).clamp(0.0, 1.0);
        _velocityY -= 320.0 * depth * dt;
      }
    }

    _velocityY *= math.pow(_airDrag, dt * 60).toDouble();
    if (_velocityY > _maxFallSpeed) _velocityY = _maxFallSpeed;
    if (_velocityY < -_maxFallSpeed) _velocityY = -_maxFallSpeed;
    crane.y += _velocityY * dt;

    pipeSpawner.craneX = crane.x;

    if (crane.y < 32) {
      crane.y = 32;
      _velocityY = 0;
    }

    if (crane.y > ground.topY - 16) {
      crane.y = ground.topY - 16;
      _die();
      return;
    }

    if (_checkPipeCollisions()) {
      if (_isDemoRound) {
        // Keep demo continuous, but invalidate this clearance attempt.
        _demoCollisionSinceLastClear = true;
        if (_demoCollisionCooldown <= 0) {
          _velocityY = -115;
          crane.y = math.max(44, crane.y - 6);
          crane.angle = math.max(-0.45, crane.angle - 0.25);
          crane.setAnimState(CraneAnimState.flap);
          _demoCollisionCooldown = 0.28;
        }
        return;
      }

      _hasCollided = true;
      pipeSpawner.scoringEnabled = false;
      _collisionFxTime = _collisionFxDuration;
      _collisionBaseX = crane.x;
      _velocityY = _collisionDropImpulse;
      crane.y = math.min(ground.topY - 20, crane.y + _collisionDropNudge);
      crane.angle = 0.88;
      crane.setAnimState(CraneAnimState.glide);
      return;
    }

    if (targetDelta < -6 && crane.animState != CraneAnimState.flap) {
      crane.setAnimState(CraneAnimState.flap);
    } else if (_velocityY > 0 && crane.animState != CraneAnimState.idle) {
      crane.setAnimState(CraneAnimState.idle);
    }

    crane.angle += (((_velocityY / _maxFallSpeed) * 0.42) - crane.angle) * 0.14;
  }

  bool _checkPipeCollisions() {
    final craneRect = Rect.fromCenter(
      center: Offset(crane.x, crane.y),
      width: _birdWidth,
      height: _birdHeight,
    );

    for (final child in children) {
      if (child is PipePair) {
        final topRect = Rect.fromLTWH(child.x, 0, child.pipeWidth, child.gapY);
        final bottomRect = Rect.fromLTWH(
          child.x,
          child.gapY + child.gapHeight,
          child.pipeWidth,
          size.y - (child.gapY + child.gapHeight),
        );
        if (isBirdCollidingWithPipe(craneRect, topRect, bottomRect)) {
          return true;
        }
      }
    }
    return false;
  }

  void startPlaying() {
    _isDemoRound = false;
    pipeSpawner.autoSpawn = true;
    state = GameState.playing;
    pipeSpawner.active = true;
    pipeSpawner.scoringEnabled = true;
    _targetBirdY = crane.y;
    _filteredPoseHeight = 0.5;
    _velocityY = _flapImpulse * 0.6;
    onStateChanged?.call(state);
  }

  void startDemoRound() {
    restart();
    _isDemoRound = true;
    pipeSpawner.autoSpawn = true;
    pipeSpawner.active = true;
    pipeSpawner.scoringEnabled = true;
    _demoCollisionSinceLastClear = false;
    _demoCollisionCooldown = 0.0;
    state = GameState.playing;
    _targetBirdY = crane.y;
    _filteredPoseHeight = 0.5;
    _velocityY = _flapImpulse * 0.55;
    // Spawn one immediate pipe, then keep spacing from regular spawner.
    pipeSpawner.spawnOnePipe();
    onStateChanged?.call(state);
  }

  void setPoseVerticalInput(double normalizedHeight) {
    if (state != GameState.playing) return;

    final clampedHeight = normalizedHeight.clamp(0.0, 1.0);
    _filteredPoseHeight += (clampedHeight - _filteredPoseHeight) * 0.5;
    final minY = 48.0;
    final maxY = ground.topY - 56;
    final travel = maxY - minY;
    _targetBirdY = maxY - (_filteredPoseHeight * travel);
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

  // --- Exercise-only inputs (no tap) ---

  void onNormalRep() {
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
    if (state != GameState.playing) return;
    _velocityY = _boostImpulse;
    crane.setAnimState(CraneAnimState.boost);
    _eventController.add(GameEvent.boost);
  }

  void _die() {
    if (_isDemoRound) {
      _resetDemoAttempt();
      return;
    }
    if (state == GameState.gameOver) return;
    state = GameState.gameOver;
    pipeSpawner.scoringEnabled = false;
    _eventController.add(GameEvent.died);
    onStateChanged?.call(state);
  }

  void _finishDemoRound(bool passed) {
    _isDemoRound = false;
    restart();
    onDemoFinished?.call(passed);
  }

  void _resetDemoAttempt() {
    _hasCollided = false;
    _velocityY = 0;
    _targetBirdY = size.y * 0.4;
    crane.y = size.y * 0.4;
    crane.x = size.x * 0.25;
    _collisionBaseX = crane.x;
    _collisionFxTime = 0;
    crane.angle = 0;
    crane.setAnimState(CraneAnimState.idle);
  }

  @override
  void onRemove() {
    _eventController.close();
    super.onRemove();
  }
}

bool isBirdCollidingWithPipe(Rect birdRect, Rect topPipeRect, Rect bottomPipeRect) {
  final birdBounds = birdRect.inflate(1.5);
  final topHitRect = Rect.fromLTWH(
    topPipeRect.left - 1,
    topPipeRect.top - 3,
    topPipeRect.width + 2,
    topPipeRect.height + 5,
  );
  final bottomHitRect = Rect.fromLTWH(
    bottomPipeRect.left - 1,
    bottomPipeRect.top - 3,
    bottomPipeRect.width + 2,
    bottomPipeRect.height + 5,
  );
  return birdBounds.overlaps(topHitRect) || birdBounds.overlaps(bottomHitRect);
}

enum GameEvent { flap, glide, boost, scored, died }
