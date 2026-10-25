import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:go_router/go_router.dart';

/// Registers this device for the daily check-in reminders sent by the
/// `dailyNudge` function and routes notification taps into the app.
class PushService {
  PushService(this._router);
  final GoRouter _router;
  final _subs = <StreamSubscription<dynamic>>[];

  void start() {
    _subs
      ..add(
        FirebaseAuth.instance.authStateChanges().listen((user) {
          if (user != null) _register(user.uid);
        }),
      )
      ..add(
        // Registration tokens (not the newer FID registration) because the
        // Admin SDK's multicast send used by `dailyNudge` targets tokens.
        // ignore: deprecated_member_use
        FirebaseMessaging.instance.onTokenRefresh.listen((token) {
          final uid = FirebaseAuth.instance.currentUser?.uid;
          if (uid != null) _save(uid, token);
        }),
      )
      ..add(FirebaseMessaging.onMessageOpenedApp.listen(_open));
    FirebaseMessaging.instance.getInitialMessage().then((m) {
      if (m != null) _open(m);
    });
  }

  Future<void> _register(String uid) async {
    // ignore: deprecated_member_use
    final token = await FirebaseMessaging.instance.getToken();
    if (token != null) await _save(uid, token);
  }

  Future<void> _save(String uid, String token) => FirebaseFirestore.instance.doc('users/$uid').set({
    'fcmTokens': FieldValue.arrayUnion([token]),
  }, SetOptions(merge: true));

  void _open(RemoteMessage m) {
    final route = m.data['route'] as String?;
    if (route != null && route.startsWith('/')) _router.go(route);
  }

  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
  }
}
