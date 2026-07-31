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
  bool _readyToStart = false;
  bool _calibrationActive = false;
  bool _calibrationComplete = false;
  bool _calibrationUnlocked = false;
  bool _demoCompleted = false;
  bool _awaitingStartRep = false;
  bool _userProperlyInView = false;
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
      _phase = _Phase.playing;
    });
  }

  void _startSession() {
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
        _cameraMessage = 'Calibration complete. Starting game...';
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
          if (_calibrationUnlocked) {
            _cameraMessage = 'Calibration already unlocked. Press START DEMO to play again.';
            _viewMessage = 'Calibration is saved for this mode. Press START DEMO to jump into the game.';
          }
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
                child: Row(
                  children: [
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
                    const SizedBox(width: 10),
                    Container(
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
                  ],
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

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AevumColors.surfaceDim.withAlpha(92),
      child: SafeArea(
        child: Column(
          children: [
            const Spacer(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 26),
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
                    width: 240,
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
                    cameraMessage!,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: AevumColors.warning),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                ],
                if (cameraMessage != null && isWeb && cameraDebugInfo != null) ...[
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
                  width: 240,
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
                    width: 240,
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
          ],
        ),
      ),
    );
  }
}

class _GameOverOverlay extends StatelessWidget {
  final int score;
  final BioAgeResult? bioAgeResult;
  final VoidCallback onRestart;

  const _GameOverOverlay({
    required this.score,
    required this.bioAgeResult,
    required this.onRestart,
  });

  @override
  Widget build(BuildContext context) {
    final result = bioAgeResult;
    return Container(
      color: AevumColors.surfaceDim.withAlpha(220),
      child: Center(
        child: SingleChildScrollView(
          child: Card(
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
