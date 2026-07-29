import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';

class AevumCraneComponent extends CircleComponent {
  AevumCraneComponent()
      : super(
          radius: 16,
          paint: Paint()..color = const Color(0xFFFFB300),
        );

  void flap() {
    // TODO: Replace with sprite animation and physics impulse.
    y -= 18;
  }

  void glideHold() {
    // TODO: Adjust gravity scale during hold prompts.
    y -= 4;
  }

  void burstBoost() {
    y -= 28;
  }
}

class AevumFlappyGame extends FlameGame {
  late final AevumCraneComponent crane;

  @override
  Future<void> onLoad() async {
    crane = AevumCraneComponent()
      ..position = Vector2(size.x * 0.25, size.y * 0.5);
    add(crane);
  }

  void onNormalRep() => crane.flap();
  void onHoldEvent() => crane.glideHold();
  void onDoubleFast() => crane.burstBoost();
}
