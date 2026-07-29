import 'dart:math';
import 'dart:ui' as ui;

import 'package:flame/components.dart';

/// A single pipe column (top + bottom rectangles with a gap).
class PipePair extends PositionComponent with HasGameRef {
  final double gapY;
  final double gapHeight;
  final double pipeWidth;
  bool scored = false;

  static final _pipePaint = ui.Paint()..color = const ui.Color(0xFF388E3C);
  static final _pipeCapPaint = ui.Paint()..color = const ui.Color(0xFF2E7D32);
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

  PipeSpawner({
    this.scrollSpeed = 120,
    this.gapHeight = 160,
    this.spawnInterval = 2.2,
  });

  /// Callback when crane passes a pipe — game increments score.
  void Function()? onScored;

  /// The x-position of the crane (for scoring checks).
  double craneX = 0;

  @override
  void update(double dt) {
    super.update(dt);

    _timeSinceSpawn += dt;
    if (_timeSinceSpawn >= spawnInterval) {
      _timeSinceSpawn = 0;
      _spawnPipe();
    }

    // Move pipes and check for scoring / removal
    for (final pipe in _pipes.toList()) {
      pipe.x -= scrollSpeed * dt;

      // Score when crane passes the right edge of a pipe
      if (!pipe.scored && pipe.x + pipe.pipeWidth < craneX) {
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
    final minGapY = 60.0;
    final maxGapY = gameHeight - gapHeight - 60;
    if (maxGapY <= minGapY) return;

    final gapY = minGapY + _rng.nextDouble() * (maxGapY - minGapY);
    final pipe = PipePair(gapY: gapY, gapHeight: gapHeight)
      ..position = Vector2(gameRef.size.x + 10, 0);

    _pipes.add(pipe);
    gameRef.add(pipe);
  }

  void reset() {
    for (final pipe in _pipes) {
      pipe.removeFromParent();
    }
    _pipes.clear();
    _timeSinceSpawn = 0;
  }
}
