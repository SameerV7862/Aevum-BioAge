import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flame/sprite.dart';
import 'package:flutter/material.dart';

/// Animation states for the Aevum crane character.
enum CraneAnimState { idle, flap, glide, boost }

/// Draws a single crane frame onto a [Canvas].
///
/// The crane is rendered programmatically so no external asset file is needed.
/// Each frame is 64×64 pixels. [wingPhase] (0.0–1.0) controls wing angle.
void _drawCraneFrame(Canvas canvas, Size size, double wingPhase, Color bodyColor) {
  final cx = size.width / 2;
  final cy = size.height / 2;

  // Body – elongated ellipse
  final bodyPaint = Paint()..color = bodyColor;
  canvas.drawOval(
    Rect.fromCenter(center: Offset(cx, cy), width: 36, height: 16),
    bodyPaint,
  );

  // Head
  canvas.drawCircle(Offset(cx + 18, cy - 4), 7, bodyPaint);

  // Eye
  final eyePaint = Paint()..color = const Color(0xFF1A1A1A);
  canvas.drawCircle(Offset(cx + 20, cy - 6), 2, eyePaint);

  // Beak
  final beakPaint = Paint()..color = const Color(0xFFFF6D00);
  final beakPath = ui.Path()
    ..moveTo(cx + 25, cy - 4)
    ..lineTo(cx + 34, cy - 3)
    ..lineTo(cx + 25, cy - 1)
    ..close();
  canvas.drawPath(beakPath, beakPaint);

  // Wing – rotates based on wingPhase
  final wingPaint = Paint()..color = bodyColor.withAlpha(200);
  final wingAngle = -0.5 + wingPhase * 1.0; // radians range
  canvas.save();
  canvas.translate(cx - 2, cy);
  canvas.rotate(wingAngle);
  canvas.drawOval(
    Rect.fromCenter(center: const Offset(0, -8), width: 22, height: 8),
    wingPaint,
  );
  canvas.restore();

  // Tail feathers
  final tailPaint = Paint()
    ..color = bodyColor.withAlpha(180)
    ..strokeWidth = 2
    ..style = PaintingStyle.stroke;
  canvas.drawLine(Offset(cx - 18, cy), Offset(cx - 26, cy - 4), tailPaint);
  canvas.drawLine(Offset(cx - 18, cy), Offset(cx - 28, cy), tailPaint);
  canvas.drawLine(Offset(cx - 18, cy), Offset(cx - 26, cy + 4), tailPaint);

  // Legs (tucked in flight – short stubs)
  final legPaint = Paint()
    ..color = const Color(0xFF5D4037)
    ..strokeWidth = 1.5;
  canvas.drawLine(Offset(cx - 4, cy + 8), Offset(cx - 6, cy + 14), legPaint);
  canvas.drawLine(Offset(cx + 4, cy + 8), Offset(cx + 2, cy + 14), legPaint);

  // Red crown mark (Aevum crane identity)
  final crownPaint = Paint()..color = const Color(0xFFD32F2F);
  canvas.drawCircle(Offset(cx + 18, cy - 10), 3, crownPaint);
}

/// Generates a sprite sheet image with [frameCount] animation frames.
Future<ui.Image> generateCraneSpriteSheet({
  int frameCount = 6,
  double frameSize = 64,
  Color bodyColor = const Color(0xFFF5F5F5), // off-white crane
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
  late final SpriteAnimation _idleAnim;
  late final SpriteAnimation _flapAnim;
  late final SpriteAnimation _glideAnim;
  late final SpriteAnimation _boostAnim;

  CraneAnimState get animState => _animState;

  @override
  Future<void> onLoad() async {
    final image = await generateCraneSpriteSheet();
    final sheet = SpriteSheet(image: image, srcSize: Vector2(64, 64));

    // Build animations from the 6-frame sheet at different speeds
    _idleAnim = sheet.createAnimation(row: 0, stepTime: 0.25, from: 1, to: 4);
    _flapAnim = sheet.createAnimation(row: 0, stepTime: 0.06, from: 0, to: 6);
    _glideAnim = sheet.createAnimation(row: 0, stepTime: 0.4, from: 2, to: 4);
    _boostAnim = sheet.createAnimation(row: 0, stepTime: 0.04, from: 0, to: 6);

    animation = _idleAnim;
  }

  void setAnimState(CraneAnimState state) {
    if (_animState == state) return;
    _animState = state;
    switch (state) {
      case CraneAnimState.idle:
        animation = _idleAnim;
      case CraneAnimState.flap:
        animation = _flapAnim;
      case CraneAnimState.glide:
        animation = _glideAnim;
      case CraneAnimState.boost:
        animation = _boostAnim;
    }
    animation?.reset();
  }
}
