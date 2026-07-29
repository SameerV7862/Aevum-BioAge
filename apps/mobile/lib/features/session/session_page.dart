import 'package:camera/camera.dart';
import 'package:flame/game.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../camera/camera_service.dart';
import '../../exercise/pushup_detector.dart';
import '../../exercise/squat_detector.dart';
import '../../game/aevum_flappy_game.dart';

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

  bool _loading = true;
  bool _cameraReady = false;
  String _mode = 'pushup';
  String? _cameraError;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      await _cameraService.initialize();
      _cameraReady = _cameraService.controller?.value.isInitialized == true;
    } catch (e) {
      _cameraError = 'Camera unavailable: $e';
      _cameraReady = false;
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  void dispose() {
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
                      setState(() => _mode = set.first);
                      _pushupDetector.reset();
                      _squatDetector.reset();
                    },
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Scaffold ready: connect camera frames to pose engine and detectors, then map events to crane controls.',
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
