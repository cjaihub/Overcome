import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Every meaningful interaction the owner wants to measure.
///
/// Events land in `users/{uid}/events`; the `aggregateEvent` Cloud Function
/// rolls them up into per-user counters and global daily metrics that the
/// admin dashboard reads.
enum AppEvent {
  appOpen,
  sessionEnd,
  onboardingStep,
  onboardingComplete,
  planAssigned,
  formSubmit,
  bookView,
  bookOpen,
  pdfPageView,
  audioPlay,
  audioComplete,
  readAlongStart,
  aiNarration,
  paywallView,
  purchase,
  codeRedeemed,
  captureAttempt,
}

extension on AppEvent {
  String get wire => name.replaceAllMapped(RegExp('[A-Z]'), (m) => '_${m[0]!.toLowerCase()}');
}

class AnalyticsService with WidgetsBindingObserver {
  AnalyticsService(this._db, this._auth);

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;
  final _ga = FirebaseAnalytics.instance;

  String _sessionId = _newId();
  DateTime _sessionStart = DateTime.now();

  static String _newId() => List.generate(16, (_) => Random.secure().nextInt(16).toRadixString(16)).join();

  void start() {
    WidgetsBinding.instance.addObserver(this);
    log(AppEvent.appOpen);
  }

  Future<void> log(AppEvent event, [Map<String, Object?> props = const {}]) async {
    final user = _auth.currentUser;
    final clean = {
      for (final e in props.entries)
        if (e.value != null) e.key: e.value!,
    };
    await _ga.logEvent(
      name: event.wire,
      parameters: clean.map((k, v) => MapEntry(k, v is num || v is String ? v : v.toString())),
    );
    if (user == null) return;
    await _db.collection('users/${user.uid}/events').add({
      'type': event.wire,
      'props': clean,
      'sessionId': _sessionId,
      'at': FieldValue.serverTimestamp(),
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
        final seconds = DateTime.now().difference(_sessionStart).inSeconds;
        log(AppEvent.sessionEnd, {'durationSec': seconds});
      case AppLifecycleState.resumed:
        _sessionId = _newId();
        _sessionStart = DateTime.now();
        log(AppEvent.appOpen);
      default:
        break;
    }
  }
}

final analyticsProvider = Provider<AnalyticsService>(
  (_) => AnalyticsService(FirebaseFirestore.instance, FirebaseAuth.instance),
);
