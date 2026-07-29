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
import '../../scoring/bioage_estimator.dart';
import '../../scoring/session_stats.dart';
import '../../theme/aevum_colors.dart';

// ---------- Session flow phases ----------
enum _Phase { profileInput, playing }

class SessionPage extends StatefulWidget {
  static const routeName = '/session';
  const SessionPage({super.key});

  @override
  State<SessionPage> createState() => _SessionPageState();
}

class _SessionPageState extends State<SessionPage> {
  // --- Infrastructure ---
  final _cameraService = CameraService();
  final _pushupDetector = PushupDetector();
  final _squatDetector = SquatDetector();
  late final AevumFlappyGame _game;
  late final ExerciseGameBridge _bridge;
  late final PosePipeline _pipeline;
  StreamSubscription<ExerciseEvent>? _eventSub;
  StreamSubscription<GameEvent>? _gameSub;

  // --- State ---
  _Phase _phase = _Phase.profileInput;
  bool _loading = true;
  bool _cameraReady = false;
  bool _pipelineActive = false;
  String _mode = 'pushup';
  int _repCount = 0;
  GameState _gameState = GameState.ready;

  // --- Profile & scoring ---
  UserProfile? _profile;
  late SessionStats _stats;
  BioAgeResult? _bioAgeResult;
  final _estimator = const BioAgeEstimator();

  @override
  void initState() {
    super.initState();
    _stats = SessionStats(mode: _mode);
    _game = AevumFlappyGame()
      ..onStateChanged = (s) {
        if (mounted) {
          setState(() => _gameState = s);
          if (s == GameState.gameOver) _computeBioAge();
        }
      };
    _bridge = ExerciseGameBridge(_game);
    _pipeline = PosePipeline(
      poseEngine: createPoseEngine(),
      detector: _pushupDetector,
    );
    _init();
  }

  Future<void> _init() async {
    try {
      await _cameraService.initialize();
      _cameraReady = _cameraService.controller?.value.isInitialized == true;
    } catch (e) {
      debugPrint('Camera unavailable: $e');
    }

    try {
      await _pipeline.initialize();
      _pipelineActive = true;
    } catch (e) {
      debugPrint('Pose engine init failed: $e');
    }

    _eventSub = _pipeline.events.listen((event) {
      _bridge.onEvent(event);
      _stats.onEvent(event);
      if (event is RepCompletedEvent && mounted) {
        setState(() => _repCount++);
      }
    });

    _gameSub = _game.events.listen((event) {
      if (event == GameEvent.scored && mounted) setState(() {});
    });

    if (_cameraReady && !kIsWeb) _startCameraFrameStream();
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

  void _onProfileSubmitted(UserProfile profile) {
    setState(() {
      _profile = profile;
      _phase = _Phase.playing;
    });
  }

  void _computeBioAge() {
    if (_profile == null) return;
    final features = _stats.toFeatures();
    _bioAgeResult = _estimator.estimate(features, _profile!);
  }

  void _restart() {
    _game.restart();
    _bridge.reset();
    _pushupDetector.reset();
    _squatDetector.reset();
    _stats.reset();
    setState(() {
      _repCount = 0;
      _gameState = GameState.ready;
      _bioAgeResult = null;
    });
  }

  void _switchMode(String newMode) {
    setState(() {
      _mode = newMode;
      _repCount = 0;
    });
    _stats = SessionStats(mode: newMode);
    _bridge.reset();
    if (_mode == 'pushup') {
      _pushupDetector.reset();
      _pipeline.setDetector(_pushupDetector);
    } else {
      _squatDetector.reset();
      _pipeline.setDetector(_squatDetector);
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

    if (_phase == _Phase.profileInput) {
      return _ProfileInputScreen(onSubmit: _onProfileSubmitted);
    }

    final controller = _cameraService.controller;
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (_cameraReady && controller != null && controller.value.isInitialized)
            SizedBox.expand(
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: controller.value.previewSize?.height ?? 480,
                  height: controller.value.previewSize?.width ?? 640,
                  child: CameraPreview(controller),
                ),
              ),
            )
          else
            const ColoredBox(color: Colors.black),

          GameWidget(game: _game),

          if (_gameState == GameState.ready)
            _ReadyOverlay(
              pipelineActive: _pipelineActive,
              mode: _mode,
              onModeChanged: _switchMode,
            ),

          if (_gameState == GameState.gameOver)
            _GameOverOverlay(
              score: _game.score,
              repCount: _repCount,
              bioAgeResult: _bioAgeResult,
              onRestart: _restart,
            ),

          if (_gameState == GameState.playing)
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _HudChip(icon: Icons.fitness_center, label: '$_repCount reps'),
                    const Spacer(),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        _HudChip(
                          icon: _pipelineActive ? Icons.visibility : Icons.visibility_off,
                          label: _pipelineActive ? 'TRACKING' : 'NO POSE',
                          color: _pipelineActive ? AevumColors.success : AevumColors.error,
                        ),
                        const SizedBox(height: 4),
                        _ModeChip(
                          mode: _mode,
                          onTap: () => _switchMode(_mode == 'pushup' ? 'squat' : 'pushup'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------- Profile input screen ----------

class _ProfileInputScreen extends StatefulWidget {
  final ValueChanged<UserProfile> onSubmit;
  const _ProfileInputScreen({required this.onSubmit});

  @override
  State<_ProfileInputScreen> createState() => _ProfileInputScreenState();
}

class _ProfileInputScreenState extends State<_ProfileInputScreen> {
  final _ageController = TextEditingController();
  String _sex = 'male';
  String? _ageError;

  @override
  void dispose() {
    _ageController.dispose();
    super.dispose();
  }

  void _submit() {
    final age = int.tryParse(_ageController.text.trim());
    if (age == null || age < 13 || age > 100) {
      setState(() => _ageError = 'Enter age between 13 and 100');
      return;
    }
    widget.onSubmit(UserProfile(chronologicalAge: age, sex: _sex));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Aevum BioAge',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                const Text(
                  'We need your age and sex to compare your performance against '
                  'evidence-based fitness norms and estimate your biological age.',
                  style: TextStyle(color: AevumColors.textSecondary),
                ),
                const SizedBox(height: 32),
                TextField(
                  controller: _ageController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Your age',
                    hintText: 'e.g. 30',
                    errorText: _ageError,
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.cake),
                  ),
                  onChanged: (_) => setState(() => _ageError = null),
                ),
                const SizedBox(height: 20),
                const Text('Sex', style: TextStyle(fontWeight: FontWeight.w500)),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'male', label: Text('Male'), icon: Icon(Icons.male)),
                    ButtonSegment(value: 'female', label: Text('Female'), icon: Icon(Icons.female)),
                  ],
                  selected: {_sex},
                  onSelectionChanged: (s) => setState(() => _sex = s.first),
                ),
                const SizedBox(height: 32),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AevumColors.primary.withAlpha(20),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AevumColors.primary.withAlpha(60)),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Icon(Icons.science, size: 16, color: AevumColors.primary),
                        SizedBox(width: 6),
                        Text('Based on research', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                      ]),
                      SizedBox(height: 6),
                      Text(
                        'Push-up capacity is linked to cardiovascular health '
                        '(Yang et al., JAMA Network Open, 2019). Norms from '
                        'ACSM fitness assessment guidelines.',
                        style: TextStyle(fontSize: 12, color: AevumColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'This is a wellness estimate, not a medical diagnosis.',
                  style: TextStyle(fontSize: 11, color: AevumColors.textSecondary, fontStyle: FontStyle.italic),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _submit,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('START SESSION'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AevumColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
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

// ---------- Overlay widgets ----------

class _ReadyOverlay extends StatelessWidget {
  final bool pipelineActive;
  final String mode;
  final ValueChanged<String> onModeChanged;

  const _ReadyOverlay({
    required this.pipelineActive,
    required this.mode,
    required this.onModeChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black54,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              pipelineActive ? Icons.fitness_center : Icons.videocam_off,
              size: 64, color: Colors.white70,
            ),
            const SizedBox(height: 16),
            Text(
              pipelineActive ? 'READY' : 'CAMERA NEEDED',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              pipelineActive
                  ? 'Do a ${mode == 'pushup' ? 'push-up' : 'squat'} to start flying'
                  : 'Allow camera access to begin pose tracking',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white70),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            _ModeToggle(mode: mode, onChanged: onModeChanged),
            if (!pipelineActive) ...[
              const SizedBox(height: 16),
              Text('Grant camera permission and reload',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AevumColors.warning)),
            ],
          ],
        ),
      ),
    );
  }
}

class _GameOverOverlay extends StatelessWidget {
  final int score;
  final int repCount;
  final BioAgeResult? bioAgeResult;
  final VoidCallback onRestart;

  const _GameOverOverlay({
    required this.score,
    required this.repCount,
    required this.bioAgeResult,
    required this.onRestart,
  });

  @override
  Widget build(BuildContext context) {
    final result = bioAgeResult;
    return Container(
      color: Colors.black54,
      child: Center(
        child: SingleChildScrollView(
          child: Card(
            elevation: 12,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('SESSION COMPLETE',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: 1)),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _ScoreStat(label: 'SCORE', value: '$score'),
                      const SizedBox(width: 28),
                      _ScoreStat(label: 'REPS', value: '$repCount'),
                    ],
                  ),
                  if (result != null) ...[
                    const Divider(height: 32),
                    const Text('Estimated Bio Age',
                        style: TextStyle(fontSize: 13, color: AevumColors.textSecondary, letterSpacing: 0.5)),
                    const SizedBox(height: 4),
                    Text(
                      '${result.estimatedBioAge.round()}',
                      style: TextStyle(
                        fontSize: 56, fontWeight: FontWeight.bold,
                        color: result.ageDelta <= -3
                            ? AevumColors.success
                            : result.ageDelta >= 3
                                ? AevumColors.error
                                : AevumColors.primary,
                      ),
                    ),
                    Text('${result.confidenceLow.round()}–${result.confidenceHigh.round()} range',
                        style: const TextStyle(fontSize: 12, color: AevumColors.textSecondary)),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: (result.ageDelta <= -3
                                ? AevumColors.success
                                : result.ageDelta >= 3
                                    ? AevumColors.error
                                    : AevumColors.primary)
                            .withAlpha(30),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        result.ageDelta <= 0
                            ? '${result.ageDelta.abs().round()} years younger than ${result.chronologicalAge}'
                            : '${result.ageDelta.round()} years older than ${result.chronologicalAge}',
                        style: TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600,
                          color: result.ageDelta <= -3
                              ? AevumColors.success
                              : result.ageDelta >= 3
                                  ? AevumColors.error
                                  : AevumColors.primary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text('${result.percentileLabel} · ${result.reliability} confidence',
                        style: const TextStyle(fontSize: 12, color: AevumColors.textSecondary)),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.grey.withAlpha(20), borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'Based on ACSM norms & Yang et al. (JAMA, 2019). '
                        'This is a wellness estimate, not a medical diagnosis.',
                        style: TextStyle(fontSize: 10, color: AevumColors.textSecondary),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    onPressed: onRestart,
                    icon: const Icon(Icons.refresh),
                    label: const Text('PLAY AGAIN'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AevumColors.primary, foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------- Shared widgets ----------

class _ScoreStat extends StatelessWidget {
  final String label;
  final String value;
  const _ScoreStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Text(value, style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold)),
      Text(label, style: const TextStyle(fontSize: 12, color: AevumColors.textSecondary, letterSpacing: 1)),
    ]);
  }
}

class _HudChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _HudChip({required this.icon, required this.label, this.color = Colors.white});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: Colors.black38, borderRadius: BorderRadius.circular(16)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(color: color, fontSize: 12)),
      ]),
    );
  }
}

class _ModeChip extends StatelessWidget {
  final String mode;
  final VoidCallback onTap;
  const _ModeChip({required this.mode, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(color: AevumColors.primary.withAlpha(180), borderRadius: BorderRadius.circular(16)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.swap_horiz, size: 14, color: Colors.white),
          const SizedBox(width: 4),
          Text(mode == 'pushup' ? 'Push-up' : 'Squat', style: const TextStyle(color: Colors.white, fontSize: 12)),
        ]),
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
      decoration: BoxDecoration(color: Colors.black38, borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        _toggleBtn('pushup', 'Push-up', mode == 'pushup'),
        _toggleBtn('squat', 'Squat', mode == 'squat'),
      ]),
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
        child: Text(label, style: TextStyle(
          color: active ? Colors.white : Colors.white70,
          fontSize: 12, fontWeight: active ? FontWeight.bold : FontWeight.normal,
        )),
      ),
    );
  }
}
