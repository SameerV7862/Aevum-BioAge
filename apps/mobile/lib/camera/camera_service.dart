import 'package:flutter/foundation.dart';

import 'camera_stub.dart';

class CameraService {
  CameraController? _controller;

  CameraController? get controller => _controller;

  Future<void> initialize() async {
    // On web, the camera package has limited support.
    // Wrap in try/catch so the app remains functional without camera.
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        debugPrint('CameraService: no cameras found');
        return;
      }

      final camera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      _controller = CameraController(
        camera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: kIsWeb ? ImageFormatGroup.jpeg : ImageFormatGroup.yuv420,
      );

      await _controller!.initialize();
    } catch (e) {
      debugPrint('CameraService init error: $e');
      _controller = null;
    }
  }

  Future<void> dispose() async {
    await _controller?.dispose();
  }
}
