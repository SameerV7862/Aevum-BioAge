import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flame/game.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../camera/camera_service.dart';
import '../../camera/camera_stub.dart';
import '../../exercise/exercise_types.dart';
import '../../exercise/pushup_detector.dart';
import '../../exercise/squat_detector.dart';
import '../../game/aevum_flappy_game.dart';
import '../../game/exercise_game_bridge.dart';
import '../../pose/pose_engine_factory.dart';
import '../../pose/pose_pipeline.dart';
import '../../pose/pose_types.dart';
import '../../pose/web_pose_camera.dart';
import '../../scoring/bioage_estimator.dart';
import '../../scoring/session_stats.dart';
import '../../theme/aevum_colors.dart';

// ---------- Session flow phases ----------
enum _Phase { profileInput, prepBriefing, playing }

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
  final _poseHeightCalibrator = PoseHeightCalibrator();
  StreamSubscription<ExerciseEvent>? _eventSub;
  StreamSubscription<GameEvent>? _gameSub;
  Timer? _readyTimer;
  Timer? _webFrameTimer;
  Timer? _calibrationTimer;
  int _calibrationFrames = 0;
  int _calibrationReadyFrames = 0;
  double _calibrationMinPoseHeight = 1.0;
  double _calibrationMaxPoseHeight = 0.0;
  double _calibrationHeightSum = 0.0;
  int _calibrationHeightSamples = 0;
  int _webNullPoseFrameStreak = 0;

  // --- State ---
  _Phase _phase = _Phase.profileInput;
  bool _loading = true;
  bool _cameraReady = false;
  bool _pipelineActive = false;
  bool _cameraRequestInFlight = false;
  String _mode = 'pushup';
  GameState _gameState = GameState.ready;
  bool _prepBriefingCompleted = false;
  bool _readyToStart = false;
  bool _calibrationActive = false;
  bool _calibrationComplete = false;
  bool _calibrationUnlocked = false;
  bool _demoCompleted = false;
  bool _awaitingStartRep = false;
  bool _userProperlyInView = false;
  bool _completedRunAtGoal = false;
  int _countdownSeconds = 0;
  String? _cameraMessage;
  String? _cameraDebugInfo;
  String _lastWebPreviewLayout = '';
  String _viewMessage = 'Enable the camera to begin calibration.';

  // --- Profile & scoring ---
  UserProfile? _profile;
  late SessionStats _stats;
  BioAgeResult? _bioAgeResult;
  final _estimator = const BioAgeEstimator();

  String get _countdownLabel {
    switch (_countdownSeconds) {
      case 3:
        return 'READY';
      case 2:
        return 'SET';
      case 1:
        return 'GO';
      default:
        return '';
    }
  }

  @override
  void initState() {
    super.initState();
    _stats = SessionStats(mode: _mode);
    _game = AevumFlappyGame()
      ..onStateChanged = (s) {
        if (mounted) {
          setState(() => _gameState = s);
          if (kIsWeb && _cameraReady && (s == GameState.playing || s == GameState.ready)) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              unawaited(_refreshWebCameraPreview());
            });
          }
          if (s == GameState.gameOver) _computeBioAge();
        }
      }
      ..onDemoFinished = _handleCalibrationDemoFinished;
    _bridge = ExerciseGameBridge(_game);
    _pipeline = PosePipeline(
      poseEngine: createPoseEngine(),
      detector: _pushupDetector,
    );
    _init();
  }

  Future<void> _init() async {
    if (!kIsWeb) {
      try {
        await _cameraService.initialize();
        _cameraReady = _cameraService.controller?.value.isInitialized == true;
      } catch (e) {
        debugPrint('Camera unavailable: $e');
      }
    }

    try {
      await _pipeline.initialize();
      _pipelineActive = true;
    } catch (e) {
      debugPrint('Pose engine init failed: $e');
    }

    _eventSub = _pipeline.events.listen((event) {
      if (_awaitingStartRep && event is RepCompletedEvent) {
        _beginRound();
        _bridge.onEvent(event);
        _stats.onEvent(event);
        return;
      }

      if (_gameState != GameState.playing) return;

      _bridge.onEvent(event);
      _stats.onEvent(event);
    });

    _gameSub = _game.events.listen((event) {
      if (event == GameEvent.scored) {
        _stats.onPipeCleared(DateTime.now());
        if (kIsWeb) {
          unawaited(playWebScoreSound());
        }
        if (mounted) setState(() {});
      } else if (event == GameEvent.died && kIsWeb) {
        unawaited(playWebDeathSound());
      } else if (event == GameEvent.finished && mounted) {
        setState(() {
          _completedRunAtGoal = true;
          _cameraMessage = null;
        });
        if (kIsWeb) {
          unawaited(playWebFinishSound());
        }
      }
    });

    if (_cameraReady) {
      _startCameraFrameStream();
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _initWebCamera() async {
    if (_cameraRequestInFlight) return;
    if (mounted) {
      setState(() {
        _cameraRequestInFlight = true;
        _cameraMessage = null;
      });
    }

    try {
      final ready = await startWebPoseCamera();
      final bridgeError = getWebPoseCameraLastError();
      final debugState = getWebPoseCameraDebugState();
      if (!mounted) return;
      setState(() {
        _cameraReady = ready;
        _cameraRequestInFlight = false;
        _cameraMessage = ready ? null : _cameraErrorMessage(bridgeError: bridgeError);
        _cameraDebugInfo = debugState;
      });
      if (!ready) return;

      if (kIsWeb) {
        unawaited(startWebBackgroundMusic());
      }

      _webFrameTimer?.cancel();
      _webFrameTimer = Timer.periodic(const Duration(milliseconds: 66), (_) {
        unawaited(_processPoseFrame(Uint8List(0), 0, 0));
      });
    } catch (e) {
      debugPrint('Web camera unavailable: $e');
      if (mounted) {
        setState(() {
          _cameraReady = false;
          _cameraRequestInFlight = false;
          _cameraMessage = _cameraErrorMessage(exception: e);
        });
      }
    }
  }

  Future<void> _refreshWebCameraPreview() async {
    final ready = await startWebPoseCamera();
    final bridgeError = getWebPoseCameraLastError();
    final debugState = getWebPoseCameraDebugState();
    if (!mounted) return;

    if (!ready) {
      setState(() {
        _cameraReady = false;
        _cameraMessage = _cameraErrorMessage(bridgeError: bridgeError);
        _cameraDebugInfo = debugState;
      });
      return;
    }

    if (!_cameraReady || _cameraMessage != null || _cameraDebugInfo != debugState) {
      setState(() {
        _cameraReady = true;
        _cameraMessage = null;
        _cameraDebugInfo = debugState;
      });
    }
  }

  Future<void> _syncWebPreviewLayout() async {
    if (!kIsWeb || !mounted) return;

    final layout = _cameraReady
      ? (_countdownSeconds > 0
        ? 'hidden'
        : ((_gameState == GameState.ready && !_calibrationActive) ? 'ready' : 'corner'))
      : 'hidden';
    if (layout == _lastWebPreviewLayout) return;

    _lastWebPreviewLayout = layout;
    setWebPoseCameraPreviewLayout(layout);

    if (layout != 'hidden' && _cameraReady) {
      await _refreshWebCameraPreview();
    }
  }

  String _cameraErrorMessage({String? bridgeError, Object? exception}) {
    if (bridgeError == 'permission_denied') {
      return 'Camera permission is blocked in your browser. Allow camera for this site, then reload and try again.';
    }
    if (bridgeError == 'no_container') {
      return 'Camera preview was not ready in this tab. Hard refresh (Cmd+Shift+R) and tap ENABLE CAMERA again.';
    }
    if (bridgeError == 'unsupported') {
      return 'This browser does not support camera capture for the current context.';
    }
    if (bridgeError == 'video_not_ready') {
      return 'Camera stream started but video preview did not become ready. Tap ENABLE CAMERA again.';
    }
    if (bridgeError == 'no_stream_tracks') {
      return 'Camera did not return a usable video track. Re-enable camera and close other apps using the camera.';
    }

    final errorText = (exception ?? '').toString().toLowerCase();
    if (errorText.contains('startcamera') || errorText.contains('not a function')) {
      return 'This tab is using an outdated camera bridge. Hard refresh (Cmd+Shift+R) and tap ENABLE CAMERA again.';
    }

    return 'Camera access failed. Check browser permissions and try again.';
  }

  Future<void> _requestCameraAccess() async {
    if (kIsWeb) {
      await _initWebCamera();
      return;
    }

    try {
      await _cameraService.initialize();
      final ready = _cameraService.controller?.value.isInitialized == true;
      if (!mounted) return;
      setState(() => _cameraReady = ready);
      if (ready) {
        _startCameraFrameStream();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cameraReady = false;
        _cameraMessage = 'Camera access failed. Check device permissions and try again.';
      });
    }
  }

  void _startCameraFrameStream() {
    final controller = _cameraService.controller;
    if (controller == null) return;
    try {
      controller.startImageStream((CameraImage image) {
        final bytes = image.planes.isEmpty ? Uint8List(0) : image.planes[0].bytes;
        unawaited(_processPoseFrame(bytes, image.width, image.height));
      });
    } catch (e) {
      debugPrint('startImageStream not supported: $e');
    }
  }

  Future<void> _processPoseFrame(Uint8List bytes, int width, int height) async {
    await _pipeline.processFrame(bytes, width, height);
    final frame = _pipeline.lastFrame;
    if (frame == null) {
      if (kIsWeb) {
        _webNullPoseFrameStreak++;
        if (_webNullPoseFrameStreak % 30 == 0 && mounted) {
          final debugState = getWebPoseCameraDebugState();
          setState(() {
            _cameraMessage =
                'Camera is active but pose frames are not being detected. Try re-enabling camera and keeping shoulders in view.';
            _cameraDebugInfo = debugState;
          });
        }
      }
      return;
    }

    _webNullPoseFrameStreak = 0;

    _stats.onPoseFrame(frame.trackingConfidence);
    final basePoseHeight = frame.estimateVerticalNormalizedHeight();
    final controlPoseHeight =
        _mode == 'pushup' ? frame.estimateUpperBodyNormalizedHeight() : basePoseHeight;
    final assessment = frame.assessView();
    if (mounted &&
        (assessment.isReady != _userProperlyInView || assessment.message != _viewMessage)) {
      setState(() {
        _userProperlyInView = assessment.isReady;
        _viewMessage = assessment.message;
        if (_cameraMessage != null && _cameraMessage!.contains('pose frames are not being detected')) {
          _cameraMessage = null;
        }
      });
    }

    if (_calibrationActive) {
      _calibrationFrames++;
      _poseHeightCalibrator.addCalibrationSample(controlPoseHeight);
      if (assessment.isReady) {
        _calibrationReadyFrames++;
        _calibrationHeightSum += controlPoseHeight;
        _calibrationHeightSamples++;
      }
      _calibrationMinPoseHeight = math.min(_calibrationMinPoseHeight, controlPoseHeight);
      _calibrationMaxPoseHeight = math.max(_calibrationMaxPoseHeight, controlPoseHeight);
    }

    if (!mounted || _gameState != GameState.playing) return;

    final calibratedPoseHeight = _mode == 'pushup'
      ? _poseHeightCalibrator.normalizeRelativeToBaseline(controlPoseHeight)
      : _poseHeightCalibrator.normalizeForControl(controlPoseHeight);
    _game.setPoseVerticalInput(calibratedPoseHeight);
  }

  void _onProfileSubmitted(UserProfile profile) {
    setState(() {
      _profile = profile;
      _phase = _Phase.prepBriefing;
    });
  }

  void _onPrepBriefingContinue() {
    setState(() {
      _prepBriefingCompleted = true;
      _phase = _Phase.playing;
    });
  }

  void _startSession() {
    if (!_prepBriefingCompleted) {
      setState(() {
        _phase = _Phase.prepBriefing;
        _cameraMessage = 'Review the instructions first, then start demo calibration.';
      });
      return;
    }

    if (!cameraReadyOrWarn()) return;
    if (!_pipelineActive) {
      setState(() {
        _cameraMessage = 'Pose engine is not ready yet. Refresh the page and enable camera again.';
      });
      return;
    }
    if (_calibrationActive) {
      return;
    }

    if (_calibrationUnlocked || _calibrationComplete) {
      if (kIsWeb) {
        unawaited(startWebBackgroundMusic());
      }
      _beginRound();
      return;
    }

    _poseHeightCalibrator.reset();
    _resetCalibrationMetrics();
    setState(() {
      _readyToStart = false;
      _calibrationActive = true;
      _calibrationComplete = false;
      _demoCompleted = false;
      _awaitingStartRep = false;
      _countdownSeconds = 0;
      _viewMessage = 'Follow the crane through one pipe to calibrate your motion range.';
    });

    if (kIsWeb) {
      unawaited(startWebBackgroundMusic());
    }

    _game.startDemoRound();
  }

  void _handleCalibrationDemoFinished(bool passedPipe) {
    if (!mounted) return;

    final readyFrameRatio = _calibrationFrames == 0 ? 0.0 : _calibrationReadyFrames / _calibrationFrames;
    final observedRange = _calibrationMaxPoseHeight - _calibrationMinPoseHeight;
    final calibratorReady = _poseHeightCalibrator.finalizeCalibration(minimumRange: 0.07);
    final enoughSamples = _calibrationHeightSamples >= 8;
    final passedCalibration = passedPipe && calibratorReady && enoughSamples && readyFrameRatio >= 0.15;

    if (passedCalibration) {
      final baseline = _calibrationHeightSamples > 0
          ? _calibrationHeightSum / _calibrationHeightSamples
          : (_calibrationMinPoseHeight + _calibrationMaxPoseHeight) / 2;
      _poseHeightCalibrator.setLockedRange(
        minValue: _calibrationMinPoseHeight,
        maxValue: _calibrationMaxPoseHeight,
        baseline: baseline,
      );

      setState(() {
        _calibrationActive = false;
        _calibrationComplete = true;
        _calibrationUnlocked = true;
        _demoCompleted = true;
        _cameraMessage = null;
        _viewMessage = 'Great run. Get ready...';
        _countdownSeconds = 3;
      });

      if (kIsWeb) {
        unawaited(playWebCountdownSound());
      }

      // Ready/Set/Go countdown before auto-starting the real run.
      _readyTimer?.cancel();
      _readyTimer = Timer.periodic(const Duration(milliseconds: 700), (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }

        if (_countdownSeconds <= 1) {
          timer.cancel();
          setState(() {
            _countdownSeconds = 0;
          });
          _beginRound();
          return;
        }

        setState(() {
          _countdownSeconds -= 1;
        });
      });
      return;
    }

    setState(() {
      _calibrationActive = false;
      _calibrationComplete = passedCalibration;
      _demoCompleted = passedPipe;
      _awaitingStartRep = false;
      _readyToStart = false;
      _viewMessage = passedCalibration
          ? 'Demo complete. Calibration locked. Press CONTINUE to start your run.'
          : observedRange < 0.06
              ? 'Move through a larger range in the demo and try again.'
              : 'Calibration data was noisy. Keep your torso centered and run the demo again.';
      if (!passedCalibration) {
        _cameraMessage = 'Run the one-pipe demo again so we can capture a stable movement range.';
      } else {
        _cameraMessage = null;
      }
    });

    if (kIsWeb && _cameraReady) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_refreshWebCameraPreview());
      });
    }
  }

  void _exitCalibration() {
    _game.restart();
    setState(() {
      _calibrationActive = false;
      _calibrationComplete = _calibrationUnlocked;
      _demoCompleted = false;
      _awaitingStartRep = false;
      _cameraMessage = _calibrationUnlocked
          ? 'Calibration remains unlocked. Press START DEMO to play again.'
          : 'Calibration exited. You can restart demo calibration anytime.';
      _viewMessage = _calibrationUnlocked
          ? 'Calibration is saved for this mode. Press START DEMO to jump back in.'
          : 'Choose your mode and start demo calibration when ready.';
    });

    if (kIsWeb && _cameraReady) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_refreshWebCameraPreview());
      });
    }
  }

  bool cameraReadyOrWarn() {
    if (_cameraReady) return true;
    setState(() {
      _cameraMessage = 'Enable camera access before starting calibration.';
    });
    return false;
  }

  void _resetCalibrationMetrics() {
    _calibrationFrames = 0;
    _calibrationReadyFrames = 0;
    _calibrationMinPoseHeight = 1.0;
    _calibrationMaxPoseHeight = 0.0;
    _calibrationHeightSum = 0.0;
    _calibrationHeightSamples = 0;
  }

  void _beginRound() {
    _readyTimer?.cancel();
    _readyTimer = null;
    _calibrationTimer?.cancel();
    _calibrationTimer = null;

    _game.restart();
    _bridge.reset();
    _pushupDetector.reset();
    _squatDetector.reset();
    _stats = SessionStats(mode: _mode);
    _resetCalibrationMetrics();

    if (mounted) {
      setState(() {
        _readyToStart = false;
        _calibrationActive = false;
        _calibrationComplete = _calibrationUnlocked;
        _awaitingStartRep = false;
        _countdownSeconds = 0;
        _cameraMessage = null;
      });
    }

    _game.startPlaying();
  }

  void _computeBioAge() {
    if (_profile == null) return;
    final features = _stats.toFeatures(scoreOverride: _game.score);
    _bioAgeResult = _estimator.estimate(features, _profile!);
  }

  void _restart() {
    _readyTimer?.cancel();
    _readyTimer = null;
    _calibrationTimer?.cancel();
    _calibrationTimer = null;
    _game.restart();
    _bridge.reset();
    _pushupDetector.reset();
    _squatDetector.reset();
    _stats.reset();
    _poseHeightCalibrator.reset();
    _resetCalibrationMetrics();
    setState(() {
      _gameState = GameState.ready;
      _bioAgeResult = null;
      _completedRunAtGoal = false;
      _readyToStart = false;
      _calibrationActive = false;
      _calibrationComplete = _calibrationUnlocked;
      _demoCompleted = false;
      _awaitingStartRep = false;
      _userProperlyInView = false;
      _countdownSeconds = 0;
      _viewMessage = _calibrationUnlocked
          ? 'Calibration is saved for this mode. Press START DEMO to play again.'
          : 'Enable the camera to begin calibration.';
    });
    if (kIsWeb) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_syncWebPreviewLayout());
      });
    }
  }

  void _switchMode(String newMode) {
    setState(() {
      _mode = newMode;
    });
    _stats = SessionStats(mode: newMode);
    _bridge.reset();
    _poseHeightCalibrator.reset();
    _resetCalibrationMetrics();
    _calibrationTimer?.cancel();
    _calibrationTimer = null;
    _calibrationActive = false;
    _calibrationComplete = false;
    _calibrationUnlocked = false;
    _demoCompleted = false;
    _awaitingStartRep = false;
    _countdownSeconds = 0;
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
    _readyTimer?.cancel();
    _webFrameTimer?.cancel();
    _calibrationTimer?.cancel();
    _eventSub?.cancel();
    _gameSub?.cancel();
    if (kIsWeb) {
      stopWebBackgroundMusic();
      unawaited(stopWebPoseCamera());
    }
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

    if (_phase == _Phase.prepBriefing) {
      return _PrepBriefingScreen(onContinue: _onPrepBriefingContinue);
    }

    if (kIsWeb) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_syncWebPreviewLayout());
      });
    }

    final controller = _cameraService.controller;
    final readyOverlayPreview = _gameState == GameState.ready
        ? _buildCameraPreview(
            controller: controller,
            forCorner: false,
          )
        : null;
    final gameplayCornerPreview =
        _gameState == GameState.playing && !_calibrationActive
            ? _buildCameraPreview(
                controller: controller,
                forCorner: true,
              )
            : null;
    final calibrationSidePreview =
        _gameState == GameState.playing && _calibrationActive
            ? _buildCameraPreview(
                controller: controller,
                forCorner: false,
              )
            : null;

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: Color(0xFF080B0F)),

          GameWidget(game: _game),

          if (_gameState == GameState.playing || _gameState == GameState.gameOver)
            Positioned(
              top: 16,
              left: 16,
              child: SafeArea(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: IconButton(
                    onPressed: _restart,
                    color: Colors.white,
                    icon: const Icon(Icons.restart_alt),
                  ),
                ),
              ),
            ),

          if (_gameState == GameState.ready)
            _ReadyOverlay(
              cameraReady: _cameraReady,
              cameraRequestInFlight: _cameraRequestInFlight,
              cameraMessage: _cameraMessage,
              cameraDebugInfo: _cameraDebugInfo,
              isWeb: kIsWeb,
              pipelineActive: _pipelineActive,
              calibrationActive: _calibrationActive,
              calibrationComplete: _calibrationComplete,
              demoCompleted: _demoCompleted,
              awaitingStartRep: _awaitingStartRep,
              userProperlyInView: _userProperlyInView,
              viewMessage: _viewMessage,
              mode: _mode,
              countdownSeconds: _countdownSeconds,
              onRequestCamera: _requestCameraAccess,
              onModeChanged: _switchMode,
              onStart: _startSession,
              onExitCalibration: _exitCalibration,
              cameraPreview: readyOverlayPreview,
            ),

          if (_calibrationActive && _gameState == GameState.playing && calibrationSidePreview != null)
            Positioned(
              top: 16,
              right: 16,
              child: SafeArea(
                child: IgnorePointer(
                  ignoring: true,
                  child: Opacity(
                    opacity: 0.98,
                    child: calibrationSidePreview,
                  ),
                ),
              ),
            ),

          if (_calibrationActive && _gameState == GameState.playing)
            Positioned(
              top: 16,
              left: 16,
              right: 16,
              child: SafeArea(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final compact = constraints.maxWidth < 430;
                    return Flex(
                      direction: compact ? Axis.vertical : Axis.horizontal,
                      crossAxisAlignment: compact ? CrossAxisAlignment.stretch : CrossAxisAlignment.center,
                      children: [
                        if (compact)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: Colors.white24),
                            ),
                            child: const Text(
                              'Calibration demo: clear one pipe to auto-start the game.',
                              style: TextStyle(color: Colors.white, fontSize: 12, height: 1.35),
                            ),
                          )
                        else
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                color: Colors.black54,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: Colors.white24),
                              ),
                              child: const Text(
                                'Calibration demo: clear one pipe to auto-start the game.',
                                style: TextStyle(color: Colors.white, fontSize: 12, height: 1.35),
                              ),
                            ),
                          ),
                        SizedBox(width: compact ? 0 : 10, height: compact ? 8 : 0),
                        Align(
                          alignment: compact ? Alignment.centerRight : Alignment.center,
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(color: Colors.white24),
                            ),
                            child: TextButton.icon(
                              onPressed: _exitCalibration,
                              icon: const Icon(Icons.close, color: Colors.white, size: 16),
                              label: const Text(
                                'EXIT CALIBRATION',
                                style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),

          if (_countdownSeconds > 0)
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  color: Colors.black38,
                  alignment: Alignment.center,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _countdownLabel,
                        style: Theme.of(context).textTheme.displaySmall?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 2,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Starting game...',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(color: Colors.white70),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          if (_gameState == GameState.gameOver)
            _GameOverOverlay(
              score: _game.score,
              completedGoal: _completedRunAtGoal,
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
                    _HudChip(icon: Icons.score, label: '${_game.score} cleared'),
                    _HudChip(icon: Icons.flag, label: '/ ${AevumFlappyGame.maxPipesPerRun}'),
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

          if (_gameState == GameState.playing && !_calibrationActive && gameplayCornerPreview != null)
            Positioned(
              top: 16,
              right: 16,
              child: SafeArea(
                child: IgnorePointer(
                  ignoring: true,
                  child: gameplayCornerPreview,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget? _buildCameraPreview({
    required CameraController? controller,
    required bool forCorner,
  }) {
    if (kIsWeb) {
      // Web preview is rendered by a floating DOM overlay managed in JS.
      // Returning null here removes the stale black in-widget preview box.
      return null;
    }

    if (!_cameraReady) return null;

    final preview = (controller != null && controller.value.isInitialized)
        ? FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: controller.value.previewSize?.height ?? 480,
              height: controller.value.previewSize?.width ?? 640,
              child: CameraPreview(controller),
            ),
          )
        : null;

    if (preview == null) return null;

    final box = forCorner
      ? const BoxConstraints.tightFor(width: 128, height: 180)
      : const BoxConstraints.tightFor(width: 220, height: 300);

    return Container(
      constraints: box,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white24),
        boxShadow: const [
          BoxShadow(color: Colors.black54, blurRadius: 14, offset: Offset(0, 8)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          preview,
          Positioned(
            left: 8,
            bottom: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Text(
                'LIVE',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 10,
                  letterSpacing: 0.8,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WebCameraViewport extends StatelessWidget {
  const _WebCameraViewport();

  @override
  Widget build(BuildContext context) {
    return buildWebPoseCameraPreview();
  }
}

// ---------- Profile input screen ----------

class _ProfileInputScreen extends StatefulWidget {
  final ValueChanged<UserProfile> onSubmit;
  const _ProfileInputScreen({required this.onSubmit});

  @override
  State<_ProfileInputScreen> createState() => _ProfileInputScreenState();
}

class _PrepBriefingScreen extends StatefulWidget {
  final VoidCallback onContinue;

  const _PrepBriefingScreen({required this.onContinue});

  @override
  State<_PrepBriefingScreen> createState() => _PrepBriefingScreenState();
}

class _PrepBriefingScreenState extends State<_PrepBriefingScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          const _AevumScreenBackdrop(),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 26),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: AevumColors.primary.withAlpha(28),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(Icons.space_dashboard, color: AevumColors.primary),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              'Before You Start',
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineSmall
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        const Text(
                          'Step 1: Make sure you have a clear room. Keep space in front, behind, and on both sides so your movement is safe and fully visible to the camera.',
                          style: TextStyle(fontSize: 15, color: AevumColors.textPrimary, height: 1.5),
                        ),
                        const SizedBox(height: 14),
                        AspectRatio(
                          aspectRatio: 16 / 7,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: AevumColors.surfaceDim.withAlpha(175),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: AevumColors.border),
                            ),
                            child: AnimatedBuilder(
                              animation: _controller,
                              builder: (context, _) {
                                return CustomPaint(
                                  painter: _RoomClearancePainter(progress: _controller.value),
                                );
                              },
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AevumColors.surfaceDim.withAlpha(170),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AevumColors.border),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Step 2: Control the bird with your movement',
                                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Goal: clear as many pipes as possible (up to 60). The stick figure demos below show that your body position in the movement range controls the bird height.',
                                style: TextStyle(fontSize: 13, color: AevumColors.textSecondary, height: 1.5),
                              ),
                              const SizedBox(height: 12),
                              LayoutBuilder(
                                builder: (context, constraints) {
                                  final narrow = constraints.maxWidth < 470;
                                  final cards = [
                                    Expanded(
                                      child: _ControlDemoCard(
                                        title: 'Push-up Control',
                                        progress: _controller,
                                        mode: _ControlDemoMode.pushup,
                                      ),
                                    ),
                                    Expanded(
                                      child: _ControlDemoCard(
                                        title: 'Squat Control',
                                        progress: _controller,
                                        mode: _ControlDemoMode.squat,
                                      ),
                                    ),
                                  ];

                                  if (narrow) {
                                    return Column(
                                      children: [
                                        cards[0],
                                        const SizedBox(height: 10),
                                        cards[1],
                                      ],
                                    );
                                  }

                                  return Row(
                                    children: [
                                      cards[0],
                                      const SizedBox(width: 10),
                                      cards[1],
                                    ],
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),
                        const Text(
                          'Tip: smooth reps give steadier control than sudden spikes.',
                          style: TextStyle(fontSize: 12, color: AevumColors.textSecondary),
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: widget.onContinue,
                            icon: const Icon(Icons.arrow_forward),
                            label: const Text('I HAVE SPACE, START TUTORIAL'),
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 15),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoomClearancePainter extends CustomPainter {
  final double progress;

  const _RoomClearancePainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final frame = Paint()..color = const Color(0xFF3A5A78).withAlpha(150);
    final room = RRect.fromRectAndRadius(
      Rect.fromLTWH(8, 8, size.width - 16, size.height - 16),
      const Radius.circular(12),
    );
    canvas.drawRRect(room, frame);

    final center = Offset(size.width * 0.5, size.height * 0.58);
    final breathing = 0.88 + 0.12 * math.sin(progress * math.pi * 2);
    final clearanceRadius = (size.height * 0.28) * breathing;

    final safePaint = Paint()
      ..color = const Color(0xFF2CC36B).withAlpha(42)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, clearanceRadius, safePaint);

    final ringPaint = Paint()
      ..color = const Color(0xFF59D98D).withAlpha(175)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(center, clearanceRadius, ringPaint);

    final warningPaint = Paint()..color = const Color(0xFFE86A5B).withAlpha(145);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(size.width * 0.08, size.height * 0.24, 24, 24),
        const Radius.circular(6),
      ),
      warningPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(size.width * 0.84, size.height * 0.68, 24, 24),
        const Radius.circular(6),
      ),
      warningPaint,
    );

    final personPaint = Paint()
      ..color = const Color(0xFFF8FCFF)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final sway = math.sin(progress * math.pi * 2) * 6;
    final head = Offset(center.dx + sway, center.dy - 24);
    canvas.drawCircle(head, 7, personPaint);
    canvas.drawLine(Offset(head.dx, head.dy + 8), Offset(head.dx, head.dy + 32), personPaint);
    canvas.drawLine(Offset(head.dx, head.dy + 16), Offset(head.dx - 10, head.dy + 22), personPaint);
    canvas.drawLine(Offset(head.dx, head.dy + 16), Offset(head.dx + 10, head.dy + 22), personPaint);
    canvas.drawLine(Offset(head.dx, head.dy + 32), Offset(head.dx - 9, head.dy + 46), personPaint);
    canvas.drawLine(Offset(head.dx, head.dy + 32), Offset(head.dx + 9, head.dy + 46), personPaint);
  }

  @override
  bool shouldRepaint(covariant _RoomClearancePainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

enum _ControlDemoMode { pushup, squat }

class _ControlDemoCard extends StatelessWidget {
  final String title;
  final Animation<double> progress;
  final _ControlDemoMode mode;

  const _ControlDemoCard({
    required this.title,
    required this.progress,
    required this.mode,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AevumColors.surfaceDim.withAlpha(150),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AevumColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            AspectRatio(
              aspectRatio: 16 / 8,
              child: AnimatedBuilder(
                animation: progress,
                builder: (context, _) {
                  return CustomPaint(
                    painter: _StickBirdControlPainter(
                      progress: progress.value,
                      mode: mode,
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StickBirdControlPainter extends CustomPainter {
  final double progress;
  final _ControlDemoMode mode;

  const _StickBirdControlPainter({required this.progress, required this.mode});

  @override
  void paint(Canvas canvas, Size size) {
    final t = (math.sin(progress * math.pi * 2) + 1) / 2;
    final figureBaseY = size.height * 0.78;
    final motionRange = mode == _ControlDemoMode.pushup ? 16.0 : 22.0;
    final bodyOffset = (0.5 - t) * motionRange;

    final pipePaint = Paint()..color = const Color(0xFF355D87);
    canvas.drawRect(Rect.fromLTWH(size.width * 0.77, 0, size.width * 0.1, size.height * 0.35), pipePaint);
    canvas.drawRect(
      Rect.fromLTWH(size.width * 0.77, size.height * 0.65, size.width * 0.1, size.height * 0.35),
      pipePaint,
    );

    final linePaint = Paint()
      ..color = const Color(0xFFEBF5FF)
      ..strokeWidth = 2.4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    if (mode == _ControlDemoMode.pushup) {
      final bend = 1 - t;
      final groundY = figureBaseY + 6;
      final shoulder = Offset(size.width * 0.44, size.height * 0.56 + bodyOffset * 0.6);
      final hip = Offset(size.width * 0.30, shoulder.dy + bend * 2);
      final ankle = Offset(size.width * 0.14, groundY - 2);
      final elbow = Offset(size.width * 0.51, shoulder.dy + 12 + bend * 10);
      final wrist = Offset(size.width * 0.57, groundY);
      final head = Offset(size.width * 0.60, shoulder.dy - 10 - bend);
      final neck = Offset(head.dx - 7, head.dy + 7);
      final knee = Offset(
        (hip.dx + ankle.dx) / 2,
        (hip.dy + ankle.dy) / 2 + 1,
      );

      final floorPaint = Paint()
        ..color = const Color(0xFFEBF5FF).withAlpha(52)
        ..strokeWidth = 1.4
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(
        Offset(size.width * 0.16, groundY + 9),
        Offset(size.width * 0.62, groundY + 9),
        floorPaint,
      );

      canvas.drawCircle(head, 5.8, linePaint);
      canvas.drawLine(neck, shoulder, linePaint);
      canvas.drawLine(shoulder, hip, linePaint);
      canvas.drawLine(hip, knee, linePaint);
      canvas.drawLine(knee, ankle, linePaint);
      canvas.drawLine(shoulder, elbow, linePaint);
      canvas.drawLine(elbow, wrist, linePaint);
      canvas.drawLine(wrist, Offset(wrist.dx - 4, wrist.dy), linePaint);
      canvas.drawLine(ankle, Offset(ankle.dx + 5, groundY - 2), linePaint);
    } else {
      final hipY = figureBaseY - 30 + bodyOffset;
      final head = Offset(size.width * 0.24, hipY - 24);
      canvas.drawCircle(head, 5, linePaint);
      canvas.drawLine(Offset(head.dx, head.dy + 6), Offset(head.dx, hipY), linePaint);
      final kneeY = hipY + 16 + (1 - t) * 5;
      canvas.drawLine(Offset(head.dx, hipY), Offset(head.dx - 10, kneeY), linePaint);
      canvas.drawLine(Offset(head.dx, hipY), Offset(head.dx + 10, kneeY), linePaint);
      canvas.drawLine(Offset(head.dx - 10, kneeY), Offset(head.dx - 8, figureBaseY + 4), linePaint);
      canvas.drawLine(Offset(head.dx + 10, kneeY), Offset(head.dx + 8, figureBaseY + 4), linePaint);
      canvas.drawLine(Offset(head.dx, head.dy + 14), Offset(head.dx - 10, head.dy + 20), linePaint);
      canvas.drawLine(Offset(head.dx, head.dy + 14), Offset(head.dx + 10, head.dy + 20), linePaint);
    }

    final birdY = size.height * 0.72 - (t * size.height * 0.34);
    final birdX = size.width * 0.58;
    final bird = Path()
      ..moveTo(birdX - 11, birdY)
      ..quadraticBezierTo(birdX - 1, birdY - 8, birdX + 11, birdY)
      ..quadraticBezierTo(birdX - 1, birdY + 8, birdX - 11, birdY)
      ..close();
    final birdPaint = Paint()..color = const Color(0xFFDEB857);
    canvas.drawPath(bird, birdPaint);

    final arrowPaint = Paint()
      ..color = const Color(0xFF75D0FF)
      ..strokeWidth = 2;
    final arrowX = size.width * 0.67;
    canvas.drawLine(Offset(arrowX, size.height * 0.26), Offset(arrowX, size.height * 0.72), arrowPaint);
    canvas.drawLine(Offset(arrowX, size.height * 0.26), Offset(arrowX - 4, size.height * 0.31), arrowPaint);
    canvas.drawLine(Offset(arrowX, size.height * 0.26), Offset(arrowX + 4, size.height * 0.31), arrowPaint);
    canvas.drawLine(Offset(arrowX, size.height * 0.72), Offset(arrowX - 4, size.height * 0.67), arrowPaint);
    canvas.drawLine(Offset(arrowX, size.height * 0.72), Offset(arrowX + 4, size.height * 0.67), arrowPaint);
  }

  @override
  bool shouldRepaint(covariant _StickBirdControlPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.mode != mode;
  }
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
      body: Stack(
        fit: StackFit.expand,
        children: [
          const _AevumScreenBackdrop(),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Aevum BioAge',
                            style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        const Text(
                          'Set your baseline first, then use movement to guide the crane through a coordinated longevity-inspired assessment.',
                          style: TextStyle(color: AevumColors.textSecondary, height: 1.5),
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
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [AevumColors.primary.withAlpha(22), AevumColors.gold.withAlpha(18)],
                            ),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: AevumColors.primary.withAlpha(60)),
                          ),
                          child: const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                Icon(Icons.science, size: 16, color: AevumColors.primary),
                                SizedBox(width: 6),
                                Text('Evidence-aware estimate', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                              ]),
                              SizedBox(height: 6),
                              Text(
                                'Pipe-clear performance and pace consistency are used as a movement-capacity signal in this game-based estimate. Tracking quality is factored into confidence.',
                                style: TextStyle(fontSize: 12, color: AevumColors.textSecondary, height: 1.45),
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
                              padding: const EdgeInsets.symmetric(vertical: 16),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
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
  final bool cameraReady;
  final bool cameraRequestInFlight;
  final String? cameraMessage;
  final String? cameraDebugInfo;
  final bool isWeb;
  final bool pipelineActive;
  final bool calibrationActive;
  final bool calibrationComplete;
  final bool demoCompleted;
  final bool awaitingStartRep;
  final bool userProperlyInView;
  final String viewMessage;
  final String mode;
  final int countdownSeconds;
  final Future<void> Function() onRequestCamera;
  final ValueChanged<String> onModeChanged;
  final VoidCallback onStart;
  final VoidCallback onExitCalibration;
  final Widget? cameraPreview;

  const _ReadyOverlay({
    required this.cameraReady,
    required this.cameraRequestInFlight,
    required this.cameraMessage,
    required this.cameraDebugInfo,
    required this.isWeb,
    required this.pipelineActive,
    required this.calibrationActive,
    required this.calibrationComplete,
    required this.demoCompleted,
    required this.awaitingStartRep,
    required this.userProperlyInView,
    required this.viewMessage,
    required this.mode,
    required this.countdownSeconds,
    required this.onRequestCamera,
    required this.onModeChanged,
    required this.onStart,
    required this.onExitCalibration,
    required this.cameraPreview,
  });

  String _cleanStatusText(String value) {
    final noTags = value.replaceAll(RegExp(r'<[^>]*>'), ' ');
    return noTags.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final compact = screenWidth < 430;
    final cardPadding = compact
        ? const EdgeInsets.symmetric(horizontal: 16, vertical: 14)
        : const EdgeInsets.symmetric(horizontal: 28, vertical: 26);
    final buttonWidth = compact ? double.infinity : 240.0;

    return Container(
      color: AevumColors.surfaceDim.withAlpha(92),
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 16, vertical: compact ? 8 : 12),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight - (compact ? 16 : 24)),
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Card(
                    child: Padding(
                      padding: cardPadding,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                Icon(
                  pipelineActive ? Icons.fitness_center : Icons.videocam_off,
                  size: 64, color: AevumColors.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  pipelineActive
                      ? calibrationActive
                      ? 'DEMO CALIBRATION'
                          : calibrationComplete
                        ? 'READY TO CONTINUE'
                              : 'READY'
                      : 'CAMERA NEEDED',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  pipelineActive && cameraReady
                      ? calibrationActive
                      ? 'Guide the crane through spaced pipes. Clear one pipe to complete calibration.'
                      : calibrationComplete
                        ? 'Calibration is complete. Press CONTINUE to start the real run.'
                        : 'Choose ${mode == 'pushup' ? 'push-ups' : 'squats'} and start the demo calibration.'
                      : (isWeb
                          ? 'Enable camera access to start browser pose tracking on laptop or mobile.'
                          : 'Allow camera access to begin pose tracking'),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white70),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                if (cameraPreview != null) ...[
                  Center(child: cameraPreview),
                  const SizedBox(height: 16),
                ],
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: (userProperlyInView ? AevumColors.success : AevumColors.muted).withAlpha(60),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: userProperlyInView ? AevumColors.success : AevumColors.border,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        userProperlyInView ? Icons.check_circle : Icons.accessibility_new,
                        size: 16,
                        color: userProperlyInView ? AevumColors.success : AevumColors.textSecondary,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          viewMessage,
                          style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.4),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                _ModeToggle(mode: mode, onChanged: onModeChanged),
                const SizedBox(height: 16),
                if (!cameraReady) ...[
                  SizedBox(
                    width: buttonWidth,
                    child: FilledButton.icon(
                      onPressed: cameraRequestInFlight ? null : () => onRequestCamera(),
                      style: FilledButton.styleFrom(
                        backgroundColor: AevumColors.primary,
                        foregroundColor: AevumColors.background,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                      ),
                      icon: Icon(cameraRequestInFlight ? Icons.hourglass_top : Icons.videocam),
                      label: Text(cameraRequestInFlight ? 'REQUESTING CAMERA' : 'ENABLE CAMERA'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    cameraMessage ??
                        (isWeb
                            ? 'Works best in Safari, Chrome, or Edge with front-camera permission enabled.'
                            : 'Grant camera permission when your device prompts for it.'),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: cameraMessage == null ? AevumColors.textSecondary : AevumColors.warning,
                        ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                ],
                if (cameraMessage != null && cameraReady) ...[
                  Text(
                    _cleanStatusText(cameraMessage!),
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: AevumColors.warning),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                ],
                if (kDebugMode && cameraMessage != null && isWeb && cameraDebugInfo != null) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black26,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: Text(
                      'debug: $cameraDebugInfo',
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 10,
                        height: 1.3,
                      ),
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                SizedBox(
                  width: buttonWidth,
                  child: FilledButton.icon(
                    onPressed: cameraReady && !calibrationActive && countdownSeconds == 0 ? onStart : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: AevumColors.gold,
                      foregroundColor: AevumColors.background,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                    ),
                    icon: Icon(
                      calibrationActive
                          ? Icons.sports_score
                          : calibrationComplete
                              ? Icons.play_circle_fill
                              : Icons.play_arrow,
                    ),
                    label: Text(
                      countdownSeconds > 0
                        ? 'STARTING...'
                        : calibrationActive
                          ? 'DEMO RUNNING...'
                          : calibrationComplete
                              ? 'CONTINUE'
                              : 'START DEMO',
                    ),
                  ),
                ),
                if (calibrationActive) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    width: buttonWidth,
                    child: OutlinedButton.icon(
                      onPressed: onExitCalibration,
                      icon: const Icon(Icons.close),
                      label: const Text('EXIT CALIBRATION'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white38),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                      ),
                    ),
                  ),
                ],
                if (!pipelineActive) ...[
                  const SizedBox(height: 16),
                  Text('Pose tracking initializes after camera permission is granted',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AevumColors.warning)),
                ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _GameOverOverlay extends StatelessWidget {
  final int score;
  final bool completedGoal;
  final BioAgeResult? bioAgeResult;
  final VoidCallback onRestart;

  const _GameOverOverlay({
    required this.score,
    required this.completedGoal,
    required this.bioAgeResult,
    required this.onRestart,
  });

  @override
  Widget build(BuildContext context) {
    final result = bioAgeResult;
    return Container(
      color: AevumColors.surfaceDim.withAlpha(220),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (completedGoal) const IgnorePointer(child: _ConfettiOverlay()),
          Center(
            child: SingleChildScrollView(
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        completedGoal ? 'GOAL COMPLETE' : 'SESSION COMPLETE',
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: 1),
                      ),
                      if (completedGoal) ...[
                        const SizedBox(height: 8),
                        const Text(
                          'You reached the 60 pipe finish line.',
                          style: TextStyle(fontSize: 12, color: AevumColors.success),
                        ),
                      ],
                      const SizedBox(height: 20),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _ScoreStat(label: 'SCORE', value: '$score'),
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
                            color: AevumColors.muted, borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            'Based on score-based session performance, tracking quality, and pacing consistency. '
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
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConfettiOverlay extends StatefulWidget {
  const _ConfettiOverlay();

  @override
  State<_ConfettiOverlay> createState() => _ConfettiOverlayState();
}

class _ConfettiOverlayState extends State<_ConfettiOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final List<_ConfettiPiece> _pieces;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1900),
    )..repeat();
    _pieces = _buildPieces();
  }

  List<_ConfettiPiece> _buildPieces() {
    final rng = math.Random(42);
    final palette = <Color>[
      const Color(0xFFE9B949),
      const Color(0xFF64D2FF),
      const Color(0xFF82E08C),
      const Color(0xFFFF8F70),
      const Color(0xFFF5F7FA),
    ];

    return List.generate(70, (_) {
      return _ConfettiPiece(
        x: rng.nextDouble(),
        size: 5 + rng.nextDouble() * 7,
        fallSpeed: 0.65 + rng.nextDouble() * 0.75,
        sway: 0.01 + rng.nextDouble() * 0.03,
        phase: rng.nextDouble() * math.pi * 2,
        color: palette[rng.nextInt(palette.length)],
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return CustomPaint(
          painter: _ConfettiPainter(
            pieces: _pieces,
            progress: _controller.value,
          ),
          child: const SizedBox.expand(),
        );
      },
    );
  }
}

class _ConfettiPiece {
  final double x;
  final double size;
  final double fallSpeed;
  final double sway;
  final double phase;
  final Color color;

  const _ConfettiPiece({
    required this.x,
    required this.size,
    required this.fallSpeed,
    required this.sway,
    required this.phase,
    required this.color,
  });
}

class _ConfettiPainter extends CustomPainter {
  final List<_ConfettiPiece> pieces;
  final double progress;

  const _ConfettiPainter({required this.pieces, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    for (final piece in pieces) {
      final xDrift = math.sin((progress * math.pi * 2 * piece.fallSpeed) + piece.phase) * (24 * piece.sway * 40);
      final dx = (piece.x * size.width) + xDrift;
      final dy = ((progress * piece.fallSpeed + piece.x) % 1.2) * size.height - 24;

      final rect = Rect.fromCenter(
        center: Offset(dx, dy),
        width: piece.size,
        height: piece.size * 0.6,
      );
      final paint = Paint()..color = piece.color.withAlpha(220);
      canvas.save();
      canvas.translate(dx, dy);
      canvas.rotate((progress * 6.5) + piece.phase);
      canvas.drawRect(
        Rect.fromCenter(center: Offset.zero, width: rect.width, height: rect.height),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.pieces != pieces;
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
      decoration: BoxDecoration(color: AevumColors.surfaceDim.withAlpha(200), borderRadius: BorderRadius.circular(16)),
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
      decoration: BoxDecoration(color: AevumColors.surfaceDim.withAlpha(200), borderRadius: BorderRadius.circular(20)),
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

class _AevumScreenBackdrop extends StatelessWidget {
  const _AevumScreenBackdrop();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF071018), Color(0xFF0F2336), Color(0xFF183754)],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -80,
            right: -40,
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [AevumColors.primary.withAlpha(70), Colors.transparent]),
              ),
            ),
          ),
          Positioned(
            bottom: -60,
            left: -40,
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [AevumColors.gold.withAlpha(42), Colors.transparent]),
              ),
            ),
          ),
          Positioned.fill(
            child: CustomPaint(
              painter: _SessionBackdropPainter(),
            ),
          ),
        ],
      ),
    );
  }
}

class _SessionBackdropPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = AevumColors.secondary.withAlpha(14)
      ..strokeWidth = 1;
    const spacing = 34.0;
    for (var x = 0.0; x <= size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), linePaint);
    }
    for (var y = 0.0; y <= size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);
    }

    final orbitPaint = Paint()
      ..color = AevumColors.cream.withAlpha(20)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    canvas.drawOval(Rect.fromCenter(center: Offset(size.width * 0.72, size.height * 0.18), width: 220, height: 110), orbitPaint);
    canvas.drawOval(Rect.fromCenter(center: Offset(size.width * 0.18, size.height * 0.74), width: 180, height: 90), orbitPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
