enum PromptType {
  normalRep,
  hold2s,
  hold3s,
  doubleFast,
  slowRep,
}

class RhythmPrompt {
  final PromptType type;
  final Duration issuedAt;

  const RhythmPrompt({required this.type, required this.issuedAt});
}

class RhythmPromptEngine {
  int _index = 0;

  static const List<PromptType> _pattern = [
    PromptType.normalRep,
    PromptType.hold2s,
    PromptType.doubleFast,
    PromptType.normalRep,
    PromptType.slowRep,
    PromptType.hold3s,
  ];

  RhythmPrompt nextPrompt(Duration sessionElapsed) {
    final type = _pattern[_index % _pattern.length];
    _index++;
    return RhythmPrompt(type: type, issuedAt: sessionElapsed);
  }

  void reset() => _index = 0;
}
