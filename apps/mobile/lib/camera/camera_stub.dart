import 'dart:typed_data';

import 'package:flutter/widgets.dart';

class CameraValue {
  CameraValue({required this.isInitialized, this.previewSize});

  final bool isInitialized;
  final Size? previewSize;
}

class CameraDescription {
  const CameraDescription({required this.lensDirection});

  final CameraLensDirection lensDirection;
}

enum CameraLensDirection { front, back }

enum ResolutionPreset { low, medium, high, veryHigh, ultraHigh, max }

enum ImageFormatGroup { yuv420, jpeg }

class CameraImage {
  const CameraImage({required this.width, required this.height, required this.planes});

  final int width;
  final int height;
  final List<Plane> planes;
}

class Plane {
  const Plane({required this.bytes});

  final Uint8List bytes;
}

class CameraController {
  CameraController(
    this.description,
    this.resolutionPreset, {
    this.enableAudio = false,
    this.imageFormatGroup,
  });

  final CameraDescription description;
  final ResolutionPreset resolutionPreset;
  final bool enableAudio;
  final ImageFormatGroup? imageFormatGroup;

  CameraValue value = CameraValue(isInitialized: false);

  Future<void> initialize() async {
    value = CameraValue(
      isInitialized: true,
      previewSize: const Size(480, 640),
    );
  }

  Future<void> dispose() async {}

  void startImageStream(Function(CameraImage image) onImage) {
    onImage(const CameraImage(width: 0, height: 0, planes: []));
  }
}

Future<List<CameraDescription>> availableCameras() async => const <CameraDescription>[];

class CameraPreview extends StatelessWidget {
  const CameraPreview(this.controller, {super.key});

  final CameraController controller;

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}
