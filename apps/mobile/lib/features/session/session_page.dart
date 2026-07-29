import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flame/game.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../camera/camera_service.dart';
import '../../exercise/exercise_types.dart';
import '../../exercise/pushup_detector.dart';
import '../../exercise/squat_detector.dart';
import '../../game/aevum_flappy_game.dart';
import '../../game/exercise_game_bridge.dart';
import '../../pose/pose_engine_factory.dart';
import '../../pose/pose_pipeline.dart';
import '../../theme/aevum_colors.dart';

class SessionPage extends StatefulWidget {
  static const routeName = '/session';
  const SessionPage({super.key});

  @override
  State<SessionPage> createState() => _SessionPageState();
}

class _SessionPageState extends State<SessionPage> {
  final _cameraService = CameraService();
  final _pushupDetector = PushupDetector();
  final _squatDetector = SquatDetector();
  late final AevumFlappyGame _game;
  late final ExerciseGameBridge _bridge;
  late final PosePipeline _pipeline;
  StreamSubscription<ExerciseEvent>? _eventSub;
  StreamSubscription<GameEvent>? _gameSub;

  bool _loading = true;
  bool _cameraReady = false;
  bool _pipelineActive = false;
  String _mode = 'pushup';
  String? _cameraError;
  int _repCount = 0;
  GameState _gameState = GameState.ready;

  @override
  void initState() {
    super.initState();
    _game = AevumFlappyGame()
      ..onStateChanged = (s) {
        if (mounted) setState(() => _gameState = s);
      };
    _bridge = ExerciseGameBridge(_game);
    _pipeline = PosePipeline(
      poseEngine: createPoseEngine(),
      detector: _pushupDetector,
    );
    _init();
  }

  Future<void> _init() async {
    // Camera init — tolerate failure gracefully
    try {
      await _cameraService.initialize();
      _cameraReady = _cameraService.controller?.value.isInitialized == true;
    } catch (e) {
      _cameraError = 'Camera unavailable: $e';
      _cameraReady = false;
    }

    // Pose engine init — non-fatal
    try {
      await _pipeline.initialize();
      _pipelineActive = true;
    } catch (e) {
      debugPrint('Pose engine init failed (non-fatal): $e');
      _pipelineActive = false;
    }

    // Subscribe exercise events → game bridge
    _eventSub = _pipeline.events.listen((event) {
      _bridge.onEvent(event);
      if (event is RepCompletedEvent && mounted) {
        setState(() => _repCount++);
      }
    });

    // Listen to game events for score updates
    _gameSub = _game.events.listen((event) {
      if (event == GameEvent.scored && mounted) {
        setState(() {});
      }
    });

    // Camera frame streaming (mobile only — web reads video element directly)
    if (_cameraReady && !kIsWeb) {
      _startCameraFrameStream();
    }

    if (mounted) setState(() => _loading = false);
  }

  void _startCameraFrameStream() {
    final controller = _cameraService.controller;
    if (controller == null) return;
    try {
      controller.startImageStream((CameraImage image) {
        final bytes = image.planes[0].bytes;
        _pipeline.processFrame(bytes, image.width, image.height);
      });
    } catch (e) {
      debugPrint('startImageStream not supported: $e');
    }
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    _gameSub?.cancel();
    _pipeline.dispose();
    _cameraService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Game fills the whole screen
          GameWidget(game: _game),

          // Ready overlay
          if (_gameState == GameState.ready) _ReadyOverlay(game: _game),

          // Game-over overlay
          if (_gameState == GameState.gameOver)
            _GameOverOverlay(
              score: _game.score,
              repCount: _repCount,
              onRestart: () {
                _game.restart();
                _bridge.reset();
                _pushupDetector.reset();
                _squatDetector.reset();
                setState(() {
                  _repCount = 0;
                  _gameState = GameState.ready;
                });
              },
            ),

          // HUD — top bar
          if (_gameState == GameState.playing)
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    _HudChip(
                      icon: Icons.fitness_center,
                      label: '$_repCount reps',
                    ),
                    const Spacer(),
                    _HudChip(
                      icon: _pipelineActive ? Icons.visibility : Icons.visibility_off,
                      label: _pipelineActive ? 'TRACKING' : 'MANUAL',
                      color: _pipelineActive ? AevumColors.success : AevumColors.warning,
                    ),
                  ],
                ),
              ),
            ),

          // Bottom controls — mode selector + manual buttons
          if (_gameState == GameState.playing)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SafeArea(
                child: Container(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withAlpha(120),
                      ],
                    ),
                  ),
                  child: Row(
                    children: [
                      // Mode toggle
                      _ModeToggle(
                        mode: _mode,
                        onChanged: (m) {
                          setState(() {
                            _mode = m;
                            _repCount = 0;
                          });
                          _bridge.reset();
                          if (_mode == 'pushup') {
                            _pushupDetector.reset();
                            _pipeline.setDetector(_pushupDetector);
                          } else {
                            _squatDetector.reset();
                            _pipeline.setDetector(_squatDetector);
                          }
                        },
                      ),
                      const Spacer(),
                      // Manual flap/boost for testing
                      _ActionButton(
                        label: 'FLAP',
                        onTap: () => _game.onNormalRep(),
                        color: AevumColors.primary,
                      ),
                      const SizedBox(width: 8),
                      _ActionButton(
                        label: 'BOOST',
                        onTap: () => _game.onDoubleFast(),
                        color: AevumColors.accent,
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------- Overlay widgets ----------

class _ReadyOverlay extends StatelessWidget {
  final AevumFlappyGame game;
  const _ReadyOverlay({required this.game});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black38,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.touch_app, size: 64, color: Colors.white70),
            const SizedBox(height: 16),
            Text(
              'TAP TO START',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Tap screen or do a push-up to flap',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: Colors.white70),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => game.startPlaying(),
              icon: const Icon(Icons.play_arrow),
              label: const Text('START'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AevumColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GameOverOverlay extends StatelessWidget {
  final int score;
  final int repCount;
  final VoidCallback onRestart;

  const _GameOverOverlay({
    required this.score,
    required this.repCount,
    required this.onRestart,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black54,
      child: Center(
        child: Card(
          elevation: 12,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'GAME OVER',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: AevumColors.error,
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _ScoreStat(label: 'SCORE', value: '$score'),
                    const SizedBox(width: 32),
                    _ScoreStat(label: 'REPS', value: '$repCount'),
                  ],
                ),
                const SizedBox(height: 28),
                ElevatedButton.icon(
                  onPressed: onRestart,
                  icon: const Icon(Icons.refresh),
                  label: const Text('PLAY AGAIN'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AevumColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 14,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ScoreStat extends StatelessWidget {
  final String label;
  final String value;
  const _ScoreStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value,
            style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold)),
        Text(label,
            style: const TextStyle(
                fontSize: 12,
                color: AevumColors.textSecondary,
                letterSpacing: 1)),
      ],
    );
  }
}

class _HudChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _HudChip({
    required this.icon,
    required this.label,
    this.color = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black38,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(color: color, fontSize: 12)),
        ],
      ),
    );
  }
}

class _ModeToggle extends StatelessWidget {
  final String mode;
  final ValueChanged<String> onChanged;
  const _ModeToggle({required this.mode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black38,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _toggleBtn('pushup', 'Push-up', mode == 'pushup'),
          _toggleBtn('squat', 'Squat', mode == 'squat'),
        ],
      ),
    );
  }

  Widget _toggleBtn(String value, String label, bool active) {
    return GestureDetector(
      onTap: () => onChanged(value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: active ? AevumColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? Colors.white : Colors.white70,
            fontSize: 12,
            fontWeight: active ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final Color color;
  const _ActionButton({
    required this.label,
    required this.onTap,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withAlpha(200),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }
}
