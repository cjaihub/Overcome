import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../core/services/analytics_service.dart';
import '../../core/services/usage_service.dart';
import '../onboarding/onboarding_profile.dart';
import 'usage_insights.dart';

/// Mirrors daily usage summaries to `users/{uid}/usage/{yyyymmdd}` so the AI
/// coach, the server reminders and the owner dashboard work from real data.
/// Runs on launch, on resume and every 5 minutes while the app is open.
/// Only app *names* and totals leave the device — never notification content.
class UsageSync with WidgetsBindingObserver {
  UsageSync(this._ref);
  final Ref _ref;
  Timer? _timer;

  void start() {
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(const Duration(minutes: 5), (_) => sync());
    sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _ref.invalidate(usageStatusProvider);
      sync();
    }
  }

  Future<void> sync() async {
    final usage = _ref.read(usageServiceProvider);
    final user = FirebaseAuth.instance.currentUser;
    if (!usage.supported || user == null) return;
    try {
      if (!(await usage.status()).usageAccess) return;
      final db = FirebaseFirestore.instance;
      final profileSnap = await db.doc('users/${user.uid}').get();
      final profile = OnboardingProfile.fromMap(profileSnap.data()?['profile'] as Map<String, dynamic>?);
      final target = UsageInsights.targetMinutes(
        baselineHours: profile.dailyHours,
        commitMinutes: profile.dailyMinutesGoal,
      );
      final now = DateTime.now();
      // Today, plus yesterday so its final numbers are captured after midnight.
      for (final day in [now.subtract(const Duration(days: 1)), now]) {
        final s = await usage.day(day);
        await db.doc('users/${user.uid}/usage/${DateFormat('yyyyMMdd').format(day)}').set({
          'totalMin': s.total.inMinutes,
          'screenOnMin': s.screenOn.inMinutes,
          'pickups': s.pickups,
          'notifications': s.notifications,
          'lateNightMin': s.lateNightMinutes.round(),
          'focusScore': UsageInsights.focusScore(s, targetMinutes: target),
          'targetMin': target,
          'hourlyMin': [for (final h in s.hourly) h.round()],
          'topApps': [
            for (final a in s.apps.take(8))
              {
                'label': a.label,
                'minutes': a.foreground.inMinutes,
                'launches': a.launches,
                'notifications': a.notifications,
              },
          ],
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      final analytics = _ref.read(analyticsProvider);
      for (final n in await usage.drainNudges()) {
        await analytics.log(AppEvent.nudgeSent, {'kind': n['kind'], 'title': n['title']});
      }
    } catch (e) {
      debugPrint('Usage sync skipped: $e');
    }
  }

  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
  }
}

final usageSyncProvider = Provider<UsageSync>((ref) {
  final sync = UsageSync(ref);
  ref.onDispose(sync.dispose);
  return sync;
});
