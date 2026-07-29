import 'dart:ui' as ui;

import 'package:flame/components.dart';

/// In-game score display (top-center).
class ScoreDisplay extends PositionComponent with HasGameRef {
  int _score = 0;

  @override
  int get priority => 10;

  int get score => _score;

  void increment() => _score++;
  void reset() => _score = 0;

  @override
  void render(ui.Canvas canvas) {
    final text = _score.toString();
    final style = ui.ParagraphStyle(
      textAlign: ui.TextAlign.center,
      fontSize: 48,
      fontWeight: ui.FontWeight.bold,
    );
    final builder = ui.ParagraphBuilder(style)
      ..pushStyle(ui.TextStyle(
        color: const ui.Color(0xFFFFFFFF),
        fontSize: 48,
        fontWeight: ui.FontWeight.bold,
        shadows: const [
          ui.Shadow(
            color: ui.Color(0x88000000),
            offset: ui.Offset(2, 2),
            blurRadius: 4,
          ),
        ],
      ))
      ..addText(text);
    final paragraph = builder.build()
      ..layout(ui.ParagraphConstraints(width: gameRef.size.x));
    canvas.drawParagraph(paragraph, const ui.Offset(0, 40));
  }
}
