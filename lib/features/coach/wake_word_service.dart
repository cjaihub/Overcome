import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/router/app_router.dart';
import '../../core/services/analytics_service.dart';
import '../../core/services/firebase_providers.dart';
import '../tracker/guardian_controller.dart';
import 'voice_engine.dart';

/// Hands-free mode: while Ovacome is open, listens for the user's wake
/// phrase (their first name by default, or any name they choose) and opens
/// the voice coach. Paused whenever the app is in the background, while
/// the coach itself is listening, or when hands-free is turned off.
class WakeWordService with WidgetsBindingObserver {
  WakeWordService(this._ref);
  final Ref _ref;
  bool _running = false;
  bool _paused = false;
  bool _foreground = true;

  void start() {
    WidgetsBinding.instance.addObserver(this);
    _ref.listen(guardianProvider, (_, _) => _loop(), fireImmediately: true);
  }

  /// The coach screen pauses wake listening while it records.
  void pause() => _paused = true;

  void resume() {
    _paused = false;
    _loop();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) _loop();
  }

  bool get _shouldListen => _foreground && !_paused && _ref.read(guardianProvider).handsFree;

  Future<void> _loop() async {
    if (_running || !_shouldListen) return;
    if (!await Permission.microphone.request().isGranted) return;
    _running = true;
    final engine = _ref.read(voiceEngineProvider);
    try {
      while (_shouldListen) {
        final name = (_ref.read(userDocProvider).value?['profile'] as Map?)?['displayName'] as String? ?? '';
        final phrase = _ref.read(guardianProvider).effectiveWakePhrase(name);
        if (await engine.listenForPhrase(phrase) && _shouldListen) {
          HapticFeedback.heavyImpact();
          _ref.read(analyticsProvider).log(AppEvent.wakeWord);
          _paused = true;
          _ref.read(routerProvider).push('/coach?voice=1');
        }
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
    } finally {
      _running = false;
    }
  }
}

final wakeWordProvider = Provider<WakeWordService>((ref) => WakeWordService(ref));
