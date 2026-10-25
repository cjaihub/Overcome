import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/analytics_service.dart';
import '../../core/services/firebase_providers.dart';
import 'recovery_plan.dart';

class CheckIn {
  const CheckIn({required this.formId, required this.answers, required this.at, this.mood});
  final String formId;
  final Map<String, dynamic> answers;
  final DateTime at;
  final num? mood;
}

class ProgressRepository {
  ProgressRepository(this._db, this._auth, this._analytics);

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;
  final AnalyticsService _analytics;

  String get _uid => _auth.currentUser!.uid;

  Stream<RecoveryPlan?> watchPlan() =>
      _db.doc('users/$_uid/plan/current').snapshots().map((s) => s.exists ? RecoveryPlan.fromMap(s.data()!) : null);

  Stream<List<CheckIn>> watchCheckIns({int days = 30}) => _db
      .collection('users/$_uid/checkIns')
      .where('at', isGreaterThan: Timestamp.fromDate(DateTime.now().subtract(Duration(days: days))))
      .orderBy('at')
      .snapshots()
      .map(
        (q) => [
          for (final d in q.docs)
            CheckIn(
              formId: d['formId'] as String,
              answers: Map<String, dynamic>.from(d['answers'] as Map),
              at: (d['at'] as Timestamp?)?.toDate() ?? DateTime.now(),
              mood: d.data()['mood'] as num?,
            ),
        ],
      );

  Future<void> submit(FormTemplate form, Map<String, dynamic> answers) async {
    // The first 0–10 scale is treated as the headline "how am I doing" score
    // for charts and live progress.
    final scale = form.fields.where((f) => f.type == FieldType.scale).firstOrNull;
    await _db.collection('users/$_uid/checkIns').add({
      'formId': form.id,
      'formTitle': form.title,
      'answers': answers,
      if (scale != null && answers[scale.id] is num) 'mood': answers[scale.id],
      'at': FieldValue.serverTimestamp(),
    });
    await _analytics.log(AppEvent.formSubmit, {'formId': form.id});
  }
}

final progressRepositoryProvider = Provider<ProgressRepository>(
  (ref) =>
      ProgressRepository(ref.watch(firestoreProvider), ref.watch(firebaseAuthProvider), ref.watch(analyticsProvider)),
);

final planProvider = StreamProvider<RecoveryPlan?>((ref) {
  ref.watch(authStateProvider);
  return ref.watch(progressRepositoryProvider).watchPlan();
});

final checkInsProvider = StreamProvider<List<CheckIn>>((ref) {
  ref.watch(authStateProvider);
  return ref.watch(progressRepositoryProvider).watchCheckIns();
});
