import 'dart:math';
import 'dart:ui' as ui;

import 'package:flame/components.dart';

/// A single pipe column (top + bottom rectangles with a gap).
class PipePair extends PositionComponent with HasGameRef {
  final double gapY;
  final double gapHeight;
  final double pipeWidth;
  bool scored = false;

  static final _pipePaint = ui.Paint()..color = const ui.Color(0xFF245684);
  static final _pipeCapPaint = ui.Paint()..color = const ui.Color(0xFF2B4564);
  static const double _capHeight = 12;
  static const double _capOverhang = 4;

  PipePair({
    required this.gapY,
    required this.gapHeight,
    this.pipeWidth = 52,
  });

  @override
  Future<void> onLoad() async {
    // No hitbox components — collision is checked manually in game update
  }

  @override
  void render(ui.Canvas canvas) {
    final gameHeight = gameRef.size.y;

    // Top pipe body
    final topHeight = gapY;
    if (topHeight > 0) {
      canvas.drawRect(
        ui.Rect.fromLTWH(0, 0, pipeWidth, topHeight),
        _pipePaint,
      );
      // Cap at bottom of top pipe
      canvas.drawRect(
        ui.Rect.fromLTWH(
          -_capOverhang,
          topHeight - _capHeight,
          pipeWidth + _capOverhang * 2,
          _capHeight,
        ),
        _pipeCapPaint,
      );
    }

    // Bottom pipe body
    final bottomTop = gapY + gapHeight;
    final bottomHeight = gameHeight - bottomTop;
    if (bottomHeight > 0) {
      canvas.drawRect(
        ui.Rect.fromLTWH(0, bottomTop, pipeWidth, bottomHeight),
        _pipePaint,
      );
      // Cap at top of bottom pipe
      canvas.drawRect(
        ui.Rect.fromLTWH(
          -_capOverhang,
          bottomTop,
          pipeWidth + _capOverhang * 2,
          _capHeight,
        ),
        _pipeCapPaint,
      );
    }
  }
}

/// Spawns and recycles [PipePair]s as they scroll left.
class PipeSpawner extends Component with HasGameRef {
  final double scrollSpeed;
  final double gapHeight;
  final double spawnInterval;
  final Random _rng = Random();

  double _timeSinceSpawn = 0;
  final List<PipePair> _pipes = [];
  bool scoringEnabled = false;
  bool active = false;
  bool autoSpawn = true;

  PipeSpawner({
    this.scrollSpeed = 120,
    this.gapHeight = 160,
    this.spawnInterval = 3.05,
  });

  /// Callback when crane passes a pipe — game increments score.
  void Function()? onScored;

  /// The x-position of the crane (for scoring checks).
  double craneX = 0;

  PipeAssistTarget? nextAssistTarget(double birdX) {
    PipePair? nearest;
    var bestDistance = double.infinity;

    for (final pipe in _pipes) {
      final distance = pipe.x - birdX;
      if (distance < -pipe.pipeWidth) continue;
      if (distance < bestDistance) {
        bestDistance = distance;
        nearest = pipe;
      }
    }

    if (nearest == null) return null;
    return PipeAssistTarget(
      gapCenterY: nearest.gapY + nearest.gapHeight / 2,
      distanceX: bestDistance,
    );
  }

  @override
  void update(double dt) {
    super.update(dt);

    if (autoSpawn) {
      _timeSinceSpawn += dt;
      if (_timeSinceSpawn >= spawnInterval) {
        _timeSinceSpawn = 0;
        _spawnPipe();
      }
    }

    // Move pipes and check for scoring / removal
    for (final pipe in _pipes.toList()) {
      pipe.x -= scrollSpeed * dt;

      // Score only once the round is active and the bird has passed the pipe.
      if (active && scoringEnabled && !pipe.scored && pipe.x + pipe.pipeWidth < craneX - 6) {
        pipe.scored = true;
        onScored?.call();
      }

      // Remove off-screen pipes
      if (pipe.x < -pipe.pipeWidth - 10) {
        pipe.removeFromParent();
        _pipes.remove(pipe);
      }
    }
  }

  void _spawnPipe() {
    final gameHeight = gameRef.size.y;
    final minGapY = 84.0;
    final maxGapY = gameHeight - gapHeight - 92;
    if (maxGapY <= minGapY) return;

    final raw = _rng.nextDouble();
    // Slight center bias trims unreachable extremes while keeping variety.
    final centered = 0.5 + ((raw - 0.5) * 0.60);
    final gapY = minGapY + centered * (maxGapY - minGapY);
    final pipe = PipePair(gapY: gapY, gapHeight: gapHeight)
      ..position = Vector2(gameRef.size.x + 10, 0);

    _pipes.add(pipe);
    gameRef.add(pipe);
  }

  void spawnOnePipe() {
    _spawnPipe();
  }

  void reset() {
    for (final pipe in _pipes) {
      pipe.removeFromParent();
    }
    _pipes.clear();
    _timeSinceSpawn = 0;
    active = false;
    scoringEnabled = false;
    autoSpawn = true;
  }
}

class PipeAssistTarget {
  final double gapCenterY;
  final double distanceX;

  const PipeAssistTarget({required this.gapCenterY, required this.distanceX});
}
