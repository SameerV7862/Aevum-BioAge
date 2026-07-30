import 'dart:async';
import 'dart:js_interop';
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';

const _viewType = 'aevum-web-camera-preview';
String? _latestContainerId;

bool _registered = false;
Future<bool>? _cameraStartFuture;

@JS('AevumPoseBridge.startCamera')
external JSPromise _jsStartCamera(JSString containerId);

@JS('AevumPoseBridge.stopCamera')
external JSPromise _jsStopCamera();

@JS('AevumPoseBridge.getLastCameraError')
external JSString? _jsGetLastCameraError();

@JS('AevumPoseBridge.getCameraDebugState')
external JSString? _jsGetCameraDebugState();

@JS('AevumPoseBridge.setPreviewLayout')
external void _jsSetPreviewLayout(JSString layout);

void _ensureRegistered() {
  if (_registered) return;
  ui_web.platformViewRegistry.registerViewFactory(_viewType, (int viewId) {
    final containerId = 'aevum-web-camera-container-$viewId';
    final element = html.DivElement()
      ..id = containerId
      ..className = 'aevum-web-camera-container'
      ..dataset['aevumCameraContainer'] = 'true'
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.display = 'block'
      ..style.position = 'relative'
      ..style.overflow = 'hidden'
      ..style.backgroundColor = '#08111b';
    _latestContainerId = containerId;
    return element;
  });
  _registered = true;
}

Widget buildWebPoseCameraPreview() {
  _ensureRegistered();
  return const HtmlElementView(viewType: _viewType);
}

Future<bool> startWebPoseCamera() async {
  final inFlight = _cameraStartFuture;
  if (inFlight != null) {
    return inFlight;
  }

  _ensureRegistered();
  final future = _startWebPoseCameraInternal();
  _cameraStartFuture = future;
  try {
    return await future;
  } finally {
    _cameraStartFuture = null;
  }
}

Future<bool> _startWebPoseCameraInternal() async {
  var containerId = _latestContainerId ?? '';
  for (var i = 0; i < 8 && containerId.isEmpty; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 16));
    containerId = _latestContainerId ?? '';
  }

  final result = await _jsStartCamera(containerId.toJS).toDart;
  return (result as JSBoolean).toDart;
}

Future<void> stopWebPoseCamera() async {
  await _jsStopCamera().toDart;
}

String? getWebPoseCameraLastError() {
  final error = _jsGetLastCameraError();
  return error?.toDart;
}

String? getWebPoseCameraDebugState() {
  final state = _jsGetCameraDebugState();
  return state?.toDart;
}

void setWebPoseCameraPreviewLayout(String layout) {
  _jsSetPreviewLayout(layout.toJS);
}