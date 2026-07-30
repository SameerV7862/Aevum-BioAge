import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/game/aevum_flappy_game.dart';

void main() {
  test('detects collision when the bird overlaps a pipe body', () {
    final birdRect = const Rect.fromLTWH(100, 100, 44, 40);
    final topPipeRect = const Rect.fromLTWH(90, 90, 60, 90);
    final bottomPipeRect = const Rect.fromLTWH(90, 220, 60, 200);

    expect(isBirdCollidingWithPipe(birdRect, topPipeRect, bottomPipeRect), isTrue);
  });

  test('does not report collision when the bird is clear of the pipe hitboxes', () {
    final birdRect = const Rect.fromLTWH(100, 100, 44, 40);
    final topPipeRect = const Rect.fromLTWH(900, 0, 60, 90);
    final bottomPipeRect = const Rect.fromLTWH(900, 220, 60, 200);

    expect(isBirdCollidingWithPipe(birdRect, topPipeRect, bottomPipeRect), isFalse);
  });
}
