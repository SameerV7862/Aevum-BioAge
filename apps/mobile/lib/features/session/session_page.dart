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
  final _game = AevumFlappyGame();
  late final ExerciseGameBridge _bridge;
  late final PosePipeline _pipeline;
  StreamSubscription<ExerciseEvent>? _eventSub;

  bool _loading = true;
  bool _cameraReady = false;
  bool _pipelineActive = false;
  String _mode = 'pushup';
  String? _cameraError;
  int _repCount = 0;

  @override
  void initState() {
    super.initState();
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
      _cameraError = 'Camera unavailable: $e';
      _cameraReady = false;
    }

    try {
      await _pipeline.initialize();
    } catch (e) {
      debugPrint('Pose engine init failed: $e');
    }

    // Subscribe exercise events → game bridge
    _eventSub = _pipeline.events.listen((event) {
      _bridge.onEvent(event);
      if (event is RepCompletedEvent) {
        setState(() => _repCount++);
      }
    });

    // Start camera frame streaming (non-web uses image stream)
    if (_cameraReady && !kIsWeb) {
      _startCameraFrameStream();
    }

    if (mounted) {
      setState(() {
        _loading = false;
        _pipelineActive = true;
      });
    }
  }

  void _startCameraFrameStream() {
    final controller = _cameraService.controller;
    if (controller == null) return;

    controller.startImageStream((CameraImage image) {
      // Convert YUV420 plane[0] to bytes for the pose engine
      final bytes = image.planes[0].bytes;
      _pipeline.processFrame(bytes, image.width, image.height);
    });
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    _pipeline.dispose();
    _cameraService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final controller = _cameraService.controller;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Aevum BioAge Session'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Center(
              child: Text(
                'Reps: $_repCount',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            flex: 3,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (_cameraReady && controller != null && controller.value.isInitialized)
                  CameraPreview(controller)
                else
                  _CameraFallback(error: _cameraError, isWeb: kIsWeb),
                GameWidget(game: _game),
                // Pipeline status indicator
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _pipelineActive
                          ? Colors.green.withAlpha(180)
                          : Colors.red.withAlpha(180),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _pipelineActive ? 'TRACKING' : 'OFFLINE',
                      style: const TextStyle(color: Colors.white, fontSize: 10),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Mode'),
                  const SizedBox(height: 8),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'pushup', label: Text('Push-up')),
                      ButtonSegment(value: 'squat', label: Text('Squat')),
                    ],
                    selected: {_mode},
                    onSelectionChanged: (set) {
                      setState(() {
                        _mode = set.first;
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
                  const SizedBox(height: 12),
                  Text(
                    _pipelineActive
                        ? 'Pipeline active: camera → pose → ${_mode} detector → crane'
                        : 'Pipeline offline — check camera & pose engine',
                  ),
                  const Spacer(),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            _game.onNormalRep();
                          },
                          child: const Text('Test Flap'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            _game.onDoubleFast();
                          },
                          child: const Text('Test Boost'),
                        ),
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

class _CameraFallback extends StatelessWidget {
  final String? error;
  final bool isWeb;

  const _CameraFallback({required this.error, required this.isWeb});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black12,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.videocam_off, size: 44),
              const SizedBox(height: 8),
              Text(
                error ?? 'Camera preview unavailable',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                isWeb
                    ? 'On web, ensure HTTPS and browser camera permission are enabled.'
                    : 'Check app permission settings and retry.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
