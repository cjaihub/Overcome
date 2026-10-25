import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Bridge to the native anti-capture layer.
///
/// * Android: `FLAG_SECURE` is set on the activity window at launch
///   (MainActivity.kt). Screenshots, screen recordings, casting to
///   non-secure displays and the recent-apps thumbnail all render black.
/// * iOS: the Flutter view is hosted inside a secure text-entry layer
///   (AppDelegate.swift), so the system screenshot and recorder capture a
///   blank frame. Recording/mirroring is also reported here so the UI can
///   blank protected content, and screenshot attempts are logged.
///
/// A camera pointed at the screen cannot be blocked by any software, so
/// protected pages also carry a per-user forensic watermark
/// (see [SecureContentGuard]).
class ScreenSecurity {
  ScreenSecurity._();
  static final instance = ScreenSecurity._();

  static const _method = MethodChannel('overcome/security');
  static const _events = EventChannel('overcome/security/events');

  final _captured = StreamController<bool>.broadcast();
  final _screenshots = StreamController<void>.broadcast();
  bool _isCaptured = false;
  StreamSubscription<dynamic>? _sub;

  bool get isCaptured => _isCaptured;
  Stream<bool> get capturedChanges => _captured.stream;
  Stream<void> get screenshotAttempts => _screenshots.stream;

  Future<void> init() async {
    if (kIsWeb) return;
    try {
      await _method.invokeMethod<void>('enable');
      _isCaptured = await _method.invokeMethod<bool>('isCaptured') ?? false;
    } on MissingPluginException {
      return; // tests / unsupported platforms
    }
    _sub = _events.receiveBroadcastStream().listen((event) {
      if (event is! Map) return;
      switch (event['type']) {
        case 'captured':
          _isCaptured = event['value'] == true;
          _captured.add(_isCaptured);
        case 'screenshot':
          _screenshots.add(null);
      }
    });
  }

  /// Android's PdfRenderer needs a file descriptor, so the PDF plugin stages
  /// decrypted bytes in the app-private cache. Once the renderer holds the
  /// descriptor the file can be unlinked; this removes every staged copy.
  Future<void> purgeRendererCache() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _method.invokeMethod<void>('purgeRendererCache');
    } on MissingPluginException {
      return;
    }
  }

  Future<void> dispose() async {
    await _sub?.cancel();
  }
}
