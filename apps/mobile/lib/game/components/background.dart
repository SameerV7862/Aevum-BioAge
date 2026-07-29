import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flutter/painting.dart';

/// Scrolling ground strip at the bottom of the game world.
class GroundComponent extends PositionComponent with HasGameRef {
  static const double groundHeight = 40;
  static final _groundPaint = ui.Paint()..color = const Color(0xFF5D4037);
  static final _grassPaint = ui.Paint()..color = const Color(0xFF66BB6A);
  static const double _grassHeight = 6;

  double _scrollOffset = 0;
  final double scrollSpeed;

  GroundComponent({this.scrollSpeed = 120});

  @override
  void render(ui.Canvas canvas) {
    final w = gameRef.size.x;
    final h = gameRef.size.y;
    final top = h - groundHeight;

    // Grass strip
    canvas.drawRect(ui.Rect.fromLTWH(0, top, w, _grassHeight), _grassPaint);

    // Dirt
    canvas.drawRect(
      ui.Rect.fromLTWH(0, top + _grassHeight, w, groundHeight - _grassHeight),
      _groundPaint,
    );

    // Scrolling texture lines
    final linePaint = ui.Paint()
      ..color = const Color(0xFF4E342E)
      ..strokeWidth = 1;
    const spacing = 24.0;
    final startX = -(_scrollOffset % spacing);
    for (var x = startX; x < w; x += spacing) {
      canvas.drawLine(
        ui.Offset(x, top + _grassHeight + 2),
        ui.Offset(x + 8, top + groundHeight - 2),
        linePaint,
      );
    }
  }

  @override
  void update(double dt) {
    super.update(dt);
    _scrollOffset += scrollSpeed * dt;
  }

  void reset() {
    _scrollOffset = 0;
  }

  /// The y-coordinate of the ground top edge.
  double get topY => gameRef.size.y - groundHeight;
}

/// Sky gradient background. Drawn behind everything else.
class SkyBackground extends PositionComponent with HasGameRef {
  @override
  int get priority => -10;

  @override
  void render(ui.Canvas canvas) {
    final rect = ui.Rect.fromLTWH(0, 0, gameRef.size.x, gameRef.size.y);
    final gradient = const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        Color(0xFF87CEEB), // light sky blue
        Color(0xFFE0F0FF), // pale horizon
      ],
    );
    canvas.drawRect(rect, ui.Paint()..shader = gradient.createShader(rect));
  }
}
