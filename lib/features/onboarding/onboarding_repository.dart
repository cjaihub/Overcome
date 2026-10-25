import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/firebase_providers.dart';
import 'onboarding_profile.dart';

class OnboardingDraft {
  const OnboardingDraft(this.profile, this.step);
  final OnboardingProfile profile;
  final int step;
}

class OnboardingRepository {
  OnboardingRepository(this._db, this._auth);

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;
  Timer? _debounce;

  String get _uid => _auth.currentUser!.uid;
  DocumentReference<Map<String, dynamic>> get _draft => _db.doc('users/$_uid/private/onboardingDraft');

  Future<OnboardingDraft> load() async {
    final snap = await _draft.get();
    final data = snap.data();
    return OnboardingDraft(
      OnboardingProfile.fromMap(data?['profile'] as Map<String, dynamic>?),
      (data?['step'] as num?)?.toInt() ?? 0,
    );
  }

  /// Debounced autosave — every keystroke and tap is safe.
  void autosave(OnboardingProfile profile, int step) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), () {
      _draft.set({'profile': profile.toMap(), 'step': step, 'updatedAt': FieldValue.serverTimestamp()});
    });
  }

  Future<void> complete(OnboardingProfile profile) async {
    _debounce?.cancel();
    final batch = _db.batch()
      ..set(_draft, {'profile': profile.toMap(), 'step': -1, 'updatedAt': FieldValue.serverTimestamp()})
      ..set(_db.doc('users/$_uid'), {
        'profile': profile.toMap(),
        'onboardingCompletedAt': FieldValue.serverTimestamp(),
        // Default evening check-in reminder (editable in Settings).
        'settings': {
          'reminders': true,
          'reminderHour': 20,
          'reminderUtcHour': (20 - DateTime.now().timeZoneOffset.inMinutes / 60).round() % 24,
        },
      }, SetOptions(merge: true));
    await batch.commit();
    await _auth.currentUser?.updateDisplayName(profile.displayName);
  }

  /// Queues the AI plan agent (the `runPlanAgent` Firestore trigger picks it
  /// up). The agent writes each step it takes back to the run document, which
  /// the UI streams through [watchRun].
  Future<String> startPlanAgent() async {
    final ref = _db.collection('users/$_uid/agentRuns').doc();
    await ref.set({'status': 'queued', 'steps': [], 'createdAt': FieldValue.serverTimestamp()});
    return ref.id;
  }

  Stream<Map<String, dynamic>?> watchRun(String runId) =>
      _db.doc('users/$_uid/agentRuns/$runId').snapshots().map((s) => s.data());
}

final onboardingRepositoryProvider = Provider<OnboardingRepository>(
  (ref) => OnboardingRepository(ref.watch(firestoreProvider), ref.watch(firebaseAuthProvider)),
);
