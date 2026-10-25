import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../core/services/firebase_providers.dart';

class DailyMetric {
  const DailyMetric(this.day, this.data);
  final DateTime day;
  final Map<String, dynamic> data;

  int get(String k) => (data[k] as num?)?.toInt() ?? 0;
}

class AdminUserRow {
  const AdminUserRow(this.uid, this.data);
  final String uid;
  final Map<String, dynamic> data;

  Map<String, dynamic> get stats => (data['stats'] as Map?)?.cast<String, dynamic>() ?? const {};
  Map<String, dynamic> get profile => (data['profile'] as Map?)?.cast<String, dynamic>() ?? const {};
  String get name => profile['displayName'] as String? ?? '(no name)';
  String get phone => data['phone'] as String? ?? '';
  DateTime? get lastActive => (stats['lastActiveAt'] as Timestamp?)?.toDate();
  int stat(String k) => (stats[k] as num?)?.toInt() ?? 0;
}

/// Reads the roll-ups written by the `aggregateEvent` function. Access is
/// limited to accounts with the `admin` custom claim (firestore.rules).
class AdminRepository {
  AdminRepository(this._db);
  final FirebaseFirestore _db;

  Stream<Map<String, dynamic>> watchGlobal() => _db.doc('metrics/global').snapshots().map((s) => s.data() ?? const {});

  Stream<List<DailyMetric>> watchDaily({int days = 30}) {
    final from = DateFormat('yyyyMMdd').format(DateTime.now().subtract(Duration(days: days - 1)));
    return _db
        .collection('metrics/global/daily')
        .where(FieldPath.documentId, isGreaterThanOrEqualTo: from)
        .orderBy(FieldPath.documentId)
        .snapshots()
        .map((q) => [for (final d in q.docs) DailyMetric(DateFormat('yyyyMMdd').parse(d.id), d.data())]);
  }

  Stream<List<AdminUserRow>> watchUsers({int limit = 100}) => _db
      .collection('users')
      .orderBy('stats.lastActiveAt', descending: true)
      .limit(limit)
      .snapshots()
      .map((q) => [for (final d in q.docs) AdminUserRow(d.id, d.data())]);

  Stream<AdminUserRow?> watchUser(String uid) =>
      _db.doc('users/$uid').snapshots().map((d) => d.exists ? AdminUserRow(d.id, d.data()!) : null);

  Stream<List<Map<String, dynamic>>> watchEvents(String uid, {int limit = 100}) => _db
      .collection('users/$uid/events')
      .orderBy('at', descending: true)
      .limit(limit)
      .snapshots()
      .map((q) => [for (final d in q.docs) d.data()]);

  Stream<List<Map<String, dynamic>>> watchCheckIns(String uid) => _db
      .collection('users/$uid/checkIns')
      .orderBy('at', descending: true)
      .limit(60)
      .snapshots()
      .map((q) => [for (final d in q.docs) d.data()]);
}

final adminRepositoryProvider = Provider((ref) => AdminRepository(ref.watch(firestoreProvider)));
final adminGlobalProvider = StreamProvider((ref) => ref.watch(adminRepositoryProvider).watchGlobal());
final adminDailyProvider = StreamProvider((ref) => ref.watch(adminRepositoryProvider).watchDaily());
final adminUsersProvider = StreamProvider((ref) => ref.watch(adminRepositoryProvider).watchUsers());
