import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flutter/painting.dart';

import '../../theme/aevum_colors.dart';

/// Scrolling ground strip at the bottom of the game world.
class GroundComponent extends PositionComponent with HasGameRef {
  static const double groundHeight = 40;
  static final _groundPaint = ui.Paint()..color = AevumColors.surfaceDim;
  static final _grassPaint = ui.Paint()..color = AevumColors.primaryDark;
  static const double _grassHeight = 6;

  double _scrollOffset = 0;
  final double scrollSpeed;

  GroundComponent({this.scrollSpeed = 120});

  @override
  void render(ui.Canvas canvas) {
    final w = gameRef.size.x;
    final h = gameRef.size.y;
    final top = h - groundHeight;

    final highlightRect = ui.Rect.fromLTWH(0, top - 8, w, 18);
    canvas.drawRect(
      highlightRect,
      ui.Paint()
        ..shader = const LinearGradient(
          colors: [
            Color(0x00E4B860),
            Color(0x66E4B860),
            Color(0x00E4B860),
          ],
        ).createShader(highlightRect),
    );

    // Grass strip
    canvas.drawRect(ui.Rect.fromLTWH(0, top, w, _grassHeight), _grassPaint);

    // Dirt
    canvas.drawRect(
      ui.Rect.fromLTWH(0, top + _grassHeight, w, groundHeight - _grassHeight),
      _groundPaint,
    );

    // Scrolling texture lines
    final linePaint = ui.Paint()
      ..color = const Color(0xFF1C3654)
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

    final goldLine = ui.Paint()
      ..color = AevumColors.gold.withAlpha(110)
      ..strokeWidth = 1.2;
    canvas.drawLine(
      ui.Offset(0, top + 1),
      ui.Offset(w, top + 1),
      goldLine,
    );
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
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Color(0xFF08121D),
        Color(0xFF10253A),
        Color(0xFF1A3C5A),
      ],
    );
    canvas.drawRect(rect, ui.Paint()..shader = gradient.createShader(rect));

    final glowPaint = ui.Paint()
      ..shader = ui.Gradient.radial(
        ui.Offset(gameRef.size.x * 0.78, gameRef.size.y * 0.18),
        gameRef.size.x * 0.45,
        [
          AevumColors.primary.withAlpha(70),
          AevumColors.primary.withAlpha(0),
        ],
      );
    canvas.drawRect(rect, glowPaint);

    final warmPaint = ui.Paint()
      ..shader = ui.Gradient.radial(
        ui.Offset(gameRef.size.x * 0.2, gameRef.size.y * 0.74),
        gameRef.size.x * 0.4,
        [
          AevumColors.gold.withAlpha(45),
          AevumColors.gold.withAlpha(0),
        ],
      );
    canvas.drawRect(rect, warmPaint);

    final gridPaint = ui.Paint()
      ..color = AevumColors.secondary.withAlpha(20)
      ..strokeWidth = 1;
    const gridSpacing = 36.0;
    for (var x = 0.0; x <= gameRef.size.x; x += gridSpacing) {
      canvas.drawLine(ui.Offset(x, 0), ui.Offset(x, gameRef.size.y), gridPaint);
    }
    for (var y = 0.0; y <= gameRef.size.y; y += gridSpacing) {
      canvas.drawLine(ui.Offset(0, y), ui.Offset(gameRef.size.x, y), gridPaint);
    }

    final horizonPaint = ui.Paint()
      ..color = AevumColors.cream.withAlpha(18)
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final horizonPath = ui.Path()
      ..moveTo(0, gameRef.size.y * 0.62)
      ..quadraticBezierTo(
        gameRef.size.x * 0.28,
        gameRef.size.y * 0.55,
        gameRef.size.x * 0.52,
        gameRef.size.y * 0.61,
      )
      ..quadraticBezierTo(
        gameRef.size.x * 0.74,
        gameRef.size.y * 0.66,
        gameRef.size.x,
        gameRef.size.y * 0.58,
      );
    canvas.drawPath(horizonPath, horizonPaint);

    final orbitPaint = ui.Paint()
      ..color = AevumColors.cream.withAlpha(24)
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawOval(
      ui.Rect.fromCenter(
        center: ui.Offset(gameRef.size.x * 0.77, gameRef.size.y * 0.2),
        width: gameRef.size.x * 0.28,
        height: gameRef.size.y * 0.16,
      ),
      orbitPaint,
    );
    canvas.drawOval(
      ui.Rect.fromCenter(
        center: ui.Offset(gameRef.size.x * 0.24, gameRef.size.y * 0.28),
        width: gameRef.size.x * 0.18,
        height: gameRef.size.y * 0.1,
      ),
      orbitPaint,
    );

    final markPaint = ui.Paint()
      ..color = AevumColors.cream.withAlpha(28)
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = 2;
    final markPath = ui.Path()
      ..moveTo(gameRef.size.x * 0.12, gameRef.size.y * 0.18)
      ..lineTo(gameRef.size.x * 0.18, gameRef.size.y * 0.23)
      ..lineTo(gameRef.size.x * 0.24, gameRef.size.y * 0.16);
    canvas.drawPath(markPath, markPaint);
  }
}
