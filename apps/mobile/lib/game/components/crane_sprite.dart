import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flame/sprite.dart';
import 'package:flutter/material.dart';

import '../../theme/aevum_colors.dart';

/// Animation states for the Aevum crane character.
enum CraneAnimState { idle, flap, glide, boost }

/// Draws a single crane frame onto a [Canvas].
///
/// The crane is rendered programmatically so no external asset file is needed.
/// The design uses sharper, folded planes to echo the paper-heron mark used
/// throughout the Aevum website.
void _drawCraneFrame(Canvas canvas, Size size, double wingPhase, Color bodyColor) {
  final cx = size.width / 2;
  final cy = size.height / 2;

  final flutter = (wingPhase - 0.5) * 16;
  final bodyPaint = Paint()..color = bodyColor;
  final shadowPaint = Paint()..color = const Color(0xFFDCCEB6);
  final outlinePaint = Paint()
    ..color = const Color(0xFF0C1A27)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.5;
  final foldPaint = Paint()
    ..color = AevumColors.gold.withAlpha(190)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.1;

  final leftWing = ui.Path()
    ..moveTo(cx - 2, cy)
    ..lineTo(cx - 25, cy - 10 - flutter)
    ..lineTo(cx - 10, cy + 3)
    ..close();
  final rightWing = ui.Path()
    ..moveTo(cx + 1, cy - 1)
    ..lineTo(cx + 24, cy - 12 + flutter * 0.8)
    ..lineTo(cx + 9, cy + 4)
    ..close();
  canvas.drawPath(leftWing, shadowPaint);
  canvas.drawPath(rightWing, bodyPaint);
  canvas.drawPath(leftWing, outlinePaint);
  canvas.drawPath(rightWing, outlinePaint);

  final bodyPath = ui.Path()
    ..moveTo(cx - 10, cy + 4)
    ..lineTo(cx - 2, cy - 4)
    ..lineTo(cx + 12, cy + 1)
    ..lineTo(cx + 3, cy + 11)
    ..close();
  canvas.drawPath(bodyPath, bodyPaint);
  canvas.drawPath(bodyPath, outlinePaint);

  final neckPath = ui.Path()
    ..moveTo(cx + 8, cy - 2)
    ..lineTo(cx + 15, cy - 16)
    ..lineTo(cx + 19, cy - 13)
    ..lineTo(cx + 12, cy)
    ..close();
  canvas.drawPath(neckPath, bodyPaint);
  canvas.drawPath(neckPath, outlinePaint);

  final headPath = ui.Path()
    ..moveTo(cx + 16, cy - 17)
    ..lineTo(cx + 22, cy - 18)
    ..lineTo(cx + 19, cy - 12)
    ..close();
  canvas.drawPath(headPath, bodyPaint);
  canvas.drawPath(headPath, outlinePaint);

  final beakPath = ui.Path()
    ..moveTo(cx + 22, cy - 18)
    ..lineTo(cx + 31, cy - 20)
    ..lineTo(cx + 21, cy - 15)
    ..close();
  canvas.drawPath(beakPath, Paint()..color = AevumColors.gold);

  final tailPath = ui.Path()
    ..moveTo(cx - 11, cy + 5)
    ..lineTo(cx - 24, cy + 11)
    ..lineTo(cx - 12, cy)
    ..close();
  canvas.drawPath(tailPath, Paint()..color = const Color(0xFF132B44));
  canvas.drawPath(tailPath, outlinePaint);

  canvas.drawLine(Offset(cx - 1, cy - 4), Offset(cx + 9, cy + 8), foldPaint);
  canvas.drawLine(Offset(cx + 8, cy - 2), Offset(cx + 15, cy - 15), foldPaint);
  canvas.drawLine(Offset(cx - 8, cy + 3), Offset(cx - 18, cy - 4 - flutter * 0.4), foldPaint);

  final eyePaint = Paint()..color = const Color(0xFF08121D);
  canvas.drawCircle(Offset(cx + 18, cy - 16), 1.2, eyePaint);
}

/// Generates a sprite sheet image with [frameCount] animation frames.
Future<ui.Image> generateCraneSpriteSheet({
  int frameCount = 6,
  double frameSize = 64,
  Color bodyColor = AevumColors.cream,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final size = Size(frameSize, frameSize);

  for (var i = 0; i < frameCount; i++) {
    canvas.save();
    canvas.translate(i * frameSize, 0);
    final phase = i / (frameCount - 1);
    _drawCraneFrame(canvas, size, phase, bodyColor);
    canvas.restore();
  }

  final picture = recorder.endRecording();
  return picture.toImage(
    (frameSize * frameCount).toInt(),
    frameSize.toInt(),
  );
}

/// The Aevum crane character as a Flame [SpriteAnimationComponent].
///
/// Supports idle/flap/glide/boost states with different playback speeds.
class CraneSpriteComponent extends SpriteAnimationComponent with HasGameRef {
  CraneSpriteComponent() : super(size: Vector2(64, 64));

  CraneAnimState _animState = CraneAnimState.idle;
  late final SpriteSheet _sheet;
  late final SpriteAnimation _idleAnim;
  late final SpriteAnimation _flapAnim;
  late final SpriteAnimation _glideAnim;
  late final SpriteAnimation _boostAnim;

  CraneAnimState get animState => _animState;

  @override
  Future<void> onLoad() async {
    final image = await generateCraneSpriteSheet();
    _sheet = SpriteSheet(image: image, srcSize: Vector2(64, 64));

    // Build animations from the 6-frame sheet (indices 0–5) at different speeds
    _idleAnim = _buildAnimation(from: 1, to: 3, stepTime: 0.25);
    _flapAnim = _buildAnimation(from: 0, to: 5, stepTime: 0.06);
    _glideAnim = _buildAnimation(from: 2, to: 3, stepTime: 0.4);
    _boostAnim = _buildAnimation(from: 0, to: 5, stepTime: 0.04);

    animation = _idleAnim;
  }

  SpriteAnimation _buildAnimation({
    required int from,
    required int to,
    required double stepTime,
  }) {
    return _sheet.createAnimation(row: 0, stepTime: stepTime, from: from, to: to);
  }

  void setAnimState(CraneAnimState state) {
    if (_animState == state) return;
    _animState = state;
    switch (state) {
      case CraneAnimState.idle:
        animation = _idleAnim;
        break;
      case CraneAnimState.flap:
        animation = _flapAnim;
        break;
      case CraneAnimState.glide:
        animation = _glideAnim;
        break;
      case CraneAnimState.boost:
        animation = _boostAnim;
        break;
    }
  }
}
