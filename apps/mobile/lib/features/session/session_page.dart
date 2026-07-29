import 'package:camera/camera.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../../camera/camera_service.dart';
import '../../exercise/pushup_detector.dart';
import '../../exercise/squat_detector.dart';
import '../../game/aevum_flappy_game.dart';

class SessionPage extends StatefulWidget {
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
  String _mode = 'pushup';

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _cameraService.initialize();
    setState(() => _loading = false);
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
        title: const Text('Aevum BioAge'),
      ),
      body: Column(
        children: [
          Expanded(
            flex: 3,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (controller != null && controller.value.isInitialized)
                  CameraPreview(controller)
                else
                  const ColoredBox(color: Colors.black12),
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
                            // Temporary manual test controls.
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
